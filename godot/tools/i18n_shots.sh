#!/bin/bash
# Снимки главных экранов на выбранном языке — глазами проверить вёрстку (docs/plan-demo/I18N.md, «Проверка вёрстки»).
#   godot/tools/i18n_shots.sh <код языка | qps> [папка]        qps — «растянутый» псевдоязык (+35 % длины), жёсткий стресс-тест
# Что снимает: гараж (титул, История, Настройки, Трофеи), кампания в эфире ТВ (лестница, исход, мастерская), мастерская внутри гаража,
# HUD боя (панели, баннеры, итоги). Окно без кражи фокуса (godot_nofocus.sh); результат — папка с png, путь печатается в конце.
set -euo pipefail
LANG_CODE="${1:?usage: i18n_shots.sh <код языка|qps> [папка]}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
OUT="${2:-${TMPDIR:-/tmp}/ragdoll-i18n-shots/$LANG_CODE}"
mkdir -p "$OUT"
export GODOT_BIN="${GODOT_BIN:-godot}"
RUN=("$HERE/godot_nofocus.sh" --path "$PROJ" --resolution 1920x1080 --fixed-fps 60)
"${RUN[@]}" res://tests/garage_menu_shots.tscn -- "out=$OUT" "lang=$LANG_CODE" shots=title,story,quick,workshop,settings_screen,trophies_screen > /dev/null
"${RUN[@]}" res://tests/garage_campaign_shots.tscn -- "out=$OUT" "lang=$LANG_CODE" > /dev/null
"${RUN[@]}" res://tests/garage_workshop_shots.tscn -- "out=$OUT" "lang=$LANG_CODE" > /dev/null
"${RUN[@]}" res://tests/hud_snapshot.tscn -- "players=2,out=$OUT/,lang=$LANG_CODE" > /dev/null
echo "$OUT"
ls "$OUT"
