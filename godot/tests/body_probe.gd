## Проба системы сборки тела (docs/plan-demo/BODY_CRAFT.md §1–3): ModularDoll по пресетам data/body/blueprints/*.tres.
## Headless: godot --headless --path . --fixed-fps 60 res://tests/body_probe.tscn        → tests/body_probe_report.json, код выхода 0/1
## Кадр:     godot --path . --resolution 1920x1080 res://tests/body_probe.tscn -- "shot=<путь.png>"   (все пресеты рядом, подписи)
##
## Проверки (всё в одном мире, куклы в 8 м друг от друга, пол y = 0):
##   • пресет: validate() пуст, собирается (тела/суставы по чертежу, energy ≤ бюджета); 5 с покоя без взрыва — скорость частей
##     ≤ MAX_IDLE_SPEED, суставы целы (точки сустава на обоих телах расходятся ≤ MAX_JOINT_GAP), ни одна часть не дальше от торса,
##     чем длина её цепи + CHAIN_SLACK; внешний ввод (1, 0.4) 1.5 с двигает ЦМ вправо ≥ MIN_MOVE; knock_out() → break_apart
##     (суставы сняты, тела целы и конечны); у деталей Foot_3 / Hand_C после DollCombat включён монитор контактов;
##   • human против scenes/doll/doll.tscn: те же имена и порядок тел/суставов, массы, total_mass, формы, дамп, лимиты, трение,
##     группы и поза покоя; кадры сборки (≤ 1 мм); пара со spawn_in_pose = false (одна и та же физика) после 3 с покоя ≤ HUMAN_REST_TOL;
##     пара со спавном в позе — справочно (у Doll._snap_to_pose суставы после спавна расходятся на 7 см, см. modular_doll.gd _snap_pose);
##     одинаковая тяга (ввод);
##   • Match.respawn_doll пересоздаёт ModularDoll с тем же чертежом, подмена scene_file_path меняет пресет (так делает площадка).
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
const PRESETS := {
	"human": "res://scenes/body/modular_doll.tscn",
	"spider": "res://scenes/body/presets/spider.tscn",
	"long_arm": "res://scenes/body/presets/long_arm.tscn",
	"big_arm": "res://scenes/body/presets/big_arm.tscn",
	"legless": "res://scenes/body/presets/legless.tscn",
	"junk": "res://scenes/body/presets/junk.tscn",
	"flail": "res://scenes/body/presets/flail.tscn",
}
const SPACING := 8.0
const IDLE_S := 5.0
const MOVE_S := 1.5
const KO_WAIT_S := 1.0
const HUMAN_REST_S := 3.0
const MAX_IDLE_SPEED := 8.0      # м/с: покой на полу (g = 2) — всё, что быстрее, «взрыв»
const MAX_JOINT_GAP := 0.05      # м: расхождение точки сустава на двух телах (мягкий лимит Jolt под нагрузкой ~мм)
const CHAIN_SLACK := 0.05        # м
const MIN_MOVE := 0.5            # м ЦМ за MOVE_S под вводом (1, 0.4)
const HUMAN_SPAWN_TOL := 0.001   # м
const HUMAN_REST_TOL := 0.02     # м (~2 см, задача)
const MOVE_INPUT := Vector2(1.0, 0.4)

var shot_path := ""
var report_path := "res://tests/body_probe_report.json"
var t := 0.0
var stage := 0
var busy := false
var failures: PackedStringArray = []
var report := {"presets": {}, "human_vs_doll": {}, "respawn": {}}

