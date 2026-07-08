# 1 — Стабилизация: критические баги

Цель: убрать всё, что молча ломает бой. Без этого любые новые фичи строятся на песке.
Оценка: 3–5 дней.

## 1.1 Критические баги (найдены аудитом 08.07.2026)

- [x] **Инвертированный урон бота.** `src/core/combatPipeline.ts` ~82: `BOT_DAMAGE_MULTIPLIER`
  применяется к боту, а не к игроку (в `useHealth` — наоборот). Итог: в core-симуляции
  игрок получает обычный урон, бот ×1.4. Починить направление и покрыть тестом
  «бот наносит игроку × multiplier».

- [x] **`Events.off` сносит чужие обработчики.** `src/core/battleSession.ts` ~351:
  `Events.off(engine, "collisionStart")` без ссылки на handler снимает ВСЕ обработчики
  с общего движка. После рематча могут отвалиться захваты/урон. Хранить ссылку на
  handler и снимать только её. Тест: 3 рематча подряд, урон продолжает работать.

- [x] **Двойной нокаут = бой без конца.** `battleSession.resolveWinner()` возвращает
  `null`, `BattleRecapOverlay` требует победителя → нет оверлея. Добавить: tie-break
  (больше оставшегося HP → победа; равно → «Ничья») и экран ничьей.
  То же в `src/lib/useHealth.ts` ~212 (сейчас при одновременном нуле всегда
  побеждает оппонент) и `useVictoryDefeatFx.ts` ~36 (разлёт ragdoll при null winner).

- [x] **4FFA компиляция** — ~~нет импорта `OPPONENT_COLORS`/`PLAYER_COLORS`~~
  ✅ исправлено 08.07.2026.

- [x] **Grab-иммунитет не работает в core.** `battleSession.ts` ~184:
  `grabCtx.opponentGrab` захардкожен `null` → удержанный игрок продолжает получать
  «мега-хиты». Прокинуть реальный grab-state оппонента. Аналогично `useHealth.ts` ~530.

## 1.2 Технический долг, который аукнется на релизе

- [x] **`npx tsc --noEmit` должен проходить чисто** (сейчас ~50 ошибок в `src/`,
  Vite их игнорирует). Включить type-check в CI/пре-коммит. Ошибки уровня
  «неиспользуемые импорты» и `exactOptionalPropertyTypes` — вычистить.
- [x] **Версионирование localStorage.** `loadVersioned`/`saveVersioned` для:
  campaign progress, achievements, blueprints, settings (`ragdoll-riot-settings`),
  profile (`ragdoll-faces-profile`). Легаси JSON без обёртки мигрирует как `fromVersion=0`.
- [x] **Утечка `victimHitTrackers`.** `src/lib/grab/useGrabSystem.ts` ~55 — map живёт
  на уровне модуля; чистить при старте боя.
- [x] Удалить мёртвый код: `WorkshopStatControls.tsx`, `PlayScopeMenu.tsx`,
  `CampaignStub.tsx`, `GameTypeMenu.tsx`, `TeamLobbyPanel.tsx`, `MenuPreviewArena.tsx`.

## 1.3 Мелкие баги мастерской

- [x] `deletePartAt` пишет `maxHp` в мету оружия/арены (`Workshop.tsx` ~363) —
  гейтить `workshopKind === "monster"`.
- [x] Кнопка «Библиотека» ничего не делает при пустой библиотеке — показывать
  попап с `libraryEmpty`.
- [x] `blockLabels.ts` — все размеры core показываются как «Ядро M».
- [x] Статусбар мастерской: «part/parts» захардкожен на английском.
- [x] Стартовые монстры удаляются без подтверждения — добавить confirm или защиту.

## Критерий готовности этапа

- 3 рематча подряд: урон, захваты, звуки — всё работает.
- Двойной KO показывает «Ничья».
- `npm run build && npx tsc --noEmit && npm test` — зелёные.
- Ручной чек-лист из `9-marketing-launch.md` §QA проходит без блокеров.
