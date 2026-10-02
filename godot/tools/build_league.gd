## NULL League в игре (docs/plan-demo/ART_NULL.md, «Детали лиги» v1 / v2): материалы ролей League_* и бойцы лиги.
##   • assets/materials/kit/League_*.tres — фиксированные роли деталей tools/blender/kit_league.py, рядом с материалами кита; их ставит
##     тот же пост-импорт tools/kit_import.gd по имени роли. Отдельный builder, а не таблица MATS в tools/build_body_kit.gd: кит ведёт
##     соседняя сессия (BODY_KIT.md §0), здесь — только новое;
##   • data/body/blueprints/league_*.tres + scenes/body/presets/league_*.tscn — четыре бойца лиги (LEAGUE_FIGHTERS; кадр стиля тех же
##     бойцов — tools/blender/league_fighters.py, держать углы совпадающими). В сцене пресета у куклы ребёнок LeagueLook
##     (scripts/league/league_look.gd): ужатые светящиеся шары суставов, фиолетовый вместо цвета игрока, визор с глазом на лице.
## Порядок для новых деталей: blender -b --python tools/blender/body_kit.py -- --export <Имя…> → --import → этот builder →
## -s res://tools/build_body_kit.gd → --import (детали и PartDef — общим builder-ом кита) → этот builder ещё раз (чертежи
## проверяются по PartDef: без них пресеты не пишутся, материалы пишутся всегда).
## Металл не зеркальный (как железо кита, BODY_KIT.md §2): в сценах без неба metallic 0.85+ отражал пустоту и выходил чёрным.
extends SceneTree

const DIR := "res://assets/materials/kit/"
const BLUEPRINT_DIR := "res://data/body/blueprints/"
const PRESET_DIR := "res://scenes/body/presets/"
const MODULAR_SCRIPT := "res://scripts/body/modular_doll.gd"
const BLUEPRINT_SCRIPT := "res://scripts/body/body_blueprint.gd"
const LOOK_SCRIPT := "res://scripts/league/league_look.gd"
const FACE_TEX := "res://assets/textures/league/league_face.png"

## роль → параметры (цвета линейные): albedo, rough, metal, glow + energy, alpha, rim (кромка силуэта: чёрный глянец в тёмном зале)
const MATS := {
	"League_Void": {"albedo": [0.045, 0.036, 0.07], "rough": 0.25, "metal": 0.5, "rim": 0.45},
	"League_Glow": {"albedo": [0.1, 0.02, 0.22], "rough": 0.3, "metal": 0.0, "glow": [0.55, 0.12, 1.0], "energy": 1.3},
	"League_Cyan": {"albedo": [0.03, 0.2, 0.28], "rough": 0.3, "metal": 0.0, "glow": [0.15, 0.8, 1.0], "energy": 1.2},
	"League_Crystal": {"albedo": [0.35, 0.72, 0.95], "rough": 0.05, "metal": 0.1, "glow": [0.2, 0.6, 1.0], "energy": 0.5, "alpha": 0.55},
	"League_Gold": {"albedo": [0.85, 0.58, 0.2], "rough": 0.3, "metal": 0.6},
	"League_Flesh": {"albedo": [0.26, 0.018, 0.035], "rough": 0.35, "metal": 0.0, "glow": [0.35, 0.02, 0.06], "energy": 0.25, "rim": 0.3},
}

