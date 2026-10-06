## Поле «Гольфа: кукла — мяч» (docs/plan-demo/GOLF.md) внутри купола Old NULL Hall: три лунки по очереди на одном месте — для каждой
## поле собирается кодом заново (build_hole), прежнее убирается из дерева сразу (не queue_free: кукла на новом старте не должна
## встретить старые стены в этом же шаге физики). Купол даёт мембрану (банковый удар) и поле гравитации (сила — Tuning.GOLF_FIELD_G,
## ставит площадка); пол купола — y = 0, мембрана — полуэллипс 16 × 19 м.
## Лунки (hole_data — числа в одном месте; пар — Tuning.GOLF_PARS):
##   1. «Банковый удар»: чаша под козырьком справа, слева её закрывает стенка до козырька — прямой удар не проходит. Сильный удар в
##      мембрану справа ловит её «сеткой» и роняет в проход под козырьком, оттуда — короткий удар в чашу. Яма посередине — недолёт.
##   2. «Машины Свалки»: над стартом низкий потолок — только настильный удар; паровой столб (machine_steam_vent, всё время ACTIVE)
##      поднимает куклу к полке, на полке чаша. Бочки-пушки у столба и у полки: деталь куклы ближе GOLF_BARREL_TOUCH_M — взрыв через
##      GOLF_BARREL_FUSE_S (Explosion), новая бочка через GOLF_BARREL_RESPAWN_S. Яма под полкой — недолёт.
##   3. «Гравитация вбок»: справа от стенки — свой NullField (приоритет выше поля купола): гравитация влево-вниз. Мяч, пущенный далеко
##      вправо, заворачивает назад к стенке, где у её подножия чаша. Ниже зоны — обычная гравитация (в чаше кукла ложится как обычно).
## Запросы для матча и бота: tee_slots, cup, in_hazard, gravity_at, bot_hint; tick(delta, dolls) — бочки.
class_name GolfCourse
extends Node3D

signal barrel_blown(pos: Vector3)

const BARREL_SCENE := "res://scenes/props/scrap/prop_metal_barrel.tscn"
const VENT_SCENE := "res://scenes/props/scrap/machine_steam_vent.tscn"
const GRID_SHADER := "res://assets/shaders/energy_grid.gdshader"
const IRON := "res://assets/textures/pbr/iron/%s.png"
const DEPTH_Z := 2.0
const TEE_GAP_M := 2.6
const HAZARD_COLOUR := Color(1.0, 0.18, 0.12)
const ZONE_COLOUR := Color(0.45, 0.55, 1.0)

var hole_i := -1
var cup: GolfCup
var hall_g := Vector2(0.0, -Tuning.GOLF_FIELD_G * Tuning.G_EARTH)
var data: Dictionary = {}
var barrels: Array = []          # [{home: Vector2, node: ExplosiveBarrel | null, wait: float}]
var vents: Array = []            # SteamVentMachine
var zones: Array = []            # NullField
var _root: Node3D
var _block_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _chevrons: Array = []        # [Label3D, база x, направление]
var _t := 0.0


static func hole_count() -> int:
	return 3


