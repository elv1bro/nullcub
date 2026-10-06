## Проба вида поля NULL (look-null, docs/plan-demo/look/null.md), headless, exit 0 / 1:
##   dome_attached     в куполе есть NullLook (kind dome), пункты «ВИД» группы «Поле NULL» зарегистрированы;
##   dust_layers       пыль — 3 слоя GPUParticles3D с шейдером движения, слой перед плоскостью боя и за ней, за ней частиц больше;
##   drift_gravity     дрейф пыли — по вектору гравитации поля (cos ≥ 0.99), медленный (0.05…0.6 м/с);
##   shell_mesh        пузырь — куски полуэллипсоида (задние z ≤ 0, передний z ≥ 0, низ на полу): кромка сзади — с преломлением,
##                     передняя — только свет (null_bubble_glow), середина задней стенки в покое спрятана; пункт «преломление»
##                     выкл — задняя половина тоже только свет;
##   shift_event       смена поля: волна по кадру включилась, пыль толкает по новому вектору, табло GRAVITY вспыхнуло, плашка поля в HUD
##                     толкнулась; через 1.6 с дрейф повернулся к новому полю, волна погасла, табло и плашка — как были;
##   hit_waves         сильный удар (Match.hit_fx heavy) и удар о мембрану дают волну (в пыли и на пузыре, середина стенки видна),
##                     лёгкий — нет;
##   wake              быстрый боец оставляет кильватер в пыли, выкл пункта — нет;
##   look_off          выкл пунктов: пыль и пузырь спрятаны, лента мембраны видна с ИСХОДНЫМ материалом (тот же ресурс, шейдер
##                     null_membrane), смена поля без волны; вкл — снова новый вид; рубильник «как было» — всё сразу;
##   other_arenas      Руины — упрощённая пыль (2 слоя, блики тёплые, а не искры NULL, пункт null_dust_plain), спорт-зал и
##                     тренировочный зал — пыль NULL.
## Запуск: godot --headless --path godot --fixed-fps 60 res://tests/look_null_probe.tscn
extends Node

var checks: Array = []
var ok := true
var look: Node


