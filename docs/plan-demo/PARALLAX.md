# Параллакс: решение, числа, бриф для генерации

28.09.2026. Работа над фоном отдельно от арены. Первый биом — Свалка (THE SCRAP), дальше по тому же конвейеру остальные из `BIOMES.md`.

## Что было не так

v1 резался из одного листа `docs/refs/biomes/01-scrap/parallax.png`, где пять слоёв — полосы по 64–116 пкс в высоту. Тест теперь меряет это по пикселям источника. При максимальном приближении на 1080p v1 растягивал источник так: небо ×4.0, башни ×3.9, средний план ×5.3, передний ×6.2 (апскейл текстур до 4096 деталей не добавлял). Чтобы это спрятать, у арены стоял сильный DOF дали (24 / 40 / 0.05), и он размывал фон ещё сильнее. Совет ChatGPT (лист — только референс, каждый слой генерировать отдельно) верный.

## Решение

С советом ChatGPT совпадаем в главном:

- каждый слой — отдельная генерация;
- средний и передний планы собираются в движке из отдельных элементов;
- лист остаётся референсом стиля.

Расходимся в шести местах:

1. **Слои шириной 10240–15360 пкс из секций A–D не нужны.** Камера арены видит около 1.5 экрана по ширине (центр x ±13 м при зуме z 10–24), а не 20 экранов. Ограничивает не ширина, а разрешение на своей глубине (таблица ниже). Стыки секций — лишняя работа без выигрыша.
2. **У нас 3D.** Каждый элемент стоит на своей глубине z, и перспективная камера сама даёт параллакс, причём непрерывный, а не пять ступенек. Коэффициенты скорости слоёв не нужны: скорость задаёт глубина.
3. **Отражение по x ломает свет.** Солнце заката справа, кайма света справа. Поэтому в брифе контражур: солнце за объектом, кайма с обеих сторон. Если свет боковой — у полосы `allow_flip = false`.
4. **Мосты и конвейеры, которые соединяют башни,** процедурно правдоподобно не соединить. Их запекаем внутрь элемента («кластер»: две башни с пролётом = один элемент).
5. **Ближний хлам (LAYER 3 NEAR SCRAP)** уже сделан 3D-китом со светом и тенями, картинка не нужна.
6. **Дальним башням хватает одной сплошной картинки** (`far-towers.webp`): на весь диапазон камеры увеличение ×1.3. Дальние силуэты-элементы — по желанию, для разнообразия и длинных уровней.

## 29.09: фон из 3D, запечённый в PNG (основной путь)

Автор: генерировать хорошие отдельные картинки для фона будет трудно (прозрачность, одинаковый свет, подписи на листах). Поэтому средний план (и дальше передний) строим **из 3D и запекаем**.

- `godot/tools/blender/scrap_backdrop.py` процедурно строит конструкции Свалки. Материалы те же, что у арены: хелперы и PBR из `scrap_kit.py`, флаги с короной, цепи, крюки. Сейчас это ферменные башни с кабинами, площадками, трубой вдоль ноги и фонарями; портальные краны с ковшом или магнитом; дымовая труба; водонапорная башня; пара башен с мостом-конвейером и ковшами.
- Каждая конструкция рендерится отдельно: орто спереди, прозрачный фон, 60 пкс/м, EEVEE, 7 штук меньше чем за минуту. Свет — два скользящих солнца справа и слева, чуть сзади, плюс слабый холодный заполняющий спереди. Фасад тёмный, на фасках кайма с обеих сторон, окна светятся. Поэтому элементы можно зеркалить.
- `parallax_elements_cut.py --single --ppm 60` кладёт PNG в `assets/textures/parallax/scrap_baked/mid/`. В manifest пишется `m_per_px`, и `ParallaxScatter3D` берёт **настоящую высоту** × `scale_range` полосы: кран не станет ростом с водокачку.
- Нагрузка в игре — только плоские квады. 7 элементов = 5.6 Мпкс, в видеопамяти около 7.5 МБ (BPTC + мипмапы), на диске 3.4 МБ. Ни одного 3D-треугольника фона.
- ИИ остаётся там, где он хорош: небо и дальний фон в дымке (`sky.webp`, `far-towers.webp`).

Что даёт по сравнению с генерацией: стиль и материалы совпадают с 3D-ареной; свет одинаковый у всех элементов; разрешение любое (перерендер за минуту); новый вариант — новый seed или параметр. Чего не хватает до уровня нарисованного фона: разнообразия (7 уникальных, повторы заметны — нужно 15–20), насыщенности деталями (сараи, трубопроводы, лестницы, дым) и цветокоррекции под небо. Это работа скриптом, а не борьба с генератором.

