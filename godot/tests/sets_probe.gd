## Наборы 04.10 в игре (docs/plan-demo/KIT_SETS.md): бойцы про-лиги Земли и Аоэлюн из деталей tools/blender/kit_pro.py / kit_aoe.py.
## Headless: godot --headless --path godot --fixed-fps 60 res://tests/sets_probe.tscn → exit 0/1
## Проверки: пресеты собираются без ошибок чертежа и влезают в свой бюджет; у земных бойцов LeagueLook нет, у Аоэлюн есть;
## броня новых деталей дошла до тел (реактор 0.15, щит-панель и панцирь 0.3); у ядер есть пассив; IDLE_S покоя на полу без взрыва —
## точки суставов расходятся ≤ MAX_JOINT_GAP, скорость частей ≤ MAX_IDLE_SPEED, нет NaN; под вводом боец сдвигается ≥ MIN_MOVE.
## Ветвление: у конструкций с разветвителями дети висят на боковых разъёмах не ядра; мастерская (CraftEdit.attach) собирает
## ветвящееся тело из заготовки «Открытая категория», и оно собирается в куклу.
extends Node3D

const PRESETS := ["pro_sprinter", "pro_titan", "aoe_predator", "aoe_ram",
	# «невозможные конструкции»: ветвление через тройник / узел-сплетение и раму-позвонок / позвонок
	"pro_centipede", "pro_multitool", "aoe_leviathan", "set_chimera"]
## Конструкции с разветвителями: сколько детей должно висеть на якорях Side_* НЕ ядра (ветвление дошло до куклы).
const BRANCHES := {"pro_centipede": 8, "pro_multitool": 8, "aoe_leviathan": 8, "set_chimera": 8}
const PRESET_DIR := "res://scenes/body/presets/"
const SPACING := 8.0
const IDLE_S := 4.0
const MOVE_S := 1.5
const MAX_JOINT_GAP := 0.05
const MAX_IDLE_SPEED := 8.0
const MIN_MOVE := 0.5
const EPS := 0.0005
## тело с бронёй → доля (Tuning.PART_ARMOR)
const ARMOR := {
	"pro_titan": {"Torso": 0.15, "LowerArm_L": 0.3},
	"aoe_ram": {"LowerArm_L": 0.3, "LowerArm_R": 0.3},
	"pro_multitool": {"Torso": 0.15},
	"set_chimera": {"Torso": 0.15, "UpperArm_L": 0.3, "UpperArm_R": 0.3},
}

var checks: Array = []
var dolls: Array[ModularDoll] = []
var track: Array = []
var max_gap := {}
var gap_joint := {}     # id бойца → сустав с наибольшим расхождением (что именно рвётся)
var max_speed := {}
var nan := {}
var start_x := {}
var t := 0.0
var stage := 0


func _check(id: String, ok: bool, detail: Variant = "") -> void:
	checks.append({"id": id, "ok": ok, "detail": detail})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, detail])


func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80.0, 1.0, 40.0)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(0.0, -0.5, 0.0)
	add_child(body)
	for i in range(PRESETS.size()):
		var ps := load(PRESET_DIR + PRESETS[i] + ".tscn") as PackedScene
		if ps == null:
			_check(PRESETS[i] + ".scene", false, "нет сцены")
			continue
		var d := ps.instantiate() as ModularDoll
		d.external_input = true
		d.player_index = i % 2
		d.position = Vector3((i - (PRESETS.size() - 1) * 0.5) * SPACING, 0.0, 0.0)
		add_child(d)
		dolls.append(d)


func _physics_process(dt: float) -> void:
	if stage == 0:
		stage = 1
		_static_checks()
		for d in dolls:
			track.append(_joints_of(d))
		return
	t += dt
	for i in range(dolls.size()):
		_tick(i)
	if stage == 1 and t >= IDLE_S:
		stage = 2
		for d in dolls:
			var id := String(d.blueprint.id)
			_check(id + ".idle", not nan.has(id) and float(max_gap.get(id, 0.0)) <= MAX_JOINT_GAP
				and float(max_speed.get(id, 0.0)) <= MAX_IDLE_SPEED, "gap %.3f м (%s), speed %.2f м/с%s" % [max_gap.get(id, 0.0),
				gap_joint.get(id, "—"), max_speed.get(id, 0.0), ", NaN" if nan.has(id) else ""])
			start_x[id] = d.centre_of_mass().x
			d.input_vec = Vector2(1.0, 0.4)
	elif stage == 2 and t >= IDLE_S + MOVE_S:
		stage = 3
		for d in dolls:
			var id := String(d.blueprint.id)
			var dx := d.centre_of_mass().x - float(start_x[id])
			_check(id + ".move", dx >= MIN_MOVE and not nan.has(id), "ЦМ сдвинулся на %.2f м за %.1f с" % [dx, MOVE_S])
		_finish()


