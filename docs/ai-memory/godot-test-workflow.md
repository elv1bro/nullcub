---
name: godot-test-workflow
description: "How to run the Godot demo gates from a Claude worktree (import first, native arm64, which probes need a window)"
metadata:
  node_type: memory
  type: reference
  originSessionId: c656eb1a-1291-4839-9c01-774a0b730717
  modified: 2026-09-29T09:18:40.509Z
---

Running `godot/` gates from a Claude Code worktree (verified 29.09.2026, Godot 4.7.2):

- A fresh worktree has no `.godot/`: run `gtimeout 900 /usr/bin/arch -arm64 /usr/local/bin/godot --headless --path godot --import` once (~3 min, 472 MB assets). This only touches the worktree's own `.godot/`, never the author's open editor project; tracked files stay clean.
- Gate scripts call bare `godot`, so wrap the shell, not godot: `gtimeout 900 /usr/bin/arch -arm64 bash tests/run_gate.sh` (gtimeout is x86 → otherwise Rosetta).
- Headless is fine for run_gate, run_combat_gate, match_probe, scrap_match_probe, scene_switch_probe. `tests/hud_snapshot.tscn` and `tests/clip_capture.tscn` capture frames and need a window (`--resolution 1280x720`); headless they hang on frame_post_draw.
- Parallel match_probe runs overwrite `tests/match_probe_report.json`; parse the JSON printed to stdout between `=== MATCH PROBE ===` and `=== OK ===` instead.
- `--check-only -s <script.gd>` really parses non-SceneTree scripts (a broken file prints "Parse Error").
- Other sessions edit the main checkout concurrently (uncommitted); hand worktree work over as a patch and `git -C <main> apply --check` it rather than writing into main.

Related: [[project-essence]]