Кадры: `img/scrap-backdrop-baked-v1.png` (все конструкции), `img/scrap-parallax-scatter-{a,b,c}.png` (сцена `parallax_scrap_scatter.tscn`: средний план и дальние силуэты — запечённые, передний — грейбокс), `img/scrap-parallax-pan-baked.mp4`.

## Как устроено в Godot

| План | Источник | Глубина z, м | Чем | Сейчас |
|---|---|---|---|---|
| Небо | `parallax-v2/sky.webp` | −100 | слой `Layer4Sky` | **v2** |
| Дальние башни и море облаков | `parallax-v2/far-towers.webp` | −55 | слой `Layer3Far` | **v2** |
| Дальние силуэты | запечённые 3D-конструкции, тёмная дымка | −48…−36 | `ParallaxScatter3D` | **запечено** (в сцене scatter) |
| Средний план | запечённые 3D-конструкции (`scrap_backdrop.py`) | −32…−21 | `ParallaxScatter3D` | **запечено** (в сцене scatter); в арене пока слой v2 |
| Туман у подножий | генерируется | −20 | слой `Layer2Fog` | **v2** |
| Ближний хлам | 3D-кит K01–K22, №001–040 | −2…0 | 3D | готово |
| Передний план | сейчас полоса v1, дальше элементы (запечь цепи/шестерни/балки тем же путём) | +2.5…+5 | слой `Layer1Fore` → `ParallaxScatter3D` | v1 (мыло ×6.2), в сцене scatter — грейбокс |

Файлы:

- `godot/tools/parallax_cut_scrap_v2.py`: слои v2 из отдельных генераций. Небо с дорисованным зенитом. Небо у башен и облака в небе вырезаются в alpha (остаются только острова, связанные с основанием). Второе солнце убирается. Воздушная перспектива запекается (дальше — светлее). Скрипт печатает таблицу увеличения и **сам пишет** `scenes/arena/parallax_scrap_v2.tscn`, так что геометрия не расходится с текстурами. Превью: `img/scrap-parallax-v2-preview.png`.
- `scenes/arena/scrap.tscn` и `tools/build_arena_scrap.gd` уже на v2. DOF дали 45 / 70 / 0.03 (был 24 / 40 / 0.05: он прятал мыло v1).
- `scenes/arena/parallax_scatter.gd` (`ParallaxScatter3D`) и `parallax_scatter_band.gd` (`ParallaxScatterBand`): процедурная расстановка. Полоса задаёт папку элементов, диапазон глубины, высоту в метрах, основание или верх (для подвешенных), зазор, дымку по глубине, растворение основания и seed. Ширину покрытия узел считает из диапазона камеры. Раскладка детерминирована. Шейдер `parallax_element.gdshader`: без света, дымка, отражение, растворение основания, `depth_prepass_alpha`.
- `scenes/arena/parallax_scrap_scatter.tscn`: целевая сборка. Слои неба, дальнего плана и тумана из v2, средний план и дальние силуэты — `ParallaxScatter3D` на запечённых 3D-конструкциях, передний план — грейбокс.
- `godot/tools/blender/scrap_backdrop.py`: 3D-конструкции фона → PNG (раздел «фон из 3D» выше).
- `godot/tools/parallax_elements_cut.py`: лист элементов → PNG с alpha + `manifest.json`. Понимает настоящую прозрачность и ровный фон (зелёный с подавлением переливания). Фейковую alpha-виньетку игнорирует. Якорь `top` выставляется, если объект касается верхнего края листа.
- `godot/tools/parallax_greybox.py`: грейбокс-листы в формате брифа (`tests/fixtures/parallax_greybox/`) для проверки конвейера до арта.

Кадры и видео: `img/scrap-parallax-godot-v2{a,b,c}.png`, `img/scrap-arena-v2-{wide,start,vertical,fight}.png`, `img/scrap-parallax-scatter-{a,b,c}.png`, `img/scrap-parallax-pan-v1-v2.mp4` (проезд камеры: v1 сверху, v2 снизу), `img/scrap-parallax-pan-baked.mp4`.

## Числа: какое разрешение нужно

Экранных пикселей на метр при 1080p на расстоянии D от камеры: 1080 / (2·tan 22.5°·D) ≈ **1304 / D**. Худший случай — максимальное приближение (камера z = 10). Для 1440p всё ×1.33. Цель — увеличение ≤ ×1.6 при 1080p (порог в тестах).

