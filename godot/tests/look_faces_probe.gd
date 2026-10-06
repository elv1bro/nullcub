## Проба лиц с выражениями (look-faces, docs/plan-demo/look/faces.md; headless): FaceExpr цепляется к кукле, голова кита получает атлас,
## удар / сильный удар / KO / «попал» меняют ячейку, моргание идёт само, пункт «ВИД» выкл возвращает исходный материал плашки; манекен —
## наклейка-лицо (треугольники есть, выкл — спрятана); голова с визором лиги не трогается; KitBodies выбирает сцену подмены только для
## манекена. Запуск: godot --headless --path godot res://tests/look_faces_probe.tscn   Exit 0/1.
extends Node

const KIT := "res://scenes/body/presets/pro_sprinter.tscn"
const KIT2 := "res://scenes/body/presets/kit_human.tscn"
const WOOD := "res://scenes/doll/doll.tscn"
const LEAGUE := "res://scenes/body/presets/aoe_predator.tscn"

var ok := true
var _look: Node
var _saved := {}
var _master0 := true


func _check(id: String, cond: bool, detail: String) -> void:
	if not cond:
		ok = false
	print("  %s %s: %s" % ["ok  " if cond else "FAIL", id, detail])


func _ready() -> void:
	print("=== LOOK FACES PROBE ===")
	_look = get_node_or_null("/root/Look")
	_check("look", _look != null, "автозагрузка Look")
	if _look == null:
		_finish()
		return
	_master0 = _look.master
	_look.set_master(true)
	for id in [FaceExpr.LOOK_KIT, FaceExpr.LOOK_WOOD, KitBodies.LOOK_HUMAN, KitBodies.LOOK_SETS]:
		_saved[id] = _look.checked(id)
	_look.set_on(FaceExpr.LOOK_KIT, true)
	_look.set_on(FaceExpr.LOOK_WOOD, true)
	_look.set_on(KitBodies.LOOK_HUMAN, false)
	_look.set_on(KitBodies.LOOK_SETS, false)
	await _kit()
	await _wood()
	await _league()
	_kit_bodies()
	_finish()


func _spawn(path: String, x: float, pi := 0) -> Doll:
	var d := (load(path) as PackedScene).instantiate() as Doll
	d.player_index = pi
	d.external_input = true
	d.position = Vector3(x, 0.0, 0.0)
	add_child(d)
	await get_tree().process_frame
	await get_tree().process_frame
	return d


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _kit_mat(fe: FaceExpr) -> StandardMaterial3D:
	if fe.kit_slots.is_empty():
		return null
	return fe.kit_slots[0]["mat"] as StandardMaterial3D


func _cell_is(fe: FaceExpr, name: String) -> bool:
	var m := _kit_mat(fe)
	return m != null and m.uv1_offset.is_equal_approx(FaceExpr.cell_offset(name)) and fe.expression == name


