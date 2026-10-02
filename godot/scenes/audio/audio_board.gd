## Звуковая доска (docs/plan-demo/AUDIO.md §6): послушать любой слой и любое событие боя без боя — для настройки микса на слух.
##   godot --path godot res://scenes/audio/audio_board.tscn
## Слева — события (как в бою: удар деревом / металлом / сковородой / мечом, крит с крупным планом, KO, удар о стену, взрыв,
## отсчёт и FIGHT!, комбо, конец матча), справа — все слои SfxDirector по одному. Внизу: толпа (уровень возбуждения ползунком,
## реакции), фон арен (Свалка / Руины / Мастерская / Void — петли, разовые звуки и реверберация), музыка (вкл/выкл, следующий
## трек). Пробел — повторить последнее, Esc — выход. Крит и KO звучат так же, как в бою (SfxDirector, шины GameAudio).
extends Control

var sfx: SfxDirector
var crowd: CrowdDirector
var amb: ArenaAmbience
var ga: Node
var _last: Callable
var _level: HSlider
var _status: Label


func _ready() -> void:
	ga = get_node_or_null("/root/GameAudio")
	sfx = (load("res://scenes/audio/sfx_director.tscn") as PackedScene).instantiate() as SfxDirector
	sfx.doll_audio = false
	add_child(sfx)
	crowd = CrowdDirector.new()
	crowd.hold = true                   # уровень держит ползунок, не стекает к базе фазы
	add_child(crowd)
	amb = ArenaAmbience.new()
	amb.music = false
	add_child(amb)
	_build_ui()
	await get_tree().process_frame
	amb.start_preset("scrap")
	_set_status(tr("Свалка: фон, реверберация «купол»"))


func _ctx(tier: String, damage: float, weapon := "", part := "Torso") -> Dictionary:
	return {"victim": null, "attacker": null, "damage": damage, "kind": "body", "part": part, "part_base": part,
		"position": Vector3.ZERO, "tier": tier, "score": damage, "weapon_id": weapon, "combo": 1}


func _events() -> Array:
	return [
		[tr("Лёгкий: дерево по дереву"), _ev_light], [tr("Лёгкий: по голове"), _ev_light_head], [tr("Тяжёлый: дерево"), _ev_heavy],
		[tr("Тяжёлый: голова"), _ev_heavy_head], [tr("Тяжёлый: молот"), _ev_heavy_hammer], [tr("Тяжёлый: сковорода"), _ev_heavy_pan],
		[tr("Тяжёлый: меч"), _ev_heavy_sword], [tr("Крит (крупный план)"), _ev_crit], [tr("Крит без крупного плана"), _ev_crit_short],
		["KO", _ev_ko], [tr("Удар о стену"), _ev_slam], [tr("Удар о стену в крит-полёте"), _ev_slam_crit], [tr("Взрыв бочки"), _ev_explosion],
		[tr("Отсчёт 3-2-1 + FIGHT!"), _countdown], [tr("Комбо 2 → 6"), _combo], [tr("Конец матча"), _ev_over],
	]


func _ev_light() -> void:
	sfx.handle_hit_fx(_ctx("light", 6.0))


func _ev_light_head() -> void:
	sfx.handle_hit_fx(_ctx("light", 7.0, "", "Head"))


func _ev_heavy() -> void:
	sfx.handle_hit_fx(_ctx("heavy", 18.0))


func _ev_heavy_head() -> void:
	sfx.handle_hit_fx(_ctx("heavy", 22.0, "", "Head"))


func _ev_heavy_hammer() -> void:
	sfx.handle_hit_fx(_ctx("heavy", 22.0, "hammer"))


func _ev_heavy_pan() -> void:
	sfx.handle_hit_fx(_ctx("heavy", 22.0, "pan"))


func _ev_heavy_sword() -> void:
	sfx.handle_hit_fx(_ctx("heavy", 20.0, "sword"))


func _ev_crit() -> void:
	sfx.force_crit_mode = "cine"
	sfx.handle_hit_fx(_ctx("crit", 26.0))
	sfx.force_crit_mode = ""


func _ev_crit_short() -> void:
	sfx.force_crit_mode = "short"
	sfx.handle_hit_fx(_ctx("crit", 26.0))
	sfx.force_crit_mode = ""


func _ev_ko() -> void:
	sfx.handle_ko(null, null, {"position": Vector3.ZERO})
	crowd._on_ko(null, null, {})


