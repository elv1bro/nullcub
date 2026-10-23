## Лица бойцов с выражениями (проход по картинке LOOK_PASS.md, направление look-faces; итог — docs/plan-demo/look/faces.md).
## Узел-ребёнок куклы: Doll._ready в конце зовёт FaceExpr.attach(self) (единственная точка подключения), настройка — отложенно, когда
## ModularDoll уже собрал тело и положил фото (BodyPaint). Match.respawn_doll переносит скриптовых детей — второй узел у новой куклы
## уходит сам (_ready), работает первый.
##
## Где лицо:
##   • голова кита (Kit_Head_*: плашка FacePlate, материал «Face» с картинкой kit/face_default.png, UV 0..1) — копия материала с
##     атласом выражений (assets/textures/faces/face_expr_atlas.png, 4 × 3 ячейки, tools/gen_face_visor.py: LED-глаза на тёмном визоре), ячейка = uv1_offset, как у N0;
##     голова с фото игрока (у плашки другая картинка: BodyPaint.set_face, визор лиги LeagueLook) — не трогается;
##   • деревянный манекен (doll.tscn / doll_dark.tscn, wood_head; плашка Face.* утоплена в «яйцо» головы — её не видно) — своя наклейка
##     «Face_Expr»: треугольники яйца спереди, обрезанные по квадрату лица, трафаретная краска с меткой краш-теста (face_expr_ink.png, без бумаги);
##     только когда фото игрока на голове нет (наклейки BodyPaint «Sticker» на теле головы).
## Пункты «ВИД» (группа «Лица»): faces_expr — выражения на головах кита (выкл — исходный материал плашки), faces_wood — лицо манекена
## (выкл — наклейка убрана). Переключение применяется сразу в обработчике Look.changed (снимки «до / после» — на паузе дерева).
##
## Выражения (EXPRESSIONS = порядок ячеек атласа): состояние куклы — KO (не жива / развалилась) → победа / проигрыш (Match.match_over) →
## оглушена → Заряд (ускорение или раскрутка) → страх (летит после удара быстрее FEAR_SPEED) → нейтральное с морганием каждые 2–5 с;
## поверх — вспышки событий (flash) с приоритетом: получила удар (Doll.damaged: < 5 HP — wince, < 20 — hurt, сильнее — crit), уровень
## удара Match.hit_fx (crit / ko_crit — crit у жертвы, победа у бьющего), сама попала (smug), выбила соперника (victory). Держится
## 0.3–1.2 с по силе. Пороги — как в CONCEPT.md §15 (FaceState) и Tuning (ANNOUNCE_MIN_DAMAGE, HIT_STOP_DAMAGE_1).
## Бойцы-наборы вместо манекена — KitBodies (scripts/look/kit_bodies.gd), его зовёт тот же узел.
class_name FaceExpr
extends Node

const ATLAS_PATH := "res://assets/textures/faces/face_expr_atlas.png"
const INK_PATH := "res://assets/textures/faces/face_expr_ink.png"
const KIT_FACE_PATH := "res://assets/materials/kit/face_default.png"
const COLS := 4
const ROWS := 3
const EXPRESSIONS: Array[String] = ["neutral", "blink", "wince", "hurt", "crit", "ko", "charge", "victory", "fear", "smug", "stun", "sad"]
const LOOK_KIT := &"faces_expr"
const LOOK_WOOD := &"faces_wood"
const NODE_NAME := "FaceExpr"
const STICKER_NAME := "Face_Expr"
## Пороги урона (HP): слабее LIGHT — wince, слабее HEAVY — hurt, иначе crit.
const LIGHT_HP := 5.0
const HEAVY_HP := 20.0
## Сколько держится вспышка: 0.3 + урон / HOLD_PER_HP, не дольше HOLD_MAX.
const HOLD_MIN := 0.3
const HOLD_MAX := 1.2
const HOLD_PER_HP := 40.0
## Страх: в полёте после удара (Doll.is_flying) и ЦМ торса быстрее, м/с.
const FEAR_SPEED := 3.6
const BLINK_S := 0.12
const BLINK_GAP := Vector2(2.0, 5.0)
## Наклейка манекена: сторона квадрата лица (м), центр по высоте — от низа плашки Face.* (доля её высоты), отступ от поверхности (м).
const WOOD_SIZE := 0.18
const WOOD_CENTER_Y := 0.62
const WOOD_LIFT := 0.0008