var ref_doll: Doll                 # scenes/doll/doll.tscn
var ref_mod: ModularDoll           # human
var ns_doll: Doll                  # та же пара со spawn_in_pose = false — регресс «та же сборка → та же физика»
var ns_mod: ModularDoll
var presets: Dictionary = {}       # id -> ModularDoll
var track: Dictionary = {}         # id -> {joints: [[a, b, pa, pb]], chain: {body: len}, max_speed, max_gap, max_reach_over, com0}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "shot":
				shot_path = p[1]
			elif p.size() == 2 and p[0] == "report":
				report_path = p[1]
	_floor(Vector3.ZERO, 120.0)
	if shot_path != "":
		_setup_shot()
		return
	# human-пара: эталон doll.tscn и модульный human
	ref_doll = DollScene.instantiate()
	ref_doll.external_input = true
	ref_doll.position = Vector3(-24.0, 0.0, 0.0)
	add_child(ref_doll)
	ref_mod = _spawn("human", Vector3(-16.0, 0.0, 0.0))
	ns_doll = DollScene.instantiate()
	ns_doll.external_input = true
	ns_doll.spawn_in_pose = false
	ns_doll.position = Vector3(-40.0, 0.0, 0.0)
	add_child(ns_doll)
	ns_mod = (load(PRESETS["human"]) as PackedScene).instantiate() as ModularDoll
	ns_mod.external_input = true
	ns_mod.spawn_in_pose = false
	ns_mod.position = Vector3(-32.0, 0.0, 0.0)
	add_child(ns_mod)
	_compare_human_static()
	# пресеты
	var i := 0
	for id in PRESETS:
		if not ResourceLoader.exists(PRESETS[id]):
			continue
		var d := _spawn(id, Vector3(i * SPACING, 0.0, 0.0))
		presets[id] = d
		_track_init(id, d)
		var combat := DollCombat.new()
		combat.name = "DollCombat"
		d.add_child(combat)
		i += 1


func _spawn(id: String, pos: Vector3) -> ModularDoll:
	var ps: PackedScene = load(PRESETS[id])
	var d := ps.instantiate() as ModularDoll
	d.external_input = true
	d.position = pos
	add_child(d)
	return d


func _fail(msg: String) -> void:
	failures.append(msg)
	push_warning("FAIL: " + msg)


# --- human против doll.tscn ---

