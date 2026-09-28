#!/usr/bin/env bash
# Headless-гейт рэгдолла. Использование: tests/run_gate.sh ["k=60,c=6,f=6,tmax=80"]
# --fixed-fps 60: физика идёт с фиксированным шагом быстрее реального времени.
# Godot доносит до скрипта только первый аргумент после "--", поэтому параметры одной строкой.
# 1) doll_gate (9 проверок поведения); 2) feel_probe strict=1 — цели feel из docs/plan-demo/FEEL_TARGET.md §7
#    (поза покоя, пружины, оседание, тяга, отскок) валят гейт. Override мышц (аргумент) идёт только в doll_gate:
#    feel-цели откалиброваны под Tuning. Отчёты: tests/doll_gate_report.json, tests/feel_probe_report.json.
set -uo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --fixed-fps 60 res://tests/doll_gate.tscn -- "${1:-}"
gate=$?
godot --headless --path . --fixed-fps 60 res://tests/feel_probe.tscn -- "strict=1" > /dev/null
feel=$?
echo "=== run_gate: doll_gate exit $gate, feel_probe(strict) exit $feel ==="
[ "$gate" -eq 0 ] && [ "$feel" -eq 0 ]
