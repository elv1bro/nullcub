---
name: project-essence
description: "Что такое Ragdoll Faces / «Yobbo Yobbo» — жанр, стек, состояние, ключевые риски (аудит 18.09.2026)"
metadata: 
  node_type: memory
  type: project
  originSessionId: e01d6aa4-0c2f-4ed8-9133-35a39f9ccd48
  modified: 2026-09-20T16:54:46.360Z
---

Ragdoll Faces (в UI «Yobbo Yobbo», ключ настроек «ragdoll-riot») — физический рэгдолл-файтинг «для компании», форк onedoes/ragdollmasters, перелицензирован в проприетарный. Автор E1viBro, один разработчик с ИИ-ассистентом.

**Стек (as-built, не то, что в docs/ARCHITECTURE.md):** TypeScript strictest, React 18, Vite 5, Matter.js 0.20 через самописный matter4react (`@1/framework`), XState 4 для экранов, UnoCSS, MediaPipe Face Landmarker (лицо с вебки на голове рэгдолла — главная фишка), Supabase (обязательный логин на web + синк прогресса), собственный WS-сервер на Node для онлайн-дуэлей (P2P trystero и 4FFA выключены флагами), Electron только как dev-лаунчер. Yarn 4, Node 20 x64 под Rosetta.

**Режимы:** vs бот, локальные 2P, кампания «Вышибала» (6 глав), рогалик с драфтом способностей (половина способностей заглушки), мастерская монстров/оружия/арен (монстры доходят до боя, оружие и арены нет), онлайн-дуэль по коду (только при VITE_WS_URL).

**Ядро:** `src/core/battleSession.ts` — headless детерминированная симуляция, гоняется в vitest, на сервере и в браузере. Контур проверки для ИИ описан в `AGENTS.md` (yarn test, eval:behavior, smoke:duel, verify:browser).

**Стратегия (docs/plan/0-9):** бесплатный веб → вирус → wishlist → Steam, цель 1000 DAU.

**Состояние на 18.09.2026:** 208 незакоммиченных файлов (~32k строк), git remote не настроен, история 7 сплющенных коммитов от 08.07.2026. CI только build. 2 падающих теста (snapshot.test устарел после solid-оружия; duelStability 34.9 урона против порога 50 — баланс). 102 ошибки tsc в `src/ad/adProbeScene.ts`. Три пути урона (core, legacy useHealth, useRosterHealth). God-файлы LeveL1.tsx 1452, Workshop.tsx 1176. Полный отчёт: `docs/AUDIT_2026-09-18.md`.

**Why:** Сессия началась с полного аудита; факты выше не выводятся из кода быстро и нужны для любого следующего разговора.
**How to apply:** Начинать с docs/AUDIT_2026-09-18.md и AGENTS.md; не доверять docs/ARCHITECTURE.md §1-4 (целевая, не as-built). Первый шаг любой работы — remote + коммиты. См. [[engine-switch-decision]].
