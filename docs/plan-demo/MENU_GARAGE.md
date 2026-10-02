# Главное меню «Гараж + эфир» — идея, болванка, промты (02.10.2026)

> Идея автора (02.10): слева тёмная комната — гараж бойца, в ней телевизор, по нему идёт трансляция NULL Fighting; справа — красивое меню. Что показывает телевизор, может зависеть от момента истории. На разные пункты меню камера плавно переезжает в разные стороны.
>
> Ниже: как я понял идею, моё мнение, кадры болванки (Godot, без моделей), промты для референсов и 3D-предметов. Всё, что сверх слов автора, — **предложение**, пока автор не принял. Прошлый разбор вариантов меню лежит в чате облачной сессии 02.10; этот документ его заменяет.

## 1. Как устроено

Бокс 07 — гараж бойца под ареной местной лиги. Ночь, свет почти только от телевизора. Кукла игрока (его текущая сборка) сидит на ящике и смотрит трансляцию. Справа поверх тёмной части кадра — меню.

Каждый пункт меню — место в гараже. Когда фокус переходит на пункт:
- камера за 0.6–0.8 с переезжает к этому месту, движение плавное, с лёгкой дугой;
- над местом загорается своя лампа, остальные зоны притухают;
- телевизор через 2–3 кадра помех переключается на нужный канал;
- ввод не блокируется: следующее нажатие перебивает переезд.

| Пункт | Место в гараже | Камера | Что по телевизору | Свет |
|---|---|---|---|---|
| ИСТОРИЯ | телевизор, кукла на ящике | вперёд, через плечо куклы | следующий соперник и что на кону | экран |
| БЫСТРЫЙ БОЙ | ворота лифта на арену, афиши арен | влево | выставочный канал, превью арены ◀ ▶ | поле NULL из-под ворот |
| МАСТЕРСКАЯ | верстак, стенд, чертёж | влево-назад | карточка бойца: имя, масса, ENERGY | лампа над верстаком |
| ТРОФЕИ | полка с деталями побеждённых | вправо | повтор боя, где взят выбранный трофей | подсветка полок |
| НАСТРОЙКИ | радио, щиток, доска эфира | вправо-назад | настроечная таблица (по ней яркость) | шкала радио |
| ВЫХОД | рубильник на щитке | — | телевизор схлопывается в точку | свет гаснет |

Вход в пункт (предложение):
- **ИСТОРИЯ** — камера ныряет в экран (1.1 с), картинка эфира заполняет кадр, и мы уже в трансляции боя: выход бойца, проход сквозь мембрану. После боя камера выезжает из телевизора обратно в гараж, по ТВ — повтор.
- **БЫСТРЫЙ БОЙ** — ворота поднимаются, фиолетовый свет заливает гараж, к лифту подходят участники (лобби P1–P4), лифт везёт наверх и прячет загрузку арены.
- **МАСТЕРСКАЯ** — кукла встаёт и садится в стенд, открывается мастерская v0.3. Мастерская может жить в этой же комнате — тогда переход бесшовный.
- **ВЫХОД** — рубильник: лампы гаснут по очереди, телевизор схлопывается в белую точку.

Мышь: наведение на предмет в гараже тоже переводит фокус, клик — вход. Цифры 1–5 — сразу к пункту. Геймпад — стики и A/B.

## 2. Мнение

Идея сильная. Она берёт лучшее из двух вариантов прошлого разбора: эфир даёт дешёвый и понятный канал для сюжета, а гараж — личное место игрока, трофеи и мастерскую. Слабые места обоих закрываются: купол NULL виден с первой секунды (на экране), а меню остаётся обычным списком справа — быстрым и понятным.

Что даёт игре:
- **Кадр с первой секунды объясняет, кто ты.** Кукла в тёмном гараже смотрит, как дерутся профи, — это мечта новичка, как в «Рокки». ИСТОРИЯ — это записаться в лигу.
- **Телевизор — главный голос сюжета.** Новости, соперники, повторы, экстренные выпуски, позже — пиратский сигнал Тишины. «Сюжет создаёт геймплей»: что показали по ТВ, то и открылось в меню.
- **NULL объясняется без текста** (предложение). Гараж вне поля, поэтому кукла здесь тяжёлая и сидит обмякнув. В куполе она впервые всплывает. Контраст «тяжело в гараже — легко на арене» — готовое первое «вау» дебюта.
- **Сборка и покраска имеют зрителя.** В гараже сидит твоя текущая сборка, а после победы тебя показывают по телевизору. Ради этого и стоит строить (§7 документа автора).
- **Правило трофея видно вещами.** Полка с деталями побеждённых и пустое место «?» для следующей.