func _compare_human_static() -> void:
	var r := {}
	var a := ref_doll
	var b := ref_mod
	r["bodies_same_order"] = a.parts.keys() == b.parts.keys()
	r["joints_same_order"] = a.joints.keys() == b.joints.keys()
	if not r["bodies_same_order"]:
		_fail("human: тела %s ≠ doll %s" % [b.parts.keys(), a.parts.keys()])
	if not r["joints_same_order"]:
		_fail("human: суставы %s ≠ doll %s" % [b.joints.keys(), a.joints.keys()])
	r["total_mass"] = [a.total_mass, b.total_mass]
	if absf(a.total_mass - b.total_mass) > 1e-4:
		_fail("human: total_mass %.3f ≠ %.3f" % [b.total_mass, a.total_mass])
	var max_pos := 0.0
	for pn in a.parts:
		if not b.parts.has(pn):
			continue
		var pa := a.parts[pn] as RigidBody3D
		var pb := b.parts[pn] as RigidBody3D
		if absf(pa.mass - pb.mass) > 1e-5:
			_fail("human: масса %s %.3f ≠ %.3f" % [pn, pb.mass, pa.mass])
		if absf(pa.linear_damp - pb.linear_damp) > 1e-5 or absf(pa.angular_damp - pb.angular_damp) > 1e-5:
			_fail("human: дамп %s" % pn)
		if pa.axis_lock_linear_z != pb.axis_lock_linear_z or pa.continuous_cd != pb.continuous_cd or pa.can_sleep != pb.can_sleep:
			_fail("human: флаги тела %s" % pn)
		var fa := (pa.physics_material_override as PhysicsMaterial)
		var fb := (pb.physics_material_override as PhysicsMaterial)
		if fa == null or fb == null or absf(fa.friction - fb.friction) > 1e-5 or absf(fa.bounce - fb.bounce) > 1e-5:
			_fail("human: материал %s" % pn)
		var sa := _shape_sig(pa)
		var sb := _shape_sig(pb)
		if sa != sb:
			_fail("human: форма %s %s ≠ %s" % [pn, sb, sa])
	# сборка (до позы): кадры тел ModularDoll.assembly против узлов doll.tscn (инстанс вне дерева — _ready не зовётся)
	var tscn := DollScene.instantiate()
	var asm := {}
	for c in tscn.get_children():
		if c is Node3D:
			asm[String(c.name)] = (c as Node3D).transform
	tscn.free()
	for pn in b.assembly:
		if not asm.has(pn):
			continue
		var ta: Transform3D = asm[pn]
		var tb: Transform3D = b.assembly[pn]
		max_pos = maxf(max_pos, ta.origin.distance_to(tb.origin))
		max_pos = maxf(max_pos, (ta.basis.x - tb.basis.x).length() + (ta.basis.y - tb.basis.y).length())
	r["assembly_max_diff_m"] = max_pos
	if max_pos > HUMAN_SPAWN_TOL:
		_fail("human: сборка расходится с doll.tscn на %.4f" % max_pos)
	# спавн в позе: насколько расходятся суставы сразу после _ready (у Doll._snap_to_pose — поворот вокруг узла сустава на месте сборки)
	r["doll_spawn_joint_gap_m"] = snappedf(_spawn_gap(a, asm), 0.0001)
	r["modular_spawn_joint_gap_m"] = snappedf(_spawn_gap(b, b.assembly), 0.0001)
	if float(r["modular_spawn_joint_gap_m"]) > 0.002:
		_fail("human: суставы после спавна в позе расходятся на %.4f м" % r["modular_spawn_joint_gap_m"])
	var pose_a := a.get_pose()
	var pose_b := b.get_pose()
	var max_pose := 0.0
	var max_lim := 0.0
	for jn in a.joints:
		if not b.joints.has(jn):
			continue
		var ja := a.joints[jn] as Generic6DOFJoint3D
		var jb := b.joints[jn] as Generic6DOFJoint3D
		for prop in ["angular_limit_z/lower_angle", "angular_limit_z/upper_angle", "angular_motor_z/force_limit"]:
			max_lim = maxf(max_lim, absf(float(ja.get(prop)) - float(jb.get(prop))))
		if bool(ja.get("angular_motor_z/enabled")) != bool(jb.get("angular_motor_z/enabled")):
			_fail("human: мотор %s" % jn)
		if absf(float(ja.get_meta("friction_factor", 0.0)) - float(jb.get_meta("friction_factor", -1.0))) > 1e-5:
			_fail("human: friction_factor %s" % jn)
		if (ja.get_node(ja.node_a) as Node).name != (jb.get_node(jb.node_a) as Node).name \
				or (ja.get_node(ja.node_b) as Node).name != (jb.get_node(jb.node_b) as Node).name:
			_fail("human: тела сустава %s" % jn)
		if (ja.global_position - a.global_position).distance_to(jb.global_position - b.global_position) > HUMAN_SPAWN_TOL:
			_fail("human: точка сустава %s" % jn)
		max_pose = maxf(max_pose, absf(float(pose_a.get(jn, 0.0)) - float(pose_b.get(jn, 999.0))))
	r["limits_max_diff"] = max_lim
	r["pose_max_diff_deg"] = max_pose
	if max_lim > 1e-4:
		_fail("human: лимиты/трение суставов расходятся на %.5f" % max_lim)
	if max_pose > 1e-3:
		_fail("human: поза покоя расходится на %.4f°" % max_pose)
	report["human_vs_doll"] = r


## Наибольшее расхождение точки сустава на двух телах (asm — кадры тел при сборке, в них Jolt посчитал кадры сустава).
func _spawn_gap(d: Doll, asm: Dictionary) -> float:
	var m := 0.0
	for j in d.joints.values():
		var jj := j as Generic6DOFJoint3D
		var a := jj.get_node(jj.node_a) as RigidBody3D
		var b := jj.get_node(jj.node_b) as RigidBody3D
		var pa: Vector3 = (asm[String(a.name)] as Transform3D).affine_inverse() * jj.position
		var pb: Vector3 = (asm[String(b.name)] as Transform3D).affine_inverse() * jj.position
		m = maxf(m, a.to_global(pa).distance_to(b.to_global(pb)))
	return m


