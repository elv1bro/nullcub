#!/usr/bin/env bash
# Headless-гейт звука (docs/plan-demo/AUDIO.md §6). Использование: tests/run_audio_gate.sh
# 1) sfx_probe — удары по материалам, крит, KO, объявления, лимиты голосов; 2) audio_probe × 4 арены — шины, фон и реверберация
#    арены, музыка и её выключатель, толпа (удары, KO, крит, скука), ветер полёта, рывок/переворот, стук ящиков по материалу,
#    тишина в покое, бой ботов (стук ≤ 16/с, голосов ≤ 24, толпа заводится). Отчёты tests/sfx_probe_report.json,
#    tests/audio_probe_<арена>_report.json.
# Запуск из-под x86-обёртки: gtimeout 1800 /usr/bin/arch -arm64 /bin/bash godot/tests/run_audio_gate.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
run() { godot --headless --path . --fixed-fps 60 "res://tests/$1" -- "${2:-}" > /dev/null 2>&1; local rc=$?; echo "  $1 ${2:-} exit $rc"; [ $rc -eq 0 ] || fail=1; }
run sfx_probe.tscn "fight_s=20"
for a in scrap void ruins workshop; do
	run audio_probe.tscn "scene=$a,fight_s=15,out=res://tests/audio_probe_${a}_report.json"
done
echo "=== run_audio_gate: $([ $fail -eq 0 ] && echo OK || echo FAIL) ==="
exit $fail
