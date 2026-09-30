# Кит тела v2 — контракт (29.09.2026)

Автор недоволен видом куклы (манекен v3 с синими полосками) и хочет больше деталей и более интересный крафт. Референс автора — лист «Ragdoll Master: build · fly · smash». Кадр стиля (утверждён 29.09) — `docs/plan-demo/img/body-kit-v1.png`, лист-каталог всех деталей — `docs/plan-demo/img/body-kit-v2.png`, пресеты в игре — `docs/plan-demo/img/body-kit-v1-presets.png`.

Этот документ дополняет `BODY_CRAFT.md` (контракт v1: Socket/Anchor, чертёж, ModularDoll, крафт оружия). Всё, что там сказано, остаётся в силе, если здесь не сказано иначе.

## 0. Кто что держит (согласовано 29.09 с соседними сессиями)

| Зона | Владелец | Файлы |
|---|---|---|
| Кит тела | эта сессия («Модульная система куклы») | `tools/blender/body_kit.py`, `tools/blender/kit_*.py`, `assets/models/body/kit/`, `assets/materials/kit/`, `tools/build_body_kit.gd`, `tools/kit_import.gd`, `scenes/body/**`, `data/body/**`, `scripts/body/{modular_doll,part_def,body_blueprint,weapon_blueprint,material_def,kit_joint}.gd`, `scenes/workshop/**`, `tools/build_body_parts.gd`, `tools/build_craft_parts.gd`, `tools/blender/craft_parts.py`, `tests/{body,craft,workshop,kit}_probe.gd` |
| Бой и эффекты | «Gamedev project audit and roadmap» | `scripts/core/{damage,match,doll_combat}.gd`, `scripts/tuning.gd`, `scenes/doll/doll.gd` (только аддитивно), `scripts/fx/**`, `scenes/ui/**`, аудио, камера. Пограничные: `crafted_weapon.gd`, `thrown_credit.gd` (MASS_CAP) — перед правкой написать им |
| Свалка v2 | «Определение игры и планы» | `scenes/arena/scrap.*`, `tools/build_arena_scrap.gd`, `scenes/props/scrap/**` (магнит, машины, лут), `scripts/body/run_inventory.gd`, `scripts/body/arm_assist.gd` |
| Заставка | «Красивая заставка комикс для игры» | `scenes/intro/**`, `tools/build_intro_comic.gd`. Зависит от `assets/models/heroes/mannequin_v3/**` — **эти файлы не менять и не удалять** |
| Фикс двойного KO | «Fix double KO…» | патч в worktree; `match.gd` `build_results` / `_on_doll_ko` не трогать |

**Не трогаем:** `doll.tscn`, `doll_dark.tscn`, `doll.gd`, `tuning.gd`, `damage.gd`, `doll_combat.gd`, `match.gd`, `arm_assist.gd`, `playground.gd`/`.tscn`, `project.godot`, тесты `combat_gate`, `match_probe`, `scrap_*`, `arm_assist_probe`.

Переключать дефолтную куклу матча (`doll.tscn`) и кукол заставки на кит — **позже и только по согласованию** (§9).

**Godot запускаем только через блокировку:** `gtimeout 900 /usr/bin/arch -arm64 /usr/bin/python3 <GL> --headless --path godot …`, где `<GL>` = `/private/tmp/claude-501/-Users-eliseyvrublevskiy-Projects-ragdoll-faces/0b6ad0e0-94f8-4b1f-b4c8-05aa77984376/scratchpad/godot_locked.py`. Боевая сессия запускает `--import` без блокировки: если импорт столкнулся, повторить через минуту.

## 1. Детали в Blender

**Модули.**
- `tools/blender/kit_common.py` — материалы по ролям, общие узлы (обоймы, заклёпки, колышек, плашка лица, окошко Ядра), `HUMAN_ANCHORS`, `limb_empties`.
- Детали по категориям: `kit_joints`, `kit_heads`, `kit_cores`, `kit_limbs`, `kit_ends`, `kit_deco`, `kit_weapons`. В каждом модуле функции `build_<Имя>(**kw) → (объекты, пустышки[, [FacePlate]])`.
- `body_kit.py` собирает реестр из всех `build_*` модулей.

**Команды** (из корня репозитория, `B=/Applications/Blender.app/Contents/MacOS/Blender`):
- `$B -b --python godot/tools/blender/body_kit.py -- --export [Имя…]` — пишет `godot/assets/models/body/kit/Kit_<Имя>[_<размер>].glb` и `kit_catalog.json`, печатает сводку `=== body kit === {json}`. Без имён — все детали; деталь сверх бюджета треугольников — `ERROR: over budget`, код выхода 1.
  - Размеры (`body_kit.sized`): конечности — `S` / `L` (`Limb_Basic` ещё `LA` / `LL`); любая другая деталь, у builder-а которой есть параметр `r` (радиус конечности, на которую она надевается: `Deco_Spikes`, `Deco_Gauntlet`), — тоже `S` / `L` с `r = SIZES[…]["r"]`. Подпись размера в `title`: «(рука)» / «(нога)» (`LA` / `LL` — «(предплечье v3)» / «(голень v3)»).
- `$B -b --python … -- --preview /abs/out.png Имя Имя@PaintBlue Limb_X^L …` — ряд деталей рядом с эталонной куклой кита «Человек» (`^L` — размер L, и у конечностей, и у деталей с `r`).
- `$B -b --python … -- --frame`, затем `python3 godot/tools/blender/body_kit.py --sheet` — лист-каталог. Переменные: `KIT_RENDER_SAMPLES` (48), `KIT_RENDER_TMP` (папка рядов, по умолчанию `<tmp>/body_kit_render`).
  - `--sheet` без пути пишет два файла:
    - полный лист (2600 px, ~10 МБ) — `$KIT_RENDER_TMP/body-kit-v2-full.png` (`SHEET_FULL`), вне `docs/`;
    - копию для `docs/` — `docs/plan-demo/img/body-kit-v2.png` (`SHEET_PNG`): 1480 px по ширине (`SHEET_DOC_W`), Pillow LANCZOS, RGB без палитры, `optimize=True`. Больше 4 МБ (`SHEET_DOC_MAX_BYTES`) — `ERROR`, код выхода 1, файл в `docs/` не меняется.
  - `--sheet out.png` — только полный лист по этому пути.
  - `body-kit-v1.png` — утверждённый кадр стиля, `--sheet` его не перезаписывает.
  - Правило `docs/`: не шире 1800 px, PNG без потерь, ≤ 4 МБ. `body-kit-v1.png` — 1760 px. `body-kit-v2.png` — 1480 px, 3.9 МБ: при 1800 px шум рендера даёт 5.7 МБ, а палитра на 256 цветов даёт полосы на хабе.
- Экспорт детали берёт случайные сдвиги UV (`craft_parts.fin`) от своего зерна (crc32 имени glb). Поэтому правка одной детали не переставляет UV у всех следующих по алфавиту, а `--export Имя` даёт тот же glb, что полный прогон.

**Геометрия.**
- Координаты Godot: x вбок, **+X — левая сторона куклы**, y вверх, z к камере. `craft_parts.G2B` переводит их в Blender.
- Origin детали = `Socket`, деталь растёт в −Y. Голова и декор, который ставится сверху, растут вверх: у них `Socket` повёрнут на 180° вокруг Z.
  - В Godot у кисти начало тела переносит builder (§3.1): там оно в центре форм, а `Socket` выше. В glb origin кисти — тоже `Socket`.
- Бюджет: ≤ 3000 треугольников на деталь, ≤ 6000 на ядро.

**Пустышки** — как в `craft_parts.py`:
- `Socket`;
- `Anchor_<имя>`: позиция = точка сустава, −Y = куда вырастет ребёнок;
- `Shape_<Box|Sphere|Cyl|Capsule>_<имя>`: масштаб кодирует размеры.

**Имена якорей** — это контракт: метаданные якоря выводятся из имени (§3).
- Ядро: `Neck`, `Shoulder_L/_R`, `Hip_L/_R`, `Side_L/_R`, `Back`.
- Конечность: `End` на конце и `Deco` у верха.
- Голова: `Top`.
- Кадры якорей одинаковы у всех ядер (`HUMAN_ANCHORS`): плечи и бёдра смотрят −Y вниз, бока на ±60°, шея и `Back` вверх. Позиции у ядер свои. Поэтому углы покоя чертежа одинаково работают на любом ядре.

**Материалы в glb — плоские.** Имя материала — это роль:

