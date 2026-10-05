## Счёт спорт-зала поверх боевого HUD (docs/plan-demo/SPORT.md): две плашки с цифрами по бокам от таймера — слева команда P1,
## справа команда P2, цвет — цвет игрока (Tuning.PLAYER_COLORS), под таймером подпись «ВИД · ДО N». Гол — цифра забившего
## «подпрыгивает». Шрифт и эффект — по скину HUD (HudSkin.style_label), смена скина перекрашивает на лету.
## Золотой гол: подпись боевого HUD под таймером — GOLDEN GOAL вместо SUDDEN DEATH. Итоги: к WINS! дописывается счёт.
## Дерево строит сам; bind(match, hud) — подписка на SportMatch (score_changed, goal_scored, sport_changed, phase_changed).
class_name SportHud
extends CanvasLayer

const PLATE_W := 120.0
const PLATE_H := 92.0
const GAP := 164.0          # от центра экрана до ближнего края плашки (таймер HUD — ±150)
const TOP := 14.0
const SCORE_PX := 76
const CAPTION_PX := 24

var match_node: SportMatch
var hud: Hud
var labels: Array = []      # [Label слева, Label справа]
var caption: Label
var _root: Control
var _plates: Array = []


func _init() -> void:
	layer = 11


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	for i in 2:
		var plate := PanelContainer.new()
		plate.name = "Score%d" % i
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.anchor_left = 0.5
		plate.anchor_right = 0.5
		plate.offset_left = -GAP - PLATE_W if i == 0 else GAP
		plate.offset_right = -GAP if i == 0 else GAP + PLATE_W
		plate.offset_top = TOP
		plate.offset_bottom = TOP + PLATE_H
		plate.pivot_offset = Vector2(PLATE_W, PLATE_H) * 0.5
		var l := Label.new()
		l.text = "0"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(l)
		_root.add_child(plate)
		_plates.append(plate)
		labels.append(l)
	caption = Label.new()
	caption.name = "Caption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.anchor_left = 0.5
	caption.anchor_right = 0.5
	caption.offset_left = -300.0
	caption.offset_right = 300.0
	caption.offset_top = TOP + PLATE_H + 6.0
	caption.offset_bottom = TOP + PLATE_H + 40.0
	_root.add_child(caption)
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())
	_refresh_caption()


func bind(m: SportMatch, h: Hud) -> void:
	match_node = m
	hud = h
	if m != null:
		m.score_changed.connect(_on_score)
		m.goal_scored.connect(_on_goal)
		m.sport_changed.connect(func(_id: String) -> void: _refresh_caption())
		m.phase_changed.connect(_on_phase)
		_on_score(m.score)
	if h != null:
		h.results.visibility_changed.connect(_on_results_visibility)
	_refresh_caption()


func _colour(i: int) -> Color:
	return (Tuning.PLAYER_COLORS[i] as Color).lightened(0.35)


func _apply_skin() -> void:
	for i in labels.size():
		var c := _colour(i)
		HudSkin.style_label(labels[i], "display", SCORE_PX, Color.WHITE, c)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.05, 0.86)
		sb.border_color = c
		sb.border_width_bottom = 6
		sb.set_corner_radius_all(4)
		(_plates[i] as PanelContainer).add_theme_stylebox_override("panel", sb)
	if caption != null:
		HudSkin.style_label(caption, "display", CAPTION_PX, Color(1, 1, 1, 0.8))
		caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		caption.add_theme_constant_override("outline_size", 5)


func _refresh_caption() -> void:
	if caption == null:
		return
	var id := match_node.sport if match_node != null else "football"
	var n := match_node.goals_to_win if match_node != null else Tuning.SPORT_GOALS_TO_WIN
	caption.text = "%s · %s" % [tr(String(Tuning.SPORTS[id]["title"])), tr("ДО %d") % n]


func _on_score(score: Array) -> void:
	for i in mini(labels.size(), score.size()):
		(labels[i] as Label).text = str(int(score[i]))


func _on_goal(team: int, _scorer: Doll, _own: bool) -> void:
	if team < 0 or team >= _plates.size():
		return
	var p := _plates[team] as Control
	var tw := p.create_tween().set_ignore_time_scale(true)
	tw.tween_property(p, "scale", Vector2(1.45, 1.45), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_phase(p: int) -> void:
	if hud != null and p == Match.Phase.SUDDEN_DEATH:
		hud.sudden_death_label.text = tr("GOLDEN GOAL")
	caption.visible = p != Match.Phase.SUDDEN_DEATH


## Итоги открыты — счёт уезжает в строку победителя («P1 WINS! 3 : 1»), плашки прячутся вместе с боевым HUD.
func _on_results_visibility() -> void:
	if hud == null or hud.results.warming:
		return
	_root.visible = not hud.results.visible
	if hud.results.visible and match_node != null:
		var s := "%d : %d" % [int(match_node.score[0]), int(match_node.score[1])]
		var wt := hud.results.wins_text
		wt.text = s if wt.text == "" else "%s  %s" % [wt.text, s]
