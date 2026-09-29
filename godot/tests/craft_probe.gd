## Проба деталей крафта и крафтового оружия (docs/plan-demo/BODY_CRAFT.md §1, §4) — headless, --fixed-fps 60:
##   godot --headless --path . --fixed-fps 60 res://tests/craft_probe.tscn -- "layout=/abs/craft_layout.json"
## Аргументы одной строкой k=v,k=v: layout= — куда записать раскладку для контакт-рендера (tools/blender/craft_parts.py --render),
## only=<preset> — мах только этим пресетом. Отчёт — tests/craft_probe_report.json, выход 0/1.
## Проверки (checks[].id):
##   part_<id>_*     — каждая деталь PARTS: PartDef валиден, сцена грузится (корень RigidBody3D), есть Socket, у Anchor_* корректные
##                     accepts (виды PartDef.KINDS) / joint_group (группа Tuning.MUSCLE_GROUPS) / rest_deg / mirror и −Y в плоскости XY,
##                     масса сцены = PartDef.mass, есть коллизии Shape* и Mesh, attach и энергия по правилам BODY_CRAFT/CONCEPT_V2 §6;
##   preset_<id>_*   — пресет data/body/weapons: validate() пуст, CraftedWeapon собрался без ошибок, масса / ЦМ / длина правдоподобны;
##   differ_*        — mallet / hammer / heavy_hammer / long_hammer / flail различаются массой, ЦМ от хвата и инерцией (таблица), и
##                     порядок физический: тяжелее головка — дальше ЦМ и больше инерция, длиннее рукоять — больше инерция;
##   floor_<id>_*    — все пресеты падают на пол и лежат: через 6 с скорость ≈ 0, ничего не под полом, цепь цела;
##   flail_*         — кистень за неподвижную рукоять, цепь вверх: цепь падает и болтается (шар уходит ниже хвата), шарниры не рвутся,
##                     скорости ограничены, цепь не переставляется физикой (teleports);
##   swing_<id>_*    — мах: кукла scenes/doll/doll.tscn держит оружие левой кистью (WeaponPickup.attach, оружие продолжает руку),
##                     торс закреплён (стенд), рука от плеча до кисти сварена в рычаг, плечо ведёт «мышца» с ограничением скорости
##                     (ω ≤ SWING_W, момент ≤ SWING_TMAX) из 60° над горизонтом по часовой стрелке; манекен (та же кукла, руки вниз)
##                     стоит так, что дуга центра головки проходит через его голову. Первый удар оружием по манекену: вид weapon,
##                     атакующий — держащий; печатается энергия бьющего тела перед ударом, скорость, урон и урон без MASS_CAP;
##   swing_energy_*  — пиковая энергия удара тяжёлого и длинного молота выше, чем у обычного.
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
const PARTS := ["handle_short", "handle_long", "head_mallet", "head_hammer", "head_mace_ball", "blade_sword", "blade_axe", "hook",
	"mod_nails", "mod_iron_plate", "chain_segment", "metal_forearm", "iron_ball_fist", "extra_joint", "metal_head", "shield_plate"]
const PRESETS := ["mallet", "hammer", "spiked_hammer", "heavy_hammer", "long_hammer", "flail", "sword", "axe", "concept_hammer"]
const COMPARE := ["mallet", "hammer", "heavy_hammer", "long_hammer", "flail"]
const FIXED_KINDS := ["handle", "weapon_head", "mod", "plate"]
const WEAPON_KINDS := ["handle", "weapon_head", "mod"]
## Энергия деталей тела по CONCEPT_V2.md §6 (Heavy Arm 18, Additional Joint 5, Metal Head 20, Shield 12; цепь на теле ~8).
const ENERGY := {"metal_forearm": 18, "extra_joint": 5, "metal_head": 20, "shield_plate": 12, "chain_segment": 8}
const FLOOR_S := 6.0
const HANG_S := 4.0
# --- стенд маха ---
const SHOULDER := Vector3(0.22, 1.43, 0.0)   # плечо L куклы v3 (x ±0.22, y 1.43)
const DUMMY_HEAD_Y := 1.625                   # центр головы стоящей куклы
const ARM_TO_GRIP := 0.60                     # плечо → точка хвата кисти (плечо 1.43 → запястье 0.86 → +0.03)
const ARM_DEG := 150.0                        # плечо L (measured): рука вверх-вбок, 60° над горизонтом
const SWING_W := 6.0                          # рад/с: мышца ограничена скоростью — лёгкое и тяжёлое оружие выходят на одну ω
const SWING_TMAX := 200.0                     # Н·м: момент «мышцы» маха
const SWING_KD := 300.0                       # Н·м·с/рад: жёсткость привода по скорости
const HOLD_KP := 400.0                        # удержание руки до маха
const HOLD_KD := 60.0
const ATTACH_T := 1.0                         # с: оружие в руку после spawn grace манекена (0.7 с) и опускания его рук
const SWING_T := 1.35                        # 0.35 с после хвата: оружие успокаивается в руке
const FLAIL_SWING_T := 1.05                  # кистень — сразу: цепь ещё вытянута вдоль рукояти (замах после раскрутки)
## Кистень раскручивают: плечо не проворачивается на 360° (лимит сустава −25…170°), поэтому раскрутка задаётся импульсом —
## в начале маха рука, рукоять и звенья получают скорости жёсткого вращения вокруг плеча с ω = −SWING_W, дальше цепь свободна.
const SWING_TIMEOUT := 1.3
const AFTER_HIT_S := 0.4
const FLAIL_FRACS := [0.95, 0.88, 0.8]        # кистень: цепь в махе отстаёт — манекен на доле полного вылета, 3 попытки