| Имя | Роль | Что делает Godot |
|---|---|---|
| `Base_<Mat>` | основной материал детали; `<Mat>` — материал по умолчанию | узел чертежа может заменить его (ось материалов, §4) |
| `Shirt_Kit` | цвет игрока: пояса ядер, шары шарниров, полоски, флажок, ремни | `Doll._recolor("Shirt")` перекрашивает его сам |
| `Face` | объект `FacePlate`, UV 0..1 | фото игрока; по умолчанию — нарисованное лицо |
| `CoreGlow` | окошко Ядра | эмиссия |
| `Iron`, `Steel`, `Brass`, `Rubber`, `Bone`, `WoodDark`, `Rust`, `RustDark`, `Rope`, `Gem`, `Pin`, `Joint`, `Screen` | фурнитура | не перекрашивается |
| `Glass` | закопчённое стекло (фонарь) | янтарное, полупрозрачное (`TRANSPARENCY_ALPHA`, альфа 0.38), слабый отсвет огарка |

Все материалы Base_* дают UV из расчёта 2 тайла на метр (`KIT_MATS`, последний столбец), поэтому их можно заменять друг на друга.

**Цвет игрока на ядре** (29.09, QA на Свалке, `docs/plan-demo/img/body-kit-v1-arena.png`).
- Проблема: на игровом расстоянии (полувысота кадра ~4 м) шары шарниров и тонкие полоски `Shirt_Kit` занимают несколько пикселей. Кукла читалась цветом своей краски, а не цветом игрока: чёртик в красной краске — как P2, каталка и робот в синей — как P1, жёлтые поршни сливались с P4.
- Решение, часть 1: у каждого ядра широкий пояс `Shirt_Kit` — не меньше ~15 % фронтального силуэта ядра. Строят его `_player_band` (пояс на теле вращения) и `_ribbon` (лента по поверхности) в `kit_cores.py`.
- Решение, часть 2: краски больше не совпадают с цветами игроков (§4).
- Доля цвета игрока спереди (орто-рендер Workbench, пиксели `Shirt_Kit` / силуэт):

| Ядро | Что цвета игрока | Доля |
|---|---|---|
| `Core_Barrel` | обруч под окошком Ядра (вместо третьего железного) | 22 % |
| `Core_Crate` | полоса вокруг ящика под окошком | 16 % |
| `Core_Ball` | пояс под ободом | 18 % |
| `Core_Boiler` | два пояса: над лазом и под ним (вместо нижнего шва) | 19 % |
| `Core_Toy` | широкий пояс и помочи через грудь | 21 % |
| `Core_Drum` | широкий пояс под крышкой и узкий у дна | 21 % |
| `Core_Cage` | обруч на плече купола (вместо железного), пояс цоколя, тонкий обруч | 25 % (от непрозрачного силуэта) |

- Бюджет треугольников соблюдён: ядра 3.9–5.9 тыс.
- Головы пока почти без цвета игрока: 0 % у круглой, ящика и рогатого шлема, до 7 % у банки. Это следующий шаг, если на Свалке цвета ядра окажется мало.
- Проверять только на Свалке при полувысоте 4 м, а не на фоне `body_probe`: игровой тёплый свет меняет краски (бирюза на солнце светлеет до голубой).

**Размеры конечностей** (`SIZES`, длина между шарнирами / радиус):
- `S` 0.30 / 0.058 — рука;
- `L` 0.42 / 0.074 — нога;
- `LA` 0.27 / 0.052 и `LL` 0.40 / 0.064 — предплечье и голень рига v3, только у `Limb_Basic` (для кита «Человек»).

## 2. Материалы в Godot: пост-импорт

- `tools/kit_import.gd` (`@tool extends EditorScenePostImport`) проходит по всем MeshInstance3D импортируемой сцены. Для каждой поверхности с материалом `<Имя>` он загружает `res://assets/materials/kit/<Имя>.tres`, если такой файл есть, и ставит его через `mesh.surface_set_material`.
- Builder прописывает `import_script/path="res://tools/kit_import.gd"` во все `assets/models/body/kit/*.glb.import` и перезапускает импорт.
- В результате материалы правильные везде без рантайм-кода: в кукле, иконках мастерской, призраке при перетаскивании, крафтовом оружии.
- `assets/materials/kit/<Имя>.tres` — StandardMaterial3D.
  - `resource_name` = имя роли. От этого зависят `_recolor` (префикс «Shirt») и замена Base_*.
  - Текстуры — копии 512² с мип-мапами `assets/materials/kit/tex/<папка>/{albedo,roughness,normal,metallic}.webp` (какие есть у исходника), папки — из `KIT_MATS`; `uv1_scale = (1,1,1)`.
    - Копии пишет `python3 godot/tools/gen_kit_face.py` из `assets/textures/pbr/<папка>/*.png` (albedo / roughness / metallic — WebP q 92, normal — WebP без потерь; альфа albedo отбрасывается: у `paint_marks` она почти нулевая, и WebP обнулил бы под ней цвет). Скрипт идемпотентный: копия пересоздаётся, если исходник новее.
    - Зачем: исходники 2048² импортированы без мип-мапов и без сжатия — ~16 МБ видеопамяти на карту, ~0.5 ГБ на кит, мерцание мелких деталей.
    - Запасной путь: если копии нет (не сгенерирована или не импортирована), builder берёт исходник `assets/textures/pbr/<папка>/<карта>.png` и пишет предупреждение в сводку.
  - `Shirt_Kit` — светлая краска (`paint_marks`), цвет задаёт `albedo_color`.
  - `Face` — `assets/materials/kit/face_default.png` (256², тоже `gen_kit_face.py`), мультяшное лицо «фотокарточка».
  - `CoreGlow` — эмиссия: тёмная база (0.30, 0.10, 0.02) и насыщенный оранжевый (1.0, 0.25, 0.03), energy 0.9. При energy 3 и светлой базе купол выгорал в белый диск (ACES), теперь он тёплый оранжевый с горячим бликом. В Blender — `CORE_GLOW_STRENGTH` = 1.2 (`kit_common.py`, AgX; было 9).
  - `Glass` — плоский янтарный (0.50, 0.30, 0.10), альфа 0.38, roughness 0.08, эмиссия 0.2 — стекло фонаря сбоку и сзади читается как освещённое стекло, сквозь него виден огарок (раньше там была почти чёрная роль `Screen`).
  - **Металл читается без отражений** (29.09). У сцен без неба (Свалка, `body_probe`) металличность 1.0 отражала пустоту, и железо выходило почти чёрным.
    - `Iron`, `Base_Iron`: albedo карты `iron` (~0.06 линейно) поднят tint > 1 до ~0.25 (tint `[3.4, 4.3, 4.3]`), metallic 0.6 × карта (≈ 0.54), roughness — карта (среднее 0.63). Получается тёмный крашеный / кованый металл с рыжими пятнами.
    - `Steel` (заклёпки, болты, шипы): ~0.35, metallic 0.65, roughness × 0.9.
    - `Rust`, `Base_Rust`: tint `[1.35, 1.5, 1.6]`, metallic 0.55 × карта. `RustDark`: tint 0.8, metallic 0.55. `RustRed`, `Base_RustRed`: metallic 0.6 × карта (краска почти не металл, сколы — металл).
    - `Brass`, `Base_Brass`: metallic 0.7 × карта (≈ 0.64 в среднем). `Pin`: metallic 0.6, roughness 0.45. `Joint`: (0.25, 0.24, 0.25), metallic 0.5.
  - **Blender (`KIT_MATS` в `kit_common.py`) и Godot различаются.** Роли и папки текстур одни, а числа — нет. Лист-каталог поэтому не точная копия игры (свет и небо тоже другие). Различия:
    - albedo железа (`Iron`, `Base_Iron`, `Steel`) в Blender ~0.2, в Godot ~0.25–0.35: светлый мир кадра даёт отражения, тёмный фон игры — нет;
    - `Rust`, `RustDark`, `Base_Rust`: в Blender металличность — константа 0.3, в Godot — 0.55 × карта (≈ 0.26 в среднем, карта ~0.47);
    - `Iron` / `Base_Iron` / `Steel`: в Blender константа 0.5 / 0.5 / 0.6, в Godot 0.6 / 0.6 / 0.65 × карта (≈ 0.54 / 0.54 / 0.59);
    - `Brass`, `Base_Brass`: с 29.09 в Blender константа 0.65 ≈ среднее Godot. Раньше Blender брал карту `brass_worn` как есть (~0.92), и на листе латунь блестела сильнее, чем в игре;
    - `Joint` / `Pin` в Blender — `craft_parts.FLAT` (albedo 0.11 / 0.62, metallic 0.85 / 1.0), в Godot — albedo 0.25 / 0.62, metallic 0.5 / 0.6. На виде кита это не сказывается (см. ниже).
    - `Steel`, `Brass`, `Rust`, `RustDark` в `KIT_MATS` перекрывают `craft_parts.MAT_DEFS` только для кита.
  - **Роли без пользователей.** В glb кита сейчас нет ролей `Joint`, `Pin`, `Screen`, `Rust`, `RustRed`. Соединители — `Iron` / `Steel` / `Brass` / `Shirt_Kit`, ржавчина кита — `Base_Rust` / `Base_RustRed` / `RustDark`, стекло фонаря — `Glass`. Их `.tres` — запас на будущее: правки в них на вид не влияют. `Base_Rust` и `Base_RustRed` с теми же числами используются (по 4 поверхности).
  - Материалы генерирует `tools/build_body_kit.gd`: таблица `MATS` в нём повторяет `KIT_MATS` (ключи: `pbr`, `tint` — линейный, может быть > 1; `rough`; `metal` — множитель карты metallic или металличность плоского; `flat`; `alpha`; `glow`, `energy`; `swatch`).
  - Новая роль: `kit_import.gd` ставит `.tres` только при импорте glb. glb, импортированные до появления `<Роль>.tres`, остаются с плоским материалом. Builder пишет предупреждение «новая роль …: touch …glb, затем --import».

