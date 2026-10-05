# Задание на генерацию 3D-ассетов ИИ (04.10.2026)

> **Обновление 04.10, вечер.** Автор прислал три листа-концепта («Профессиональная лига Земли», «Аоэлюн — живые модули», «Утилиты и аренные модули») и попросил добавлять детали в игру и закрывать проблемы из раздела 8. Первая партия построена **скриптами Blender**, без генерации 3D нейросетью — итог в `KIT_SETS.md`; броня и поломка деталей — в `ARMOR_BREAK.md`. Списки ассетов раздела 5 ниже написаны до листов: листы автора важнее, партии A и B частично ими заменены.

**Статус: предложение [П], автор не утверждал.** Основа — разбор каталога деталей (`docs/catalog/index.html`, сборка 0.0.2, `8a7c23f`): 157 деталей, 15 материалов, 14 видов оружия, 25 бойцов, 2 врага.

Цель партии — сделать игру «взрослее»: меньше детской, больше спорта, железа и чужой живой угрозы. Дерево и ручная покраска остаются — это язык самого спорта. Добавляются три вещи, которых сейчас нет: профессиональный спортивный кит Земли, живой кит Аоэлюн и настоящая броня.

## 0. Как это совмещается с правилами проекта

- `ASSET_PIPELINE.md`, правило 1: все модели — из скриптов Blender. `ART_DIRECTION.md` (28.09): «не брать AI-генерацию 3D» — это про куклу целиком (единый меш без частей).
- Здесь ИИ делает **одну деталь = один объект**, поэтому возражение про «единый меш» не действует. Но правило 1 задание всё равно нарушает: исходником формы становится файл генератора, а не скрипт. **Это решение автора.**
- Смягчение: сырой файл генератора в игру не попадает. Его обрабатывает скрипт Blender (нужно написать, рабочее имя `godot/tools/blender/kit_ai.py`), а обвязку кита — обойму, шар сустава, плашку лица, окошко ядра, пояс цвета игрока, пустышки — ставят готовые функции `kit_common.py`. Сырьё хранится рядом со скриптом и коммитится.

## 1. Что делает ИИ, а что нет

| Делает ИИ | Делает скрипт (не просить у генератора) |
|---|---|
| форму корпуса одной детали | шар сустава и обойму у сокета |
| крупный рельеф: швы, вмятины, рёбра, шипы, пластины | плашку лица `FacePlate` (фото пилота) |
| для класса U — свою текстуру | окошко ядра `CoreGlow` |
| | пояс и полоски цвета игрока `Shirt_Kit` |
| | масштаб, поворот, origin, упрощение сетки |
| | пустышки `Socket`, `Anchor_*`, `Shape_*` |

Два класса деталей — класс указан у каждого ассета:

- **Класс M (перекрашиваемая).** От генератора нужна только форма. Текстуру генератора выбрасываем, скрипт кладёт UV «2 тайла на метр» и роль `Base_<Mat>`. Деталь работает с осью материалов: 15 материалов, масса и удар пересчитываются. Подходит простым формам из одного материала.
- **Класс U (уникальная).** Текстура генератора остаётся, деталь не перекрашивается — как детали лиги и хлам. Подходит живым и сложным деталям.

Повреждённые состояния деталей (трещины, вмятины, обгорание) ИИ **не генерирует**: генератор не повторит ту же деталь «чуть сломанной». Их надо делать скриптом из готового меша.

## 2. Общий стиль — блок в начало каждого промпта

Лучше работает цепочка «картинка → 3D»: сначала картинка-концепт по промпту, автор отбирает, потом генерация 3D по картинке. Промпты ниже годятся и для «текст → 3D».

```
single game asset, one detachable body part of a modular fighting robot,
stylized PBR, chunky readable silhouette, slightly exaggerated proportions,
hard-surface with soft bevelled edges, built by hand and repaired many times:
scratches, chipped paint, weld seams, dents, oil stains, mismatched bolts,
solid watertight object, centered, front three-quarter view,
plain neutral grey background, soft even studio light
```

Запреты — в поле negative или в конец промпта:

```
no text, no letters, no logos, no numbers, no character, no full robot, no hands holding it,
no stand, no base, no ground, no thin wires, no floating pieces, no glass, no transparency,
no baked shadows, no strong highlights, not photorealistic, not low-poly, not cartoon toy
```

Три наречия партии — добавлять после общего блока:

| Набор | Добавка к промпту |
|---|---|
| **Про-лига Земли** | `regulation sports equipment for a zero-gravity combat league, motorsport and hockey gear feel, carbon fibre, anodized aluminium, painted steel, rubber bumpers, exposed fasteners, no decoration` |
| **Аоэлюн** | `grown not built: a living modular organism part, dark chitin plates over deep red muscle tissue, bone-white spikes, faint violet bioluminescent seams, segmented like a machine part, unsettling but clean, not gore` |
| **Лига NULL** | `alien engineering, near-black glossy void metal with violet sheen, thin violet light seams, cyan sensor lens, brass emitters, floating ring near the joint` |

Цвета лиги и Аоэлюн уже заданы ролями в `kit_league.py` (`League_Void`, `League_Glow`, `League_Cyan`, `League_Crystal`, `League_Gold`, `League_Flesh`) — концепты сверять с `img/league-parts-v2.jpg`.

## 3. Требования к файлу из генератора

1. Формат **GLB**, один объект, один материал. Карты: base color, normal, roughness, metallic, **1024 или 2048**.
2. Сетка сырья — до 50 000 треугольников. В игру идёт упрощённая: **≤ 3000 на деталь, ≤ 6000 на ядро** (бюджет кита; сейчас медиана 1784, максимум 5928). Мелкий рельеф уходит в карту нормалей при запекании.
3. Albedo без света и теней (если у генератора есть режим delight / unlit — включить).
4. Деталь стоит вертикально, длинная ось вверх, лицевая сторона к камере.
5. Головы, ядра, стопы — **симметричны слева направо**. Правая сторона куклы получается зеркалом левой, поэтому надписи и стрелки запрещены: отразятся.
6. Нет элементов тоньше 8 мм и нет отдельно висящих кусков: физика детали — 1–3 простые формы (капсула, коробка, шар).
7. У сокета оставить чистую шейку или торец: туда встанут обойма и шар сустава.
8. У головы спереди — ровная или слегка выпуклая площадка под лицо, примерно **0.20 × 0.16 м**: экран, забрало, перепонка.
9. У ядра спереди — круглое место под окошко ядра Ø ≈ 0.12 м и свободный пояс под цвет игрока (не меньше 15 % силуэта).

## 4. Габариты по видам

Размеры — по деталям кита из каталога (ширина × высота × глубина, м). Скрипт подгонит масштаб, но пропорции должны попадать.

| Вид | Типичный габарит | Предел | Как растёт от сокета |
|---|---|---|---|
| Голова | 0.38 × 0.43 × 0.29 | 0.60 × 0.63 × 0.44 | вверх |
| Ядро | 0.45 × 0.54 × 0.42 | 0.69 × 0.65 × 0.69 | центр в середине |
| Рука (S) | 0.13 × 0.26 × 0.11, длина между шарнирами 0.30, радиус 0.058 | 0.23 × 0.45 × 0.18 | вниз |
| Нога (L) | 0.17 × 0.36 × 0.14, длина 0.42, радиус 0.074 | 0.27 × 0.61 × 0.23 | вниз |
| Кисть | 0.15 × 0.19 × 0.10 | 0.16 × 0.34 × 0.15 | вниз |
| Стопа | 0.13 × 0.09 × 0.17 | 0.20 × 0.15 × 0.28 | вниз, носок к камере |
| Броня / декор | 0.20 × 0.21 × 0.21 | — | надевается на конечность радиусом 0.058 / 0.074 |
| Навершие | 0.29 × 0.44 × 0.08 | 0.39 × 0.71 × 0.17 | вверх от рукояти |

Руку и ногу одного типа генерировать **один раз**: скрипт сделает оба размера масштабом.

## 5. Ассеты

Имена — по контракту кита (`BODY_KIT.md` §1): `Head_*`, `Core_*`, `Limb_*`, `Hand_*`, `Foot_*`, `Deco_*`, навершия — `*_Head`. Русские названия — рабочие.

### Партия A — Про-лига Земли (14). Взрослый спорт вместо игрушки

Сейчас земной кит — бочка, ящик, игрушка, корова, чёртик, корона. Это нижняя ступень карьеры. Верхней ступени — машин клубов с деньгами — нет.

