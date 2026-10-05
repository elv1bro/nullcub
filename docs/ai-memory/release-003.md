---
name: release-003
description: "05.10 релиз 0.0.3 — 10 сессий опрошены, 2 коммита в main + 4 ветки worktree слиты, тег v0.0.3; что красное и какие решения ждут автора"
metadata:
  node_type: memory
  type: project
  originSessionId: f63d0168-56ec-4337-9d06-6ce08d10867f
  modified: 2026-10-05T07:50:25.515Z
---

05.10.2026 по просьбе автора («договорись со всеми активными диалогами, чтобы все слили ветки в main, и подготовь версию 0.0.3») разослал 10 живым сессиям просьбу закоммитить. «Суставы» (1b43adf) и «Каталог» (bd9fc75) закоммитили в main сами, ограничивая коммит путями. Ветки Руин, спорта, мастерской и сборщика пресетов (`claude/distracted-bartik-b85bfe`, `worktree-sport-modes`, `claude/magical-poincare-74d71e`, `claude/vigorous-wilson-1e8724`) я влил в отдельном worktree `release/0.0.3`, проверил и перенёс в main. Версия `config/version="0.0.3"`, тег `v0.0.3`, заметки `docs/plan-demo/RELEASE_0.0.3.md`.

**Why:** автору нужна общая точка отсчёта, как и с [[release-002]].
**How to apply:** порядок, который сработал: сначала сессии основного чекаута коммитят в main (`git commit -- <пути>`, см. [[shared-checkout-commits]]), worktree-сессии коммитят в СВОЮ ветку и не трогают main; потом один интегратор сливает ветки в отдельном worktree, гоняет пробы и передвигает main через `--ff-only`. Красная на 0.0.3 только `scrap_machines_probe` (магнит, с 0.0.1). Нестабильны под параллельной нагрузкой `hitfx_core_probe` (freq_normal_flight) и `workshop_probe` (pattern_frame_budget): повтор по одной — зелёные. `menu_probe` больше не привязана к номеру версии. Открытые решения автора: PART_BREAK против суставов C, числа брони и бюджет, спорт (весело ли, футбол быстрый, баскетбол долгий), коммитить ли `docs/catalog/` (24 МБ). Ничья неотслеживаемая папка `docs/plan-demo/narrative-proposal/` в основном чекауте: ни одна сессия не признала её своей. Связано: [[joint-break-mode]], [[kit-sets-0410]], [[sport-modes]].
