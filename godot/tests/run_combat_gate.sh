#!/usr/bin/env bash
# Headless-гейт боя (план 06). Использование: tests/run_combat_gate.sh ["only=band_hammer"]
# --fixed-fps 60: физика с фиксированным шагом быстрее реального времени. Отчёт: tests/combat_gate_report.json, exit 0/1.
# 128 проверок, 13 сценариев (28.09). Урон от окружения выключен (Tuning.ENV_DAMAGE_ENABLED = false): env_wall, prop_push,
# loose_weapon ждут 0 урона/стана/отброса/надписей/hit_feel; weapon_still и weapon_thrown — что оружие бьёт как раньше.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --fixed-fps 60 res://tests/combat_gate.tscn -- "${1:-}"