func _shape_sig(b: RigidBody3D) -> String:
	var out := []
	for c in b.get_children():
		if c is CollisionShape3D:
			var s: Shape3D = (c as CollisionShape3D).shape
			var o := (c as Node3D).position
			if s is BoxShape3D:
				out.append("box%s@%s" % [(s as BoxShape3D).size.snappedf(0.0001), o.snappedf(0.0001)])
			elif s is CapsuleShape3D:
				out.append("cap%.4f/%.4f@%s" % [(s as CapsuleShape3D).radius, (s as CapsuleShape3D).height, o.snappedf(0.0001)])
			else:
				out.append(s.get_class())
	return ",".join(out)


func _compare_human_rest() -> void:
	var r: Dictionary = report["human_vs_doll"]
	var ns := _pair_diff(ns_doll, ns_mod)
	var sp := _pair_diff(ref_doll, ref_mod)
	r["rest_%.0fs_no_snap_max_diff_m" % HUMAN_REST_S] = snappedf(ns[0], 0.0001)
	r["rest_%.0fs_spawn_in_pose_max_diff_m" % HUMAN_REST_S] = snappedf(sp[0], 0.0001)
	r["rest_spawn_in_pose_worst_part"] = sp[1]
	if ns[0] > HUMAN_REST_TOL:
		_fail("human: после %.0f с покоя %s расходится с doll.tscn на %.3f м" % [HUMAN_REST_S, ns[1], ns[0]])


## [наибольшее расхождение части относительно корня, м; имя части]
func _pair_diff(a: Doll, b: Doll) -> Array:
	var m := 0.0
	var worst := ""
	for pn in a.parts:
		if not b.parts.has(pn):
			continue
		var la := (a.parts[pn] as Node3D).global_position - a.global_position
		var lb := (b.parts[pn] as Node3D).global_position - b.global_position
		var d := la.distance_to(lb)
		if d > m:
			m = d
			worst = pn
	return [m, worst]


# --- пресеты ---

func _track_init(id: String, d: ModularDoll) -> void:
	var r := {
		"title": d.blueprint.title, "validate": Array(d.blueprint.validate()), "build_errors": Array(d.build_errors),
		"energy": d.blueprint.energy_used(), "budget": d.blueprint.energy_budget, "mass": snappedf(d.total_mass, 0.01),
		"bodies": d.parts.size(), "joints": d.joints.size(), "control": Array(d.control_part_names()),
	}
	report["presets"][id] = r
	if not d.blueprint.validate().is_empty() or not d.build_errors.is_empty():
		_fail("%s: validate %s" % [id, d.blueprint.validate()])
	if d.blueprint.id != id:
		_fail("%s: собран чертёж «%s»" % [id, d.blueprint.id])
	var nodes := d.blueprint.nodes.size()
	var fixed := 0
	for n in d.blueprint.nodes:
		var pd := BodyBlueprint.part_def(String(n["part"]))
		if pd != null and pd.attach == "fixed":
			fixed += 1
	if d.parts.size() != nodes - fixed or d.joints.size() != nodes - fixed - 1:
		_fail("%s: тел %d / суставов %d при %d деталях (%d fixed)" % [id, d.parts.size(), d.joints.size(), nodes, fixed])
	if d.blueprint.energy_used() > d.blueprint.energy_budget:
		_fail("%s: энергия %d > %d" % [id, d.blueprint.energy_used(), d.blueprint.energy_budget])
	for cn in d.control_part_names():
		if not d.parts.has(cn):
			_fail("%s: управляемой части %s нет" % [id, cn])
	# суставы: точка сустава в локале обоих тел — по кадрам СБОРКИ (d.assembly): Jolt считает кадры сустава при входе в дерево, а
	# spawn_in_pose потом поворачивает дистальные тела, узел сустава остаётся на месте сборки; длина цепи от торса по суставам
	var joints: Array = []
	var parent_of := {}
	for j in d.joints.values():
		var jj := j as Generic6DOFJoint3D
		var a := jj.get_node(jj.node_a) as RigidBody3D
		var b := jj.get_node(jj.node_b) as RigidBody3D
		var pa: Vector3 = (d.assembly[String(a.name)] as Transform3D).affine_inverse() * jj.position
		var pb: Vector3 = (d.assembly[String(b.name)] as Transform3D).affine_inverse() * jj.position
		joints.append([a, b, pa, pb, String(jj.name)])
		parent_of[b] = [a, a.to_global(pa)]
	var chain := {}
	var torso := d.torso()
	for b in d.parts.values():
		var clen := 0.0
		var cur := b as RigidBody3D
		var p := cur.global_position
		var guard := 0
		while parent_of.has(cur) and guard < 64:
			var e: Array = parent_of[cur]
			clen += p.distance_to(e[1])
			p = e[1]
			cur = e[0]
			guard += 1
		clen += p.distance_to(torso.global_position)
		chain[b] = clen
	track[id] = {"joints": joints, "chain": chain, "max_speed": 0.0, "max_gap": 0.0, "max_reach_over": -INF, "worst": "", "nan": false}