Риски и как их снять:
- **«Сначала весело и ярко».** Тёмная комната может уйти в нуар. Поэтому яркость держат эфир (цветной, спортивный) и тёплые лампы. N0 шутит с первого кадра. Хоррора и мрака нет.
- **Объём.** Нужно 15–20 предметов. С генерацией 3D это реально; главное — одна палитра и один масштаб (требования в §7).
- **Второй рендер — сам эфир.** Живой бой ботов в SubViewport стоит видеокарты. Запасной путь — заранее записанные ролики из самой игры (Movie Maker → `.ogv`, `VideoStreamPlayer`). Для сюжетных выпусков ролики даже удобнее.
- **Правило 1 `ASSET_PIPELINE.md`.** Там все модели — только из Blender-скриптов. Сгенерированные 3D-модели — исключение, его надо записать (решение автора). Для статичных предметов гаража это годится. Куклы и детали остаются из кита: трофеи на полке — тоже детали кита.
- **Узкие экраны** (16:10, Steam Deck). Левая часть кадра сужается — композицию проверить и там.

## 3. Что идёт по телевизору — предложение

| Момент | По телевизору | Зачем |
|---|---|---|
| Первый запуск | живой матч местной лиги; бегущая строка «ОТКРЫТ НАБОР НОВИЧКОВ · БОКСЫ 01–12» | приглашение: ты новичок, ИСТОРИЯ = записаться |
| Перед боем кампании | карточка соперника, его лучшие удары, «НА КОНУ: деталь» | правило трофея: видно, что можно выиграть и проиграть |
| После победы | повтор твоего KO, твоё имя в таблице лиги, N0 хвалит сборку | награда: тебя показывают |
| После поражения | повтор в замедлении и шутка N0 | смягчить и позвать на реванш |
| Фокус на Быстром бое | выставочный канал: превью выбранной арены | выбор арены = переключение каналов ◀ ▶ |
| Фокус на Мастерской | карточка бойца как на выходе (имя, масса, ENERGY, детали) | сборка связана с эфиром |
| Фокус на Трофеях | повтор боя, где взят выбранный трофей | память о победах |
| Настройки | настроечная таблица; яркость подбирают по ней | функция в мире |
| Акт 2 | «ЭКСТРЕННЫЙ ВЫПУСК»: мембрану продавливают снаружи | новый режим (PvE) открывается через эфир |
| Акты 3–4 | чемпионат мира, межмировая лига, первые кадры завоевателей | следующая ступень карьеры |
| Тайна (поздно) | ночью эфир на секунду перебивает пиратский сигнал Тишины; N0 сбивается на полуслове | тайна в предметах, не в диалогах |

Тайну N0 (MEMORY RESET, CYCLE 217) в меню до конца первого акта не показываем.

## 4. Болванка

Отдельный маленький проект Godot: `docs/plan-demo/menu-garage-blockout/`. Это не часть игры: комната и предметы собраны из примитивов, цвет примитива обозначает роль материала. На экране телевизора — кадры из игры (`docs/plan-demo/img/`) и графика эфира. Шрифты меню — Oswald, Rubik и JetBrains Mono (OFL, с кириллицей), кандидаты и для настоящего меню.

Кадры (1600×900) лежат в `docs/plan-demo/img/menu-garage/`:

| Файл | Что |
|---|---|
| `garage-title.png` | титул: общий план, «НАЖМИ ЛЮБУЮ КНОПКУ» |
| `garage-story.png` | ИСТОРИЯ: через плечо куклы, на ТВ — карточка соперника |
| `garage-quick.png` | БЫСТРЫЙ БОЙ: ворота лифта, свет поля, афиши |
| `garage-workshop.png` | МАСТЕРСКАЯ: верстак, стенд, лампа |
| `garage-trophies.png` | ТРОФЕИ: полка, бирки, пустое место «?» |
| `garage-settings.png` | НАСТРОЙКИ: радио, щиток, доска эфира, на ТВ — настроечная таблица |
| `garage-into_tv.png` | вход в бой: камера в экране |
| `garage-plan.png` | план сверху: зоны и точки камер |
| `garage-moves.mp4` | ролик: перелёты камеры по пунктам и нырок в телевизор |

