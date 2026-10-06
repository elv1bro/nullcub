## Поле NULL видно всегда (проход по картинке, docs/plan-demo/look/null.md, LOOK_PASS.md п. 4). Узел ставит арена в своём _ready:
## NullLook.attach(self, kind):
##   "dome"  — купол NULL HALL (NullField): пыль и мусор, мембрана-пузырь, смена гравитации как событие, кильватер;
##   "hall"  — тренировочный зал, спорт-зал (поле NULL без купола): пыль NULL и кильватер, дрейф — по гравитации проекта;
##   "plain" — обычные арены (Руины, Полигон): упрощённая пыль.
## Пункты панели «ВИД» (Э), группа «Поле NULL»; выключение сразу возвращает прежний вид (узлы прячутся, лента мембраны — прежняя).
## Волны: сильные удары (Match.hit_fx — heavy / crit / ko), удар о статику (env_slam) и удар о мембрану (NullField.membrane_hit) —
## кольцо от точки: пыль разлетается, по пузырю бежит кольцо сетки. Смена поля (NullField.field_changed: клавиша G, голосование) —
## волна по кадру (null_shift_wave.gdshader), фронт по пузырю, пыль толкает по новому вектору, табло GRAVITY и плашка поля в HUD мигают.
class_name NullLook
extends Node3D

const KIND_DOME := "dome"
const KIND_HALL := "hall"
const KIND_PLAIN := "plain"

const BUBBLE_SHADER := "res://assets/shaders/null_bubble.gdshader"
const SHIFT_SHADER := "res://assets/shaders/null_shift_wave.gdshader"

const BUBBLE_DEPTH := 4.0          # м: полуглубина пузыря по z (лента прежней мембраны — 2.5, якоря — z = −3)
const DRIFT_BASE := 0.06           # м/с: дрейф пыли при слабом поле
const DRIFT_PER_G := 0.9           # м/с на 1 G: при 0.20 G — ≈ 0.24 м/с
const PLAIN_BREEZE := Vector3(0.1, 0.0, 0.0)
const WAVE_LIFE_S := 1.9
const WAVE_POWER := {"light": 0.0, "heavy": 0.55, "crit": 1.0, "ko": 0.85, "ko_crit": 1.0}
const SLAM_POWER_SPEED := Vector2(7.0, 16.0)   # м/с: удар о статику — от слабой волны до 0.6
const SHIFT_S := 1.0               # с: проход волны по кадру
const SHIFT_PUSH := 2.4            # м/с²: толчок пыли по новому полю, пока идёт волна
const SHIFT_BAND := 0.09           # ширина фронта на пузыре — доля высоты кадра (крупный план крита — фронт уже)
const WAKE_SPEED := Vector2(5.0, 12.0)   # м/с ЦМ: с какой скорости кильватер появляется и где он полный
const WAKE_R := 1.4

var kind := KIND_DOME
var arena: Node3D
var field: NullField
var dust: NullDust
var bubble: Array[MeshInstance3D] = []     # [задняя половина, передняя]
var strip: MeshInstance3D                  # прежняя лента мембраны (выкл — видна она)
var strip_mat0: Material                   # её исходный материал (не меняется, проба сверяет)
var shift_layer: CanvasLayer
var shift_rect: ColorRect
var shift_age := -1.0
var shift_dir := Vector2(0.0, -1.0)
var shifts := 0                            # для проб: сколько раз показана смена поля
var shift_band_m := 1.5
var waves: Array = []                      # [{"pos": Vector3, "age": float, "power": float}]
var waves_total := 0                       # для проб
var _bubble_mats: Array[ShaderMaterial] = []
var _shift_mat: ShaderMaterial
var _matches: Array = []
var _match_poll := 0.0
var _flash: Array = []                     # [[CanvasItem | Label3D, исходный modulate]] — что мигает при смене поля
var _flash_t := -1.0
var _look: Node
var _no_waves := PackedVector4Array([Vector4(0, 0, 0, -1), Vector4(0, 0, 0, -1), Vector4(0, 0, 0, -1), Vector4(0, 0, 0, -1)])
var _no_wakes := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])