var cfg := {"layout": "", "only": ""}
var report := {"ok": true, "checks": [], "parts": {}, "presets": {}}
var stats := {}          # preset → сводка CraftedWeapon + reach + раскладка
var phase := "floor"
var t := 0.0
var world: Node3D
var floor_w := {}        # preset → CraftedWeapon
var floor_track := {}
var hang_w: CraftedWeapon
var hang_track := {}
var swing_queue: Array = []
var sw := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2:
				cfg[p[0]] = p[1]
	print("=== CRAFT PROBE (MASS_CAP %.1f kg, g %.1f) ===" % [Tuning.MASS_CAP, ProjectSettings.get_setting("physics/3d/default_gravity")])
	_check_parts()
	_static_presets()
	_start_floor()


func _check(id: String, ok: bool, what: String, value: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "what": what, "value": value})
	if not ok:
		report["ok"] = false
		print("  FAIL %s — %s (%s)" % [id, what, str(value)])


# --- детали ---

func _check_parts() -> void:
	print("\n--- детали ---")
	print("  %-15s %-11s %5s %3s %-5s %5s %5s %6s  %s" % ["id", "kind", "kg", "E", "att", "×wpn", "tris", "shapes", "anchors"])
	for id in PARTS:
		var def := BodyBlueprint.part_def(id)
		if def == null:
			_check("part_%s_def" % id, false, "PartDef exists")
			continue
		_check("part_%s_def" % id, def.is_valid(), "PartDef valid (id, scene, kind, mass > 0)")
		var inst := def.scene.instantiate()
		var rb := inst as RigidBody3D
		_check("part_%s_loads" % id, rb != null, "scene root is RigidBody3D")
		if rb == null:
			inst.free()
			continue
		var sock := rb.get_node_or_null("Socket")
		_check("part_%s_socket" % id, sock is Marker3D, "has Marker3D Socket")
		var shapes := 0
		var has_mesh := false
		var anchors: Array = []
		var bad: Array = []
		for c in rb.get_children():
			if c is CollisionShape3D and String(c.name).begins_with("Shape"):
				shapes += 1
			elif String(c.name) == "Mesh":
				has_mesh = true
			elif c is Marker3D and String(c.name).begins_with("Anchor_"):
				anchors.append(String(c.name))
				var acc: Variant = c.get_meta("accepts", null)
				var jg: Variant = c.get_meta("joint_group", null)
				var rd: Variant = c.get_meta("rest_deg", null)
				var mi: Variant = c.get_meta("mirror", null)
				if not (acc is PackedStringArray) or (acc as PackedStringArray).is_empty():
					bad.append("%s.accepts" % c.name)
				else:
					for k in acc:
						if not PartDef.KINDS.has(k):
							bad.append("%s.accepts[%s]" % [c.name, k])
				if not (jg is String) or not Tuning.MUSCLE_GROUPS.has(jg):
					bad.append("%s.joint_group" % c.name)
				if not (rd is float):
					bad.append("%s.rest_deg" % c.name)
				if not (mi is bool):
					bad.append("%s.mirror" % c.name)
				var down: Vector3 = (c as Marker3D).transform.basis * Vector3.DOWN
				if absf(down.z) > 1e-4 or absf(down.length() - 1.0) > 1e-3:
					bad.append("%s −Y не в плоскости XY" % c.name)
		_check("part_%s_anchors" % id, bad.is_empty(), "Anchor_* metadata accepts/joint_group/rest_deg/mirror", bad)
		_check("part_%s_mass" % id, absf(rb.mass - def.mass) < 1e-4, "scene mass == PartDef.mass", [rb.mass, def.mass])
		_check("part_%s_shapes" % id, shapes > 0 and has_mesh, "collision Shape* and Mesh present", shapes)
		var want_attach := "fixed" if FIXED_KINDS.has(def.kind) else "joint"
		_check("part_%s_attach" % id, def.attach == want_attach, "attach %s for kind %s" % [want_attach, def.kind], def.attach)
		var want_e: int = ENERGY.get(id, 0 if WEAPON_KINDS.has(def.kind) else -1)
		_check("part_%s_energy" % id, want_e < 0 or def.energy == want_e, "energy per CONCEPT_V2 §6", [def.energy, want_e])
		var tris := _tris(rb)
		report["parts"][id] = {"id": id, "title": def.title, "kind": def.kind, "mass": def.mass, "energy": def.energy, "attach": def.attach,
			"weapon_mult": def.weapon_mult, "body_mult": def.body_mult, "tris": tris, "glb": _glb_of(rb.get_node_or_null("Mesh")),
			"anchors": anchors, "shapes": shapes}
		print("  %-15s %-11s %5.2f %3d %-5s %5.2f %5d %6d  %s" % [id, def.kind, def.mass, def.energy, def.attach, def.weapon_mult, tris, shapes,
			", ".join(anchors)])
		inst.free()


func _tris(n: Node) -> int:
	var total := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			total += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for c in n.get_children():
		total += _tris(c)
	return total


func _glb_of(n: Node) -> String:
	if n == null:
		return ""
	return n.scene_file_path.get_file().get_basename()


static func _xf(t3: Transform3D) -> Array:
	var b := t3.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t3.origin.x, t3.origin.y, t3.origin.z]


# --- пресеты: сборка, таблица ---

