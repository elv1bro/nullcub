## Площадка спорт-зала (docs/plan-demo/SPORT.md; автор 04.10: «режим ФУТБОЛ… до 3 голов» и другие виды спорта, если легко):
## зал SportHall + две куклы (P1 — клён, P2 — орех) + мяч SportBall + SportMatch (счёт, розыгрыши) + боевой HUD + счёт SportHud.
## Дерево собирает tools/build_sport_hall.gd (scenes/playground_sport.tscn; _basketball / _volleyball — та же сцена с другим sport).
## От площадки боя (scenes/playground.gd) — R, Esc, 1–9, M / N, H, F10. Своё:
##   F — следующий вид спорта (футбол → баскетбол → волейбол), матч заново;
##   U — за P2 играет бот (SportBrain) или человек на стрелках; по умолчанию бот (C занята режимом «Прочность суставов»). Человек может просто нажать свою клавишу
##       (стрелки / правый Ctrl / Enter) — бот отдаст управление сам.
## Камера держит в кадре обе куклы и мяч (группа sport_cam); масштаб игрока (DynamicCamera.user_zoom, общий на все арены, по
## умолчанию 1.5× ближе) здесь на время сцены сброшен в 1 — иначе при разлёте по залу мяч или соперник уходили бы за кадр.
## «Запас из деталей» (PartHp, «;») в зале по умолчанию включён (Tuning.SPORT_PARTHP, автор 06.10) — ставится в _enter_tree, раньше
## _ready кукол (запасы суставов считаются по режиму); на выходе из зала оба режима отрыва возвращаются как были.
extends "res://scenes/playground.gd"

const CAM_GROUP := "sport_cam"
const BOT_NAME := "SportBrain"

@export var sport := "football"
@export var p2_bot := true
@export var bot_level := 2

var ball: SportBall
var sport_hud: SportHud
var _zoom_before := 1.0
var _break_modes_before: Array = []   # [PartHp.on, JointBreak.on] до входа в зал


func _enter_tree() -> void:
	_break_modes_before = [PartHp.on, JointBreak.on]
	if Tuning.SPORT_PARTHP:
		PartHp.set_on(true)
		JointBreak.set_on(false)   # один механизм отрыва — два режима сразу не ведём (HitJuice)


func _ready() -> void:
	_zoom_before = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = 1.0
	ball = get_node_or_null("Ball") as SportBall
	sport_hud = get_node_or_null("SportHud") as SportHud
	var sm := $Match as SportMatch
	sm.sport = sport
	super._ready()
	if sport_hud != null:
		sport_hud.bind(sm, hud)
	sm.doll_replaced.connect(func(_o: Doll, _n: Doll) -> void: _refresh_hint())
	set_p2_bot(p2_bot)
	_refresh_hint()


func _exit_tree() -> void:
	DynamicCamera.user_zoom = _zoom_before
	if _break_modes_before.size() == 2:
		PartHp.set_on(bool(_break_modes_before[0]))
		JointBreak.set_on(bool(_break_modes_before[1]))


func sport_match() -> SportMatch:
	return match_node as SportMatch


func _p2() -> Doll:
	for d in dolls():
		if (d as Doll).player_index == 1:
			return d
	return null


## За P2 — бот (SportBrain ребёнком куклы) или человек. Match.respawn_doll переносит и external_input, и узел мозга.
func set_p2_bot(on: bool) -> void:
	p2_bot = on
	var d := _p2()
	if d == null:
		return
	var brain := d.get_node_or_null(BOT_NAME)
	if on and brain == null:
		var b := SportBrain.new()
		b.name = BOT_NAME
		b.level = bot_level
		d.add_child(b)
	elif not on and brain != null:
		d.remove_child(brain)
		brain.queue_free()
	d.external_input = on
	if not on:
		d.input_vec = Vector2.ZERO
	hud.set_player_name(1, tr("БОТ") if on else "")   # "" — снова «ИГРОК 2»
	_refresh_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F:
				var id := sport_match().next_sport()
				_show_fx_toast(tr(String(Tuning.SPORTS[id]["title"])))
				_refresh_hint()
				return
			KEY_U:
				set_p2_bot(not p2_bot)
				_show_fx_toast(tr("P2: бот") if p2_bot else tr("P2: человек"))
				return
	if p2_bot and event is InputEventKey and event.pressed and not event.echo:
		for a in ["p2_left", "p2_right", "p2_up", "p2_down", "p2_dash", "p2_flip"]:
			if InputMap.has_action(a) and event.is_action(a):
				set_p2_bot(false)
				_show_fx_toast(tr("P2: человек"))
				break
	super._unhandled_input(event)


func _refresh_hint() -> void:
	var hint := get_node_or_null("UI/Hint") as Label
	if hint == null:
		return
	var who := tr("P2: бот (U — играть самому на стрелках)") if p2_bot else tr("P2: стрелки + правый Ctrl + Enter (U — бот)")
	hint.text = "%s    %s    %s" % [tr("P1: WASD + Shift + Space — влетай в мяч телом"), who, tr("F: вид спорта    R: заново    L: все клавиши    Esc: пауза")]
