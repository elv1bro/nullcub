## Проба направления look-frame (docs/plan-demo/look/frame.md, headless): «правило кадра» и «дорогой пластик» включаются и снимаются
## РОВНО (рубильник Look в том же кадре, без ожидания — так снимает look_capture на паузе), переживают смену цвета команды и уход арены,
## не пишут user://look.cfg; RendererPin пишет и убирает переопределение рендерера (на пробном пути, настоящий user:// не трогается).
## В headless LookFrame молчит, пока проба не включит headless_enabled. Запуск: godot --headless --path . res://tests/look_frame_probe.tscn
## Exit 0/1.
extends Node

const DOME := "res://scenes/playground_null_hall.tscn"
const RUINS := "res://scenes/playground.tscn"
const ITEM_IDS := [&"frame_rim", &"frame_glow", &"frame_shadow", &"frame_backdrop", &"frame_lamps", &"plastic_coat", &"plastic_probe"]
const LAMP := "res://assets/materials/null_hall/Hall_LightWarm.tres"

var ok := true
var lf: Node
var look: Node


func _check(id: String, cond: bool, detail: String) -> void:
	if not cond:
		ok = false
	print("  %s %s: %s" % ["ok  " if cond else "FAIL", id, detail])


func _ready() -> void:
	print("=== LOOK FRAME PROBE ===")
	lf = get_node_or_null("/root/LookFrame")
	look = get_node_or_null("/root/Look")
	_check("autoload", lf != null and look != null, "LookFrame и Look в автозагрузке")
	if lf == null or look == null:
		_finish()
		return
	var cfg := ProjectSettings.globalize_path(look.SAVE_PATH)
	var cfg_before := FileAccess.get_file_as_string(cfg) if FileAccess.file_exists(cfg) else ""
	var master0: bool = look.master
	look.set_master(true)
	_check("headless_quiet", not lf.active() and not look.ids().has(&"frame_rim"), "в headless без пробы проход молчит, пунктов нет")
	lf.headless_enabled = true
	lf.refresh()
	var ids: Array = look.ids()
	var reg := ITEM_IDS.all(func(id: StringName) -> bool: return ids.has(id))
	_check("items", reg, "7 пунктов в панели «ВИД»")
	_check("groups", look.group_of(&"frame_rim") == tr("Кадр") and look.group_of(&"plastic_coat") == tr("Пластик"),
		"группы «%s» / «%s»" % [look.group_of(&"frame_rim"), look.group_of(&"plastic_coat")])

	var lamp := load(LAMP) as BaseMaterial3D
	var lamp_e0 := lamp.emission_energy_multiplier
	var inst := (load(DOME) as PackedScene).instantiate()
	add_child(inst)
	await _frames(70)
	var dolls0 := get_tree().get_nodes_in_group("dolls")
	_check("probe_bits", _bits(dolls0, FrameDress.PROBE_BIT) == _mesh_count(dolls0), "бит отражений у %d/%d мешей" % [_bits(dolls0, FrameDress.PROBE_BIT), _mesh_count(dolls0)])
	var arena: FrameArena = lf.arenas[0] if not lf.arenas.is_empty() else null
	_check("arena", arena != null and arena.scene == "null_hall.tscn", "профиль купола найден (%d арен)" % lf.arenas.size())
	if arena == null:
		_finish_scene(inst, master0, cfg, cfg_before)
		return
	var env := arena.we.environment
	var fog0: Dictionary = env.get_meta(FrameArena.META_ENV, {})
	_check("fog_depth", env.fog_mode == Environment.FOG_MODE_DEPTH and env.fog_depth_begin > 3.0 and env.fog_depth_end > env.fog_depth_begin,
		"туман глубины за плоскостью боя: %.1f…%.1f м" % [env.fog_depth_begin, env.fog_depth_end])
	_check("grade", env.adjustment_enabled and env.adjustment_saturation < 1.0, "цветокоррекция: насыщенность %.2f" % env.adjustment_saturation)
	_check("lamps", is_equal_approx(lamp.emission_energy_multiplier, lamp_e0 * 0.62), "лампы %.2f → %.2f" % [lamp_e0, lamp.emission_energy_multiplier])
	_check("probe", arena.probe != null and arena.probe.visible and arena.probe.size.x > 10.0 and arena.probe.reflection_mask == FrameDress.PROBE_BIT,
		"ReflectionProbe %s, отражения только на куклах" % (str(arena.probe.size) if arena.probe != null else "нет"))
	var dolls := get_tree().get_nodes_in_group("dolls")
	_check("dolls", dolls.size() == 2 and lf.dressed_count() == 2, "одето кукол: %d из %d" % [lf.dressed_count(), dolls.size()])
	_check("rim_on", lf.rim_visible() and _rim_bits(dolls) == _mesh_count(dolls), "контровой свет, бит слоя у %d/%d мешей" % [_rim_bits(dolls), _mesh_count(dolls)])
	_check("glow_on", _glowing(dolls) >= 4, "светится поверхностей Shirt*: %d" % _glowing(dolls))
	_check("shadow_on", lf.shadows.decal_count() == 8 and lf.shadows.visible_count() >= 4, "пятен %d, видно %d (пол и за спиной)" % [lf.shadows.decal_count(), lf.shadows.visible_count()])

	# рубильник — в том же кадре
	look.set_master(false)
	_check("off_fog", env.fog_mode == int(fog0.get("fog_mode", -1)) and is_equal_approx(env.fog_density, float(fog0.get("fog_density", -1.0)))
		and not env.has_meta(FrameArena.META_ENV), "туман как в сцене: режим %d, плотность %.3f" % [env.fog_mode, env.fog_density])
	_check("off_grade", env.adjustment_enabled == bool(fog0.get("adjustment_enabled", true)), "цветокоррекция как в сцене")
	_check("off_lamps", is_equal_approx(lamp.emission_energy_multiplier, lamp_e0), "лампы %.2f" % lamp.emission_energy_multiplier)
	_check("off_probe", arena.probe != null and not arena.probe.visible and _bits(dolls, FrameDress.PROBE_BIT) == 0, "отражения спрятаны, бит снят")
	_check("off_rim", not lf.rim_visible() and _rim_bits(dolls) == 0, "свет спрятан, бит слоя снят")
	_check("off_glow", _glowing(dolls) == 0 and _metas(dolls, FrameDress.META_GLOW) == 0, "свечения нет, meta сняты")
	_check("off_shadow", lf.shadows.visible_count() == 0, "пятна спрятаны")
	look.set_master(true)
	await _frames(3)
	_check("on_again", env.fog_mode == Environment.FOG_MODE_DEPTH and _glowing(dolls) >= 4 and lf.rim_visible() and arena.probe.visible,
		"снова вкл — всё вернулось")

	# новый меш в одетой кукле (класс стычки, оружие в руке) — одевается сам, без переодевания всей куклы
	var extra := MeshInstance3D.new()
	extra.name = "ProbeExtra"
	extra.mesh = BoxMesh.new()
	((dolls[1] as Doll).parts["Torso"] as Node).add_child(extra)
	await _frames(3)
	_check("new_mesh", extra.layers & FrameDress.RIM_BIT != 0 and extra.layers & FrameDress.PROBE_BIT != 0, "новый меш получил биты слоя")
	look.set_master(false)
	_check("new_mesh_off", extra.layers & (FrameDress.RIM_BIT | FrameDress.PROBE_BIT) == 0, "и снимает их выключение")
	look.set_master(true)
	extra.queue_free()
	await _frames(2)

	# смена цвета команды (SquadMatch зовёт _recolor с новым цветом): копия нашего материала несёт meta, свечение — новый цвет
	var d0 := dolls[0] as Doll
	d0._recolor(d0, Doll.SHIRT_MATERIAL, Color(0.1, 0.8, 0.3))
	await _wait_rescan()
	var em := _shirt_emission(d0)
	_check("recolor_glow", em.is_equal_approx(Color(0.1, 0.8, 0.3)), "свечение за цветом команды: %s" % str(em))
	look.set_master(false)
	_check("recolor_off", _glowing([d0]) == 0, "после перекраски выключение снимает и с новой копии")
	look.set_master(true)
	await _frames(2)

	# кукла кита: чемпион лиги (краска и пластик лиги — лак, ядро и суставы — свечение)
	var champ: Doll = inst.get_node("NullHall").call("call_champion")
	await _wait_rescan()
	var coat := _coated(champ)
	_check("coat_on", coat > 0, "лак на %d поверхностях кита" % coat)
	look.set_master(false)
	_check("coat_off", _coated(champ) == 0 and _swaps(champ) == 0, "лак снят, подмены вернулись (%d)" % _coated(champ))
	look.set_master(true)
	await _frames(2)
	look.set_on(&"plastic_coat", false)
	_check("item_coat_off", _coated(champ) == 0 and _glowing(dolls) >= 4, "галочка «лак» снимает только лак")
	look.set_on(&"plastic_coat", true)
	look.set_on(&"frame_shadow", false)
	_check("item_shadow_off", lf.shadows.visible_count() == 0 and lf.rim_visible(), "галочка «тень» — только пятна")
	look.set_on(&"frame_shadow", true)
	_finish_scene(inst, master0, cfg, cfg_before, lamp, lamp_e0, env, fog0)


