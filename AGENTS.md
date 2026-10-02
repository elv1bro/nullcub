# AGENTS.md — как ИИ проверяет Ragdoll Faces

Цель: агент должен **сам** понять, что игра ок или сломана, без «посмотри глазами».

> **Новая сессия (в том числе в облаке): сначала прочти `docs/ai-memory/README.md`** — снимок памяти прошлых сессий (30.09.2026). Там описано, что сейчас за игра, что сделано и что не закончено. Текущая игра — Godot-демо в `godot/` (гейты: `godot/README.md`, `docs/plan-demo/`). Всё ниже относится к веб-части на TypeScript.

> **Godot с окном — только без кражи фокуса (macOS):** любую оконную пробу (снимки, клипы, перф: всё, что не `--headless`) запускай через `godot/tools/godot_nofocus.sh` вместо `godot`, без `--always-on-top`. Человек в это время работает за компьютером; обычный `godot` с окном отбирает у него клавиатуру и передний план. Headless-пробы и веб-часть (Puppeteer `headless: true`) фокус и так не трогают.

## Правила для всех агентов

**Как писать баги и hotfix** (в чат, в отчёт агента, в `docs/plan-demo/HOTFIX_*.md`). Одна запись = один дефект, только то, что проверено; непроверенное помечай словом «не проверено». Обязательные поля:
1. **Название** и приоритет: P1 — ломает игру или тест-гейт, P2 — заметный дефект, P3 — мелочь.
2. **Шаги** — по пунктам, с точной командой (проба, аргументы) или кликами/клавишами; сборка (коммит) и язык игры.
3. **Ожидается** — конкретно (число, текст, поведение), со ссылкой на пробу, спеку или док.
4. **Получается** — фактический вывод пробы / число / скриншот, не пересказ.
5. **Где искать** — файл:строка или модуль, если известно; причину пиши отдельно от факта.
Красная проба — это дефект или ошибка в самой пробе: проверь на чистом main (отдельный worktree) и запиши, «красная и до моих правок», не списывай молча.

**Название игры — NULL GRAVITY** (`docs/plan-demo/BRAND.md`). «Ragdoll Master(s)» — название чужой игры: в интерфейсе, заголовке окна, подписях, названиях файлов сборки и текстах для публики не использовать (в комментариях кода как референс можно). Знак игры — дрон N0 (`godot/assets/ui/brand/`).

**Язык игры (мультиязычность).** Любой текст, который видит игрок, — через `tr("…")` (в `static func` — `TranslationServer.translate("…")`), ключ — строка из кода, английский перевод — в `godot/locale/en.json`. В `const` перевод вызывается в месте использования; логику на тексте не строить (только коды); склейки — форматом. После правок текста: `python3 godot/tools/i18n.py check` и `godot --headless --path godot res://tests/i18n_probe.tscn` + `i18n_scenes_probe.tscn` + `i18n_layout_probe.tscn` (вёрстка на всех языках против русского эталона; языков будет 10+, глазами каждый не проверить). Новый экран с текстом — добавить в `_pass()` пробы вёрстки. Подробно и глоссарий — `docs/plan-demo/I18N.md`.

## Быстрый контур (каждый патч)

```bash
yarn test                 # unit + headless duel/server (~секунды)
yarn eval:behavior        # JSON-метрики управления/idle/монстров/pace → test-artifacts/behavior-report.json
yarn test:feel            # те же feel-кейсы через vitest
yarn smoke:duel           # живой WS 12s: guest не умирает на спавне
yarn verify:browser:fast  # Puppeteer: меню + quick + workshop + workshopFight
yarn verify:feel          # eval:behavior + verify:browser:fast
```

Полный контур перед merge:

```bash
yarn verify:game          # test + smoke:duel + verify:browser
```

Exit code ≠ 0 → **не ок**. Не спрашивай пользователя «вроде работает?» — чини или откатывай.

### Поведение / управление (после патча move/stickman/workshop links)

```bash
yarn eval:behavior
```