Перерисовать (нужно окно; на сервере — `xvfb-run`):

```bash
cd docs/plan-demo/menu-garage-blockout
godot --path . --resolution 1600x900 -- shots=all out=/абс/папка
godot --path . --resolution 1280x720 -- video=1 out=/абс/кадры   # потом ffmpeg -framerate 24 -i f%04d.png …
```

Точки камер и зоны — в таблице `SHOTS` в `garage.gd`. В настоящей сцене меню они переедут как есть.

## 5. Как работаем с картинками

1. **Кадр стиля.** Генерируешь «Титул» (промт V1). Как образец композиции прикладываешь `garage-title.png`, как образец кукол — `docs/plan-demo/img/body-kit-v1.png`. Из 4–8 вариантов выбираешь один, он становится эталоном стиля.
2. **Остальные виды** (V2–V7) — тем же стилем: к промту прикладываешь выбранный кадр как образец стиля и кадр болванки как образец композиции.
3. **Предметы для 3D** (§7): картинка по промту → генератор 3D по картинке (Meshy, Tripo, Rodin, Hunyuan3D…). Тоже с эталоном стиля в приложении, чтобы предметы были из одного мира.
4. **Отдаёшь мне** картинки (сохраню в `docs/refs/menu-garage/`) и модели (`.glb`, положу в `godot/assets/models/garage/`). Я собираю настоящую сцену меню и меняю примитивы болванки на модели по одной, с проверкой кадров.

Надписей генераторы не сделают — все тексты (табло, бирки, афиши, эфир) накладываю в движке. Поэтому в промтах везде «без текста».

## 6. Промты: виды (концепт-арт)

Общий блок стиля — добавлять в конец каждого промта вида:

```text
Stylized 3D game art of a handcrafted toy-like world of modular wooden fighters. Chunky, simple, readable shapes. Materials: painted and weathered wood, riveted iron, brass, cream ceramic and bakelite, worn cloth. Muted palette (maroon, teal, mustard, olive, warm wood) with cool blue TV glow and the violet light of the NULL field. Cozy night mood but colorful and inviting, not grim. Cinematic lighting, light volumetric haze, soft bloom. High-end stylized PC game look (It Takes Two, Ratchet & Clank: Rift Apart, Psychonauts 2), Unreal Engine render. 16:9.
```

Описание куклы — добавлять, где она в кадре:

```text
The fighter: a modular wooden ragdoll about 1.5 m tall built from parts — a barrel torso with dark iron hoops and a small glowing porthole on the chest, a box-shaped wooden head with a cream face plate and two small dot eyes, cylindrical wooden limbs, dark ball joints wrapped with teal cloth rings, mitten-like hands. A hand-made toy, not a robot, not a human.
```

Негатив (или «avoid: …» в конце):

```text
humans, realistic people, humanoid robots, cyberpunk, neon city, anime, photorealism, gore, readable text, letters, watermark, logo, UI
```

**V1 — Титул, общий план** (образец: `garage-title.png`)

```text
Wide establishing shot, eye level slightly above. Night interior of a small fighter's garage — a pit bay under a sports arena. The room is dark; the main light source is an old retro-futuristic CRT television with a wooden case and a cream bezel, standing on a low wooden sideboard against the back wall of dark wooden planks. Its screen shows a bright, colorful live sports broadcast of a fight inside a glowing transparent dome. In front of the TV, on a low wooden crate, the fighter sits slumped and heavy, watching the screen, its back three-quarters to the camera. Left side of the room: a workbench with a pegboard full of tools, a pale blue blueprint pinned to the wall, an empty build stand (round steel turntable base, vertical rail, orange saddle ring) under a hanging green enamel lamp with a warm cone of light. Far left wall: a big roller-shutter lift gate with a yellow-black hazard frame, a round porthole and violet light leaking from under the shutter. Concrete floor with a faded painted bay number. The right 40% of the frame is dark, calm, nearly empty negative space reserved for the game menu.
```

**V2 — ИСТОРИЯ, через плечо** (`garage-story.png`)

