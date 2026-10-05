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
## Наборы 04.10 (листы автора «Профессиональная лига Земли» и «Аоэлюн — живые модули»; tools/blender/kit_pro.py, kit_aoe.py): роли
## Pro_* пишутся здесь же, бойцы — в той же таблице. "look": false — земной боец без LeagueLook (шары суставов и пояса — цвет игрока,
## лицо — фото пилота); rest_deg null — угол сустава из позы (плечи и бёдра человечка, как у пресетов кита).
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
	# про-лига Земли (tools/blender/kit_pro.py PRO_MATS): голубой свет линз и сопел, матовый карбон, оранжевый жар реактора
	"Pro_Glow": {"albedo": [0.03, 0.16, 0.5], "rough": 0.3, "metal": 0.0, "glow": [0.1, 0.4, 1.0], "energy": 1.2},
	"Pro_Carbon": {"albedo": [0.03, 0.032, 0.036], "rough": 0.6, "metal": 0.2, "rim": 0.25},
	"Pro_Heat": {"albedo": [0.3, 0.1, 0.02], "rough": 0.3, "metal": 0.0, "glow": [1.0, 0.4, 0.05], "energy": 1.2},
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
	# --- наборы 04.10 (лист автора «полные боевые конструкции») ---
	"pro_sprinter": {
		"title": "Спринтер",
		"hint": "про-лига Земли: ядро-гиростаб, голова-визор; левая рука с клешнёй, в правой — энергоклинок; ноги на копьях",
		"look": false,
		"core": "kit_core_pro_gyro", "head": "kit_head_pro_visor",
		"chains": [
			["Shoulder_L", ["kit_limb_pro_panel_s", "kit_limb_pro_panel_s", "kit_hand_pro_claw"], [null, 12.0, 0.0], "",
				["UpperArm", "LowerArm", "Hand"]],
			["Shoulder_R", ["kit_limb_pro_panel_s", "kit_limb_pro_panel_s", "kit_blade_pro_energy"], [null, 12.0, 0.0], "",
				["UpperArm", "LowerArm", ""]],
			["Hip", ["kit_limb_pro_panel_l", "kit_limb_pro_panel_l", "kit_foot_pro_spike"], [null, 5.0, 0.0], "",
				["UpperLeg", "LowerLeg", "Foot"]],
		],
		"control": "LowerArm_R",
	},
	"pro_titan": {
		"title": "Титан",
		"hint": "про-лига Земли: ядро-реактор, шлем пилота; дробилка и молот-барабан, щит-панель на левом предплечье; ноги на колёсах",
		"look": false,
		"core": "kit_core_pro_reactor", "head": "kit_head_pro_pilot",
		"chains": [
			["Shoulder_L", ["kit_limb_pro_panel_s", "kit_limb_pro_panel_s", "kit_hand_pro_crusher"], [null, 12.0, 0.0],
				"kit_deco_pro_panel_s", ["UpperArm", "LowerArm", "Hand"]],
			["Shoulder_R", ["kit_limb_pro_panel_s", "kit_limb_pro_panel_s", "kit_hammer_pro_drum"], [null, 12.0, 0.0], "",
				["UpperArm", "LowerArm", ""]],
			["Hip", ["kit_limb_pro_panel_l", "kit_limb_pro_panel_l", "kit_foot_pro_wheel"], [null, 5.0, 0.0], "",
				["UpperLeg", "LowerLeg", "Foot"]],
		],
		"control": "LowerArm_R",
	},
	"aoe_predator": {
		"title": "Хищник Аоэлюн",
		"hint": "живое тело: ядро-сердце, голова-охотник; руки-лезвия с когтями, ноги-жилы на ходулях, иглы на спине",
		"core": "kit_core_aoe_heart", "head": "kit_head_aoe_hunter",
		"chains": [
			["Shoulder", ["kit_limb_aoe_blade_s", "kit_limb_aoe_blade_s", "kit_hand_aoe_claw"], [70.0, 40.0, 0.0], "",
				["UpperArm", "LowerArm", "Hand"]],
			["Hip", ["kit_limb_aoe_sinew_l", "kit_limb_aoe_sinew_l", "kit_foot_aoe_stilt"], [24.0, 6.0, -14.0], "",
				["UpperLeg", "LowerLeg", "Foot"]],
		],
		"control": "Hand_R",
		"deco": [["kit_deco_aoe_spines", "T", "Anchor_Back"]],
	},
	"aoe_ram": {
		"title": "Таран Аоэлюн",
		"hint": "живое тело: ядро-сердце, голова-наблюдатель; руки-жилы в панцире с крюками, ноги-плети на присосках",
		"core": "kit_core_aoe_heart", "head": "kit_head_aoe_watcher",
		"chains": [
			["Shoulder", ["kit_limb_aoe_sinew_s", "kit_limb_aoe_sinew_s", "kit_hand_aoe_hook"], [50.0, 30.0, 0.0],
				"kit_deco_aoe_carapace_s", ["UpperArm", "LowerArm", "Hand"]],
			["Hip", ["kit_limb_aoe_whip_l", "kit_limb_aoe_whip_l", "kit_foot_aoe_grip"], [20.0, 6.0, -10.0], "",
				["UpperLeg", "LowerLeg", "Foot"]],
		],
		"control": "Hand_R",
	},
	# --- «невозможные конструкции» 04.10: ветвление через тройник / узел и раму-позвонок / позвонок (KIT_SETS.md) ---
	"pro_centipede": {
		"title": "Сороконожка",
		"hint": "про-лига: гиростаб посередине горизонтального хребта из четырёх рам-позвонков; на каждом позвонке нога вниз и клинок вверх, на концах хребта — копья",
		"look": false,
		"core": "kit_core_pro_gyro", "head": "kit_head_pro_visor",
		"tree": [
			["s1*", "kit_limb_pro_spine_s", "T", "Side_*", 30.0, {}],
			["s2*", "kit_limb_pro_spine_s", "s1*", "End", 0.0, {}],
			["tail*", "kit_foot_pro_spike", "s2*", "End", 0.0, {}],
			["leg1*", "kit_limb_pro_panel_s", "s1*", "Side_R", 0.0, {}],
			["foot1*", "kit_foot_pro_wheel", "leg1*", "End", 0.0, {}],
			["leg2*", "kit_limb_pro_panel_s", "s2*", "Side_R", 0.0, {}],
			["foot2*", "kit_foot_pro_wheel", "leg2*", "End", 0.0, {}],
			["fin1*", "kit_blade_pro_energy", "s1*", "Side_L", 0.0, {}],
			["fin2*", "kit_hand_pro_claw", "s2*", "Side_L", 0.0, {}],
			["leg0*", "kit_limb_pro_panel_s", "T", "Hip_*", null, {}],
			["foot0*", "kit_foot_pro_wheel", "leg0*", "End", 0.0, {}],
			["arm*", "kit_limb_pro_panel_s", "T", "Shoulder_*", null, {"name": "UpperArm_*"}],
			["hand*", "kit_hand_pro_crusher", "arm*", "End", 10.0, {"name": "Hand_*"}],
		],
		"control": "hand*R",
	},
	"pro_multitool": {
		"title": "Мультитул",
		"hint": "про-лига: реактор, шлем пилота; каждая рука кончается тройником с тремя инструментами, каждая нога — тройником с двумя колёсными стойками",
		"look": false,
		"core": "kit_core_pro_reactor", "head": "kit_head_pro_pilot",
		"tree": [
			["arm*", "kit_limb_pro_panel_s", "T", "Shoulder_*", null, {"name": "UpperArm_*"}],
			["tee*", "kit_hub_pro_tee", "arm*", "End", 12.0, {"name": "LowerArm_*"}],
			["toolAL", "kit_hand_pro_crusher", "teeL", "End", 0.0, {}],
			["toolBL", "kit_hand_pro_claw", "teeL", "Side_L", 0.0, {}],
			["toolCL", "kit_saw_disc", "teeL", "Side_R", 0.0, {}],
			["toolAR", "kit_blade_pro_energy", "teeR", "End", 0.0, {}],
			["toolBR", "kit_hand_pro_claw", "teeR", "Side_L", 0.0, {}],
			["toolCR", "kit_hammer_pro_drum", "teeR", "Side_R", 0.0, {}],
			["leg*", "kit_limb_pro_panel_l", "T", "Hip_*", null, {"name": "UpperLeg_*"}],
			["fork*", "kit_hub_pro_tee", "leg*", "End", 0.0, {}],
			["shinA*", "kit_limb_pro_panel_s", "fork*", "Side_L", 25.0, {}],
			["wheelA*", "kit_foot_pro_wheel", "shinA*", "End", 0.0, {}],
			["shinB*", "kit_limb_pro_panel_s", "fork*", "Side_R", 25.0, {}],
			["wheelB*", "kit_foot_pro_wheel", "shinB*", "End", 0.0, {}],
		],
		"control": "tee*R",
	},
	"aoe_leviathan": {
		"title": "Левиафан Аоэлюн",
		"hint": "живое тело: ядро-сердце, голова-наблюдатель; верхние плети делятся в узлах на коготь и два лезвия, нижние жилы — на две плети с присосками, из боков — плети с крюками",
		"core": "kit_core_aoe_heart", "head": "kit_head_aoe_watcher",
		"tree": [
			["arm*", "kit_limb_aoe_whip_s", "T", "Shoulder_*", 80.0, {"name": "UpperArm_*"}],
			["node*", "kit_hub_aoe_node", "arm*", "End", 30.0, {"name": "LowerArm_*"}],
			["mid*", "kit_limb_aoe_whip_s", "node*", "End", 0.0, {}],
			["claw*", "kit_hand_aoe_claw", "mid*", "End", 0.0, {"name": "Hand_*"}],
			["bladeA*", "kit_limb_aoe_blade_s", "node*", "Side_L", 0.0, {}],
			["bladeB*", "kit_limb_aoe_blade_s", "node*", "Side_R", 0.0, {}],
			["side*", "kit_limb_aoe_whip_s", "T", "Side_*", 10.0, {}],
			["hook*", "kit_hand_aoe_hook", "side*", "End", 20.0, {}],
			["leg*", "kit_limb_aoe_sinew_l", "T", "Hip_*", 16.0, {"name": "UpperLeg_*"}],
			["split*", "kit_hub_aoe_node", "leg*", "End", 0.0, {}],
			["tentA*", "kit_limb_aoe_whip_s", "split*", "Side_L", 20.0, {}],
			["gripA*", "kit_foot_aoe_grip", "tentA*", "End", 0.0, {}],
			["tentB*", "kit_limb_aoe_whip_s", "split*", "Side_R", 20.0, {}],
			["gripB*", "kit_foot_aoe_grip", "tentB*", "End", 0.0, {}],
		],
		"deco": [["kit_deco_aoe_spines", "T", "Anchor_Back"]],
		"control": "claw*R",
	},
	"set_chimera": {
		"title": "Химера",
		"hint": "трофейная сборка: реактор и шлем пилота про-лиги на живых деталях — руки-плети делятся в узлах на два когтя, ноги — хребты из позвонков с лезвиями в стороны, на копытах-ходулях",
		"look": false,
		"core": "kit_core_pro_reactor", "head": "kit_head_pro_pilot",
		"tree": [
			["arm*", "kit_limb_aoe_whip_s", "T", "Shoulder_*", null, {"name": "UpperArm_*"}],
			["node*", "kit_hub_aoe_node", "arm*", "End", 10.0, {"name": "LowerArm_*"}],
			["clawA*", "kit_hand_aoe_claw", "node*", "Side_L", 0.0, {}],
			["clawB*", "kit_hand_aoe_claw", "node*", "Side_R", 0.0, {}],
			["sting*", "kit_spear_tip", "node*", "End", 0.0, {}],
			["leg*", "kit_limb_aoe_spine_l", "T", "Hip_*", null, {"name": "UpperLeg_*"}],
			["shin*", "kit_limb_aoe_spine_s", "leg*", "End", 5.0, {"name": "LowerLeg_*"}],
			["stilt*", "kit_foot_aoe_stilt", "shin*", "End", 0.0, {"name": "Foot_*"}],
			["rib1*", "kit_limb_aoe_blade_s", "leg*", "Side_L", 0.0, {}],
			["rib2*", "kit_limb_aoe_blade_s", "shin*", "Side_L", 0.0, {}],
		],
		"deco": [["kit_deco_pro_panel_s", "arm*L", "Anchor_Deco"], ["kit_deco_pro_panel_s", "arm*R", "Anchor_Deco"]],
		"control": "node*R",
	},
	"open_empty": {
		"title": "Открытая категория",
		"hint": "заготовка без регламента: гиростаб и голова-визор, бюджет энергии 300 — под большие ветвящиеся сборки",
		"look": false,
		"core": "kit_core_pro_gyro", "head": "kit_head_pro_visor",
		"tree": [],
		"budget": 300,
	},
}
## без H и T (голова, ядро) и без L и R: тело без своего имени зовётся <префикс>_<uid>, и узел «L» дал бы второй «UpperArm_L»
const UIDS := "123456789ABCDEFGIJKMNOPQSUVWXYZ"

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


