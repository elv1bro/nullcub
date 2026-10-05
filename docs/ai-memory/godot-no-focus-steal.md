---
name: godot-no-focus-steal
description: "Оконные пробы Godot на macOS не должны красть фокус: запуск через godot/tools/godot_nofocus.sh (DYLD-вставка), что НЕ работает"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 3a354f6a-291d-4e05-ae92-a7f57233623d
  modified: 2026-10-02T12:59:51.091Z
---

Оконные пробы Godot (снимки, клипы, perf — всё без `--headless`) запускать через `godot/tools/godot_nofocus.sh`, не голым `godot` и не с `--always-on-top`.

**Why:** 02.10 автор спросил, можно ли гонять тесты без перехвата фокуса. Обычный запуск делает Godot frontmost-приложением (~15% кадров пробы) и забирает клавиатуру, пока человек работает.

**How to apply:** обёртка подставляет `DYLD_INSERT_LIBRARIES=godot/.godot/nofocus/libnofocus.dylib` (исходник `godot/tools/nofocus/nofocus.m`, собирается сама при первом вызове) и глушит `activateIgnoringOtherApps:`/`activate`/`activateWithOptions:`, а политику ставит accessory. Замер по pid frontmost (`lsappinfo info -only pid $(lsappinfo front)`): 0 из 100–300 замеров, exit 0 на hud_snapshot, hitfx_snapshot (`--fixed-fps 60`), perf_probe.

Что НЕ работает (проверено на Godot 4.7.2, всё равно frontmost): `--position -4000,-4000`; `display/window/size/no_focus=true` (override.cfg); `open -g -j`. Перепаковка Godot.app с `LSUIElement` + `codesign --force` — не делать: бинарь падает SIGKILL, macOS показывает системные диалоги (CoreServicesUIAgent). `DYLD_*` вырезается системным `arch`, поэтому только через `arch -arm64 -e DYLD_INSERT_LIBRARIES=…`. Окно за экраном (`--position`) троттлится — FPS вдвое ниже, для perf_probe не использовать. При замере фокуса учитывай чужие окна: другие сессии тоже гоняют `godot`, различать по pid, не по имени.

Related: [[godot-test-workflow]]
