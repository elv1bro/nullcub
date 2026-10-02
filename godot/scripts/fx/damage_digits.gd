## Цифры-обломки (HIT_FX.md §13; автор 02.10: «цифры, если сделать красиво с обломками, чтобы как часть падало, может и окей»):
## урон удара выпадает из точки удара объёмной цифрой цвета краски жертвы — как кусок, отколотый от неё. Вылетает вверх и в сторону
## от атакующего, крутится в плоскости экрана (читается всегда), падает тяжелее поля NULL, отскакивает от статики и лежит
## Tuning.JUICE_DIGIT_REST_S, потом уходит в пол. Большая цифра (≥ JUICE_DIGIT_BIG) светится.
## Не физика Jolt: тела на слое 1 толкали бы кукол и считались бы DollCombat ударом. Свой полёт: луч до статики (StaticBody3D, CSG)
## под цифрой, иначе пол — низ bounds() арены; стены — края bounds по X. Время — шаг физики (замирает на стоп-кадре вместе с боем).
## Клавиша «−» (HitJuice.digits_on) — вкл/выкл. Пул: JUICE_DIGIT_MAX кусков, по 3 MeshInstance3D (TextMesh на символ, кэш), старый кусок переиспользуется — узлы не плодятся.
class_name DamageDigits
extends Node3D

const FONT_NAMES := ["Impact", "Arial Black", "Haettenschweiler", "Arial"]
const FONT_SIZE := 96
const PIXEL := 0.004
const DEPTH := 0.09
const MAX_CHARS := 3
const GAP := 0.012                 # м между символами (до масштаба)
const POP_S := 0.12
const SINK_S := 0.35
const REST_SPEED := 0.6            # м/с: медленнее на полу — лежит
const Z_FRONT := 0.3              # м к камере от точки удара: цифра не прячется в куклах
const FRICTION := 0.7              # доля скорости вдоль пола после удара о пол

static var _glyphs: Dictionary = {}     # символ -> TextMesh
static var _mats: Dictionary = {}       # цвет+big -> StandardMaterial3D
static var _font: SystemFont

## Куски: {root, meshes, state ("fly" | "rest" | "sink" | "free"), pos, vel, ang, spin, t, h, rr, text, big}.
var chunks: Array = []
var stats := {"spawned": 0, "landed": 0, "reused": 0}
var arena: Node = null


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(FONT_NAMES)
		_font.font_weight = 900
	return _font


static func glyph(ch: String) -> TextMesh:
	if _glyphs.has(ch):
		return _glyphs[ch]
	var tm := TextMesh.new()
	tm.font = font()
	tm.text = ch
	tm.font_size = FONT_SIZE
	tm.pixel_size = PIXEL
	tm.depth = DEPTH
	tm.curve_step = 1.5
	_glyphs[ch] = tm
	return tm