```text
Over-the-shoulder shot from behind and to the right of the seated fighter, looking at the CRT television on the sideboard. The TV sits left of center and shows a "next opponent" broadcast card: a horned fighter in a dark iron helmet on a maroon background, blank title bars. Blue TV light rims the fighter's shoulder and the edge of its box head in the foreground. Behind the TV: a wall of dark wooden planks, a pale blue blueprint, antenna shadows. The right 40% of the frame is dark and empty.
```

**V3 — БЫСТРЫЙ БОЙ, ворота лифта** (`garage-quick.png`)

```text
The camera turns to the left wall of the garage: a huge industrial roller-shutter lift gate, 3 m wide and 3 m tall, in a heavy steel frame with yellow-black hazard stripes. A round porthole in the shutter glows violet; violet light from the arena field spills across the concrete floor from the gap under the shutter. A big stenciled bay number on the shutter, a small red warning lamp and a dark blank sign plate above. Framed painterly posters of arenas hang on both sides of the gate. It feels like the tunnel to the arena is right behind this door. The right 40% of the frame is dark.
```

**V4 — МАСТЕРСКАЯ, верстак и стенд** (`garage-workshop.png`)

```text
The camera turns to the back-left corner: a sturdy wooden workbench with an olive metal drawer unit, a cast-iron bench vise, a hammer and spare wooden limbs lying on it; a pegboard of tools; a pale blue blueprint of a ragdoll body pinned above. In front of the bench stands an empty build stand — a round steel turntable with brass screws, a vertical rail and a saddle clamp — waiting for the fighter. A hanging green enamel lamp throws a warm cone of light onto the stand through light haze. A wooden bin full of spare limbs in different colors. The right 40% of the frame is dark.
```

**V5 — ТРОФЕИ, полка** (`garage-trophies.png`)

```text
The camera turns to the right wall: a dark wooden shelving unit lit by three small warm clamp spotlights. On the shelves stand trophies taken from defeated opponents: a horned dark iron helmet, a small golden crown, a wooden box head with a cream face plate, a red spiked mace ball, a striped painted forearm, a spring limb. Each trophy has a small blank paper tag; one empty spot is marked with a chalk circle for the next trophy. A teal pennant of the local league hangs above. The right 40% of the frame is dark.
```

**V6 — НАСТРОЙКИ, радио и щиток** (`garage-settings.png`)

```text
The camera turns to the back-right corner: a cream bakelite tube radio with a glowing amber dial on a dark wooden cabinet; a grey-green fuse box on the wall with a big knife-switch lever with a red handle and three indicator lamps (green, amber, red); cables running up to the ceiling; a small wooden-framed chalkboard with blank chalk scribbles; one small warm spotlight. The right 40% of the frame is dark.
```

**V7 — Нырок в телевизор** (`garage-into_tv.png`)

```text
Extreme close-up: the camera pushes into the curved CRT screen of the television, the broadcast fills almost the whole frame — a huge glowing transparent dome arena with wooden fighters floating inside, a scoreboard bar and a red LIVE tag with blank text, crowd lights around. Scanlines, slight barrel distortion, phosphor glow; the cream bezel is visible only at the very edges.
```

**V8 — Выход, свет гаснет** (по желанию; композиция как V1)

```text
Same wide shot of the garage, but every lamp is off and the CRT television is collapsing into a single bright horizontal line in the dark; only the violet light under the lift gate remains, outlining the seated fighter.
```

## 7. Промты: предметы для 3D

Требования к картинке для генератора 3D: один предмет, по центру, целиком в кадре, светло-серый фон, вид спереди-слева и чуть сверху (три четверти), ровный свет без падающих теней. Если генератор принимает несколько видов — добавь вид спереди и сбоку.

Требования к модели:
- `.glb`, масштаб в метрах (размеры — в таблице);
- ориентацию не трогаю: разверну сам;
- треугольников: крупные предметы (телевизор, ворота, верстак, полка) до ~20k, мелкие до ~5k. Если генератор даёт больше — присылай как есть, я упрощу;
- текстуры PBR 1–2K.

Экран телевизора, шкалу радио, иллюминатор ворот и лампы я накрываю своими светящимися материалами. Если генератор не умеет делать их отдельным материалом — не страшно.

Шаблон — подставить предмет вместо `[OBJECT]`:

```text
[OBJECT]. Stylized 3D game asset, single object isolated on a plain light-grey background, centered, whole object in frame, three-quarter view from the front-left and slightly above, neutral even studio lighting, no cast shadows, no other props. Clean readable silhouette, chunky handcrafted proportions, hand-painted PBR materials (worn painted wood, riveted iron, brass, cream bakelite), muted palette (maroon, teal, mustard, olive, warm wood). No text, no logo.
```

