## Панель игрока в HUD — вид по скину (scripts/ui/hud_skin.gd: трансляция / неон / LED, меняется на лету): плашка панели
## (трансляция — косая с полосой цвета игрока по внешнему краю и янтарной снизу, неон — стекло с краем цвета игрока, LED —
## чёрное табло), портрет с инициалами «P1» (или фото), справа имя капсом, метки побед в раундах (slots 0..3) и полоса HP;
## под плашкой — счётчик комбо «×N» (появляется с n ≥ 2, «пружинит» при росте). set_side(true) зеркалит панель для правого края
## (P2/P4): портрет справа, наклон зеркальный, заливка HP от правого края. Имя — «ИГРОК N», set_display_name — своё (кампания).
## Дерево узлов — scenes/ui/player_panel.tscn; здесь поведение и плашка (_draw). Цвет — Tuning.PLAYER_COLORS[player_index].
class_name PlayerPanel
extends Control

const PLATE_H := 112.0
const PIP_SIZE := Vector2(26, 10)
const NAME_SIZE := 28

var player_index := 0
var colour := Color.WHITE
var right_side := false
var wins := 0
var slots := 2
var combo := 0
var display_name := ""


@onready var row: HBoxContainer = $Row
@onready var portrait_col: VBoxContainer = $Row/PortraitCol
@onready var bar_col: VBoxContainer = $Row/BarCol
@onready var portrait: Portrait = $Row/PortraitCol/Portrait
@onready var top_row: HBoxContainer = $Row/BarCol/Top
@onready var name_label: Label = $Row/BarCol/Top/Name
@onready var crowns: HBoxContainer = $Row/BarCol/Top/Crowns
@onready var hp_bar: HpBar = $Row/BarCol/HpBar
@onready var charge_bar: ChargeBar = $Row/BarCol/ChargeBar
@onready var combo_row: HBoxContainer = $ComboRow
@onready var combo_label: Label = $ComboRow/Combo


func _ready() -> void:
	combo_label.visible = false
	set_player(player_index)
	set_round_slots(slots)
	resized.connect(queue_redraw)
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())


## Шрифты, цвета и панели по текущему скину (зовётся и при смене скина).
func _apply_skin() -> void:
	HudSkin.style_label(name_label, "plate", NAME_SIZE, HudSkin.text_colour(), colour)
	combo_label.add_theme_stylebox_override("normal", HudSkin.panel("combo"))
	HudSkin.style_label(combo_label, "display", 24, HudSkin.text_for("gold"))
	set_wins(wins)
	hp_bar.queue_redraw()
	portrait.queue_redraw()
	queue_redraw()


func _draw() -> void:
	HudSkin.panel("player", colour, right_side).draw(get_canvas_item(), Rect2(Vector2.ZERO, Vector2(size.x, PLATE_H)))


func set_player(index: int) -> void:
	player_index = index
	colour = Tuning.PLAYER_COLORS[clampi(index, 0, Tuning.PLAYER_COLORS.size() - 1)]
	portrait.set_player(index)
	name_label.text = display_name.to_upper() if display_name != "" else default_name(index)
	hp_bar.colour = colour
	_apply_skin()


## Имя на плашке без своего: «ИГРОК 1» (в блоке-портрете и так «P1»).
static func default_name(index: int) -> String:
	return "ИГРОК %d" % (index + 1)


## Имя на плашке (кампания: имя игрока и титул соперника); "" — снова «ИГРОК N».
func set_display_name(text: String) -> void:
	display_name = text
	name_label.text = text.to_upper() if text != "" else default_name(player_index)


func set_side(right: bool) -> void:
	right_side = right
	row.move_child(portrait_col, 1 if right else 0)
	row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	top_row.move_child(crowns, 0 if right else 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	combo_row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
	portrait.mirror = right
	portrait.queue_redraw()
	hp_bar.fill_from_right = right
	hp_bar.queue_redraw()
	charge_bar.fill_from_right = right
	charge_bar.queue_redraw()
	set_wins(wins)
	queue_redraw()


func set_hp(hp: float, max_hp: float = Tuning.MAX_HP, animate: bool = true) -> void:
	hp_bar.max_hp = max_hp
	hp_bar.set_hp(hp, animate)


## Заряд бойца (COMBAT_CHARGE.md): значение и «выдохся»; зовёт Hud каждый кадр из Doll.charge / charge_locked.
func set_charge(value: float, locked: bool) -> void:
	charge_bar.set_charge(value, locked)


func set_combo(n: int) -> void:
	var grew := n > combo
	combo = n
	if n < 2:
		combo_label.visible = false
		return
	combo_label.text = "×%d" % n
	combo_label.visible = true
	if grew:
		combo_label.pivot_offset = combo_label.get_minimum_size() * 0.5
		combo_label.scale = Vector2(1.5, 1.5)
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
	charge_bar.snap(Tuning.CHARGE_MAX)


func set_round_slots(n: int) -> void:
	slots = clampi(n, 0, 3)
	for c in crowns.get_children():
		c.queue_free()
	for i in range(slots):
		var p := Panel.new()
		p.custom_minimum_size = PIP_SIZE
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crowns.add_child(p)
	crowns.visible = slots > 0
	set_wins(wins)


func set_wins(n: int) -> void:
	wins = clampi(n, 0, 3)
	var i := 0
	for c in crowns.get_children():
		if c is Panel and not c.is_queued_for_deletion():
			(c as Panel).add_theme_stylebox_override("panel", HudSkin.panel("pip_on" if i < wins else "pip_off", colour, right_side))
			i += 1
