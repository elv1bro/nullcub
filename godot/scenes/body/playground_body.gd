## Площадка сборки тела (BODY_CRAFT.md, CONCEPT_V2 «Порядок»: пресеты тела без UI против обычной куклы): арена «Мастерская»,
## P1 — ModularDoll (scenes/body/modular_doll.tscn), P2 — обычная кукла (орех). Дерево — scenes/playground_body.tscn.
##   Пресет тела P1 (PRESETS: human … flail, дальше пресеты кита тела v2 — docs/plan-demo/BODY_KIT.md §3.5, их пишет
##   tools/build_body_kit.gd): F1–F9, F11, F12 — сразу пресет 1–9, 11, 12 (F13 — 13-й, только на полной клавиатуре; на macOS
##   F-клавиши — с fn). F10 не занят: это пресет эффектов удара из scenes/playground.gd (cycle_fx_preset) — 10-й пресет тела только
##   листанием: ] / PageDown — следующий пресет, [ / PageUp — предыдущий (по кругу, все пресеты, в том числе дальше F12).
##   Кукла пересоздаётся Match.respawn_doll с другим scene_file_path (scenes/body/presets/<id>.tscn), поэтому пресет переживает
##   R и KO. Пресеты, сцены которых ещё нет на диске, пропускаются.
##   Остальное — как scenes/playground.gd: R заново, 1 / 2 / 3 — обычные площадки (Руины / Мастерская / Void), Esc — пауза (Flow).
## Подсказка снизу: пресет (номер / всего), энергия / бюджет, масса, число тел, разгон тяги относительно куклы v3
## (фиксированная тяга Ядра), клавиши выбора пресета.
extends "res://scenes/playground.gd"

const PRESETS := [
	["human", "res://scenes/body/modular_doll.tscn"],
	["spider", "res://scenes/body/presets/spider.tscn"],
	["long_arm", "res://scenes/body/presets/long_arm.tscn"],
	["big_arm", "res://scenes/body/presets/big_arm.tscn"],
	["legless", "res://scenes/body/presets/legless.tscn"],
	["junk", "res://scenes/body/presets/junk.tscn"],
	["flail", "res://scenes/body/presets/flail.tscn"],
	["kit_human", "res://scenes/body/presets/kit_human.tscn"],
	["kit_brawler", "res://scenes/body/presets/kit_brawler.tscn"],
	["kit_bot", "res://scenes/body/presets/kit_bot.tscn"],
	["kit_horned", "res://scenes/body/presets/kit_horned.tscn"],
	["kit_king", "res://scenes/body/presets/kit_king.tscn"],
	["kit_spider", "res://scenes/body/presets/kit_spider.tscn"],
	["kit_devil", "res://scenes/body/presets/kit_devil.tscn"],
	["kit_skull", "res://scenes/body/presets/kit_skull.tscn"],
	["kit_wheels", "res://scenes/body/presets/kit_wheels.tscn"],
	["kit_lantern", "res://scenes/body/presets/kit_lantern.tscn"],
	# витрина покраски (docs/plan-demo/BODY_PAINT.md §4): узлы kit_human / kit_brawler + краска и трафареты
	["kit_graffiti", "res://scenes/body/presets/kit_graffiti.tscn"],
	["kit_camo", "res://scenes/body/presets/kit_camo.tscn"],
	["kit_spinner", "res://scenes/body/presets/kit_spinner.tscn"],
	["kit_empty", "res://scenes/body/presets/kit_empty.tscn"],
	# наборы 04.10 (docs/plan-demo/KIT_SETS.md): про-лига Земли и живые бойцы Аоэлюн — листанием ] / [
	["pro_sprinter", "res://scenes/body/presets/pro_sprinter.tscn"],
	["pro_titan", "res://scenes/body/presets/pro_titan.tscn"],
	["aoe_predator", "res://scenes/body/presets/aoe_predator.tscn"],
	["aoe_ram", "res://scenes/body/presets/aoe_ram.tscn"],
	["pro_centipede", "res://scenes/body/presets/pro_centipede.tscn"],
	["pro_multitool", "res://scenes/body/presets/pro_multitool.tscn"],
	["aoe_leviathan", "res://scenes/body/presets/aoe_leviathan.tscn"],
	["set_chimera", "res://scenes/body/presets/set_chimera.tscn"],
]
## Прямой выбор: клавиша → индекс PRESETS (номер F-клавиши = номер пресета). F10 пропущен — его ловит base (playground.gd:
## cycle_fx_preset, пресет эффектов удара); 10-й пресет и всё дальше F13 — только листанием.
const PRESET_KEYS := {KEY_F1: 0, KEY_F2: 1, KEY_F3: 2, KEY_F4: 3, KEY_F5: 4, KEY_F6: 5, KEY_F7: 6, KEY_F8: 7, KEY_F9: 8, KEY_F11: 10,
	KEY_F12: 11, KEY_F13: 12}
## Листание пресетов по кругу: +1 / −1.
const CYCLE_KEYS := {KEY_BRACKETRIGHT: 1, KEY_PAGEDOWN: 1, KEY_BRACKETLEFT: -1, KEY_PAGEUP: -1}
const PRESET_HELP := "F1–F9, F11, F12, [ / ], PgUp / PgDn"
const CONTROLS := "P1: WASD + Shift + Space    P2: стрелки + правый Ctrl + Enter    R: заново    1 / 2 / 3: другие площадки    Esc: пауза"

var preset_index := 0

@onready var hint: Label = $UI/Hint


func _ready() -> void:
	super._ready()
	match_node.doll_replaced.connect(func(_o: Doll, _n: Doll) -> void: _update_hint())
	_update_hint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if PRESET_KEYS.has(key):
			set_preset(int(PRESET_KEYS[key]))
			get_viewport().set_input_as_handled()
			return
		if CYCLE_KEYS.has(key):
			cycle_preset(int(CYCLE_KEYS[key]))
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


## Следующий (step = 1) / предыдущий (step = −1) пресет по кругу; пресеты без сцены на диске пропускаются.
func cycle_preset(step: int) -> Doll:
	var n := PRESETS.size()
	var i := preset_index
	for _k in range(n):
		i = posmod(i + step, n)
		if ResourceLoader.exists(PRESETS[i][1]):
			return set_preset(i)
	return null


func p1_doll() -> Doll:
	for d in dolls():
		if (d as Doll).player_index == 0:
			return d
	return null


func _update_hint() -> void:
	if hint == null:
		return
	var line := tr("P1: обычная кукла")
	var p1 := p1_doll()
	if p1 is ModularDoll:
		var md := p1 as ModularDoll
		var bp := md.blueprint
		var accel := md.thrust_mass() / maxf(md.total_mass, 0.001) if md.fixed_thrust else 1.0
		line = tr("P1: %s — энергия %d / %d, масса %.1f кг, тел %d, разгон ×%.2f") % [bp.title, bp.energy_used(), bp.energy_cap(),
			md.total_mass, md.parts.size(), accel]
	hint.text = tr("%s    [пресет %d / %d %s — %s]\n%s") % [line, preset_index + 1, PRESETS.size(), PRESETS[preset_index][0], PRESET_HELP,
		tr(CONTROLS)]