## Сцена пресета — текстом: кукла ModularDoll с чертежом (и LeagueLook у бойцов лиги). Не PackedScene.pack: в режиме -s
## modular_doll.gd не компилируется (scenes/ui/hud.gd зовёт автозагрузку Flow, её в -s нет), и pack записывал в сцену значения всех
## свойств куклы вместо двух (04.10: так были испорчены league_*.tscn, восстановлены из git). Готовая сцена не переписывается:
## в ней только ссылки на скрипт и чертёж.
func _write_preset_scene(id: String, league_look: bool) -> bool:
	var path := PRESET_DIR + id + ".tscn"
	if FileAccess.file_exists(path):
		return true
	var t := "[gd_scene format=3]\n\n"
	t += "[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]\n" % MODULAR_SCRIPT
	t += "[ext_resource type=\"Resource\" path=\"%s%s.tres\" id=\"2\"]\n" % [BLUEPRINT_DIR, id]
	if league_look:
		t += "[ext_resource type=\"Script\" path=\"%s\" id=\"3\"]\n" % LOOK_SCRIPT
	t += "\n[node name=\"ModularDoll\" type=\"Node3D\"]\nscript = ExtResource(\"1\")\nblueprint = ExtResource(\"2\")\n"
	if league_look:
		t += "\n[node name=\"LeagueLook\" type=\"Node\" parent=\".\"]\nscript = ExtResource(\"3\")\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(t)
	f.close()
	return true