| Имя | Вид, класс | Что это | Промпт (после общего блока и добавки «Про-лига») |
|---|---|---|---|
| `Head_Pro_Visor` | голова, M | шлем пилота с широким экраном-забралом | `robot head shaped like a racing helmet, wide flat visor screen on the front, side air intakes, chin guard, short neck collar` |
| `Head_Pro_Cage` | голова, M | маска-решётка, как у вратаря | `robot head like a hockey goalie mask with a steel cage over a flat face panel, padded sides, strap anchors` |
| `Head_Pro_Sensor` | голова, M | низкая плоская голова-датчик | `low flat sensor head, armored camera housing with a flat front panel and two side lens pods, ribbed heat sink on top` |
| `Core_Pro_Frame` | ядро, M | трубчатая рама с капсулой ядра | `torso built as a welded tubular roll cage around an armored capsule, round port in the chest, four mounting hubs at shoulders and hips` |
| `Core_Pro_Shell` | ядро, M | монокок, литая скорлупа | `torso as a one-piece carbon monocoque shell, smooth chest with a round port, recessed belt groove around the waist, vent slots on the back` |
| `Core_Pro_Tank` | ядро, M | тяжёлый бронекорпус | `heavy armored torso block, bolted steel plates over a cylinder core, round chest port, reinforced shoulders, tow hooks` |
| `Limb_Pro_Strut` | конечность, M | карбоновая стойка | `straight carbon fibre strut limb segment with aluminium end caps and a thin rubber bumper ring` |
| `Limb_Pro_Hydra` | конечность, M | гидроцилиндр в кожухе | `limb segment: thick hydraulic cylinder inside a slotted armored sleeve, hose stub, end clamps` |
| `Limb_Pro_Truss` | конечность, M | лёгкая ферма | `limb segment as a short triangular truss of welded tubes with gusset plates, solid ends` |
| `Hand_Pro_Striker` | кисть, M | ударная перчатка | `robot fist like a boxing glove made of layered rubber and steel knuckle plate, wrist cuff` |
| `Hand_Pro_Grip` | кисть, M | трёхпалый захват | `three-finger industrial gripper hand, thick short fingers with rubber pads, compact palm block` |
| `Foot_Pro_Blade` | стопа, M | беговое лезвие-протез | `running blade foot, curved carbon spring blade with a rubber tread strip, clamp block on top` |
| `Foot_Pro_Pad` | стопа, M | амортизирующая лапа | `wide shock-absorbing foot pad, layered rubber sole, short piston ankle, steel toe cap` |
| `Deco_Pro_Fin` | декор, M | спинной киль-стабилизатор | `dorsal stabilizer fin with a mounting plate, perforated aluminium, rubber edge` |

### Партия B — Аоэлюн, живой кит (12). Угроза, которой не хватает

По канону (`LORE_V2.md` 2б, п. 6–7) Аоэлюн — живой адаптирующийся организм, «модульная кукла без пилота». Сейчас живых деталей три: голова, ядро и щупальце (S / L). Врагов для PvE — два, Разборщик из хлама и Уборщик из клёна с железом. Полного живого тела собрать не из чего.

| Имя | Вид, класс | Что это | Промпт (после общего блока и добавки «Аоэлюн») |
|---|---|---|---|
| `Head_Aoe_Crest` | голова, U | гребень и одна перепонка-лицо | `head: smooth chitin crest sweeping back, a flat stretched membrane on the front framed by short mandibles, no eyes` |
| `Head_Aoe_Cluster` | голова, U | гроздь глаз под панцирем | `head: low armored dome with a cluster of small glowing eyes around a flat front membrane, two bone hooks at the jaw` |
| `Core_Aoe_Ribcage` | ядро, U | грудная клетка наружу | `torso: external rib cage of bone arches over a dark red sac, round glowing organ in the chest, chitin spine ridge` |
| `Core_Aoe_Pod` | ядро, U | гладкий кокон | `torso: smooth egg-shaped chitin pod split by glowing seams, round organ port in front, four fleshy mounting stumps` |
| `Limb_Aoe_Sinew` | конечность, U | жила в хитиновых кольцах | `limb segment: twisted bundle of dark red sinew held by three chitin rings` |
| `Limb_Aoe_Plate` | конечность, U | бронированный сегмент | `limb segment: thick overlapping chitin plates like a lobster tail, bone studs along the outer edge` |
| `Limb_Aoe_Blade` | конечность, U | сегмент с костяным лезвием | `limb segment with a long curved bone blade growing along one side, dark muscle core, chitin cuffs` |
| `Hand_Aoe_Hook` | кисть, U | два костяных крюка | `hand: two heavy curved bone hooks on a knot of muscle, chitin wrist cuff` |
| `Hand_Aoe_Maw` | кисть, U | кисть-пасть | `hand shaped like a small three-jawed maw with bone teeth, closed, chitin wrist cuff` |
| `Foot_Aoe_Hoof` | стопа, U | раздвоенное копыто | `foot: split chitin hoof with a bone spur at the heel` |
| `Deco_Aoe_Arc` | декор, U | **незамкнутая дуга на плечо** | `shoulder ornament: an open bone arc, an incomplete ring with a gap, growing from a small chitin base` |
| `Deco_Aoe_Spines` | декор, U | спинные иглы | `back ornament: a row of five bone spines of different length on a chitin plate` |

