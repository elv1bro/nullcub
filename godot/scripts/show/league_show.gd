## Оформление «прямого эфира Лиги» (docs/plan-demo/look/show.md; LOOK_PASS.md п. 6, ветка look-show). Узел-ребёнок лоадера Loading
## (своей автозагрузки нет — список автозагрузок общий у пяти веток прохода по картинке). Регистрирует пункты панели «ВИД» в группе
## «Эфир» и сам находит, куда что поставить, по мере появления узлов в дереве (сцены не правятся):
##   show_stinger      — заставка-стингер Лиги между сценами (LeagueStinger, по сигналам Loading opened / closing);
##   show_plates       — плашки бойцов в начале боя (LowerThirds рядом с матчем 1 на 1);
##   show_crowd_dim    — толпа купола приглушена;               ┐
##   show_crowd_fx     — вспышки камер, волна, покачивание;      │ HallShow в арене купола (NullHallArena)
##   show_spots        — прожекторы ферм ведут бойцов;           │
##   show_final_light  — последние 10 с: свет купола гаснет;     ┘
##   show_hud          — единый HUD: два шрифта эфира во всех HUD (ShowTokens.unified → HudSkin) и плашки HUD режимов в грамматике
##                       скина (HudUnify в SquadHud / SportHud / BombHud / RaceHud).
## Каждый пункт по умолчанию включён; выключение возвращает ровно прежний вид сразу в обработчике Look.changed.
class_name LeagueShow
extends Node

const GROUP := "Эфир"
const ITEMS := [
	[&"show_stinger", "Заставка Лиги между сценами"],
	[&"show_plates", "Плашки бойцов в начале боя"],
	[&"show_crowd_dim", "Толпа приглушена"],
	[&"show_crowd_fx", "Толпа: вспышки камер, волна, покачивание"],
	[&"show_spots", "Прожекторы ведут бойцов"],
	[&"show_final_light", "Последние 10 с: свет купола гаснет"],
	[&"show_hud", "Единый HUD (шрифты и плашки режимов)"],
]
const HALL_SCRIPT := "res://scenes/arena/null_hall.gd"
const MODE_HUDS := ["res://scenes/squad/squad_hud.gd", "res://scenes/sport/sport_hud.gd", "res://scenes/bomb/bomb_hud.gd",
	"res://scenes/race/race_hud.gd"]

var stinger: LeagueStinger
var _look: Node
var _loading: Node


func _init() -> void:
	name = "LeagueShow"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_loading = get_parent()
	stinger = LeagueStinger.new()
	add_child(stinger)
	if _loading != null and _loading.has_signal("opened"):
		_loading.connect("opened", func() -> void: stinger.play("reveal"))
		_loading.connect("closing", func() -> void: stinger.play("full"))
	get_tree().node_added.connect(_on_node_added)
	_setup.call_deferred()   # автозагрузка Look стоит после Loading — пункты регистрируются, когда она уже в дереве


func _setup() -> void:
	_look = get_node_or_null("/root/Look")
	if _look == null:
		_set_unified(true)
		return
	# подписи — ключи перевода; tr() здесь, в месте использования (I18N.md, правило 2)
	for it in ITEMS:
		_look.call("add", it[0], tr(String(it[1])), tr(GROUP))
	_look.connect("changed", _on_look)
	_set_unified(bool(_look.call("on", &"show_hud")))


func _on_look(id: StringName, on: bool) -> void:
	if id == &"show_hud":
		_set_unified(on)


func _set_unified(on: bool) -> void:
	if ShowTokens.unified == on:
		return
	ShowTokens.unified = on
	HudSkin.events.changed.emit(HudSkin.id())   # все HUD перестраивают шрифты и темы на лету (как при смене скина клавишей H)


func _on_node_added(n: Node) -> void:
	var s := n.get_script() as Script
	if s == null:
		return
	var path := s.resource_path
	if path == HALL_SCRIPT:
		_attach_hall.call_deferred(n)
	elif MODE_HUDS.has(path):
		_attach_hud.call_deferred(n)
	elif n.has_signal("phase_changed") and n.has_method("time_left_s") and n.has_method("dolls"):
		_attach_match.call_deferred(n)


## Помощники грузятся лениво (load в месте использования): лоадер — автозагрузка, и тянуть при старте игры скрипты матча, куклы и HUD
## режимов ради проверки типа незачем.
func _attach_hall(n: Node) -> void:
	if is_instance_valid(n) and n.is_inside_tree():
		load("res://scripts/show/hall_show.gd").call("attach", n)


func _attach_hud(n: Node) -> void:
	if is_instance_valid(n) and n.is_inside_tree() and n is CanvasLayer:
		load("res://scripts/show/hud_unify.gd").call("attach", n)


func _attach_match(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree() or n.get_parent() == null:
		return
	var lt: Script = load("res://scripts/show/lower_thirds.gd")
	if bool(lt.call("wants", n)):
		lt.call("attach", n)
