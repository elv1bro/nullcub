#!/bin/bash
# NULL GRAVITY — запуск ПОСЛЕДНЕЙ версии: сначала подтянуть main с GitHub, потом обычный ./play-mac.command (он сам обновит импорт Godot).
# Двойной клик или ./play-latest.command. Если слияние не получилось (конфликт) — оно отменяется, игра запускается как есть.
cd "$(dirname "$0")" || exit 1
if git fetch origin 2>/dev/null; then
	branch="$(git branch --show-current)"
	if [ "$branch" = "main" ]; then
		if git merge --ff-only origin/main >/dev/null 2>&1; then
			echo "main обновлён (fast-forward)."
		elif git merge --no-edit origin/main >/dev/null 2>&1; then
			echo "main обновлён (слияние: у тебя были свои коммиты, которых нет на GitHub)."
		else
			git merge --abort >/dev/null 2>&1
			echo "!! Не удалось слить origin/main (конфликт или незакоммиченные правки в тех же файлах). Запускаю как есть — разберись вручную: git status"
		fi
	else
		echo "Ты на ветке «$branch», не на main — не обновляю. (git switch main — и снова.)"
	fi
else
	echo "Нет связи с GitHub — запускаю то, что есть."
fi
[ -n "${NOPLAY:-}" ] && exit 0
exec ./play-mac.command