## 3. Сцены и данные деталей (`tools/build_body_kit.gd`)

Запуск: `<GL> --headless --path godot -s res://tools/build_body_kit.gd`. Порядок: (`gen_kit_face.py`, один раз / при смене PBR) → Blender `--export` → `--import` → builder → `--import` → пробы.

- Первый `--import` пишет `.glb.import` новых glb без пост-импорта. Builder на **каждом** прогоне дописывает `import_script/path` во все `*.glb.import` кита, где его нет (`import_patched` в сводке), второй `--import` переимпортирует их через `kit_import.gd`.
- Сводка `=== BODY KIT BUILD === {json}`: `parts`, `connectors`, `human_parts`, `presets` (энергия / масса), `self_check` кита «Человек», `shapeless`, `stale`, `warnings`, `errors`; код выхода 1 при ошибках.

### 3.1 Детали из glb (`scenes/body/kit/<id>.tscn`, id = `kit_<имя в snake_case>`, напр. `kit_limb_thick_s`)

Корень — `RigidBody3D`, как в `build_craft_parts.gd`:
- оси заперты: `axis_lock_linear_z`, `axis_lock_angular_x/y`;
- `continuous_cd = true`, `can_sleep = false`;
- демпфирование куклы: ядро и голова `DOLL_LINEAR_DAMP`/`DOLL_ANGULAR_DAMP`, остальное `DOLL_LIMB_*`;
- `PhysicsMaterial` берётся из MaterialDef материала по умолчанию (§4);
- meta: `kind`, `part_id`.

Дети корня:
- `Shape_<имя>` — CollisionShape3D из пустышек (`_shape_from` скопирован из `build_craft_parts.gd`).
- `Mesh` — инстанс glb, meta `rig_mesh = true`. Пустышки и `FacePlate` остаются внутри `Mesh`, это нормально.
- `Socket` и `Anchor_*` — Marker3D.
- У конечности builder добавляет Marker3D `Grip` в точке `Anchor_End`. Это точка хвата ArmAssist, когда рука мышью ведёт саму конечность (предплечье с навершием вместо кисти: `kit_lantern`, `kit_king`). Без маркера хват был бы в начале тела, то есть в локте, а досягаемость — одно звено (0.30 м). У `kit_human_*` маркера нет: они байт в байт как `wood_*`.
- **Кисть — исключение из «origin = Socket»** (раскладка `wood_hand`). Builder сдвигает всех детей корня на −c, где c — центр форм по Y, взвешенный по объёму, как `ModularDoll._com_local`. Начало тела оказывается в центре форм, `Socket` выше (`kit_hand_mitten`: +0.11).
  - Зачем: `WeaponPickup.hand_grip_offset`, фолбэк ArmAssist и `WorkshopBuild.HAND_GRIP` держат хват в (0, −0.03, 0) тела кисти. При `Socket` в начале координат хват попадал в запястье — над коробкой кисти, внутри шара коннектора.
  - Сборка (`xf = anchor × socket⁻¹`), коннектор, призрак мастерской и `ArmAssist._pivot_local` идут через `Socket`, поэтому их это не меняет.
  - Стопы не сдвигаются: хвата на них нет.
- Суффиксы Blender `.001` / `_001` в именах отрезаются.
- **Каждая** пустышка `Shape_*` становится своей CollisionShape3D (повтор имени — суффикс `_2`): у `Limb_Curved` их две (`Shape_Limb` и `Shape_Bow` на изгибе), у крыльев, флажка, дымохода, рогов, наверший — по несколько.

**Метаданные якорей по имени:**

| Якорь | accepts | joint_group | прочее |
|---|---|---|---|
| `Neck` | `["head"]` | `Neck` | `rest_from_pose` |
| `Shoulder_*` | ANY_LIMB | `Shoulder` | `rest_from_pose`; `mirror` у `_R` |
| `Hip_*` | ANY_LIMB | `Hip` | `rest_from_pose`; `mirror` у `_R` |
| `Side_*` | ANY_LIMB | `Hip` | `rest_deg = 0`; `limit_deg = SIDE_LIMITS` (−60, 80); `mirror` у `_R` |
| `End` | ANY_LIMB | `auto` | `rest_deg = 0` (AUTO_NEXT: плечо → локоть → кисть, бедро → колено → лодыжка) |
| `Deco` | `["armor","deco"]` | `""` | только fixed-дети |
| `Top` | `["deco"]` | `""` | только fixed-дети |
| `Back` | `["deco"]` | `""` | только fixed-дети |
| прочие | `["weapon_head","chain","mod"]` | `Ankle` | как у `build_craft_parts.gd` |

- `ANY_LIMB` = `["limb","hand","foot","joint","chain","weapon_head","handle","mod","plate"]` (`BP.ANY_LIMB`).
- Якорь с `joint_group = ""` не принимает деталей со своим телом: `accepts` содержит только fixed-виды.
- Ядра — без `Socket`, как `wood_torso`.
- Кисти и стопы — концевые детали, `Anchor_End` у них нет.
- **Навершия кита** (`kit_weapons.py`, вид `weapon_head`, энергия 0): fixed-детали, как `head_mace_ball`. На теле встают на `End` конечности вместо кисти и сливаются с ней (бур у `kit_lantern`). Их якоря — по строке «прочие»: `Face_L` у кирки принимает `mod` (и `weapon_head`, `chain`), группа `Ankle`.
- Декор — на `Top` (голова: корона, султан, антенна), `Back` (ядро: флажок, крылья, дымоход) и `Deco` (конечность: наплечник, шипы, наруч).
- Коннектор `Joint_Motor` (шестерня) — сцена `connectors/motor.tscn`, как остальные (§3.4).

### 3.2 Детали кита «Человек» под риг v3 (`kit_human_*`)

- Строятся из готовых `scenes/body/parts/wood_*.tscn`: инстанс, `scene_file_path = ""`, `Mesh` и `Mesh_R` удаляются.
- На их место ставится `Mesh` = kit glb с `transform = wood_socket.transform * glb_socket.transform.affine_inverse()`. У ядра Socket нет, берётся единичный.
- Формы, массы, демпфирование, физматериал и якоря остаются **байт в байт как у wood_***. Builder сверяет это сам.
- Сверх того добавляются якоря декора `Deco` (конечности), `Top` (голова), `Back` (торс) — по таблице §3.1.

| id | из | glb | |
|---|---|---|---|
| `kit_human_torso` | `wood_torso` | `Kit_Core_Barrel` | |
| `kit_human_head` | `wood_head` | `Kit_Head_Round` | |
| `kit_human_upper_arm` | `wood_upper_arm` | `Kit_Limb_Basic_S` | 0.30 |
| `kit_human_lower_arm` | `wood_lower_arm` | `Kit_Limb_Basic_LA` | 0.27 |
| `kit_human_hand` | `wood_hand` | `Kit_Hand_Mitten` | |
| `kit_human_upper_leg` | `wood_upper_leg` | `Kit_Limb_Basic_L` | 0.42 |
| `kit_human_lower_leg` | `wood_lower_leg` | `Kit_Limb_Basic_LL` | 0.40 |
| `kit_human_foot` | `wood_foot` | `Kit_Foot_Boot` | |

Меш кита симметричен, поэтому `Mesh_R` не нужен: `_mirror_part` отражает `Mesh` сам.

### 3.3 PartDef (`data/body/parts/kit_*.tres`)

Прежние поля остаются. Новые поля — в §5.1. Массы, энергия и вид задаются в таблице builder-а.

**Энергия (ориентир):**

| Деталь | S / L |
|---|---|
| конечность Basic | 4 / 6 |
| Thick | 7 / 9 |
| Spring | 5 / 7 |
| Piston | 6 / 8 |
| Bone | 3 / 5 |
| Plate | 6 / 8 |
| Tentacle | 5 / 7 |
| Thin | 3 / 4 |
| Curved | 5 / 7 |
| Spiked | 6 / 8 |
| Robotic | 7 / 9 |
| Rope | 3 / 5 |
| Fantasy | 5 / 7 |

