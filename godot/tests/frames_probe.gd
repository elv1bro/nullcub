## Рама и разветвители (tools/blender/kit_frames.py, docs/plan-demo/WORKSHOP_V4.md «Рама и разветвители», 06.10.2026): headless-проба.
##   godot --headless --path godot --fixed-fps 60 res://tests/frames_probe.tscn
## Боец из kit_human: вместо левой ноги — малая рама на бедре, из неё три ноги (End, SideB_L, SideB_R); на правом запястье — звезда
## с пятью кистями (End, Side ×2, SideB ×2), на левом — развилка с двумя кистями. Проверки:
##   • детали есть: рама в двух размерах, звезда и развилка; у рамы и звезды якоря SideB принимают конечности (группа Hip), у рамы — Deco;
##   • чертёж валиден, кукла собрана без ошибок, тел столько, сколько узлов, суставы SideB — в группе мышц Hip;
##   • 3 с покоя на полу: суставы не расходятся больше 3 см, нет NaN, кукла не разлетелась.
## В stdout — «=== FRAMES PROBE ===» и JSON.
extends Node3D

const DOLL := preload("res://scenes/body/modular_doll.tscn")
const HUMAN := "res://data/body/blueprints/kit_human.tres"
const PARTS := ["kit_limb_frame_s", "kit_limb_frame_l", "kit_hub_star", "kit_hub_fork"]

var checks: Array = []
var ok := true


func _check(pass_: bool, what: String, detail: Variant = null) -> void:
	checks.append({"ok": pass_, "check": what, "detail": detail})
	ok = ok and pass_
	print("  %s %s  %s" % ["ok  " if pass_ else "FAIL", what, "" if detail == null else str(detail)])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _ready() -> void:
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40.0, 1.0, 4.0)
	cs.shape = bx
	floor.add_child(cs)
	floor.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor)
	# детали и якоря
	var bad: Array = []
	for id in PARTS:
		var d := BodyBlueprint.part_def(id)
		if d == null:
			bad.append(id)
			continue
		var an := BodyBlueprint.part_anchors(d)
		var want := ["Anchor_Side_L", "Anchor_Side_R"]
		if id != "kit_hub_fork":
			want.append_array(["Anchor_End", "Anchor_SideB_L", "Anchor_SideB_R"])
		if id.begins_with("kit_limb_frame"):
			want.append("Anchor_Deco")
		for w in want:
			if not an.has(w):
				bad.append("%s:%s" % [id, w])
			elif w.begins_with("Anchor_SideB"):
				var a: Dictionary = an[w]
				if String(a.get("joint_group", "")) != "Hip" or not (a.get("accepts", PackedStringArray()) as PackedStringArray).has("hand"):
					bad.append("%s:%s мета" % [id, w])
	_check(bad.is_empty(), "рама (S, L), звезда, развилка: детали и якоря; SideB — группа Hip, принимают конечности и кисти", bad)
	# боец
	var bp := (load(HUMAN) as BodyBlueprint).duplicate(true) as BodyBlueprint
	var nodes: Array[Dictionary] = []
	for n in bp.nodes:
		if not ["4", "5", "6", "3", "9"].has(String(n["uid"])):
			nodes.append((n as Dictionary).duplicate(true))
	var add := [
		["4", "kit_limb_frame_s", "T", "Anchor_Hip_L"], ["5", "kit_human_lower_leg", "4", "Anchor_End"], ["6", "kit_human_foot", "5", "Anchor_Ankle"],
		["D", "kit_human_lower_leg", "4", "Anchor_SideB_L"], ["E", "kit_human_lower_leg", "4", "Anchor_SideB_R"],
		["9", "kit_hub_star", "8", "Anchor_Wrist"], ["F", "kit_human_hand", "9", "Anchor_End"], ["G", "kit_human_hand", "9", "Anchor_Side_L"],
		["I", "kit_human_hand", "9", "Anchor_Side_R"], ["J", "kit_human_hand", "9", "Anchor_SideB_L"], ["K", "kit_human_hand", "9", "Anchor_SideB_R"],
		["3", "kit_hub_fork", "2", "Anchor_Wrist"], ["L", "kit_human_hand", "3", "Anchor_Side_L"], ["M", "kit_human_hand", "3", "Anchor_Side_R"],
	]
	for a in add:
		nodes.append({"uid": a[0], "part": a[1], "parent": a[2], "anchor": a[3]})
	bp.nodes = nodes
	bp.control = PackedStringArray(["F"])
	bp.energy_budget = 1000
	bp.id = "frames_probe"
	var errs := bp.validate()
	_check(errs.is_empty(), "чертёж с рамой, звездой и развилкой валиден", errs)
	var d := DOLL.instantiate() as ModularDoll
	d.blueprint = bp
	d.external_input = true
	add_child(d)
	var own := 0
	for n in bp.nodes:
		if not bp.is_fixed(String(n["uid"])):
			own += 1
	var hip_side := 0
	for jn in d.joints:
		if String(jn).begins_with("Hip_"):
			hip_side += 1
	_check(d.build_errors.is_empty() and d.parts.size() == own and hip_side >= 6, "кукла собрана: %d тел, суставов группы Hip %d (бедро + выходы рамы и звёзд)" % [d.parts.size(), hip_side],
		{"errors": d.build_errors, "own": own})
	# 3 с покоя: суставы не расходятся
	var track: Array = []
	for j in d.joints.values():
		var jj := j as Generic6DOFJoint3D
		var a := jj.get_node_or_null(jj.node_a) as RigidBody3D
		var b := jj.get_node_or_null(jj.node_b) as RigidBody3D
		if a == null or b == null:
			continue
		track.append([jj, a, b, (d.assembly[String(a.name)] as Transform3D).affine_inverse() * jj.position,
			(d.assembly[String(b.name)] as Transform3D).affine_inverse() * jj.position])
	var worst := 0.0
	var worst_j := ""
	var nan := false
	for f in range(180):
		await get_tree().physics_frame
		for e in track:
			var pa := (e[1] as RigidBody3D).to_global(e[3] as Vector3)
			var pb := (e[2] as RigidBody3D).to_global(e[4] as Vector3)
			if not (pa.is_finite() and pb.is_finite()):
				nan = true
				continue
			if f > 10 and pa.distance_to(pb) > worst:
				worst = pa.distance_to(pb)
				worst_j = String((e[0] as Node).name)
	var calm := true
	for b in d.parts.values():
		calm = calm and (b as RigidBody3D).linear_velocity.length() < 1.5
	_check(worst < 0.03 and not nan and calm, "3 с покоя: суставы держат (наибольшее расхождение %.3f м — %s), нет NaN, кукла не разлетелась" % [worst, worst_j],
		{"worst": snappedf(worst, 0.001), "joint": worst_j, "nan": nan, "calm": calm})
	print("=== FRAMES PROBE ===")
	print(JSON.stringify({"ok": ok, "checks": checks}))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
