## «Быстрый конструктор» (docs/plan-demo/FIGHTER_SELECT.md): три ответа игрока → валидный чертёж тела. Собирает только через API
## мастерской (CraftEdit.set_root / attach / set_joint / set_control), поэтому сборка проходит те же проверки, что и руками: якоря, вид
## детали, энергия (BodyBlueprint.energy_cap — и в «запасе из деталей», и без него), структура. Повтор с теми же ответами и другим
## seed даёт другой вариант: пулы деталей по ответу, выбор — rng.
##   стиль   — ядро, конечности, стопы, голова: fast — лёгкие (тонкие, кость), balanced — средние, heavy — тяжёлые (толстые, плиты);
##   удар    — fists: кулаки на обеих руках, тяга на правой; head: ударная голова (×1.15–1.2) + рога, тяга на голове, кисти мягкие;
##             weapon: навершие на конце правой руки (и иногда левой), тяга на предплечье; flail: цепь / трос со свободным шарниром /
##             ядро-кулак на тросе, на конце булава, тяга на руке с цепью;
##   особое  — piston: ударная деталь «на поршне» (у головы — правая стопа) + поршневые плечи; rotor: маховик на спине ядра и мотор
##             в плече ударной руки; arms: доп. руки на боках ядра; armor: щитки и наручи на якорях Deco.
## Если сборка не влезла в энергию — снимаются необязательные детали (броня сверх первой, правая лишняя рука: ответ остаётся в
## чертеже), потом новый бросок; после 2/3 попыток —
## уступка 1 (ноги из пула «Средний», одно звено цепи, без мотора в плече), последние 4 — уступка 2 (тонкие ноги и плечи). Тесно
## бывает только без «запаса из деталей» (бюджет ровно 100): с ним тяжёлое ядро само даёт больше энергии.
class_name QuickBuild
extends RefCounted

const STYLES := ["fast", "balanced", "heavy"]
const HITTERS := ["fists", "head", "weapon", "flail"]
const SPECIALS := ["piston", "rotor", "arms", "armor"]

## Подписи ответов — ключи перевода (tr в месте показа).
const STYLE_TITLES := {"fast": "Быстрый", "balanced": "Средний", "heavy": "Тяжёлый"}
const STYLE_HINTS := {"fast": "лёгкий корпус, тонкие конечности", "balanced": "середина во всём", "heavy": "тяжёлое ядро, толстые конечности"}
const HITTER_TITLES := {"fists": "Кулаки", "head": "Голова", "weapon": "Оружие", "flail": "Кистень"}
const HITTER_HINTS := {"fists": "тяжёлые кулаки на обеих руках", "head": "рогатая голова — главный таран", "weapon": "молот, топор или клинок вместо кисти",
	"flail": "булава на цепи или тросе"}
const SPECIAL_TITLES := {"piston": "Поршень", "rotor": "Ротор", "arms": "Лишние руки", "armor": "Броня"}
const SPECIAL_HINTS := {"piston": "удар выстреливает по клавише канала", "rotor": "маховик: раскрутка сильнее", "arms": "ещё пара рук на боках",
	"armor": "щитки и наручи на конечностях"}