- Кисть 2–3, стопа 2–4, голова 7–10 (шлем 12), ядро 0, декор 1–3, навершие 0.
- Масса по умолчанию — объём формы × плотность материала по умолчанию. Итог округлить до 0.1 кг и сверить с деревянными деталями того же размера: Basic_S = 2.0, как `wood_upper_arm`.
- `body_mult` детали со своим телом (ядро, голова, конечность, кисть, стопа) = `Tuning.BODY_MULT[name_prefix]`. Его пишет builder, в каталоге ключа нет.
  - В бою этот множитель не читается: удар — таблица по **имени тела** × материал узла × `hit_mult` детали (meta `body_mult`, §5.4). Кулак бьёт сильнее варежки ещё и ржавчиной (×1.15), клешня и тиски — железом (×1.2).
  - kit_probe сверяет `body_mult` с таблицей.
- **`hit_mult` — удар формой** (29.09, по концепту автора: конструкция решает). Множитель удара ЭТОЙ формой — шипы, рога, клешня; на таблицу по имени и материал он умножается.
  - Только у деталей со своим телом. Значение — `META["hit_mult"]` Blender-модуля → `kit_catalog.json` (ключ есть, только если задан) → builder → `PartDef.hit_mult`. Нет ключа — 1.0. У декора, брони, наверший и `kit_human_*` — 1.0.
  - Значения:

| Деталь | `hit_mult` | Подсказка на полке |
|---|---|---|
| `Limb_Spiked` (S, L) | 1.3 | «шипы: удар ×1.3» |
| `Head_Horned` | 1.3 | «рога» |
| `Head_Devil` | 1.15 | «рожки» |
| `Head_Cow` | 1.1 | «рога» |
| `Hand_Claw` | 1.15 | «клешня» |
| `Hand_Clamp` | 1.1 | «тиски» |
| `Hand_Fist` | 1.1 | «кулак» |
| `Foot_Peg` | 1.15 | «острый колышек» |
| `Limb_Rope` (S, L) | 0.85 | «мягкая верёвка» |
| `Limb_Tentacle` (S, L) | 0.9 | «мягкое щупальце» |
| остальные | 1.0 | — |

  - Пример (kit_devil): плечо и предплечье шипастые из ореха — 0.8 × 1.05 × 1.3 = 1.092 и 1.0 × 1.05 × 1.3 = 1.365; клешня из железа — 2.0 × 1.2 × 1.15 = 2.76; кулак из ржавчины — 2.0 × 1.15 × 1.1 = 2.53; голова-чёртик — 0.35 × 1.0 × 1.15 = 0.4025.
  - Сварка (`weld`) узла со своим телом `hit_mult` не переносит: как и материал, в удар идёт только хозяин (§5.4).
- Декор с шипами: `body_mult = 1.25`, это бонус к удару телом-хозяином (§6). Этот множитель в бою работает.

### 3.4 Шарниры-коннекторы

- `scenes/body/kit/connectors/<type>.tscn` — Node3D с инстансом `Kit_Joint_<Type>.glb`, радиус 1.
- **Без коллизий и без RigidBody.**

### 3.5 Пресеты

- `data/body/blueprints/kit_*.tres` и `scenes/body/presets/kit_*.tscn`, формат как у `junk.tscn`. Пишет `tools/build_body_kit.gd` (`_build_presets`), бюджет 100.
- `kit_human` повторяет `human` один в один (те же uid, имена тел, углы), только детали `kit_human_*`.
- Остальные — «человеческая» раскладка тел (`UpperArm_L`, `LowerArm_L`, `Hand_L`… как `human`: `Damage.body_mult_of` по имени); углы локтя / колена заданы явно (10° / 5°), потому что у `End` кита `rest_deg = 0`.
- Конечность кита без явного имени на локте / колене получает тело `LowerArm_<uid>` / `LowerLeg_<uid>` (`BodyBlueprint.name_prefix_of`). Это нужно, потому что `name_prefix` у неё — по размеру (S — UpperArm, L — UpperLeg).
  - Так предплечье из мастерской бьёт как предплечье (1.0, а не 0.8), а голень — как голень (0.7, а не 0.6). Монитор контактов у них — как в `DollCombat.MONITORED`.
  - Плечо, бедро, бок и третий сегмент сохраняют префикс детали: у `kit_spider` имена прежние.
- `kit_king`: рука мышью ведёт правое щупальце с булавой. Шарнир у него spring, а не free: к свободному локтю ArmAssist не может поднять хват вверх (у ModularDoll нет IK двух звеньев), ошибка цели была ~0.6 м.
- Каждый пресет есть в `scenes/body/playground_body.gd` (`PRESETS`), в `CraftEdit.BODY_PRESETS` (кнопки шаблонов мастерской) и в `tests/body_probe.gd` / `tests/kit_probe.gd` (`PRESETS`).
- `id = "human"` builder кита не пишет никогда.

| id | Название | Ядро · голова | Руки · кисти | Ноги · стопы | Декор, материал, шарниры | control | E / масса (энергия по расстоянию, 30.09) |
|---|---|---|---|---|---|---|---|
| `kit_human` | Кит «Человек» | `kit_human_*` (бочка, круглая) | базовые · варежки | базовые · ботинки | как `human` | 9 | 82 / 40.0 |
| `kit_brawler` | Громила | ящик · ящик | толстые · варежки `rust_red` | поршень + базовая голень · ботинки | — (наплечники и мотор плеча сняты ради энергии) | 9 | 97 / 50.9 |
| `kit_bot` | Робот | хаб `paint_blue` · экран | пружины · клешни | поршни `paint_white` · колышки | флажок; локти spring | 9 | 98 / 52.2 |
| `kit_horned` | Рогатый | бочка `iron` · шлем | кости · клешни | бронеплиты · ботинки `iron` | — (шипы на бёдрах и моторы колен сняты ради энергии) | 9 | 94 / 67.8 |
| `kit_king` | Король-булава | хаб `rust` · круглая `paint_white` | толстые `paint_green` + щупальца · шар булавы | базовые `wood_dark` · ботинки | корона; левое предплечье free, правое (рука мышью) spring | 8 | 82 / 70.2 |
| `kit_spider` | Паук из кита | хаб · круглая | — | 4 базовые ноги (бёдра, плечи; боковые сняты ради энергии) · ботинки | — | J | 92 / 54.0 |
| `kit_devil` | Чёртик | игрушка `paint_red` · чёртик | шипастые · клешня (L), кулак (R) | тонкие · ласты `paint_red` | крылья на спине; колени spring | 9 | 95 / 39.6 |
| `kit_skull` | Скелет | клетка · череп | кости · тиски | кости · колышки `bone` | султан на голове, наруч на правом предплечье; левое предплечье free | 9 | 78 / 37.3 |
| `kit_wheels` | Каталка | бочка из-под масла · банка | робо + тонкое · лопасти | робо · колёса | антенна на голове (пружины колен сняты ради энергии) | 9 | 100 / 50.8 |
| `kit_lantern` | Фонарщик | котёл · фонарь | гнутая труба + тонкое · тиски (L), бур (R, вместо кисти) | поршень + базовая голень · ботинки `iron` | дымоход на спине; правый локоть motor (бур) | 8 | 98 / 56.9 |

**Площадка** `scenes/playground_body.tscn` (`scenes/body/playground_body.gd`): P1 — пресет, P2 — обычная кукла.
- F1–F9, F11, F12 — пресет по номеру в `PRESETS` (F13 — 13-й, только на полной клавиатуре; на macOS F-клавиши — с fn).
  - F10 не занят: это пресет эффектов удара (`playground.gd` `cycle_fx_preset`). 10-й пресет тела выбирается только листанием.
  - `PRESET_KEYS` — словарь «клавиша → индекс». Номер F-клавиши = номер пресета, пропуск F10 номера не сдвигает.
- `]` / PageDown — следующий пресет, `[` / PageUp — предыдущий, по кругу через все пресеты (10-й и дальше F12 — только так). Пресеты без сцены на диске пропускаются.
- Кукла пересоздаётся `Match.respawn_doll` с другим `scene_file_path`, поэтому пресет переживает R и KO.
- Подсказка снизу: название, энергия / бюджет, масса, тел, разгон тяги, «пресет N / всего id».

### 3.6 Детали кита (каталог `kit_catalog.json`, 29.09)

Материал — `base_mat` (id MaterialDef, §4). Энергия коннектора — энергия типа шарнира (`KitJoint`). Бюджет треугольников соблюдён у всех (ядра до 5.9k, остальное до 3k).