func _static_presets() -> void:
	print("\n--- пресеты (CraftedWeapon, хват — начало координат, оружие вдоль +X) ---")
	print("  %-15s %6s %6s %8s %7s %8s %6s %5s %6s  %s" % ["preset", "mass", "rigid", "ЦМ→хват", "ЦМ_x", "I_хват", "длина", "×урон", "тел", "досяг"])
	var holder := Node3D.new()
	holder.name = "StaticHolder"
	add_child(holder)
	var k := 0
	for id in PRESETS:
		var bp := CraftedWeapon.preset(id)
		if bp == null:
			_check("preset_%s_exists" % id, false, "data/body/weapons/%s.tres" % id)
			continue
		var errs := bp.validate()
		var w := CraftedWeapon.create(bp)
		holder.add_child(w)
		w.global_position = Vector3(100.0 + 5.0 * k, 50.0, 0.0)
		k += 1
		var s := w.summary()
		# досягаемость: центр самой дальней детали (для кистеня — шар в выпрямленной цепи)
		var reach := 0.0
		var rest: Array = []
		for uid in w.parts_info:
			var info: Dictionary = w.parts_info[uid]
			reach = maxf(reach, (info["centre"] as Vector3).length())
			rest.append({"glb": _glb_of(info["mesh"]), "xf": _xf(info["rest"])})
		s["reach"] = reach
		s["rest"] = rest
		s["title"] = bp.title
		stats[id] = s
		_check("preset_%s_valid" % id, errs.is_empty() and w.build_errors.is_empty(), "validate() empty and built", [errs, w.build_errors])
		var plaus: bool = s["mass"] > 1.0 and s["mass"] < 8.0 and s["length"] > 0.4 and s["length"] < 2.2 \
			and s["com_from_grip"] > 0.05 and s["com_from_grip"] < s["length"] and s["inertia_grip"] > 0.0
		_check("preset_%s_plausible" % id, plaus, "mass 1–8 kg, length 0.4–2.2 m, 0.05 < ЦМ < length, I > 0",
			[snappedf(s["mass"], 0.01), snappedf(s["length"], 0.01), snappedf(s["com_from_grip"], 0.001)])
		print("  %-15s %6.2f %6.2f %8.3f %7.3f %8.3f %6.2f %5.2f %6d  %.2f" % [id, s["mass"], s["rigid_mass"], s["com_from_grip"], s["com_x"],
			s["inertia_grip"], s["length"], s["damage_mult"], s["bodies"], reach])
		w.queue_free()
	holder.queue_free()
	# различия и физический порядок
	for i in COMPARE.size():
		for j in range(i + 1, COMPARE.size()):
			var a: Dictionary = stats.get(COMPARE[i], {})
			var b: Dictionary = stats.get(COMPARE[j], {})
			if a.is_empty() or b.is_empty():
				continue
			var dm := absf(float(a["mass"]) - float(b["mass"]))
			var dc := absf(float(a["com_from_grip"]) - float(b["com_from_grip"]))
			var di := absf(float(a["inertia_grip"]) - float(b["inertia_grip"])) / maxf(float(a["inertia_grip"]), float(b["inertia_grip"]))
			_check("differ_%s_%s" % [COMPARE[i], COMPARE[j]], dm > 0.1 and dc > 0.01 and di > 0.05,
				"mass Δ > 0.1 kg, ЦМ Δ > 1 cm, I Δ > 5 %", [snappedf(dm, 0.01), snappedf(dc, 0.001), snappedf(di, 0.01)])
	if stats.has("mallet") and stats.has("hammer") and stats.has("heavy_hammer") and stats.has("long_hammer"):
		_check("differ_order_head", stats["mallet"]["inertia_grip"] < stats["hammer"]["inertia_grip"] and stats["hammer"]["inertia_grip"] < stats["heavy_hammer"]["inertia_grip"]
			and stats["mallet"]["com_from_grip"] < stats["hammer"]["com_from_grip"] and stats["hammer"]["com_from_grip"] < stats["heavy_hammer"]["com_from_grip"],
			"heavier head → ЦМ дальше от хвата и инерция больше (киянка < молот < тяжёлый)")
		_check("differ_order_handle", stats["long_hammer"]["inertia_grip"] > 2.0 * stats["hammer"]["inertia_grip"]
			and stats["long_hammer"]["com_from_grip"] > stats["hammer"]["com_from_grip"] + 0.3,
			"long handle → ЦМ на ~0.5 м дальше, инерция больше вдвое+")


# --- пол ---

func _add_floor(parent: Node3D, width: float, x0: float = 0.0) -> void:
	var fb := StaticBody3D.new()
	fb.name = "Floor"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 1.0, 6.0)
	cs.shape = bs
	fb.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	fb.physics_material_override = pm
	parent.add_child(fb)
	fb.position = Vector3(x0, -0.5, 0.0)


func _new_world() -> void:
	if world != null:
		remove_child(world)
		world.queue_free()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	t = 0.0


func _start_floor() -> void:
	_new_world()
	_add_floor(world, 80.0, 15.0)
	var x := 0.0
	for id in PRESETS:
		if not stats.has(id):
			continue
		var w := CraftedWeapon.spawn_preset(id, world, Vector3(x, 0.4, 0.0), 0.0)
		floor_w[id] = w
		floor_track[id] = {"max_sep": 0.0, "pos_1s": Vector3.ZERO}
		x += float(stats[id]["length"]) + 1.2
	phase = "floor"


func _lowest_y(w: CraftedWeapon) -> float:
	var lo := INF
	for body in w.bodies():
		for c in (body as Node).get_children():
			if c is CollisionShape3D:
				for corner in CraftedWeapon._shape_corners(c):
					lo = minf(lo, ((body as RigidBody3D).global_transform * corner).y)
	return lo


