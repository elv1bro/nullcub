# THE SCRAP — список ассетов для 3D (биом 1, `docs/plan-demo/BIOMES.md`)

Источник: листы автора (ChatGPT) от 28.09.2026, копии в этой папке; исходное описание — `source-description.txt`.

| Файл | Что |
|---|---|
| `sheet-01.jpg` … `sheet-05.png` | ассеты №001–100, по 20 на лист |
| `kit-01.png` | модульный кит 01: платформы, опоры, соединения (K01–K22), **с размерами и эталоном куклы 1.8 м** |
| `kit-02.png` | модульный кит 02: стены, двери/люки, детали, цепи, машины, состояния разрушения и работы (K23–K56) |
| `parallax.png` | 5 слоёв параллакса + пример сборки и геймплея 2.5D |
| `scenes.png` | 7 зон уровня: обзор, старт в куче, платформы, конвейер, пресс, вертикаль, выходные ворота |

**Физика:** S — статика (StaticBody3D, упрощённая коллизия), R — твёрдое тело (RigidBody3D, толкается и летает), B — разрушаемое (`scenes/props/breakable.gd`, состояния целый → обломки), M — механизм с поведением (своя волна), D — только декор/фон (без коллизии), L — лут/интерактив. Размеры — Ш × В × Г в метрах, ориентир; камера смотрит спереди на плоскость XY, глубина Г — визуальная.

**Волны:** 1 — №001–040 + кит K01–K22 + параллакс + уровень v1; 2 — №041–080 + кит K23–K56 (механизмы с поведением); 3 — №081–100 (лор, крафт, лут).

## Лист 01 — Scrap & Bodies (001–020), волна 1

| № | Asset | Что | Физ. | Размер |
|---|---|---|---|---|
| 001 | Scrap Heap Small | маленькая куча дерева, металла и деталей | S | 1.6 × 0.7 × 1.2 |
| 002 | Scrap Heap Medium | средняя куча для заполнения уровня | S | 3.0 × 1.4 × 2.0 |
| 003 | Scrap Heap Massive | огромная гора, часть геометрии арены | S | 10 × 5 × 4 |
| 004 | Puppet Limb Pile | куча рук и ног старых кукол | S + R сверху | 2.0 × 0.8 × 1.5 |
| 005 | Puppet Head Pile | гора деревянных голов (шар с глазницами) | S + R сверху | 1.8 × 1.0 × 1.4 |
| 006 | Broken Puppet | почти целая выброшенная кукла, лежит | S | 1.8 длина |
| 007 | Crushed Puppet | кукла, раздавленная прессом (под плитой) | S | 1.6 × 0.6 |
| 008 | Half Puppet | торс с одной конечностью | S | 1.2 |
| 009 | Empty Torso | пустой корпус без Core, открытая грудь | R | 0.6 × 0.7 × 0.4 |
| 010 | Dead Core Shell | разбитая сферическая оболочка Core | R | ⌀ 0.5 |
| 011 | Wooden Limb Bundle | связка конечностей, перевязана верёвкой | R | 1.4 × 0.5 × 0.6 |
| 012 | Metal Parts Heap | груда металлических деталей | S | 2.0 × 0.9 × 1.5 |
| 013 | Gear Heap | куча шестерней | S + R шестерни | 2.0 × 1.0 × 1.5 |
| 014 | Chain Heap | спутанная куча цепей | S | 1.8 × 0.7 × 1.4 |
| 015 | Nail Bucket | деревянное ведро гвоздей | R | ⌀ 0.5 × 0.55 |
| 016 | Bolt & Nut Box | ящик болтов и гаек | R | 0.8 × 0.45 × 0.5 |
| 017 | Broken Weapons Pile | мечи, молоты, булава, топоры | S | 2.0 × 0.8 × 1.2 |
| 018 | Broken Armor Heap | шлемы, щит с короной, пластины | S | 2.0 × 1.0 × 1.4 |
| 019 | Cloth Scrap Heap | старые флаги (красный/синий с короной) | S | 2.0 × 0.9 × 1.4 |
| 020 | Mystery Scrap Heap | куча с сундучком и тёплым свечением внутри | S + L | 2.2 × 1.4 × 1.6 |