func _ev_slam() -> void:
	sfx.handle_env_slam({"speed": 9.0, "position": Vector3.ZERO, "part": "Torso"})


func _ev_slam_crit() -> void:
	sfx.handle_env_slam({"speed": 12.0, "position": Vector3.ZERO, "crit_flight": true})


func _ev_explosion() -> void:
	sfx.play_layer("explosion", 2.0, 1.0)
	sfx.play_layer("boom", -4.0, 0.8)
	sfx.play_layer("crash", -3.0, 0.85)
	crowd.react("crowd_ooh", 0.0, "explosion", true, 250.0)


func _ev_over() -> void:
	sfx.handle_match_over(self, {})
	crowd._on_match_over(null, {})


func _countdown() -> void:
	for n in [3, 2, 1]:
		sfx.handle_announce(str(n), Color.WHITE, "countdown")
		await get_tree().create_timer(0.7).timeout
	sfx.handle_announce("FIGHT!", Color.WHITE, "fight")
	crowd._on_announce("FIGHT!", Color.WHITE, "fight")


func _combo() -> void:
	for n in range(2, 7):
		sfx.handle_announce("%d HIT COMBO!" % n, Color.WHITE, "combo")
		await get_tree().create_timer(0.35).timeout


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -16
	root.offset_bottom = -12
	add_child(root)
	var title := Label.new()
	title.text = tr("Звуковая доска — NULL GRAVITY (пробел — повторить, Esc — выход)")
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	_status = Label.new()
	root.add_child(_status)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	# события
	var ev := _column(cols, tr("События боя"), 1.0)
	for e in _events():
		_button(ev, String(e[0]), e[1])
	# слои
	var lay_box := _column(cols, tr("Слои SfxDirector"), 2.0)
	var grid := GridContainer.new()
	grid.columns = 4
	lay_box.add_child(grid)
	for layer in SfxDirector.LAYER_ORDER:
		var l := String(layer)
		_button(grid, l, func() -> void: sfx.play_layer(l, 0.0, 1.0))
	# толпа, фон, музыка
	var side := _column(cols, tr("Толпа, фон, музыка"), 1.2)
	var lv := Label.new()
	lv.text = tr("Возбуждение толпы (гул → оживление → рёв)")
	side.add_child(lv)
	_level = HSlider.new()
	_level.min_value = 0.0
	_level.max_value = 1.0
	_level.step = 0.01
	_level.value = 0.2
	_level.value_changed.connect(func(v: float) -> void:
		crowd.excitement = v
		_set_status(tr("толпа: возбуждение %.2f") % v))
	side.add_child(_level)
	for r in CrowdDirector.SHOTS:
		var rl := String(r)
		_button(side, tr("Толпа: ") + rl.trim_prefix("crowd_"), func() -> void: crowd.react(rl, 0.0, "board", true, 0.0))
	for a in ["scrap", "ruins", "workshop", "void"]:
		var an := String(a)
		_button(side, tr("Фон: ") + an, func() -> void:
			amb.start_preset(an)
			_set_status(tr("фон %s, реверберация %s") % [an, ga.room if ga != null else "?"]))
	_button(side, tr("Музыка: вкл/выкл"), func() -> void:
		if ga != null:
			if ga.music_context == "":
				ga.play_context("fight")
				ga.set_music_on(true, false)
			else:
				ga.play_context("")
			_set_status(tr("музыка: %s %s") % [ga.music_context, ga.music_track]))
	_button(side, tr("Музыка: следующий трек"), func() -> void:
		if ga != null:
			ga.play_context("fight")
			ga.call("_start_track", "fight")
			_set_status(tr("музыка: %s") % ga.music_track))
	_button(side, tr("Глушение крита вкл/выкл"), func() -> void:
		sfx.set_muffle(not sfx.is_muffled())
		_set_status(tr("глушение: %s") % sfx.is_muffled()))


func _column(parent: Node, title: String, ratio: float) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = ratio
	parent.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 18)
	box.add_child(l)
	return box


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		_last = cb
		cb.call()
		_set_status(text))
	parent.add_child(b)


func _set_status(t: String) -> void:
	if _status != null:
		_status.text = t


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_SPACE:
				if _last.is_valid():
					_last.call()
			KEY_ESCAPE:
				get_tree().quit()
