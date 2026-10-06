## Токены оформления «прямого эфира Лиги» (docs/plan-demo/look/show.md, LOOK_PASS.md п. 6): одна палитра и два шрифта на весь эфир —
## HUD боя и HUD режимов (стычка, спорт, бомба, гонка), плашки бойцов, заставка между сценами.
##   Палитра: голубой NULL (поле, N0), янтарь Лиги (свет ферм, полоса эфира), синий / красный команд (= Tuning.PLAYER_COLORS 0 / 1),
##            тёмно-синяя плашка, белый текст, приглушённый текст, красный тревоги.
##   Шрифты:  Oswald (OFL, assets/fonts) — заголовки, имена, цифры (три веса); Rubik (OFL) — подписи и реплики. Оба с кириллицей, лежат
##            в проекте (на машине без DIN Condensed / Avenir HUD больше не падает в узкий Arial).
## «Единый HUD» (пункт панели «ВИД» show_hud): unified = true — HudSkin.font() / HudSkin.theme() отдают шрифты токенов (у каждого скина
## свои эффекты: трансляция — наклон крупных надписей, неон — разрядка и свечение, LED — точки), а плашки HUD режимов (StyleBoxFlat:
## тёмный прямоугольник с полосой цвета) перекрашиваются на месте в грамматику текущего скина (restyle_flat / restore_flat; HudUnify).
## Без автозагрузок: класс стоит в цепочке hud_skin.gd → hud.gd → modular_doll.gd, которую грузят сборщики в режиме -s.
class_name ShowTokens
extends RefCounted

const NULL_BLUE := Color(0.27, 0.89, 1.0)          # поле NULL, глаза N0 (BRAND.md #5ce1ff ≈ Broadcast.FIELD)
const AMBER := Color(0.941, 0.667, 0.145)          # янтарь Лиги (Broadcast.AMBER)
const TEAM_BLUE := Color("2f6fde")                 # = Tuning.PLAYER_COLORS[0] = SQUAD_COLORS[0]
const TEAM_RED := Color("d9342b")                  # = Tuning.PLAYER_COLORS[1] = SQUAD_COLORS[1]
const PLATE := Color(0.04, 0.063, 0.118, 0.93)     # тёмно-синяя плашка эфира
const PLATE_LIGHT := Color(0.11, 0.153, 0.259, 1.0)
const INK := Color(0.06, 0.06, 0.07)               # текст на янтаре
const TEXT := Color(0.97, 0.97, 0.98)
const MUTED := Color(0.64, 0.69, 0.78)
const ALERT := Color(0.86, 0.13, 0.11)
const SKEW := 0.21                                 # tan 12°: наклон плашек трансляции

const OSWALD := "res://assets/fonts/Oswald.ttf"
const RUBIK := "res://assets/fonts/Rubik.ttf"
const META := &"show_orig"

## «Единый HUD» включён (ставит LeagueShow по пункту show_hud; без него — как было).
static var unified := false

static var _fonts := {}
static var _themes := {}


## Цвет команды / игрока: 0 — синие, 1 — красные, дальше — цвета игроков P3+ как есть.
static func team(i: int, others: Array = []) -> Color:
	if i == 0:
		return TEAM_BLUE
	if i == 1:
		return TEAM_RED
	return others[i] if i >= 0 and i < others.size() else AMBER


## Шрифт токена: title(вес) — Oswald, text() — Rubik.
static func title(weight := 650) -> Font:
	return _variation(OSWALD, weight, "", 0)


static func text(weight := 500) -> Font:
	return _variation(RUBIK, weight, "", 0)


## Шрифт роли HudSkin в скине: display — крупные надписи, plate — имена и подписи, digits — цифры табло, body — реплики.
static func font(role: String, skin: String) -> Font:
	match role:
		"body":
			return _variation(RUBIK, 500, skin, 1 if skin == "neon" else 0)
		"digits":
			return _variation(OSWALD, 600, skin, 2 if skin == "neon" else 0)
		"plate":
			return _variation(OSWALD, 600, skin, 2 if skin == "neon" else 1)
	# display: трансляция — с наклоном (как курсив Avenir Condensed), неон — разрядка, LED — прямо
	return _variation(OSWALD, 700, skin + ("/slant" if skin == "broadcast" else ""), 3 if skin == "neon" else 1)


static func _variation(path: String, weight: int, key: String, spacing: int) -> Font:
	var k := "%s/%d/%s/%d" % [path.get_file(), weight, key, spacing]
	if _fonts.has(k):
		return _fonts[k]
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	fv.spacing_glyph = spacing
	if key.ends_with("/slant"):
		fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(0.2, 1.0), Vector2.ZERO)
	_fonts[k] = fv
	return fv