## Данные лунки i: name / tip (ключи перевода), tee, cup (середина дна чаши), blocks (Rect2 — твёрдое), ramps ([a, b] — скат), hazards (Rect2 — ямы, проверка
## по ЦМ), zones ({rect, dir, g}), vents ({x, y, h, w}), barrels (Vector2 — низ бочки), hints — подсказки боту: {from: Rect2 — откуда,
## to — куда, arc (GolfShot.solve), deg — угол (необязательно), power — сила (необязательно: рецепт лунки, без расчёта)}. Без
## подходящей подсказки бот бьёт в чашу «drop».
static func hole_data(i: int) -> Dictionary:
	match i:
		0:
			return {
				"name": "БАНКОВЫЙ УДАР",
				"tip": "Чаша под козырьком: бей сильно в мембрану справа — она поймает и уронит куклу к чаше",
				"tee": Vector2(-12.0, 0.0),
				"cup": Vector2(8.6, 0.0),
				"blocks": [Rect2(1.0, 0.0, 0.6, 4.6), Rect2(1.0, 4.6, 9.8, 0.4)],
				"hazards": [Rect2(-5.5, -0.5, 5.5, 1.6)],
				"zones": [],
				"vents": [],
				"barrels": [],
				"hints": [
					{"from": Rect2(-17.0, -1.0, 18.0, 20.0), "to": Vector2(13.3, 0.8), "arc": "high"},
					{"from": Rect2(1.0, 5.0, 16.0, 15.0), "to": Vector2(13.3, 0.8), "arc": "drop"},
				],
			}
		1:
			return {
				"name": "МАШИНЫ СВАЛКИ",
				"tip": "Низкий потолок: бей настильно в паровой столб — он поднимет к полке с чашей. Бочки взрываются",
				"tee": Vector2(-12.0, 0.0),
				"cup": Vector2(11.4, 7.0),
				"blocks": [Rect2(-16.5, 4.0, 14.5, 0.4), Rect2(8.0, 0.0, 8.5, 7.0)],
				"hazards": [],
				"zones": [],
				"vents": [{"x": 2.0, "y": 0.0, "h": 10.0, "w": 1.8, "speed": 4.0, "drag": 300.0, "top": 0.1, "centre": 5.0}],
				"barrels": [Vector2(5.4, 0.0), Vector2(13.7, 7.0)],
				"hints": [
					{"from": Rect2(-17.0, -1.0, 15.0, 5.0), "to": Vector2(1.2, 0.3), "arc": "low", "deg": 20.0},
					{"from": Rect2(-17.0, 4.4, 17.2, 16.0), "to": Vector2(2.0, 1.5), "arc": "drop"},
					{"from": Rect2(3.8, -1.0, 4.2, 6.5), "to": Vector2(2.2, 0.5), "arc": "drop"},
				],
			}
		_:
			return {
				"name": "ГРАВИТАЦИЯ ВБОК",
				"tip": "Справа от стенки гравитация тянет влево-вниз: перебрось стенку дальше чаши — кукла завернёт назад к стенке",
				"tee": Vector2(-12.0, 0.0),
				"cup": Vector2(4.2, 0.0),
				"blocks": [Rect2(-0.6, 0.0, 1.0, 6.5)],
				"ramps": [[Vector2(-4.0, 0.0), Vector2(-0.6, 6.3)]],
				"hazards": [Rect2(-7.5, -0.5, 4.0, 1.6)],
				"zones": [{"rect": Rect2(0.4, 2.6, 16.0, 17.0), "dir": Vector2(-0.75, -0.66), "g": Tuning.GOLF_SIDE_G}],
				"vents": [],
				"barrels": [],
				"hints": [
					{"from": Rect2(-17.0, -1.0, 16.4, 20.0), "to": Vector2(8.0, 4.0), "deg": 52.0, "power": 0.93},
				],
			}


func _ready() -> void:
	_block_mat = StandardMaterial3D.new()
	_block_mat.albedo_color = Color(0.72, 0.74, 0.8)
	_block_mat.metallic = 0.3
	_block_mat.roughness = 0.55
	if ResourceLoader.exists(IRON % "albedo"):
		_block_mat.albedo_texture = load(IRON % "albedo")
		_block_mat.roughness_texture = load(IRON % "roughness")
		_block_mat.normal_enabled = true
		_block_mat.normal_texture = load(IRON % "normal")
	_block_mat.uv1_triplanar = true
	_block_mat.uv1_world_triplanar = true
	_block_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	_trim_mat = StandardMaterial3D.new()
	_trim_mat.albedo_color = Color(1.0, 0.72, 0.15)
	_trim_mat.emission_enabled = true
	_trim_mat.emission = Color(1.0, 0.6, 0.1)
	_trim_mat.emission_energy_multiplier = 0.6


func par() -> int:
	return int(Tuning.GOLF_PARS[clampi(hole_i, 0, Tuning.GOLF_PARS.size() - 1)])