| # | Предмет | Размер, м (Ш × В × Г) | Пункт | Вставка вместо `[OBJECT]` |
|---|---|---|---|---|
| 1 | Телевизор | 1.5 × 1.05 × 0.85 | ИСТОРИЯ | `A retro-futuristic CRT television set: chunky wooden case with rounded corners, cream bezel around a large slightly curved dark glass screen (screen off, plain dark), two maroon knobs and a speaker grille on the right side of the bezel, a small red power light, rabbit-ear antenna on top, short tapered legs` |
| 2 | Тумба под ТВ | 1.9 × 0.85 × 0.62 | ИСТОРИЯ | `A low wooden sideboard / TV cabinet with three drawers and brass handles, worn edges, short legs` |
| 3 | Ящик-сиденье | 0.7 × 0.42 × 0.7 | ИСТОРИЯ | `A low sturdy wooden crate with dark corner posts and a diagonal brace, scuffed, used as a seat` |
| 4 | Ворота лифта | 3.4 × 3.6 × 0.4 | БЫСТРЫЙ БОЙ | `An industrial roller-shutter gate set into a heavy steel frame with yellow-black hazard stripes: horizontal metal slats, a round porthole window in the shutter, a small red warning lamp and a blank dark sign plate above the frame` |
| 5 | Верстак | 2.3 × 0.9 × 0.7 | МАСТЕРСКАЯ | `A heavy wooden workbench with a thick worn top, an olive-green metal drawer unit on one side, a cast-iron bench vise on the corner, a lower shelf` |
| 6 | Перфопанель с инструментом | 2.3 × 1.15 × 0.1 | МАСТЕРСКАЯ | `A wall pegboard panel with hanging tools: hammers, wrenches, screwdrivers, clamps, a coil of rope; flat panel, front view` |
| 7 | Подвесная лампа | 0.6 × 0.3 × 0.6 | МАСТЕРСКАЯ | `An industrial pendant lamp with a green enamel cone shade, white inside, an exposed warm bulb and a black cord` |
| 8 | Полка трофеев | 2.6 × 2.2 × 0.4 | ТРОФЕИ | `A wall shelving unit of dark wood with three long shelves and side posts, three small brass clamp spotlights on top, small blank paper tags hanging from the shelf edges, shelves empty` |
| 9 | Радио | 0.74 × 0.42 × 0.3 | НАСТРОЙКИ | `A vintage tube radio of cream bakelite with a rounded top, a large amber tuning dial window, a fabric speaker grille, two maroon knobs and a small telescopic antenna` |
| 10 | Щиток с рубильником | 0.55 × 0.75 × 0.15 | НАСТРОЙКИ / ВЫХОД | `A wall-mounted grey-green metal fuse box with a big knife-switch lever with a red handle and three round indicator lamps (green, amber, red), cables going up` |
| 11 | Тумба под радио | 1.7 × 0.9 × 0.5 | НАСТРОЙКИ | `A dark wooden low cabinet with two doors and iron hinges` |
| 12 | Ящик запчастей | 0.6 × 0.4 × 0.5 | МАСТЕРСКАЯ | `An open wooden bin, empty, with rope handles and painted stencil marks` (конечности в нём — детали кита) |
| 13 | Мелочь гаража | разные | фон | по одному: `a dented oil can`, `a metal bucket`, `a red metal toolbox`, `an extension cable reel`, `a small desk fan`, `a stack of old sports magazines` |

Не генерировать:
- стенд (`godot/scenes/workshop/stand/build_stand.tscn`) и трофеи — в игре уже есть: это стенд мастерской и детали кита (шлем с рогами, корона, голова-ящик, булава…);
- стены, потолок, балки, трубы — сделаю модулями сам.

Текстуры для стен и пола (бесшовные):

```text
Seamless tileable texture, flat front view, even lighting, stylized hand-painted PBR albedo, 2048x2048: [dark weathered vertical wooden planks wall | corrugated painted metal wall, grey-blue | stained concrete garage floor with faded yellow paint marks | worn maroon rug with a simple woven border pattern]
```

## 8. Промты: эфир, интерфейс, афиши (2D)