func _finish_scene(inst: Node, master0: bool, cfg: String, cfg_before: String, lamp: BaseMaterial3D = null, lamp_e0 := 0.0,
		env: Environment = null, fog0: Dictionary = {}) -> void:
	inst.queue_free()
	await _frames(4)
	_check("arena_gone", lf.arenas.is_empty(), "арена ушла из учёта")
	if lamp != null:
		_check("lamps_restored", is_equal_approx(lamp.emission_energy_multiplier, lamp_e0), "общий ресурс ламп вернулся: %.2f" % lamp.emission_energy_multiplier)
	if env != null:
		_check("env_restored", not env.has_meta(FrameArena.META_ENV) and env.fog_mode == int(fog0.get("fog_mode", 0)), "окружение купола вернулось")
	_check("shadows_freed", lf.shadows.decal_count() == 0, "пятна освобождены (%d)" % lf.shadows.decal_count())
	await _ruins()
	_renderer_pin()
	look.set_master(master0)
	var cfg_after := FileAccess.get_file_as_string(cfg) if FileAccess.file_exists(cfg) else ""
	_check("no_look_cfg", cfg_after == cfg_before, "user://look.cfg не тронут")
	lf.headless_enabled = false
	_finish()


## Руины: фон-параллакс темнее и холоднее (множитель цвета слоёв), контровой свет сильнее (светлый день); выключение — как было.
func _ruins() -> void:
	var inst := (load(RUINS) as PackedScene).instantiate()
	add_child(inst)
	await _frames(40)
	var arena: FrameArena = lf.arenas[0] if not lf.arenas.is_empty() else null
	_check("ruins_arena", arena != null and arena.scene == "ruins.tscn", "профиль Руин")
	if arena == null:
		inst.queue_free()
		await _frames(3)
		return
	var sky := inst.get_node_or_null("Ruins/Parallax/Layer4Sky") as MeshInstance3D
	var mat := sky.material_override as BaseMaterial3D if sky != null else null
	var c0: Color = mat.get_meta(FrameArena.META_PAR, Color.BLACK) if mat != null else Color.BLACK
	_check("ruins_parallax", mat != null and mat.has_meta(FrameArena.META_PAR) and mat.albedo_color.v < c0.v,
		"небо фона темнее: %.2f → %.2f" % [c0.v, mat.albedo_color.v if mat != null else -1.0])
	_check("ruins_rim", is_equal_approx(lf.rim_lights[0].light_energy, float(lf.get("RIM_ENERGY")) * arena.rim_mult()) and arena.rim_mult() > 1.0,
		"контровой свет ×%.1f" % arena.rim_mult())
	_check("ruins_no_probe", arena.probe == null, "на открытой арене без ReflectionProbe (небо отражается и так)")
	look.set_master(false)
	_check("ruins_off", mat != null and not mat.has_meta(FrameArena.META_PAR) and mat.albedo_color.is_equal_approx(c0), "фон как было")
	look.set_master(true)
	inst.queue_free()
	await _frames(3)
	_check("ruins_restored", mat != null and mat.albedo_color.is_equal_approx(c0) and lf.arenas.is_empty(), "после ухода арены общий материал фона вернулся")


