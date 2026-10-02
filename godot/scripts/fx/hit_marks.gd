## Следы ударов на деталях (HIT_FX.md §13): скол + трещины в точке удара остаются на детали до конца её жизни — урон виден по самой
## кукле (план 06-combat-hud «трещины и сколы по мере потери HP»). Без узлов: на каждый меш ударенной детали — свой ShaderMaterial
## (assets/shaders/doll_marks.gdshader) в material_overlay, до Tuning.JUICE_MARKS_PER_MESH следов в координатах меша. Повторный удар
## ближе JUICE_MARK_MERGE радиуса к следу углубляет и расширяет его, а не добавляет новый; места нет — самый мелкий след заменяется.
## Вид следа — по материалу детали (FxMaterial.MARK_LOOK: под краской дерево, под ржавчиной металл, вмятина на железе, мазок на резине).
## CritCinematic на время ката подменяет material_overlay и потом возвращает прежний — следы переживают крит (материал тот же объект).
##   HitMarks.add(body, world_pos, damage, cls) -> float — сумма глубин следов на детали после удара (для повода N0 worn);
##   HitMarks.wear(body) — та же сумма; HitMarks.marks_of(mesh) — [{p: Vector3 (меш), r, power}] для проб.
class_name HitMarks
extends RefCounted

const SHADER: Shader = preload("res://assets/shaders/doll_marks.gdshader")
const META := "hit_marks"          # меш → {mat: ShaderMaterial, marks: Array}
const BODY_META := "hit_wear"      # тело → сумма глубин
const SKIP_PREFIXES := ["Sticker", "Face", "Connector_", "Outline"]   # Outline — обводка бойцов (DollOutline)


static func radius_for(damage: float) -> float:
	return clampf(Tuning.JUICE_MARK_R0 + Tuning.JUICE_MARK_R_PER_HP * maxf(damage - Tuning.JUICE_MARK_MIN_DAMAGE, 0.0), Tuning.JUICE_MARK_R0,
		Tuning.JUICE_MARK_R_MAX)


static func power_for(damage: float) -> float:
	return clampf(damage / Tuning.JUICE_MARK_FULL_HP, 0.3, 1.0)


static func add(body: Node3D, world_pos: Vector3, damage: float, cls: String) -> float:
	if body == null or not is_instance_valid(body) or damage < Tuning.JUICE_MARK_MIN_DAMAGE:
		return wear(body)
	var r := radius_for(damage)
	var pw := power_for(damage)
	var added := 0.0
	for m in meshes_of(body):
		added = maxf(added, _add_to_mesh(m, world_pos, r, pw, cls))
	var w := wear(body) + added
	body.set_meta(BODY_META, w)
	return w


static func wear(body: Node) -> float:
	if body == null or not is_instance_valid(body):
		return 0.0
	return float(body.get_meta(BODY_META, 0.0))


## Видимые меши детали (без наклеек, лица-плашки, коннекторов и служебного рига).
static func meshes_of(body: Node3D) -> Array:
	var out: Array = []
	_collect(body, out)
	return out


static func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is RigidBody3D:
			continue   # отцепленная/чужая деталь — своё тело
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var skip := not mi.visible or mi.has_meta("rig_mesh") or mi.mesh == null
			for pre in SKIP_PREFIXES:
				skip = skip or String(mi.name).begins_with(pre)
			if not skip:
				out.append(mi)
		_collect(c, out)


static func marks_of(mi: MeshInstance3D) -> Array:
	if mi == null or not mi.has_meta(META):
		return []
	return (mi.get_meta(META) as Dictionary)["marks"]


## След в меш: точка в координатах меша, радиус с поправкой на масштаб меша. Возвращает прибавку глубины.
static func _add_to_mesh(mi: MeshInstance3D, world_pos: Vector3, r: float, pw: float, cls: String) -> float:
	var st: Dictionary = mi.get_meta(META) if mi.has_meta(META) else {}
	if st.is_empty():
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		var look: Array = FxMaterial.MARK_LOOK.get(cls, FxMaterial.MARK_LOOK[FxMaterial.WOOD])
		mat.set_shader_parameter("chip_colour", look[0])
		mat.set_shader_parameter("crack_colour", look[1])
		mat.set_shader_parameter("chip_metal", look[2])
		mat.set_shader_parameter("chip_rough", look[3])
		st = {"mat": mat, "marks": []}
		mi.set_meta(META, st)
	if mi.material_overlay != st["mat"] and mi.material_overlay == null:
		mi.material_overlay = st["mat"]   # чужой оверлей (рентген крита) не трогаем — вернётся наш, когда кат кончится
	var inv := mi.global_transform.affine_inverse()
	var p := inv * world_pos
	var sc := mi.global_basis.get_scale()
	var s := maxf((absf(sc.x) + absf(sc.y) + absf(sc.z)) / 3.0, 1e-4)
	var rl := r / s
	var marks: Array = st["marks"]
	# повтор в то же место — углубить и расширить
	for mk in marks:
		if (mk["p"] as Vector3).distance_to(p) < float(mk["r"]) * Tuning.JUICE_MARK_MERGE:
			var before := float(mk["power"])
			mk["power"] = minf(before + pw * 0.6, 1.5)
			mk["r"] = minf(maxf(float(mk["r"]) * 1.15, rl), Tuning.JUICE_MARK_R_MAX * 1.4 / s)
			_upload(st)
			return float(mk["power"]) - before
	if marks.size() >= Tuning.JUICE_MARKS_PER_MESH:
		var weakest := 0
		for i in range(1, marks.size()):
			if float(marks[i]["power"]) < float(marks[weakest]["power"]):
				weakest = i
		marks.remove_at(weakest)
	marks.append({"p": p, "r": rl, "power": pw})
	_upload(st)
	return pw


static func _upload(st: Dictionary) -> void:
	var marks: Array = st["marks"]
	var v: Array = []
	var pw: Array = []
	for i in range(Tuning.JUICE_MARKS_PER_MESH):
		if i < marks.size():
			var p: Vector3 = marks[i]["p"]
			v.append(Vector4(p.x, p.y, p.z, float(marks[i]["r"])))
			pw.append(float(marks[i]["power"]))
		else:
			v.append(Vector4.ZERO)
			pw.append(0.0)
	var mat: ShaderMaterial = st["mat"]
	mat.set_shader_parameter("marks", v)
	mat.set_shader_parameter("power", PackedFloat32Array(pw))
	mat.set_shader_parameter("count", marks.size())