static var _atlas: Texture2D
static var _ink: Texture2D

var doll: Doll
## Текущее показанное выражение (для проб).
var expression := "neutral"
## Кит: [{mi, s, orig (override до нас или null), mat (наша копия)}].
var kit_slots: Array = []
## Манекен: наклейка (MeshInstance3D) или null; wood_ok — голова подходит (есть утопленная плашка, фото нет).
var wood_sticker: MeshInstance3D
var wood_ok := false
var _wood_mat: StandardMaterial3D
var _wood_head: Node3D
var _wood_egg: MeshInstance3D
var _wood_plate: MeshInstance3D
var _wood_plate_orig: Array = []     # override поверхностей плашки до нас
var _wood_plate_box := AABB()
var _ready_done := false
var _flash := ""
var _flash_left := 0.0
var _flash_pri := -1
var _blink_left := 0.0
var _blink_next := 3.0
var _won := false
var _lost := false
var _matches: Array = []
var _rescan_pending := false


## Подключить к кукле (Doll._ready). Повторный вызов — тот же узел.
static func attach(d: Doll) -> FaceExpr:
	if d == null:
		return null
	for c in d.get_children():
		if c is FaceExpr:
			return c as FaceExpr
	var f := FaceExpr.new()
	f.name = NODE_NAME
	d.add_child(f)
	return f


## Узел выражений куклы (или null).
static func of(d: Node) -> FaceExpr:
	if d == null:
		return null
	for c in d.get_children():
		if c is FaceExpr and not (c as Node).is_queued_for_deletion():
			return c as FaceExpr
	return null


static func atlas() -> Texture2D:
	if _atlas == null and ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH) as Texture2D
	return _atlas


static func ink() -> Texture2D:
	if _ink == null and ResourceLoader.exists(INK_PATH):
		_ink = load(INK_PATH) as Texture2D
	return _ink


## Смещение UV ячейки выражения (как N0Drone._cell_offset).
static func cell_offset(name: String) -> Vector3:
	var i := maxi(EXPRESSIONS.find(name), 0)
	return Vector3(float(i % COLS) / COLS, float(i / COLS) / ROWS, 0.0)


static func cell_scale() -> Vector3:
	return Vector3(1.0 / COLS, 1.0 / ROWS, 1.0)


static func _look() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null("Look") if ml != null else null


static func look_on(id: StringName) -> bool:
	var l := _look()
	return true if l == null else bool(l.call("on", id))


## Плашка головы кита с лицом по умолчанию: материал «Face*» с картинкой KIT_FACE_PATH, не фото (BodyPaint.set_face кладёт фото
## triplanar-проекцией и своей картинкой).
static func is_kit_face(m: Material) -> bool:
	var b := m as BaseMaterial3D
	if b == null or not b.resource_name.begins_with("Face") or b.uv1_triplanar:
		return false
	return b.albedo_texture != null and b.albedo_texture.resource_path == KIT_FACE_PATH


## Копия материала плашки кита с атласом выражений (ячейка name).
static func make_kit_material(src: BaseMaterial3D, name: String) -> StandardMaterial3D:
	var m: StandardMaterial3D
	if src is StandardMaterial3D:
		m = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
	else:
		m = StandardMaterial3D.new()
		m.resource_name = "Face"
		m.roughness = 0.55
	m.albedo_texture = atlas()
	if m.emission_enabled and m.emission_texture != null:
		m.emission_texture = m.albedo_texture   # визор светится той же картинкой (Face.tres, build_body_kit.gd face_glow)
	m.uv1_scale = cell_scale()
	m.uv1_offset = cell_offset(name)
	m.texture_repeat = false
	return m


