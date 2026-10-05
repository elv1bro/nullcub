---
name: training-hall-and-loader
description: 02.10 тренировочный зал за воротами мастерской (груша, экраны, энергосетка) и лоадер Loading на все загрузки; как устроено, что менять осторожно
metadata:
  type: project
---

02.10 автор (по референс-листу «training arena»): за дверьми мастерской в гараже — большой зал, при «Испытать» ворота открываются, можно вылететь и подраться с манекеном; HUD — экраны на стенах + энергосетка по краям; груша с экраном силы удара и скорости; все загрузки под лоадером. Сделано в ветке claude/training-hall (в main — после мержа; пуш — только по просьбе автора).

Как: ворота в левой стене гаража (`Fighter_Gate`×0.58, `garage_hall_gate.gd`, строит `tools/build_garage_menu.gd`), зал `scenes/arena/training_hall.tscn` (builder `tools/build_training_hall.tscn` — **сценой**, не `-s`: скриптам нужны autoload), кит Old NULL Hall + новые модули в `tools/blender/arena_null_hall.py` (Heavy_Bag, Chain_Link, Tire_Column, Hang_Beam), `HeavyBag` (шар на «цепи»-пружине, замер удара), `HallScreen` ×3 (скорость / сила удара / манекен), `energy_grid.gdshader`, связка — `GarageWorkshop.prepare_hall/_enter_test/_leave_test`. Лоадер: autoload `Loading` (`scripts/menu/loading.gd`), главная сцена `scenes/boot.tscn`; `Loading.hold/release/load_async/change_scene`. Пробы: `garage_workshop_probe` (43), `loading_probe`.

**Why:** 2.5D бой жёстко в плоскости z = 0 (`ArmAssist.mouse_on_plane`) — поэтому проём ворот на левой стене в этой плоскости, а не ворота на задней стене. Груша не хватается (`meta no_grab` → `ArmAssist.can_grab`).

**How to apply:** Loading — асинхронный: пробы, ждущие смены сцены, должны ждать `Loading.showing == false` (flow/menu/scene_switch_probe уже так). Любой видимый игроку текст — через `tr()` + `locale/en.json` (правило AGENTS.md, `python3 godot/tools/i18n.py check`). См. [[workshop-in-garage]], [[campaign-in-tv]].
