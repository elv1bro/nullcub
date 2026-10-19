## Тень-пятно бойца (docs/plan-demo/look/frame.md, пункт «ВИД» frame_shadow): Mobile-рендерер выключает SSAO, и куклы «висят» над
## полом. На каждую куклу группы "dolls" — до трёх пятен по лучам (вниз, влево, вправо): луч из настоящего центра масс до ближайшей СТАТИЧНОЙ
## поверхности (части кукол и подвижные тела пропускаются), квадрат пятна ложится в плоскость попадания; сила и размер — по
## расстоянию (у пола стоящая кукла — полное пятно, выше — бледнее и шире; у стены — только вплотную). Пятно — экранная декаль
## contact_shadow.gdshader (множит итоговый цвет по глубине сцены; Decal меняет только альбедо — на тёмном блестящем полу купола
## его не видно, проверено 06.10). Лучи — раз в RAY_EVERY физических тиков на куклу (со сдвигом по куклам; исключены только свои части,
## чужая кукла или летящий пропс — повтором), между ними квадрат едет за центром масс по найденной плоскости; расстановка — в
## физическом тике (сглаживается интерполяцией физики, телепорт — reset_physics_interpolation). Было 0,9 мс на тик в стычке 3 на 3
## (лучи каждый тик с исключением всех частей всех кукол) — стало ~0,1 мс. Четвёртое пятно — «за спиной»: квадрат в слое z ∈ BACK_Z ± BACK_H позади плоскости боя, без луча
## (стены Руин и Полигона — декор без коллизий, вплотную за куклой): мягкий тёмный ореол на стене за силуэтом — светлая кукла не
## сливается со светлым кирпичом; где за спиной пусто (купол), пятну не на что лечь. Узлы живут здесь (ребёнок LookFrame), в кукле
## ничего не добавляется; нокаут — пятна гаснут.
## Выключение — enabled = false: всё прячется сразу.
class_name FrameShadows
extends Node3D

const DIRS := [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]   # FORWARD (−Z) — за спиной, без луча
const REACH := [5.5, 1.5, 1.5, 0.0]      # м: дальше луч не ищет поверхность
const ALPHA := [0.62, 0.38, 0.38, 0.42]  # сила пятна в центре у самой поверхности (доля затемнения)
const BACK := 3                     # индекс пятна за спиной
const RAYS := 3                     # пятна по лучам (вниз, влево, вправо)
const RAY_EVERY := 3                # лучи куклы — раз в 3 физических тика (куклы со сдвигом); между ними — та же плоскость
const BACK_Z := -0.55               # центр слоя за спиной (кукла — z ∈ ±0.2)
const BACK_H := 0.33                # полутолщина слоя: от −0.22 до −0.88
const BACK_R := 1.05                # радиус ореола, м (полроста куклы с запасом)
const STAND_D := 1.0                # центр масс стоящей куклы над полом: ближе — пятно полное
const R0 := 0.55                    # радиус пятна у поверхности, м
const R_PER_M := 0.17               # + на метр расстояния
const BOX_H := 0.9                  # толщина слоя у поверхности, где ложится пятно (по нормали, ± половина)
const SMOOTH := 0.35                # доля пути к новой силе за тик
const SHADER := preload("res://assets/shaders/contact_shadow.gdshader")

var enabled := true:
	set(v):
		enabled = v
		if not v:
			for id in _by_doll:
				for dc in _by_doll[id]["q"]:
					(dc as MeshInstance3D).visible = false
					(dc as MeshInstance3D).set_meta("a", 0.0)
					(dc as MeshInstance3D).set_instance_shader_parameter("strength", 0.0)
var _mesh: PlaneMesh
var _mat: ShaderMaterial
var _by_doll := {}   # instance_id куклы → {"q": [MeshInstance3D × 4], "rids": RID своих частей, "nparts", "planes": [[точка, нормаль] | null × 3], "cast"}
var _query: PhysicsRayQueryParameters3D


func _ready() -> void:
	name = "FrameShadows"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2.ONE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mesh.material = _mat


func _physics_process(_dt: float) -> void:
	if not enabled or not is_inside_tree():
		return
	var dolls := get_tree().get_nodes_in_group("dolls")
	var space := get_world_3d().direct_space_state
	var tick := Engine.get_physics_frames()
	var seen := {}
	var k := 0
	for d in dolls:
		if not d is Doll or not (d as Node).is_inside_tree():
			continue
		var doll := d as Doll
		var id := doll.get_instance_id()
		seen[id] = true
		var st: Dictionary = _ensure(id)
		var live := doll.alive and doll.visible and doll.parts.has("Torso")
		var com := doll.centre_of_mass() if live else Vector3.ZERO
		if live and int(st["nparts"]) != doll.parts.size():
			var rids: Array[RID] = []
			for b in doll.parts.values():
				if is_instance_valid(b) and b is CollisionObject3D:
					rids.append((b as CollisionObject3D).get_rid())
			st["rids"] = rids
			st["nparts"] = doll.parts.size()
		var fresh := live and ((tick + k) % RAY_EVERY == 0 or not bool(st["cast"]))
		var planes: Array = st["planes"]
		var qs: Array = st["q"]
		for i in RAYS:
			if fresh:
				var hit := _cast(space, com, DIRS[i] * REACH[i], st["rids"])
				var ok: bool = not hit.is_empty() and (hit["normal"] as Vector3).dot(-DIRS[i]) > 0.6   # поверхность смотрит на куклу
				planes[i] = [hit["position"], hit["normal"]] if ok else null
			_place(qs[i] as MeshInstance3D, i, com, planes[i] if live else null)
		_place_back(qs[BACK] as MeshInstance3D, com, live)
		st["cast"] = st["cast"] or fresh
		k += 1
	for id in _by_doll.keys():
		if not seen.has(id):
			for dc in _by_doll[id]["q"]:
				(dc as Node).queue_free()
			_by_doll.erase(id)