## Бойцы лиги — предложение облачной сессии (имена, роли и бюджет энергии — решения автора). Цепь: [якорь ядра (без _L / _R — пара),
## детали, rest_deg, декор / броня на последний сегмент, имена тел]. Правая сторона — те же углы (зеркалит ModularDoll).
## actives — особые модули дома (активные блоки, ActiveBlocks.DEFS): [деталь, родитель (uid ядра / головы или имя тела), якорь,
## канал 1–3].
## Углы — в пределах суставов ModularDoll.JOINT_LIMITS (локоть и колено гнутся в одну сторону) и SIDE_LIMITS у боковых якорей.
const LEAGUE_FIGHTERS := {
	"league_reaper": {
		"title": "Жнец Аоэлюн",
		"hint": "ядро-око, голова-око с рогами; верхние руки — косы над головой, нижняя пара с когтями из боков; ноги-ходули на когтях",
		"core": "kit_core_league_orb", "head": "kit_head_league_eye",
		"chains": [
			["Shoulder", ["kit_limb_league_float_s", "kit_limb_league_scythe_s"], [100.0, 110.0], "", ["UpperArm", "LowerArm"]],
			["Side", ["kit_limb_league_float_s", "kit_limb_league_float_s", "kit_hand_league_talon"], [-10.0, 35.0, 0.0], "", []],
			["Hip", ["kit_limb_league_float_l", "kit_limb_league_float_l", "kit_foot_league_spike"], [40.0, 0.0, -20.0], "",
				["UpperLeg", "LowerLeg", "Foot"]],
		],
		"control": "LowerArm_R",
		"actives": [["kit_active_league_gravity", "T", "Anchor_Back", 1]],
	},
	"league_crystal": {
		"title": "Кристаллид",
		"hint": "кристальное ядро в клетке, голова-друза; руки длинные, до земли, щит на левом предплечье, клинок в правой; короткие ноги на парящих стопах",
		"core": "kit_core_league_crystal", "head": "kit_head_league_crystal",
		"chains": [
			["Shoulder_L", ["kit_limb_league_crystal_l", "kit_limb_league_crystal_l", "kit_hand_league_talon"], [22.0, 6.0, 0.0],
				"kit_deco_league_shield_l", ["UpperArm", "LowerArm", "Hand"]],
			["Shoulder_R", ["kit_limb_league_crystal_l", "kit_limb_league_crystal_l", "kit_blade_league_crystal"], [26.0, 10.0, 0.0], "",
				["UpperArm", "LowerArm", ""]],
			["Hip", ["kit_limb_league_crystal_s", "kit_limb_league_crystal_s", "kit_foot_league_hover"], [16.0, 0.0, -16.0], "",
				["UpperLeg", "LowerLeg", "Foot"]],
		],
		"control": "LowerArm_R",
		"actives": [["kit_active_league_shield", "UpperArm_R", "Anchor_Deco", 1]],
	},
	"league_deep": {
		"title": "Глубинный",
		"hint": "живое ядро под хитином, живая голова с гроздью глаз; четыре щупальца (верхние — с клешнями), стоит на двух щупальцах без стоп",
		"core": "kit_core_league_flesh", "head": "kit_head_league_flesh",
		"chains": [
			["Shoulder", ["kit_limb_league_tentacle_s", "kit_limb_league_tentacle_s", "kit_hand_league_pincer"], [95.0, 55.0, 0.0], "",
				["UpperArm", "LowerArm", "Hand"]],
			["Side", ["kit_limb_league_tentacle_s", "kit_limb_league_tentacle_s"], [-5.0, 40.0], "", []],
			["Hip", ["kit_limb_league_tentacle_l", "kit_limb_league_tentacle_l"], [18.0, 10.0], "", ["UpperLeg", "LowerLeg"]],
		],
		"control": "Hand_R",
		"actives": [["kit_active_league_repair", "T", "Anchor_Back", 1]],
	},
	"league_portal": {
		"title": "Страж портала",
		"hint": "ядро-гироскоп, голова в кольце-портале, длинные парящие руки (клешня, шар-булава); ног почти нет — корпус висит над эмиттерами",
		"core": "kit_core_league_gyro", "head": "kit_head_league_ring",
		"chains": [
			["Shoulder_L", ["kit_limb_league_float_l", "kit_limb_league_float_l", "kit_hand_league_pincer"], [70.0, 60.0, 0.0], "",
				["UpperArm", "LowerArm", "Hand"]],
			["Shoulder_R", ["kit_limb_league_float_l", "kit_limb_league_float_l", "kit_mace_league_orb"], [60.0, 20.0, 0.0], "",
				["UpperArm", "LowerArm", ""]],
			["Hip", ["kit_limb_league_float_s", "kit_foot_league_hover"], [22.0, 0.0], "", ["UpperLeg", "Foot"]],
		],
		"control": "LowerArm_R",
		"actives": [["kit_active_league_phase", "T", "Anchor_Back", 1]],
	},
}
const UIDS := "123456789ABCDEFGIJKLMNOPQRSUVWXYZ"   # без H и T (голова, ядро)

var errors := 0


func _init() -> void:
	_build_mats()
	_build_fighters()
	print("build_league: errors=%d" % errors)
	quit(1 if errors > 0 else 0)


func _err(msg: String) -> void:
	push_error("build_league: " + msg)
	errors += 1


