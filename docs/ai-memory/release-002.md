---
name: release-002
description: 03.10 релиз 0.0.2 — все сессии собраны, main запушен с тегом v0.0.2; что красное и какие решения ждут автора
metadata:
  type: project
---

03.10.2026 по просьбе автора («собери все диалоги, чтобы закончили работу, слей в origin main, ставим v0.0.2») разослал 8 сессиям просьбу влить работу; все ответили, что вливать нечего — всё уже в main. Версия `config/version="0.0.2"`, тег `v0.0.2`, `origin/main` = 9639a6f. Заметки: `docs/plan-demo/RELEASE_0.0.2.md`.

Название игры — **NULL GRAVITY**, знак — N0 ([[i18n-languages]], `docs/plan-demo/BRAND.md`); «Ragdoll Master(s)» чужое, не использовать.

**Why:** автор хочет одну общую точку отсчёта перед следующим этапом.
**How to apply:** красные пробы на 0.0.2 — только `scrap_machines_probe` (магнит, красный и в 0.0.1) и `control_feel_probe responds_rotate`; `fx_probe` оконная. Открытые решения автора: скин HUD, OFL-шрифт с кириллицей, ДРАЙВ по умолчанию, замедление на 0, микс звука; проверить занятость названия NULL GRAVITY. Хотфикс-список — `docs/plan-demo/HOTFIX_2026-10-02.md`. Устаревшие worktree (audio-rework, combat-juice*, perf-pass-3, release-0.0.1 и др.) целиком в main и их можно удалить; ветку claude/combat-juice не вливать (заменена v2).