| План | z, м | D от камеры (z 10), м | пкс/м на экране | Высота объекта, м | **Нужно пкс по высоте объекта** |
|---|---|---|---|---|---|
| Небо (слой 194 м шириной) | −100 | 110 | 11.9 | — | ширина ≥ 2300 (есть 2000 → ×1.15) |
| Дальние башни (слой 128 м) | −55 | 65 | 20 | — | ширина ≥ 2560 (есть 2000 → ×1.28) |
| Дальние силуэты | −48…−36 | 46–58 | 22–28 | 16–26 | **≥ 750** |
| Средний план | −32…−21 | 31–42 | 31–42 | 10–16 | **≥ 900** (для 1440p ≥ 1100) |
| Передний план | +2.5…+5 | 5–7.5 | 174–261 | 2.4–7.5 | **≥ 1000**, лучше 1 объект на картинку |

Итог: средний план — 2–3 объекта на лист 1536×1024 (каждый почти во всю высоту). Передний план — 2–3 объекта на лист или по одному в портрет 1024×1536. Передний план близко к камере и почти чёрный: небольшое мыло там простительно, но резкие силуэты читаются лучше.

## Бриф для генерации (ChatGPT) — запасной путь

С 29.09 средний план запекаем из 3D (выше). Бриф нужен, если захочется нарисованных элементов для отдельных акцентов или для другого биома. Числа разрешения из таблицы выше действуют и для рендеров: `scrap_backdrop.py ppm=60` даёт запас и для 1440p.

**Общие правила для всех листов элементов:**

- PNG, 1536×1024 (или 1024×1536 для высоких).
- **Фон прозрачный.** Если прозрачность не выходит — ровный чистый зелёный `#00FF00`: без градиента, теней, виньетки и пола. Если ChatGPT нарисовал «шахматку» вместо прозрачности, просить зелёный фон: шахматка не вырезается.
- Объекты раздельно, между ними и до краёв ≥ 60 пкс. Исключение — подвешенные (цепи, тросы): они **касаются верхнего края**.
- **Без текста, подписей, цифр и рамок.** На прошлых листах были «LAYER 0 SKY» — это портит арт.
- **Свет — контражур:** солнце за объектом, фасад в тени, тонкая тёплая кайма на **обоих** краях силуэта. Без сильного бокового света: элементы зеркалятся.
- Вид строго сбоку, без ракурса снизу. Объект стоит вертикально.
- Низ стоящих объектов обрезан ровно: без земли, куч и тумана у основания. Туман и дымку по глубине добавляет движок.
- Стиль и палитра — как референс. Прикладывать `docs/refs/biomes/01-scrap/parallax-v2/sheet.webp` и `far-towers.webp`.

**Лист A — средний план, 4 листа по 3 объекта (итого 12):**

```
Side-view game asset sheet for a 2.5D parallax background, 3 separate tall industrial structures of a
fantasy scrapyard tower city (same style and palette as the attached reference): rusted riveted iron
lattice towers with small cabins, gantry cranes with hanging buckets and scrap magnets, smokestacks,
water tanks, some structures joined in pairs by a conveyor bridge that is part of the same object.
Painterly, highly detailed. Backlit by a low sunset sun behind the objects: dark rusty-brown fronts,
thin warm orange rim light on BOTH left and right edges, a few small glowing windows, some red banners
with a golden crown. Straight side view, no low-angle perspective. Each structure stands upright and
fills about 90% of the image height; the bottom edge is cut straight, no ground, no rubble, no fog at
the base. At least 60 px of empty space between objects and to the borders. Fully transparent
background (PNG with alpha); if transparency is impossible, a flat solid pure green #00FF00 background
with no gradient, shadow or vignette. No text, no labels, no numbers, no frame.
```

**Лист B — передний план, подвешенное, 1–2 листа по 4–5 объектов:**

```
Side-view game asset sheet, 5 separate hanging foreground props for a 2.5D parallax game: heavy rusty
chains, a chain with a big hook, a chain with a scrap magnet, a steel cable with a pulley block. Each
object hangs from the TOP EDGE of the image and touches it; different lengths (40–95% of the image
height). Near-black silhouettes with a thin warm orange rim light on both edges, crisp edges, no blur.
Straight side view. Fully transparent background (or flat pure green #00FF00). No text, no labels.
```

**Лист C — передний план, стоящее, 2 листа по 2–3 объекта:**

```
Side-view game asset sheet, 3 separate foreground silhouettes for a 2.5D parallax game: a large broken
gear wheel half buried, a tilted rusty I-beam, a pile of scrap (planks, pipes, broken wooden puppet
limbs). Near-black with a thin warm orange rim light on both edges, crisp edges. Each object at least
900 px tall, the bottom edge cut straight, nothing below it. Fully transparent background (or flat
pure green #00FF00). No text, no labels.
```

**Лист D (по желанию) — дальние силуэты, 1–2 листа по 6 объектов:**