func _build_fighters() -> void:
	var bp_script := load(BLUEPRINT_SCRIPT)
	for id: String in LEAGUE_FIGHTERS:
		var f: Dictionary = LEAGUE_FIGHTERS[id]
		var league_look := bool(f.get("look", true))
		var nodes: Array[Dictionary] = [{"uid": "T", "part": f["core"], "parent": "", "anchor": "", "name": "Torso"},
			{"uid": "H", "part": f["head"], "parent": "T", "anchor": "Anchor_Neck", "name": "Head"}]
		if league_look:
			nodes[1]["face"] = FACE_TEX
		var next := 0
		var control := ""
		for ch in f.get("chains", []):
			var anchor := String(ch[0])
			var sides: Array = [anchor] if anchor.ends_with("_L") or anchor.ends_with("_R") else [anchor + "_L", anchor + "_R"]
			for side in sides:
				var sfx := String(side).right(2)
				var parent := "T"
				var names: Array = ch[4]
				for i in range((ch[1] as Array).size()):
					var uid := UIDS[next]
					next += 1
					var n := {"uid": uid, "part": String(ch[1][i]), "parent": parent, "anchor": "Anchor_" + side if i == 0 else "Anchor_End"}
					if ch[2][i] != null:
						n["rest_deg"] = float(ch[2][i])
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
		# ветвящаяся сборка: [ключ, деталь, ключ родителя (T, H или ключ узла выше), якорь без «Anchor_», rest_deg | null, {name, joint, mat}];
		# «*» в ключе — пара веток: строка разворачивается в левую и правую («*» → L и R в ключе, родителе, якоре и имени тела)
		var keys := {"T": "T", "H": "H"}
		for e in f.get("tree", []):
			for side in (["L", "R"] if String(e[0]).contains("*") else [""]):
				if next >= UIDS.length():
					_err("%s: узлов больше, чем uid (%d)" % [id, UIDS.length() + 2])
					break
				var key := String(e[0]).replace("*", side)
				var pkey := String(e[2]).replace("*", side)
				var opts: Dictionary = e[5]
				var n := {"uid": UIDS[next], "part": String(e[1]), "parent": String(keys.get(pkey, "?" + pkey)),
					"anchor": "Anchor_" + String(e[3]).replace("*", side)}
				next += 1
				if e[4] != null:
					n["rest_deg"] = float(e[4])
				for k in ["joint", "mat"]:
					if opts.has(k):
						n[k] = String(opts[k])
				if opts.has("name"):
					n["name"] = String(opts["name"]).replace("*", side)
				keys[key] = n["uid"]
				if key == String(f.get("control", "")).replace("*", ""):
					control = String(n["uid"])
				nodes.append(n)
		for dc in f.get("deco", []):   # декор на ядро / голову / узел дерева: [деталь, uid или ключ хозяина, якорь]
			var dhost := String(dc[1]).replace("*", "")
			nodes.append({"uid": UIDS[next], "part": String(dc[0]), "parent": String(keys.get(dhost, dc[1])), "anchor": String(dc[2])})
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
		bp.set("energy_budget", maxi(maxi(100, int(f.get("budget", 0))), int(ceil(used / 10.0)) * 10))
		var errs: PackedStringArray = bp.call("validate")
		if not errs.is_empty():
			_err("%s: %s" % [id, "; ".join(errs)])
			continue
		var path := BLUEPRINT_DIR + id + ".tres"
		if ResourceSaver.save(bp, path) != OK:
			_err("save " + path)
			continue
		bp = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if not _write_preset_scene(id, league_look):
			_err("сцена пресета %s не записана" % id)
			continue
		print("league %-15s energy %3d / %d, mass %5.1f kg, %2d nodes, control %s" % [id, used, int(bp.get("energy_budget")),
			float(bp.call("total_mass")), nodes.size(), control])