## RendererPin на пробном пути: ultra пишет forward_plus, high убирает файл; настоящий user://renderer.cfg не трогается.
func _renderer_pin() -> void:
	var real := RendererPin.path
	var real_before := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<нет>"
	RendererPin.path = "user://renderer_probe.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RendererPin.path))
	_check("pin_wanted", RendererPin.wanted_for("ultra") == "forward_plus" and RendererPin.wanted_for("high") == "", "ультра → forward_plus")
	var w1 := RendererPin.write("ultra")
	_check("pin_write", w1 and RendererPin.pinned() == "forward_plus" and RendererPin.next_method() == "forward_plus",
		"файл: %s" % FileAccess.get_file_as_string(RendererPin.path).strip_edges().replace("\n", " "))
	_check("pin_same", not RendererPin.write("ultra"), "повторная запись — без изменений")
	var w2 := RendererPin.write("high")
	_check("pin_remove", w2 and RendererPin.pinned() == "" and not FileAccess.file_exists(RendererPin.path) and RendererPin.next_method() == "mobile",
		"high убрал файл")
	RendererPin.path = real
	var real_after := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<нет>"
	_check("pin_real_untouched", real_after == real_before, "настоящий %s не тронут" % real)
	_check("override_setting", String(ProjectSettings.get_setting("application/config/project_settings_override", "")) == "user://renderer.cfg",
		"project.godot читает user://renderer.cfg")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait_rescan() -> void:
	await get_tree().create_timer(LookFrame_RESCAN() + 0.25).timeout
	await _frames(4)