func _kit() -> void:
	var a := await _spawn(KIT, -2.0, 0)
	var b := await _spawn(KIT2, 2.0, 1)
	var fa := FaceExpr.of(a)
	var fb := FaceExpr.of(b)
	_check("attach", fa != null and fb != null, "FaceExpr у куклы кита (Спринтер, «Человек»)")
	if fa == null or fb == null:
		return
	_check("kit_slots", fa.kit_slots.size() == 1 and fb.kit_slots.size() == 1, "плашка лица найдена: %d / %d" % [fa.kit_slots.size(), fb.kit_slots.size()])
	if fa.kit_slots.is_empty():
		return
	var slot: Dictionary = fa.kit_slots[0]
	var mi := slot["mi"] as MeshInstance3D
	var s := int(slot["s"])
	var orig: Variant = slot["orig"]
	var m := _kit_mat(fa)
	_check("atlas", m != null and mi.get_surface_override_material(s) == m and m.albedo_texture == FaceExpr.atlas()
			and m.uv1_scale.is_equal_approx(FaceExpr.cell_scale()), "на плашке копия материала с атласом 4 × 3")
	_check("neutral", fa.expression == "neutral" and _cell_is(fa, "neutral"), "в покое — нейтральное (%s)" % fa.expression)
	# моргание: таймер вышел — моргнула, через BLINK_S — снова нейтральное
	fa._blink_next = 0.0
	await _frames(2)
	_check("blink", fa.expression == "blink" and _cell_is(fa, "blink"), "моргание идёт само (%s)" % fa.expression)
	await get_tree().create_timer(FaceExpr.BLINK_S + 0.1).timeout
	await _frames(2)
	_check("blink_back", fa.expression == "neutral", "после моргания — нейтральное (%s)" % fa.expression)
	fa._blink_next = 100.0
	fb._blink_next = 100.0
	# удары по кукле: слабый, средний (атакующий — «попал»), сильный
	a.damaged.emit(3.0, null, "Head", Vector3.ZERO, "head")
	await _frames(1)
	_check("wince", _cell_is(fa, "wince"), "слабый удар 3 HP → wince (%s)" % fa.expression)
	await get_tree().create_timer(FaceExpr.HOLD_MIN + 0.1).timeout
	await _frames(1)
	a.damaged.emit(12.0, b, "Torso", Vector3.ZERO, "body")
	await _frames(1)
	_check("hurt", _cell_is(fa, "hurt"), "удар 12 HP → hurt (%s)" % fa.expression)
	_check("smug", _cell_is(fb, "smug"), "бьющий → smug (%s)" % fb.expression)
	a.damaged.emit(30.0, b, "Head", Vector3.ZERO, "head")
	await _frames(1)
	_check("crit", _cell_is(fa, "crit"), "удар 30 HP → crit (%s)" % fa.expression)
	a.damaged.emit(2.0, null, "Head", Vector3.ZERO, "head")
	await _frames(1)
	_check("priority", fa.expression == "crit", "слабый удар не перебивает сильный (%s)" % fa.expression)
	var hold := fa._hold(30.0)
	_check("hold", hold >= FaceExpr.HOLD_MIN and hold <= FaceExpr.HOLD_MAX and fa._hold(100.0) == FaceExpr.HOLD_MAX,
			"держится %.2f с (0.3–1.2 по силе)" % hold)
	# Заряд
	fb._flash_left = 0.0
	b.dash_until = b._time + 1.0
	await _frames(2)
	_check("charge", _cell_is(fb, "charge"), "ускорение (Заряд) → charge (%s)" % fb.expression)
	b.dash_until = 0.0
	# выкл в Look — исходный материал; вкл — снова наш
	_look.set_on(FaceExpr.LOOK_KIT, false)
	_check("look_off", mi.get_surface_override_material(s) == orig, "пункт выкл → override плашки как до FaceExpr (%s)" % str(orig))
	var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
	_check("look_off_tex", src != null and src.albedo_texture != null and src.albedo_texture.resource_path == FaceExpr.KIT_FACE_PATH,
			"видно исходное лицо кита (face_default.png)")
	_look.set_on(FaceExpr.LOOK_KIT, true)
	_check("look_on", mi.get_surface_override_material(s) == m, "пункт вкл → снова атлас")
	# вид класса стычки (SquadLook меняет меш головы на визор): плашка найдена заново, на ней атлас
	SquadLook.apply(b as ModularDoll, "sniper", 0)
	await _frames(2)
	var swapped := false
	for sl in fb.kit_slots:
		var smi := sl["mi"] as MeshInstance3D
		if is_instance_valid(smi) and smi.is_visible_in_tree() and smi.get_surface_override_material(int(sl["s"])) == sl["mat"]:
			swapped = true
	_check("squad_look", swapped, "голова-визор класса стычки получила атлас (плашек: %d)" % fb.kit_slots.size())
	# KO: держится, бьющему — победа
	a.knocked_out.emit(b, {})
	a.alive = false
	await _frames(2)
	_check("ko", _cell_is(fa, "ko"), "KO → спирали (%s)" % fa.expression)
	_check("ko_attacker", _cell_is(fb, "victory"), "выбивший → victory (%s)" % fb.expression)
	a.damaged.emit(40.0, null, "Head", Vector3.ZERO, "head")
	await _frames(1)
	_check("ko_holds", fa.expression == "ko", "после KO удары лицо не меняют (%s)" % fa.expression)
	# фото из мастерской после FaceExpr: выкл пункта фото не затирает
	var photo := (src.duplicate() as StandardMaterial3D)
	photo.albedo_texture = FaceExpr.ink()
	mi.set_surface_override_material(s, photo)
	_look.set_on(FaceExpr.LOOK_KIT, false)
	_check("photo_kept", mi.get_surface_override_material(s) == photo, "выкл пункта не трогает плашку, если на ней уже фото")
	_look.set_on(FaceExpr.LOOK_KIT, true)
	_check("photo_kept_on", mi.get_surface_override_material(s) == photo, "вкл пункта не затирает фото")
	a.queue_free()
	b.queue_free()
	await _frames(2)


