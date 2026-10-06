## Арена в «правиле кадра» (docs/plan-demo/look/frame.md): профиль PROFILES по сцене арены (файл, которому принадлежит её
## WorldEnvironment). Рантаймом, файлы арен не правятся; исходные значения — meta на ресурсах, выключение возвращает ровно их:
##   • backdrop — туман ГЛУБИНЫ за плоскостью боя (fog_mode = depth: начало — расстояние камеры до плоскости z = 0 + begin, конец
##                + end, пересчёт каждый кадр — update_camera), дальний план темнее и холоднее, сами бойцы без дымки (прежний
##                экспоненциальный туман купола клал 25 % дымки и на них); цветокоррекция (контраст, насыщенность); слои
##                фона-параллакса (у них fog_disabled) — множитель цвета: темнее и холоднее. Толпу не трогаем (её ведёт look-show);
##   • lamps    — полосы ламп купола (общие ресурсы кита купола Hall_LightWarm / Hall_LightCool) — эмиссия × lamps, пока арена живёт;
##   • probe    — ReflectionProbe интерьера по габариту мешей арены (обновление один раз, reflection_mask — только куклы, бит
##                FrameDress.PROBE_BIT): глянцу кукол есть что отражать, пол и трибуны не меняются.
## rim — множитель контрового света LookFrame на этой арене (на светлом дне он должен быть сильнее).
class_name FrameArena
extends RefCounted

const META_ENV := "lf_env0"
const META_LAMP := "lf_lamp0"
const META_PAR := "lf_par0"
## Свойства окружения, которые трогает «фон отступает». ambient_light_energy и fog_light_energy НЕ трогаем: их множителем гасит эфир
## на финал раунда (look-show, HallShow._set_final) — свет финала ложится поверх нашего тумана, выключение любого из двух не затирает
## другое. Цвет тумана — наш, его яркость (fog_light_energy) — их.
const ENV_PROPS := ["fog_enabled", "fog_mode", "fog_light_color", "fog_density", "fog_depth_begin", "fog_depth_end",
	"fog_depth_curve", "adjustment_enabled", "adjustment_brightness", "adjustment_contrast", "adjustment_saturation"]
const PAR_LAYERS := ["Layer4Sky", "Layer3Far", "Layer2Mid"]

const HALL_LAMPS := ["Hall_LightWarm", "Hall_LightCool"]
const _DOME_FOG := {"colour": Color(0.016, 0.02, 0.042), "max": 0.78, "begin": 2.5, "end": 24.0, "curve": 0.9}
const PROFILES := {
	"null_hall.tscn": {"fog": _DOME_FOG, "contrast": 1.06, "saturation": 0.9, "lamps": 0.62, "lamp_names": HALL_LAMPS,
		"probe": true, "rim": 1.15},
	"sport_hall.tscn": {"fog": _DOME_FOG, "contrast": 1.06, "saturation": 0.9, "lamps": 0.62, "lamp_names": HALL_LAMPS,
		"probe": true, "rim": 1.15},
	"ruins.tscn": {"fog": {"colour": Color(0.36, 0.39, 0.47), "max": 0.42, "begin": 1.2, "end": 16.0, "curve": 0.8},
		"contrast": 1.05, "saturation": 0.96, "parallax": Color(0.74, 0.77, 0.86), "probe": false, "rim": 1.5},
	"proving_ground.tscn": {"fog": {"colour": Color(0.36, 0.39, 0.47), "max": 0.42, "begin": 1.2, "end": 16.0, "curve": 0.8},
		"contrast": 1.05, "saturation": 0.96, "parallax": Color(0.74, 0.77, 0.86), "probe": false, "rim": 1.5},
	"proving_ground_night.tscn": {"fog": {"colour": Color(0.02, 0.03, 0.07), "max": 0.6, "begin": 1.2, "end": 18.0, "curve": 0.9},
		"contrast": 1.05, "saturation": 0.95, "parallax": Color(0.75, 0.78, 0.85), "probe": false, "rim": 1.2},
}

var we: WorldEnvironment
var root: Node
var scene := ""
var profile: Dictionary = {}
var probe: ReflectionProbe
var _lamps: Array = []       # общие материалы ламп этой арены
var _par: Array = []         # материалы слоёв фона
var _backdrop := false
var _lamps_on := false
var _cam_d := -1.0


## Профиль для WorldEnvironment: ищем вверх по владельцам сцену из PROFILES. Пусто — арена без профиля.
static func find(w: WorldEnvironment) -> FrameArena:
	var o: Node = w.owner if w.owner != null else w.get_parent()
	var guard := 0
	while o != null and guard < 8:
		var f := o.scene_file_path.get_file()
		if PROFILES.has(f):
			var a := FrameArena.new()
			a.we = w
			a.root = o
			a.scene = f
			a.profile = PROFILES[f]
			return a
		o = o.owner
		guard += 1
	return null


func rim_mult() -> float:
	return float(profile.get("rim", 1.0))


func valid() -> bool:
	return we != null and is_instance_valid(we) and we.is_inside_tree()


# --- фон ---

