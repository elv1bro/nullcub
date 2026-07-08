# AGENTS.md — как ИИ проверяет Ragdoll Faces

Цель: агент должен **сам** понять, что игра ок или сломана, без «посмотри глазами».

## Быстрый контур (каждый патч)

```bash
yarn test                 # unit + headless duel/server (~секунды)
yarn smoke:duel           # живой WS 12s: guest не умирает на спавне
yarn verify:browser:fast  # Puppeteer: меню + quick battle без полного duel
```

Полный контур перед merge:

```bash
yarn verify:game          # test + smoke:duel + verify:browser
```

Exit code ≠ 0 → **не ок**. Не спрашивай пользователя «вроде работает?» — чини или откатывай.

## Что уже даёт сигнал «ок / не ок»

| Сигнал | Где | Что ловит |
|--------|-----|-----------|
| Vitest core | `src/core/*.test.ts` | HP, timeout, destroy shared engine, abilities |
| Vitest combat | `src/lib/combat*.test.ts` | формула урона, knockback, grab rules |
| Vitest server | `src/server/*.test.ts` | ready→start, input clamp, e2e WS duel |
| Headless AI | `yarn benchmark:ai` | баланс ботов (регрессии winrate) |
| Duel smoke | `scripts/duel-smoke.mjs` | spawn grace, HP guest, server build id |
| Browser verify | `scripts/verify-app.mjs` | загрузка, меню, quick battle, e2e harness |
| Screenshots | `yarn verify:screenshots` | визуальный diff артефактов в `test-artifacts/` |

## E2E harness в браузере

`src/dev/e2eHarness.ts` + query `?e2e=menu|quick|workshop`:

- страница пишет `window.__RAGDOLL_E2E__` с `phase` / `ok` / `fail`
- `verify-app.mjs` читает это через Puppeteer

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
- WS: join требует явный roomId; bind по умолчанию `127.0.0.1`.
- `GRAB_ENABLED=false` пока core grab parity не покрыта тестами.

## Добавляя фичу

1. Тест рядом с кодом (`*.test.ts`).
2. Если сеть — кейс в `e2eDuel.test.ts` или `duel-smoke`.
3. Если меню/роут — ветка в e2e harness + `verify-app`.
4. Не расширяй legacy `useHealth` collision path для новых правил — только `core/`.
