# 01 — Референсы: подробный план генерации

Каждая картинка ниже это один запуск генерации в отдельном диалоге. Порядок важен: R1 задаёт куклу, всё остальное должно ей соответствовать, поэтому после принятия R1 её картинку прикладывать к промптам R2–R5 и R12 как образец.

## Протокол одного диалога

Фраза для начала:

```
Посмотри docs/plan-demo/01-references.md и docs/refs/README.md. Найди первый референс без статуса «принят». Дай мне готовый промпт для него. Когда я пришлю картинку, сохрани её в docs/refs/ под нужным именем, допиши строку в docs/refs/README.md и скажи, что проверить по критериям приёмки.
```

Правила сохранения:
- Имя файла `R{номер}-{буква варианта}-{краткое}.png`, например `R01-a-doll-sheet.png`. Варианты одной картинки a, b, c.
- `docs/refs/README.md` содержит по строке на файл: `R01-a | doll-sheet | принят / отклонён: почему`.
- Принятый вариант один на референс. Отклонённые не удалять, они помогают следующему промпту.
- Картинки, которые прислал автор, ИИ сохраняет в `docs/refs/` без пересжатия.

## Общие настройки

Стиль-хвост, добавлять в конец каждого промпта:

```
wooden articulated toy ragdoll style, painted low-poly look, warm toon shading, visible ball joints, slightly chipped paint, soft studio light, game concept art, clean composition
```

Негатив (если генератор поддерживает): `photorealistic skin, text, watermark, blurry, extra limbs, cropped, cluttered background`.

Соотношения сторон: листы персонажей 16:9, арена 21:9, отдельные предметы 1:1, слои фона 4:1, UI 16:9.

---

## R1 — Кукла, лист персонажа (самый важный)

Файл: `R01-*-doll-sheet.png`, 16:9.

Промпт:
```
character sheet of a wooden articulated ragdoll fighter, T-pose, four views in a row: front, side, back, three-quarter; neutral unpainted light wood, ball joints clearly visible at neck, shoulders, elbows, hips, knees, ankles; big round head about one quarter of body height, simple torso block, arms and legs in two segments each, flat feet; total 12 parts; plain grey background, orthographic, same scale in all views, [стиль-хвост]
```

Приёмка:
- Считаются 12 частей: голова, торс, плечо и предплечье ×2, бедро и голень ×2, стопы ×2.
- Шарниры видны на всех четырёх ракурсах, пропорции одинаковые.
- Голова примерно четверть роста, стопы плоские, чтобы кукла стояла.
- Нет одежды, оружия, шляп: это базовая модель.

Если не сходится: попросить «exactly 12 parts, no clothing, joints as separate spheres», уменьшить детализацию.

## R2 — Голова и лицо

Файл: `R02-*-face.png`, 16:9. Приложить принятую R1.

Промпт:
```
close-up study of the wooden ragdoll head from the character sheet, three angles: front, three-quarter, profile; a real human photo face is mounted on the head as a slightly curved painted plate with a thin wooden rim; two variants side by side: (a) flat face plate on a sphere, (b) face wrapped into the sphere surface; show how the rim hides the photo edge; plain background, [стиль-хвост]
```

Приёмка: оба варианта показаны, видно, где кончается фото и начинается дерево, лицо не выглядит жутко в профиль. Выбрать вариант и записать выбор в README.

## R3 — Раскраски P1–P4

Файл: `R03-*-colors.png`, 16:9. Приложить R1.

Промпт:
```
four identical wooden ragdoll fighters standing in a row, front view, each wearing a simple painted sleeveless shirt: blue, red, green, yellow; small player badge P1 P2 P3 P4 above heads; same wood tone, same pose, same scale, plain background, [стиль-хвост]
```

Приёмка: куклы идентичны кроме цвета рубашки, цвета различимы на расстоянии.

## R4 — Шляпы

Файл: `R04-*-hats.png`, 16:9. Приложить R1.

Промпт:
```
sheet of eight hats for the wooden ragdoll, each shown on the doll's head in profile and three-quarter view, two rows of four, labeled: golden crown, cowboy hat, knight helmet, viking horned helmet, rubber chicken, cooking pot, baseball cap, metal bucket; chunky toy proportions, same head size in every cell, plain background, [стиль-хвост]
```

Приёмка: 8 шляп, все в одном масштабе относительно головы, у каждой понятно, как она сидит на макушке.

## R5 — Оружие

Файл: `R05-*-weapons.png`, 16:9. Приложить R1.

Промпт:
```
sheet of five toy weapons for the wooden ragdoll, side view, one row, same scale, a small doll hand gripping each to show grip point: two-handed war hammer, spiked mace on a chain with four links, wooden plank with a nail, cast-iron frying pan, burning torch; chunky, readable silhouettes, plain background, [стиль-хвост]
```

Приёмка: 5 предметов, видна точка хвата, цепь булавы из 4 звеньев, масштаб относительно руки одинаковый.

## R6 — Арена «Руины», общий вид

Файл: `R06-*-ruins.png`, 21:9. Сделать 2–3 варианта.

Промпт:
```
ultra-wide side-view 2.5D fighting arena, medieval castle ruins on a sea cliff; three tiers of stone and wooden plank platforms with gaps, a collapsed tower on the right, a bottomless pit on the far left, wooden barrels and crates on platforms, a rope bridge, a red banner with a crown; sea, sailing ship and a small blimp in the far background; warm afternoon light; painted low-poly game environment concept, readable silhouettes, no characters
```

