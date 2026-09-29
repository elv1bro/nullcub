## Полоса глубины для ParallaxScatter3D: из каких элементов, на какой глубине, какого размера и как часто.
## Элементы — папка с manifest.json и PNG от tools/parallax_elements_cut.py (docs/plan-demo/PARALLAX.md).
class_name ParallaxScatterBand
extends Resource

## Папка res:// с manifest.json и PNG элементов.
@export_dir var dir := ""
## Брать только элементы с этими якорями: "bottom" — стоит, "top" — подвешен (цепи, тросы).
@export var anchors := PackedStringArray(["bottom", "top"])
## Глубина z, м: x — дальняя граница, y — ближняя. Каждый элемент — случайная глубина внутри (непрерывный параллакс).
@export var z_range := Vector2(-30.0, -21.0)
## Мировая высота элемента, м (ширина — по пропорциям PNG). Для элементов с "m_per_px" в manifest (запечённые
## 3D-рендеры знают свой масштаб) вместо неё — настоящая высота × scale_range.
@export var height_m := Vector2(10.0, 16.0)
@export var scale_range := Vector2(0.85, 1.15)
## Мировая y основания стоящих элементов, м (ниже тумана/пола — основание спрятано).
@export var base_y := Vector2(-8.0, -5.0)
## Мировая y верхней кромки подвешенных элементов, м (выше кадра — видна только свисающая часть).
@export var top_y := Vector2(19.0, 21.0)
## Зазор между соседями по x, м (отрицательный — перекрытие).
@export var gap_m := Vector2(-2.0, 3.0)
## Зеркалить случайную половину. Только если свет в арте симметричный (контражур, см. бриф).
@export var allow_flip := true
## Доля дымки: x — на дальней границе, y — на ближней. Смешивание в линейном цвете: 0.4 на глаз уже сильная дымка.
@export var haze := Vector2(0.45, 0.2)
@export var haze_color := Color(0.62, 0.54, 0.68)
## Доля высоты снизу, растворяемая в прозрачность (0 — без растворения).
@export_range(0.0, 0.5, 0.01) var base_fade := 0.0
@export var seed := 1