## Собрать лунку i (прежнее поле — из дерева сразу).
func build_hole(i: int) -> void:
	clear()
	hole_i = i
	data = hole_data(i)
	_root = Node3D.new()
	_root.name = "Hole%d" % (i + 1)
	add_child(_root)
	for r in data["blocks"]:
		_block(r as Rect2)
	for rp in data.get("ramps", []):
		_ramp(rp[0] as Vector2, rp[1] as Vector2)
	for r in data["hazards"]:
		_hazard(r as Rect2)
	for z in data["zones"]:
		_zone(z as Dictionary)
	for v in data["vents"]:
		_vent(v as Dictionary)
	for b in data["barrels"]:
		barrels.append({"home": b as Vector2, "node": null, "wait": 0.0})
		_spawn_barrel(barrels[-1])
	cup = GolfCup.new(i + 1)
	var c: Vector2 = data["cup"]
	_root.add_child(cup)
	cup.position = Vector3(c.x, c.y, 0.0)
	cup.add_to_group("golf_focus")


func clear() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null
	cup = null
	barrels.clear()
	vents.clear()
	zones.clear()
	_chevrons.clear()
	# бочки и их обломки, взрывы — дети поля (Explosion.detonate кладёт себя к родителю бочки)
	for c in get_children():
		if c is RigidBody3D or c is Explosion:
			remove_child(c)
			c.queue_free()


## Места старта для n кукол: P1 — на старте, P2 — на TEE_GAP_M впереди (правее): удар P1 навесом проходит над ним, бот бьёт первый удар
## позже человека (GOLF_BOT_FIRST_S) и не летит сквозь него.
func tee_slots(n: int) -> Array:
	var t: Vector2 = data.get("tee", Vector2.ZERO)
	var out: Array = []
	for k in n:
		var offs := [0.0, TEE_GAP_M, -TEE_GAP_M, TEE_GAP_M * 2.0]
		var off: float = offs[k % 4]
		out.append(Vector3(t.x + off, t.y + 0.05, 0.0))
	return out


func tee_point() -> Vector2:
	return data.get("tee", Vector2.ZERO)


func hole_name() -> String:
	return String(data.get("name", ""))


func tip() -> String:
	return String(data.get("tip", ""))


func in_hazard(p: Vector2) -> bool:
	for r in data.get("hazards", []):
		if (r as Rect2).has_point(p):
			return true
	return false


## Точка у верха столба пара (верхние 3.5 м и 1.5 м над ним): кукла там висит и качается — удар кончается по GOLF_HOVER_REST_SPEED.
func in_vent(p: Vector2) -> bool:
	for v in vents:
		var m := v as SteamVentMachine
		if m == null or not is_instance_valid(m):
			continue
		var r := m.column_rect()
		if Rect2(r.position.x - 0.6, r.end.y - 3.5, r.size.x + 1.2, 5.0).has_point(p):
			return true
	return false


## Гравитация в точке (мир, м/с²): зона лунки (если точка в ней) или поле купола.
func gravity_at(p: Vector2) -> Vector2:
	for z in data.get("zones", []):
		if ((z as Dictionary)["rect"] as Rect2).has_point(p):
			return ((z as Dictionary)["dir"] as Vector2).normalized() * float(z["g"]) * Tuning.G_EARTH
	return hall_g


## Подсказка боту: куда целиться из точки p — {to, arc}. Нет подходящей — в чашу, «min».
func bot_hint(p: Vector2) -> Dictionary:
	for h in data.get("hints", []):
		if ((h as Dictionary)["from"] as Rect2).has_point(p):
			return h
	return {"to": cup.aim_point() if cup != null else Vector2.ZERO, "arc": "min"}


## Бочки: деталь куклы рядом — поджечь; взорванная — новая через GOLF_BARREL_RESPAWN_S.
func tick(delta: float, dolls: Array) -> void:
	_t += delta
	for b in barrels:
		var node: Variant = b["node"]
		if node == null or not is_instance_valid(node) or (node as ExplosiveBarrel).state == Breakable.State.DESTROYED:
			if node != null:
				b["node"] = null
				b["wait"] = Tuning.GOLF_BARREL_RESPAWN_S
			b["wait"] = float(b["wait"]) - delta
			if float(b["wait"]) <= 0.0:
				_spawn_barrel(b)
			continue
		var bar := node as ExplosiveBarrel
		if bar.lit:
			continue
		var c := bar.global_position + Vector3(0.0, 0.45, 0.0)
		for d in dolls:
			var dd := d as Doll
			if dd == null or not is_instance_valid(dd) or not dd.visible:
				continue
			var near := false
			for p in dd.parts.values():
				if is_instance_valid(p) and (p as Node3D).global_position.distance_to(c) < Tuning.GOLF_BARREL_TOUCH_M:
					near = true
					break
			if near:
				bar.ignite(Tuning.GOLF_BARREL_FUSE_S, dd)
				barrel_blown.emit(c)
				break


