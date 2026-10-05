#!/bin/bash
# NULL GRAVITY — тестовая сборка 0.0.3: запуск на Mac из исходников (docs/plan-demo/RELEASE_0.0.3.md).
# Нужен Godot 4.7.2 (godotengine.org → Download → macOS). Двойной клик по этому файлу или ./play-mac.command в терминале.
# Свой путь к Godot: GODOT=/путь/к/Godot ./play-mac.command
cd "$(dirname "$0")" || exit 1
for c in "${GODOT:-}" /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		/Applications/Godot_mono.app/Contents/MacOS/Godot "$(command -v godot 2>/dev/null)"; do
	if [ -n "$c" ] && [ -x "$c" ]; then GODOT_BIN="$c"; break; fi
done
if [ -z "${GODOT_BIN:-}" ]; then
	echo "Godot 4.7.2 не найден. Скачай его с https://godotengine.org/download/macos/ и положи Godot.app в «Программы»."
	read -r -p "Enter — закрыть"; exit 1
fi
echo "Godot: $GODOT_BIN ($("$GODOT_BIN" --version 2>/dev/null))"
# Импорт — при первом запуске и каждый раз, когда поменялся код (git pull): новые скрипты с class_name попадают в кэш классов
# Godot только при импорте, без него свежая версия не запускается («… not declared in the current scope»).
STAMP=godot/.godot/last_import_head
HEAD_NOW="$(git rev-parse HEAD 2>/dev/null || echo none)"
if [ ! -d godot/.godot/imported ]; then
	echo "Первый запуск: Godot импортирует модели и текстуры — это несколько минут, окно игры откроется само."
	"$GODOT_BIN" --headless --path godot --import && echo "$HEAD_NOW" > "$STAMP"
elif [ "$(cat "$STAMP" 2>/dev/null)" != "$HEAD_NOW" ]; then
	echo "Код обновился — Godot обновляет импорт (обычно меньше минуты)."
	"$GODOT_BIN" --headless --path godot --import && echo "$HEAD_NOW" > "$STAMP"
fi
exec "$GODOT_BIN" --path godot
