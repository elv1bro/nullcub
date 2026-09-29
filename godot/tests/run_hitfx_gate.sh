#!/usr/bin/env bash
# Headless-гейт эффектов ударов (docs/plan-demo/HIT_FX.md §5, интеграция 29.09). Использование: tests/run_hitfx_gate.sh
# 1) hit_tier_probe — правило уровней (синтетика); 2) hitfx_core_probe — потолок массы, время/камера, крит-отлёт, стена и частота
#    крита у ботов (3 площадки × 2 сида: Σ бой / Σ crit+ko_crit в 15–45 с, зазоры 8/15/2 с, heavy 5–30 %, env-урон 0, env_slam > 0);
# 3) hitfx_probe — HitFxDirector на doll_dark / doll / ModularDoll; 4) crit_probe — таймлайн CritCinematic; 5) sfx_probe — звук.
# Запуск из-под x86-обёртки: gtimeout 1800 /usr/bin/arch -arm64 /bin/bash godot/tests/run_hitfx_gate.sh
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
run() { godot --headless --path . --fixed-fps 60 "res://tests/$1" -- "${2:-}" > /dev/null 2>&1; local rc=$?; echo "  $1 ${2:-} exit $rc"; [ $rc -eq 0 ] || fail=1; }
run hit_tier_probe.tscn
run hitfx_core_probe.tscn
run hitfx_probe.tscn "scene=void,victim=p2"
run hitfx_probe.tscn "scene=void,victim=p1,out=res://tests/hitfx_probe_p1.json"
run hitfx_probe.tscn "scene=body,victim=p1,out=res://tests/hitfx_probe_body.json"
run crit_probe.tscn
run sfx_probe.tscn "fight_s=20"
echo "=== run_hitfx_gate: $([ $fail -eq 0 ] && echo OK || echo FAIL) ==="
exit $fail