## Лист 02 — Physical Props (021–040), волна 1

| № | Asset | Что | Физ. | Размер | Состояния на листе |
|---|---|---|---|---|---|
| 021 | Wooden Crate | ящик с короной | B | 1.0 куб | intact / open / broken |
| 022 | Reinforced Crate | тёмный ящик, железные уголки, латунная корона | B (прочнее) | 1.0 куб | intact / open / damaged |
| 023 | Broken Crate | развалившийся ящик | R / обломки | 1.0 × 0.6 × 1.0 | variant A / B / debris |
| 024 | Large Shipping Crate | крашеный красный транспортный ящик | R тяжёлый | 2.4 × 1.4 × 1.4 | intact / open / broken |
| 025 | Wooden Barrel | бочка с обручами | B | ⌀ 0.7 × 1.0 | intact / broken / debris |
| 026 | Metal Barrel | красная железная бочка с короной | R тяжёлый | ⌀ 0.6 × 0.9 | intact / dented / broken |
| 027 | Broken Barrel | обломки бочки | R | — | variant A / B / debris |
| 028 | Scrap Basket | сетчатая корзина на колёсиках | R | 1.0 × 0.8 × 0.7 | empty / full / broken |
| 029 | Junk Cart | деревянная тележка с хламом | R (колёса) | 1.8 × 1.1 × 1.0 | intact / loaded / broken |
| 030 | Overturned Junk Cart | перевёрнутая тележка | S | 1.8 × 1.1 | variant A / B / debris |
| 031 | Rail Scrap Wagon | вагонетка на рельсах | R (позже M) | 2.2 × 1.4 × 1.2 | full / empty / broken |
| 032 | Broken Wheelbarrow | ржавая тачка | R | 1.5 × 0.7 × 0.6 | intact / broken / debris |
| 033 | Wooden Pallet | поддон | R | 1.2 × 0.15 × 1.0 | intact / broken / variant |
| 034 | Metal Plate | клёпаная ржавая пластина | R | 1.5 × 0.03 × 1.0 | variant A / B / stack |
| 035 | Corrugated Sheet | погнутый профлист | R | 2.0 × 0.05 × 1.0 | variant A / B / stack |
| 036 | Wooden Beam | брус | R тяжёлый | 3.0 × 0.3 × 0.3 | intact / broken / stack |
| 037 | Broken Beam | расколотая балка со скобами | R | 2.5 × 0.4 × 0.4 | variant A / B / debris |
| 038 | Pipe Bundle | связка труб в хомутах | R | 2.0 × 0.6 × 0.6 | intact / small / broken |
| 039 | Rope Coil | бухта верёвки | R | ⌀ 0.9 × 0.3 | intact / loose / … |
| 040 | Cable Coil | бухта стального кабеля | R | ⌀ 1.0 × 0.35 | … |

## Лист 03 — Level Building Kit (041–060), волна 2

041 Scrap Floor Module (S, 2 × 0.2 × 2) · 042 Scrap Platform Small (S, 2 × 1 × 1.5) · 043 Scrap Platform Large (S, 4 × 1 × 2) · 044 Hanging Platform (M, на цепях) · 045 Tilting Platform (M, шарнир) · 046 Broken Bridge (S) · 047 Improvised Bridge (M, как `rope_bridge`) · 048 Hanging Rope Bridge (M) · 049 Scrap Staircase (S) · 050 Broken Staircase (S) · 051 Improvised Ladder (S) · 052 Chain Ladder (M) · 053 Scrap Wall (S, 4 × 3) · 054 Junk Barricade (B) · 055 Collapsible Wall (B, путь в SECRET) · 056 Scrap Arch (S, 5 × 4) · 057 Support Tower (S, 6 м) · 058 Hanging Cage (M, маятник) · 059 Broken Cage (S) · 060 Scrap Shelter (S, 3 × 2.5 × 2.5).

## Лист 04 — Machines & Hazards (061–080), волна 2