func _wood() -> void:
	var t0 := Time.get_ticks_usec()
	var d := await _spawn(WOOD, 0.0, 0)
	var d2 := await _spawn("res://scenes/doll/doll_dark.tscn", 2.0, 1)
	var fe2 := FaceExpr.of(d2)
	_check("wood_dark", fe2 != null and fe2.wood_ok and fe2.wood_sticker != null and fe2.wood_sticker.mesh != null,
			"тёмный орех — тоже наклейка (меш общий: %s)" % str(fe2 != null and FaceExpr.of(d) != null and fe2.wood_sticker != null
			and FaceExpr.of(d).wood_sticker != null and fe2.wood_sticker.mesh == FaceExpr.of(d).wood_sticker.mesh))
	print("  (два манекена с наклейками: %.1f мс вместе со спавном; обход яйца — %.1f мс, один раз на меш)" % [
			(Time.get_ticks_usec() - t0) / 1000.0, FaceExpr.last_build_us / 1000.0])
	d2.queue_free()
	var fe := FaceExpr.of(d)
	_check("wood_attach", fe != null and fe.kit_slots.is_empty() and fe.wood_ok, "манекен: плашки кита нет, голова подходит под наклейку")
	if fe == null or not fe.wood_ok:
		return
	var st := fe.wood_sticker
	var tris := 0
	if st != null and st.mesh != null and st.mesh.get_surface_count() > 0:
		tris = (st.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_check("wood_sticker", st != null and st.visible and tris > 20 and st.get_parent() == d.parts.get("Head"),
			"наклейка-лицо на теле головы: %d треугольников" % tris)
	fe._blink_next = 100.0
	d.damaged.emit(12.0, null, "Head", Vector3.ZERO, "head")
	await _frames(1)
	var wm := st.get_surface_override_material(0) as StandardMaterial3D if st != null else null
	_check("wood_hurt", wm != null and wm.uv1_offset.is_equal_approx(FaceExpr.cell_offset("hurt")), "удар → ячейка hurt на наклейке")
	_look.set_on(FaceExpr.LOOK_WOOD, false)
	_check("wood_off", st != null and not st.visible, "пункт выкл → наклейки не видно")
	_look.set_on(FaceExpr.LOOK_WOOD, true)
	_check("wood_on", st != null and st.visible, "пункт вкл → наклейка снова видна")
	# фото игрока легло на голову манекена (наклейка мастерской «Sticker») — нарисованное лицо уходит
	var photo := MeshInstance3D.new()
	photo.name = "Sticker"
	(d.parts.get("Head") as Node).add_child(photo)
	await _frames(2)
	_check("wood_photo", st != null and not st.visible and not fe.wood_ok, "фото-наклейка на голове → нарисованного лица нет")
	d.queue_free()
	await _frames(2)


func _league() -> void:
	var d := await _spawn(LEAGUE, 0.0, 0)
	var fe := FaceExpr.of(d)
	_check("league_untouched", fe != null and fe.kit_slots.is_empty() and not fe.wood_ok, "визор лиги (фото на плашке) не трогается")
	d.queue_free()
	await _frames(2)


func _kit_bodies() -> void:
	var d := (load(WOOD) as PackedScene).instantiate() as Doll
	d.scene_file_path = WOOD
	_check("kb_off", KitBodies.target_scene(d) == WOOD, "пункты выкл → манекен остаётся")
	_look.set_on(KitBodies.LOOK_HUMAN, true)
	_check("kb_human", KitBodies.target_scene(d) == KitBodies.HUMAN, "«Человек» вкл → kit_human")
	_look.set_on(KitBodies.LOOK_SETS, true)
	d.player_index = 1
	_check("kb_sets", KitBodies.target_scene(d) == KitBodies.SETS[1], "наборы вкл → P2 Титан")
	var k := (load(KIT2) as PackedScene).instantiate() as Doll
	_check("kb_not_mannequin", KitBodies.target_scene(k) == k.scene_file_path, "не манекен — без подмены")
	_look.set_on(KitBodies.LOOK_HUMAN, false)
	_look.set_on(KitBodies.LOOK_SETS, false)
	d.free()
	k.free()


func _finish() -> void:
	if _look != null:
		for id in _saved:
			_look.set_on(id, bool(_saved[id]))
		_look.set_master(_master0)
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
