## Декали спонсоров телеэфира NULL TV (проход 2 «взрослого вида», docs/plan-demo/grownup_art/README.md, стиль C LEAGUE PRO):
## ORBIT JOINTS на плечах, VOLTA CORES на груди ядра (над окошком CoreGlow), NULL TV на бёдрах — как наклейки спонсоров на болиде.
## Картинки — assets/textures/sponsors/*.png (белое на прозрачном; лист codex jobs_sponsor_decals.json, нарезка — README).
## Наносятся наклейками BodyPaint (меш-декаль на треугольники детали): поверхности цвета игрока (Shirt*) и коннекторы BodyPaint
## пропускает сам — цвет игрока не перекрывается. Не в чертеже: ModularDoll.add_sticker не зовётся (мастерская их не сохраняет и
## не редактирует), имя узла «Sticker_Sponsor» — обводка, следы ударов и FrameDress пропускают «Sticker*» как обычные наклейки.
## Цвет — тёплый белый на тёмной детали, графит на светлой (керамика, кость). Бойцы Лиги и Аоэлюн (LeagueLook) — без спонсоров:
## у них свой эфир. Враги PvE — EnemyLook.setup снимает (clear).
## Зовёт ModularDoll._ready после _apply_paint. Физика не меняется: наклейка — MeshInstance3D без коллизий.
class_name SponsorMarks
extends RefCounted

const DIR := "res://assets/textures/sponsors/"
const NODE_NAME := "Sticker_Sponsor"
const META := "sponsor"
## префикс имени тела куклы («UpperArm_L», «UpperArm_4») → [картинка, ширина в долях поперечника детали, сдвиг вверх в долях высоты]
const SPOTS := {
	"Torso": ["volta_cores", 0.42, 0.18],
	"UpperArm": ["orbit_joints", 0.8, 0.0],
	"UpperLeg": ["null_tv", 0.8, 0.0],
}
const WIDTH_RANGE := Vector2(0.04, 0.16)
## запасные точки, если первая легла на пояс цвета игрока (пустая наклейка): доли высоты детали
const RETRY_UP := [0.0, 0.12, -0.12, 0.26]
const LIGHT := Color(0.86, 0.84, 0.8, 0.82)
const DARK := Color(0.07, 0.07, 0.08, 0.78)
## яркость детали (линейная), выше которой наклейка — графит
const LIGHT_SURFACE := 0.18
## окошко Ядра: латунное кольцо выступает за свечение на эту долю высоты свечения; зазор до верха детали, м
const GLOW_RIM := 0.45
const TOP_MARGIN := 0.02

static var _aspect: Dictionary = {}   # картинка -> высота / ширина
static var _tex_lum: Dictionary = {}  # путь текстуры -> средняя линейная яркость


## Наклейки на куклу. Число поставленных (для проб).
static func apply(doll: ModularDoll) -> int:
	if doll == null or doll.blueprint == null or _has_child_of(doll, "LeagueLook"):
		return 0
	var n := 0
	for node in doll.blueprint.nodes:
		var uid := String(node.get("uid", ""))
		if not doll.uid_body.has(uid) or doll.blueprint.is_fixed(uid):
			continue
		var bn := String(doll.uid_body[uid])
		var key := bn.get_slice("_", 0)
		if not SPOTS.has(key):
			continue
		if _place(doll, uid, SPOTS[key]):
			n += 1
	return n


## Снять наклейки спонсоров (враги PvE).
static func clear(doll: Node) -> void:
	for c in _marks(doll):
		(c as Node).get_parent().remove_child(c)
		(c as Node).queue_free()


static func marks(doll: Node) -> Array:
	return _marks(doll)


static func _marks(n: Node) -> Array:
	var out: Array = []
	if n == null:
		return out
	for c in n.get_children():
		if c is MeshInstance3D and c.has_meta(META):
			out.append(c)
		else:
			out += _marks(c)
	return out


