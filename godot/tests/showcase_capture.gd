## Ролики-показ мастерской v4 (docs/plan-demo/WORKSHOP_V4.md): запас из деталей, модули, связки, рама и разветвители, поршни в деле.
## Окно и запись Movie Maker (кадр на кадр):
##   godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 --fixed-fps 30 --write-movie /abs/act.avi \
##       res://tests/showcase_capture.tscn -- "act=hp"
## act: hp | mods | links | frames | pistons. Сцена сама выходит в конце; ничего не пишет на диск, кроме ролика Movie Maker.
extends Node3D

const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"

var act := "hp"
var ws: WorkshopBuild


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "act":
				act = p[1]
	_run.call_deferred()


func _wait(s: float) -> void:
	for i in range(int(s * 30.0)):
		await get_tree().process_frame


func _run() -> void:
	var was := PartHp.on
	PartHp.set_on(false)
	WorkshopBuild.prefs_path = "user://workshop_prefs_showcase.cfg"
	ws = (load(WORKSHOP) as PackedScene).instantiate() as WorkshopBuild
	ws.load_autosave = false
	ws.autosave_on_test = false
	add_child(ws)
	await _wait(0.6)
	match act:
		"hp":
			await _act_hp()
		"mods":
			await _act_mods()
		"links":
			await _act_links()
		"frames":
			await _act_frames()
		"pistons":
			await _act_pistons()
	PartHp.set_on(was)
	get_tree().quit(0)


func _tab(id: String) -> void:
	ws.ui.get("shelf_tab")["body"] = id
	ws.ui.call("_build_left")


## Запас из деталей: «;» — ❤ на карточках и в сводке, паспорт ядра (энергия, мотор), головы и кисти; тяжёлый Рогатый и лёгкий Пустой.
func _act_hp() -> void:
	ws.set_preset("kit_human")
	await _wait(1.8)
	ws.toggle_parts_hp()
	await _wait(2.6)
	ws.select_stand("T", "body")
	await _wait(2.6)
	ws.select_stand("H", "body")
	await _wait(2.2)
	ws.select_stand("3", "body")
	await _wait(2.2)
	ws.clear_selection()
	ws.set_preset("kit_horned")
	await _wait(2.6)
	ws.set_preset("kit_empty")
	await _wait(2.4)
	ws.toggle_parts_hp()


## Модули: полка «Модули», модули по одному на «Человека», паспорт сервопривода и паруса.
func _act_mods() -> void:
	ws.set_preset("kit_human")
	_tab("mods")
	await _wait(1.6)
	var mods := [["kit_mod_servo", "8", "Anchor_Deco"], ["kit_mod_sail", "2", "Anchor_Deco"], ["kit_mod_flywheel", "T", "Anchor_Back"],
		["kit_mod_fairing", "H", "Anchor_Top"], ["kit_mod_grinder", "5", "Anchor_Deco"], ["kit_mod_damper", "B", "Anchor_Deco"]]
	var uids := "DEFGIJ"
	ws.blueprint.energy_budget = 1000
	for k in range(mods.size()):
		ws.blueprint.nodes.append({"uid": uids[k], "part": mods[k][0], "parent": mods[k][1], "anchor": mods[k][2]})
		ws.call("_rebuild")
		_tab("mods")
		ws.select_stand(uids[k], "body")
		await _wait(1.5)
	ws.select_stand("D", "body")
	await _wait(2.4)
	ws.select_stand("E", "body")
	await _wait(2.2)


## Связки: вкладка «Связки», стержень, трос, пружина, поршень — двумя кликами; затем шаблон «Поршневой».
func _act_links() -> void:
	ws.set_preset("kit_human")
	_tab("link")
	await _wait(1.6)
	var plan := [["rod", "3", "Hand_L", "4", "UpperLeg_L"], ["rope", "9", "Hand_R", "C", "Foot_R"], ["spring", "5", "LowerLeg_L", "B", "LowerLeg_R"],
		["piston", "7", "UpperArm_R", "A", "UpperLeg_R"]]
	for st in plan:
		ws.set_link_pick(String(st[0]))
		await _wait(0.9)
		ws._link_click({"target": "body", "uid": st[1], "pos": (ws.stand.parts[st[2]] as Node3D).global_position})
		await _wait(0.9)
		ws._link_click({"target": "body", "uid": st[3], "pos": (ws.stand.parts[st[4]] as Node3D).global_position})
		await _wait(1.3)
	ws.clear_tools()
	await _wait(1.0)
	ws.set_preset("kit_pistons")
	await _wait(2.6)


