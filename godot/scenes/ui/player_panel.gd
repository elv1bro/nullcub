## Панель игрока в HUD (R20): круглый портрет с кольцом цветом игрока и подписью «P1», справа — короны побед
## в раундах (slots 0..3) над полосой HP, под полосой счётчик комбо «×N» (появляется с n ≥ 2, «пружинит» при росте).
## set_side(true) зеркалит панель для правого края экрана (P2/P4): портрет справа, заливка HP от правого края.
## Дерево узлов — scenes/ui/player_panel.tscn; здесь только поведение. Цвет — Tuning.PLAYER_COLORS[player_index].
class_name PlayerPanel
extends Control

const CROWN: Texture2D = preload("res://assets/ui/crown.png")
const CROWN_SIZE := 36.0
const CROWN_ON := Color(1.0, 0.86, 0.4, 1.0)
const CROWN_OFF := Color(0.42, 0.38, 0.34, 0.75)

var player_index := 0
var colour := Color.WHITE
var right_side := false
var wins := 0
var slots := 2
var combo := 0

@onready var row: HBoxContainer = $Row
@onready var portrait_col: VBoxContainer = $Row/PortraitCol
@onready var bar_col: VBoxContainer = $Row/BarCol
@onready var portrait: Portrait = $Row/PortraitCol/Portrait
@onready var name_label: Label = $Row/PortraitCol/Name
@onready var crowns: HBoxContainer = $Row/BarCol/Crowns
@onready var hp_bar: HpBar = $Row/BarCol/HpBar
@onready var combo_row: HBoxContainer = $Row/BarCol/ComboRow
@onready var combo_label: Label = $Row/BarCol/ComboRow/Combo


func _ready() -> void:
	combo_label.visible = false
	set_player(player_index)
	set_round_slots(slots)


func set_player(index: int) -> void:
	player_index = index
	colour = Tuning.PLAYER_COLORS[clampi(index, 0, Tuning.PLAYER_COLORS.size() - 1)]
	portrait.set_player(index)
	name_label.text = "P%d" % (index + 1)
	name_label.add_theme_color_override("font_color", colour.lightened(0.35))
	hp_bar.colour = colour
	hp_bar.queue_redraw()


func set_side(right: bool) -> void:
	right_side = right
	row.move_child(portrait_col, 1 if right else 0)
	row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	crowns.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	combo_row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	hp_bar.fill_from_right = right
	hp_bar.queue_redraw()


func set_hp(hp: float, max_hp: float = Tuning.MAX_HP, animate: bool = true) -> void:
	hp_bar.max_hp = max_hp
	hp_bar.set_hp(hp, animate)


func set_combo(n: int) -> void:
	var grew := n > combo
	combo = n
	if n < 2:
		combo_label.visible = false
		return
	combo_label.text = "×%d" % n
	combo_label.add_theme_color_override("font_color", Announcer.combo_colour(n))
	combo_label.visible = true
	if grew:
		combo_label.pivot_offset = combo_label.get_minimum_size() * 0.5
		combo_label.scale = Vector2(1.6, 1.6)
		var tw := combo_label.create_tween().set_ignore_time_scale(true)
		tw.tween_property(combo_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_ko(ko: bool) -> void:
	portrait.set_ko(ko)
	if ko:
		hp_bar.set_hp(0.0)
		combo_label.visible = false
	name_label.modulate = Color(0.6, 0.6, 0.6, 1.0) if ko else Color.WHITE


func reset() -> void:
	set_ko(false)
	set_combo(0)
	hp_bar.set_hp(hp_bar.max_hp, false)


func set_round_slots(n: int) -> void:
	slots = clampi(n, 0, 3)
	for c in crowns.get_children():
		c.queue_free()
	for i in range(slots):
		var t := TextureRect.new()
		t.texture = CROWN
		t.custom_minimum_size = Vector2(CROWN_SIZE, CROWN_SIZE)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crowns.add_child(t)
	crowns.visible = slots > 0
	set_wins(wins)


func set_wins(n: int) -> void:
	wins = clampi(n, 0, 3)
	var i := 0
	for c in crowns.get_children():
		if c is TextureRect:
			(c as TextureRect).modulate = CROWN_ON if i < wins else CROWN_OFF
			i += 1