func _tick_floor(delta: float) -> void:
	t += delta
	for id in floor_w:
		var w: CraftedWeapon = floor_w[id]
		floor_track[id]["max_sep"] = maxf(float(floor_track[id]["max_sep"]), w.joint_separation())
		if not floor_track[id].has("p1") and t >= FLOOR_S - 1.0:
			floor_track[id]["p1"] = true
			floor_track[id]["pos_1s"] = w.global_position
	if t < FLOOR_S:
		return
	print("\n--- пол: %.0f с лёжа ---" % FLOOR_S)
	for id in floor_w:
		var w: CraftedWeapon = floor_w[id]
		var vmax := 0.0
		var wmax := 0.0
		for body in w.bodies():
			vmax = maxf(vmax, (body as RigidBody3D).linear_velocity.length())
			wmax = maxf(wmax, absf((body as RigidBody3D).angular_velocity.z))
		var drift := w.global_position.distance_to(floor_track[id]["pos_1s"])
		var lo := _lowest_y(w)
		var sep := float(floor_track[id]["max_sep"])
		print("  %-15s v %.3f м/с  ω %.3f рад/с  дрейф за 1 с %.4f м  низ %.3f м  разрыв цепи %.4f м" % [id, vmax, wmax, drift, lo, sep])
		_check("floor_%s_rest" % id, vmax < 0.05 and wmax < 0.3 and drift < 0.01, "lies still: v < 0.05, ω < 0.3, drift < 1 cm over 1 s",
			[snappedf(vmax, 0.001), snappedf(wmax, 0.001), snappedf(drift, 0.0001)])
		_check("floor_%s_above" % id, lo > -0.03, "nothing sinks under the floor (lowest shape point > −3 cm)", snappedf(lo, 0.001))
		if w.links.size() > 0:
			_check("floor_%s_chain" % id, sep < 0.03, "chain joints hold (max separation < 3 cm)", snappedf(sep, 0.0001))
		if id == "flail":
			var lying: Array = []
			for uid in w.parts_info:
				var info: Dictionary = w.parts_info[uid]
				var gx: Transform3D = (info["body"] as RigidBody3D).global_transform * (info["local"] as Transform3D)
				gx.origin.x -= w.global_position.x
				lying.append({"glb": _glb_of(info["mesh"]), "xf": _xf(gx)})
			stats[id]["lying"] = lying
		report["presets"][id] = {"floor": {"v": vmax, "w": wmax, "drift": drift, "lowest": lo, "chain_sep": sep}}
	floor_w.clear()
	_start_hang()


# --- кистень на неподвижной рукояти ---

func _start_hang() -> void:
	_new_world()
	if not stats.has("flail"):
		_start_swings()
		return
	# рукоять под 60° вверх, цепь выпрямлена по ней (строго вертикальная цепь — неустойчивое равновесие, стояла бы вечно)
	hang_w = CraftedWeapon.spawn_preset("flail", world, Vector3(0.0, 2.8, 0.0), 60.0)
	hang_w.freeze = true
	hang_track = {"min_rel_y": INF, "max_sep": 0.0, "max_v": 0.0, "teleports0": -1, "angle_min": INF, "angle_max": -INF}
	phase = "hang"


func _tick_hang(delta: float) -> void:
	t += delta
	if int(hang_track["teleports0"]) < 0 and t >= 0.1:
		hang_track["teleports0"] = hang_w.teleports   # после спавна и заморозки — дальше только физика
	var ball: RigidBody3D = hang_w.links.back()
	var grip := hang_w.grip_global()
	var bc := ball.to_global(ball.center_of_mass)
	hang_track["min_rel_y"] = minf(float(hang_track["min_rel_y"]), bc.y - grip.y)
	hang_track["max_sep"] = maxf(float(hang_track["max_sep"]), hang_w.joint_separation())
	for l in hang_w.links:
		hang_track["max_v"] = maxf(float(hang_track["max_v"]), (l as RigidBody3D).linear_velocity.length())
	var ang := rad_to_deg(wrapf(ball.global_rotation.z - hang_w.global_rotation.z, -PI, PI))
	hang_track["angle_min"] = minf(float(hang_track["angle_min"]), ang)
	hang_track["angle_max"] = maxf(float(hang_track["angle_max"]), ang)
	if t < HANG_S:
		return
	var tp := hang_w.teleports - int(hang_track["teleports0"])
	print("\n--- кистень на неподвижной рукояти, %.0f с ---" % HANG_S)
	print("  шар ниже хвата на %.2f м, угол последнего звена к рукояти %.0f°…%.0f°, разрыв шарниров ≤ %.4f м, v звеньев ≤ %.2f м/с, телепортов цепи %d" %
		[-float(hang_track["min_rel_y"]), hang_track["angle_min"], hang_track["angle_max"], hang_track["max_sep"], hang_track["max_v"], tp])
	_check("flail_swings", float(hang_track["min_rel_y"]) < -0.5, "chain falls and dangles: ball goes > 0.5 m below the grip", snappedf(float(hang_track["min_rel_y"]), 0.01))
	_check("flail_intact", float(hang_track["max_sep"]) < 0.03 and float(hang_track["max_v"]) < 15.0,
		"no blow-up: joint separation < 3 cm, link speed < 15 m/s", [snappedf(float(hang_track["max_sep"]), 0.0001), snappedf(float(hang_track["max_v"]), 0.01)])
	_check("flail_no_teleport", tp == 0, "physics steps do not re-place the chain (no teleports after spawn)", tp)
	report["presets"]["flail"]["hang"] = hang_track.duplicate()
	_start_swings()


# --- мах ---