const POOLS := {
	"fast": {
		"core": ["kit_core_crate", "kit_core_toy"],
		"head": ["kit_head_skull", "kit_head_crate", "kit_head_can"],
		"arm_up": ["kit_limb_thin_s", "kit_limb_bone_s", "kit_limb_aoe_whip_s"],
		"arm_lo": ["kit_limb_thin_s", "kit_limb_bone_s"],
		"leg_up": ["kit_limb_thin_l", "kit_limb_bone_l"],
		"leg_lo": ["kit_limb_thin_s", "kit_limb_bone_s"],
		"foot": ["kit_foot_peg", "kit_foot_spring", "kit_foot_flipper"],
		"hand": ["kit_hand_claw", "kit_hand_mitten", "kit_hand_paddle"],
		"fist": ["kit_hand_claw", "kit_hand_league_talon", "kit_hand_fist"],
		"ram_head": ["kit_head_devil", "kit_head_league_eye"],
		"weapon": ["kit_spear_tip", "blade_sword", "kit_blade_pro_energy", "kit_blade_league_crystal"],
		"flail_head": ["kit_mace_league_orb", "head_mallet", "kit_torch_head"],
		"chain": 1,
		"armor_up": ["kit_deco_league_shield_s", "kit_deco_aoe_carapace_s"],
		"armor_lo": ["kit_deco_gauntlet_s"],
		"armor_leg": ["kit_deco_league_shield_s"],
	},
	"balanced": {
		"core": ["kit_core_barrel", "kit_core_drum", "kit_core_cage", "kit_human_torso"],
		"head": ["kit_head_round", "kit_head_bot", "kit_head_pro_visor", "kit_head_cow"],
		"arm_up": ["kit_limb_basic_s", "kit_limb_curved_s", "kit_limb_spring_s"],
		"arm_lo": ["kit_limb_basic_s", "kit_limb_curved_s"],
		"leg_up": ["kit_limb_basic_l", "kit_limb_curved_l"],
		"leg_lo": ["kit_limb_basic_s", "kit_limb_spring_s"],
		"foot": ["kit_foot_boot", "kit_foot_wheel", "kit_foot_aoe_grip"],
		"hand": ["kit_hand_clamp", "kit_hand_mitten", "kit_hand_league_pincer"],
		"fist": ["kit_hand_fist", "kit_hand_pro_claw", "kit_hand_clamp"],
		"ram_head": ["kit_head_aoe_hunter", "kit_head_devil", "kit_head_cow"],
		"weapon": ["blade_axe", "kit_pick_head", "kit_saw_disc", "head_mallet"],
		"flail_head": ["head_mace_ball", "kit_mace_league_orb"],
		"chain": 1,
		"armor_up": ["kit_deco_pauldron", "kit_deco_pro_panel_s"],
		"armor_lo": ["kit_deco_gauntlet_s", "kit_deco_gauntlet_l"],
		"armor_leg": ["kit_deco_pro_panel_s", "kit_deco_league_shield_l"],
	},
	"heavy": {
		"core": ["kit_core_boiler", "kit_core_pro_reactor", "kit_core_league_gyro"],
		"head": ["kit_head_lantern", "kit_head_bot", "kit_head_pro_pilot"],
		"arm_up": ["kit_limb_thick_s", "kit_limb_robotic_s", "kit_limb_plate_s"],
		"arm_lo": ["kit_limb_thick_s", "kit_limb_plate_s"],
		"leg_up": ["kit_limb_thick_l", "kit_limb_plate_l", "kit_limb_robotic_l"],
		"leg_lo": ["kit_limb_thick_s", "kit_limb_plate_s"],
		"foot": ["kit_foot_boot", "kit_foot_pro_wheel"],
		"hand": ["kit_hand_clamp", "kit_hand_fist"],
		"fist": ["kit_hand_pro_crusher", "kit_hand_fist"],
		"ram_head": ["kit_head_horned"],
		"weapon": ["head_hammer", "kit_hammer_pro_drum", "head_mace_ball", "kit_drill_head"],
		"flail_head": ["head_mace_ball", "kit_anchor_head"],
		"chain": 2,
		"armor_up": ["kit_deco_pauldron", "kit_deco_pro_panel_l"],
		"armor_lo": ["kit_deco_gauntlet_l"],
		"armor_leg": ["kit_deco_pro_panel_l", "kit_deco_aoe_carapace_l"],
	},
}
## Рога / шипы на голове-таране (якорь Top головы кита).
const RAM_DECO := ["kit_deco_horns", "kit_deco_spikes_s"]
## Самые дешёвые ноги — запасной шаг, если энергия не сходится.
const CHEAP_LEG := "kit_limb_thin_s"
const CHEAP_FOOT := "kit_foot_peg"
const MID_LEGS := ["kit_limb_basic_s", "kit_limb_bone_s"]
const TRIES := 24


## Ответы по умолчанию (средний, кулаки, броня).
static func default_answers() -> Dictionary:
	return {"style": "balanced", "hitter": "fists", "special": "armor"}


## Чертёж по ответам; seed — вариант (тот же seed и ответы → тот же чертёж). {bp: BodyBlueprint, strike: uid ударной детали,
## notes: PackedStringArray, tries: int}. bp всегда валиден (CraftEdit.friendly_errors пуст) — иначе null (пробы это ловят).
static func generate(answers: Dictionary, seed_v: int) -> Dictionary:
	var style := String(answers.get("style", "balanced"))
	var hitter := String(answers.get("hitter", "fists"))
	var special := String(answers.get("special", "armor"))
	if not POOLS.has(style):
		style = "balanced"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([style, hitter, special, seed_v])
	for t in TRIES:
		var lvl := 0 if t < TRIES * 2 / 3 else (1 if t < TRIES - 4 else 2)
		var r := _try(style, hitter, special, rng, lvl)
		if not r.is_empty():
			r["tries"] = t + 1
			r["level"] = lvl
			return r
	return {"bp": null, "strike": "", "notes": PackedStringArray(), "tries": TRIES, "level": -1}


## Короткая строка ответов для подписи («Тяжёлый · Голова · Поршень»), на языке игрока.
static func answers_line(answers: Dictionary) -> String:
	return "%s · %s · %s" % [
		TranslationServer.translate(String(STYLE_TITLES.get(String(answers.get("style", "")), ""))),
		TranslationServer.translate(String(HITTER_TITLES.get(String(answers.get("hitter", "")), ""))),
		TranslationServer.translate(String(SPECIAL_TITLES.get(String(answers.get("special", "")), "")))]


