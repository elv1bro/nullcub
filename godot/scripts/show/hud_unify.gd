## «Единый HUD» для HUD режимов (стычка SquadHud, спорт SportHud, бомба BombHud, гонка RaceHud) без переписывания их вёрстки
## (docs/plan-demo/look/show.md; пункт «ВИД» show_hud, группа «Эфир»). Ребёнок слоя HUD режима, ставит LeagueShow.
## Шрифты делает сам HudSkin (ShowTokens.unified → два шрифта эфира во всех HUD). Здесь — плашки: HUD режимов рисуют свои панели
## StyleBoxFlat (тёмный прямоугольник со скруглением и полосой цвета снизу), а HUD боя — плашками скина. Каждую панель-override
## (PanelContainer / Panel, стиль «panel») узел перекрашивает НА МЕСТЕ в грамматику текущего скина (ShowTokens.restyle_flat: трансляция —
## косая тёмно-синяя плашка с полосой цвета, неон — стекло со свечением, LED — табло), цвет полосы — из палитры токенов. HUD режима
## создаёт новые стили (смена скина, лидер гонки, держатель бомбы) — узел подхватывает их в том же кадре (process_priority после HUD).
## Выключение — исходные свойства каждой плашки возвращаются сразу. Холст стычки (_draw: полосы, кольца, карточки) не трогается:
## там скругления — часть рисунка (полосы HP, деления), перекраска на месте сломала бы их; его текст и так берёт шрифт HudSkin.
class_name HudUnify
extends Node

const ID := &"show_hud"
const RESCAN_S := 0.5

var hud: CanvasLayer
var restyled := 0                    # сколько плашек перекрашено сейчас (пробы)
var _panels: Array[Control] = []
var _rescan := 0.0
var _look: Node


static func attach(layer: CanvasLayer) -> HudUnify:
	var u := layer.get_node_or_null("HudUnify") as HudUnify
	if u != null:
		return u
	u = HudUnify.new()
	u.name = "HudUnify"
	u.hud = layer
	layer.add_child(u)
	return u


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # снимки «до / после» на паузе: перекраска сразу
	process_priority = 100


func _ready() -> void:
	if hud == null:
		hud = get_parent() as CanvasLayer
	_look = get_node_or_null("/root/Look")
	if _look != null:
		_look.changed.connect(func(id: StringName, _on: bool) -> void:
			if id == ID:
				apply())
	HudSkin.events.changed.connect(func(_id: String) -> void: apply.call_deferred())
	apply.call_deferred()


func _exit_tree() -> void:
	_restore_all()


func on() -> bool:
	return ShowTokens.unified


func _collect() -> void:
	_panels.clear()
	if hud == null or not is_instance_valid(hud):
		return
	for c in hud.find_children("*", "Control", true, false):
		if (c is PanelContainer or c is Panel) and (c as Control).has_theme_stylebox_override("panel"):
			_panels.append(c)


## Перекрасить (или вернуть) все плашки HUD режима по состоянию пункта.
func apply() -> void:
	if not is_inside_tree():
		return
	_collect()
	_rescan = RESCAN_S
	if on():
		_restyle_all()
	else:
		_restore_all()


func _restyle_all() -> void:
	var skin := HudSkin.id()
	var n := 0
	for c in _panels:
		if not is_instance_valid(c):
			continue
		var sb := c.get_theme_stylebox("panel") as StyleBoxFlat
		if sb == null:
			continue
		ShowTokens.restyle_flat(sb, skin)
		n += 1
	restyled = n


func _restore_all() -> void:
	for c in _panels:
		if is_instance_valid(c):
			ShowTokens.restore_flat(c.get_theme_stylebox("panel") as StyleBoxFlat)
	restyled = 0


func _process(delta: float) -> void:
	if not on():
		return
	_rescan -= delta
	if _rescan <= 0.0:
		_rescan = RESCAN_S
		_collect()
	_restyle_all()