func _start_swings() -> void:
	swing_queue.clear()
	for id in PRESETS:
		if stats.has(id) and (cfg["only"] == "" or cfg["only"] == id):
			swing_queue.append([id, 0])
	print("\n--- мах: стенд (торс закреплён, рука-рычаг, ω ≤ %.1f рад/с, τ ≤ %.0f Н·м), манекен — doll.tscn ---" % [SWING_W, SWING_TMAX])
	_next_swing()


func _next_swing() -> void:
	if swing_queue.is_empty():
		_finish()
		return
	var e: Array = swing_queue.pop_front()
	_start_swing(String(e[0]), int(e[1]))


func _spawn_doll(nm: String, idx: int, pos: Vector3) -> Doll:
	var d: Doll = DollScene.instantiate()
	d.name = nm
	d.player_index = idx
	d.external_input = true
	world.add_child(d)
	d.position = pos
	var c := DollCombat.new()
	c.name = "DollCombat"
	d.add_child(c)
	return d


func _start_swing(id: String, attempt: int) -> void:
	_new_world()
	_add_floor(world, 20.0, 1.0)
	var r := ARM_TO_GRIP + float(stats[id]["reach"])
	var xb: float
	if id == "flail":
		xb = SHOULDER.x + float(FLAIL_FRACS[attempt]) * r
	else:
		xb = SHOULDER.x + sqrt(maxf(r * r - pow(DUMMY_HEAD_Y - SHOULDER.y, 2.0), 0.09))
	var a := _spawn_doll("Attacker", 0, Vector3.ZERO)
	var b := _spawn_doll("Dummy", 1, Vector3(xb, 0.0, 0.0))
	sw = {"id": id, "attempt": attempt, "xb": xb, "a": a, "b": b, "stage": "pose", "hits": [], "ke": {}, "weapon": null,
		"pickup": null, "theta0": 0.0, "t0": -1.0, "hit_t": -1.0, "ticks": 0, "w_max": 0.0}
	b.damaged.connect(_on_dummy_hit)
	phase = "swing"


## Поворот дистальной цепи сустава jn в measured-угол target_deg вокруг точки сустава (как Doll._snap_to_pose).
func _snap(d: Doll, jn: String, target_deg: float, bodies: Array) -> void:
	var j: Generic6DOFJoint3D = d.joints[jn]
	var pa := j.get_node(j.node_a) as RigidBody3D
	var pb := j.get_node(j.node_b) as RigidBody3D
	var cur := wrapf(pb.global_rotation.z - pa.global_rotation.z, -PI, PI)
	var delta := wrapf(deg_to_rad(target_deg) - cur, -PI, PI)
	var pivot := j.global_position
	var rot := Basis(Vector3(0, 0, 1), delta)
	for n in bodies:
		var rb: RigidBody3D = d.parts[n]
		var tr := rb.global_transform
		rb.global_transform = Transform3D(rot * tr.basis, pivot + rot * (tr.origin - pivot))
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO


func _weld(p: RigidBody3D, q: RigidBody3D, at: Vector3) -> Generic6DOFJoint3D:
	var j := Generic6DOFJoint3D.new()
	j.name = "ArmWeld"
	world.add_child(j)
	j.global_transform = Transform3D(Basis.IDENTITY, at)
	j.exclude_nodes_from_collision = true
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
		j.set("angular_limit_%s/enabled" % ax, true)
		j.set("angular_limit_%s/upper_angle" % ax, 0.0)
		j.set("angular_limit_%s/lower_angle" % ax, 0.0)
	j.node_a = j.get_path_to(p)
	j.node_b = j.get_path_to(q)
	return j


## «Мышца» маха/удержания: угловое ускорение α = τ / I_рычага вокруг плеча раздаётся ВСЕМ телам жёсткого рычага (плечо, предплечье,
## кисть, жёсткая часть оружия): сила m·(α × r) в ЦМ и момент I·α — суммарный момент вокруг плеча ровно τ (≤ SWING_TMAX).
## Момент на одно плечо тонет в цепочке суставов Jolt (кисть 0.5 кг между плечом и 4–6 кг оружия): мах выходил втрое медленнее
## заданного и сравнивал бы решатель, а не оружие. Звенья цепи не ведутся — они болтаются сами. Возвращает I_рычага.
func _drive(bodies: Array, pivot: Vector3, tau: float) -> float:
	var itot := 0.0
	var data: Array = []
	for rb in bodies:
		var st := PhysicsServer3D.body_get_direct_state((rb as RigidBody3D).get_rid())
		var inv := st.inverse_inertia.z
		var iz := 1.0 / inv if inv > 1e-9 else 0.0
		var r: Vector3 = (rb as RigidBody3D).global_transform * st.center_of_mass_local - pivot
		r.z = 0.0
		itot += iz + (rb as RigidBody3D).mass * r.length_squared()
		data.append([rb, iz, r])
	var alpha := tau / maxf(itot, 1e-3)
	for d in data:
		var rb: RigidBody3D = d[0]
		rb.apply_torque(Vector3(0, 0, float(d[1]) * alpha))
		rb.apply_central_force(rb.mass * Vector3(0, 0, alpha).cross(d[2]))
	return itot


func _lever(a: Doll) -> Array:
	var out: Array = [a.parts["UpperArm_L"], a.parts["LowerArm_L"], a.parts["Hand_L"]]
	if sw.get("weapon") != null:
		out.append(sw["weapon"])
	return out


func _arm_muscles_off(a: Doll) -> void:
	for jn in ["Shoulder_L", "Elbow_L", "Wrist_L"]:
		a.set_muscle_joint(jn, 0.0, 0.0)