`body_mult` деталей со своим телом (головы, ядра, конечности, кисти, стопы) = `Tuning.BODY_MULT` по `name_prefix`. В бою он не читается, удар меняют материал (§4), форма (`hit_mult`, §3.3) и декор (§6). В столбце «Прочее» у них `body_mult` не пишется, `hit_mult` — если ≠ 1.

`weapon_mult` навершия работает только в крафтовом оружии (`CraftedWeapon`). На теле навершие сливается с конечностью массой и формами, удар — `body_mult` тела (§5.4).

| Группа | Деталь (builder) | id `kit_…` | Название | Материал | Масса, кг | Энергия | Прочее |
|---|---|---|---|---|---|---|---|
| Головы | `Head_Bot` | `head_bot` | Голова-экран | paint_yellow | 4.5 | 9 |  |
|  | `Head_Can` | `head_can` | Голова-банка | iron | 3.5 | 8 |  |
|  | `Head_Cow` | `head_cow` | Голова-корова | paint_white | 4.3 | 9 | hit_mult 1.1 |
|  | `Head_Crate` | `head_crate` | Голова-ящик | planks | 3.5 | 7 | плашка лица скруглена по рамке; вкладыш-орех под пазами |
|  | `Head_Devil` | `head_devil` | Голова-чёртик | paint_red | 4 | 9 | hit_mult 1.15 |
|  | `Head_Horned` | `head_horned` | Рогатый шлем | iron | 6 | 12 | hit_mult 1.3 |
|  | `Head_Lantern` | `head_lantern` | Голова-фонарь | brass | 5 | 10 | стёкла — роль `Glass` |
|  | `Head_Round` | `head_round` | Голова-игрушка | wood | 4 | 8 |  |
|  | `Head_Skull` | `head_skull` | Череп с карточкой | bone | 3.2 | 7 |  |
| Ядра | `Core_Ball` | `core_ball` | Ядро-хаб | paint_red | 14 | 0 |  |
|  | `Core_Barrel` | `core_barrel` | Ядро-бочка | wood | 12 | 0 |  |
|  | `Core_Boiler` | `core_boiler` | Ядро-котёл | rust_red | 18 | 0 |  |
|  | `Core_Cage` | `core_cage` | Ядро-клетка | iron | 14 | 0 |  |
|  | `Core_Crate` | `core_crate` | Ядро-ящик | planks | 11 | 0 | вкладыш-орех под пазами (щели не светятся) |
|  | `Core_Drum` | `core_drum` | Ядро-бочка из-под масла | paint_blue | 13 | 0 |  |
|  | `Core_Toy` | `core_toy` | Ядро-игрушка | paint_white | 11 | 0 |  |
| Конечности | `Limb_Basic` | `limb_basic_s/la/l/ll` | Базовая | wood | 2 / 1.5 / 4 / 3 | 4 / 4 / 6 / 6 |  |
|  | `Limb_Bone` | `limb_bone_s/l` | Кость | bone | 1.3 / 2.6 | 3 / 5 |  |
|  | `Limb_Curved` | `limb_curved_s/l` | Гнутая труба | rust | 2.2 / 4.4 | 5 / 7 | 2 формы |
|  | `Limb_Fantasy` | `limb_fantasy_s/l` | Сказочная | paint_white | 2.2 / 4.4 | 5 / 7 |  |
|  | `Limb_Piston` | `limb_piston_s/l` | Поршень | paint_yellow | 2.8 / 5.2 | 6 / 8 |  |
|  | `Limb_Plate` | `limb_plate_s/l` | Бронированная | wood_dark | 3.2 / 6 | 6 / 8 |  |
|  | `Limb_Robotic` | `limb_robotic_s/l` | Робо-гидравлика | paint_yellow | 3 / 5.8 | 7 / 9 |  |
|  | `Limb_Rope` | `limb_rope_s/l` | Верёвка | wood | 1.2 / 2.4 | 3 / 5 | hit_mult 0.85 |
|  | `Limb_Spiked` | `limb_spiked_s/l` | Шипастая | wood_dark | 2.7 / 5.4 | 6 / 8 | hit_mult 1.3 |
|  | `Limb_Spring` | `limb_spring_s/l` | Пружина | iron | 2.4 / 4.4 | 5 / 7 |  |
|  | `Limb_Tentacle` | `limb_tentacle_s/l` | Щупальце | rubber | 1.6 / 3 | 5 / 7 | hit_mult 0.9 |
|  | `Limb_Thick` | `limb_thick_s/l` | Толстая | paint_red | 3.6 / 7 | 7 / 9 |  |
|  | `Limb_Thin` | `limb_thin_s/l` | Тонкая | iron | 1.1 / 2.2 | 3 / 4 |  |
| Кисти | `Hand_Clamp` | `hand_clamp` | Тиски | iron | 1.1 | 3 | hit_mult 1.1 |
|  | `Hand_Claw` | `hand_claw` | Клешня | iron | 0.9 | 3 | hit_mult 1.15 |
|  | `Hand_Fist` | `hand_fist` | Кулак | rust | 1.5 | 3 | hit_mult 1.1 |
|  | `Hand_Mitten` | `hand_mitten` | Варежка | wood | 0.5 | 2 |  |
|  | `Hand_Paddle` | `hand_paddle` | Лопасть | wood | 0.6 | 2 |  |
| Стопы | `Foot_Boot` | `foot_boot` | Ботинок | wood | 1 | 3 |  |
|  | `Foot_Flipper` | `foot_flipper` | Ласта | paint_green | 0.7 | 3 |  |
|  | `Foot_Peg` | `foot_peg` | Колышек | wood_dark | 0.5 | 2 | hit_mult 1.15 |
|  | `Foot_Spring` | `foot_spring` | Пого-пружина | rubber | 0.7 | 4 |  |
|  | `Foot_Wheel` | `foot_wheel` | Колесо | paint_red | 0.7 | 3 |  |
| Декор и броня | `Deco_Antenna` | `deco_antenna` | Антенна | iron | 0.3 | 1 |  |
|  | `Deco_Banner` | `deco_banner` | Флажок | wood_dark | 0.5 | 1 |  |
|  | `Deco_Chimney` | `deco_chimney` | Дымоход | rust | 1 | 2 |  |
|  | `Deco_Crown` | `deco_crown` | Корона | brass | 0.4 | 1 |  |
|  | `Deco_Gauntlet` | `deco_gauntlet_s/l` | Наруч | iron | 1.2 / 2 | 3 | body_mult 1.1; броня |
|  | `Deco_Horns` | `deco_horns` | Рога | bone | 0.8 | 2 | body_mult 1.2 |
|  | `Deco_Pauldron` | `deco_pauldron` | Наплечник | rust_red | 1.5 | 3 | броня; купол ниже по конечности и смотрит наружу — шар плеча виден |
|  | `Deco_Plume` | `deco_plume` | Султан | brass | 0.3 | 1 |  |
|  | `Deco_Spikes` | `deco_spikes_s/l` | Шипастый ошейник | iron | 0.6 / 0.8 | 3 | body_mult 1.25 |
|  | `Deco_Wings` | `deco_wings` | Жестяные крылья | rust_red | 1.2 | 3 |  |
| Навершия | `Anchor_Head` | `anchor_head` | Якорь | iron | 3.2 | 0 | weapon_mult 1.1 (только в оружии), Hook |
|  | `Drill_Head` | `drill_head` | Бур | iron | 2.4 | 0 | weapon_mult 1.45, Blade |
|  | `Pick_Head` | `pick_head` | Кирка | rust_red | 2.6 | 0 | weapon_mult 1.35, Hammer; якорь Face_L |
|  | `Saw_Disc` | `saw_disc` | Дисковая пила | iron | 1.8 | 0 | weapon_mult 1.55, Blade |
|  | `Spear_Tip` | `spear_tip` | Наконечник копья | iron | 0.9 | 0 | weapon_mult 1.5, Blade |
|  | `Torch_Head` | `torch_head` | Факел | wood | 0.9 | 0 | weapon_mult 1.2, Mace |
| Коннекторы | `Joint_Free` | `scenes/body/kit/connectors/free.tscn` | Свободный | — | — | 0 | без коллизий |
|  | `Joint_Motor` | `scenes/body/kit/connectors/motor.tscn` | Мотор | — | — | 8 | без коллизий |
|  | `Joint_Pin` | `scenes/body/kit/connectors/pin.tscn` | Ось | — | — | 0 | без коллизий |
|  | `Joint_Spring` | `scenes/body/kit/connectors/spring.tscn` | Пружина | — | — | 2 | без коллизий |

## 4. Ось материалов — `MaterialDef`

`scripts/body/material_def.gd`: `class_name MaterialDef extends Resource`, файлы `data/body/materials/<id>.tres`.