061 Garbage Chute (M, спавн хлама) · 062 Disposal Hatch (M) · 063 Giant Dump Gate (M, 8 × 6) · 064 Scrap Conveyor (M, лента) · 065 Broken Conveyor (S) · 066 Sorting Machine (M) · 067 Crushing Press (M, off/warning/active/cooldown) · 068 Compacting Machine (M) · 069 Scrap Shredder (M) · 070 Magnetic Crane (M, тянет металл) · 071 Claw Crane (M, хватает) · 072 Chain Hoist (M) · 073 Winch (M) · 074 Rotating Gear Mechanism (M) · 075 Junk Elevator (M) · 076 Scrap Furnace (M, огонь) · 077 Ventilation Fan (M, ветер) · 078 Steam Vent (M, периодический толчок) · 079 Swinging Magnet (M, маятник) · 080 Falling Scrap Trap (M).

## Лист 05 — Lore, Loot & Interaction (081–100), волна 3

081 Old Warning Sign «DISPOSAL» · 082 Crown Warning Sign (флаг) · 083 Direction Sign (LOWER WARDS / WORKSHOPS / ARENA / ARCHIVES) · 084 Broken Arena Banner · 085 Hanging Lantern (M, свет) · 086 Broken Lamp (M, мигает) · 087 Disposal Control Panel · 088 Dead Terminal · 089 Ancient Speaker (голос Башни) · 090 Scrap Worker Station · 091 Repair Table (крафт) · 092 Primitive Forge · 093 Salvage Rack (склад) · 094 Body Parts Rack (Body Builder) · 095 Weapon Parts Rack · 096 Energy Cell (L) · 097 Active Core Fragment (L) · 098 Crown-Sealed Container (L, открывается короной) · 099 First Awakening Crater (точка старта) · 100 Ancient Workshop Door (выход, корона).

## Кит 01 — Core Structures (K01–K22), волна 1

Сетка 2 м, эталон куклы 1.8 м, единая система соединений (квадратные клёпаные узлы с проушинами, «snap to grid»).

| K | Модуль | Размер | Физ. |
|---|---|---|---|
| 01 | Straight Platform S | 2 м | S |
| 02 | Straight Platform M | 4 м | S |
| 03 | Straight Platform L | 6 м | S |
| 04 | Platform End (Left) | 2 м, скошенная опора | S |
| 05 | Platform End (Right) | 2 м | S |
| 06 | Gap Platform | две половины с разрывом | S |
| 07 | Lower Platform | 2 м, низкая | S |
| 08 | Upper Platform | 2 м, высокая на раме с крестом | S |
| 09–11 | Corner 90° / T-Junction / Cross | вид сверху; в 2.5D не нужны | — |
| 12 | Sloped Platform 15° | скат | S |
| 13 | Sloped Platform 30° | скат | S |
| 14 | Vertical Support S | 3 м | S |
| 15 | Vertical Support M | 4 м | S |
| 16 | Vertical Support L | 6 м | S |
| 17 | Diagonal Support | подкос | S |
| 18 | Wall Frame | рама с флагом-короной | S |
| 19 | Banner Frame | рама с большим флагом | S |
| 19b | Fence / Railing | перила с цепью | S |
| 20 | Chain Connection | цепь с крюком | D / M |
| 21 | Hanging Beam | балка на цепях | M |
| 22 | Ladder | лестница | S |

## Кит 02 — Props, Interactive, Destruction (K23–K56), волна 2

Walls & Barriers: 23 Panel Wall · 24 Broken Wall · 25 Reinforced Wall · 26 Fence Wall · 27 Gate Wall. Doors & Hatches: 28 Horizontal Hatch · 29 Vertical Gate · 30 Sliding Door · 31 Drop Hatch. Detail Props: 32 Crates · 33 Barrels · 34 Scrap Pile · 35 Boxes · 36 Cables & Pipes · 37 Lamps · 38 Signs & Banners. Chain & Hanging: 39 Chains · 40 Chain Variants · 41 Hanging Platform · 42 Cage · 43 Net · 44 Hooks. Industrial (static): 45 Generator · 46 Tank · 47 Pipe System · 48 Vent Fan · 49 Control Panel · 50 Gear · 51 Cylinder. Interactive (off / warning / active / cooldown): 52 Conveyor · 53 Crusher · 54 Press · 55 Magnet · 56 Shredder. Состояния разрушения платформы: intact → damaged 1 → damaged 2 → broken → debris.
