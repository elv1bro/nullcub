---
name: audio-rework
description: "02.10 звук переделан целиком (ветка claude/audio-rework): CC0-конвейер, GameAudio, удары по материалам, толпа, стук столкновений, фон, музыка; как проверять без ушей"
metadata:
  node_type: memory
  type: project
  originSessionId: 998a0c47-da3b-4c76-833c-3bb14a6d1471
  modified: 2026-10-02T11:04:33.664Z
---

02.10.2026 автор попросил «переработать весь звук» (удары — фигня, нет толпы, нет звука полёта). Сделано в ветке `claude/audio-rework`, документ `docs/plan-demo/AUDIO.md` (заменяет HIT_FX.md §2.5/§7).

Решения автора 02.10: качать CC0 (Kenney + Freesound) — да; толпа **и** музыка, с выключателем (сделано: M — музыка, N — толпа, `user://audio.cfg`); работать в отдельной ветке и потом слить.

**Why:** бойцы — дерево/железо, а звучали «кулаком по мясу»; мир молчал между ударами.
**How to apply:**
- Исходники: `godot/tools/audio/fetch_audio_sources.py` → кэш `~/.cache/ragdoll-faces/audio_src` (вне git, ~42 МБ); сборка `build_audio.py` (громкость BS.1770; `audio_dsp.py` сверен с ffmpeg ebur128). Слой = папка вариантов; баланс — в `SfxDirector.LAYER_DB`, `GameAudio.DEFAULT_DB`.
- Я не слышу звук: «уши» — `tests/run_audio_gate.sh` (sfx_probe + audio_probe × 4 арены) и `tools/audio/mix_check.py` по AVI Movie Maker (цель −18 LUFS, клип v1 −18.3). Спектрограммы/огибающие (matplotlib) помогают выбрать куски из длинных записей толпы.
- Подводные камни: `get_meta(k, null)` в Godot ругается без ключа — `has_meta`; stop() плееров в `_exit_tree` при quit() headless УВЕЛИЧИВАЕТ «leaked at exit» (не делать); в worktree-сессии bash-циклы с переменными и `git -C <main>` блокирует песочница — гейт-скрипты запускать `bash tests/run_*.sh` (шелл уже arm64), git только в своём worktree; `--check-only` не знает имени автозагрузки GameAudio — в коде звать `get_node("/root/GameAudio")` или `SfxDirector.GameAudioScript` для static.
- Компрессор старого SFX (−14 дБ, 2.5:1) душил удары; фон (музыка+толпа+арена) без sidechain-приглушения закрывал heavy — теперь sidechain от SFX на Music/Crowd/Ambience.
- Механика «Заряд» (main 30d0d13): `Doll.dashed` — передний фронт удерживаемого ускорения, `flipped` — старт раскрутки.

Открыто: автор слушает клип `docs/plan-demo/img/audio-fight-v1.mp4` и доску `scenes/audio/audio_board.tscn`, правит микс; голос N0; петли тяги/раскрутки. Связано: [[project-essence]], [[godot-test-workflow]], [[shared-checkout-commits]].