func _tick_swing(delta: float) -> void:
	t += delta
	var a: Doll = sw["a"]
	var b: Doll = sw["b"]
	var upper: RigidBody3D = a.parts["UpperArm_L"]
	match String(sw["stage"]):
		"pose":
			a.torso().freeze = true
			a.set_pose({"Shoulder_L": ARM_DEG, "Elbow_L": 0.0, "Wrist_L": 0.0})
			_snap(a, "Elbow_L", 0.0, ["LowerArm_L", "Hand_L"])
			_snap(a, "Wrist_L", 0.0, ["Hand_L"])
			_snap(a, "Shoulder_L", ARM_DEG, ["UpperArm_L", "LowerArm_L", "Hand_L"])
			_weld(upper, a.parts["Hand_L"], (a.parts["LowerArm_L"] as RigidBody3D).global_position)
			_arm_muscles_off(a)
			b.set_pose({"Shoulder": 8.0})
			_snap(b, "Shoulder_L", 8.0, ["UpperArm_L", "LowerArm_L", "Hand_L"])
			_snap(b, "Shoulder_R", -8.0, ["UpperArm_R", "LowerArm_R", "Hand_R"])
			sw["theta0"] = upper.global_rotation.z
			sw["pivot"] = (a.joints["Shoulder_L"] as Node3D).global_position
			sw["stage"] = "hold"
		"hold", "attached":
			if cfg.get("debug", "") == "1" and sw["stage"] == "attached":
				var w0: CraftedWeapon = sw["weapon"]
				var ls: Array = []
				for l in w0.links:
					ls.append("%s p%s v%.2f" % [(l as Node).name, str((l as Node3D).global_position.snapped(Vector3.ONE * 0.01)), (l as RigidBody3D).linear_velocity.length()])
				print("    dbg att t %.3f hold %.4f sep %.4f root %s v %.2f tp %d | %s" % [t, (sw["pickup"] as WeaponPickup).hold_distance("Hand_L"), w0.joint_separation(),
					str(w0.global_position.snapped(Vector3.ONE * 0.01)), w0.linear_velocity.length(), w0.teleports, " ".join(ls)])
			var err := wrapf(float(sw["theta0"]) - upper.global_rotation.z, -PI, PI)
			_drive(_lever(a), sw["pivot"], clampf(HOLD_KP * err - HOLD_KD * upper.angular_velocity.z, -SWING_TMAX, SWING_TMAX))
			if sw["stage"] == "hold" and t >= ATTACH_T:
				var pickup := WeaponPickup.new()
				pickup.name = "WeaponPickup"
				pickup.auto_pickup = false
				a.add_child(pickup)
				var h := pickup.hand("Hand_L")
				# attach ставит +X оружия под углом φ_кисти − 90° + hold (Hand_L); нужно вдоль руки: φ_плеча − 90° → hold = φ_плеча − φ_кисти
				pickup.hold_angle_deg = wrapf(rad_to_deg(upper.global_rotation.z - h.global_rotation.z), -180.0, 180.0)
				var grip := pickup.hand_grip_global("Hand_L")
				var w := CraftedWeapon.spawn_preset(String(sw["id"]), world, grip, 0.0)
				w.global_position += grip - w.grip_global()
				var ok := pickup.attach("Hand_L", w)
				_arm_muscles_off(a)
				sw["weapon"] = w
				sw["pickup"] = pickup
				sw["attach_ok"] = ok
				sw["stage"] = "attached"
			elif sw["stage"] == "attached" and t >= (FLAIL_SWING_T if sw["id"] == "flail" else SWING_T):
				var w: CraftedWeapon = sw["weapon"]
				var pk: WeaponPickup = sw["pickup"]
				sw["hold_dist"] = pk.hold_distance("Hand_L")
				sw["held"] = w.is_held()
				var dir := Vector3.RIGHT.rotated(Vector3(0, 0, 1), w.global_rotation.z)
				sw["aim_deg"] = rad_to_deg(atan2(dir.y, dir.x))
				sw["t0"] = t
				sw["stage"] = "swing"
				if sw["id"] == "flail":
					var pv: Vector3 = sw["pivot"]
					var spin: Array = _lever(a)
					spin.append_array(w.links)
					for body in spin:
						var rb := body as RigidBody3D
						var st := PhysicsServer3D.body_get_direct_state(rb.get_rid())
						var r: Vector3 = rb.global_transform * st.center_of_mass_local - pv
						rb.linear_velocity = Vector3(0, 0, -SWING_W).cross(Vector3(r.x, r.y, 0.0))
						rb.angular_velocity = Vector3(0, 0, -SWING_W)
		"swing", "after":
			var w: CraftedWeapon = sw["weapon"]
			for body in w.bodies():
				var rb := body as RigidBody3D
				var ke := 0.5 * rb.mass * rb.linear_velocity.length_squared() + 0.5 * rb.inertia.z * rb.angular_velocity.z * rb.angular_velocity.z
				var hist: Array = sw["ke"].get(rb, [])
				hist.append(ke)
				if hist.size() > 3:
					hist.pop_front()
				sw["ke"][rb] = hist
			sw["w_max"] = maxf(float(sw["w_max"]), absf(upper.angular_velocity.z))
			if cfg.get("debug", "") == "1":
				var bc := DollCombat.combat_of(b)
				for q in bc._queue:
					print("    dbg queue kind %s speed %.2f mass %.2f striker %s part %s nrm %s pos %s" % [q["kind"], q["speed"], q["mass"], q["striker"], (q["victim_part"] as Node).name, str(q["nrm"]), str(q["pos"])])
				if bc.env_ignored > 0:
					print("    dbg env_ignored %d max %.2f" % [bc.env_ignored, bc.env_ignored_max_speed])
			if cfg.get("debug", "") == "1" and int(Engine.get_physics_frames()) % 3 == 0:
				var far := Vector3.ZERO
				for body in w.bodies():
					for c in (body as Node).get_children():
						if c is CollisionShape3D:
							for corner in CraftedWeapon._shape_corners(c):
								var g: Vector3 = (body as RigidBody3D).global_transform * corner
								if g.distance_to(sw["pivot"]) > far.distance_to(sw["pivot"]):
									far = g
				var hd: RigidBody3D = b.parts["Head"]
				var contacts: Array = []
				for pn in ["Head", "Torso", "Hand_R", "LowerArm_R", "UpperArm_R"]:
					var bp: RigidBody3D = b.parts[pn]
					if bp.contact_monitor:
						for o in bp.get_colliding_bodies():
							contacts.append("%s-%s" % [pn, o.name])
				print("    dbg t %.2f θ %.0f° ω %.2f far %s head %s w %s contacts %s" % [t - float(sw["t0"]), rad_to_deg(upper.global_rotation.z) - 90.0,
					upper.angular_velocity.z, str(far.snapped(Vector3.ONE * 0.01)), str(hd.global_position.snapped(Vector3.ONE * 0.01)),
					str(w.global_position.snapped(Vector3.ONE * 0.01)), str(contacts)])
			if sw["stage"] == "swing":
				var tau := clampf(SWING_KD * (-SWING_W - upper.angular_velocity.z), -SWING_TMAX, SWING_TMAX)
				sw["i_lever"] = _drive(_lever(a), sw["pivot"], tau)
				sw["hold_max"] = maxf(float(sw.get("hold_max", 0.0)), (sw["pickup"] as WeaponPickup).hold_distance("Hand_L"))
				if not _weapon_hit().is_empty():
					sw["hit_t"] = t
					sw["stage"] = "after"
				elif t - float(sw["t0"]) > SWING_TIMEOUT:
					_end_swing()
			elif t - float(sw["hit_t"]) > AFTER_HIT_S:
				_end_swing()