## Поставить вид поля на арену (зовёт арена в _ready). kind — KIND_DOME / KIND_HALL / KIND_PLAIN.
static func attach(host: Node3D, k: String) -> NullLook:
	var n := NullLook.new()
	n.name = "NullLook"
	n.kind = k
	n.arena = host
	host.add_child(n)
	return n


func _ready() -> void:
	if arena == null:
		arena = get_parent() as Node3D
	# автозагрузка Look — через путь, не по имени: сцены арен грузят и builder-ы в режиме -s, где имён автозагрузок нет
	_look = get_node_or_null("/root/Look")
	if _look != null:
		var grp := tr("Поле NULL")
		if kind == KIND_PLAIN:
			_look.call("add", &"null_dust_plain", tr("Пыль на обычных аренах"), grp)
		else:
			_look.call("add", &"null_dust", tr("Пыль и мусор в объёме боя"), grp)
			_look.call("add", &"null_wake", tr("Кильватер поля за быстрым бойцом"), grp)
		if kind == KIND_DOME:
			_look.call("add", &"null_bubble", tr("Мембрана-пузырь: преломление, радужный край, рябь"), grp)
			_look.call("add", &"null_shift", tr("Смена гравитации: волна по кадру"), grp)
		_look.connect("changed", _on_look)
	if kind == KIND_DOME:
		field = arena.get_node_or_null("Field") as NullField
	_build_dust()
	if kind == KIND_DOME and field != null:
		_build_bubble()
		_build_shift()
		field.field_changed.connect(_on_field_changed)
		field.membrane_hit.connect(_on_membrane_hit)
	_apply(&"null_dust_plain" if kind == KIND_PLAIN else &"null_dust")
	if kind == KIND_DOME:
		_apply(&"null_bubble")
		_apply(&"null_shift")
	_poll_matches()


## Пункт «ВИД» включён (без автозагрузки Look — всё включено).
func _is_on(id: StringName) -> bool:
	return _look == null or bool(_look.call("on", id))


func dust_id() -> StringName:
	return &"null_dust_plain" if kind == KIND_PLAIN else &"null_dust"


# --- сборка ---------------------------------------------------------------------------------------------------------------------

func _build_dust() -> void:
	dust = NullDust.new()
	dust.name = "Dust"
	add_child(dust)
	if kind == KIND_DOME and field != null:
		var a := field.axes
		var c := field.centre
		dust.build(AABB(Vector3(c.x - a.x, c.y, -BUBBLE_DEPTH), Vector3(a.x * 2.0, a.y, BUBBLE_DEPTH * 2.0)), false,
			Vector4(a.x, a.y, BUBBLE_DEPTH, 1.0), Vector3(c.x, c.y, 0.0))
	else:
		var b: AABB = arena.call("bounds") if arena.has_method("bounds") else AABB(Vector3(-16, 0, -1), Vector3(32, 12, 2))
		# низ коробки — не ниже пола (у Руин в границах ямы до −6 м)
		var y0 := maxf(b.position.y, -0.5)
		dust.build(AABB(Vector3(b.position.x, y0, -4.0), Vector3(b.size.x, b.end.y - y0, 8.0)), kind == KIND_PLAIN)
	dust.global_transform = Transform3D.IDENTITY
	dust.set_drift(_drift())


func _build_bubble() -> void:
	strip = field.get_node_or_null(field.membrane_path) as MeshInstance3D
	if strip != null:
		strip_mat0 = strip.material_override
	var sh: Shader = load(BUBBLE_SHADER)
	for back in [true, false]:
		var mi := MeshInstance3D.new()
		mi.name = "BubbleBack" if back else "BubbleFront"
		mi.mesh = half_shell(field.axes.x, field.axes.y, BUBBLE_DEPTH, back)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 4.0
		# задняя половина рисуется первой из прозрачных (её преломление не стирает то, что прозрачно и дальше), передняя — последней
		mi.sorting_offset = -200.0 if back else 200.0
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("back_half", back)
		m.set_shader_parameter("axes", Vector3(field.axes.x, field.axes.y, BUBBLE_DEPTH))
		m.set_shader_parameter("centre", field.centre)
		m.set_shader_parameter("hits", PackedVector4Array(field.hits) if field.hits.size() == 4 else _no_wakes)
		m.set_shader_parameter("waves", _no_waves)
		mi.material_override = m
		add_child(mi)
		mi.position = Vector3(field.centre.x, field.centre.y, 0.0)
		bubble.append(mi)
		_bubble_mats.append(m)


