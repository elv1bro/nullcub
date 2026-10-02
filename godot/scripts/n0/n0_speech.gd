## Субтитр N0 — плашка у самого дрона (N0_VOICE.md, «Реплика»: позиция дрона на экране, прижата к краям, текст набирается
## по буквам). Вид по скину HUD (scripts/ui/hud_skin.gd): трансляция — «нижняя плашка» эфира с янтарным ярлыком «N0», неон —
## голубое стекло, LED — экран самого N0 (голубой текст). Слой создаёт scripts/n0/n0_host.gd. Время реальное (не тормозит
## в стоп-кадре и замедлении удара).
## Облачко над дроном; если над ним полоса HUD (верх top_band кадра) — под дроном. Прячется, пока скрыт HUD (выход бойца),
## в кинематографе крита (Hud.is_cinematic) и на итогах матча.
class_name N0Speech
extends CanvasLayer

@export var chars_per_s := 45.0
@export var hold_s := 1.8
@export var hold_per_char_s := 0.045
@export var fade_s := 0.3
@export var max_width := 460.0
@export var font_size := 21
## Доли кадра сверху (панели HUD) и снизу (подсказка), куда облачко не заходит.
@export var top_band := 0.19
@export var bottom_band := 0.07
## Над/под дроном (м от центра корпуса до края облачка).
@export var top_offset_m := 0.5
@export var bottom_offset_m := 0.45

var text := ""
var drone: Node3D
var hud: Node
var bubble: PanelContainer
var tag: Label
var label: Label
var tail: Polygon2D
var _t := 0.0          # с начала реплики (реальные секунды)
var _dur := 0.0        # набор + держать
var _last_ms := 0
var _placed := false
var _below := false
var _settle := 0          # кадров до показа новой строки
const SETTLE_FRAMES := 2


func _ready() -> void:
	layer = 6   # над стрелками за экраном (5), под HUD (10): карточка KO и итоги — поверх
	bubble = PanelContainer.new()
	bubble.name = "Bubble"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bubble)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(row)
	tag = Label.new()
	tag.name = "Tag"
	tag.text = "N0"
	tag.size_flags_vertical = Control.SIZE_FILL
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tag)
	label = Label.new()
	label.name = "Text"
	label.autowrap_mode = TextServer.AUTOWRAP_OFF   # строки разбивает say() (wrap): размер облачка не ждёт раскладки
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lm := StyleBoxEmpty.new()
	lm.content_margin_top = 8.0
	lm.content_margin_bottom = 9.0
	label.add_theme_stylebox_override("normal", lm)
	row.add_child(label)
	tail = Polygon2D.new()
	tail.name = "Tail"
	add_child(tail)
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())
	_hide()
	_last_ms = Time.get_ticks_msec()


## Панель, ярлык, текст и хвостик по текущему скину HUD.
func _apply_skin() -> void:
	bubble.add_theme_stylebox_override("panel", HudSkin.panel("n0"))
	tag.add_theme_stylebox_override("normal", HudSkin.panel("n0_tag"))
	match HudSkin.id():
		"neon":
			HudSkin.style_label(tag, "display", font_size + 4, HudSkin.NEON_AMBER)
			HudSkin.style_label(label, "body", font_size, Color(0.92, 0.99, 1.0), HudSkin.NEON)
		"led":   # экран N0: голубые строки
			HudSkin.style_label(tag, "display", font_size + 6, HudSkin.LED_CYAN)
			HudSkin.style_label(label, "body", font_size, HudSkin.LED_CYAN)
		_:
			HudSkin.style_label(tag, "display", font_size + 4, Broadcast.INK)
			HudSkin.style_label(label, "body", font_size, Broadcast.TEXT)
	tail.color = HudSkin.panel_bg("n0")
	if text != "":
		label.text = wrap_lines(text, label.get_theme_font("font"), font_size, max_width)
		bubble.reset_size()


## Сказать реплику: перебивает текущую.
func say(line: String) -> void:
	text = line
	_t = 0.0
	_dur = float(line.length()) / chars_per_s + hold_s + hold_per_char_s * line.length()
	label.text = wrap_lines(line, label.get_theme_font("font"), font_size, max_width)
	label.visible_characters = 0
	bubble.reset_size()
	bubble.modulate.a = 1.0
	tail.modulate.a = 1.0
	_placed = false
	_settle = SETTLE_FRAMES
	_hide()   # до пересчёта размеров не показывать (иначе прошлое облачко на кадр раздувается под новую строку)


