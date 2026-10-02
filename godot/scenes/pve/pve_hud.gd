## HUD режима волн (scenes/pve/pve_hud.tscn, стиль scenes/ui: hud_theme.tres — тёмные доски с деревянной рамкой, шрифты диктора).
## Дерево — в сцене, здесь поведение:
##   Root/Players  — панели игроков (scenes/ui/player_panel.tscn: портрет цвета игрока + HP), P1 слева сверху, P2 справа;
##   Root/WaveBox  — табличка «ВОЛНА 2/3» и «ВРАГОВ: 3» по центру сверху, под ней строка систем поля (капсом, янтарём, печатается по буквам
##                   TYPE_CPS, держится LINE_HOLD_S и гаснет);
##   Root/Marks    — поверх мира: у каждого живого врага полоска HP над головой (красная, ширина ∝ max_hp — Уборщик длиннее) и
##                   надпись телеграфа (SWEEP! / PARTS! / MINE! / UNSCREW!) из EnemyLook.callout — крупно, с пульсом: видно, КТО
##                   враг и ЧТО он сейчас сделает, на любом зуме камеры (3D-надпись на полном отъезде была бы в 20 px);
##   Root/Announcer — диктор (scenes/ui/announcer.gd): WAVE 1, KO!, CLEAR!, FIELD CLEAR!;
##   Root/EndPanel — итог забега (ПОБЕДА / ПОРАЖЕНИЕ, строка систем поля, «R — заново») — внизу по центру: камера держит игрока в центре
##                   кадра, табличка посередине закрывала бы его (и запоздавшую бочку).
## bind(director): WaveDirector (scripts/pve/wave_director.gd) — подписка по именам сигналов.
class_name PveHud
extends CanvasLayer

const PlayerPanelScene: PackedScene = preload("res://scenes/ui/player_panel.tscn")
const PANEL_SIZE := Vector2(500, 136)
const PANEL_MARGIN := Vector2(24, 18)
const TYPE_CPS := 38.0
const LINE_HOLD_S := 3.2
const LINE_FADE_S := 0.6
const BAR_H := 7.0
const BAR_W_PER_HP := 1.1              # px на 1 HP макс. (Разборщик 40 → 44 px, Уборщик 80 → 88 px)
const BAR_LIFT := 0.55                 # м над головой

var director: Node = null
var panels: Dictionary = {}            # player_index -> PlayerPanel
var _line_full := ""
var _line_t := 0.0
var _clock := 0.0

@onready var root: Control = $Root
@onready var players_root: Control = $Root/Players
@onready var marks: Control = $Root/Marks
@onready var wave_label: Label = $Root/WaveBox/WavePanel/WaveVBox/WaveLabel
@onready var left_label: Label = $Root/WaveBox/WavePanel/WaveVBox/LeftLabel
@onready var field_label: Label = $Root/WaveBox/FieldLine
@onready var announcer: Announcer = $Root/Announcer
@onready var end_panel: PanelContainer = $Root/EndPanel
@onready var end_title: Label = $Root/EndPanel/EndVBox/EndTitle
@onready var end_line: Label = $Root/EndPanel/EndVBox/EndLine


func _ready() -> void:
	end_panel.visible = false
	field_label.text = ""
	marks.draw.connect(_draw_marks)
	wave_label.text = tr("ВОЛНА —")
	left_label.text = ""


func bind(d: Node) -> void:
	director = d
	var pairs := [
		["wave_started", _on_wave_started], ["wave_cleared", _on_wave_cleared], ["enemies_changed", _on_enemies_changed],
		["field_line", _on_field_line], ["run_over", _on_run_over], ["announce", _on_announce], ["hp_changed", _on_hp_changed],
		["ko", _on_ko], ["phase_changed", _on_phase_changed],
	]
	for p in pairs:
		if d.has_signal(p[0]) and not d.is_connected(p[0], p[1]):
			d.connect(p[0], p[1])
	_sync_players()


func _sync_players() -> void:
	if director == null or not director.has_method("players"):
		return
	for p in director.call("players"):
		var pn := panel_for(int((p as Doll).player_index))
		if pn != null:
			pn.set_hp((p as Doll).hp, (p as Doll).max_hp, false)
			pn.set_ko(not (p as Doll).alive)


func panel_for(index: int) -> PlayerPanel:
	if index < 0:
		return null
	if panels.has(index):
		return panels[index]
	var p: PlayerPanel = PlayerPanelScene.instantiate()
	p.slots = 0
	p.player_index = index
	players_root.add_child(p)
	p.set_player(index)
	panels[index] = p
	var right := index % 2 == 1
	p.set_side(right)
	p.anchor_left = 1.0 if right else 0.0
	p.anchor_right = p.anchor_left
	p.offset_top = PANEL_MARGIN.y
	p.offset_bottom = PANEL_MARGIN.y + PANEL_SIZE.y
	if right:
		p.offset_left = -PANEL_MARGIN.x - PANEL_SIZE.x
		p.offset_right = -PANEL_MARGIN.x
	else:
		p.offset_left = PANEL_MARGIN.x
		p.offset_right = PANEL_MARGIN.x + PANEL_SIZE.x
	return p