func _build_shift() -> void:
	shift_layer = CanvasLayer.new()
	shift_layer.name = "ShiftWave"
	shift_layer.layer = 4   # ниже стрелок за экраном (5) и HUD (10)
	add_child(shift_layer)
	shift_rect = ColorRect.new()
	shift_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shift_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shift_mat = ShaderMaterial.new()
	_shift_mat.shader = load(SHIFT_SHADER)
	shift_rect.material = _shift_mat
	shift_rect.visible = false
	shift_layer.add_child(shift_rect)


## Половина купола-полуэллипсоида (полуоси a — ширина, b — высота, c — глубина; низ на y = 0): back — z ≤ 0, иначе z ≥ 0.
static func half_shell(a: float, b: float, c: float, back: bool, seg_az := 96, seg_el := 40) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var az0 := PI if back else 0.0
	for j in seg_el + 1:
		var el := (PI * 0.5) * float(j) / seg_el
		for i in seg_az + 1:
			var az := az0 + PI * float(i) / seg_az
			var p := Vector3(a * cos(el) * cos(az), b * sin(el), c * cos(el) * sin(az))
			verts.append(p)
			norms.append(Vector3(p.x / (a * a), p.y / (b * b), p.z / (c * c)).normalized())
			uvs.append(Vector2(float(i) / seg_az, float(j) / seg_el))
	var row := seg_az + 1
	for j in seg_el:
		for i in seg_az:
			var v0 := j * row + i
			idx.append_array([v0, v0 + row, v0 + 1, v0 + 1, v0 + row, v0 + row + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


# --- пункты «ВИД» ---------------------------------------------------------------------------------------------------------------

func _on_look(id: StringName, _on: bool) -> void:
	if id in [&"null_dust", &"null_dust_plain", &"null_bubble", &"null_shift", &"null_wake"]:
		_apply(id)


func _apply(id: StringName) -> void:
	match id:
		&"null_dust", &"null_dust_plain":
			if dust != null and id == dust_id():
				dust.visible = _is_on(id)
		&"null_bubble":
			var on := _is_on(&"null_bubble")
			for b in bubble:
				b.visible = on
			if strip != null:
				strip.visible = not on
				strip.material_override = strip_mat0
		&"null_shift":
			if not _is_on(&"null_shift"):
				_stop_shift()
		&"null_wake":
			if dust != null and not _is_on(&"null_wake"):
				dust.set_wakes(_no_wakes, _no_wakes)


# --- каждый кадр ----------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_match_poll -= delta
	if _match_poll <= 0.0:
		_match_poll = 0.5
		_poll_matches()
	_tick_waves(delta)
	var wv := _pack_waves()
	if dust != null and dust.visible:
		dust.set_drift(_drift())
		dust.set_waves(wv[0], wv[1])
		_tick_wakes()
	# смена поля — событие поля, а не боя: идёт в реальном времени и в замедлении крита / стопе удара
	var real := delta / Engine.time_scale if Engine.time_scale > 0.001 else delta
	if shift_age >= 0.0:
		_tick_shift(real)
	if _flash_t >= 0.0:
		_tick_flash(real)
	if not bubble.is_empty() and bubble[0].visible:
		var hits := PackedVector4Array(field.hits) if field.hits.size() == 4 else _no_wakes
		var sh := _bubble_shift()
		for m in _bubble_mats:
			m.set_shader_parameter("hits", hits)
			m.set_shader_parameter("waves", wv[0])
			m.set_shader_parameter("wave_power", wv[1])
			m.set_shader_parameter("shift", sh)
			m.set_shader_parameter("shift_w", shift_band_m)


## Вектор дрейфа пыли: по гравитации поля (купол) или проекта (остальные арены), медленно.
func _drift() -> Vector3:
	var g_dir := Vector2(0.0, -1.0)
	var g_units := float(ProjectSettings.get_setting("physics/3d/default_gravity", 2.0)) / 9.81
	if field != null:
		g_units = field.field_g
		g_dir = field.field_dir.normalized() if field.field_dir.length() > 0.001 else g_dir
	var v := Vector3(g_dir.x, g_dir.y, 0.0) * (DRIFT_BASE + DRIFT_PER_G * g_units) if g_units > 0.004 else Vector3.ZERO
	if kind == KIND_PLAIN:
		v += PLAIN_BREEZE
	return v


## Волна от точки pos силой power 0..1 (пыль разлетается кольцом, по пузырю бежит кольцо сетки). Не больше 4 сразу — вытесняет старшую.
func add_wave(pos: Vector3, power: float) -> void:
	if power <= 0.0:
		return
	if waves.size() >= 4:
		waves.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["age"]) < float(y["age"]))
		waves.resize(3)
	waves.append({"pos": pos, "age": 0.0, "power": clampf(power, 0.0, 1.0)})
	waves_total += 1


