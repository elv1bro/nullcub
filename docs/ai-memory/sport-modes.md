---
name: sport-modes
description: "04.10 спорт-зал — футбол, баскетбол, волейбол до 3 голов; где код, что решено, что ждёт оценки автора; ветка worktree-sport-modes"
metadata:
  node_type: memory
  type: project
  originSessionId: 4c6c14d4-da5f-4a07-a22f-7b1ac15cd0e2
  modified: 2026-10-05T07:36:23.000Z
---

04.10.2026 автор: «хочу попробовать добавить ещё режим ФУТБОЛ, где куклам нужно пинать мяч в чужие ворота… до 3 голов. И если какие-то спорты легко перенести — тоже». Сделано пробой: футбол + баскетбол + волейбол в одном зале. Worktree `.claude/worktrees/sport-modes`, ветка `worktree-sport-modes` от main 8a7c23f; 05.10 закоммичено в эту ветку (9e377dc) по просьбе сессии «Подготовка версии 0.0.3» и слито ею в main (релиз 0.0.3, [[release-003]]); сам не вливал и не пушил (автор в этой сессии на вопрос о коммите не отвечал). Описание — `docs/plan-demo/SPORT.md`.

Как устроено: `SportMatch extends Match` (`godot/scripts/sport/`), мяч `SportBall`, бот `SportBrain extends EnemyBrain`, зал `scenes/arena/sport_hall.tscn` из кита Old NULL Hall (сборщик `tools/build_sport_hall.tscn`, модели `Sport_*` в `tools/blender/arena_null_hall.py`), площадки `scenes/playground_sport*.tscn`, числа — блок «спорт-зал» в `tuning.gd`. Вход — «ВСЕ РЕЖИМЫ» (test_menu). Клавиши в зале: F — вид спорта, U — бот / человек за P2 (C занята режимом [[joint-break-mode]]). Проба `tests/sport_probe.tscn` — 89 проверок, матч ботов до конца по каждому виду.

**Why так:** удара-кнопки нет — мяч бьют телом (язык игры: кукла летает и врезается). Нокаут не кончает матч, а «удаляет» на 2.5 с. Баскетбольный мяч сам отскакивает от пола (floor_kick): лежащий мяч куклой не поднять, без этого боты 270 с катали его по полу со счётом 0:0. Пункт в главное меню гаража не добавлен: он сдвинул бы цифры 1–7, точки камеры и жёсткие индексы `garage_menu_probe`.

**How to apply:** ощущение игры руками автор ещё не оценивал — следующий разговор про спорт начинать с его отзыва; первые ручки — `Tuning.SPORTS[вид]` (масса и тяжесть мяча, высота ворот) и `SPORT_BOT_LEVELS`. `Match.respawn_doll` пересоздаёт детей-скрипты куклы без настроек — мозг бота берёт команду у куклы сам. Камера: `DynamicCamera.user_zoom` статический и общий, площадка спорта на время сцены ставит 1. См. [[training-hall-and-loader]], [[port-in-game-language]], [[godot-test-workflow]].