func _ensure(id: int) -> Dictionary:
	if _by_doll.has(id):
		return _by_doll[id]
	var arr: Array = []
	for i in DIRS.size():
		var dc := MeshInstance3D.new()
		dc.name = "Shadow_%d_%d" % [id, i]
		dc.mesh = _mesh
		dc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dc.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		dc.extra_cull_margin = BOX_H
		dc.set_meta("a", 0.0)
		dc.set_instance_shader_parameter("half_h", BACK_H if i == BACK else BOX_H * 0.5)
		dc.visible = false
		add_child(dc)
		arr.append(dc)
	var empty_rids: Array[RID] = []
	var st := {"q": arr, "rids": empty_rids, "nparts": -1, "planes": [null, null, null], "cast": false}
	_by_doll[id] = st
	return st


## Пятно по плоскости, найденной лучом (раз в RAY_EVERY тиков): между лучами квадрат едет за центром масс по той же плоскости.
func _place(dc: MeshInstance3D, i: int, com: Vector3, plane: Variant) -> void:
	var target := 0.0
	if plane != null:
		var p0: Vector3 = plane[0]
		var n: Vector3 = plane[1]
		var dist := (com - p0).dot(n)   # по нормали до плоскости
		if dist > -0.2 and dist < REACH[i] + 0.3:
			dist = maxf(dist, 0.0)
			var t := clampf((dist - STAND_D) / (REACH[i] - STAND_D), 0.0, 1.0) if i == 0 else clampf(dist / REACH[i], 0.0, 1.0)
			target = ALPHA[i] * pow(1.0 - t, 1.5)
			var r := R0 + R_PER_M * dist
			var x := n.cross(Vector3.BACK) if absf(n.z) < 0.9 else n.cross(Vector3.RIGHT)
			x = x.normalized()
			dc.transform = Transform3D(Basis(x * r * 2.0, n, x.cross(n) * r * 2.0), com - n * dist + n * 0.01)
			if not dc.visible:
				dc.reset_physics_interpolation()
	_fade(dc, target)


func _place_back(dc: MeshInstance3D, com: Vector3, live: bool) -> void:
	var target := 0.0
	if live:
		target = ALPHA[BACK]
		var d := BACK_R * 2.0
		dc.transform = Transform3D(Basis(Vector3.RIGHT * d, Vector3.BACK, Vector3.DOWN * d), Vector3(com.x, com.y, BACK_Z))
		if not dc.visible:
			dc.reset_physics_interpolation()
	_fade(dc, target)


func _fade(dc: MeshInstance3D, target: float) -> void:
	var a0 := float(dc.get_meta("a"))
	var a := lerpf(a0, target, SMOOTH) if dc.visible else target
	if a < 0.01:
		a = 0.0
	if absf(a - a0) > 0.002:
		dc.set_meta("a", a)
		dc.set_instance_shader_parameter("strength", a)
	var v := a > 0.0
	if dc.visible != v:
		dc.visible = v


## Луч до статичной поверхности: свои части куклы исключены сразу, подвижные тела (чужая кукла, оружие, пропсы в полёте) — повтором
## (до двух).
func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, ray: Vector3, rids: Array[RID]) -> Dictionary:
	if _query == null:
		_query = PhysicsRayQueryParameters3D.new()
		_query.collide_with_areas = false
	_query.from = from
	_query.to = from + ray
	_query.exclude = rids
	var ex: Array[RID] = rids
	for k in 3:
		var hit := space.intersect_ray(_query)
		if hit.is_empty():
			return {}
		var col: Object = hit.get("collider")
		if col is RigidBody3D and not (col as RigidBody3D).freeze:
			if ex == rids:
				ex = rids.duplicate()
			ex.append((col as RigidBody3D).get_rid())
			_query.exclude = ex
			continue
		return hit
	return {}


## Видимых пятен сейчас (для проб).
func visible_count() -> int:
	var n := 0
	for id in _by_doll:
		for dc in _by_doll[id]["q"]:
			n += int((dc as MeshInstance3D).visible)
	return n


func decal_count() -> int:
	var n := 0
	for id in _by_doll:
		n += (_by_doll[id]["q"] as Array).size()
	return n