| поле | смысл |
|---|---|
| `id`, `title` | |
| `surface: Material` | материал для поверхностей `Base_*` (`assets/materials/kit/Base_<Mat>.tres`) |
| `swatch: Color` | цвет плашки в мастерской |
| `density` | множитель массы относительно дерева (дерево = 1.0) |
| `friction`, `bounce` | PhysicsMaterial тела |
| `body_mult` | множитель урона ударом частью из этого материала |
| `iron: bool` | притягивается магнитом Свалки |

Статические функции: `MaterialDef.get_def(id) -> MaterialDef` (кэш) и `MaterialDef.all_ids() -> PackedStringArray` (в порядке таблицы).

| id | Base_ | title | density | friction | bounce | body_mult | iron |
|---|---|---|---|---|---|---|---|
| `wood` | Wood | Дерево | 1.0 | 0.6 | 0.05 | 1.0 | нет |
| `maple` | Maple | Клён | 1.0 | 0.6 | 0.05 | 1.0 | нет |
| `wood_dark` | WoodDark | Орех | 1.15 | 0.6 | 0.05 | 1.05 | нет |
| `planks` | Planks | Доски | 0.9 | 0.65 | 0.05 | 1.0 | нет |
| `paint_red` | PaintRed | Бордовая краска | 1.0 | 0.5 | 0.05 | 1.0 | нет |
| `paint_blue` | PaintBlue | Бирюзовая краска | 1.0 | 0.5 | 0.05 | 1.0 | нет |
| `paint_yellow` | PaintYellow | Горчичная краска | 1.0 | 0.5 | 0.05 | 1.0 | нет |
| `paint_white` | PaintWhite | Белая краска | 1.0 | 0.5 | 0.05 | 1.0 | нет |
| `paint_green` | PaintGreen | Оливковая краска | 1.0 | 0.5 | 0.05 | 1.0 | нет |
| `rust_red` | RustRed | Крашеный лист | 1.6 | 0.55 | 0.1 | 1.1 | да |
| `iron` | Iron | Железо | 2.2 | 0.5 | 0.1 | 1.2 | да |
| `rust` | Rust | Ржавчина | 2.0 | 0.7 | 0.08 | 1.15 | да |
| `brass` | Brass | Латунь | 2.4 | 0.45 | 0.15 | 1.2 | нет (латунь не магнитится) |
| `bone` | Bone | Кость | 0.9 | 0.55 | 0.1 | 1.05 | нет |
| `rubber` | Pink | Резина | 0.8 | 0.9 | 0.6 | 0.8 | нет |

**Краски — не цвета игроков** (29.09, QA на Свалке, §1 «Цвет игрока на ядре»):
- Раньше красная, синяя, жёлтая и зелёная краски совпадали с `Tuning.PLAYER_COLORS` (2f6fde, d9342b, 2e9e4f, e8b820): ΔE2000 3–6. Кукла P1 в красной краске читалась как P2.
- Теперь итоговый цвет (tint × albedo `paint_marks` ~0.82) такой:

| id | цвет | sRGB | ΔE2000 до ближайшего игрока |
|---|---|---|---|
| `paint_red` | бордовый | #701c3c | 26 (P2) |
| `paint_blue` | тёмная бирюза | #1f6e70 | 25 (P3), 27 (P1) |
| `paint_yellow` | горчичный | #8a6a20 | 23 (P4) |
| `paint_green` | оливковый | #5a5a26 | 24 (P3) |

- Id красок прежние: на них ссылаются чертежи и пробы. Названия по новому цвету.
- Tint задаётся в двух местах, их надо держать одинаковыми: `KIT_MATS` в `kit_common.py` и `MATS` в `build_body_kit.gd`.
- Подбирать новую краску так, чтобы ΔE2000 до каждого цвета игрока было ≥ ~20, и проверять на Свалке. `kit_probe` сверяет грубо: ΔE76 от `albedo_color` поверхности до `PLAYER_COLORS` не меньше 30 (сейчас минимум ~38, у прежней красной — 12).
- `rust_red` (крашеный лист, ΔE2000 до P2 ≈ 14) остался красным: это текстура, и тинтом её от красного не увести. На котле фонарщика пояс P2 поэтому еле виден. Кукла при этом читается красной, то есть правильно для P2; у P1 / P3 / P4 пояса на котле видны.

**Правила:**
- Материал узла: `node["mat"]`, иначе `PartDef.base_mat`.
- Деталь без `base_mat` (все старые `wood_*`, `junk_*`, craft) не красится: `mat` для неё — ошибка валидации.
- Масса узла: `def.mass × mat.density / base.density`. Здесь `base = MaterialDef(def.base_mat)`, а если `base_mat == ""`, то просто `def.mass`.

## 5. Изменения API

### 5.1 `PartDef`

- `KINDS` += `"deco"`, `"armor"`. Оба fixed.
- `@export var base_mat := ""` — id MaterialDef по умолчанию; `""` значит, что деталь не красится.
- `@export var connector := false` — на суставе, которым деталь висит на родителе, показывается коннектор. У кита `true`, у старых деталей `false`: у манекена свои шары в меше.
- `material` (wood/iron/cloth) не меняется: его читает магнит.
  - Кто читает: `ScrapMachine` — на запасном пути, для деталей крафтового оружия; `BodyBlueprint._node_iron` — только для старых деталей. У узла кита в ModularDoll железо берётся из `MaterialDef.iron` материала узла.
  - У деталей кита значение пишет Blender-экспортёр (`body_kit.py`, `IRON_MATS`) в `kit_catalog.json`, builder переносит его без изменений: `"iron"` тогда и только тогда, когда у `MaterialDef(base_mat)` `iron = да` (сейчас `iron`, `rust`, `rust_red`), иначе `"wood"`.
  - `IRON_MATS` должен совпадать с колонкой iron в §4. kit_probe это сверяет.
- `body_mult` у детали со своим телом = `Tuning.BODY_MULT[name_prefix]`, в бою его не читают (§3.3). Своё значение — только у декора и брони: бонус к удару телом-хозяином.
- `@export var hit_mult := 1.0` — множитель удара ЭТОЙ формой (шипы, рога, клешня), на материал и таблицу имени умножается (§3.3, §5.4). Только у деталей со своим телом; у старых деталей, декора, брони и наверший — 1.0.
- `weapon_mult` работает только в `CraftedWeapon`.

### 5.2 Типы шарниров — `scripts/body/kit_joint.gd`

`class_name KitJoint`, только константы и статические функции.

```
const TYPES := {
  "pin":    {"title": "Ось",       "k": 1.0,  "tmax": 1.0, "friction": 1.0, "limits": "group",       "energy": 0, "connector": "pin"},
  "free":   {"title": "Свободный", "k": 0.0,  "tmax": 0.0, "friction": 0.3, "limits": Vector2(-160, 160), "energy": 0, "connector": "free"},
  "spring": {"title": "Пружина",   "k": 0.45, "tmax": 0.6, "friction": 0.5, "limits": "group+20",    "energy": 2, "connector": "spring"},
  "motor":  {"title": "Мотор",     "k": 1.8,  "tmax": 2.2, "friction": 1.3, "limits": "group",       "energy": 8, "connector": "motor"},
  "weld":   {"title": "Сварка",    "fixed": true, "energy": 0, "connector": ""},
}
const ORDER := ["pin", "free", "spring", "motor", "weld"]
const RADIUS := {"Neck": 0.05, "Shoulder": 0.064, "Elbow": 0.054, "Wrist": 0.044, "Hip": 0.076, "Knee": 0.066, "Ankle": 0.052}
```

- Ключ узла — `node["joint"]`. Он описывает связь узла с родителем; нет ключа — значит `"pin"`.
- **Нельзя:**
  - шарнир у корня;
  - шарнир у детали, которая fixed по `PartDef`;
  - `weld` у головы;
  - `weld` у узла из `control`;
  - `weld` у узла, у которого есть свой ребёнок на суставе с группой `auto`. Это ради простоты: группа сустава берётся от хозяина;
  - `motor` и `spring` на суставе группы без мышцы (k = 0 в `Tuning.MUSCLE_GROUPS`; сейчас это `Ankle`: стопы, третий сегмент ноги, «прочие» якоря). Там они стоили бы энергию и ничего не давали: мышца × 0.
    - Группа берётся по якорю (`BodyBlueprint.anchor_group_of`), даже если узел сейчас сварен.
    - `free` на таком суставе можно.
- **Сварка держит позу покоя сустава** (`ModularDoll._weld_rest`). Деталь сливается с родителем, повёрнутая вокруг точки сустава на угол покоя:
  - угол — `rest_deg` узла, иначе `Tuning.POSE` группы якоря (`rest_from_pose`), иначе `rest_deg` якоря; у зеркальной стороны знак меняется;
  - плечо, сваренное на `Shoulder_*`, торчит под 85°, а не висит вниз;
  - `rest_deg` узла при переключении на weld не стирается, поэтому возврат к pin восстанавливает прежний угол;
  - fixed по `PartDef` (декор, броня, навершия) ставится по якорю без угла, как раньше;
  - призрак мастерской и `CraftEdit.rest_rel_deg` считают так же.

