---
name: godot-no-focus-steal
description: "Оконные пробы Godot на macOS не должны красть фокус: невидимо через godot/tools/godot_bg.sh (1×1 окно + SubViewport, как fgame), что НЕ работает"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 3a354f6a-291d-4e05-ae92-a7f57233623d
  modified: 2026-10-23T12:00:00.000Z
---

Оконные пробы Godot (снимки, клипы — всё без `--headless`) запускать **невидимо** через `godot/tools/godot_bg.sh` (или `godot_nofocus.sh`, он теперь вызывает его же), не голым `godot` и не с `--always-on-top`. Пример: `GODOT_BIN=/usr/local/bin/godot godot/tools/godot_bg.sh --path godot --resolution 1600x900 --fixed-fps 60 res://tests/null_hall_snapshot.tscn -- args`.

**Why:** 02.10 автор попросил гонять тесты без перехвата фокуса; 23.10 — «все тесты запускай в фоне без потери фокуса как проект на fgame». Прежний вариант (видимое окно + accessory) всё равно мелькал окном.

**How to apply:** godot_bg.sh (порт fgame/tools/godot_bg) делает проект-обёртку в `~/Library/Caches/null-gravity-bg/rp-<md5>` (ссылки на всё из godot/ + override.cfg: главная сцена `res://tools/godot_bg/bgrun.tscn`, окно 1×1 прозрачное no_focus), bgrun.gd ставит окно в (-20000,-20000), unfocusable, mouse_passthrough и рисует сцену пробы в SubViewport размера `--resolution` (снимки через get_viewport().get_texture() работают; если окно «невидимо» — force_draw). nofocus.m (DYLD через `arch -arm64 -e`): политика Prohibited, глушит activate*, makeKeyWindow, TransformProcessType; звук Dummy. Проверено 23.10: doll_snapshot и null_hall_snapshot rc=0, Godot ни разу не frontmost. Не годится для проб с change_scene/current_scene/размером окна и для perf — им `NOFOCUS_VISIBLE=1 godot/tools/godot_nofocus.sh` (старый видимый режим, nofocus_visible.m).

Что НЕ работает (Godot 4.7.2): `--position -4000,-4000`; только `no_focus=true` в override.cfg; `open -g -j`; перепаковка Godot.app с LSUIElement + codesign (SIGKILL). `DYLD_*` системный `arch` вырезает — только `arch -arm64 -e`. Чужие окна других сессий различать по pid.

Related: [[godot-test-workflow]]