## Мастерская собирает ветвящееся тело теми же ходами, что игрок (CraftEdit.attach): заготовка «Открытая категория», рука →
## тройник → три ветки, одна из них — живой позвонок с когтем сбоку и узлом на конце, на узле колесо. Чертёж проходит проверку
## и собирается в куклу.
func _workshop_check() -> void:
	var bp := CraftEdit.load_body_preset("open_empty")
	if bp == null:
		_check("workshop.open_empty", false, "заготовка не грузится")
		return
	var steps := [
		["arm", "kit_limb_pro_panel_s", "T", "Anchor_Shoulder_L"], ["tee", "kit_hub_pro_tee", "arm", "Anchor_End"],
		["claw", "kit_hand_pro_claw", "tee", "Anchor_Side_L"], ["blade", "kit_blade_pro_energy", "tee", "Anchor_Side_R"],
		["spine", "kit_limb_aoe_spine_s", "tee", "Anchor_End"], ["rib", "kit_hand_aoe_claw", "spine", "Anchor_Side_L"],
		["node", "kit_hub_aoe_node", "spine", "Anchor_End"], ["wheel", "kit_foot_pro_wheel", "node", "Anchor_Side_R"],
	]
	var uid := {"T": "T"}
	var failed: PackedStringArray = []
	for st in steps:
		var r: Dictionary = CraftEdit.attach(bp, String(st[1]), String(uid.get(st[2], "?")), String(st[3]))
		if bool(r.get("ok", false)):
			uid[st[0]] = String(r.get("uid", ""))
		else:
			failed.append("%s: %s" % [st[0], r.get("reason", r.get("code", "?"))])
	var errs := bp.validate()
	_check("workshop.branching", failed.is_empty() and errs.is_empty() and bp.energy_used() <= bp.energy_budget,
		"ходов %d, энергия %d / %d%s%s" % [steps.size(), bp.energy_used(), bp.energy_budget,
		"; отказы: " + "; ".join(failed) if not failed.is_empty() else "", "; чертёж: " + "; ".join(errs) if not errs.is_empty() else ""])
	var d := (load("res://scenes/body/modular_doll.tscn") as PackedScene).instantiate() as ModularDoll
	d.blueprint = bp
	d.external_input = true
	d.position = Vector3(0.0, 0.0, 12.0)
	add_child(d)
	_check("workshop.doll", d.build_errors.is_empty() and d.parts.size() == 9, "тел %d (навершие слито с тройником), ошибок %d" % [d.parts.size(),
		d.build_errors.size()])
	d.queue_free()


func _static_checks() -> void:
	_check("presets", dolls.size() == PRESETS.size(), "%d / %d" % [dolls.size(), PRESETS.size()])
	_workshop_check()
	for d in dolls:
		var id := String(d.blueprint.id)
		var bp := d.blueprint
		_check(id + ".build", d.build_errors.is_empty() and bp.energy_used() <= bp.energy_budget,
			"энергия %d / %d, масса %.1f кг%s" % [bp.energy_used(), bp.energy_budget, bp.total_mass(),
			"; " + "; ".join(d.build_errors) if not d.build_errors.is_empty() else ""])
		var look := d.get_node_or_null("LeagueLook")
		_check(id + ".look", (look != null) == id.begins_with("aoe_"), "LeagueLook %s" % ("есть" if look != null else "нет"))
		if BRANCHES.has(id):
			var side := 0
			for n in bp.nodes:
				var par := String(n.get("parent", ""))
				if par != "" and par != "T" and String(n.get("anchor", "")).begins_with("Anchor_Side_"):
					side += 1
			_check(id + ".branches", side == int(BRANCHES[id]), "детей на боковых разъёмах не ядра: %d, ждали %d" % [side, BRANCHES[id]])
		var core := String(bp.find_node("T").get("part", ""))
		_check(id + ".passive", ActiveBlocks.PASSIVE.has(core) and d.active_rig != null, "%s, ActiveRig %s" % [core,
			"есть" if d.active_rig != null else "нет"])
		for bn in ARMOR.get(id, {}):
			var b := d.parts.get(bn) as RigidBody3D
			var want := float(ARMOR[id][bn])
			var got := float(b.get_meta("armor", 0.0)) if b != null else -1.0
			_check("%s.armor.%s" % [id, bn], absf(got - want) < EPS, "%.2f, ждали %.2f" % [got, want])
		var limbs := 0
		for bn in d.part_integrity:
			limbs += 1 if float(d.part_integrity[bn]) > 0.0 else 0
		_check(id + ".integrity", limbs >= 6 and not d.part_integrity.has("Torso") and not d.part_integrity.has("Head"),
			"тел с запасом прочности: %d" % limbs)


func _joints_of(d: ModularDoll) -> Array:
	var out: Array = []
	for j in d.joints.values():
		var jj := j as Generic6DOFJoint3D
		var a := jj.get_node_or_null(jj.node_a) as RigidBody3D
		var b := jj.get_node_or_null(jj.node_b) as RigidBody3D
		if a == null or b == null:
			continue
		var pa: Vector3 = (d.assembly[String(a.name)] as Transform3D).affine_inverse() * jj.position
		var pb: Vector3 = (d.assembly[String(b.name)] as Transform3D).affine_inverse() * jj.position
		out.append([jj, a, b, pa, pb])
	return out


func _tick(i: int) -> void:
	var id := String(dolls[i].blueprint.id)
	for e in track[i]:
		var a := e[1] as RigidBody3D
		var b := e[2] as RigidBody3D
		if not is_instance_valid(a) or not is_instance_valid(b):
			continue
		var pa := a.to_global(e[3] as Vector3)
		var pb := b.to_global(e[4] as Vector3)
		if not (pa.is_finite() and pb.is_finite()):
			nan[id] = true
			continue
		if pa.distance_to(pb) > float(max_gap.get(id, 0.0)):
			max_gap[id] = pa.distance_to(pb)
			gap_joint[id] = "%s: %s — %s" % [(e[0] as Node).name, a.name, b.name]
	for rb in dolls[i].find_children("*", "RigidBody3D", true, false):
		var v := (rb as RigidBody3D).linear_velocity
		if not v.is_finite():
			nan[id] = true
		else:
			max_speed[id] = maxf(float(max_speed.get(id, 0.0)), v.length())


func _finish() -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c["ok"])
	print("sets_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)