## Разбить строку по словам на строки не шире width (px) — с явными переносами: у Label с автопереносом высота считается
## от ширины после раскладки контейнера, и в первый кадр облачко бывало огромным (отчёт сессии эффектов 02.10).
static func wrap_lines(line: String, font: Font, size: int, width: float) -> String:
	if font == null:
		return line
	var para := TextParagraph.new()
	para.add_string(line, font, size)
	para.width = width
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	var out := PackedStringArray()
	for i in para.get_line_count():
		var r := para.get_line_range(i)
		out.append(line.substr(r.x, r.y - r.x).strip_edges())
	return "\n".join(out)


## N0 ещё говорит (набирает или держит реплику).
func speaking() -> bool:
	return text != "" and _t < _dur


## Набор идёт (N0Drone.talking — корпус подпрыгивает в такт).
func typing() -> bool:
	return text != "" and label.visible_characters >= 0 and label.visible_characters < text.length()


## Облачко на экране сейчас (для проб).
func shown() -> bool:
	return bubble.visible and text != ""


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	if text == "":
		return
	_t += real
	if _t >= _dur + fade_s:
		text = ""
		_hide()
		return
	label.visible_characters = mini(int(_t * chars_per_s), text.length())
	if label.visible_characters >= text.length():
		label.visible_characters = -1
	var a := 1.0 - clampf((_t - _dur) / fade_s, 0.0, 1.0)
	bubble.modulate.a = a
	tail.modulate.a = a
	if _settle > 0:   # новая строка: контейнер ещё не пересчитал размер — первый кадр облачко было огромным (отчёт сессии эффектов)
		_settle -= 1
		bubble.reset_size()
		_hide()
		return
	if _suppressed():
		bubble.visible = false
		tail.visible = false
		return
	_place()


func _hide() -> void:
	bubble.visible = false
	tail.visible = false


func _suppressed() -> bool:
	if drone == null or not is_instance_valid(drone) or not drone.is_visible_in_tree():
		return true
	if hud == null or not is_instance_valid(hud):
		hud = get_tree().get_first_node_in_group("hud")
	if hud != null:
		if hud is CanvasLayer and not (hud as CanvasLayer).visible:
			return true
		if hud.has_method("is_cinematic") and bool(hud.call("is_cinematic")):
			return true
		var res: Variant = hud.get("results")
		if res is CanvasItem and (res as CanvasItem).visible:
			return true
	return false


func _place() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(drone.global_position):
		_hide()
		return
	var vs := get_viewport().get_visible_rect().size
	bubble.reset_size()   # подогнать под строку (короткая после длинной — облачко ужимается)
	var top := cam.unproject_position(drone.global_position + Vector3(0.0, top_offset_m, 0.0))
	var bot := cam.unproject_position(drone.global_position - Vector3(0.0, bottom_offset_m, 0.0))
	var sz := bubble.size
	var gap := 16.0
	var y_min := vs.y * top_band
	var y_max := vs.y * (1.0 - bottom_band) - sz.y
	var want := Vector2(top.x - sz.x * 0.5, top.y - gap - sz.y)
	var below := want.y < y_min
	if below:
		want.y = bot.y + gap
	want.x = clampf(want.x, 16.0, vs.x - 16.0 - sz.x)
	want.y = clampf(want.y, y_min, maxf(y_min, y_max))
	if not _placed or below != _below:
		bubble.position = want
	else:
		bubble.position = bubble.position.lerp(want, 0.35)
	_placed = true
	_below = below
	bubble.visible = true
	# хвостик: от края облачка к дрону
	var anchor := bot if below else top
	var edge_y := bubble.position.y if below else bubble.position.y + sz.y
	var bx := clampf(anchor.x, bubble.position.x + 18.0, bubble.position.x + sz.x - 18.0)
	var tip := Vector2(anchor.x, anchor.y)
	var d := tip - Vector2(bx, edge_y)
	if d.length() > 14.0:
		tip = Vector2(bx, edge_y) + d.normalized() * 14.0
	var inset := 1.0 if below else -1.0
	tail.polygon = PackedVector2Array([Vector2(bx - 9.0, edge_y + inset), Vector2(bx + 9.0, edge_y + inset), tip])
	tail.visible = d.length() > 4.0