# ------------------------------------------------------------------ сборка

static func _pick(rng: RandomNumberGenerator, a: Array) -> String:
	return String(a[rng.randi_range(0, a.size() - 1)])


static func _ok(bp: BodyBlueprint) -> bool:
	return CraftEdit.friendly_errors(bp).is_empty() and CraftEdit.structural_errors(bp).is_empty()


## Прикрутить без отказа по энергии: энергию сверяем в конце целиком (порядок деталей не должен решать, что встанет). Вид и якорь —
## как у мастерской (CraftEdit.check), кроме «energy».
static func _put(bp: BodyBlueprint, part_id: String, parent: String, anchor: String) -> String:
	if parent == "":
		return ""
	var c := CraftEdit.check(bp, part_id, parent, anchor)
	if not bool(c["ok"]) and String(c["code"]) != "energy":
		return ""
	var res := CraftEdit._apply_attach(bp, part_id, parent, CraftEdit.anchor_name(anchor))
	return String(res.get("uid", "")) if bool(res.get("ok", false)) else ""


## Цепочка конечностей от якоря ядра: верх → низ → конец. Вернёт [верх, низ, конец].
static func _limb(bp: BodyBlueprint, core: String, anchor: String, up: String, lo: String, end_part: String) -> Array:
	var u := _put(bp, up, core, anchor)
	var l := _put(bp, lo, u, "Anchor_End")
	var e := _put(bp, end_part, l, "Anchor_End") if end_part != "" else ""
	return [u, l, e]