# --- сигналы режима ---

func _on_wave_started(index: int, total: int, _line: String) -> void:
	wave_label.text = tr("ВОЛНА %d/%d") % [index + 1, total]
	end_panel.visible = false
	_sync_players()


func _on_wave_cleared(index: int, total: int) -> void:
	wave_label.text = tr("ВОЛНА %d/%d — ЧИСТО") % [index + 1, total]


func _on_enemies_changed(left: int, total: int) -> void:
	left_label.text = tr("ВРАГОВ: %d из %d") % [left, total] if total > 0 else ""


func _on_field_line(text: String) -> void:
	_line_full = text
	_line_t = 0.0


func _on_run_over(victory: bool, line: String) -> void:
	end_title.text = tr("ПОБЕДА") if victory else tr("ПОРАЖЕНИЕ")
	end_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if victory else Color(0.95, 0.25, 0.18))
	end_line.text = line
	end_panel.visible = true
	end_panel.modulate.a = 0.0
	var tw := end_panel.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.9)
	tw.tween_property(end_panel, "modulate:a", 1.0, 0.35)


func _on_phase_changed(_p: int) -> void:
	if director != null and String(director.get("wave_state")) == "intro":
		end_panel.visible = false
		wave_label.text = tr("ВОЛНА —")
		_sync_players()


func _on_announce(text: String, color: Color, kind: String) -> void:
	announcer.announce(text, color, kind)


func _on_hp_changed(doll: Doll, hp: float, max_hp: float) -> void:
	if doll == null or not is_instance_valid(doll) or doll.is_in_group("enemies"):
		return
	var p := panel_for(doll.player_index)
	if p != null:
		p.set_hp(hp, max_hp)
		p.set_ko(hp <= 0.0)


func _on_ko(victim: Doll, _attacker: Node, _rec: Dictionary) -> void:
	if victim == null or not is_instance_valid(victim) or victim.is_in_group("enemies"):
		return
	var p := panel_for(victim.player_index)
	if p != null:
		p.set_ko(true)


# --- кадр ---

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_clock += real
	if _line_full != "":
		_line_t += real
		var n := int(_line_t * TYPE_CPS)
		field_label.text = _line_full.substr(0, mini(n, _line_full.length()))
		var type_s := float(_line_full.length()) / TYPE_CPS
		var a := 1.0 - clampf((_line_t - type_s - LINE_HOLD_S) / LINE_FADE_S, 0.0, 1.0)
		field_label.modulate.a = a
		if a <= 0.0:
			_line_full = ""
			field_label.text = ""
	marks.queue_redraw()


## Полоски HP и надписи телеграфа над врагами (проекция ЦМ головы на экран активной камеры).
func _draw_marks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var font := marks.get_theme_font("font", "DisplayLabel")
	if font == null:
		font = ThemeDB.fallback_font
	var vp_size := get_viewport().get_visible_rect().size
	var to_canvas := marks.get_global_transform_with_canvas().affine_inverse()
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Doll
		if e == null or not e.is_inside_tree() or not e.alive or not e.parts.has("Head"):
			continue
		var hp_top := (e.parts["Head"] as Node3D).global_position + Vector3(0.0, BAR_LIFT, 0.0)
		if cam.is_position_behind(hp_top):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(hp_top)
		if sp.x < -100.0 or sp.y < -100.0 or sp.x > vp_size.x + 100.0 or sp.y > vp_size.y + 100.0:
			continue
		var mx := e.max_hp
		var w := mx * BAR_W_PER_HP
		var r := Rect2(sp - Vector2(w * 0.5, BAR_H * 0.5), Vector2(w, BAR_H))
		marks.draw_rect(r.grow(2.0), Color(0.05, 0.03, 0.02, 0.85))
		marks.draw_rect(Rect2(r.position, Vector2(w * clampf(e.hp / maxf(mx, 1.0), 0.0, 1.0), BAR_H)), Color(0.9, 0.18, 0.1))
		var look := e.get_node_or_null("EnemyLook") as EnemyLook
		if look != null and look.callout_active():
			var txt := look.callout
			var size := 40
			var pulse := 1.0 + 0.12 * sin(_clock * 22.0)
			var fs := int(size * pulse)
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var pos := sp + Vector2(-tw.x * 0.5, -14.0)
			marks.draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.06, 0.03, 0.02, 1.0))
			marks.draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, look.callout_colour)