`Deco_Aoe_Arc` — знак Сборщика из сюжетного предложения (`narrative-proposal/03-characters.md`); это [П], не канон.

### Партия C — добор лиги с листов автора (8)

На листах 3–4 (`ART_NULL.md`) — 24 головы, 12 корпусов, около 18 конечностей, около 20 видов оружия, 16–20 шарниров. Сделано 29 деталей; шарниров лиги нет совсем.

Коннекторам лиги нужна правка кода: сейчас вид шара выбирается по типу шарнира (`KitJoint.TYPES`), а не по набору детали.

| Имя | Вид, класс | Что это | Промпт (после общего блока и добавки «Лига NULL») |
|---|---|---|---|
| `Joint_League_Ring` | коннектор | шар в кольце поля | `joint connector: a small dark sphere inside a thin floating energy ring` |
| `Joint_League_Crystal` | коннектор | шар-кристалл | `joint connector: a faceted crystal sphere held by three brass claws` |
| `Joint_League_Magnet` | коннектор | магнитный замок | `joint connector: two dark hemispheres with a glowing gap between them, magnetic lock` |
| `Head_League_Helm` | голова, U | шлем-яйцо с одним объективом и рогами-антеннами | `egg-shaped helmet head, one large lens above a flat dark front panel, two swept-back antenna horns` |
| `Core_League_Cube` | ядро, U | кристаллический куб в раме | `torso: a large crystal cube held in a dark metal frame with brass corners, round port in front` |
| `Scythe_League_Head` | навершие, U | коса | `weapon head: a long curved scythe blade of dark metal with a glowing violet edge, brass socket` |
| `Trident_League_Head` | навершие, U | трезубец | `weapon head: a trident with three crystal prongs on a dark metal collar` |
| `Chakram_League_Head` | навершие, U | кольцо-чакрам | `weapon head: a flat ring blade with a glowing inner edge and a short grip spoke` |

### Партия D — оружие (10)

Рукоятей две, модов два, готового оружия арены пять. Наверший — 14, но ставить их почти не на что.

| Имя | Вид, класс | Что это | Промпт (после общего блока) |
|---|---|---|---|
| `Handle_TwoHand` | рукоять, M | длинная двуручная | `long two-handed weapon shaft, steel tube with two wrapped rubber grips and a pommel cap` |
| `Handle_Bent` | рукоять, M | гнутая, как у клюшки | `weapon shaft with a slight forward bend near the top, laminated wood with a steel sleeve` |
| `Handle_Tele` | рукоять, M | телескопическая | `telescopic weapon shaft, three nested steel tubes, locking collars` |
| `Mod_Counterweight` | мод, M | противовес | `weapon attachment: a clamp-on steel counterweight block with two bolts` |
| `Mod_SpikeRing` | мод, M | кольцо шипов | `weapon attachment: a steel ring collar with six short thick spikes` |
| `Mod_Booster` | мод, M | реактивный ускоритель | `weapon attachment: a small strap-on rocket booster with a scorched nozzle and a clamp` |
| `weapon_sledge` | оружие арены | кувалда | `heavy sledgehammer, steel head with chipped paint, long wooden handle with tape wrap` |
| `weapon_wrench` | оружие арены | большой гаечный ключ | `oversized adjustable pipe wrench, worn red paint, heavy jaw` |
| `weapon_crowbar` | оружие арены | монтировка | `long steel crowbar with a hooked end and a flat pry tip, blue-black steel` |
| `weapon_shield` | оружие арены | щит-дверца | `improvised riot shield cut from a steel door panel, welded handle, hazard stripe paint worn off` |

Оружие арены: origin — точка хвата, оружие вытянуто вдоль +X, бюджет ≤ 4000 треугольников (`ASSET_PIPELINE.md`).

### Партия E — броня (6)

Брони шесть штук, вся на конечности. На ядро и голову ничего нет. В бою броня сейчас ничего не защищает (раздел 8).

