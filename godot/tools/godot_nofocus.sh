#!/bin/bash
# Оконная проба Godot без кражи фокуса (macOS). Вместо `godot …`:
#   godot/tools/godot_nofocus.sh --path godot --resolution 1280x720 res://tests/hud_snapshot.tscn -- "players=2"
# По умолчанию — НЕВИДИМО, через godot_bg.sh (окно 1×1 за экраном, кадр во внутреннем SubViewport, без Dock и фокуса;
# по образцу проекта fgame). NOFOCUS_VISIBLE=1 — прежний режим: окно на экране, но приложение не активируется
# (для perf-замеров и проб, которые меняют сцену или трогают размер окна — им SubViewport не подходит).
# Не macOS или нет clang — просто запускает godot как есть. Для --headless-проб обёртка не нужна.
# Переменные: GODOT_BIN (по умолчанию godot из PATH).
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${NOFOCUS_VISIBLE:-0}" != "1" ]]; then
	exec "$HERE/godot_bg.sh" "$@"
fi

SRC="$HERE/nofocus/nofocus_visible.m"
LIB_DIR="$HERE/../.godot/nofocus"   # .godot/ в .gitignore
LIB="$LIB_DIR/libnofocus_visible.dylib"

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v clang >/dev/null 2>&1; then
	exec "$GODOT_BIN" "$@"
fi

if [[ ! -f "$LIB" || "$SRC" -nt "$LIB" ]]; then
	mkdir -p "$LIB_DIR"
	clang -arch arm64 -arch x86_64 -dynamiclib -framework AppKit -o "$LIB" "$SRC"
fi

# arch — бинарь под SIP: переменные DYLD_* он вырезает, поэтому передаём их через `arch -e`,
# чтобы они дошли до самого Godot. arch -arm64 нужен и для нативного запуска (без Rosetta).
exec /usr/bin/arch -arm64 -e "DYLD_INSERT_LIBRARIES=$LIB" "$(command -v "$GODOT_BIN")" "$@"