func _track_tick(id: String, d: ModularDoll) -> void:
	var tr: Dictionary = track[id]
	var torso := d.torso()
	for b in d.parts.values():
		var rb := b as RigidBody3D
		var v := rb.linear_velocity.length()
		if not is_finite(v) or not rb.global_position.is_finite():
			tr["nan"] = true
			continue
		if v > float(tr["max_speed"]):
			tr["max_speed"] = v
			tr["worst"] = String(rb.name)
		var over := rb.global_position.distance_to(torso.global_position) - float(tr["chain"][rb])
		tr["max_reach_over"] = maxf(float(tr["max_reach_over"]), over)
	for e in tr["joints"]:
		var gap := (e[0] as RigidBody3D).to_global(e[2]).distance_to((e[1] as RigidBody3D).to_global(e[3]))
		tr["max_gap"] = maxf(float(tr["max_gap"]), gap)


func _idle_verdict() -> void:
	for id in presets:
		var tr: Dictionary = track[id]
		var r: Dictionary = report["presets"][id]
		r["idle_max_speed"] = snappedf(float(tr["max_speed"]), 0.001)
		r["idle_fastest_part"] = tr["worst"]
		r["idle_max_joint_gap_m"] = snappedf(float(tr["max_gap"]), 0.0001)
		r["idle_max_reach_over_chain_m"] = snappedf(float(tr["max_reach_over"]), 0.0001)
		r["idle_nan"] = tr["nan"]
		var d: ModularDoll = presets[id]
		var hm := 0.0
		for b in d.parts.values():
			hm = maxf(hm, (b as Node3D).global_position.y)
		r["idle_top_y"] = snappedf(hm, 0.01)
		r["idle_torso_y"] = snappedf(d.torso().global_position.y, 0.01)
		if tr["nan"]:
			_fail("%s: NaN в покое" % id)
		if float(tr["max_speed"]) > MAX_IDLE_SPEED:
			_fail("%s: в покое %s разогналась до %.1f м/с" % [id, tr["worst"], tr["max_speed"]])
		if float(tr["max_gap"]) > MAX_JOINT_GAP:
			_fail("%s: сустав разошёлся на %.3f м" % [id, tr["max_gap"]])
		if float(tr["max_reach_over"]) > CHAIN_SLACK:
			_fail("%s: часть ушла от торса дальше цепи на %.3f м" % [id, tr["max_reach_over"]])
		var monitor_ok := true
		for c in d.get_children():
			if c is DollCombat:
				for b in d.parts.values():
					if d.combat_monitored(String((b as Node).name)) and not (b as RigidBody3D).contact_monitor:
						monitor_ok = false
						_fail("%s: у %s нет монитора контактов DollCombat" % [id, (b as Node).name])
		r["combat_monitor_ok"] = monitor_ok


