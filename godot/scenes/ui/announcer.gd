## Диктор / строки табло (INSPIRATION_GAMES.md; вид по скину HUD — scripts/ui/hud_skin.gd): надпись по центру экрана.
## Группы: gold — отсчёт и FIGHT!, alert — KO! и SUDDEN DEATH, event — HEAD / BODY / DOUBLE BLOW!, N HIT COMBO!, свои строки
## (цвет события — переданный, иначе по kind/тексту: HEAD BLOW! красно-оранжевый, BODY BLOW! зелёный, DOUBLE BLOW! бело-жёлтый,
## N HIT COMBO! синий → фиолетовый с ростом n). Трансляция — косая плашка (gold — янтарная, alert — красная, event — тёмная
## с полосой цвета события) и вход «выезжает слева»; неон — светящийся текст без плашки, вход с отскоком; LED — чёрная панель
## табло и точки светодиодов, вход с миганием. Удержание 0.5 с, затухание 0.2 с; в стеке не больше двух (старая уходит
## сразу). Дети Stack — PanelContainer (meta "text" — строка), внутри Label. Одинаковый текст в окне DEDUPE_S (взаимный удар: HEAD BLOW! у обоих в один кадр) не дублируется —
## существующая надпись только «подпрыгивает». Анимации по реальному времени (Tween.set_ignore_time_scale) — hit-stop их не тормозит.
## Узел Stack (VBoxContainer по центру) живёт в scenes/ui/hud.tscn.
class_name Announcer
extends Control

const SCALE_IN_S := 0.1
const HOLD_S := 0.5
const FADE_S := 0.2
const MAX_STACK := 2
const DEDUPE_S := 0.45
const COLOURS := {
	"fight": Color(1.0, 1.0, 1.0),
	"head": Color(1.0, 0.36, 0.16),
	"body": Color(0.45, 0.9, 0.35),
	"double": Color(1.0, 0.97, 0.62),
	"ko": Color(0.93, 0.14, 0.1),
	"sudden": Color(1.0, 0.6, 0.15),
	"countdown": Color(1.0, 0.92, 0.7),
}

@onready var stack: VBoxContainer = $Stack


static func combo_colour(n: int) -> Color:
	var t := clampf(float(n - 2) / 4.0, 0.0, 1.0)
	return Color(0.4, 0.66, 1.0).lerp(Color(0.75, 0.32, 1.0), t)


## Ведущее число из текста вроде "3 HIT COMBO!" (0, если его нет).
static func leading_int(text: String) -> int:
	var digits := ""
	for ch in text.strip_edges():
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	return int(digits) if digits != "" else 0


static func kind_of(kind: String, text: String) -> String:
	var k := kind.to_lower()
	var t := text.to_upper()
	for key in COLOURS.keys():
		if k.contains(key):
			return key
	if k.contains("combo") or t.contains("COMBO"):
		return "combo"
	if t.begins_with("FIGHT"):
		return "fight"
	if t.begins_with("HEAD"):
		return "head"
	if t.begins_with("BODY"):
		return "body"
	if t.begins_with("DOUBLE"):
		return "double"
	if t.begins_with("KO"):
		return "ko"
	if t.begins_with("SUDDEN"):
		return "sudden"
	return ""


static func colour_for(kind: String, text: String, given: Color) -> Color:
	if given.a > 0.0 and given.r + given.g + given.b > 0.05:
		return given
	var k := kind_of(kind, text)
	if k == "combo":
		return combo_colour(maxi(leading_int(text), 2))
	if COLOURS.has(k):
		return COLOURS[k]
	return Color.WHITE


static func font_size_for(kind: String, text: String) -> int:
	var k := kind_of(kind, text)
	if k == "ko":
		return 116
	if k == "fight" or k == "sudden":
		return 104
	if k == "countdown":
		return 128
	return 80


## Группа надписи для скина: gold / alert / event.
static func group_of(kind: String, text: String) -> String:
	var k := kind_of(kind, text)
	if k == "countdown" or k == "fight":
		return "gold"
	if k == "ko" or k == "sudden":
		return "alert"
	return "event"


func announce(text: String, color: Color = Color(0, 0, 0, 0), kind: String = "") -> void:
	var now := Time.get_ticks_msec()
	for c in stack.get_children():
		var same := c as Control
		if same == null or String(same.get_meta("text", "")) != text:
			continue
		if now - int(same.get_meta("born_ms", 0)) > int(DEDUPE_S * 1000.0):
			continue
		var pulse := same.create_tween().set_ignore_time_scale(true)
		pulse.tween_property(same, "scale", Vector2(1.08, 1.08), 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pulse.tween_property(same, "scale", Vector2.ONE, 0.08)
		return
	while stack.get_child_count() >= MAX_STACK:
		var old := stack.get_child(0)
		stack.remove_child(old)
		old.queue_free()
	var group := group_of(kind, text)
	var ev := colour_for(kind, text, color)
	var fs := font_size_for(kind, text)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", HudSkin.panel("announce", ev, false, group))
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_meta("text", text)
	plate.set_meta("born_ms", now)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudSkin.style_label(l, "display", fs, HudSkin.text_for(group, ev), ev)
	plate.add_child(l)
	stack.add_child(plate)
	var tw := plate.create_tween().set_ignore_time_scale(true)
	match HudSkin.id():
		"neon":   # вспышка с отскоком
			plate.pivot_offset = plate.get_minimum_size() * 0.5
			plate.scale = Vector2(0.4, 0.4)
			plate.modulate.a = 0.0
			tw.set_parallel(true)
			tw.tween_property(plate, "scale", Vector2(1.08, 1.08), SCALE_IN_S * 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(plate, "modulate:a", 1.0, SCALE_IN_S * 0.5)
			tw.set_parallel(false)
			tw.tween_property(plate, "scale", Vector2.ONE, SCALE_IN_S * 0.4)
		"led":    # табло загорается с миганием
			plate.modulate.a = 0.0
			tw.tween_property(plate, "modulate:a", 1.0, 0.02)
			tw.tween_property(plate, "modulate:a", 0.35, 0.03)
			tw.tween_property(plate, "modulate:a", 1.0, 0.03)
		_:        # плашка «выезжает» слева
			plate.pivot_offset = Vector2(0.0, plate.get_minimum_size().y * 0.5)
			plate.scale = Vector2(0.05, 1.0)
			tw.tween_property(plate, "scale", Vector2(1.04, 1.0), SCALE_IN_S * 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(plate, "scale", Vector2.ONE, SCALE_IN_S * 0.3)
	tw.tween_interval(HOLD_S)
	tw.tween_property(plate, "modulate:a", 0.0, FADE_S)
	tw.tween_callback(plate.queue_free)


func clear() -> void:
	for c in stack.get_children():
		stack.remove_child(c)
		c.queue_free()