func _ready() -> void:
	look = get_node("/root/Look")
	var master0: bool = look.master
	look.set_master(true)
	var states := {}
	for id in [&"null_dust", &"null_bubble", &"null_refract", &"null_shift", &"null_wake", &"null_dust_plain"]:
		states[id] = look.checked(id)
		look.set_on(id, true)
	await _dome()
	await _others()
	for id in states:
		look.set_on(id, states[id])
	look.set_master(master0)
	for c in checks:
		print("  %s %s — %s" % ["PASS" if c[1] else "FAIL", c[0], c[2]])
	print("look_null_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)


func _check(name: String, cond: bool, detail: String) -> void:
	checks.append([name, cond, detail])
	if not cond:
		ok = false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _dir_cos(v: Vector3, d: Vector2) -> float:
	var a := Vector2(v.x, v.y)
	if a.length() < 1e-6 or d.length() < 1e-6:
		return 0.0
	return a.normalized().dot(d.normalized())


func _dome() -> void:
	var pg: Node = (load("res://scenes/playground_null_hall.tscn") as PackedScene).instantiate()
	add_child(pg)
	await _frames(5)
	# ожидания ниже — в кадрах по 1/60 с (волна смены поля 1.0–1.3 с); без --fixed-fps headless-кадр короче или длиннее → ложный FAIL.
	# Флаг движок забирает себе (в get_cmdline_args его нет) — узнаём по delta
	_check("fixed_fps", absf(get_process_delta_time() - 1.0 / 60.0) < 1e-6,
		"запуск с --fixed-fps 60 (иначе тайминги волны плывут), delta %.4f" % get_process_delta_time())
	var hall := pg.get_node("NullHall") as NullHallArena
	var nl := hall.get_node_or_null("NullLook") as NullLook
	var grp := tr("Поле NULL")
	var reg := true
	for id in [&"null_dust", &"null_bubble", &"null_refract", &"null_shift", &"null_wake"]:
		reg = reg and id in look.ids() and look.group_of(id) == grp
	_check("dome_attached", nl != null and nl.kind == NullLook.KIND_DOME and nl.field != null and reg,
		"NullLook %s, items %s" % ["yes" if nl != null else "no", "ok" if reg else "missing"])
	if nl == null:
		pg.queue_free()
		return
	# --- пыль
	var d := nl.dust
	var front := 0
	var back := 0
	var shader_ok := true
	for p in d.layers:
		var pm := p.process_material as ShaderMaterial
		shader_ok = shader_ok and pm != null and pm.shader.resource_path.ends_with("null_dust_process.gdshader") and p.emitting and p.amount > 0
		var bmin: Vector3 = pm.get_shader_parameter("box_min")
		var bsize: Vector3 = pm.get_shader_parameter("box_size")
		if bmin.z >= 0.0:
			front += p.amount
		elif bmin.z + bsize.z <= 0.0:
			back += p.amount
	_check("dust_layers", d.layers.size() == 3 and shader_ok and front > 0 and back > front and d.visible,
		"layers %d, front %d, back %d, total %d" % [d.layers.size(), front, back, d.total_amount()])
	var drift: Vector3 = (d.layers[0].process_material as ShaderMaterial).get_shader_parameter("drift")
	var cg := _dir_cos(drift, nl.field.field_dir)
	_check("drift_gravity", cg >= 0.99 and drift.length() > 0.05 and drift.length() < 0.6,
		"drift %s, field %s, cos %.3f" % [str(drift), str(nl.field.field_dir), cg])
	# --- пузырь
	var mesh_ok := nl.bubble.size() >= 3 and nl.bubble_centre != null
	var refr := 0
	var glow_front := 0
	var tris := 0
	var floor_ok := false
	for mi in nl.bubble + [nl.bubble_centre]:
		var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		tris += idx.size() / 3
		var is_back: bool = mi.get_meta(&"back", true)
		var zmin := INF
		var zmax := -INF
		var ymin := INF
		for v in vs:
			zmin = minf(zmin, v.z)
			zmax = maxf(zmax, v.z)
			ymin = minf(ymin, v.y)
		mesh_ok = mesh_ok and idx.size() > 0 and ymin > -0.001 and (zmax <= 0.001 if is_back else zmin >= -0.001)
		floor_ok = floor_ok or absf(ymin) < 0.001
		var path := ((mi.material_override as ShaderMaterial).shader as Shader).resource_path
		if is_back and path.ends_with("null_bubble.gdshader"):
			refr += 1
		if not is_back and path.ends_with("null_bubble_glow.gdshader"):
			glow_front += 1
	var rest_vis := true
	for mi in nl.bubble:
		rest_vis = rest_vis and mi.visible
	var centre_rest := not nl.bubble_centre.visible
	look.set_on(&"null_refract", false)
	var refr_off := ((nl.bubble[0].material_override as ShaderMaterial).shader as Shader).resource_path.ends_with("null_bubble_glow.gdshader")
	look.set_on(&"null_refract", true)
	var refr_on := ((nl.bubble[0].material_override as ShaderMaterial).shader as Shader).resource_path.ends_with("null_bubble.gdshader")
	_check("shell_mesh", mesh_ok and floor_ok and refr >= 2 and glow_front == 1 and rest_vis and centre_rest and refr_off and refr_on
		and nl.strip != null and not nl.strip.visible,
		"meshes %d (+centre), triangles %d, with refraction %d, front glow-only %d, centre hidden at rest %s, refraction item off/on %s/%s, old strip hidden %s" % [
		nl.bubble.size(), tris, refr, glow_front, str(centre_rest), str(refr_off), str(refr_on), str(nl.strip != null and not nl.strip.visible)])
	# --- смена поля
	var boards: Array = []
	for lbl in get_tree().get_nodes_in_group("null_hall_gravity"):
		if hall.is_ancestor_of(lbl):
			boards.append([lbl, (lbl as Label3D).modulate])
	var badge: Control = null
	for c in get_tree().root.find_children("*", "PanelContainer", true, false):
		if c is FieldBadge and (c as Control).is_visible_in_tree():
			badge = c
	var badge_scale0 := badge.scale if badge != null else Vector2.ONE
	var new_dir := Vector2(0.7, -0.7)
	hall.set_field(0.35, new_dir)
	await _frames(1)
	var wave_on := nl.shift_rect != null and nl.shift_rect.visible and nl.shifts == 1
	var push: Vector3 = (d.layers[0].process_material as ShaderMaterial).get_shader_parameter("push")
	var push_cos := _dir_cos(push, new_dir)
	var flash_max := 0.0
	var badge_max := 1.0
	for i in 40:
		await _frames(1)
		for b in boards:
			var m: Color = (b[0] as Label3D).modulate
			flash_max = maxf(flash_max, m.b - (b[1] as Color).b)
		if badge != null:
			badge_max = maxf(badge_max, badge.scale.x / maxf(badge_scale0.x, 0.001))
	await _frames(60)
	var drift2: Vector3 = (d.layers[0].process_material as ShaderMaterial).get_shader_parameter("drift")
	var c2 := _dir_cos(drift2, new_dir)
	var restored := true
	for b in boards:
		restored = restored and (b[0] as Label3D).modulate.is_equal_approx(b[1])
	if badge != null:
		restored = restored and badge.scale.is_equal_approx(badge_scale0)
	var push_end: Vector3 = (d.layers[0].process_material as ShaderMaterial).get_shader_parameter("push")
	_check("shift_event", wave_on and push_cos > 0.99 and flash_max > 0.3 and (badge == null or badge_max > 1.05) and c2 >= 0.99
		and not nl.shift_rect.visible and restored and push_end.length() < 1e-4 and boards.size() >= 1,
		"wave %s, push cos %.2f, board flash +%.2f (%d boards), HUD badge ×%.2f%s, drift cos %.3f after 1.7 s, wave off %s, restored %s" % [
		str(wave_on), push_cos, flash_max, boards.size(), badge_max, "" if badge != null else " (no badge)", c2,
		str(not nl.shift_rect.visible), str(restored)])
	# --- волны ударов
	var m_node := pg.get_node("Match")
	var w0 := nl.waves_total
	var hp := Vector3(1.5, 3.0, 0.0)
	var p1 := pg.get_node("P1") as Doll
	var p2 := pg.get_node("P2") as Doll
	# сила кольца — по урону (автор 06.10): слабый удар без кольца, 14 HP — слабое, крит / KO — не слабее своего пола
	var pw_ok := NullLook.wave_power(5.0, "light") == 0.0 and NullLook.wave_power(14.0, "light") > 0.1 \
		and NullLook.wave_power(14.0, "light") < 0.5 and NullLook.wave_power(30.0, "heavy") >= 0.99 \
		and NullLook.wave_power(15.0, "crit") >= 0.85 and NullLook.wave_power(14.0, "ko_crit") >= 0.99
	_check("wave_by_damage", pw_ok, "5 HP %.2f, 14 HP %.2f, 30 HP %.2f, крит 15 HP %.2f" % [NullLook.wave_power(5.0, "light"),
		NullLook.wave_power(14.0, "light"), NullLook.wave_power(30.0, "heavy"), NullLook.wave_power(15.0, "crit")])
	var ctx: Dictionary = m_node.call("make_hit_ctx", p2, p1, 5.0, "punch", hp, 1, false, "", 8.0)
	ctx["tier"] = "light"
	m_node.emit_signal("hit_fx", ctx.duplicate())
	var after_light := nl.waves_total
	ctx["damage"] = 18.0
	ctx["tier"] = "heavy"
	m_node.emit_signal("hit_fx", ctx.duplicate())
	nl.field.membrane_hit.emit(Vector2(16.0, 2.0), 9.0)
	await _frames(2)
	var dw: PackedVector4Array = (d.layers[1].process_material as ShaderMaterial).get_shader_parameter("waves")
	var bw: PackedVector4Array = (nl.bubble[0].material_override as ShaderMaterial).get_shader_parameter("waves")
	var in_dust := false
	var in_bubble := false
	for v in dw:
		in_dust = in_dust or (Vector3(v.x, v.y, v.z).distance_to(hp) < 0.01 and v.w >= 0.0)
	for v in bw:
		in_bubble = in_bubble or (Vector3(v.x, v.y, v.z).distance_to(hp) < 0.01 and v.w >= 0.0)
	var centre_on := nl.bubble_centre.visible
	_check("hit_waves", after_light == w0 and nl.waves_total == w0 + 2 and in_dust and in_bubble and centre_on,
		"light +%d, heavy+membrane +%d, in dust %s, in bubble %s, bubble centre shown %s" % [after_light - w0, nl.waves_total - after_light,
		str(in_dust), str(in_bubble), str(centre_on)])
	# --- Z («Я»): пыль арены вкл / выкл, Ctrl+Z (отмена в мастерской) не трогает
	var dust_was: bool = look.checked(&"null_dust")
	var cfg_path := ProjectSettings.globalize_path("user://look.cfg")
	var cfg_before := FileAccess.get_file_as_string(cfg_path) if FileAccess.file_exists(cfg_path) else ""
	var kz := InputEventKey.new()
	kz.physical_keycode = KEY_Z
	kz.pressed = true
	kz.ctrl_pressed = true
	Input.parse_input_event(kz)
	await _frames(2)
	var ctrl_kept: bool = look.checked(&"null_dust") == dust_was
	var kz2 := InputEventKey.new()
	kz2.physical_keycode = KEY_Z
	kz2.pressed = true
	Input.parse_input_event(kz2)
	await _frames(2)
	var toggled: bool = look.checked(&"null_dust") != dust_was and d.visible != dust_was
	look.set_on(&"null_dust", dust_was)
	# клавиша пишет галочку в user://look.cfg (как панель) — вернуть файл игрока как был
	if cfg_before == "":
		if FileAccess.file_exists(cfg_path):
			DirAccess.remove_absolute(cfg_path)
	else:
		var fw := FileAccess.open(cfg_path, FileAccess.WRITE)
		fw.store_string(cfg_before)
		fw.close()
	_check("z_toggles_dust", ctrl_kept and toggled and d.visible == dust_was, "Ctrl+Z не трогает %s, Z переключает %s, вернули %s" % [
		str(ctrl_kept), str(toggled), str(d.visible == dust_was)])
	# --- кильватер
	for b in p1.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3(14.0, 0.0, 0.0)
	await get_tree().physics_frame
	await _frames(1)
	var wk: PackedVector4Array = (d.layers[1].process_material as ShaderMaterial).get_shader_parameter("wake_vel")
	var wake_on := false
	for v in wk:
		wake_on = wake_on or v.w > 0.0
	look.set_on(&"null_wake", false)
	await _frames(1)
	var wk2: PackedVector4Array = (d.layers[1].process_material as ShaderMaterial).get_shader_parameter("wake_vel")
	var wake_off := true
	for v in wk2:
		wake_off = wake_off and v.w <= 0.0
	look.set_on(&"null_wake", true)
	_check("wake", wake_on and wake_off, "fast fighter wake %s, off clears %s" % [str(wake_on), str(wake_off)])
	# --- выкл / вкл
	var mat0 := nl.strip_mat0
	look.set_on(&"null_bubble", false)
	look.set_on(&"null_dust", false)
	var off_ok := not nl.bubble[0].visible and not nl.bubble[nl.bubble.size() - 1].visible and not nl.bubble_centre.visible and nl.strip.visible and nl.strip.material_override == mat0 \
		and mat0 is ShaderMaterial and (mat0 as ShaderMaterial).shader.resource_path.ends_with("null_membrane.gdshader") and not d.visible
	look.set_on(&"null_shift", false)
	var s0 := nl.shifts
	hall.set_field(0.204, Vector2(0.0, -1.0))
	await _frames(2)
	var no_shift := nl.shifts == s0 and not nl.shift_rect.visible
	look.set_on(&"null_bubble", true)
	look.set_on(&"null_dust", true)
	look.set_on(&"null_shift", true)
	var on_ok := nl.bubble[0].visible and not nl.strip.visible and d.visible
	look.set_master(false)
	var master_off := not nl.bubble[0].visible and nl.strip.visible and nl.strip.material_override == mat0 and not d.visible
	look.set_master(true)
	var master_on := nl.bubble[0].visible and not nl.strip.visible and d.visible
	_check("look_off", off_ok and no_shift and on_ok and master_off and master_on,
		"off: original membrane %s, no shift wave %s; on %s; master off %s, on %s" % [str(off_ok), str(no_shift), str(on_ok),
		str(master_off), str(master_on)])
	pg.queue_free()
	await _frames(3)


func _others() -> void:
	var res := {}
	for e in [["ruins", "res://scenes/playground.tscn", NullLook.KIND_PLAIN], ["sport", "res://scenes/playground_sport.tscn", NullLook.KIND_HALL],
			["training", "res://scenes/arena/training_hall.tscn", NullLook.KIND_HALL]]:
		var sc: Node = (load(String(e[1])) as PackedScene).instantiate()
		add_child(sc)
		await _frames(3)
		var nl: NullLook = null
		for n in sc.find_children("NullLook", "", true, false):
			nl = n as NullLook
		if sc.name == "NullLook":
			nl = sc as NullLook
		var good := nl != null and nl.kind == String(e[2]) and nl.dust != null and nl.dust.total_amount() > 0
		if good and nl.kind == NullLook.KIND_PLAIN:
			var warm := true
			for p in nl.dust.layers:
				var spc: Color = ((p.draw_pass_1 as QuadMesh).material as ShaderMaterial).get_shader_parameter("spark_col")
				warm = warm and spc.r > spc.b
			good = nl.dust.layers.size() == 2 and warm and &"null_dust_plain" in look.ids()
		res[e[0]] = "%s %d" % [nl.kind if nl != null else "none", nl.dust.total_amount() if nl != null and nl.dust != null else 0] if good else "FAIL"
		sc.queue_free()
		await _frames(2)
	var all_ok := true
	for k in res:
		all_ok = all_ok and res[k] != "FAIL"
	_check("other_arenas", all_ok, str(res))