func _start_move() -> void:
	for d in _all_moving():
		(d as Doll).input_vec = MOVE_INPUT
		(d as Doll).set_meta("com0", (d as Doll).centre_of_mass())


func _all_moving() -> Array:
	var out: Array = presets.values()
	out.append(ref_doll)
	out.append(ref_mod)
	return out


func _stop_move() -> void:
	for d in _all_moving():
		(d as Doll).input_vec = Vector2.ZERO
	for id in presets:
		var d: ModularDoll = presets[id]
		var dx := d.centre_of_mass().x - Vector3(d.get_meta("com0")).x
		report["presets"][id]["move_dx_m"] = snappedf(dx, 0.001)
		report["presets"][id]["thrust_accel"] = snappedf(Tuning.MOVE_FORCE_PER_KG * d.thrust_mass() / d.total_mass, 0.01)
		if dx < MIN_MOVE:
			_fail("%s: ввод сдвинул ЦМ только на %.2f м" % [id, dx])
	var da := ref_doll.centre_of_mass().x - Vector3(ref_doll.get_meta("com0")).x
	var db := ref_mod.centre_of_mass().x - Vector3(ref_mod.get_meta("com0")).x
	report["human_vs_doll"]["move_dx_doll_m"] = snappedf(da, 0.001)
	report["human_vs_doll"]["move_dx_modular_m"] = snappedf(db, 0.001)
	if absf(da - db) > 0.05:
		_fail("human: тяга расходится с doll.tscn: %.3f против %.3f м" % [db, da])


func _knock_out_all() -> void:
	for id in presets:
		var d: ModularDoll = presets[id]
		d.set_meta("span0", _span(d))
		d.knock_out()


func _span(d: Doll) -> float:
	var m := 0.0
	for b in d.parts.values():
		m = maxf(m, (b as Node3D).global_position.distance_to(d.torso().global_position))
	return m


func _ko_verdict() -> void:
	for id in presets:
		var d: ModularDoll = presets[id]
		var ok := d.is_broken() and not d.alive and d.joints.is_empty()
		var finite := true
		for b in d.parts.values():
			if not is_instance_valid(b) or not (b as Node3D).global_position.is_finite():
				finite = false
		var span := _span(d)
		report["presets"][id]["ko_broken"] = ok
		report["presets"][id]["ko_span_m"] = [snappedf(float(d.get_meta("span0")), 0.01), snappedf(span, 0.01)]
		var left := 0
		for c in d.get_children():
			if c is Generic6DOFJoint3D:
				left += 1
		if not ok or not finite or left > 0:
			_fail("%s: knock_out → break_apart не сработал (broken %s, суставов в дереве %d, конечны %s)" % [id, d.is_broken(), left, finite])
		if span <= float(d.get_meta("span0")):
			_fail("%s: после KO части не разлетелись (%.2f → %.2f м)" % [id, d.get_meta("span0"), span])


## Match.respawn_doll: тот же чертёж по scene_file_path; подмена scene_file_path — смена пресета (площадка F1–F6).
func _respawn_test() -> void:
	var m := Match.new()
	m.autostart = false
	m.feel_enabled = false
	add_child(m)
	var d: ModularDoll = presets.get("spider")
	var r := {}
	if d == null:
		_fail("respawn: нет spider")
		return
	var nd := m.respawn_doll(d) as ModularDoll
	r["same_preset"] = nd != null and nd.blueprint.id == "spider" and nd.parts.size() == 20 and not nd.is_broken()
	if not r["same_preset"]:
		_fail("respawn: Match.respawn_doll не пересоздал spider")
	if nd != null:
		nd.scene_file_path = PRESETS["junk"]
		var jd := m.respawn_doll(nd) as ModularDoll
		r["switch_to_junk"] = jd != null and jd.blueprint.id == "junk" and jd.parts.has("Hand_R")
		if not r["switch_to_junk"]:
			_fail("respawn: подмена scene_file_path не сменила пресет")
	report["respawn"] = r


