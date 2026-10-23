#!/bin/bash
# Оконная проба Godot НЕВИДИМО и без кражи фокуса (macOS), по образцу проекта fgame (tools/godot_bg). Вместо `godot …`:
#   godot/tools/godot_bg.sh --path godot --resolution 1600x900 --fixed-fps 60 res://tests/hud_snapshot.tscn -- "players=2"
# Что происходит: окно — 1×1 прозрачный пиксель за краем экрана, без фокуса и без мыши; сцена пробы рисуется во внутренний
# SubViewport размера --resolution (по умолчанию 1920×1080), снимки через get_viewport().get_texture() работают как обычно.
# Приложение не попадает в Dock и не активируется (tools/nofocus/nofocus.m), звук выключен. Код выхода и вывод — как у godot.
# Проект-обёртка (ссылки на всё из godot/ + override.cfg с главной сценой bgrun) — в ~/Library/Caches/null-gravity-bg/.
# Не годится для проб, которые меняют сцену (change_scene_*) или трогают get_tree().current_scene / размер окна.
# Headless-пробам обёртка не нужна. Не macOS — просто godot как есть. Переменные: GODOT_BIN (по умолчанию godot из PATH).
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/nofocus/nofocus.m"
LIB_DIR="$HERE/../.godot/nofocus"   # .godot/ в .gitignore
LIB="$LIB_DIR/libnofocus.dylib"

project=""
scene=""
size=""
pre=()
post=()
while (($#)); do
	case "$1" in
		--path) project="$2"; shift 2 ;;
		--resolution) size="$2"; shift 2 ;;
		--) shift; post=("$@"); break ;;
		res://*.tscn|res://*.scn) scene="$1"; shift ;;
		*) pre+=("$1"); shift ;;
	esac
done
[[ -n "$project" ]] || project="$(cd "$HERE/.." && pwd)"
project="$(cd "$project" && pwd)"
[[ -n "$scene" ]] || { echo "godot_bg: укажи сцену res://….tscn" >&2; exit 2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
	exec "$GODOT_BIN" --path "$project" ${size:+--resolution "$size"} "${pre[@]+"${pre[@]}"}" "$scene" -- "${post[@]+"${post[@]}"}"
fi

if [[ ! -f "$LIB" || "$SRC" -nt "$LIB" ]]; then
	mkdir -p "$LIB_DIR"
	clang -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -fobjc-arc -framework AppKit -o "$LIB" "$SRC"
fi

# Проект-обёртка: те же файлы (ссылками), но главная сцена — bgrun, окно 1×1 прозрачное. Своя на каждый чекаут.
key="$(printf '%s' "$project" | md5 -q)"
RP="$HOME/Library/Caches/null-gravity-bg/rp-$key"
mkdir -p "$RP"
for entry in "$project"/* "$project"/.godot; do
	name="$(basename "$entry")"
	[[ "$name" == "override.cfg" ]] && continue
	[[ -L "$RP/$name" || -e "$RP/$name" ]] || ln -s "$entry" "$RP/$name"
done
for link in "$RP"/* "$RP"/.godot; do
	[[ -L "$link" && ! -e "$link" ]] && rm -f "$link"   # файл удалён из проекта
done
cat > "$RP/override.cfg" <<'CFG'
[application]
run/main_scene="res://tools/godot_bg/bgrun.tscn"
[display]
window/size/window_width_override=1
window/size/window_height_override=1
window/size/borderless=true
window/size/transparent=true
window/size/no_focus=true
window/per_pixel_transparency/allowed=true
[rendering]
viewport/transparent_background=true
CFG

user=("--scene=$scene")
[[ -n "$size" ]] && user+=("--size=$size")
# arch — бинарь под SIP: DYLD_* он вырезает, поэтому передаём через `arch -e`; -arm64 — нативный запуск без Rosetta.
exec /usr/bin/arch -arm64 -e "DYLD_INSERT_LIBRARIES=$LIB" "$(command -v "$GODOT_BIN")" --audio-driver Dummy --path "$RP" \
	"${pre[@]+"${pre[@]}"}" -- "${user[@]}" "${post[@]+"${post[@]}"}"