## Тема HUD скина с шрифтами токенов (стили и цвета — из темы скина). Кэш по скину.
static func theme_for(skin: String, base: Theme) -> Theme:
	if _themes.has(skin):
		return _themes[skin]
	var t := base.duplicate() as Theme
	t.default_font = font("plate", skin)
	for v in ["AnnounceLabel", "BrushLabel", "DisplayLabel", "Button"]:
		t.set_font("font", v, font("display", skin))
	for v in ["SmallCaps", "StatLabel", "Label"]:
		t.set_font("font", v, font("plate", skin))
	for v in ["StatValue", "TimerLabel"]:
		t.set_font("font", v, font("digits", skin))
	_themes[skin] = t
	return t


## Цвет-«удостоверение» плашки режима → цвет палитры: синий → синие команды, красный → красные, янтарь / оранжевый → янтарь Лиги,
## голубой → NULL; зелёный, фиолетовый (игроки P3, P5) и серый (выбывший) — как есть.
static func token_colour(c: Color) -> Color:
	if c.a <= 0.01 or c.s < 0.25 or c.v < 0.2:
		return c
	var h := c.h * 360.0
	var out := c
	if h >= 175.0 and h < 200.0:
		out = NULL_BLUE
	elif h >= 200.0 and h < 250.0:
		out = TEAM_BLUE.lightened(0.25)
	elif h >= 340.0 or h < 12.0:
		out = TEAM_RED.lightened(0.15)
	elif h >= 12.0 and h < 52.0:
		out = AMBER
	else:
		return c
	return Color(out, c.a)


const _FLAT_PROPS := ["bg_color", "border_color", "border_width_left", "border_width_top", "border_width_right", "border_width_bottom",
	"corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_right", "corner_radius_bottom_left", "skew",
	"shadow_color", "shadow_size", "shadow_offset", "border_blend", "anti_aliasing"]


## Перекрасить плашку режима на месте в грамматику скина (исходные свойства — в мете META; повторный вызов ничего не делает).
static func restyle_flat(sb: StyleBoxFlat, skin: String) -> void:
	if sb == null or sb.has_meta(META):
		return
	var orig := {}
	for p in _FLAT_PROPS:
		orig[p] = sb.get(p)
	sb.set_meta(META, orig)
	var bw := maxi(maxi(sb.border_width_left, sb.border_width_right), maxi(sb.border_width_top, sb.border_width_bottom))
	var has_id := bw > 0 and sb.border_color.a > 0.05
	var idc := token_colour(sb.border_color) if has_id else AMBER
	var hot := sb.bg_color.s > 0.35 and sb.bg_color.v > 0.12      # подсвеченная плашка (держатель бомбы, лидер гонки)
	var all_sides := sb.border_width_left > 0 and sb.border_width_right > 0 and sb.border_width_top > 0
	sb.anti_aliasing = true
	sb.border_blend = false
	match skin:
		"neon":
			sb.bg_color = Color(token_colour(sb.bg_color).darkened(0.55), 0.78) if hot else Color(0.02, 0.035, 0.07, 0.72)
			sb.border_color = Color(idc, 0.9)
			sb.set_border_width_all(3 if all_sides else 2)
			sb.set_corner_radius_all(8)
			sb.skew = Vector2.ZERO
			sb.shadow_color = Color(idc, 0.42)
			sb.shadow_size = 14
			sb.shadow_offset = Vector2.ZERO
		"led":
			sb.bg_color = Color(token_colour(sb.bg_color).darkened(0.7), 0.95) if hot else Color(0.016, 0.018, 0.022, 0.95)
			sb.border_color = idc.darkened(0.35) if has_id else Color(0.15, 0.16, 0.18)
			sb.set_border_width_all(3 if all_sides else 2)
			sb.set_corner_radius_all(4)
			sb.skew = Vector2.ZERO
			sb.shadow_color = Color(0, 0, 0, 0.55)
			sb.shadow_size = 8
			sb.shadow_offset = Vector2.ZERO
		_:
			# трансляция: косая тёмно-синяя плашка (как панели и таймер HUD боя), полоса цвета снизу, у «горячей» — рамка целиком
			sb.bg_color = Color(token_colour(sb.bg_color).darkened(0.35), 0.93) if hot else PLATE
			sb.border_color = idc
			sb.set_border_width_all(0)
			sb.border_width_bottom = 6 if has_id else 5
			if all_sides:
				sb.set_border_width_all(4)
				sb.border_width_bottom = 7
			sb.set_corner_radius_all(0)
			sb.skew = Vector2(SKEW * 0.5, 0.0)
			sb.shadow_color = Color(0, 0, 0, 0.35)
			sb.shadow_size = 2
			sb.shadow_offset = Vector2(0, 4)


## Вернуть плашке исходный вид (после restyle_flat).
static func restore_flat(sb: StyleBoxFlat) -> void:
	if sb == null or not sb.has_meta(META):
		return
	var orig: Dictionary = sb.get_meta(META)
	for p in orig:
		sb.set(p, orig[p])
	sb.remove_meta(META)