static func material_for(colour: Color, big: bool) -> StandardMaterial3D:
	var key := "%s|%d" % [colour.to_html(false), int(big)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(colour.r, colour.g, colour.b)
	m.roughness = 0.45
	m.metallic_specular = 0.6
	m.emission_enabled = true
	m.emission = Color(colour.r, colour.g, colour.b)
	m.emission_energy_multiplier = 0.9 if big else 0.12
	m.rim_enabled = true
	m.rim = 0.35
	_mats[key] = m
	return m


static func height_for(damage: float) -> float:
	return clampf(Tuning.JUICE_DIGIT_H0 + Tuning.JUICE_DIGIT_H_PER_HP * (damage - Tuning.JUICE_DIGIT_MIN_DAMAGE), Tuning.JUICE_DIGIT_H0,
		Tuning.JUICE_DIGIT_H_MAX)


static func text_for(damage: float) -> String:
	return str(clampi(roundi(damage), 1, 999))


func spawn(damage: float, pos: Vector3, side: float, colour: Color, big: bool) -> Dictionary:
	if damage < Tuning.JUICE_DIGIT_MIN_DAMAGE:
		return {}
	var c := _take_chunk()
	var text := text_for(damage)
	var h := height_for(damage)
	var mat := material_for(colour, big)
	var meshes: Array = c["meshes"]
	var widths: Array = []
	var total := 0.0
	var gh := 0.0
	for i in range(MAX_CHARS):
		var mi := meshes[i] as MeshInstance3D
		if i < text.length():
			var g := glyph(text[i])
			mi.mesh = g
			mi.material_override = mat
			mi.visible = true
			var ab := g.get_aabb()
			widths.append(ab.size.x)
			total += ab.size.x + (GAP if i > 0 else 0.0)
			gh = maxf(gh, ab.size.y)
		else:
			mi.visible = false
	var x := -total * 0.5
	for i in range(text.length()):
		var mi := meshes[i] as MeshInstance3D
		var w := float(widths[i])
		mi.position = Vector3(x + w * 0.5, 0.0, 0.0)
		x += w + GAP
	var k := h / maxf(gh, 1e-3)
	var s := 1.0 if side >= 0.0 else -1.0
	c["text"] = text
	c["big"] = big
	c["h"] = h
	c["k"] = k
	c["rr"] = 0.5 * maxf(h, total * k) * 0.8
	c["pos"] = pos + Vector3(0.0, 0.1, Z_FRONT)
	c["vel"] = Vector3(s * randf_range(0.35, 1.1), randf_range(3.2, 4.4), 0.0)
	c["ang"] = randf_range(-0.4, 0.4)
	c["spin"] = randf_range(2.0, 5.5) * (-s if randf() < 0.7 else s)
	c["t"] = 0.0
	c["state"] = "fly"
	var root := c["root"] as Node3D
	root.visible = true
	_apply(c)
	stats["spawned"] = int(stats["spawned"]) + 1
	return c


func clear() -> void:
	for c in chunks:
		_free_chunk(c)


func live_count() -> int:
	var n := 0
	for c in chunks:
		if String(c["state"]) != "free":
			n += 1
	return n


func resting_count() -> int:
	var n := 0
	for c in chunks:
		if String(c["state"]) == "rest":
			n += 1
	return n


func _take_chunk() -> Dictionary:
	for c in chunks:
		if String(c["state"]) == "free":
			return c
	if chunks.size() < Tuning.JUICE_DIGIT_MAX:
		var root := Node3D.new()
		root.name = "Digit%d" % chunks.size()
		add_child(root)
		var meshes: Array = []
		for i in range(MAX_CHARS):
			var mi := MeshInstance3D.new()
			root.add_child(mi)
			meshes.append(mi)
		var c := {"root": root, "meshes": meshes, "state": "free"}
		chunks.append(c)
		return c
	# все заняты — самый старый (лежит дольше всех / летит дольше всех)
	var oldest: Dictionary = chunks[0]
	for c in chunks:
		if _age_key(c) > _age_key(oldest):
			oldest = c
	stats["reused"] = int(stats["reused"]) + 1
	return oldest


static func _age_key(c: Dictionary) -> float:
	var t := float(c.get("t", 0.0))
	return t + (100.0 if String(c["state"]) == "sink" else (50.0 if String(c["state"]) == "rest" else 0.0))


func _free_chunk(c: Dictionary) -> void:
	c["state"] = "free"
	(c["root"] as Node3D).visible = false


func _physics_process(delta: float) -> void:
	if chunks.is_empty():
		return
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var b := _bounds()
	for c in chunks:
		var st := String(c["state"])
		if st == "free":
			continue
		c["t"] = float(c["t"]) + delta
		match st:
			"fly":
				_fly(c, delta, space, b)
			"rest":
				# ложится ровно: к ближайшему кратному 90° (стоит на основании или на боку)
				var a := float(c["ang"])
				c["ang"] = lerp_angle(a, snappedf(a, PI * 0.5), clampf(delta * 8.0, 0.0, 1.0))
				if float(c["t"]) >= Tuning.JUICE_DIGIT_REST_S:
					c["state"] = "sink"
					c["t"] = 0.0
			"sink":
				if float(c["t"]) >= SINK_S:
					_free_chunk(c)
					continue
		_apply(c)


func _fly(c: Dictionary, delta: float, space: PhysicsDirectSpaceState3D, b: AABB) -> void:
	var pos: Vector3 = c["pos"]
	var vel: Vector3 = c["vel"]
	vel.y -= Tuning.JUICE_DIGIT_GRAVITY * delta
	var nxt := pos + vel * delta
	var rr := float(c["rr"])
	var hit := _ground(space, pos, nxt, rr)
	if hit.is_empty() and b.size != Vector3.ZERO and nxt.y - rr < b.position.y:
		hit = {"position": Vector3(nxt.x, b.position.y, nxt.z), "normal": Vector3.UP}
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		nxt = (hit["position"] as Vector3) + n * rr
		var vn := n * vel.dot(n)
		var vt := vel - vn
		vel = vt * FRICTION - vn * Tuning.JUICE_DIGIT_BOUNCE
		c["spin"] = float(c["spin"]) * 0.5 - vt.x * 1.5
		if vel.length() < REST_SPEED and n.y > 0.5:
			vel = Vector3.ZERO
			c["state"] = "rest"
			c["t"] = 0.0
			stats["landed"] = int(stats["landed"]) + 1
	if b.size != Vector3.ZERO:
		if nxt.x - rr < b.position.x and vel.x < 0.0 or nxt.x + rr > b.end.x and vel.x > 0.0:
			vel.x = -vel.x * Tuning.JUICE_DIGIT_BOUNCE
	c["pos"] = nxt
	c["vel"] = vel
	c["ang"] = float(c["ang"]) + float(c["spin"]) * delta


## Луч от центра вниз-по-ходу на rr: только статика (пол, стены, CSG); куклы, оружие и пропсы пропускаются.
func _ground(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, rr: float) -> Dictionary:
	if space == null:
		return {}
	var d := to - from
	var reach := to + (d.normalized() * rr if d.length() > 1e-5 else Vector3.DOWN * rr)
	if d.y <= 0.0:
		reach = Vector3(reach.x, minf(reach.y, to.y - rr), reach.z)
	var q := PhysicsRayQueryParameters3D.create(from, reach)
	q.collide_with_areas = false
	var ex: Array[RID] = []
	for i in range(4):
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r.is_empty():
			return {}
		var col: Object = r.get("collider")
		if col is RigidBody3D or col is CharacterBody3D or col is AnimatableBody3D:
			ex.append(r["rid"])
			continue
		return r
	return {}


func _bounds() -> AABB:
	if arena == null or not is_instance_valid(arena):
		arena = get_tree().get_first_node_in_group("arena") if is_inside_tree() else null
	if arena != null and arena.has_method("bounds"):
		var v: Variant = arena.call("bounds")
		if v is AABB:
			return v
	return AABB()


func _apply(c: Dictionary) -> void:
	var root := c["root"] as Node3D
	var k := float(c["k"])
	var st := String(c["state"])
	var t := float(c["t"])
	if st == "fly" and t < POP_S:
		k *= lerpf(0.3, 1.0, t / POP_S)
	elif st == "sink":
		k *= clampf(1.0 - t / SINK_S, 0.0, 1.0)
	root.global_transform = Transform3D(Basis(Vector3.BACK, float(c["ang"])).scaled(Vector3.ONE * maxf(k, 1e-4)), c["pos"])