## Материал наклейки манекена: трафарет краш-теста поверх дерева, альфа вершин — спад к краю «яйца».
static func make_wood_material(name: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "Face_Expr"
	m.albedo_texture = ink()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.texture_repeat = false
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.render_priority = 1
	m.uv1_scale = cell_scale()
	m.uv1_offset = cell_offset(name)
	return m


## Наклейка-лицо на «яйцо» деревянной головы: треугольники меша egg, смотрящие вперёд (+Z меша), обрезанные по квадрату size × size
## с центром center (кадр egg), UV 0..1 по квадрату (верх картинки — вверху). Узел — ребёнок head_body. null — ничего не попало.
static func build_wood_sticker(head_body: Node3D, egg: MeshInstance3D, center: Vector2, size: float, mat: Material) -> MeshInstance3D:
	if head_body == null or egg == null or egg.mesh == null:
		return null
	var to_body := _rel_xf(egg, head_body)
	var key := "%d|%s|%s|%.4f" % [egg.mesh.get_instance_id(), str(to_body), str(center), size]
	var am: ArrayMesh = _sticker_meshes.get(key)
	if am == null:
		am = _wood_sticker_mesh(egg.mesh, to_body, center, size)
		if am == null:
			return null
		_sticker_meshes[key] = am
	var mi := MeshInstance3D.new()
	mi.name = STICKER_NAME
	mi.mesh = am
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = egg.layers
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	head_body.add_child(mi)
	return mi


## Меши наклеек: один на (меш яйца, кадр в теле головы, центр, размер) — у всех манекенов он один и тот же, обход треугольников яйца
## (~мс в GDScript) — только у первой куклы.
static var _sticker_meshes := {}
## Сколько занял последний обход треугольников яйца, мкс (проба).
static var last_build_us := 0


static func _wood_sticker_mesh(mesh: Mesh, to_body: Transform3D, center: Vector2, size: float) -> ArrayMesh:
	var t0 := Time.get_ticks_usec()
	var hw := size * 0.5
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cs := PackedColorArray()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nv: Variant = arr[Mesh.ARRAY_NORMAL]
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		var ii: PackedInt32Array = idx if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0 else PackedInt32Array(range(v.size()))
		var has_n := nv is PackedVector3Array and (nv as PackedVector3Array).size() == v.size()
		for t in range(0, ii.size() - 2, 3):
			var pp: Array = []
			var pn: Array = []
			var front := 0.0
			var out_x := [0, 0]
			var out_y := [0, 0]
			for k in 3:
				var p := v[ii[t + k]]
				var n := (nv as PackedVector3Array)[ii[t + k]] if has_n else Vector3.BACK
				pp.append(p)
				pn.append(n)
				front += n.z
				out_x[0] += int(p.x - center.x < -hw)
				out_x[1] += int(p.x - center.x > hw)
				out_y[0] += int(p.y - center.y < -hw)
				out_y[1] += int(p.y - center.y > hw)
			if front < 0.9 or out_x[0] == 3 or out_x[1] == 3 or out_y[0] == 3 or out_y[1] == 3:
				continue   # смотрит назад / вбок (затылок, бока) или целиком вне квадрата
			for cut in [[0, center.x + hw, true], [0, center.x - hw, false], [1, center.y + hw, true], [1, center.y - hw, false]]:
				var r := _clip(pp, pn, int(cut[0]), float(cut[1]), bool(cut[2]))
				pp = r[0]
				pn = r[1]
				if pp.size() < 3:
					break
			if pp.size() < 3:
				continue
			for k in range(1, pp.size() - 1):
				for w in [0, k, k + 1]:
					var p: Vector3 = pp[w]
					var n: Vector3 = (pn[w] as Vector3).normalized()
					vs.append(to_body * (p + n * WOOD_LIFT))
					ns.append((to_body.basis * n).normalized())
					uvs.append(Vector2((p.x - center.x) / size + 0.5, 0.5 - (p.y - center.y) / size))
					cs.append(Color(1, 1, 1, smoothstep(0.25, 0.55, n.z)))
	if vs.is_empty():
		return null
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = vs
	a[Mesh.ARRAY_NORMAL] = ns
	a[Mesh.ARRAY_TEX_UV] = uvs
	a[Mesh.ARRAY_COLOR] = cs
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	last_build_us = Time.get_ticks_usec() - t0
	return am


## Многоугольник по одну сторону плоскости «ось ax = lim» (upper — оставить ≤ lim), Sutherland–Hodgman, нормали линейно.
static func _clip(pp: Array, pn: Array, ax: int, lim: float, upper: bool) -> Array:
	var op: Array = []
	var on: Array = []
	var n := pp.size()
	for i in n:
		var a: Vector3 = pp[i]
		var b: Vector3 = pp[(i + 1) % n]
		var da := (lim - a[ax]) if upper else (a[ax] - lim)
		var db := (lim - b[ax]) if upper else (b[ax] - lim)
		if da >= 0.0:
			op.append(a)
			on.append(pn[i])
		if (da >= 0.0) != (db >= 0.0):
			var t := da / (da - db)
			op.append(a.lerp(b, t))
			on.append((pn[i] as Vector3).lerp(pn[(i + 1) % n], t))
	return [op, on]


## Кадр n в кадре предка up (произведение локальных трансформов; up не предок — до корня цепочки).
static func _rel_xf(n: Node3D, up: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != up:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _ready() -> void:
	var d := get_parent()
	for c in d.get_children():
		if c is FaceExpr and c != self:
			queue_free()   # перенесён Match.respawn_doll: у новой куклы уже есть свой
			return
	doll = d as Doll
	_blink_next = randf_range(BLINK_GAP.x, BLINK_GAP.y)
	call_deferred("_setup")


func _setup() -> void:
	if doll == null or not is_instance_valid(doll) or is_queued_for_deletion():
		return
	var l := _look()
	if l != null:
		l.call("add", LOOK_KIT, tr("Выражения на лицах бойцов (головы кита)"), tr("Лица"))
		l.call("add", LOOK_WOOD, tr("Нарисованное лицо у деревянного манекена"), tr("Лица"))
		if not l.is_connected("changed", _on_look):
			l.connect("changed", _on_look)
	_find_faces()
	var head := doll.parts.get("Head") as Node
	if head != null and not head.child_entered_tree.is_connected(_on_head_child):
		head.child_entered_tree.connect(_on_head_child)
	if not doll.damaged.is_connected(_on_damaged):
		doll.damaged.connect(_on_damaged)
		doll.knocked_out.connect(_on_ko)
	_hook_matches()
	_ready_done = true
	_apply_kit(look_on(LOOK_KIT))
	_apply_wood(look_on(LOOK_WOOD))
	KitBodies.on_doll_ready(self)


## На голову сел новый меш (вид класса стычки SquadLook, замена детали) — плашки ищутся заново (в конце кадра, один раз на пачку).
func _on_head_child(n: Node) -> void:
	if _rescan_pending or String(n.name) == STICKER_NAME or not _ready_done:
		return
	_rescan_pending = true
	_rescan.call_deferred()


func _rescan() -> void:
	_rescan_pending = false
	if doll == null or not is_instance_valid(doll):
		return
	var on := look_on(LOOK_KIT)
	_apply_kit(false)
	_find_faces()
	_apply_kit(on)
	_apply_wood(look_on(LOOK_WOOD))


func _find_faces() -> void:
	kit_slots.clear()
	wood_ok = false
	if doll.skin_scene != "":
		return   # внешняя модель: риг спрятан
	var head := doll.parts.get("Head") as Node3D
	if head == null:
		return
	var plate: MeshInstance3D
	for mi in _meshes(head):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var o := m.get_surface_override_material(s)
			var src := o if o != null else m.mesh.surface_get_material(s)
			if is_kit_face(src):
				kit_slots.append({"mi": m, "s": s, "orig": o, "src": src, "mat": null})
			elif src != null and src.resource_name.begins_with("Face") and plate == null:
				plate = m
	if not kit_slots.is_empty() or plate == null:
		return
	# манекен: плашка Face.* утоплена в «яйцо» (её родитель — меш головы); фото игрока — наклейка BodyPaint на теле головы
	for c in head.get_children():
		if String(c.name).begins_with("Sticker"):
			return
	var egg := plate.get_parent() as MeshInstance3D
	if egg == null or egg.mesh == null:
		return
	var box := plate.get_aabb()
	box = plate.transform * box
	_wood_head = head
	_wood_egg = egg
	_wood_plate_box = box
	_wood_plate = plate
	wood_ok = true


func _meshes(n: Node) -> Array:
	var out: Array = []
	# material_override — обводка / подсветка (свой материал на весь меш): плашку на ней не трогаем
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).material_override == null \
			and not String(n.name).begins_with("Connector_") and String(n.name) != STICKER_NAME:
		out.append(n)
	for c in n.get_children():
		out += _meshes(c)
	return out


func _hook_matches() -> void:
	if not is_inside_tree():
		return
	for m in get_tree().get_nodes_in_group("match"):
		if _matches.has(m):
			continue
		_matches.append(m)
		if m.has_signal("hit_fx"):
			m.connect("hit_fx", _on_hit_fx)
		if m.has_signal("match_over"):
			m.connect("match_over", _on_match_over)
		if m.has_signal("phase_changed"):
			m.connect("phase_changed", _on_phase)


# --- Look ----------------------------------------------------------------------------------------------------------------------

func _on_look(id: StringName, on: bool) -> void:
	if not _ready_done or doll == null or not is_instance_valid(doll):
		return
	if id == LOOK_KIT:
		_apply_kit(on)
	elif id == LOOK_WOOD:
		_apply_wood(on)
	else:
		KitBodies.on_look(self, id, on)


## Выражения на плашке кита вкл / выкл: выкл — override поверхности как был до нас (если его с тех пор не сменили — фото из мастерской).
func _apply_kit(on: bool) -> void:
	for slot in kit_slots:
		var raw: Variant = slot["mi"]
		if not is_instance_valid(raw):
			continue   # меш головы заменён (вид класса, деталь) — до _rescan
		var mi := raw as MeshInstance3D
		var s := int(slot["s"])
		var cur := mi.get_surface_override_material(s)
		if on:
			if slot["mat"] == null:
				slot["mat"] = make_kit_material(slot["src"] as BaseMaterial3D, expression)
			if cur == slot["orig"]:
				mi.set_surface_override_material(s, slot["mat"])
		elif cur != null and cur == slot["mat"]:
			mi.set_surface_override_material(s, slot["orig"])
	_show(expression, true)


func _apply_wood(on: bool) -> void:
	if not wood_ok:
		if is_instance_valid(wood_sticker) and wood_sticker.visible:   # на голову легло фото игрока (наклейка мастерской)
			wood_sticker.visible = false
			_cover_plate(false)
		return
	if on and wood_sticker == null and is_instance_valid(_wood_egg) and ink() != null:
		_wood_mat = make_wood_material(expression)
		var c := Vector2(_wood_plate_box.get_center().x, _wood_plate_box.position.y + _wood_plate_box.size.y * WOOD_CENTER_Y)
		wood_sticker = build_wood_sticker(_wood_head, _wood_egg, c, WOOD_SIZE, _wood_mat)
	if wood_sticker != null and is_instance_valid(wood_sticker):
		wood_sticker.visible = on
		_cover_plate(on)
	_show(expression, true)


## Плашка манекена видна в «глазницах» яйца двумя чёрными точками (и углами) — под лицом-наклейкой она ровного цвета дерева
## (средний цвет текстуры яйца, plate_cover), выкл — override как был.
func _cover_plate(on: bool) -> void:
	if not is_instance_valid(_wood_plate) or not is_instance_valid(_wood_egg):
		return
	var n := _wood_plate.mesh.get_surface_count()
	if _wood_plate_orig.is_empty():
		for s in n:
			_wood_plate_orig.append(_wood_plate.get_surface_override_material(s))
	var src := _wood_egg.get_surface_override_material(0)
	if src == null:
		src = _wood_egg.mesh.surface_get_material(0)
	var cover := plate_cover(src)
	for s in n:
		_wood_plate.set_surface_override_material(s, cover if on else _wood_plate_orig[s])


static var _covers := {}


## Ровный материал цвета дерева src (среднее albedo-текстуры × albedo_color), кэш на материал.
static func plate_cover(src: Material) -> StandardMaterial3D:
	var key := src.get_instance_id() if src != null else 0
	if _covers.has(key):
		return _covers[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "Face_Cover"
	m.roughness = 0.6
	var c := Color(0.75, 0.56, 0.36)
	var b := src as BaseMaterial3D
	if b != null:
		c = b.albedo_color
		if b.albedo_texture != null:
			var img := b.albedo_texture.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.resize(4, 4, Image.INTERPOLATE_BILINEAR)
				var acc := Color(0, 0, 0)
				for y in 4:
					for x in 4:
						acc += img.get_pixel(x, y)
				c *= acc / 16.0
	m.albedo_color = Color(c.r, c.g, c.b, 1.0)
	_covers[key] = m
	return m


## Выражения сейчас видны (пункт включён и есть куда рисовать).
func active() -> bool:
	return (not kit_slots.is_empty() and look_on(LOOK_KIT)) or (wood_sticker != null and wood_sticker.visible)


# --- выражения -----------------------------------------------------------------------------------------------------------------

## Показать выражение на secs секунд поверх состояния, если приоритет не ниже текущей вспышки.
func flash(name: String, secs: float, pri := 1) -> void:
	if not EXPRESSIONS.has(name) or (_flash_left > 0.0 and pri < _flash_pri):
		return
	_flash = name
	_flash_left = clampf(secs, 0.05, 3.0)
	_flash_pri = pri
	_show(_want(), false)


## Выражение по состоянию куклы (без вспышек и моргания).
func state_expression() -> String:
	if doll == null or not is_instance_valid(doll):
		return "neutral"
	if not doll.alive or doll.is_broken():
		return "ko"
	if _won:
		return "victory"
	if _lost:
		return "sad"
	if doll.is_stunned():
		return "stun"
	if doll.is_dashing() or doll.is_spinning():
		return "charge"
	if doll.is_flying():
		var torso := doll.parts.get("Torso") as RigidBody3D
		if torso != null and torso.linear_velocity.length() > FEAR_SPEED:
			return "fear"
	return "neutral"


func _want() -> String:
	var st := state_expression()
	if st == "ko" or st == "victory" or st == "sad":
		return st   # исход важнее вспышек
	if _flash_left > 0.0:
		return _flash
	if st == "neutral" and _blink_left > 0.0:
		return "blink"
	return st


func _show(name: String, force: bool) -> void:
	if name == expression and not force:
		return
	expression = name
	var off := cell_offset(name)
	for slot in kit_slots:
		var m := slot["mat"] as StandardMaterial3D
		if m != null:
			m.uv1_offset = off
	if _wood_mat != null:
		_wood_mat.uv1_offset = off


func _process(delta: float) -> void:
	if not _ready_done or doll == null:
		return
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash_pri = -1
	if _blink_left > 0.0:
		_blink_left -= delta
	else:
		_blink_next -= delta
		if _blink_next <= 0.0:
			_blink_left = BLINK_S
			# изредка двойное моргание
			_blink_next = randf_range(BLINK_GAP.x, BLINK_GAP.y) if randf() > 0.2 else BLINK_S * 2.5
	_show(_want(), false)


func _hold(amount: float) -> float:
	return clampf(HOLD_MIN + amount / HOLD_PER_HP, HOLD_MIN, HOLD_MAX)


# --- события боя ---------------------------------------------------------------------------------------------------------------

func _on_damaged(amount: float, attacker: Node, _part: String, _pos: Vector3, _kind: String) -> void:
	if amount <= 0.0:
		return
	if amount < LIGHT_HP:
		flash("wince", HOLD_MIN, 1)
	elif amount < HEAVY_HP:
		flash("hurt", _hold(amount), 2)
	else:
		flash("crit", _hold(amount), 3)
	if attacker is Doll and attacker != doll and amount >= LIGHT_HP:
		var fe := FaceExpr.of(attacker)
		if fe != null:
			fe.flash("smug", _hold(amount) * 0.8, 1)


func _on_hit_fx(ctx: Dictionary) -> void:
	var tier := String(ctx.get("tier", ""))
	if tier != "crit" and tier != "ko_crit":
		return
	if ctx.get("victim") == doll:
		flash("crit", HOLD_MAX, 4)
	elif ctx.get("attacker") == doll:
		flash("victory", HOLD_MAX * 0.8, 3)


func _on_ko(attacker: Node, _record: Dictionary) -> void:
	_show("ko", false)
	if attacker is Doll and attacker != doll:
		var fe := FaceExpr.of(attacker)
		if fe != null:
			fe.flash("victory", HOLD_MAX, 4)


func _on_match_over(winner: Variant, _results: Dictionary) -> void:
	if doll == null or not is_instance_valid(doll) or not doll.is_in_group("dolls"):
		return
	_won = winner == doll
	_lost = not _won and winner != null and doll.alive
	_show(_want(), false)


func _on_phase(phase: int) -> void:
	if phase != Match.Phase.OVER:
		_won = false
		_lost = false