func _build_mats() -> void:
	for role in MATS:
		var d: Dictionary = MATS[role]
		var m := StandardMaterial3D.new()
		m.resource_name = role
		var a: Array = d["albedo"]
		m.albedo_color = Color(a[0], a[1], a[2]).linear_to_srgb()
		m.roughness = float(d["rough"])
		m.metallic = float(d["metal"])
		if d.has("glow"):
			var g: Array = d["glow"]
			m.emission_enabled = true
			m.emission = Color(g[0], g[1], g[2]).linear_to_srgb()
			m.emission_energy_multiplier = float(d["energy"])
		if d.has("alpha"):
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = float(d["alpha"])
		if d.has("rim"):
			m.rim_enabled = true
			m.rim = float(d["rim"])
			m.rim_tint = 0.6
		var err := ResourceSaver.save(m, DIR + role + ".tres")
		if err != OK:
			_err("%s — %d" % [role, err])
	print("build_league: %d materials" % MATS.size())


func _build_fighters() -> void:
	var bp_script := load(BLUEPRINT_SCRIPT)
	for id: String in LEAGUE_FIGHTERS:
		var f: Dictionary = LEAGUE_FIGHTERS[id]
		var nodes: Array[Dictionary] = [{"uid": "T", "part": f["core"], "parent": "", "anchor": "", "name": "Torso"},
			{"uid": "H", "part": f["head"], "parent": "T", "anchor": "Anchor_Neck", "name": "Head", "face": FACE_TEX}]
		var next := 0
		var control := ""
		for ch in f["chains"]:
			var anchor := String(ch[0])
			var sides: Array = [anchor] if anchor.ends_with("_L") or anchor.ends_with("_R") else [anchor + "_L", anchor + "_R"]
			for side in sides:
				var sfx := String(side).right(2)
				var parent := "T"
				var names: Array = ch[4]
				for i in range((ch[1] as Array).size()):
					var uid := UIDS[next]
					next += 1
					var n := {"uid": uid, "part": String(ch[1][i]), "parent": parent, "anchor": "Anchor_" + side if i == 0 else "Anchor_End",
						"rest_deg": float(ch[2][i])}
					if i < names.size() and String(names[i]) != "":
						n["name"] = String(names[i]) + sfx
						if n["name"] == String(f["control"]):
							control = uid
					nodes.append(n)
					parent = uid
				if String(ch[3]) != "":   # декор / броня на последний сегмент (перед концом цепи)
					var host := UIDS[next - 2] if (ch[1] as Array).size() > 2 else UIDS[next - 1]
					nodes.append({"uid": UIDS[next], "part": String(ch[3]), "parent": host, "anchor": "Anchor_Deco"})
					next += 1
		for a in f.get("actives", []):
			var host := String(a[1])
			for n in nodes:
				if String(n.get("name", "")) == host:
					host = String(n["uid"])
			nodes.append({"uid": UIDS[next], "part": String(a[0]), "parent": host, "anchor": String(a[2]), "channel": int(a[3])})
			next += 1
		var bp: Resource = bp_script.new()
		bp.set("id", id)
		bp.set("title", String(f["title"]))
		bp.set("nodes", nodes)
		bp.set("control", PackedStringArray([control]) if control != "" else PackedStringArray())
		bp.set("energy_budget", 1000)
		var used := int(bp.call("energy_used"))
		bp.set("energy_budget", maxi(100, int(ceil(used / 10.0)) * 10))
		var errs: PackedStringArray = bp.call("validate")
		if not errs.is_empty():
			_err("%s: %s" % [id, "; ".join(errs)])
			continue
		var path := BLUEPRINT_DIR + id + ".tres"
		if ResourceSaver.save(bp, path) != OK:
			_err("save " + path)
			continue
		bp = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		var root := Node3D.new()
		root.name = "ModularDoll"
		root.set_script(load(MODULAR_SCRIPT))
		if root.get_script() == null:
			root.free()
			_err("modular_doll.gd не компилируется в режиме -s — пресет %s без сцены" % id)
			continue
		root.set("blueprint", bp)
		var look := Node.new()
		look.name = "LeagueLook"
		look.set_script(load(LOOK_SCRIPT))
		root.add_child(look)
		look.owner = root
		var ps := PackedScene.new()
		var err := ps.pack(root)
		root.free()
		if err != OK or ResourceSaver.save(ps, PRESET_DIR + id + ".tscn") != OK:
			_err("pack %s" % id)
			continue
		print("league %-15s energy %3d / %d, mass %5.1f kg, %2d nodes, control %s" % [id, used, int(bp.get("energy_budget")),
			float(bp.call("total_mass")), nodes.size(), control])