## Рама и разветвители: рама вместо левой ноги (три ноги), звезда на пять кистей, развилка на две; потом испытание — полёт.
func _act_frames() -> void:
	ws.set_preset("kit_human")
	await _wait(0.5)
	var nodes: Array[Dictionary] = []
	for n in ws.blueprint.nodes:
		if not ["4", "5", "6", "3", "9"].has(String(n["uid"])):
			nodes.append(n)
	for a in [["4", "kit_limb_frame_s", "T", "Anchor_Hip_L"], ["5", "kit_human_lower_leg", "4", "Anchor_End"], ["6", "kit_human_foot", "5", "Anchor_Ankle"],
			["D", "kit_human_lower_leg", "4", "Anchor_SideB_L"], ["E", "kit_human_lower_leg", "4", "Anchor_SideB_R"],
			["9", "kit_hub_star", "8", "Anchor_Wrist"], ["F", "kit_human_hand", "9", "Anchor_End"], ["G", "kit_human_hand", "9", "Anchor_Side_L"],
			["I", "kit_human_hand", "9", "Anchor_Side_R"], ["J", "kit_human_hand", "9", "Anchor_SideB_L"], ["K", "kit_human_hand", "9", "Anchor_SideB_R"],
			["3", "kit_hub_fork", "2", "Anchor_Wrist"], ["L", "kit_human_hand", "3", "Anchor_Side_L"], ["M", "kit_human_hand", "3", "Anchor_Side_R"]]:
		nodes.append({"uid": a[0], "part": a[1], "parent": a[2], "anchor": a[3]})
	ws.blueprint.nodes = nodes
	ws.blueprint.control = PackedStringArray(["F"])
	ws.blueprint.energy_budget = 1000
	ws.call("_rebuild")
	_tab("limb")
	await _wait(1.0)
	ws.select_stand("4", "body")
	await _wait(2.0)
	ws.select_stand("9", "body")
	await _wait(2.0)
	ws.clear_selection()
	ws.start_test()
	await _wait(1.2)
	await _fly([["p1_up", 0.8], ["p1_right", 1.4], ["p1_left", 1.6], ["", 1.2]])


## Поршни в деле: испытание «Поршневого» — подлёт к манекену, I и O по очереди (взмах вверх, отпустил — удар вниз).
func _act_pistons() -> void:
	ws.set_preset("kit_pistons")
	await _wait(1.2)
	ws.start_test()
	await _wait(1.0)
	var d := ws.test_doll as Doll
	var target: Doll = ws.dummy.get("doll") if ws.dummy != null else null
	var t := 0.0
	var seq := ["p1_act1", "p1_act2"]
	var k := 0
	var hold := 0.0
	while t < 13.0:
		await get_tree().process_frame
		t += 1.0 / 30.0
		if target == null or not is_instance_valid(target):
			target = ws.dummy.get("doll") if ws.dummy != null else null
		if target == null or not is_instance_valid(d):
			continue
		var dx := target.centre_of_mass().x - d.centre_of_mass().x
		var dy := target.centre_of_mass().y + 0.2 - d.centre_of_mass().y
		_press("p1_right", dx > 1.0)
		_press("p1_left", dx < -1.0)
		_press("p1_up", dy > 0.4)
		_press("p1_down", dy < -0.6)
		if absf(dx) < 1.8:
			hold -= 1.0 / 30.0
			if hold <= 0.0:
				_press(seq[k % 2], false)
				k += 1
				_press(seq[k % 2], true)
				hold = 0.55
	for a in ["p1_right", "p1_left", "p1_up", "p1_down", "p1_act1", "p1_act2"]:
		_press(a, false)
	await _wait(1.0)


func _press(a: String, on: bool) -> void:
	if a == "" or not InputMap.has_action(a):
		return
	if on and not Input.is_action_pressed(a):
		Input.action_press(a)
	elif not on and Input.is_action_pressed(a):
		Input.action_release(a)


## Полёт в испытании: [[действие, секунды], …].
func _fly(steps: Array) -> void:
	for s in steps:
		_press(String(s[0]), true)
		await _wait(float(s[1]))
		_press(String(s[0]), false)