func _tick_waves(delta: float) -> void:
	for i in range(waves.size() - 1, -1, -1):
		waves[i]["age"] = float(waves[i]["age"]) + delta
		if float(waves[i]["age"]) > WAVE_LIFE_S:
			waves.remove_at(i)


func _pack_waves() -> Array:
	if waves.is_empty():
		return [_no_waves, Vector4.ZERO]
	var w := _no_waves.duplicate()
	var pw := Vector4.ZERO
	for i in mini(waves.size(), 4):
		var p: Vector3 = waves[i]["pos"]
		w[i] = Vector4(p.x, p.y, p.z, float(waves[i]["age"]))
		pw[i] = float(waves[i]["power"])
	return [w, pw]


func _tick_wakes() -> void:
	if not _is_on(&"null_wake"):
		return
	var pts := _no_wakes.duplicate()
	var vels := _no_wakes.duplicate()
	var n := 0
	for d in get_tree().get_nodes_in_group("dolls"):
		if n >= 4:
			break
		var doll := d as Doll
		if doll == null or not is_instance_valid(doll) or not doll.is_inside_tree():
			continue
		var v := doll.com_velocity()
		var w := clampf((v.length() - WAKE_SPEED.x) / (WAKE_SPEED.y - WAKE_SPEED.x), 0.0, 1.0)
		if w <= 0.0:
			continue
		var c := doll.centre_of_mass()
		pts[n] = Vector4(c.x, c.y, c.z, WAKE_R)
		vels[n] = Vector4(v.x, v.y, v.z, w)
		n += 1
	dust.set_wakes(pts, vels)


# --- удары ----------------------------------------------------------------------------------------------------------------------

func _poll_matches() -> void:
	if not is_inside_tree():
		return
	for m in get_tree().get_nodes_in_group("match"):
		if m in _matches or not m.has_signal("hit_fx"):
			continue
		_matches.append(m)
		m.connect("hit_fx", _on_hit_fx)
		if m.has_signal("env_slam"):
			m.connect("env_slam", _on_env_slam)


func _on_hit_fx(ctx: Dictionary) -> void:
	var p := float(WAVE_POWER.get(String(ctx.get("tier", "")), 0.0))
	if p > 0.0 and ctx.get("position") is Vector3:
		add_wave(ctx["position"], p)


func _on_env_slam(ctx: Dictionary) -> void:
	var s := float(ctx.get("speed", 0.0))
	var p := clampf((s - SLAM_POWER_SPEED.x) / (SLAM_POWER_SPEED.y - SLAM_POWER_SPEED.x), 0.0, 1.0) * 0.6
	if p > 0.05 and ctx.get("position") is Vector3:
		add_wave(ctx["position"], p)


func _on_membrane_hit(point: Vector2, speed: float) -> void:
	add_wave(Vector3(point.x, point.y, 0.0), clampf(speed / 10.0, 0.3, 1.0))


# --- смена поля -----------------------------------------------------------------------------------------------------------------

func _on_field_changed(_g_units: float, dir: Vector2) -> void:
	if not _is_on(&"null_shift"):
		return
	shift_dir = dir.normalized() if dir.length() > 0.001 else Vector2(0.0, -1.0)
	shift_age = 0.0
	shifts += 1
	if shift_rect != null:
		shift_rect.visible = true
	_start_flash()
	_tick_shift(0.0)


