#!/bin/bash
# Гейт производительности (docs/plan-demo/PERF_PASS.md §5). Из каталога godot/:  tests/run_perf_gate.sh [--window]
#   1. texture_compress_pass --check — ни одной 3D-текстуры в Lossless (память текстур Руин была 1.1 ГБ, стала 0.3);
#   2. gfx_probe — масштаб 3D под физические пиксели, пресеты;
#   3. perf_gate_probe — жесты мастерской, part_def, обломки: время (минимум из N) против пределов;
#   4. match_probe perf=1 на Руинах и Свалке — рывки кадра и «узлов за кадр» в активном бою (headless: реальные часы между кадрами =
#      цена кадра на CPU). Остальные проверки match_probe тут не смотрим (разброс ботов), только perf_*;
#   5. --window: stats_probe в окне (Mobile): память текстур ≤ 400 МБ и draw calls ≤ пределов на аренах и в сборке.
# Godot на Mac запускать нативно: gtimeout 1800 /usr/bin/arch -arm64 /bin/bash tests/run_perf_gate.sh  (GODOT=… — свой бинарник).
# Время — реальные часы: под чужой нагрузкой (load average >> числа ядер) пределы могут ложно сработать — перезапустить.
cd "$(dirname "$0")/.." || exit 2
G=${GODOT:-godot}
fail=0
say() { echo; echo "=== $* ==="; }

say "1. текстуры: VRAM-сжатие у 3D"
python3 tools/texture_compress_pass.py --check | tail -3 || fail=1

say "2. gfx_probe"
$G --headless --path . res://tests/gfx_probe.tscn 2>&1 | grep -E "FAIL|GFX PROBE|SCRIPT ERROR" || fail=1
$G --headless --path . res://tests/gfx_probe.tscn > /dev/null 2>&1 || fail=1

say "3. perf_gate_probe"
$G --headless --path . --fixed-fps 60 res://tests/perf_gate_probe.tscn 2>&1 | grep -E "ok  |FAIL|PERF GATE|SCRIPT ERROR"
[ "${PIPESTATUS[0]}" = "0" ] || fail=1

for sc in ruins scrap; do
  say "4. бой на «$sc» (match_probe perf=1)"
  out=$($G --headless --path . --fixed-fps 60 res://tests/match_probe.tscn -- "scene=$sc,max_s=60,perf=1,out=res://tests/perf_fight_${sc}_report.json" 2>&1)
  echo "$out" | grep -E "^PERF|^  (ok  |FAIL) perf_" | cut -c1-240
  echo "$out" | grep -qE "FAIL +perf_" && fail=1
  echo "$out" | grep -qE "ok +perf_nodes_per_frame" || fail=1
done

if [ "${1:-}" = "--window" ]; then
  say "5. окно (Mobile, 1280x720): память текстур и draw calls"
  for sc in playground:1500 playground_scrap:1500 playground_null_hall:1500 workshop/workshop_build:2200; do
    scene=${sc%%:*}; draws=${sc##*:}
    out=$($G --path . --resolution 1280x720 --position 100,100 res://tests/stats_probe.tscn -- "scene=res://scenes/$scene.tscn,frames=150" 2>&1)
    tex=$(echo "$out" | sed -nE 's/.*texture=([0-9]+) MB.*/\1/p' | head -1)
    dc=$(echo "$out" | sed -nE 's/.*draw=([0-9]+) .*/\1/p' | head -1)
    ok="ok  "; { [ -n "$tex" ] && [ "$tex" -le 400 ] && [ -n "$dc" ] && [ "$dc" -le "$draws" ]; } || { ok="FAIL"; fail=1; }
    echo "  $ok $scene: текстуры ${tex:-?} МБ (≤ 400), draw calls ${dc:-?} (≤ $draws)"
  done
fi

echo
if [ "$fail" = "0" ]; then echo "PERF GATE OK"; else echo "PERF GATE FAILED"; fi
exit $fail
