## Панель голосования зрителей (docs/plan-demo/15-audience-vote.md): «AUDIENCE EVENT», три строки — вариант, полоса, проценты,
## итог «… WINS» (при аномалии §14 — зачёркнутый итог и то, что включило поле) и субтитр N0 (заглушка до этапа 14).
## Узел — scenes/arena/audience_vote_panel.tscn (CanvasLayer), им управляет AudienceVote (show_vote / set_percents / show_result).
## Вид — по скину HUD (scripts/ui/hud_skin.gd: трансляция / неон / LED); стили ставятся поверх сцены в _apply_skin
## (в _ready и при смене скина).
extends CanvasLayer

const COL_WIN := Color(1.0, 0.75, 0.25)
const COL_ROW := Color(0.92, 0.94, 1.0)
const COL_BAD := Color(1.0, 0.35, 0.3)

var _hide_t: SceneTreeTimer = null

@onready var box: Control = $Box
@onready var title: Label = %Title
@onready var result: Label = %Result
@onready var n0: Label = %N0Line
@onready var rows: Array = [%Row0, %Row1, %Row2]


func _ready() -> void:
	box.visible = false
	n0.visible = false
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())


func _apply_skin() -> void:
	box.add_theme_stylebox_override("panel", HudSkin.panel("vote_box"))
	title.add_theme_stylebox_override("normal", HudSkin.panel("vote_title"))
	HudSkin.style_label(title, "display", 30, HudSkin.text_for("gold"))
	var track := StyleBoxFlat.new()
	track.bg_color = Broadcast.PLATE_LIGHT if HudSkin.id() == "broadcast" else Color(HudSkin.accent(), 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HudSkin.accent()
	for r in rows:
		var row := r as Control
		(row.get_node("Name") as Label).add_theme_font_override("font", HudSkin.font("plate"))
		(row.get_node("Pct") as Label).add_theme_font_override("font", HudSkin.font("digits"))
		(row.get_node("Bar") as ProgressBar).add_theme_stylebox_override("background", track)
		(row.get_node("Bar") as ProgressBar).add_theme_stylebox_override("fill", fill)
	result.add_theme_font_override("font", HudSkin.font("display"))


func show_vote(options: Array, n0_line: String = "") -> void:
	_hide_t = null
	box.visible = true
	title.text = tr("AUDIENCE EVENT")
	result.visible = false
	for i in rows.size():
		var row: Control = rows[i]
		row.visible = i < options.size()
		if i < options.size():
			(row.get_node("Name") as Label).text = String((options[i] as Dictionary)["title"])
			(row.get_node("Name") as Label).add_theme_color_override("font_color", COL_ROW)
			(row.get_node("Bar") as ProgressBar).value = 0.0
			(row.get_node("Pct") as Label).text = "0%"
	_say(n0_line)


func set_percents(pct: Array) -> void:
	var best := 0
	for i in pct.size():
		if int(pct[i]) > int(pct[best]):
			best = i
	for i in mini(pct.size(), rows.size()):
		var row: Control = rows[i]
		(row.get_node("Bar") as ProgressBar).value = float(pct[i])
		(row.get_node("Pct") as Label).text = "%d%%" % int(pct[i])
		(row.get_node("Name") as Label).add_theme_color_override("font_color", COL_WIN if i == best else COL_ROW)


## Итог: winner WINS; applied ≠ "" — аномалия: поле включило другое.
func show_result(winner: String, applied: String = "", n0_line: String = "") -> void:
	result.visible = true
	if applied == "":
		result.text = tr("%s WINS") % winner
		result.add_theme_color_override("font_color", COL_WIN)
	else:
		result.text = tr("%s WINS  →  %s") % [winner, applied]
		result.add_theme_color_override("font_color", COL_BAD)
	if n0_line != "":
		_say(n0_line)
	var t := get_tree().create_timer(Tuning.VOTE_RESULT_SHOW_S + (1.5 if applied != "" else 0.0), true, false, true)
	_hide_t = t
	t.timeout.connect(func() -> void:
		if _hide_t == t:
			hide_now())


func hide_now() -> void:
	_hide_t = null
	box.visible = false
	n0.visible = false


func _say(line: String) -> void:
	n0.visible = line != ""
	n0.text = line
