## Обводка бойцов (HIT_FX.md §13; автор 02.10: «обводку игроков вкл/выкл — сложно прочитать тело на фоне»): у каждого видимого меша
## куклы — ребёнок «Outline» с тем же мешем и материалом-оболочкой (без освещения, лицевые грани отсекаются, вершины выдавлены по
## нормали на THICK_M) цвета игрока — тёмный фон купола и толпы не съедает силуэт. Узлы ставятся один раз на куклу (meta), вкл/выкл —
## visible. Пока камеру держит эффект (крупный план крита) — обводка скрыта: у рентгена свой силуэт.
##   DollOutline.ensure(doll, colour) — поставить, DollOutline.set_visible(doll, on), DollOutline.count(doll) — для проб.
class_name DollOutline
extends RefCounted

const NAME := "Outline"
const META := "outline_done"
const THICK_M := 0.014
const SKIP_PREFIXES := ["Outline", "Sticker", "Face", "Connector_"]

static var _mats: Dictionary = {}


static func material_for(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html(false)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = THICK_M
	m.albedo_color = Color(colour.r, colour.g, colour.b).lightened(0.1)
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


static func ensure(doll: Node, colour: Color) -> void:
	if doll == null or not is_instance_valid(doll) or doll.has_meta(META):
		return
	doll.set_meta(META, true)
	var mat := material_for(colour)
	for mi in _meshes(doll):
		var o := MeshInstance3D.new()
		o.name = NAME
		o.mesh = (mi as MeshInstance3D).mesh
		o.material_override = mat
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as Node).add_child(o)


static func set_visible(doll: Node, on: bool) -> void:
	if doll == null or not is_instance_valid(doll):
		return
	for o in doll.find_children(NAME, "MeshInstance3D", true, false):
		(o as MeshInstance3D).visible = on


static func count(doll: Node) -> int:
	if doll == null or not is_instance_valid(doll):
		return 0
	return doll.find_children(NAME, "MeshInstance3D", true, false).size()


static func _meshes(doll: Node) -> Array:
	var out: Array = []
	for n in doll.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.has_meta("rig_mesh"):
			continue
		var skip := false
		for pre in SKIP_PREFIXES:
			skip = skip or String(mi.name).begins_with(pre)
		if not skip:
			out.append(mi)
	return out