Это образцы стиля для графики эфира и меню; текст на них будет мусорный, настоящие надписи — в движке.

**Пакет графики эфира NULL Fighting**

```text
Sports broadcast graphics package for a fictional TV channel "NULL FIGHTING", design sheet on a near-black background: a red LIVE tag, a scoreboard bar for two fighters with team-color stripes, a lower third with fighter name and stats, a next-opponent card layout, a REPLAY badge, a news ticker, a field info panel (gravity vector arrow, membrane percent), an audience vote panel with three options and percentage bars. Retro-futuristic 1980s sports TV style mixed with handcrafted materials (paper, enamel, brass). Colors: warm orange, mustard, maroon, teal, cream on near-black. Bold condensed sans-serif headings. Clean flat vector, 16:9.
```

**Заставка и знак канала**

```text
Logo for a fictional sports channel "NULL FIGHTING": an emblem of a glowing hemisphere dome with an elastic membrane and a small wooden ragdoll figure bouncing off it, bold condensed lettering. Flat vector, orange and cream on black, plus a monochrome version.
```

**Меню справа**

```text
Main menu UI design for a stylized physics fighting game, 16:9 screenshot. The left 60% shows a dark cozy garage with a glowing CRT TV (soft focus). The right 40% is a clean menu panel on a dark translucent gradient: the game title "RAGDOLL MASTER" in bold condensed letters (white and orange), a vertical list of five items, the selected item highlighted by an orange accent bar with a two-line description under it, small key hints at the bottom. Premium AAA polish, sports-broadcast typography, no clutter.
```

**Афиши арен** (по одной; вертикальные 2:3)

```text
Vintage sports poster, portrait 2:3, painterly, bold simple shapes, limited palette, paper texture, no text: [wooden ragdoll fighters floating above heaps of junk and cranes at sunset inside a faint glowing dome — "The Scrapyard" | wooden fighters floating among stone ruins, arches and banners at golden hour — "The Ruins" | a huge glowing transparent dome in a packed night stadium, a giant screen with a gravity arrow behind it — "The NULL Dome"]
```

**Купольная арена** (ключевой кадр §27 — для эфира, афиш и будущей арены демо-среза)

```text
Key art: a huge transparent glowing hemisphere dome of the NULL field in the middle of a packed night stadium. Inside, modular wooden ragdoll fighters float in low gravity mid-fight, limbs swinging; the elastic membrane visibly bulges where a fighter hits it. Around: an excited crowd, floodlights, camera cranes, stadium architecture of wood, iron and brass. Behind: a massive screen showing a gravity vector arrow and field readouts. A small round host drone hovers near the dome. Colorful, spectacular, inviting.
```

## 9. N0 — дизайн персонажа

N0 появляется в эфире с первого кадра, а дизайна у него ещё нет. По лору это очень старый дрон исследований NULL, перекрашенный под ведущего лиги. Отсюда идея: свежая ливрея лиги поверх старой промышленной маркировки. Тайну (цифры, нацарапанные внутри) пока не показываем.

```text
Character design sheet of N0, a small flying host drone of a sports broadcast in a world of handcrafted wooden ragdoll fighters. Body the size of a football, rounded, made of old cream ceramic and brass with repaired seams and rivets; one large camera-lens eye with an iris aperture that works as its expressive face; a tiny antenna; a slim anti-gravity ring under the body; two tiny jointed arms, one holding a vintage microphone. Fresh league livery (orange and teal stripes) painted over older faded industrial markings. Friendly, charismatic, a bit mischievous. Front, side, back and three-quarter views, plus six eye expressions (happy, shocked, laughing, suspicious, glitching, sleepy). Neutral grey background, stylized 3D render.
```

## 10. Что дальше

1. Ты генерируешь V1 и выбираешь стиль, потом V2–V7, N0 и предметы.
2. Я собираю настоящую сцену `godot/scenes/menu/garage_menu.tscn`:
   - точки камер и зоны света — из болванки;
   - кукла — твоя сборка (ModularDoll), сидит под обычной гравитацией;
   - телевизор — SubViewport с эфиром (живые боты или ролики).
3. Машина экранов, Esc «назад», проба путей числами (≤ 2 нажатий до боя, нет тупиков) — как в общем скелете прошлого разбора.
4. Записываю исключение для сгенерированных моделей в `ASSET_PIPELINE.md`, если автор его примет.