func _weapon_hit() -> Dictionary:
	for h in sw["hits"]:
		if h["kind"] == "weapon":
			return h
	return {}


func _on_dummy_hit(amount: float, attacker: Node, part: String, _position: Vector3, kind: String) -> void:
	if phase != "swing" or sw.is_empty():
		return
	var b: Doll = sw["b"]
	var lh: Dictionary = b.last_hit
	var striker: Object = lh.get("striker", null)
	var rec := {"amount": amount, "kind": kind, "part": part, "attacker": attacker.name if attacker != null else "",
		"by_holder": attacker == sw["a"], "speed": float(lh.get("speed", 0.0)), "combo": float(lh.get("combo_mult", 1.0)),
		"double": bool(lh.get("double_blow", false)), "t": t - float(sw["t0"]), "striker": "", "mass": 0.0, "mult": 1.0, "ke": 0.0}
	if striker is Weapon and is_instance_valid(striker):
		var ws := striker as Weapon
		rec["striker"] = String(ws.name)
		rec["mass"] = ws.mass
		rec["mult"] = ws.damage_mult
		var hist: Array = sw["ke"].get(ws, [])
		for k in hist:
			rec["ke"] = maxf(float(rec["ke"]), float(k))
	elif striker != null and is_instance_valid(striker):
		rec["striker"] = String((striker as Node).name)
	sw["hits"].append(rec)


func _end_swing() -> void:
	var id := String(sw["id"])
	var hit := _weapon_hit()
	if hit.is_empty() and id == "flail" and int(sw["attempt"]) + 1 < FLAIL_FRACS.size():
		print("  %-15s попытка %d (манекен x %.2f): удара оружием нет, двигаю манекен" % [id, int(sw["attempt"]) + 1, float(sw["xb"])])
		swing_queue.push_front([id, int(sw["attempt"]) + 1])
		sw = {}
		_next_swing()
		return
	var res := {"dummy_x": sw["xb"], "attach_ok": sw.get("attach_ok", false), "held": sw.get("held", false),
		"hold_dist": sw.get("hold_dist", -1.0), "hold_max": sw.get("hold_max", -1.0), "aim_deg": sw.get("aim_deg", 0.0), "w_max": sw["w_max"],
		"i_lever": sw.get("i_lever", 0.0), "hits": sw["hits"]}
	_check("swing_%s_attached" % id, bool(res["attach_ok"]) and bool(res["held"]) and float(res["hold_dist"]) >= 0.0 and float(res["hold_dist"]) < 0.05,
		"WeaponPickup.attach holds the crafted weapon (grip–hand < 5 cm at swing start)", snappedf(float(res["hold_dist"]), 0.0001))
	var ok_hit: bool = not hit.is_empty() and hit["kind"] == "weapon" and bool(hit["by_holder"]) and float(hit["amount"]) > 0.0
	_check("swing_%s_hit" % id, ok_hit, "dummy takes a weapon hit (kind weapon, attacker = holder)", hit.get("amount", 0.0))
	if not hit.is_empty():
		var m := float(hit["mass"])
		var tgt := Tuning.HEAD_HIT_MULT if String(hit["part"]).begins_with("Head") else 1.0
		var v_eff := maxf(0.0, float(hit["speed"]) - Tuning.MIN_IMPACT_SPEED)
		res["uncapped"] = m * v_eff * Tuning.DAMAGE_COEF * float(hit["mult"]) * tgt * float(hit["combo"])
		res["capped_formula"] = Damage.compute(m, float(hit["speed"]), 1.0, float(hit["mult"]), float(hit["combo"]), 1.0, tgt)
		res["first"] = hit
		var peak := 0.0
		for h in sw["hits"]:
			if h["kind"] == "weapon":
				peak = maxf(peak, float(h["amount"]))
		res["peak_damage"] = peak
		print("  %-15s удар %4.2f с после начала: %-13s в %-10s v %5.2f м/с  m %.2f кг (в формуле %.2f)  ×%.2f  E %6.1f Дж  урон %5.1f HP (без MASS_CAP %5.1f), пик %5.1f  [манекен x %.2f, ω≤%.1f, I_рыч %.2f, хват ≤ %.3f м]" %
			[id, hit["t"], hit["striker"], hit["part"], hit["speed"], m, minf(m, Tuning.MASS_CAP), hit["mult"], hit["ke"], hit["amount"], res["uncapped"],
			peak, sw["xb"], sw["w_max"], res["i_lever"], res["hold_max"]])
	else:
		print("  %-15s удара оружием нет (удары: %s)" % [id, str(sw["hits"])])
	if not report["presets"].has(id):
		report["presets"][id] = {}
	report["presets"][id]["swing"] = res
	stats[id]["swing"] = res
	sw = {}
	_next_swing()