```
Side-view game asset sheet, 6 separate distant tower spires of a fantasy scrap tower city: very tall,
thin, pale lavender hazy silhouettes with a faint warm backlight, low detail, atmospheric. Each fills
about 85% of the image height, bottom edge cut straight. Fully transparent background (or flat pure
green #00FF00). No text, no labels.
```

**Небо** уже подходит. Если перегенерировать: 2:1 (2048×1024), без построек, солнце на ~75 % ширины и ~65 % высоты, облака до верхнего края. Сейчас зенит дорисован градиентом и на полном отъезде камеры видна пустая полоса.

## Конвейер

Запечённые 3D-конструкции:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --python godot/tools/blender/scrap_backdrop.py -- out=/tmp/scrap_backdrop ppm=60
for f in /tmp/scrap_backdrop/*.png; do n=$(basename $f .png | tr A-Z a-z); /usr/local/bin/python3 godot/tools/parallax_elements_cut.py $f godot/assets/textures/parallax/scrap_baked/mid --single --ppm 60 --prefix $n; done
```

Сгенерированный лист элементов:

```bash
/usr/local/bin/python3 godot/tools/parallax_elements_cut.py <лист.png> godot/assets/textures/parallax/scrap_elements/mid --prefix mid_a --preview /tmp/mid_a.png
godot --headless --path godot --import
godot --path godot --resolution 1920x1080 res://tests/parallax_scatter_snapshot.tscn -- "out=/abs/dir/,pan=60"
```

Дальше в `scenes/arena/parallax_scrap_scatter.tscn` у нужной полосы заменить `dir` с `scatter_greybox/…` на `scrap_elements/…`. После зелёного теста переключить арену: `PARALLAX` в `tools/build_arena_scrap.gd` и ext_resource в `scrap.tscn` на `parallax_scrap_scatter.tscn`.

## Проверки

```bash
godot --path godot --resolution 1920x1080 res://tests/parallax_scrap_snapshot.tscn -- "scene=v2,dofd=45,doft=70,dofa=0.03,pan=60"
godot --path godot --resolution 1920x1080 res://tests/parallax_scatter_snapshot.tscn -- "pan=60"
godot --path godot --resolution 1920x1080 res://tests/scrap_snapshot.tscn -- "shots=wide+start+vertical+fight,name=scrap-arena-v2-%s.png"
```

- `parallax_scrap_snapshot` (v1 или v2): покрытие фрустума с запасом, дыры (пурпурный фон), линия земли среднего плана, кромка переднего плана, **резкость `mag_1080_*` ≤ 1.6** — экранных пикселей на пиксель источника (`metadata/source_px_w` слоя) при максимальном приближении. v2: небо 1.15, башни 1.28, средний план 1.58. v1: 4.03 / 3.91 / 5.30. Передний план v1 — 6.15, только в отчёт.
- `parallax_scatter_snapshot`: в каждой полосе есть элементы; z в диапазоне; плотные полосы покрывают ширину; раскладка детерминирована; резкость ≤ 1.6 у полос за плоскостью боя; **передний план закрывает ≤ 8 % зоны боя** (x ±18, y 0..10) из кадров A/B/C; дыр нет. Для полос переднего плана в отчёт идёт `fore_px_needed_per_m` — нужное разрешение арта.
- `scrap_snapshot` умеет `parallax=v2` (подмена фона без правки арены) и `dof=d/t/a`: сравнение фонов по одним и тем же числам читаемости кукол.

## Открыто

- Передний план пока v1: полоса листа, растянута ×6.2 — самое мыльное место кадра. Следующий шаг — запечь цепи, крюки, шестерни, балки и кучи тем же `scrap_backdrop.py` (≥ 240 пкс/м, почти чёрные силуэты).
- Арена всё ещё на слое v2 среднего плана. Переключить на `parallax_scrap_scatter.tscn` — одна константа `PARALLAX` в `build_arena_scrap.gd` и ext_resource в `scrap.tscn`. Эти файлы сейчас правит сессия «Свалка v2» (раскладка арены), переключение согласовать с ней.
- Запечённых конструкций 7, повторы заметны: нужно 15–20 (варианты башен, сараи на опорах, трубопроводы, бункеры, пар/дым) и цветокоррекция под небо.
- Кукла P2 (орех) на грани читаемости и в v1, и в v2 (порог 0.08, значения от прогона к прогону 0.09–0.69 — метрика шумная). С зазорами между элементами и дымкой по глубине за боем больше просветов — перемерить после переключения.
- Перф-гейт Свалки (55 fps) 28.09 не проходит, но фон тут ни при чём: A/B при одинаковой нагрузке v1 24.6 fps, v2 24.5 fps (батарея, Low Power Mode, Electron на 100 % CPU). Перемерить от сети.
- Анимация фона: покачивание подвешенного, дым из труб, медленный дрейф облаков неба. Следующий шаг после арта.
