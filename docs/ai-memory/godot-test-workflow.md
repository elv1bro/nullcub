---
name: godot-test-workflow
description: "How to run the Godot demo gates from a Claude worktree (import first, native arm64, which probes need a window)"
metadata:
  node_type: memory
  type: reference
  originSessionId: c656eb1a-1291-4839-9c01-774a0b730717
  modified: 2026-10-05T07:34:05.879Z
---

Running `godot/` gates from a Claude Code worktree (verified 29.09.2026, Godot 4.7.2):

- A fresh worktree has no `.godot/`: run `gtimeout 900 /usr/bin/arch -arm64 /usr/local/bin/godot --headless --path godot --import` once (~3 min, 472 MB assets). This only touches the worktree's own `.godot/`, never the author's open editor project; tracked files stay clean.
- Gate scripts call bare `godot`, so wrap the shell, not godot: `gtimeout 900 /usr/bin/arch -arm64 bash tests/run_gate.sh` (gtimeout is x86 → otherwise Rosetta).
  - Same inside your own runner scripts: `gtimeout N godot …` without `arch -arm64` runs Godot under Rosetta even when the script itself was started with `arch -arm64 bash`. Verified 05.10.2026: `build_body_kit.gd` under Rosetta rewrites `godot/assets/materials/kit/Screen.tres` (last float digit of albedo); native arm64 leaves it clean.
- Headless is fine for run_gate, run_combat_gate, match_probe, scrap_match_probe, scene_switch_probe. `tests/hud_snapshot.tscn` and `tests/clip_capture.tscn` capture frames and need a window (`--resolution 1280x720`); headless they hang on frame_post_draw.
- Windowed probes (snapshots, clips, perf_probe, --write-movie): launch via `godot/tools/godot_nofocus.sh --path godot ...` (since 02.10, commit 9c45509) — plain godot steals the author's focus. No `--always-on-top`, no off-screen `--position` (macOS throttles, perf_probe breaks). Details: AGENTS.md top, godot/README.md «Проверки».
- Parallel match_probe runs overwrite `tests/match_probe_report.json`; parse the JSON printed to stdout between `=== MATCH PROBE ===` and `=== OK ===` instead.
- `--check-only -s <script.gd>` really parses non-SceneTree scripts (a broken file prints "Parse Error").
- Other sessions edit the main checkout concurrently (uncommitted); hand worktree work over as a patch and `git -C <main> apply --check` it rather than writing into main.

- 02.10: `.godot/` в основном чекауте может отстать (кэш классов без новых `class_name` → «Could not find type WsSfx/PartNames»): сначала `--headless --import` (~3 мин под нагрузкой). Для scratch-worktree на чистом HEAD: `git worktree add --detach <путь> HEAD`, `cp -Rc godot/.godot <путь>/godot/.godot` (клон APFS мгновенный), затем `--import` ≈ 26 с; убрать `git worktree remove --force`. Оконные пробы: НЕ передавать `--fixed-fps 0` (процесс молча выходит); `--user-data-dir` с пустой папкой — проба завершается сразу, не использовать.
- Замеры под чужой нагрузкой (load 10–60) завышают мс в 2–5×: брать min/median по нескольким прогонам, сравнивать «до/после» в одном состоянии машины.

- 04.10: `match_probe scene=ruins` на HEAD 8a7c23f нестабилен (2 из 6, у меня 2 из 21 без KO за 120 с; красные ko / match_over / match_winner / match_places / results_visible / hud_phase_over). Причина найдена 04.10: кукла уходит из ямы у края (|x| 14–16) под плиты земли — под ними не было коллизии — и живёт там до конца боя. Починено коммитом `f0a80fc` в ветке `claude/distracted-bartik-b85bfe` (05.10, вливает в main сессия релиза 0.0.3; до этого — патч `ruins-match-probe-fix.patch`): стенки шахт `Bounds/PitWallL/R` в `ruins.tscn` + сборщике, в пробе — проверка `pit_walls`, обход по сетке (nav), отход упёршейся куклы, `trace=1`, `p1=/p2=`. Признак, что патч в дереве: в `ruins.tscn` есть `PitWallL`. С патчем 33 из 33 зелёные, бой 23–55 с. Без патча красные Руины с таким набором — не признак твоей правки.
- Разброс прогонов `match_probe` — от замедлений удара по реальным часам (`Match._real_clock`): исход зависит от загрузки машины, набор исходов дискретный (одни и те же fight_time повторяются).
- Bash-инструмент здесь — zsh: `$G` со строкой «команда с аргументами» не разбивается на слова (exit 127) — оборачивать в скрипт/функцию; `rm -f шаблон*` без совпадений роняет всю цепочку `&&`.
- 04.10: новый `class_name` в основном чекауте не виден пробам, пока не прошёл `--headless --import` (у меня 35 строк лога, меньше минуты); сцена с неразобранным скриптом не выходит сама — пробу запускать с `gtimeout` и выводом в файл, не через `| tail`.
Related: [[project-essence]]