static func _place(doll: ModularDoll, uid: String, spot: Array) -> bool:
	var body := BodyPaint.body_of(doll, uid)
	var root := BodyPaint.mesh_root_of(doll, uid)
	if body == null or root == null:
		return false
	var img := DIR + String(spot[0]) + ".png"
	if not ResourceLoader.exists(img):
		return false
	var to_doll := BodyPaint._rel_xf(root, doll)          # кадр корня меша → кадр куклы (перед — +Z, верх — +Y)
	var box: AABB = to_doll * BodyPaint.mesh_aabb(root)
	if box.size.x <= 0.0 or box.size.y <= 0.0:
		return false
	var w := clampf(minf(box.size.x, box.size.y) * float(spot[1]), WIDTH_RANGE.x, WIDTH_RANGE.y)
	var size := Vector2(w, w * _aspect_of(img))
	var col := DARK if _light(root) else LIGHT
	var base_y := box.get_center().y + box.size.y * float(spot[2])
	var glow := _glow_box(root, to_doll)
	if glow.size.y > 0.0:
		# окошко Ядра (CoreGlow) с латунным кольцом: наклейка над ним, ужимается до места под верхом детали
		var low := glow.end.y + glow.size.y * GLOW_RIM
		var room := box.end.y - TOP_MARGIN - low
		if room < size.y:
			if room < WIDTH_RANGE.x * _aspect_of(img):
				return false
			size *= room / size.y
		base_y = low + size.y * 0.5
	for up in RETRY_UP:
		if glow.size.y > 0.0 and float(up) < 0.0:
			continue
		var p := Vector3(box.get_center().x, base_y + box.size.y * float(up), box.get_center().z)
		if p.y + size.y * 0.5 > box.end.y:
			continue
		var hit := _front_hit(root, to_doll, p, box)
		if hit.is_empty():
			continue
		var nrm: Vector3 = hit["normal"]
		if nrm.z < 0.3:
			continue
		var z := -(Vector3.UP - nrm * Vector3.UP.dot(nrm)).normalized()   # верх картинки — −Z кадра наклейки
		var xf_doll := Transform3D(Basis(nrm.cross(z), nrm, z), hit["position"])
		var st := {"img": img, "xf": to_doll.affine_inverse() * xf_doll, "size": size, "color": col}
		var d := BodyPaint.add_sticker(body, root, st)
		if d == null:
			return false
		if d.mesh != null and d.mesh.get_surface_count() > 0:
			d.name = NODE_NAME
			d.set_meta(META, String(spot[0]))
			return true
		body.remove_child(d)
		d.free()
	return false


## Ближайшее пересечение луча из-за детали (из +Z куклы) с мешами корня: {position, normal} в кадре куклы, {} — мимо.
static func _front_hit(root: Node3D, to_doll: Transform3D, p: Vector3, box: AABB) -> Dictionary:
	var from := Vector3(p.x, p.y, box.end.z + 0.5)
	var best := {}
	var best_d := INF
	for mi in BodyPaint.meshes(root):
		var m := mi as MeshInstance3D
		var tm := m.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var xf := to_doll * BodyPaint._rel_xf(m, root)
		var inv := xf.affine_inverse()
		var r := tm.intersect_ray(inv * from, (inv.basis * Vector3.FORWARD).normalized())
		if r.is_empty():
			continue
		var pos: Vector3 = xf * (r["position"] as Vector3)
		var d := from.distance_to(pos)
		if d < best_d:
			best_d = d
			var nn := (xf.basis.inverse().transposed() * (r["normal"] as Vector3)).normalized()
			if nn.z < 0.0:
				nn = -nn
			best = {"position": pos, "normal": nn}
	return best


## Рамка поверхностей CoreGlow детали в кадре куклы (пустая — окошка нет).
static func _glow_box(root: Node3D, to_doll: Transform3D) -> AABB:
	var out := AABB()
	var any := false
	for mi in BodyPaint.meshes(root):
		var m := mi as MeshInstance3D
		var xf := to_doll * BodyPaint._rel_xf(m, root)
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat == null or not String(mat.resource_name).contains("CoreGlow"):
				continue
			var verts: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w: Vector3 = xf * v
				if not any:
					out = AABB(w, Vector3.ZERO)
					any = true
				else:
					out = out.expand(w)
	return out


static func _aspect_of(img: String) -> float:
	if not _aspect.has(img):
		var t := load(img) as Texture2D
		_aspect[img] = float(t.get_height()) / float(t.get_width()) if t != null and t.get_width() > 0 else 0.7
	return _aspect[img]


## Светлая ли деталь: первый материал Base_* / Wood_* (или любой не цвета игрока) — albedo_color × средняя яркость карты.
static func _light(root: Node3D) -> bool:
	for mi in BodyPaint.meshes(root):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			if mat == null or String(mat.resource_name).begins_with("Shirt"):
				continue
			var c := mat.albedo_color.srgb_to_linear()
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if mat.albedo_texture != null:
				lum *= _lum_of(mat.albedo_texture)
			return lum > LIGHT_SURFACE
	return false


static func _lum_of(t: Texture2D) -> float:
	var key := t.resource_path if t.resource_path != "" else str(t.get_instance_id())
	if not _tex_lum.has(key):
		var v := 0.5
		var img := t.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
			var sum := 0.0
			for y in 8:
				for x in 8:
					var c := img.get_pixel(x, y).srgb_to_linear()
					sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			v = sum / 64.0
		_tex_lum[key] = v
	return _tex_lum[key]


static func _has_child_of(n: Node, cls: String) -> bool:
	for c in n.get_children():
		if c.get_script() != null and (c.get_script() as Script).get_global_name() == cls:
			return true
	return false