func _energy_checks() -> void:
	var e := {}
	var dmg := {}
	for id in ["mallet", "hammer", "heavy_hammer", "long_hammer"]:
		var s: Dictionary = stats.get(id, {}).get("swing", {})
		if s.has("first"):
			e[id] = float(s["first"]["ke"])
			dmg[id] = float(s["first"]["amount"])
	if e.has("hammer") and e.has("heavy_hammer"):
		_check("swing_energy_heavy", e["heavy_hammer"] > e["hammer"], "heavy hammer hits with more energy than hammer", [snappedf(e["heavy_hammer"], 0.1), snappedf(e["hammer"], 0.1)])
	if e.has("hammer") and e.has("long_hammer"):
		_check("swing_energy_long", e["long_hammer"] > e["hammer"], "long hammer hits with more energy than hammer", [snappedf(e["long_hammer"], 0.1), snappedf(e["hammer"], 0.1)])
	if e.has("mallet") and e.has("hammer"):
		_check("swing_energy_mallet", e["hammer"] > e["mallet"], "iron head hits with more energy than wooden mallet", [snappedf(e["hammer"], 0.1), snappedf(e["mallet"], 0.1)])


# --- итог ---

func _finish() -> void:
	_energy_checks()
	print("\n--- сводка пресетов (ЦМ и I — жёсткой части от хвата; E — энергия бьющего тела перед первым ударом) ---")
	print("  %-15s %6s %7s %7s %6s %5s %7s %6s %7s %7s  %s" % ["preset", "масса", "ЦМ→х", "I_хват", "длина", "×урон", "E, Дж", "v", "урон", "без кап", "MASS_CAP"])
	for id in PRESETS:
		if not stats.has(id):
			continue
		var s: Dictionary = stats[id]
		var sw_r: Dictionary = s.get("swing", {})
		var f: Dictionary = sw_r.get("first", {})
		var capped := ""
		if not f.is_empty():
			var m := float(f["mass"])
			capped = ("режет %.2f → %.1f кг" % [m, Tuning.MASS_CAP]) if m > Tuning.MASS_CAP else "не режет"
		print("  %-15s %6.2f %7.3f %7.3f %6.2f %5.2f %7.1f %6.2f %7.1f %7.1f  %s" % [id, s["mass"], s["com_from_grip"], s["inertia_grip"], s["length"],
			s["damage_mult"], float(f.get("ke", 0.0)), float(f.get("speed", 0.0)), float(f.get("amount", 0.0)), float(sw_r.get("uncapped", 0.0)), capped])
		var rp: Dictionary = report["presets"].get(id, {})
		for k in ["mass", "rigid_mass", "com_from_grip", "com_x", "inertia_grip", "length", "damage_mult", "bodies", "reach"]:
			rp[k] = s[k]
		report["presets"][id] = rp
	var fails := 0
	for c in report["checks"]:
		if not bool(c["ok"]):
			fails += 1
	print("\n=== craft_probe: %d checks, %d failed → %s ===" % [report["checks"].size(), fails, "OK" if report["ok"] else "FAIL"])
	var f := FileAccess.open(ProjectSettings.globalize_path("res://tests/craft_probe_report.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	if cfg["layout"] != "":
		var presets: Array = []
		for id in PRESETS:
			if not stats.has(id):
				continue
			var s: Dictionary = stats[id]
			var sw_r: Dictionary = s.get("swing", {})
			presets.append({"id": id, "title": s["title"], "rest": s["rest"], "lying": s.get("lying", []),
				"stats": {"mass": s["mass"], "com_from_grip": s["com_from_grip"], "inertia_grip": s["inertia_grip"], "length": s["length"],
					"damage_mult": s["damage_mult"], "damage": float(sw_r.get("first", {}).get("amount", 0.0))}})
		var parts: Array = []
		for id in PARTS:
			if report["parts"].has(id):
				parts.append(report["parts"][id])
		var lf := FileAccess.open(String(cfg["layout"]), FileAccess.WRITE)
		if lf != null:
			lf.store_string(JSON.stringify({"parts": parts, "presets": presets}, " ", false))
			lf.close()
			print("layout → %s" % cfg["layout"])
	get_tree().quit(0 if report["ok"] else 1)


func _physics_process(delta: float) -> void:
	match phase:
		"floor":
			_tick_floor(delta)
		"hang":
			_tick_hang(delta)
		"swing":
			if not sw.is_empty():
				_tick_swing(delta)