Читай `test-artifacts/behavior-report.json`: `ok` + список `checks[]` с `value` / `limit`.  
Не спрашивай «норм ли управление?» — смотри отчёт.

| Симптом | check id |
|---------|----------|
| Уползает вбок без ввода | `idle_symmetry_com` |
| Не падает в idle | `idle_falls` |
| Влево/вправо разное | `move_lr_balance`, `move_left`, `move_right` |
| Вверх/вниз не едет | `move_up`, `move_down` |
| Монстр разваливается | `workshop_integrity` |
| Бой слишком короткий/длинный | `combat_pace_median_*` |

## Что уже даёт сигнал «ок / не ок»

| Сигнал | Где | Что ловит |
|--------|-----|-----------|
| Vitest core | `src/core/*.test.ts` | HP, timeout, destroy shared engine, abilities |
| Vitest combat | `src/lib/combat*.test.ts` | формула урона, knockback, grab rules |
| Vitest server | `src/server/*.test.ts` | ready→start, input clamp, e2e WS duel |
| Behavior eval | `yarn eval:behavior` | idle-симметрия, WASD, starters, pace → JSON |
| Feel QC | `yarn test:feel` | те же кейсы через vitest |
| Headless AI | `yarn benchmark:ai` | баланс ботов (регрессии winrate) |
| Duel smoke | `scripts/duel-smoke.mjs` | spawn grace, HP guest, server build id |
| Browser verify | `scripts/verify-app.mjs` | меню, quick, workshop, workshopFight |
| Screenshots | `yarn verify:screenshots` | визуальный diff артефактов в `test-artifacts/` |

## E2E harness в браузере

`src/dev/e2eHarness.ts` + query `?e2e=menu|quick|workshop|workshopFight`:

- страница пишет `window.__RAGDOLL_E2E__` с `phase` / `ok` / `fail`
- `verify-app.mjs` читает это через Puppeteer
- `workshopFight`: мастерская → Fight → бой стартовал с живым HP

Новый UI-сценарий = новый `e2eMatches(...)` + assert в `verify-app.mjs`.

## Headless бой (главный инструмент агента)

Симуляция **без DOM**:

```ts
const session = createBattleSession({ ... });
session.beginBattle();
for (let i = 0; i < 600; i++) session.tick(1000/60);
expect(session.isBattleOver()).toBe(true);
```

Правило: баг в бою → сначала тест на `BattleSession` / `combatPipeline` / `GameRoom`, потом UI.

## Как агенту «видеть» игру

1. **Не полагайся на скриншот как единственный verdict** — используй числовые инварианты (HP, winner, body count, no throw).
2. **Скриншоты** — для регрессий UI: сравни с `test-artifacts/battle-screenshots/` после `verify:screenshots`.
3. **Browser MCP / Puppeteer** — для кликов по меню; успех = e2e harness `ok`, не «картинка красивая».
4. **Логи сервера** — `RAGDOLL_DEBUG=1` → `http://127.0.0.1:8788/debug` (комнаты, HP, events).

## Инварианты, которые нельзя ломать

- Shared Matter engine: `destroy()` **не** вызывает `Engine.clear` если engine внешний.
- Ability flags: one-shot (consume после чтения) в local и dedicated.
- Dedicated snapshots: **ordered** codec, не body.id.
- WS: join требует явный roomId + 16-hex `secret` из duel code; bind по умолчанию `127.0.0.1`.
- `GRAB_ENABLED=false` пока core grab parity не покрыта тестами.
- P2P / 4FFA выключены по умолчанию (`VITE_ENABLE_P2P` / `VITE_ENABLE_LOCAL_FFA`); онлайн = WS.
- В LeveL1 `coreSim=true` → `useHealth` только FX (`skipCollisions`), урон только в `core/`.

## Добавляя фичу

1. Тест рядом с кодом (`*.test.ts`).
2. Если сеть — кейс в `e2eDuel.test.ts` или `duel-smoke`.
3. Если меню/роут — ветка в e2e harness + `verify-app`.
4. Не расширяй legacy `useHealth` collision path для новых правил — только `core/`.