func set_backdrop(on: bool) -> void:
	var env := we.environment if valid() else null
	if env == null:
		return
	if on:
		if not env.has_meta(META_ENV):
			var d := {}
			for p in ENV_PROPS:
				d[p] = env.get(p)
			env.set_meta(META_ENV, d)
		var f: Dictionary = profile["fog"]
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = f["colour"]
		env.fog_density = float(f["max"])
		env.fog_depth_curve = float(f["curve"])
		_cam_d = -1.0
		update_camera(we.get_viewport().get_camera_3d() if we.get_viewport() != null else null)
		var orig: Dictionary = env.get_meta(META_ENV)
		var had := bool(orig["adjustment_enabled"])
		env.adjustment_enabled = true
		env.adjustment_brightness = float(orig["adjustment_brightness"]) if had else 1.0
		env.adjustment_contrast = (float(orig["adjustment_contrast"]) if had else 1.0) * float(profile.get("contrast", 1.0))
		env.adjustment_saturation = (float(orig["adjustment_saturation"]) if had else 1.0) * float(profile.get("saturation", 1.0))
	elif env.has_meta(META_ENV):
		var d: Dictionary = env.get_meta(META_ENV)
		for p in d:
			env.set(p, d[p])
		env.remove_meta(META_ENV)
	_set_parallax(on)
	_backdrop = on


## Начало и конец тумана глубины — от плоскости боя, где бы ни была камера (бой, крит крупным планом, отъезд).
func update_camera(cam: Camera3D) -> void:
	var env := we.environment if valid() else null
	if env == null or cam == null or not env.has_meta(META_ENV):
		return
	var fwd := -cam.global_transform.basis.z
	var d := cam.global_position.z
	if fwd.z < -0.2:
		d = d / maxf(-fwd.z, 0.2)   # наклонная камера: вдоль взгляда до плоскости z = 0
	d = maxf(d, 0.5)
	if absf(d - _cam_d) < 0.05:
		return
	_cam_d = d
	var f: Dictionary = profile["fog"]
	env.fog_depth_begin = d + float(f["begin"])
	env.fog_depth_end = d + float(f["end"])


func _set_parallax(on: bool) -> void:
	if not profile.has("parallax") or root == null or not is_instance_valid(root):
		return
	if on and _par.is_empty():
		var par := root.get_node_or_null("Parallax")
		if par == null:
			return
		for ln in PAR_LAYERS:
			var mi := par.get_node_or_null(ln) as MeshInstance3D
			if mi != null and mi.material_override is BaseMaterial3D:
				_par.append(mi.material_override)
	var tint: Color = profile["parallax"]
	for m in _par:
		var b := m as BaseMaterial3D
		if on:
			if not b.has_meta(META_PAR):
				b.set_meta(META_PAR, b.albedo_color)
			var c0: Color = b.get_meta(META_PAR)
			b.albedo_color = Color(c0.r * tint.r, c0.g * tint.g, c0.b * tint.b, c0.a)
		elif b.has_meta(META_PAR):
			b.albedo_color = b.get_meta(META_PAR)
			b.remove_meta(META_PAR)


# --- лампы ---

func set_lamps(on: bool) -> void:
	if not profile.has("lamps"):
		return
	if on and _lamps.is_empty() and root != null and is_instance_valid(root):
		var names: Array = profile["lamp_names"]
		var seen := {}
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as BaseMaterial3D
				if m != null and not seen.has(m) and names.has(m.resource_name) and m.emission_enabled:
					seen[m] = true
					_lamps.append(m)
	for m in _lamps:
		var b := m as BaseMaterial3D
		if on:
			if not b.has_meta(META_LAMP):
				b.set_meta(META_LAMP, b.emission_energy_multiplier)
			b.emission_energy_multiplier = float(b.get_meta(META_LAMP)) * float(profile["lamps"])
		elif b.has_meta(META_LAMP):
			b.emission_energy_multiplier = float(b.get_meta(META_LAMP))
			b.remove_meta(META_LAMP)
	_lamps_on = on


func lamp_materials() -> Array:
	return _lamps


# --- отражения ---

func set_probe(on: bool, parent: Node) -> void:
	if not bool(profile.get("probe", false)):
		return
	if on and probe == null and root != null and is_instance_valid(root) and parent != null:
		var box := _mesh_bounds(root)
		if box.size == Vector3.ZERO:
			return
		probe = ReflectionProbe.new()
		probe.name = "FrameProbe_" + scene.get_basename()
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.interior = true
		probe.box_projection = true
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		probe.reflection_mask = FrameDress.PROBE_BIT   # отражения — только на куклах (пол и трибуны как были, дёшево)
		probe.size = box.size
		probe.max_distance = box.size.length()
		parent.add_child(probe)
		probe.global_position = box.get_center()
	if probe != null:
		probe.visible = on


## Габарит интерьера: объединение AABB мешей арены (без гигантских фоновых квадов), чуть уже — стены и трибуны внутри коробки.
static func _mesh_bounds(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		if b.size.length() > 150.0:
			continue
		box = b if first else box.merge(b)
		first = false
	return box.grow(-0.5) if not first else AABB()


## Арена уходит из дерева: всё вернуть (общие ресурсы ламп и фона переживают сцену в кэше Godot).
func release() -> void:
	set_lamps(false)
	_set_parallax(false)
	if we != null and is_instance_valid(we) and we.environment != null and we.environment.has_meta(META_ENV):
		var d: Dictionary = we.environment.get_meta(META_ENV)
		for p in d:
			we.environment.set(p, d[p])
		we.environment.remove_meta(META_ENV)
	_backdrop = false
	if probe != null and is_instance_valid(probe):
		probe.queue_free()
	probe = null