func _stop_shift() -> void:
	shift_age = -1.0
	if shift_rect != null:
		shift_rect.visible = false
	if dust != null:
		dust.set_push(Vector3.ZERO)
	_end_flash()


## Ход волны 0..1 → положение фронта на экране (в высотах экрана от центра) и сила.
func shift_progress() -> float:
	return clampf(shift_age / SHIFT_S, 0.0, 1.0) if shift_age >= 0.0 else -1.0


func _screen_extent(d: Vector2) -> float:
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	return 0.5 * aspect * absf(d.x) + 0.5 * absf(d.y)


func _tick_shift(delta: float) -> void:
	shift_age += delta
	var k := shift_age / SHIFT_S
	var sd := Vector2(shift_dir.x, -shift_dir.y)   # экран: y вниз
	var e := _screen_extent(sd) + 0.2
	var front := lerpf(-e, e + 0.35, k)
	var fade := 1.0 - smoothstep(0.75, 1.15, k)
	if _shift_mat != null:
		_shift_mat.set_shader_parameter("dir", sd)
		_shift_mat.set_shader_parameter("front", front)
		_shift_mat.set_shader_parameter("fade", fade)
	if dust != null:
		dust.set_push(Vector3(shift_dir.x, shift_dir.y, 0.0) * SHIFT_PUSH if k < 0.7 else Vector3.ZERO)
	if k >= 1.15:
		_stop_shift()


## Фронт смены поля на пузыре (мир): тот же фронт, что на экране, пересчитанный на плоскость боя.
func _bubble_shift() -> Vector4:
	if shift_age < 0.0:
		return Vector4(0.0, -1.0, 0.0, 0.0)
	var cam := get_viewport().get_camera_3d()
	var k := shift_age / SHIFT_S
	var sd := Vector2(shift_dir.x, -shift_dir.y)
	var e := _screen_extent(sd) + 0.2
	var front := lerpf(-e, e + 0.35, k)
	var world := front * 20.0
	if cam != null:
		var dist := absf(cam.global_position.z)
		var h := 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5)
		world = Vector2(cam.global_position.x, cam.global_position.y).dot(shift_dir) + front * h
		shift_band_m = SHIFT_BAND * h
	return Vector4(shift_dir.x, shift_dir.y, world, 1.0 - smoothstep(0.8, 1.15, k))


## Табло GRAVITY в зале и плашка поля в HUD мигают, пока идёт смена.
func _start_flash() -> void:
	_end_flash()
	for lbl in get_tree().get_nodes_in_group("null_hall_gravity"):
		if lbl is Label3D and arena.is_ancestor_of(lbl):
			_flash.append([lbl, (lbl as Label3D).modulate])
	for c in get_tree().root.find_children("*", "PanelContainer", true, false):
		if c is FieldBadge and (c as CanvasItem).is_visible_in_tree():
			_flash.append([c, (c as CanvasItem).modulate, (c as Control).scale, (c as Control).pivot_offset])
			(c as Control).pivot_offset = (c as Control).size * 0.5
	_flash_t = 0.0


func _tick_flash(delta: float) -> void:
	_flash_t += delta
	var dur := SHIFT_S * 1.3
	if _flash_t >= dur:
		_end_flash()
		return
	# три вспышки, гаснут к концу
	var blink := pow(0.5 + 0.5 * cos(_flash_t / dur * TAU * 3.0), 2.0) * (1.0 - _flash_t / dur)
	for f in _flash:
		var n: Object = f[0]
		if not is_instance_valid(n):
			continue
		var c0: Color = f[1]
		var hot := Color(c0.r * 2.6 + 0.4, c0.g * 2.6 + 0.6, c0.b * 2.6 + 0.9, c0.a)
		n.set("modulate", c0.lerp(hot, blink))
		if f.size() > 2:   # плашка HUD: 2D без HDR — ярче белого не станет, поэтому ещё и толчок размером
			(n as Control).scale = (f[2] as Vector2) * (1.0 + 0.12 * blink)


func _end_flash() -> void:
	for f in _flash:
		if is_instance_valid(f[0]):
			(f[0] as Object).set("modulate", f[1])
			if f.size() > 2:
				(f[0] as Control).scale = f[2]
				(f[0] as Control).pivot_offset = f[3]
	_flash.clear()
	_flash_t = -1.0