func _process(_delta: float) -> void:
	for ch in _chevrons:
		var l := ch[0] as Label3D
		if not is_instance_valid(l):
			continue
		var dir: Vector2 = ch[2]
		var k := fposmod(_t * 0.6 + float(ch[1]), 1.0)
		l.modulate.a = 0.8 * sin(k * PI)
		l.position = Vector3(float(ch[3]) + dir.x * k * 1.6, float(ch[4]) + dir.y * k * 1.6, l.position.z)


# --- сборка ---

func _block(r: Rect2) -> void:
	var body := StaticBody3D.new()
	body.name = "Block"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r.size.x, r.size.y, DEPTH_Z)
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = _block_mat
	body.add_child(mi)
	var trim := MeshInstance3D.new()   # жёлтая кромка по верху — видно край
	var tm := BoxMesh.new()
	tm.size = Vector3(r.size.x + 0.04, 0.08, DEPTH_Z + 0.04)
	trim.mesh = tm
	trim.material_override = _trim_mat
	trim.position = Vector3(0.0, r.size.y * 0.5 - 0.03, 0.0)
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(trim)
	body.position = Vector3(r.get_center().x, r.get_center().y, 0.0)
	_root.add_child(body)


## Скат: плита 0.4 м, верх которой — отрезок a → b (стенка лунки 3 слева — горка: недолёт скатывается в яму, а не залипает у стены).
func _ramp(a: Vector2, b: Vector2) -> void:
	var dir := (b - a)
	var n := Vector2(-dir.y, dir.x).normalized()   # нормаль влево-вверх (для a → b вправо-вверх)
	var c := (a + b) * 0.5 - n * 0.2
	var body := StaticBody3D.new()
	body.name = "Ramp"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(dir.length(), 0.4, DEPTH_Z)
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	mi.material_override = _block_mat
	body.add_child(mi)
	var trim := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(dir.length(), 0.08, DEPTH_Z + 0.04)
	trim.mesh = tm
	trim.material_override = _trim_mat
	trim.position = Vector3(0.0, 0.17, 0.0)
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(trim)
	body.position = Vector3(c.x, c.y, 0.0)
	body.rotation.z = dir.angle()
	_root.add_child(body)


## Яма: красная сетка на полу и над ним (проверка — по ЦМ куклы в прямоугольнике r).
func _hazard(r: Rect2) -> void:
	var g := Node3D.new()
	g.name = "Hazard"
	_root.add_child(g)
	var flat := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r.size.x, DEPTH_Z + 1.0)
	flat.mesh = pm
	flat.material_override = _grid_mat(HAZARD_COLOUR, Vector2(r.size.x * 1.5, 4.0), 2.2, 0.18)
	flat.position = Vector3(r.get_center().x, 0.03, 0.0)
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(flat)
	var wall := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(r.size.x, 1.6)
	wall.mesh = qm
	var wm := _grid_mat(HAZARD_COLOUR, Vector2(r.size.x * 1.5, 2.0), 1.4, 0.1)
	wm.set_shader_parameter("fade_top", 0.9)
	wall.material_override = wm
	wall.position = Vector3(r.get_center().x, 0.8, -DEPTH_Z * 0.5 - 0.05)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(wall)
	var light := OmniLight3D.new()
	light.light_color = HAZARD_COLOUR
	light.light_energy = 1.2
	light.omni_range = maxf(r.size.x * 0.7, 3.0)
	light.position = Vector3(r.get_center().x, 0.6, 1.0)
	g.add_child(light)