### 5.3 `BodyBlueprint`

- `func is_fixed(uid) -> bool`: есть родитель и (`def.attach == "fixed"` или `node.joint == "weld"`). **Все** проверки `attach == "fixed"` в `scripts/body`, `scenes/workshop` и `tests/body_probe.gd` идут через него.
  - Исключение — `arm_assist.gd`: он не наш. Weld запрещён для control-узла, поэтому ему это не нужно.
- `func node_mat(uid) -> String` и `func node_mass(uid) -> float` (§4).
- `func joint_type_of(uid) -> String`.
- `total_mass()` = Σ `node_mass`.
- `energy_used()` = Σ `node_energy(uid)`: (`def.energy` + `KitJoint.TYPES[joint].energy`) × `reach_mult(d)`, где d — вынос детали от ядра по цепочке (`node_reach`), `reach_mult = 1 + max(0, d − 0.3)` (энергия по расстоянию, `WORKSHOP_V3.md` §2, 30.09).
- `validate()` / `_validate_assembly()` дополнительно проверяют:
  - `mat` — известный id, и у детали есть `base_mat`;
  - `joint` — известный тип и допустим по §5.2;
  - `accepts` у якорей с новыми видами;
  - узел из `control` — не fixed. Иначе ArmAssist искал бы тело, которого нет, и рука мышью молча пропала бы (навершие вместо управляемой кисти). Текст ошибки: «рука мышью на «…» — у детали нет своего тела».
- `func anchor_group_of(uid)` — группа, которую якорь родителя дал бы узлу со своим суставом, в том числе сваренному (`joint_group_of` у сваренного пуст).
  - Её используют угол покоя сварки и запрет мотора без мышцы.
  - Поиск группы защищён от циклов родителей: `validate()` зовёт его до проверки цепочки. Предел глубины — 2 × число узлов.
- `func name_prefix_of(uid)` — префикс имени тела: у конечности кита на локте / колене `LowerArm` / `LowerLeg`, иначе `PartDef.name_prefix` (§3.5). Через него работают `body_name_of` и `CraftEdit._replace`.
- Имена тел и суставов не меняются. Тип шарнира **не** кодируется в имени: группа мышц идёт от имени.

### 5.4 `ModularDoll`

- **Сразу после `_mirror_part`** (узел ещё не слит):
  - если у детали есть `base_mat` и `node_mat != base_mat` — всем MeshInstance3D под инстансом заменить поверхности, у которых `get_active_material(s).resource_name` начинается на `Base_`, на `MaterialDef.surface` (`set_surface_override_material`);
  - `physics_material_override` = PhysicsMaterial(friction, bounce) материала узла. Это только у собственного тела; слитая деталь берёт физматериал хозяина;
  - масса = `bp.node_mass(uid)`, и для собственного тела, и для слияния.
- **Weld:** узел с `joint == "weld"` сливается с родителем так же, как fixed-деталь (`_merge_into`), но в позе покоя своего сустава (§5.2, `_weld_rest`).
  - Кадр детали поворачивается до записи в `info`, поэтому повёрнутый кадр получают дети, слияние, центр масс и пол.
- **Коннектор:** если `def.connector` и тип не `weld` — ребёнок тела-ребёнка (дистального) `Connector_<uid>`:
  - инстанс `scenes/body/kit/connectors/<connector>.tscn`;
  - в точке сустава, масштаб `anchor.joint_r` (meta якоря), иначе `KitJoint.RADIUS[группа]`, иначе 0.05;
  - meta `rig_mesh = true`;
  - добавляется **до** `super._ready()`, иначе `_recolor` не покрасит его в цвет игрока;
  - при зеркале коннектор ставится в зеркальную точку. Сам коннектор симметричен, поэтому трансформ не отражается.
- **Сустав:** `_make_joint`:
  - `force_limit` и meta `friction_factor` умножаются на `friction` типа;
  - лимиты по `limits` типа;
  - meta `joint_type`.
- **Мышцы:** переопределить `_update_pair_gains()`. Сначала `super()`, затем для каждой пары с типом ≠ pin умножить `k` и `tmax` на множители типа, а `c` — на √(k-множителя), если только не задан единый `c`. Для `free` k = c = tmax = 0. Так настройка переживает все вызовы Doll: `_ready`, `set_muscle_group`, `set_muscle_joint` (оружие в руке) и другие.
- **Meta тел:**
  - `material` = кг железа в теле (float): сумма `node_mass` узлов этого тела, собственного и слитых, чей материал iron. Для старых деталей iron значит `PartDef.material == "iron"`. Магнит `ScrapMachine.iron_mass` принимает число.
  - `body_mult` ставится, только если он отличается от `Damage.body_mult_of(name)`. Значение = `Damage.body_mult_of(name) × mat.body_mult × PartDef.hit_mult ×` Π `body_mult` слитых деталей вида `deco`/`armor` с `body_mult ≠ 1`. `mat` и `hit_mult` — узла, чьё это тело. `Damage.body_mult_of_body` (хук боевой сессии, 29.09) читает эту meta.
  - `PartDef.body_mult` детали со своим телом сюда не входит: он равен таблице (§3.3).
  - `hit_mult` сваренного узла со своим телом тоже не входит, как и его материал: удар — хозяина.
  - `weapon_mult` слитого навершия тоже не входит: бур у `kit_lantern` добавляет предплечью массу и формы, а удар остаётся «предплечье × железо» (как у шара булавы на цепи кистеня).
- **Цвет игрока:** `_recolor` переопределён (тот же цикл, что `Doll._recolor`, но одна копия материала на исходный материал, а не на каждую поверхность).
  - Причина: `Shirt_Kit` есть на каждой детали и на каждом коннекторе (13–19 шаров). У Doll выходило 25–37 одинаковых материалов на куклу, а headless dummy-рендер при освобождении каждой куклы кита писал «Parameter "material" is null».
  - Альфа своя у каждого исходника.
- `STRIKER_KINDS` не меняются: декор бьёт телом-хозяином.

### 5.5 Мастерская

**Полки** (`CraftEdit.BODY_SHELVES`):

| id | Вкладка | Что внутри |
|---|---|---|
| `core` | Ядро | ядра |
| `head` | Головы | головы |
| `limb` | Конечности | конечности |
| `end` | Кисти, стопы | кисти и стопы |
| `joint` | Шарниры | инструмент выбора типа шарнира (`tool: "joint"`) + детали `joint`, `chain` |
| `armor` | Броня, декор | `plate`, `armor`, `deco`, `mod`, `weapon_head` (навершия: якоря кита их принимают — ANY_LIMB, а другой полки у тела нет) |
| `mat` | Материал | инструмент-кисть (`tool: "material"`) |

- `KIND_ORDER` и `KIND_TITLES` дополняются новыми видами: `armor` — «броня», `deco` — «декор»; `plate` теперь «щиток» (слово «броня» занял `armor`).
- Детали `kit_human_*` на полках не показываются (`CraftEdit.SHELF_HIDDEN_PREFIXES`, фильтр в `all_parts()`): это дубли `wood_*` под риг v3 для пресета `kit_human`, на полке они неотличимы от `kit_limb_basic_*` / `kit_core_barrel`. Чертежи с ними грузятся как обычно.
- Шаблоны тела (`CraftEdit.BODY_PRESETS`) — 7 старых и 10 пресетов кита (§3.5), 6 рядов по 3 кнопки.
- **Кисть материала:**
  - плашки `ui/material_card.gd`: цвет, название, «плотность ×N» (дерево = 1), трение, упругость, «магнит»;
  - масса детали меняется как `новая плотность / прежняя` (§4): «масса × плотность» было бы неверно для всего, что не из дерева. Точные «было → станет» показывает подсказка при наведении;
  - выбор задаёт `paint_mat`; клик по детали на стенде вызывает `set_material(uid, mat)`: история, `node["mat"]` (для материала по умолчанию ключ стирается), пересборка;
  - Esc и ПКМ сбрасывают режим.
- **Шарниры:** плашки типов с описанием того, как ведёт себя сустав. Клик по детали вызывает `set_joint(uid, type)` — это связь с родителем. У корня и там, где нельзя по §5.2, — отказ с причиной.
- `CraftEdit.signature` включает `mat` и `joint`.
- `_replace` сохраняет `mat`, только если у новой детали есть `base_mat`.
- `_replace` в остальном:
  - явное имя тела сохраняется, если на этом месте не поменялся префикс (`name_prefix_of`): «LowerArm_L» переживает замену предплечья на конечность кита размера S;
  - если заменённая деталь стала fixed (навершие вместо управляемой кисти), рука мышью переезжает на тело-хозяина, как у `set_control`. Если хозяин — ядро, пометка снимается и `warnings()` подсказывает;
  - `weapon_on` в этом случае переходит в другую кисть (`weapon_mount`).