static func _try(style: String, hitter: String, special: String, rng: RandomNumberGenerator, lvl: int) -> Dictionary:
	var P: Dictionary = POOLS[style]
	var bp := BodyBlueprint.new()
	bp.id = "quick_%s_%s_%s" % [style, hitter, special]
	bp.title = TranslationServer.translate("Быстрая сборка")
	var core_part := _pick(rng, P["core"])
	if not bool(CraftEdit.set_root(bp, core_part).get("ok", false)):
		return {}
	var core := CraftEdit.root_uid(bp)
	var optional: Array = []   # uid, которые можно снять, если энергия не сходится
	var notes: PackedStringArray = []
	# голова
	var head_part := _pick(rng, P["ram_head"]) if hitter == "head" else _pick(rng, P["head"])
	var head := _put(bp, head_part, core, "Anchor_Neck")
	if head == "":
		return {}
	if hitter == "head":
		var horn := _put(bp, _pick(rng, RAM_DECO), head, "Anchor_Top")
		if horn != "":
			optional.append(horn)
	# руки
	var hand_l := _pick(rng, P["hand"])
	var hand_r := hand_l
	if hitter == "fists":
		hand_r = _pick(rng, P["fist"])
		hand_l = hand_r if rng.randf() < 0.6 else _pick(rng, P["fist"])
	elif hitter == "head":
		hand_r = "kit_hand_mitten" if rng.randf() < 0.5 else "kit_hand_paddle"
		hand_l = hand_r
	var up := _pick(rng, P["arm_up"]) if lvl < 2 else CHEAP_LEG
	if special == "piston":
		up = "kit_limb_piston_s"
	var lo := _pick(rng, P["arm_lo"])
	var arm_l := _limb(bp, core, "Anchor_Shoulder_L", up, lo, hand_l)
	var arm_r := _limb(bp, core, "Anchor_Shoulder_R", up, lo, "" if hitter in ["weapon", "flail"] else hand_r)
	if "" in [arm_l[0], arm_l[1], arm_l[2], arm_r[0], arm_r[1]]:
		return {}
	# ноги
	var leg_up := _pick(rng, P["leg_up"])
	var leg_lo := _pick(rng, P["leg_lo"])
	var foot := _pick(rng, P["foot"])
	if lvl == 1 and style == "heavy":
		leg_up = _pick(rng, MID_LEGS)
		leg_lo = _pick(rng, MID_LEGS)
	elif lvl >= 2:
		leg_up = CHEAP_LEG
		leg_lo = CHEAP_LEG
		foot = CHEAP_FOOT
	var leg_l := _limb(bp, core, "Anchor_Hip_L", leg_up, leg_lo, foot)
	var leg_r := _limb(bp, core, "Anchor_Hip_R", leg_up, leg_lo, foot)
	if "" in leg_l or "" in leg_r:
		return {}
	# удар
	var strike := ""
	var pull := ""
	match hitter:
		"fists":
			strike = String(arm_r[2])
			if strike == "":
				return {}
			pull = strike
		"head":
			strike = head
			pull = head
		"weapon":
			strike = _put(bp, _pick(rng, P["weapon"]), arm_r[1], "Anchor_End")
			if strike == "":
				return {}
			pull = String(arm_r[1])
			if rng.randf() < 0.5:   # второе навершие слева вместо кисти (необязательное)
				var w2 := _put(bp, _pick(rng, P["weapon"]), arm_l[1], "Anchor_End")
				if w2 != "":
					notes.append("dual")
		"flail":
			var v := rng.randi_range(0, 2)
			var tip := _pick(rng, P["flail_head"])
			if v == 0:   # цепь из звеньев → навершие
				var last := String(arm_r[1])
				for i in (int(P["chain"]) if lvl == 0 else 1):
					last = _put(bp, "chain_segment", last, "Anchor_End")
					if last == "":
						return {}
				strike = _put(bp, tip, last, "Anchor_End")
				pull = String(arm_r[1])
				notes.append("chain")
			elif v == 1:   # трос со свободным шарниром → навершие (как «Вертушка»)
				var rope := _put(bp, "kit_limb_rope_s", arm_r[1], "Anchor_End")
				if rope == "" or not bool(CraftEdit.set_joint(bp, rope, "free").get("ok", false)):
					return {}
				strike = _put(bp, tip, rope, "Anchor_End")
				pull = String(arm_r[1])
				notes.append("rope")
			else:   # ядро-кулак на тросе: тяга на нём — крути мышью
				var ball := _put(bp, "iron_ball_fist", arm_r[1], "Anchor_End")
				if ball == "" or not _joint(bp, ball, "on_rope"):
					return {}
				strike = ball
				pull = ball
				notes.append("ball")
			if strike == "":
				return {}
	# особое
	match special:
		"piston":
			var target := pull if hitter != "head" else String(leg_r[2])
			if CraftEdit.is_fixed(bp, target) or not _joint(bp, target, "on_piston"):
				return {}
			notes.append("piston:" + target)
		"rotor":
			var fw := _put(bp, "kit_mod_flywheel", core, "Anchor_Back")
			if fw == "":
				return {}
			var arm_host := String(arm_r[0]) if hitter != "head" and lvl == 0 else ""
			if arm_host != "":
				_joint(bp, arm_host, "motor")
		"arms":
			# ответ «Лишние руки» обязан остаться в чертеже: левая — всегда, правую можно снять ради энергии; на уступках — тонкие
			for side in ["Anchor_Side_L", "Anchor_Side_R"]:
				var seg_u := _pick(rng, P["arm_lo"]) if lvl == 0 else CHEAP_LEG
				var seg_l := _pick(rng, P["arm_lo"]) if lvl == 0 else CHEAP_LEG
				var ex := _limb(bp, core, side, seg_u, seg_l, _pick(rng, P["fist"]))
				if "" in ex:
					return {}
				if side == "Anchor_Side_R":
					optional.append(ex[0])
		"armor":
			var arm0 := optional.size()
			for a in [arm_l, arm_r]:
				var p1 := _put(bp, _pick(rng, P["armor_up"]), a[0], "Anchor_Deco")
				var p2 := _put(bp, _pick(rng, P["armor_lo"]), a[1], "Anchor_Deco")
				for x in [p1, p2]:
					if x != "":
						optional.append(x)
			for l in [leg_l, leg_r]:
				var p3 := _put(bp, _pick(rng, P["armor_leg"]), l[0], "Anchor_Deco")
				if p3 != "":
					optional.append(p3)
			# ответ «Броня» обязан остаться: первый щиток не снимается ради энергии (не сходится — уступка следующего уровня)
			if optional.size() == arm0:
				return {}
			optional.remove_at(arm0)
	# тяга (ЛКМ) — на ударной детали; первая бесплатна
	bp.control = PackedStringArray()
	bp.control_rmb = PackedStringArray()
	if not bool(CraftEdit.set_control(bp, pull).get("ok", false)):
		return {}
	# энергия: снимаем необязательное с конца, пока не сойдётся (снятая рука-экстра — одна сторона)
	while not _ok(bp) and not optional.is_empty():
		var u := String(optional.pop_back())
		if not CraftEdit.find(bp, u).is_empty():
			CraftEdit.detach(bp, u)
	if not _ok(bp):
		return {}
	return {"bp": bp, "strike": strike, "pull": pull, "notes": notes, "style": style, "hitter": hitter, "special": special}


static func _joint(bp: BodyBlueprint, uid: String, jt: String) -> bool:
	if CraftEdit.find(bp, uid).is_empty():
		return false
	var r := CraftEdit.check_joint(bp, uid, jt)
	if not bool(r["ok"]) and String(r["code"]) != "energy":
		return false
	CraftEdit._apply_joint(bp, uid, jt)
	return true