## Зона гравитации: NullField без мембраны с приоритетом выше поля купола + синяя сетка и бегущие шевроны по направлению.
func _zone(z: Dictionary) -> void:
	var r: Rect2 = z["rect"]
	var dir: Vector2 = (z["dir"] as Vector2).normalized()
	var f := NullField.new()
	f.name = "SideField"
	f.membrane_enabled = false
	f.field_g = float(z["g"])
	f.field_dir = dir
	f.priority = 10
	f.collision_layer = 0
	f.collision_mask = 0xFFFFFFFF
	f.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r.size.x, r.size.y, 8.0)
	cs.shape = bs
	f.add_child(cs)
	f.position = Vector3(r.get_center().x, r.get_center().y, 0.0)
	_root.add_child(f)
	zones.append(f)
	# вид: сетка позади плоскости кукол (в пределах купола) и шевроны
	var vis := Rect2(r.position, Vector2(minf(r.size.x, 15.4 - r.position.x), minf(r.size.y, 16.5 - r.position.y)))
	var panel := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = vis.size
	panel.mesh = qm
	panel.material_override = _grid_mat(ZONE_COLOUR, vis.size * 0.5, 0.55, 0.035)
	panel.position = Vector3(vis.get_center().x, vis.get_center().y, -DEPTH_Z * 0.5 - 0.3)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(panel)
	var glyph := "‹" if dir.x < -0.5 else ("›" if dir.x > 0.5 else ("˅" if dir.y < 0.0 else "˄"))
	var rot := atan2(dir.y, dir.x) - (PI if dir.x < -0.5 else 0.0)
	var k := 0
	var y := vis.position.y + 1.4
	while y < vis.end.y - 0.6:
		var x := vis.position.x + 1.2 + fposmod(float(k) * 0.9, 2.4)
		while x < vis.end.x - 0.8:
			var l := Label3D.new()
			l.text = glyph + glyph
			l.font_size = 160
			l.pixel_size = 0.006
			l.modulate = Color(ZONE_COLOUR.r * 1.2, ZONE_COLOUR.g * 1.2, 1.0, 0.6)
			l.outline_size = 0
			l.rotation.z = rot
			l.position = Vector3(x, y, -DEPTH_Z * 0.5 - 0.25)
			l.shaded = false
			l.double_sided = true
			_root.add_child(l)
			_chevrons.append([l, randf(), dir, x, y])
			x += 3.2
		y += 2.6
		k += 1


func _vent(v: Dictionary) -> void:
	var ps := load(VENT_SCENE) as PackedScene
	if ps == null:
		return
	var m := ps.instantiate() as SteamVentMachine
	m.auto_cycle = false
	m.column_height = float(v["h"])
	m.column_half_w = float(v.get("w", 0.7))
	# в поле гольфа (0.45 G против 0.2 G Свалки) родной столб куклу не поднимает: сильнее поток и сопротивление, спад к верху круче —
	# кукла зависает у верха столба (там сила = её вес), а не вылетает
	m.steam_speed = float(v.get("speed", 6.0))
	m.doll_drag = float(v.get("drag", 160.0))
	m.falloff_top = float(v.get("top", 0.15))
	m.center_k = float(v.get("centre", 2.0))
	m.active_s = 1.0e9
	_root.add_child(m)
	m.position = Vector3(float(v["x"]), float(v["y"]), 0.0)
	m.force_state(ScrapMachine.State.ACTIVE)
	vents.append(m)


func _spawn_barrel(b: Dictionary) -> void:
	var ps := load(BARREL_SCENE) as PackedScene
	if ps == null:
		return
	var n := ps.instantiate() as RigidBody3D
	var home: Vector2 = b["home"]
	add_child(n)   # ребёнок поля, не лунки: взрыв (Explosion) кладёт себя к родителю бочки
	n.global_position = Vector3(home.x, home.y + 0.02, 0.0)
	n.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	n.freeze = true
	b["node"] = n
	b["wait"] = 0.0


func _grid_mat(c: Color, cells: Vector2, glow: float, base_alpha: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(GRID_SHADER)
	m.set_shader_parameter("color", c)
	m.set_shader_parameter("cells", cells)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("base_alpha", base_alpha)
	m.set_shader_parameter("line_w", 0.06)
	return m