func LookFrame_RESCAN() -> float:
	return float(lf.get("RESCAN_S"))


func _mesh_count(dolls: Array) -> int:
	var n := 0
	for d in dolls:
		n += FrameDress.meshes(d).size()
	return n


func _rim_bits(dolls: Array) -> int:
	var n := 0
	for d in dolls:
		for mi in FrameDress.meshes(d):
			n += int((mi as MeshInstance3D).layers & FrameDress.RIM_BIT != 0)
	return n


func _bits(dolls: Array, bit: int) -> int:
	var n := 0
	for d in dolls:
		for mi in FrameDress.meshes(d):
			n += int((mi as MeshInstance3D).layers & bit != 0)
	return n


func _surfaces(d: Node) -> Array:
	var out: Array = []
	for mi in FrameDress.meshes(d):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			if mat != null:
				out.append([m, s, mat])
	return out


func _glowing(dolls: Array) -> int:
	var n := 0
	for d in dolls:
		for r in _surfaces(d):
			var mat: BaseMaterial3D = r[2]
			n += int(mat.resource_name.begins_with("Shirt") and mat.emission_enabled and mat.has_meta(FrameDress.META_GLOW))
	return n


func _metas(dolls: Array, key: String) -> int:
	var n := 0
	for d in dolls:
		for r in _surfaces(d):
			n += int((r[2] as Material).has_meta(key))
	return n


func _shirt_emission(d: Node) -> Color:
	for r in _surfaces(d):
		var mat: BaseMaterial3D = r[2]
		if mat.resource_name.begins_with("Shirt") and mat.emission_enabled:
			return mat.emission
	return Color.BLACK


func _coated(d: Node) -> int:
	var n := 0
	for r in _surfaces(d):
		var mat: BaseMaterial3D = r[2]
		n += int(mat.clearcoat_enabled and (str(mat.get_meta(FrameDress.META_MINE, "")) == "coat" or mat.has_meta(FrameDress.META_COAT)))
	return n


func _swaps(d: Node) -> int:
	var n := 0
	for mi in FrameDress.meshes(d):
		n += int((mi as Node).has_meta(FrameDress.META_SWAP) and str((mi as Node).get_meta(FrameDress.META_SWAP)).contains("coat"))
	return n


func _finish() -> void:
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