| Имя | Вид, класс | Что это | Промпт (после общего блока) |
|---|---|---|---|
| `Deco_Chestplate` | броня, M | нагрудник на ядро | `curved chest armor plate with a round cutout in the center, riveted edge, two strap lugs` |
| `Deco_Backplate` | броня, M | спинная плита | `back armor plate with vertical ribs and a carrying handle, riveted edge` |
| `Deco_Helmet_Shell` | броня, M | каска поверх головы | `open-face helmet shell that sits on top of a head, dented steel, chin strap lugs, no visor` |
| `Deco_Kneeguard` | броня, M | наколенник | `knee guard cup with a hinge plate and a rubber pad, sized for a thick limb` |
| `Deco_Shinguard` | броня, M | щиток голени | `long shin guard plate, slightly curved, two strap bands, scuffed paint` |
| `Deco_Cage_Guard` | броня, M | решётка-рукав | `forearm guard made of four bent steel bars over a leather sleeve` |

Итого 50 ассетов. Порядок — раздел 7.

## 6. Приёмка одной детали

Цифры проверяются скриптом, вид — автором.

1. GLB открывается в Blender без ошибок; один объект, один материал.
2. После обработки: треугольников ≤ 3000 (ядро ≤ 6000, оружие арены ≤ 4000), габарит в пределах раздела 4.
3. Симметрия у голов, ядер, стоп: отклонение левой половины от правой ≤ 5 мм.
4. Нет текста, логотипов, цифр на текстуре.
5. Деталь читается на игровом расстоянии: проверять на арене при полувысоте кадра 3.6–4 м (правило `BODY_KIT.md` §1), а не на сером фоне.
6. Цвет игрока виден: пояс на ядре ≥ 15 % силуэта спереди.
7. Набор A не спорит с цветами игроков: `kit_probe` сверяет краску с `Tuning.PLAYER_COLORS`.
8. Гейты кита зелёные: builder без ошибок, `tests/kit_probe.tscn`, `tests/part_names_probe.tscn` (имя детали добавлено в `PartNames.NAMES`), пробы i18n из `AGENTS.md`.
9. Каталог пересобран (`godot/tools/catalog_export.tscn` → `build_catalog.py`), деталь в нём есть.

## 7. Порядок работы

1. **Пилот — три детали:** `Limb_Pro_Strut` (самая простая, класс M), `Head_Pro_Visor` (площадка под лицо), `Core_Aoe_Ribcage` (класс U, самая сложная). На них пишется `kit_ai.py` и проверяется весь путь до игры.
2. Автор смотрит пилот в игре и решает, годится ли качество и снимается ли правило 1 для деталей.
3. Дальше партиями: B (угроза и PvE), A (верх карьеры), E, D, C.

Шаги обработки одной детали в `kit_ai.py` (нужно написать):

1. Импорт сырья, склейка в один объект, удаление мусора.
2. Поворот и масштаб по таблице раздела 4; origin в сокет.
3. Упрощение сетки до бюджета, запекание карты нормалей с исходника.
4. Класс M: UV «2 тайла на метр», материал `Base_<Mat>`. Класс U: атлас 1024², свой материал-роль.
5. Обвязка из `kit_common.py`: обойма, шар, плашка лица, окошко ядра, пояс игрока.
6. Пустышки `Socket`, `Anchor_*`, `Shape_*`; запись `META` для `kit_catalog.json`.
7. Дальше общий путь кита: `body_kit.py --export` → `--import` → `build_body_kit.gd` → `--import` → пробы.

## 8. Что не решается моделями

Новые детали сами игру глубже не сделают. Разбор каталога показал, что часть характеристик была только на витрине. Состояние на 04.10, вечер:

| Проблема | Состояние |
|---|---|
| Броня не защищает | **закрыто:** щиток снимает долю урона с ударов в своё тело (`ARMOR_BREAK.md`) |
| «Прочность» в бою не участвует | **сделано, по умолчанию выключено** (`Tuning.PART_BREAK`): у конечностей, кистей и стоп запас прочности, на нуле деталь отлетает (`ARMOR_BREAK.md`); рядом пробный режим «Прочность суставов» на клавише C (`JOINT_BREAK.md`) |
| Ядра различаются только массой | **закрыто частично:** у тяжёлых ядер своя броня, у трёх новых ядер пассивы; бочка, ящик, игрушка остались без свойств |
| У «говорящих» деталей нет своего поведения | открыто: колесо катится формой, пого-пружина прыгает резиной; ласта, поршень, пружинная рука, стопа-пропеллер — только вид |
| Материалов 15, а разных по числам — 10 | открыто: пять красок одинаковы, дерево равно клёну; материалов лиги нет |
| Эффектов состояния нет | открыто: огонь и ток дают урон в секунду, материал на них не влияет |
| Щитков на ядро и голову нет | открыто: нужны модели и приём вида `armor` якорями `Back` / `Top` |
