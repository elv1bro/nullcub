---
name: body-kit-v2
description: "29.09.2026 кит тела v2 — новый вид модульной куклы по листу автора «Ragdoll Master»: контракт BODY_KIT.md, кто что держит, как запускать"
metadata:
  node_type: memory
  type: project
  originSessionId: 56dde385-2fe1-48d5-a9ad-584750865a25
  modified: 2026-09-29T10:58:09.956Z
---

**29.09.2026:** автору не нравился вид куклы (манекен v3 с полосками). Он прислал лист-референс «Ragdoll Master: build · fly · smash» (игрушечный конструктор: головы со слотом лица, ядра-хабы, видимые шарниры, 17 типов конечностей, оружие, броня/декор, материалы) и попросил: больше деталей, круче крафт, договориться с другими сессиями. Сам лист пропал из /tmp после жёсткой перезагрузки — описание категорий есть в `docs/plan-demo/BODY_KIT.md`.

Сделано: Blender-кит `godot/tools/blender/body_kit.py` + модули `kit_common/kit_joints/kit_heads/kit_cores/kit_limbs/kit_ends/kit_deco/kit_weapons.py` (роли материалов Base_<Mat> / Shirt_Kit / Face / CoreGlow, META для `kit_catalog.json`), кадр стиля `docs/plan-demo/img/body-kit-v1.png`, контракт `docs/plan-demo/BODY_KIT.md` (ось материалов MaterialDef, типы шарниров KitJoint pin/free/spring/motor/weld, коннекторы цвета игрока, декор/броня fixed, пост-импорт `tools/kit_import.gd` ставит материалы по имени роли). Классы `scripts/body/material_def.gd`, `kit_joint.gd`, поля PartDef base_mat/connector — написаны. Интеграцию (builder `tools/build_body_kit.gd`, ModularDoll, мастерская, kit_probe) делал workflow агентов.

Договорённости: боевая сессия внесла хук `Damage.body_mult_of_body` (meta "body_mult" на теле); магнит Свалки принимает meta "material" числом (кг железа) — ModularDoll пишет её во все тела; заставка завязана на `assets/models/heroes/mannequin_v3/**` — не трогать (29.09 автор забраковал заставку по сюжету; если переделают — сразу на ките). Переключение `doll.tscn` и кукол заставки на кит — только по согласованию (BODY_KIT.md §9).

**29.09 вечер — закоммичено** `06b789b` (кит: 76 деталей, 10 пресетов, MaterialDef 15, KitJoint, мастерская «Шарниры/Броня/Материал», kit_probe 2423), рядом `c796832` архив заставки (главная сцена — scenes/playground.tscn по решению автора), `de9d2aa` параллакс. Открыто: (1) агент шлифовки сменил краски кита на бордовый/бирюзовый/горчичный/оливковый ради читаемости игроков и добавил пояса цвета игрока на ядра — автору не показано как отдельное решение, откат: тинты в KIT_MATS (kit_common.py) и MATS (build_body_kit.gd) + названия; (2) hit_mult (шипы ×1.3, рога ×1.3, клешня ×1.15…) — стартовые числа, баланс за боевой сессией; (3) обещал перевести приватные хелперы ModularDoll на префикс `_md_` (29.09 поле Doll._com_local сломало компиляцию ModularDoll).

**30.09 — покраска** (`0987f9e`, контракт `docs/plan-demo/BODY_PAINT.md`): по просьбе автора «кастомизация, на которую классно тратить время» — вкладка мастерской «Покраска»: баллончик (воксельный слой PaintLayer в кадре меша детали, zstd в ключе узла `paint`), раскраски, трафареты (20 масок, tools/gen_paint_assets.py), наклейки из любой картинки (KitImages, user://kit_images; меш-наклейки, не Decal — декали Forward+ мерцали), фото на голову (`face`), симметрия, отмена по штриху. Краска в том же проходе (двойник материала) — потеря FPS ≤ 6 %. Цвет игрока (Shirt*) и фото не красятся, физика не меняется. Обещал боевой сессии: `paint=1` в их perf_probe (или готовую функцию).

**Why:** следующий разговор про вид куклы, крафт или мастерскую должен начинаться с BODY_KIT.md, а не с BODY_CRAFT.md.
**How to apply:** правки деталей — в модулях kit_*.py (превью `-- --preview out.png Имя`), затем `--export` → `godot --import` → `-s res://tools/build_body_kit.gd`; Godot только через lock-обёртку. См. [[concept-v2-roguelite]], [[godot-test-workflow]].