- Масса и разгон в статистике считаются через `node_mass`.
- Манекен испытания (`training_dummy.gd`): запас HP — `Doll.max_hp` его куклы (`max_hp()`; сигнал `hp_changed` несёт его же). HP-табличка `workshop_ui.gd` берёт максимум оттуда (`_dummy_max_hp`: `max_hp()` манекена, иначе поле `max_hp` куклы, иначе `Tuning.MAX_HP`).
- Подсказки карточек показывают материал по умолчанию и его физику. Множитель удара — тот, что в бою:
  - у детали со своим телом — таблица по префиксу × материал по умолчанию × `hit_mult` («бьёт сильно (×2.5, ржавчина)» у кулака); форма — отдельной строкой словами: «шипы: удар ×1.3», «клешня: удар ×1.15», «мягкая верёвка: удар ×0.85» (`PartCard.HIT_WORDS`, иначе «форма»);
  - у декора — «удар хозяином ×1.25»;
  - навершие на полке тела: «на теле: только масса и форма (урон оружия ×N — в оружии)» (`PartCard.setup(d, on_body)`).
- Отказы шарниров и «приваренного конца» — словами игрока, с названиями деталей, без uid, имён якорей и «auto».
  - Перевод делают `CraftEdit._joint_refusal`, а для приваренного родителя — `check()` с кодом `welded`. Запасная сетка — `_friendly`.
  - Строки `BodyBlueprint.joint_error` не меняются: это диагностика validate(), kit_probe сверяет их по подстрокам.

## 6. Физика декора и брони

- `deco` и `armor` — fixed. Масса складывается с хозяином, центр масс сдвигается.
- Коллизии декора добавляются хозяину. Рога, наплечник и шипы правда бьются и цепляются.
- Шипы (`deco` с `body_mult` > 1) усиливают удар хозяином через meta `body_mult`.
- Флажок и корона — лёгкие, почти косметика: 0.3–0.6 кг.

## 7. Проверки

**`tests/kit_probe.gd`** (новый, headless):
- все `kit_*` PartDef валидны: сцена, Socket (не у ядра), якоря с правильной meta, масса сцены == PartDef.mass, есть `Mesh` и форма; attach `fixed` — у декора, брони и наверший (`weapon_head`, энергия 0);
- материалы поверхностей пришли из `assets/materials/kit` (пост-импорт сработал);
- у каждого ядра есть `Shirt_Kit` (пояс цвета игрока, §1); краски `paint_*` не ближе ΔE76 30 к `Tuning.PLAYER_COLORS` (§4);
- `kit_human` совпадает с `human` по массам, формам, суставам и позе;
- каждый пресет `kit_*` (все 10 из §3.5) собирается, стоит, двигается (≥ 0.5 м под вводом), после KO разваливается;
- `mat`: масса меняется на density, физматериал, meta `material`, поверхность Base_ заменена;
- `joint`: free — k = 0, motor — k ×1.8 после `set_muscle_joint`, weld — тел на одно меньше;
- коннекторы есть, у них цвет игрока, коллизий нет;
- декор-шипы — meta `body_mult`;
- `body_mult` деталей со своим телом = `Tuning.BODY_MULT[name_prefix]`;
- `hit_mult`: у каждой детали кита со своим телом = `hit_mult` каталога (нет ключа — 1.0) и таблице §3.3; у fixed и `kit_human_*` — 1.0; в каждом пресете meta `body_mult` = таблица × материал × `hit_mult` (× шипы); `kit_devil` — явными числами (плечо / предплечье × 1.3, голова × 1.15, клешня × 1.15, кулак × 1.1);
- кисть: начало тела в центре форм, `Socket` над формами; хват `WeaponPickup.hand_grip_offset` внутри формы у каждой кисти-детали и у каждой кисти каждого пресета;
- конечность: `Grip` в точке `Anchor_End`;
- рука мышью на каждом пресете (своя площадка):
  - на кисти — хват в ладони, досягаемость не короче human − 5 см;
  - `kit_lantern` / `kit_king` — хват в `Grip`, досягаемость ≥ 0.55 м; цель в 0.5 м от плеча в 7 направлениях достигается за 3 с (ошибка ≤ 0.25 м, средняя ≤ 0.15 м);
- validate отказывает:
  - мотор / пружина на лодыжке;
  - рука мышью на fixed-узле;
- цикл родителей с мотором на auto-якоре — без бесконечной рекурсии; длинная цепь (6 конечностей) — группы до конца;
- сварка предплечья `kit_human` — запястье в позе покоя локтя (10°, правая сторона).

**`workshop_probe`, правки ревью 29.09:**
- навершие вместо управляемой кисти (`kit_devil` — бур, `human` — шар булавы): рука мышью на предплечье, и в испытании ArmAssist его ведёт;
- бур вместо управляемого плеча: пометка снята;
- мотор на стопе — отказ;
- тексты отказов без uid, `Anchor_` и `auto`;
- конечность кита на локте — тело `LowerArm_<uid>`.

**`body_probe`:** F10 на площадке тела листает пресет эффектов, а не пресет тела; F11 — пресет 11.

**Прежние пробы** должны остаться зелёными: `body_probe`, `craft_probe`, `workshop_probe` (сюда же `mat_*` / `joint_*`), `arm_assist_probe` (известный чужой красный `throw_flies`), `scrap_machines_probe` (33 проверки, в т. ч. кукла с железной рукой через ModularDoll и meta `material` — просьба сессии Свалки). Когда появится `tests/pve_probe` (враги сессии «Определение игры и планы» — ModularDoll по чертежам `data/enemies/*.tres` из деталей `junk_*`/`wood_*`/`handle_long`), гонять и её: формат BodyBlueprint и id старых деталей не меняем, новые ключи узла только необязательные.

**Визуально:**
- `body_probe` в режиме `shot=` с окном — сетка пресетов. `docs/plan-demo/img/body-kit-v1-presets.png` — кадр `shot=…,only=kit_` при 1920×1080, обрезанный до сетки: (196, 128)–(1724, 1012);
- `workshop_probe` `shots=` — мастерская с китом;
- **цвет игрока — только на Свалке** (`scenes/arena/scrap.tscn`, игровая камера и свет). Ряды пресетов с игровой камерой, затем при полувысоте 4 м, со сдвигом индекса игрока 0…3: у каждой куклы должен читаться её цвет, и ни одна не должна читаться цветом другого игрока. Скрипт — scratch-сцена сессии кита (`SceneTree` по `-s /abs/path`, в проект не входит). `docs/plan-demo/img/body-kit-v1-arena.png` — его кадр `doc` (ряд 1, сдвиг 0).

## 8. Для соседей

- **Магнит (Свалка v2):** ModularDoll пишет meta `material` = кг железа (float) в каждое тело. `ScrapMachine.iron_mass` уже умеет число.
- **Боевая сессия:** meta `body_mult` на телах кита (хук `body_mult_of_body` уже внесён).
  - Просьба 29.09: `Doll.centre_of_mass()` и `FlightTrail` берут `b.global_position` тела. У деталей кита (кроме кисти) начало тела — `Socket` (шея, плечо, бедро), а не центр, поэтому ЦМ куклы кита выше настоящего на 2–8 см, а следы головы и кистей начинаются от суставов.
  - Как исправить: брать `b.global_position + PhysicsServer3D.body_get_direct_state(b.get_rid()).center_of_mass`. Это покрывает и AUTO, и CUSTOM (слитые детали). `b.to_global(b.center_of_mass)` не годится: в режиме AUTO свойство равно (0, 0, 0).
  - У `wood_*`, `junk_*` и `kit_human` числа не изменятся.
  - Удар формой кит-деталей (шипастая, рога, клешня, кулак…) сделан полем `PartDef.hit_mult` (§3.3, 29.09): оно входит в ту же meta `body_mult`, `Damage` менять не нужно. Числа — стартовые, баланс за боевой сессией и автором.
- **Заставка:** `mannequin_v3` не трогаем.

## 9. Потом, по согласованию

- Перевести `doll.tscn` / `doll_dark.tscn` на вид кита «Человек». Имена, массы и формы те же, меняется только `Mesh`. Сначала снять с боевой сессией её `snapshot`- и `combat`-гейты.
- Куклы заставки — **не нужно**: 29.09 автор забраковал заставку по сюжету, работа остановлена. Если её сделают заново, то сразу на ките; сессия заставки напишет перед началом.
- Фото лица на `FacePlate` (этап 10).
