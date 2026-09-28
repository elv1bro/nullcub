## Диктор (INSPIRATION_GAMES.md, Ragdoll Masters): надписи по центру экрана крупным «кистевым» шрифтом
## (SystemFont Impact/Arial Black, курсив, тёмная обводка — hud_theme.tres, тип AnnounceLabel).
## announce(text, color, kind): цвет — переданный, иначе по kind/тексту: FIGHT! белый, HEAD BLOW! красно-оранжевый,
## BODY BLOW! зелёный, DOUBLE BLOW! бело-жёлтый, N HIT COMBO! синий → фиолетовый с ростом n, KO! красный,
## SUDDEN DEATH оранжевый. Появление scale-in 0.1 с, удержание 0.5 с, затухание 0.2 с; в стеке не больше двух
## (старая уходит сразу). Одинаковый текст в окне DEDUPE_S (взаимный удар: HEAD BLOW! у обоих в один кадр) не дублируется —
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
		return 128
	if k == "fight" or k == "sudden":
		return 116
	if k == "countdown":
		return 140
	return 96


func announce(text: String, color: Color = Color(0, 0, 0, 0), kind: String = "") -> void:
	var now := Time.get_ticks_msec()
	for c in stack.get_children():
		var same := c as Label
		if same == null or same.text != text:
			continue
		if now - int(same.get_meta("born_ms", 0)) > int(DEDUPE_S * 1000.0):
			continue
		var pulse := same.create_tween().set_ignore_time_scale(true)
		pulse.tween_property(same, "scale", Vector2(1.18, 1.18), 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pulse.tween_property(same, "scale", Vector2.ONE, 0.08)
		return
	while stack.get_child_count() >= MAX_STACK:
		var old := stack.get_child(0)
		stack.remove_child(old)
		old.queue_free()
	var l := Label.new()
	l.theme_type_variation = &"AnnounceLabel"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", colour_for(kind, text, color))
	l.add_theme_font_size_override("font_size", font_size_for(kind, text))
	l.rotation = deg_to_rad(randf_range(-3.0, 3.0))
	l.set_meta("born_ms", now)
	stack.add_child(l)
	l.pivot_offset = l.get_minimum_size() * 0.5
	l.scale = Vector2(0.2, 0.2)
	var tw := l.create_tween().set_ignore_time_scale(true)
	tw.tween_property(l, "scale", Vector2(1.12, 1.12), SCALE_IN_S * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, SCALE_IN_S * 0.3)
	tw.tween_interval(HOLD_S)
	tw.tween_property(l, "modulate:a", 0.0, FADE_S)
	tw.tween_callback(l.queue_free)


func clear() -> void:
	for c in stack.get_children():
		stack.remove_child(c)
		c.queue_free()
