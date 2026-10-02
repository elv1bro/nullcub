#!/bin/bash
# Ragdoll Master — тестовая сборка 0.0.1: запуск на Mac из исходников (docs/plan-demo/RELEASE_0.0.1.md).
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
if [ ! -d godot/.godot/imported ]; then
	echo "Первый запуск: Godot импортирует модели и текстуры — это несколько минут, окно игры откроется само."
	"$GODOT_BIN" --headless --path godot --import
fi
exec "$GODOT_BIN" --path godot
