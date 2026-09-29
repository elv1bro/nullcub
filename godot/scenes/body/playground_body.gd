## Площадка сборки тела (BODY_CRAFT.md, CONCEPT_V2 «Порядок»: пресеты тела без UI против обычной куклы): арена «Мастерская»,
## P1 — ModularDoll (scenes/body/modular_doll.tscn), P2 — обычная кукла (орех). Дерево — scenes/playground_body.tscn.
##   F1–F6 — пресет тела P1 (F7 — кистень, если его пресет собран): кукла пересоздаётся Match.respawn_doll с другим scene_file_path
##   (scenes/body/presets/<id>.tscn), поэтому пресет переживает R и KO. На macOS F-клавиши — с fn.
##   Остальное — как scenes/playground.gd: R заново, 1 / 2 / 3 — обычные площадки (Руины / Мастерская / Void), Esc — выход.
## Подсказка снизу: пресет, энергия / бюджет, масса, число тел, разгон тяги относительно куклы v3 (фиксированная тяга Ядра).
extends "res://scenes/playground.gd"

const PRESETS := [
	["human", "res://scenes/body/modular_doll.tscn"],
	["spider", "res://scenes/body/presets/spider.tscn"],
	["long_arm", "res://scenes/body/presets/long_arm.tscn"],
	["big_arm", "res://scenes/body/presets/big_arm.tscn"],
	["legless", "res://scenes/body/presets/legless.tscn"],
	["junk", "res://scenes/body/presets/junk.tscn"],
	["flail", "res://scenes/body/presets/flail.tscn"],
]
const PRESET_KEYS := [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7]
const CONTROLS := "P1: WASD + Shift + Space    P2: стрелки + правый Ctrl + Enter    R: заново    1 / 2 / 3: другие площадки    Esc: выход"

var preset_index := 0

@onready var hint: Label = $UI/Hint


func _ready() -> void:
	super._ready()
	match_node.doll_replaced.connect(func(_o: Doll, _n: Doll) -> void: _update_hint())
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var i := PRESET_KEYS.find((event as InputEventKey).physical_keycode)
		if i >= 0:
			set_preset(i)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


## Сменить пресет P1: i — индекс PRESETS. Возвращает новую куклу (или null, если пресета нет).
func set_preset(i: int) -> Doll:
	if i < 0 or i >= PRESETS.size() or not ResourceLoader.exists(PRESETS[i][1]):
		return null
	var p1 := p1_doll()
	if p1 == null:
		return null
	preset_index = i
	p1.scene_file_path = PRESETS[i][1]   # Match.respawn_doll инстанцирует сцену по этому пути
	var d := match_node.respawn_doll(p1)
	_update_hint()
	return d


func p1_doll() -> Doll:
	for d in dolls():
		if (d as Doll).player_index == 0:
			return d
	return null


func _update_hint() -> void:
	if hint == null:
		return
	var keys: PackedStringArray = []
	for i in range(PRESETS.size()):
		if ResourceLoader.exists(PRESETS[i][1]):
			keys.append("F%d %s" % [i + 1, PRESETS[i][0]])
	var line := "P1: обычная кукла"
	var p1 := p1_doll()
	if p1 is ModularDoll:
		var md := p1 as ModularDoll
		var bp := md.blueprint
		var accel := md.thrust_mass() / maxf(md.total_mass, 0.001) if md.fixed_thrust else 1.0
		line = "P1: %s — энергия %d / %d, масса %.1f кг, тел %d, разгон ×%.2f" % [bp.title, bp.energy_used(), bp.energy_budget,
			md.total_mass, md.parts.size(), accel]
	hint.text = "%s    [%s]\n%s" % [line, "  ".join(keys), CONTROLS]