func _physics_process(delta: float) -> void:
	if shot_path != "":
		t += delta
		return
	t += delta
	if stage == 0:
		for id in presets:
			_track_tick(id, presets[id])
		if t >= HUMAN_REST_S and not report["human_vs_doll"].has("rest_spawn_in_pose_worst_part"):
			_compare_human_rest()
		if t >= IDLE_S:
			report["human_vs_doll"]["rest_%.0fs_spawn_in_pose_max_diff_m" % IDLE_S] = snappedf(_pair_diff(ref_doll, ref_mod)[0], 0.0001)
			_idle_verdict()
			_start_move()
			stage = 1
	elif stage == 1 and t >= IDLE_S + MOVE_S:
		_stop_move()
		_knock_out_all()
		stage = 2
	elif stage == 2 and t >= IDLE_S + MOVE_S + KO_WAIT_S:
		_ko_verdict()
		_respawn_test()
		_start_playground()
		stage = 3
	elif stage == 3:
		_playground_tick()


# --- площадка scenes/playground_body.tscn: F1–F7 = set_preset(i), Match.register → DollCombat → монитор деталей ---

const PG_FIRST_S := 1.0     # после загрузки площадки (отсчёт матча уже идёт)
const PG_STEP_S := 0.6
var pg: Node = null
var pg_t := 0.0
var pg_step := 0
var pg_order: Array = []


func _start_playground() -> void:
	for c in get_children():
		c.queue_free()
	pg = (load("res://scenes/playground_body.tscn") as PackedScene).instantiate()
	add_child(pg)
	var ps: Array = _pg_presets()
	for i in range(1, ps.size()):
		if ResourceLoader.exists(ps[i][1]):
			pg_order.append(i)
	pg_order.append(0)
	report["playground"] = {"switched": []}


func _pg_presets() -> Array:
	return (pg.get_script() as Script).get_script_constant_map()["PRESETS"]


func _playground_tick() -> void:
	pg_t += get_physics_process_delta_time()
	if pg_t < PG_FIRST_S + pg_step * PG_STEP_S:
		return
	var r: Dictionary = report["playground"]
	if pg_step > 0:
		_playground_check(r, int(pg_order[pg_step - 1]))
	if pg_step >= pg_order.size():
		var p1: Doll = pg.call("p1_doll")
		r["hint"] = String((pg.get_node("UI/Hint") as Label).text).split("\n")[0]
		r["match_registered"] = (pg.get("match_node") as Match).dolls().has(p1)
		if not r["match_registered"]:
			_fail("площадка: P1 не зарегистрирован в Match")
		_finish()
		stage = 4
		return
	pg.call("set_preset", int(pg_order[pg_step]))
	pg_step += 1


func _playground_check(r: Dictionary, i: int) -> void:
	var ps: Array = _pg_presets()
	var id := String(ps[i][0])
	var p1 := pg.call("p1_doll") as ModularDoll
	var ok := p1 != null and p1.blueprint.id == id and not p1.is_broken() and p1.name == "P1"
	var combat := DollCombat.combat_of(p1) if p1 != null else null
	var mon := 0
	var need := 0
	if p1 != null:
		for b in p1.parts.values():
			if p1.combat_monitored(String((b as Node).name)):
				need += 1
				if (b as RigidBody3D).contact_monitor:
					mon += 1
	(r["switched"] as Array).append({"id": id, "ok": ok, "combat": combat != null, "monitored": "%d/%d" % [mon, need],
		"pickup": p1 != null and p1.get_node_or_null("WeaponPickup") != null})
	if not ok or combat == null or mon != need:
		_fail("площадка: пресет %s — ok %s, DollCombat %s, монитор %d/%d" % [id, ok, combat != null, mon, need])


