#!/bin/bash
# Запуск Godot с окном так, чтобы он не забирал фокус (macOS). Вместо `godot …`:
#   godot/tools/godot_nofocus.sh --path godot --resolution 1280x720 res://tests/hud_snapshot.tscn -- "players=2"
# Окно рисуется как обычно (скриншоты, --write-movie, --fixed-fps работают), но приложение не активируется:
# клавиатура и передний план остаются у человека. --always-on-top и --position за экраном не нужны
# (второе троттлится macOS — FPS вдвое ниже; для perf_probe окно за экраном не использовать).
# Не macOS или нет clang — просто запускает godot как есть. Для --headless-проб обёртка не нужна.
# Переменные: GODOT_BIN (по умолчанию godot из PATH).
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/nofocus/nofocus.m"
LIB_DIR="$HERE/../.godot/nofocus"   # .godot/ в .gitignore
LIB="$LIB_DIR/libnofocus.dylib"

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