Приёмка:
- Три яруса читаются, перепад между соседними не выше роста куклы (сравнить с R1 на глаз).
- Пропасть слева и башня справа есть.
- Фон отделён от игровой зоны по глубине.

## R7 — Силуэт коллизий арены

Файл: `R07-*-ruins-collision.png`, 21:9. Приложить принятую R6.

Промпт:
```
same composition as the attached arena, but rendered as a collision diagram: all walkable platforms and solid walls filled flat orange, destructible barrels and crates flat blue, decorative background flat grey, sky white; no shading, no texture, crisp edges
```

Приёмка: оранжевое совпадает с платформами R6, синие объекты только там, где реально стоят бочки и ящики.

## R8 — Пропсы

Файл: `R08-*-props.png`, 16:9.

Промпт:
```
prop sheet for a wooden toy arena, same scale: a barrel intact and the same barrel broken into four pieces; a crate intact and broken into six pieces; a short rope bridge segment; a red banner with a golden crown on a pole; a wooden winch with a hanging stone weight; plain background, [стиль-хвост]
```

Приёмка: обломки собираются обратно в целый объект по форме, всё в одном масштабе.

## R9 — Слои параллакса

Четыре файла, 4:1 каждый: `R09-a-sky.png`, `R09-b-sea.png`, `R09-c-far-ruins.png`, `R09-d-foreground.png`. Четыре отдельных диалога.

Промпты:
```
a) wide seamless sky strip, soft cumulus clouds, warm afternoon, painted low-poly style, no ground
b) wide sea strip with a small sailing ship and a blimp, horizon line at the top third, painted low-poly, transparent-ready flat top edge
c) wide strip of distant castle ruins and cliffs, muted blue-grey haze, silhouettes only, painted low-poly
d) wide foreground strip: broken stone blocks and wooden beams along the bottom edge, dark, detailed, painted low-poly, empty above
```

Приёмка: слои складываются в кадр R6 по тонам, у слоёв b, c, d верхний край пустой для наложения.

## R10 — UI-борд

Четыре файла 16:9: `R10-a-menu.png`, `R10-b-hud.png`, `R10-c-ko.png`, `R10-d-results.png`.

Промпты:
```
a) main menu of a physics party game, left column of brush-lettered items PLAY CHARACTERS SETTINGS REPLAYS STATS EXIT, first item highlighted red, right side a wooden ragdoll sitting on a crate in a workshop, dark warm palette, game UI concept
b) in-game HUD overlay on a blurred arena: four player panels at top corners, each with a round photo portrait, colored HP bar with percentage, a big centered timer 00:43, small minimap at right; clean, readable at distance
c) KO title card: huge red brush lettering "KO!", camera shake motion blur, wood splinters, dust, slow-motion vignette, two wooden ragdolls mid-impact
d) match results screen: three podium circles with photo portraits and gold silver bronze rims, titles under each, stats lines KOs damage air time, buttons PLAY AGAIN SAVE REPLAY MAIN MENU, dark panel, brush-lettered header
```

Приёмка: один стиль шрифта и панелей на всех четырёх, элементы читаются при уменьшении вдвое.

## R11 — VFX

Файл: `R11-*-vfx.png`, 16:9.

Промпт:
```
sprite sheet of stylized effects for a wooden toy game: wood splinter burst on impact, dust puff on landing, bright radial flash for knockout, dark slow-motion vignette frame, small hit spark; each effect in 4 frames left to right, black background, painted low-poly style
```

Приёмка: каждое из 5 эффектов в 4 кадрах, читаются на чёрном.

## R12 — Позы для проверки физики

Файл: `R12-*-poses.png`, 16:9. Приложить R1.

Промпт:
```
four panels with the wooden ragdoll fighter: (1) flying backwards after a heavy hit, limbs trailing; (2) falling flat on wooden planks, limbs splayed; (3) standing braced, knees bent, arms up; (4) knocked out, slumped limp against a wall; same doll, same scale, dynamic but readable, [стиль-хвост]
```

Приёмка: по кадрам видно, как должны вести себя суставы: локти и колени не гнутся в обратную сторону, обмякшая кукла складывается в суставах, а не проходит сквозь себя.

## R13 — Материалы

Файл: `R13-*-materials.png`, 16:9.

Промпт:
```
material palette board for a wooden toy game: raw light wood, painted wood with chipped edges in blue red green yellow, dark iron, rough cloth, twisted rope, weathered stone; each as a sphere and a cube with a name label, neutral studio light
```

Приёмка: 7 материалов, у каждого сфера и куб, цвета совпадают с R3.

---

## Итог

**23.09.2026.** Все 13 референсов (19 файлов) сделаны как векторные схемы скриптом `docs/refs/gen_refs.py`, PNG и SVG лежат в `docs/refs/`, журнал в `docs/refs/README.md`. Это технические референсы (размеры, планировка, палитра, макеты), не живопись. Живописные версии при желании генерируются в любом генераторе по промптам выше с приложенной схемой как образцом компоновки; для этапов 02–05 схем достаточно.

Открыто для автора: принять R1 (пропорции), выбрать вариант лица в R2 (a или b), принять компоновку арены R6.