func _finish() -> void:
	report["ok"] = failures.is_empty()
	report["failures"] = Array(failures)
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	print("=== BODY PROBE ===")
	for id in report["presets"]:
		var r: Dictionary = report["presets"][id]
		print("  %-9s energy %3d  mass %5.1f  bodies %2d joints %2d  idle vmax %5.2f gap %.4f reach %+.3f  move %.2f m (a %.1f)  ko %s" % [
			id, r.get("energy", 0), r.get("mass", 0.0), r.get("bodies", 0), r.get("joints", 0), r.get("idle_max_speed", -1.0),
			r.get("idle_max_joint_gap_m", -1.0), r.get("idle_max_reach_over_chain_m", -1.0), r.get("move_dx_m", -1.0),
			r.get("thrust_accel", 0.0), r.get("ko_broken", false)])
	print("  human vs doll: ", report["human_vs_doll"])
	print("  respawn: ", report["respawn"])
	print("  playground: ", report.get("playground", {}))
	for fl in failures:
		print("  FAIL ", fl)
	print("BODY PROBE ", "OK" if failures.is_empty() else "FAILED (%d)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


# --- кадр пресетов ---

const SHOT_COLS := 4
const SHOT_DX := 3.3
const SHOT_ROW_Y := 3.2
const SHOT_T := 1.6
var _shot_dolls: Array = []


func _setup_shot() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_lighting()
	var ids: Array = []
	for id in PRESETS:
		if ResourceLoader.exists(PRESETS[id]):
			ids.append(id)
	var rows := int(ceil(ids.size() / float(SHOT_COLS)))
	for i in range(ids.size()):
		var col := i % SHOT_COLS
		var row := i / SHOT_COLS
		var y := (rows - 1 - row) * SHOT_ROW_Y
		var x := (col - (SHOT_COLS - 1) / 2.0) * SHOT_DX
		if y > 0.0 and col == 0:
			_floor(Vector3(0, y, 0), SHOT_COLS * SHOT_DX + 2.0)
		var d := _spawn(ids[i], Vector3(x, y, 0))
		d.player_index = i % 4
		_shot_dolls.append(d)
		var lb := Label3D.new()
		lb.text = "%s — %s\nэнергия %d / %d · %.1f кг · тел %d" % [ids[i], d.blueprint.title, d.blueprint.energy_used(), d.blueprint.energy_budget,
			d.total_mass, d.parts.size()]
		lb.font_size = 44
		lb.outline_size = 10
		lb.pixel_size = 0.004
		lb.position = Vector3(x, y - 0.42, 1.65)   # перед полом (глубина пола ±1.5 м)
		lb.modulate = Color(1, 0.95, 0.85)
		add_child(lb)
	var cam := Camera3D.new()
	cam.fov = 38
	var mid_y := (rows - 1) * SHOT_ROW_Y * 0.5 + 0.8
	cam.position = Vector3(0, mid_y + 0.4, 12.5)
	add_child(cam)
	cam.look_at(Vector3(0, mid_y, 0))
	cam.make_current()


func _process(_delta: float) -> void:
	if shot_path == "" or busy or t < SHOT_T:
		return
	busy = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot_path)
	print("saved ", shot_path, " (", err, ") at t=", snappedf(t, 0.01))
	get_tree().quit(0 if err == OK else 1)


func _floor(pos: Vector3, width: float) -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 0.2, 3.0)
	cs.shape = bs
	f.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.28, 0.21)
	mat.roughness = 0.9
	mi.material_override = mat
	f.add_child(mi)
	f.position = pos + Vector3(0, -0.1, 0)
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	f.physics_material_override = phys
	add_child(f)


func _lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.10, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.66, 0.55)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.88, 0.7)
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_energy = 0.4
	fill.light_color = Color(0.65, 0.75, 0.95)
	add_child(fill)
