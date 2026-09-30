## Проба кита тела v2 (docs/plan-demo/BODY_KIT.md §7): детали kit_*, материалы, коннекторы, кит «Человек» против human, пресеты kit_*,
## ось материалов, типы шарниров, шипы.
## Headless: godot --headless --path . --fixed-fps 60 res://tests/kit_probe.tscn [-- "report=<путь.json>"]
##   → tests/kit_probe_report.json, печатает KIT PROBE OK / KIT PROBE FAIL, код выхода 0/1.
##
## Проверки (счётчик checks, в отчёте — только провалы и сводки по разделам):
##   • материалы (§4): все MaterialDef из таблицы на диске, поля = таблица, surface — assets/materials/kit/Base_<Mat>.tres; краски paint_*
##     не ближе ΔE76 PAINT_MIN_DE к Tuning.PLAYER_COLORS (кукла в краске не читается чужим игроком);
##   • детали data/body/parts/kit_*.tres: PartDef.is_valid, base_mat известен, attach / connector / material по виду и base_mat (§5.1;
##     fixed — декор, броня и навершия kit_weapons, у наверший энергия 0);
##     сцена — корень RigidBody3D (оси, CCD, can_sleep, meta kind / part_id), масса сцены == PartDef.mass, Mesh (meta rig_mesh) и ≥ 1
##     форма Shape_*, все поверхности — материалы assets/materials/kit (пост-импорт kit_import.gd), Base_* = surface base_mat, у голов
##     Face, у ядер Shirt_Kit (пояс цвета игрока, §1). Детали из glb: Socket в начале координат (у ядра Socket нет), якоря вида (§1) с meta по таблице имён §3.1, у кисти / стопы
##     нет Anchor_End, демпфирование куклы по виду, физматериал = base_mat. kit_human_*: физика, формы и маркеры байт в байт как wood_*,
##     сверху только якорь декора (§3.2);
##   • коннекторы (§3.4): сцена для каждого типа KitJoint с коннектором, корень Node3D, без коллизий, meta, Shirt_Kit;
##   • навершия кита на верстаке оружия: handle_long + навершие (у кирки — ещё гвозди на Face_L) собирается в CraftedWeapon, масса
##     и damage_mult по PartDef;
##   • чертежи (§3.5): kit_human.tres = human.tres узел в узел (детали kit_human_*), пресеты кита в playground_body.gd и body_probe.gd;
##     validate() отказывает по §4 / §5.2 (неизвестный mat, mat на старой детали, шарнир на декоре / корне, weld головы / управляемой /
##     с auto-ребёнком, неизвестный тип);
##   • kit_human против human (обе — ModularDoll): тела и суставы по порядку, массы, дамп, флаги, физматериал, формы, кадры сборки,
##     лимиты / трение / точки суставов, мышцы, поза покоя; после 3 с покоя пары (со спавном в позе и без) ≤ 2 см; одинаковая тяга;
##   • каждый пресет kit_* (и кукла-материал, кукла-шарниры): чертёж собирается, тел = узлов − fixed, масса тела = Σ node_mass, meta
##     material = кг железа, meta body_mult по §5.4 (и Damage.body_mult_of_body), суставы — meta joint_type, трение × тип, лимиты
##     KitJoint.limits, мышцы k / tmax × тип, c × √k (free — 0), поверхности Base_* = материал узла, Connector_<uid> в точке сустава
##     (масштаб joint_r якоря или KitJoint.RADIUS, без коллизий, Shirt_Kit в цвете игрока) и только там, весь Shirt_* в цвете игрока;
##     5 с покоя без взрыва (скорость, суставы, досягаемость), пресет стоит (торс выше STAND_MIN_Y); ввод (1, 0.4) 1.5 с двигает ЦМ
##     ≥ MIN_MOVE; knock_out() → break_apart (суставы сняты, части разлетелись);
##   • кукла-материал (kit_human + mat: плечо L железо и шипы на нём, бедро L резина, бедро R латунь): масса × density / density base_mat,
##     физматериал, Base_* заменена (Shirt_Kit — нет), meta material, meta body_mult (железо × шипы);
##   • кукла-шарниры (kit_human + joint: кисть L free, локоть L spring, плечо R motor, предплечье R weld): числа из контракта §5.2 —
##     free k = c = tmax = 0 и ±160°, spring k × 0.45, tmax × 0.6, лимиты шире на 20°, motor k × 1.8, tmax × 2.2 (и после
##     set_muscle_joint / clear_muscle_joint / set_muscle_group), трение × 0.3 / 0.5 / 1.3; weld — тел и суставов на один меньше,
##     предплечье слито с плечом, коннектора нет;
##   • старые детали (human, junk, flail): коннекторов нет, meta body_mult нет, meta material (float) у каждого тела, суставы pin;
##   • правки ревью 29.09: у деталей со своим телом PartDef.body_mult = Tuning.BODY_MULT[name_prefix] (§3.3); кисть — начало тела в
##     центре форм, Socket над формами, хват WeaponPickup.hand_grip_offset внутри формы (и у каждой кисти каждого пресета); у
##     конечности — Grip в точке Anchor_End; рука мышью (ArmAssist) на всех пресетах: кисть — хват в ладони, досягаемость ≥ human −
##     5 см, kit_lantern / kit_king — хват в Grip, досягаемость ≥ 0.55 м, цель в 0.5 м от плеча (7 направлений) достигается за 3 с;
##     validate: мотор / пружина на лодыжке, рука мышью на fixed-узле, цикл родителей с мотором (без рекурсии), длинная цепь; сварка
##     держит позу покоя сустава (запястье kit_human после сварки предплечья — как после поворота локтя на угол покоя);
##   • удар формой (§3.3, §5.4): PartDef.hit_mult каждой детали кита со своим телом = hit_mult каталога kit_catalog.json (нет ключа — 1.0)
##     и таблице HIT_MULT; у fixed-видов и kit_human_* — 1.0; в пресетах meta body_mult = таблица × материал × hit_mult (× шипы), у
##     kit_devil явно: плечо / предплечье шипастые (× 1.3), голова-чёртик × 1.15, клешня × 1.15, кулак × 1.1.
extends Node3D

const HUMAN_SCENE := "res://scenes/body/modular_doll.tscn"
const HUMAN_BP := "res://data/body/blueprints/human.tres"
const KIT_HUMAN_BP := "res://data/body/blueprints/kit_human.tres"
const PRESETS := {
	"kit_human": "res://scenes/body/presets/kit_human.tscn",
	"kit_brawler": "res://scenes/body/presets/kit_brawler.tscn",
	"kit_bot": "res://scenes/body/presets/kit_bot.tscn",
	"kit_horned": "res://scenes/body/presets/kit_horned.tscn",
	"kit_king": "res://scenes/body/presets/kit_king.tscn",
	"kit_spider": "res://scenes/body/presets/kit_spider.tscn",
	"kit_devil": "res://scenes/body/presets/kit_devil.tscn",
	"kit_skull": "res://scenes/body/presets/kit_skull.tscn",
	"kit_wheels": "res://scenes/body/presets/kit_wheels.tscn",
	"kit_lantern": "res://scenes/body/presets/kit_lantern.tscn",
	# витрина покраски (docs/plan-demo/BODY_PAINT.md §4): узлы kit_human / kit_brawler + paint / stickers
	"kit_graffiti": "res://scenes/body/presets/kit_graffiti.tscn",
	"kit_camo": "res://scenes/body/presets/kit_camo.tscn",
}
## Пресеты из старых деталей (wood_*, junk_*, craft): коннекторов и meta body_mult у них быть не должно.
const LEGACY := {"junk": "res://scenes/body/presets/junk.tscn", "flail": "res://scenes/body/presets/flail.tscn"}
const PARTS_DIR := "res://data/body/parts/"
const WOOD_SCENE_DIR := "res://scenes/body/parts/"
const KIT_MAT_DIR := "res://assets/materials/kit/"
## BODY_KIT.md §4: id → [Base_, density, friction, bounce, body_mult, iron].
const MAT_TABLE := {
	"wood": ["Wood", 1.0, 0.6, 0.05, 1.0, false], "maple": ["Maple", 1.0, 0.6, 0.05, 1.0, false],
	"wood_dark": ["WoodDark", 1.15, 0.6, 0.05, 1.05, false], "planks": ["Planks", 0.9, 0.65, 0.05, 1.0, false],
	"paint_red": ["PaintRed", 1.0, 0.5, 0.05, 1.0, false], "paint_blue": ["PaintBlue", 1.0, 0.5, 0.05, 1.0, false],
	"paint_yellow": ["PaintYellow", 1.0, 0.5, 0.05, 1.0, false], "paint_white": ["PaintWhite", 1.0, 0.5, 0.05, 1.0, false],
	"paint_green": ["PaintGreen", 1.0, 0.5, 0.05, 1.0, false], "rust_red": ["RustRed", 1.6, 0.55, 0.1, 1.1, true],
	"iron": ["Iron", 2.2, 0.5, 0.1, 1.2, true], "rust": ["Rust", 2.0, 0.7, 0.08, 1.15, true],
	"brass": ["Brass", 2.4, 0.45, 0.15, 1.2, false], "bone": ["Bone", 0.9, 0.55, 0.1, 1.05, false],
	"rubber": ["Pink", 0.8, 0.9, 0.6, 0.8, false],
}
## §4: краска (paint_*) — не ближе этого ΔE76 (Lab) к любому Tuning.PLAYER_COLORS (сейчас мин. ~38; прежняя красная — 12).
const PAINT_MIN_DE := 30.0
## §3.1: ANY_LIMB (= build_body_parts.gd / build_body_kit.gd), прочие якоря — как build_craft_parts.gd.
const ANY_LIMB := ["limb", "hand", "foot", "joint", "chain", "weapon_head", "handle", "mod", "plate"]
const OTHER_ACCEPTS := ["weapon_head", "chain", "mod"]
const SIDE_LIMITS := Vector2(-60, 80)
## Виды деталей кита с attach "fixed" (body_kit.py FIXED_KINDS): декор и броня (PartDef.FIXED_KINDS) и оружейные — навершия кита
## (kit_weapons.py) сливаются с деталью-хозяином, как head_mace_ball.
const KIT_FIXED_KINDS := ["deco", "armor", "handle", "weapon_head", "mod", "plate"]
## Виды, у которых на суставе к родителю стоит коннектор (PartDef.connector, §5.1; body_kit.py catalog_entry).
const CONNECTOR_KINDS := ["head", "limb", "hand", "foot", "joint", "chain"]
const END_KINDS := ["hand", "foot"]
## Якоря, обязательные по виду детали из glb (§1).
const REQUIRED_ANCHORS := {
	"core": ["Anchor_Neck", "Anchor_Shoulder_L", "Anchor_Shoulder_R", "Anchor_Hip_L", "Anchor_Hip_R", "Anchor_Side_L", "Anchor_Side_R",
		"Anchor_Back"],
	"limb": ["Anchor_End", "Anchor_Deco"],
	"head": ["Anchor_Top"],
}
## Якорь декора, который кит «Человек» добавляет к якорям wood_* (§3.2), по виду.
const HUMAN_DECO := {"core": "Anchor_Back", "head": "Anchor_Top", "limb": "Anchor_Deco"}
const JOINT_R_RANGE := Vector2(0.02, 0.15)   # м: meta joint_r якоря (радиус шара коннектора) — правдоподобный диапазон
const CATALOG := "res://assets/models/body/kit/kit_catalog.json"
## §3.3: множитель удара формой (PartDef.hit_mult) по префиксу id детали кита; остальные детали со своим телом — 1.0.
const HIT_MULT := {
	"kit_limb_spiked_": 1.3, "kit_head_horned": 1.3, "kit_head_devil": 1.15, "kit_head_cow": 1.1, "kit_hand_claw": 1.15,
	"kit_hand_clamp": 1.1, "kit_hand_fist": 1.1, "kit_foot_peg": 1.15, "kit_limb_rope_": 0.85, "kit_limb_tentacle_": 0.9,
}

const SPACING := 8.0
const IDLE_S := 5.0
const MOVE_S := 1.5
const KO_WAIT_S := 1.0
const HUMAN_REST_S := 3.0
const MAX_IDLE_SPEED := 8.0      # м/с: покой на полу (g = 2) — всё, что быстрее, «взрыв» (= body_probe)
const MAX_JOINT_GAP := 0.05      # м: расхождение точки сустава на двух телах
const CHAIN_SLACK := 0.05        # м
const MIN_MOVE := 0.5            # м ЦМ за MOVE_S под вводом (1, 0.4)
const STAND_MIN_Y := 0.5         # м: торс пресета после покоя выше — кукла стоит, а не лежит (у лежащей ~0.15–0.25)
const HUMAN_SPAWN_TOL := 0.001   # м
const HUMAN_REST_TOL := 0.02     # м
const MOVE_INPUT := Vector2(1.0, 0.4)
const EPS := 1e-4
## Рука мышью (ArmAssist) на пресетах кита (своя площадка с ARM_X0, куклы не мешают пресетам): управляемая кисть — хват в ладони,
## досягаемость не короче human − ARM_REACH_TOL; управляемое предплечье с навершием (ARM_DYNAMIC: бур, булава) — хват в маркере Grip на
## конце, досягаемость ≥ ARM_REACH_MIN, и с целью в 0.5 м от плеча (ARM_TARGETS, цель едет за плечом каждый тик) за
## ARM_END_S − ARM_START_S хват у цели: ошибка ≤ ARM_MAX_ERR, средняя ≤ ARM_MEAN_ERR (без Grip хват в локте, круг 0.29 м — ошибка ≥ 0.21).
const ARM_DYNAMIC := ["kit_lantern", "kit_king"]
const ARM_TARGETS := [Vector3(-0.5, 0, 0), Vector3(-0.35, 0.35, 0), Vector3(0, 0.5, 0), Vector3(0.35, 0.35, 0), Vector3(-0.35, -0.35, 0),
	Vector3(0, -0.5, 0), Vector3(0.35, -0.35, 0)]
const ARM_X0 := 176.0
const ARM_START_S := 1.0
const ARM_END_S := 4.0
const ARM_REACH_MIN := 0.55
const ARM_REACH_TOL := 0.05
const ARM_MAX_ERR := 0.25
const ARM_MEAN_ERR := 0.15

var report_path := "res://tests/kit_probe_report.json"
var t := 0.0
var stage := 0
var rest_done := false
var checks := 0
var failures: PackedStringArray = []
var report := {"materials": {}, "parts": {}, "connectors": {}, "blueprints": {}, "weapon_heads": {}, "validate_rejects": {}, "kit_human_vs_human": {},
	"presets": {}, "mat_test": {}, "joint_test": {}, "legacy": {}, "hit_mult": {}}
var catalog_by_id := {}          # id PartDef → строка kit_catalog.json (hit_mult)

var grip_offset := Vector3(0, -0.03, 0)   # WeaponPickup.hand_grip_offset (читается в _ready): хват оружия в осях тела кисти
var human_ref: ModularDoll       # modular human (= doll.tscn по tests/body_probe), спавн в позе
var human_ns: ModularDoll        # пара без спавна в позе
var kit_ns: ModularDoll
var presets: Dictionary = {}     # id -> ModularDoll (kit_*)
var arm_runs: Array = []         # [id, ModularDoll, ArmAssist, смещение цели от плеча] — динамика руки мышью
var arm_done := false
var tracked: Dictionary = {}     # id -> ModularDoll: пресеты + куклы-тесты (покой)
var track: Dictionary = {}       # id -> {joints, chain, max_speed, max_gap, max_reach_over, worst, nan}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "report":
				report_path = p[1]
	var wp := WeaponPickup.new()
	grip_offset = wp.hand_grip_offset
	wp.free()
	_floor(Vector3(16, 0, 0), 240.0)
	_check_material_defs()
	_check_parts()
	_check_connector_scenes()
	_check_blueprints()
	_check_rejects()
	_check_weapon_heads()
	human_ref = _spawn_scene(HUMAN_SCENE, Vector3(-40, 0, 0), true, 0)
	human_ns = _spawn_scene(HUMAN_SCENE, Vector3(-56, 0, 0), false, 0)
	kit_ns = _spawn_scene(PRESETS["kit_human"], Vector3(-48, 0, 0), false, 0)
	var i := 0
	for id in PRESETS:
		var d := _spawn_scene(PRESETS[id], Vector3(i * SPACING, 0, 0), true, 1 + i % 3)   # цвет не P1: перекраска видна
		i += 1
		if not _check(d != null, "%s: сцена пресета %s — ModularDoll" % [id, PRESETS[id]]):
			continue
		presets[id] = d
		report["presets"][id] = _check_doll(id, d, id)
		_watch(id, d)
	if presets.has("kit_human") and human_ref != null:
		_compare_kit_human()
	if presets.has("kit_devil"):
		_check_devil_hit(presets["kit_devil"])
	_mat_test(Vector3(i * SPACING, 0, 0))
	_joint_test(Vector3((i + 1) * SPACING, 0, 0))
	if human_ref != null:
		_check_legacy("human", human_ref)
	var k := 0
	for id in LEGACY:
		var d := _spawn_scene(LEGACY[id], Vector3(-80 - k * SPACING, 0, 0), true, 0)
		k += 1
		if _check(d != null, "legacy %s: сцена грузится" % id):
			_check_legacy(id, d)
			d.queue_free()
	_arm_setup()


func _check(ok: bool, what: String, detail: Variant = null) -> bool:
	checks += 1
	if not ok:
		var msg := what if detail == null else "%s — %s" % [what, str(detail)]
		failures.append(msg)
		push_warning("FAIL: " + msg)
	return ok


func _spawn_scene(path: String, pos: Vector3, in_pose: bool, player: int) -> ModularDoll:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var n := ps.instantiate()
	var d := n as ModularDoll
	if d == null:
		n.free()
		return null
	d.external_input = true
	d.spawn_in_pose = in_pose
	d.player_index = player
	d.position = pos
	add_child(d)
	return d


func _spawn_bp(bp: BodyBlueprint, pos: Vector3, player: int) -> ModularDoll:
	var d := (load(HUMAN_SCENE) as PackedScene).instantiate() as ModularDoll
	d.blueprint = bp
	d.external_input = true
	d.player_index = player
	d.position = pos
	add_child(d)
	return d


## Удар формой на пресете (§5.4): у kit_devil meta body_mult тел — числа из контракта, без общей формулы _check_doll:
## плечо / предплечье — шипастая конечность (орех, × 1.3), голова-чёртик (paint_red, × 1.15), клешня (железо, × 1.15),
## кулак (ржавчина, × 1.1).
func _check_devil_hit(d: ModularDoll) -> void:
	var want := {
		"UpperArm_L": Damage.body_mult_of("UpperArm_L") * MaterialDef.get_def("wood_dark").body_mult * 1.3,
		"LowerArm_L": Damage.body_mult_of("LowerArm_L") * MaterialDef.get_def("wood_dark").body_mult * 1.3,
		"UpperArm_R": Damage.body_mult_of("UpperArm_R") * MaterialDef.get_def("wood_dark").body_mult * 1.3,
		"Head": Damage.body_mult_of("Head") * MaterialDef.get_def("paint_red").body_mult * 1.15,
		"Hand_L": Damage.body_mult_of("Hand_L") * MaterialDef.get_def("iron").body_mult * 1.15,
		"Hand_R": Damage.body_mult_of("Hand_R") * MaterialDef.get_def("rust").body_mult * 1.1,
	}
	var got := {}
	var bad: Array = []
	for bn in want:
		var b := d.parts.get(bn) as RigidBody3D
		var v: Variant = b.get_meta("body_mult", null) if b != null else null
		got[bn] = snappedf(float(v), 0.0001) if v != null else null
		if b == null or v == null or absf(float(v) - float(want[bn])) > EPS or absf(Damage.body_mult_of_body(b) - float(want[bn])) > EPS:
			bad.append("%s %s ≠ %.4f" % [bn, v, want[bn]])
	_check(bad.is_empty(), "kit_devil: meta body_mult = таблица × материал × hit_mult (шипы 1.3, рожки 1.15, клешня 1.15, кулак 1.1)", bad)
	report["hit_mult"]["kit_devil_body_mult"] = got


## Копия чертежа в памяти (узлы — глубокие копии), новый id.
func _copy_bp(path: String, id: String) -> BodyBlueprint:
	var src := load(path) as BodyBlueprint
	var bp := BodyBlueprint.new()
	bp.id = id
	bp.title = id
	bp.energy_budget = src.energy_budget
	var nodes: Array[Dictionary] = []
	for n in src.nodes:
		nodes.append((n as Dictionary).duplicate(true))
	bp.nodes = nodes
	bp.control = src.control.duplicate()
	return bp


# --- материалы (§4) ---

func _check_material_defs() -> void:
	var r := {}
	for mid in MAT_TABLE:
		var row: Array = MAT_TABLE[mid]
		var P := "material %s" % mid
		var m := MaterialDef.get_def(mid)
		if not _check(m != null, P + ": data/body/materials/%s.tres" % mid):
			continue
		var surf := KIT_MAT_DIR + "Base_%s.tres" % row[0]
		_check(m.id == mid and m.title != "" and MaterialDef.ORDER.has(mid), P + ": id / title / ORDER", [m.id, m.title])
		_check(is_equal_approx(m.density, row[1]) and is_equal_approx(m.friction, row[2]) and is_equal_approx(m.bounce, row[3])
			and is_equal_approx(m.body_mult, row[4]) and m.iron == row[5], P + ": density / friction / bounce / body_mult / iron = §4",
			[m.density, m.friction, m.bounce, m.body_mult, m.iron])
		_check(m.surface != null and m.surface.resource_path == surf and m.surface.resource_name == "Base_" + String(row[0]),
			P + ": surface = " + surf, m.surface.resource_path if m.surface != null else "null")
		r[mid] = {"density": m.density, "friction": m.friction, "bounce": m.bounce, "body_mult": m.body_mult, "iron": m.iron}
		# краски — не цвета игроков (§4): иначе кукла в чужой краске читается чужим игроком (QA 29.09: ΔE76 прежней красной до P2 — 12)
		if mid.begins_with("paint_") and m.surface is BaseMaterial3D:
			var dmin := INF
			for pc in Tuning.PLAYER_COLORS:
				dmin = minf(dmin, _lab((m.surface as BaseMaterial3D).albedo_color).distance_to(_lab(pc)))
			_check(dmin >= PAINT_MIN_DE, P + ": краска дальше ΔE76 %.0f от каждого Tuning.PLAYER_COLORS" % PAINT_MIN_DE, snappedf(dmin, 0.1))
			r[mid]["player_de_min"] = snappedf(dmin, 0.1)
	_check(Array(MaterialDef.all_ids()) == MaterialDef.ORDER, "MaterialDef.all_ids() = ORDER (все на диске)", MaterialDef.all_ids())
	report["materials"] = r


## CIE Lab (D65) цвета sRGB — для расстояния красок до цветов игроков (ΔE76 = расстояние в Lab).
static func _lab(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	var xyz := Vector3(0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b, 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b,
		0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / Vector3(0.95047, 1.0, 1.08883)
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(xyz.x)
	var fy: float = f.call(xyz.y)
	var fz: float = f.call(xyz.z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


# --- детали (§3.1–3.3) ---

func _check_parts() -> void:
	var cat: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if _check(cat is Dictionary, "каталог %s читается" % CATALOG):
		for k in cat:
			var e: Dictionary = cat[k]
			if e.has("id"):
				catalog_by_id[String(e["id"])] = e
	var ids: Array = []
	for fn in DirAccess.get_files_at(PARTS_DIR):
		if fn.begins_with("kit_") and fn.ends_with(".tres"):
			ids.append(fn.get_basename())
	ids.sort()
	_check(ids.size() > 0, "детали: нет data/body/parts/kit_*.tres")
	for id in ids:
		report["parts"][id] = _check_part(String(id))


func _check_part(id: String) -> Dictionary:
	var P := "part " + id
	var r := {}
	var d := BodyBlueprint.part_def(id)
	if not _check(d != null, P + ": PartDef грузится"):
		return r
	var human := id.begins_with("kit_human_")
	r["kind"] = d.kind
	r["mass"] = d.mass
	r["energy"] = d.energy
	r["base_mat"] = d.base_mat
	_check(d.is_valid() and d.id == id, P + ": PartDef.is_valid, id", [d.id, d.kind, d.mass, d.scene != null])
	var md := MaterialDef.get_def(d.base_mat)
	_check(md != null and MaterialDef.ORDER.has(d.base_mat), P + ": base_mat — известный MaterialDef", d.base_mat)
	_check((d.attach == "fixed") == KIT_FIXED_KINDS.has(d.kind), P + ": attach по виду (deco / armor / навершие — fixed)", [d.kind, d.attach])
	if d.kind == "weapon_head":
		_check(d.energy == 0 and d.weapon_mult >= 1.0, P + ": навершие — энергия 0, weapon_mult ≥ 1", [d.energy, d.weapon_mult])
	_check(d.connector == CONNECTOR_KINDS.has(d.kind), P + ": connector по виду", [d.kind, d.connector])
	if md != null:
		_check(d.material == ("iron" if md.iron else "wood"), P + ": material (магнит) по base_mat", [d.material, d.base_mat])
	if d.scene == null:
		return r
	var inst := d.scene.instantiate()
	if not _check(inst is RigidBody3D, P + ": корень сцены RigidBody3D", inst.get_class()):
		inst.free()
		return r
	var rb := inst as RigidBody3D
	var wood: RigidBody3D = null
	if human:
		var wp := WOOD_SCENE_DIR + "wood_" + id.trim_prefix("kit_human_") + ".tscn"
		if _check(ResourceLoader.exists(wp), P + ": есть " + wp):
			wood = (load(wp) as PackedScene).instantiate() as RigidBody3D
	_check(absf(rb.mass - d.mass) < EPS, P + ": масса сцены == PartDef.mass", [rb.mass, d.mass])
	_check(rb.axis_lock_linear_z and rb.axis_lock_angular_x and rb.axis_lock_angular_y and rb.continuous_cd and not rb.can_sleep,
		P + ": оси заперты, CCD, can_sleep = false")
	_check(String(rb.get_meta("kind", "")) == d.kind and String(rb.get_meta("part_id", "")) == id, P + ": meta kind / part_id",
		[rb.get_meta("kind", ""), rb.get_meta("part_id", "")])
	var pm := rb.physics_material_override
	if human and wood != null:
		var wm := wood.physics_material_override
		_check(pm != null and wm != null and pm.friction == wm.friction and pm.bounce == wm.bounce and rb.mass == wood.mass
			and rb.linear_damp == wood.linear_damp and rb.angular_damp == wood.angular_damp and rb.collision_layer == wood.collision_layer
			and rb.collision_mask == wood.collision_mask, P + ": физика = wood_* байт в байт (§3.2)")
		_check(_shape_sig(rb) == _shape_sig(wood), P + ": формы = wood_*", [_shape_sig(rb), _shape_sig(wood)])
		var mw := _markers(wood)
		var mk := _markers(rb)
		var diffs: Array = []
		for n in mw:
			if not mk.has(n):
				diffs.append("нет " + n)
				continue
			var a := mk[n] as Marker3D
			var b := mw[n] as Marker3D
			if a.transform != b.transform:
				diffs.append("кадр " + n)
			for key in b.get_meta_list():
				if not a.has_meta(key) or var_to_str(a.get_meta(key)) != var_to_str(b.get_meta(key)):
					diffs.append("meta %s.%s" % [n, key])
		_check(diffs.is_empty(), P + ": маркеры = wood_* байт в байт", diffs)
		var extra: Array = []
		for n in mk:
			if not mw.has(n):
				extra.append(n)
		var want_extra: Array = [HUMAN_DECO[d.kind]] if HUMAN_DECO.has(d.kind) else []
		_check(extra == want_extra, P + ": сверх wood_* только якорь декора (§3.2)", [extra, want_extra])
		var bad: Array = []
		for n in extra:
			bad.append_array(_anchor_errors(mk[n] as Marker3D))
		_check(bad.is_empty(), P + ": meta якоря декора по таблице §3.1", bad)
	elif not human:
		var core := d.kind == "core" or d.kind == "head"
		var ld: float = Tuning.DOLL_LINEAR_DAMP if core else Tuning.DOLL_LIMB_LINEAR_DAMP
		var ad: float = Tuning.ANGULAR_DAMP if core else Tuning.DOLL_LIMB_ANGULAR_DAMP
		_check(is_equal_approx(rb.linear_damp, ld) and is_equal_approx(rb.angular_damp, ad), P + ": демпфирование куклы по виду",
			[rb.linear_damp, rb.angular_damp, ld, ad])
		_check(pm != null and md != null and is_equal_approx(pm.friction, md.friction) and is_equal_approx(pm.bounce, md.bounce),
			P + ": PhysicsMaterial = friction / bounce base_mat", [pm.friction if pm else -1.0, pm.bounce if pm else -1.0])
		var sock := rb.get_node_or_null("Socket") as Marker3D
		if d.kind == "core":
			_check(sock == null, P + ": у ядра нет Socket")
		elif d.kind == "hand":
			# кисть (§3.1): начало тела — центр форм, Socket над формами (раскладка wood_hand; хват (0, −0.03, 0) — в ладони)
			if _check(sock != null, P + ": есть Socket"):
				var top := -INF
				for c in rb.get_children():
					if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
						top = maxf(top, _shape_aabb(c as CollisionShape3D).end.y)
				_check(absf(sock.position.x) < 1e-3 and absf(sock.position.z) < 1e-3 and sock.position.y >= top - 1e-3
					and absf(sock.transform.basis.y.z) < 1e-3, P + ": кисть — Socket над формами на оси Y, −Y в XY", [sock.position, top])
				_check(absf(_shapes_centre(rb).y) < 1e-3, P + ": кисть — начало тела в центре форм (по Y)", _shapes_centre(rb))
		elif _check(sock != null, P + ": есть Socket"):
			_check(sock.position.length() < 1e-3 and absf(sock.transform.basis.y.z) < 1e-3, P + ": Socket в начале координат, −Y в XY",
				sock.transform)
		if d.kind == "limb":
			# хват ArmAssist, когда рука мышью ведёт саму конечность: Grip в точке Anchor_End (kit_lantern, kit_king)
			var grip := rb.get_node_or_null("Grip") as Marker3D
			var end := rb.get_node_or_null("Anchor_End") as Marker3D
			_check(grip != null and end != null and grip.position.distance_to(end.position) < 1e-4, P + ": маркер Grip в точке Anchor_End",
				[grip.position if grip else null, end.position if end else null])
		var names: Array = []
		var bad: Array = []
		for c in rb.get_children():
			if c is Marker3D and String(c.name).begins_with("Anchor_"):
				names.append(String(c.name))
				bad.append_array(_anchor_errors(c as Marker3D))
		r["anchors"] = names
		var missing: Array = []
		for want in REQUIRED_ANCHORS.get(d.kind, []):
			if not names.has(want):
				missing.append(want)
		_check(missing.is_empty(), P + ": якоря вида (§1)", missing)
		_check(bad.is_empty(), P + ": meta якорей по имени (§3.1)", bad)
	if END_KINDS.has(d.kind):
		_check(rb.get_node_or_null("Anchor_End") == null, P + ": у кисти / стопы нет Anchor_End")
	if d.kind == "hand":
		# хват оружия WeaponPickup / ArmAssist / мастерской — (0, −0.03, 0) тела кисти — внутри формы кисти, а не в запястье
		_check(_inside_shapes(rb, grip_offset), P + ": хват WeaponPickup %s внутри формы кисти" % grip_offset, _shape_boxes(rb))
	# удар (§3.3, §5.4): у детали со своим телом PartDef.body_mult = Tuning.BODY_MULT по name_prefix (в бою — таблица по имени тела ×
	# материал узла); свой множитель — только у декора / брони (бонус хозяину)
	if not BodyBlueprint.is_fixed_part(d):
		var bmt := float(Tuning.BODY_MULT.get(d.name_prefix, 1.0))
		_check(is_equal_approx(d.body_mult, bmt), P + ": body_mult = Tuning.BODY_MULT[%s] (своё тело)" % d.name_prefix, [d.body_mult, bmt])
	r["body_mult"] = d.body_mult
	# удар формой (§3.3): hit_mult детали со своим телом = каталог (нет ключа — 1.0) = таблица HIT_MULT; у fixed и kit_human_* — 1.0
	var hm_want := 1.0
	if not human and not BodyBlueprint.is_fixed_part(d):
		for pre in HIT_MULT:
			if id.begins_with(String(pre)):
				hm_want = float(HIT_MULT[pre])
		if _check(catalog_by_id.has(id), P + ": есть в kit_catalog.json"):
			var hm_cat := float((catalog_by_id[id] as Dictionary).get("hit_mult", 1.0))
			_check(is_equal_approx(d.hit_mult, hm_cat), P + ": hit_mult = каталог", [d.hit_mult, hm_cat])
	_check(is_equal_approx(d.hit_mult, hm_want), P + ": hit_mult = %.2f (§3.3)" % hm_want, d.hit_mult)
	r["hit_mult"] = d.hit_mult
	if not is_equal_approx(d.hit_mult, 1.0):
		report["hit_mult"][id] = d.hit_mult
	if human and d.kind == "core":
		_check(rb.get_node_or_null("Socket") == null, P + ": у ядра нет Socket")
	# формы и меш
	var shapes := 0
	for c in rb.get_children():
		if c is CollisionShape3D and String(c.name).begins_with("Shape") and (c as CollisionShape3D).shape != null:
			shapes += 1
	r["shapes"] = shapes
	_check(shapes >= 1, P + ": есть форма Shape_* (коллизия, §3.1 / §6)", shapes)
	var mesh := rb.get_node_or_null("Mesh") as Node3D
	var meshes: Array = _meshes(mesh) if mesh != null else []
	_check(mesh != null and bool(mesh.get_meta("rig_mesh", false)) and not meshes.is_empty() and rb.get_node_or_null("Mesh_R") == null,
		P + ": Mesh (meta rig_mesh, есть MeshInstance3D), без Mesh_R")
	# поверхности: пост-импорт поставил материалы кита
	var total := 0
	var foreign: Array = []
	var base_paths: Array = []
	var roles := {}
	for mi in meshes:
		var m3 := mi as MeshInstance3D
		for s in range(m3.mesh.get_surface_count()):
			total += 1
			var m := m3.get_active_material(s)
			if m == null or not m.resource_path.begins_with(KIT_MAT_DIR):
				foreign.append("%s/%d %s" % [m3.name, s, (m.resource_name + " " + m.resource_path) if m != null else "null"])
				continue
			roles[m.resource_name] = true
			if m.resource_name.begins_with("Base_"):
				base_paths.append(m.resource_path)
	r["surfaces"] = total
	r["roles"] = roles.keys()
	_check(total > 0 and foreign.is_empty(), P + ": все поверхности — assets/materials/kit (пост-импорт, §2)", foreign)
	var want_base: String = md.surface.resource_path if md != null and md.surface != null else "?"
	var base_bad := base_paths.filter(func(x: Variant) -> bool: return String(x) != want_base)
	_check(not base_paths.is_empty() and base_bad.is_empty(), P + ": поверхности Base_* = surface base_mat (%s)" % want_base.get_file(),
		[base_paths.size(), base_bad])
	if d.kind == "head":
		_check(roles.has("Face"), P + ": у головы есть плашка Face")
	if d.kind == "core":   # §1 «Цвет игрока на ядре»: широкий пояс Shirt_Kit — цвет игрока читается на игровом расстоянии
		_check(roles.has("Shirt_Kit"), P + ": у ядра есть Shirt_Kit (пояс цвета игрока)")
	print("  part %-22s %-5s %4.1f kg  E%-2d %-12s shapes %d  surf %2d  %s" % [id, d.kind, d.mass, d.energy, d.base_mat, shapes, total,
		",".join(PackedStringArray(roles.keys()))])
	inst.free()
	if wood != null:
		wood.free()
	return r


## Ожидаемые meta якоря по имени (short — без «Anchor_»), таблица §3.1.
static func _anchor_expect(short: String) -> Dictionary:
	var base := short
	var mirror := false
	if short.ends_with("_L") or short.ends_with("_R"):
		base = short.substr(0, short.length() - 2)
		mirror = short.ends_with("_R")
	var e := {"accepts": OTHER_ACCEPTS, "group": "Ankle", "from_pose": false, "mirror": mirror, "joint_r": false}
	match base:
		"Neck":
			e["accepts"] = ["head"]
			e["group"] = "Neck"
			e["from_pose"] = true
			e["joint_r"] = true
		"Shoulder", "Hip":
			e["accepts"] = ANY_LIMB
			e["group"] = base
			e["from_pose"] = true
			e["joint_r"] = true
		"Side":
			e["accepts"] = ANY_LIMB
			e["group"] = "Hip"
			e["limit_deg"] = SIDE_LIMITS
			e["joint_r"] = true
		"End":
			e["accepts"] = ANY_LIMB
			e["group"] = "auto"
			e["joint_r"] = true
		"Deco":
			e["accepts"] = ["armor", "deco"]
			e["group"] = ""
		"Top", "Back":
			e["accepts"] = ["deco"]
			e["group"] = ""
	var g := String(e["group"])
	e["rest_deg"] = float(Tuning.POSE[g]) if bool(e["from_pose"]) and Tuning.POSE.has(g) else 0.0
	return e


func _anchor_errors(m: Marker3D) -> Array:
	var out: Array = []
	var nm := String(m.name)
	var e := _anchor_expect(nm.substr(7))
	var acc := Array(PackedStringArray(m.get_meta("accepts", PackedStringArray())))
	var want: Array = (e["accepts"] as Array).duplicate()
	acc.sort()
	want.sort()
	if acc != want:
		out.append("%s accepts %s ≠ %s" % [nm, acc, want])
	var g := String(m.get_meta("joint_group", "<нет>"))
	if g != String(e["group"]):
		out.append("%s joint_group «%s» ≠ «%s»" % [nm, g, e["group"]])
	if g == "":
		for k in acc:
			if not PartDef.FIXED_KINDS.has(k):
				out.append("%s: joint_group \"\" принимает «%s» со своим телом" % [nm, k])
	elif g != "auto" and not Tuning.MUSCLE_GROUPS.has(g):
		out.append("%s: группа «%s» не в Tuning.MUSCLE_GROUPS" % [nm, g])
	for k in acc:
		if not PartDef.KINDS.has(k):
			out.append("%s: вид «%s» не в PartDef.KINDS" % [nm, k])
	var rd: Variant = m.get_meta("rest_deg", null)
	if typeof(rd) != TYPE_FLOAT or absf(float(rd) - float(e["rest_deg"])) > 1e-4:
		out.append("%s rest_deg %s ≠ %s" % [nm, rd, e["rest_deg"]])
	if bool(m.get_meta("rest_from_pose", false)) != bool(e["from_pose"]):
		out.append("%s rest_from_pose" % nm)
	if not m.has_meta("mirror") or bool(m.get_meta("mirror")) != bool(e["mirror"]):
		out.append("%s mirror %s" % [nm, m.get_meta("mirror", null)])
	if e.has("limit_deg"):
		if not m.has_meta("limit_deg") or Vector2(m.get_meta("limit_deg")) != Vector2(e["limit_deg"]):
			out.append("%s limit_deg %s" % [nm, m.get_meta("limit_deg", null)])
	elif m.has_meta("limit_deg"):
		out.append("%s: лишний limit_deg" % nm)
	if bool(e["joint_r"]):
		var jr := float(m.get_meta("joint_r", 0.0))
		if jr < JOINT_R_RANGE.x or jr > JOINT_R_RANGE.y:
			out.append("%s joint_r %s" % [nm, m.get_meta("joint_r", null)])
	elif m.has_meta("joint_r"):
		out.append("%s: joint_r у якоря без сустава" % nm)
	if absf(m.transform.basis.y.z) > 1e-3:
		out.append("%s: −Y не в плоскости XY" % nm)
	return out


static func _markers(n: Node) -> Dictionary:
	var out := {}
	for c in n.get_children():
		if c is Marker3D:
			out[String(c.name)] = c
	return out


## AABB формы в осях тела (формы кита без поворота в XY — хватает габарита).
static func _shape_aabb(cs: CollisionShape3D) -> AABB:
	var h := ModularDoll._shape_half(cs.shape)
	return cs.transform * AABB(-h, h * 2.0)


## Центр форм тела, взвешенный по объёму (= AUTO центр масс Jolt, ModularDoll._com_local).
static func _shapes_centre(b: Node) -> Vector3:
	var acc := Vector3.ZERO
	var vol := 0.0
	for c in b.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var v := ModularDoll._shape_volume((c as CollisionShape3D).shape)
			acc += (c as Node3D).position * v
			vol += v
	return acc / vol if vol > 0.0 else Vector3.ZERO


## Точка p (в осях тела b) внутри хотя бы одной формы тела (по AABB формы).
static func _inside_shapes(b: Node, p: Vector3) -> bool:
	for c in b.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null and _shape_aabb(c as CollisionShape3D).grow(1e-4).has_point(p):
			return true
	return false


static func _shape_boxes(b: Node) -> Array:
	var out: Array = []
	for c in b.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var a := _shape_aabb(c as CollisionShape3D)
			out.append("%s %s..%s" % [c.name, a.position.snappedf(0.001), a.end.snappedf(0.001)])
	return out


# --- коннекторы (§3.4) ---

func _check_connector_scenes() -> void:
	for jt in KitJoint.ORDER:
		var path := KitJoint.connector_scene(jt)
		if path == "":
			continue
		var P := "connector " + String(jt)
		var r := {"path": path}
		report["connectors"][jt] = r
		if not _check(ResourceLoader.exists(path), P + ": есть сцена (§3.4; для «motor» — Kit_Joint_Motor.glb в каталоге)", path):
			continue
		var inst := (load(path) as PackedScene).instantiate()
		r["root"] = inst.get_class()
		_check(inst is Node3D and not inst is CollisionObject3D, P + ": корень Node3D, не тело", inst.get_class())
		_check(_collision_count(inst) == 0, P + ": без коллизий")
		_check(bool(inst.get_meta("rig_mesh", false)) and String(inst.get_meta("connector_type", "")) == String(KitJoint.info(jt)["connector"]),
			P + ": meta rig_mesh / connector_type")
		var total := 0
		var foreign: Array = []
		var shirt := 0
		for mi in _meshes(inst):
			var m3 := mi as MeshInstance3D
			for s in range(m3.mesh.get_surface_count()):
				total += 1
				var m := m3.get_active_material(s)
				if m == null or not m.resource_path.begins_with(KIT_MAT_DIR):
					foreign.append("%s/%d" % [m3.name, s])
				elif m.resource_name.begins_with("Shirt"):
					shirt += 1
		r["surfaces"] = total
		r["shirt"] = shirt
		_check(total > 0 and foreign.is_empty(), P + ": поверхности — assets/materials/kit", foreign)
		_check(shirt > 0, P + ": есть Shirt_Kit (шар в цвет игрока)")
		inst.free()


static func _collision_count(n: Node) -> int:
	var c := 1 if (n is CollisionObject3D or n is CollisionShape3D or n is CollisionPolygon3D) else 0
	for ch in n.get_children():
		c += _collision_count(ch)
	return c


static func _meshes(n: Node) -> Array:
	var out: Array = []
	if n == null:
		return out
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


## resource_path материалов поверхностей Base_* под узлом n. Покрашенная поверхность (BODY_PAINT.md §5: дубль исходного материала
## с next_pass краски, имя то же) — путь исходника по имени (assets/materials/kit/<имя>.tres).
static func _base_surfaces(n: Node) -> Array:
	var out: Array = []
	for mi in _meshes(n):
		var m3 := mi as MeshInstance3D
		for s in range(m3.mesh.get_surface_count()):
			var m := m3.get_active_material(s)
			if m != null and m.resource_name.begins_with("Base_"):
				var pth := m.resource_path
				if pth == "" and BodyPaint.paint_pass(m) != null:
					pth = KIT_MAT_DIR + m.resource_name + ".tres"
				out.append(pth if pth != "" else "<%s без пути>" % m.resource_name)
	return out


## [число поверхностей Shirt_*, список не в цвете игрока]
static func _shirt_check(n: Node, player: int) -> Array:
	var pc: Color = Tuning.PLAYER_COLORS[clampi(player, 0, 3)]
	var cnt := 0
	var wrong: Array = []
	for mi in _meshes(n):
		var m3 := mi as MeshInstance3D
		for s in range(m3.mesh.get_surface_count()):
			var m := m3.get_active_material(s)
			if m == null or not m.resource_name.begins_with("Shirt"):
				continue
			cnt += 1
			var c := (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color.BLACK
			if absf(c.r - pc.r) > 1e-3 or absf(c.g - pc.g) > 1e-3 or absf(c.b - pc.b) > 1e-3:
				wrong.append("%s/%d %s" % [m3.name, s, c.to_html(false)])
	return [cnt, wrong]


# --- чертежи (§3.5, §4, §5.2) ---

func _check_blueprints() -> void:
	var r := {}
	var h := load(HUMAN_BP) as BodyBlueprint
	var k := load(KIT_HUMAN_BP) as BodyBlueprint
	if _check(h != null and k != null, "чертежи human / kit_human грузятся"):
		var diffs: Array = []
		if h.nodes.size() != k.nodes.size():
			diffs.append("узлов %d ≠ %d" % [k.nodes.size(), h.nodes.size()])
		else:
			for i in range(h.nodes.size()):
				var a: Dictionary = h.nodes[i].duplicate()
				var b: Dictionary = k.nodes[i].duplicate()
				var want := "kit_human_" + String(a.get("part", "")).trim_prefix("wood_")
				if String(b.get("part", "")) != want:
					diffs.append("%s: деталь %s ≠ %s" % [a.get("uid", "?"), b.get("part", ""), want])
				a.erase("part")
				b.erase("part")
				if a != b:
					diffs.append("%s: %s ≠ %s" % [a.get("uid", "?"), b, a])
		if h.control != k.control or h.energy_budget != k.energy_budget:
			diffs.append("control / energy_budget")
		_check(diffs.is_empty(), "kit_human.tres = human.tres узел в узел, детали kit_human_* (§3.5)", diffs)
		r["kit_human_nodes"] = k.nodes.size()
		r["kit_human_energy"] = k.energy_used()
	var pg: Array = (load("res://scenes/body/playground_body.gd") as Script).get_script_constant_map().get("PRESETS", [])
	var bpp: Dictionary = (load("res://tests/body_probe.gd") as Script).get_script_constant_map().get("PRESETS", {})
	var miss_pg: Array = []
	var miss_bp: Array = []
	for id in PRESETS:
		var found := false
		for e in pg:
			if String(e[0]) == id and String(e[1]) == String(PRESETS[id]):
				found = true
		if not found:
			miss_pg.append(id)
		if String(bpp.get(id, "")) != String(PRESETS[id]):
			miss_bp.append(id)
	_check(miss_pg.is_empty(), "scenes/body/playground_body.gd PRESETS: пресеты кита (§3.5)", miss_pg)
	_check(miss_bp.is_empty(), "tests/body_probe.gd PRESETS: пресеты кита (§3.5)", miss_bp)
	report["blueprints"] = r


## Навершия кита (kit_weapons.py, §3.1) годятся и для верстака оружия: handle_long + навершие на Anchor_Head собирается в
## CraftedWeapon без ошибок, масса = рукоять + навершие, damage_mult = weapon_mult навершия (× рукояти); у кирки на Anchor_Face_L
## встают гвозди (mod). Оружие висит далеко от кукол и сразу удаляется.
func _check_weapon_heads() -> void:
	var r := {}
	var handle := BodyBlueprint.part_def("handle_long")
	var nails := BodyBlueprint.part_def("mod_nails")
	var ids: Array = []
	for fn in DirAccess.get_files_at(PARTS_DIR):
		if fn.begins_with("kit_") and fn.ends_with(".tres"):
			var d := BodyBlueprint.part_def(fn.get_basename())
			if d != null and d.kind == "weapon_head":
				ids.append(d.id)
	ids.sort()
	_check(ids.size() >= 6 and handle != null, "навершия кита: ≥ 6 деталей weapon_head, есть handle_long", ids)
	if handle == null:
		return
	var k := 0
	for id in ids:
		var head := BodyBlueprint.part_def(String(id))
		var bp := WeaponBlueprint.new()
		bp.id = "kit_test_" + String(id)
		var nodes: Array[Dictionary] = [{"uid": "0", "part": "handle_long", "parent": "", "anchor": ""},
			{"uid": "1", "part": String(id), "parent": "0", "anchor": "Anchor_Head"}]
		var want_mass := handle.mass + head.mass
		if BodyBlueprint.part_anchors(head).has("Anchor_Face_L") and nails != null:
			nodes.append({"uid": "2", "part": "mod_nails", "parent": "1", "anchor": "Anchor_Face_L"})
			want_mass += nails.mass
		bp.nodes = nodes
		var w := CraftedWeapon.create(bp)
		add_child(w)
		w.global_position = Vector3(-90.0 - 3.0 * k, 60.0, 0.0)
		k += 1
		var sm := w.summary()
		var want_mult := handle.weapon_mult * head.weapon_mult * (nails.weapon_mult if nodes.size() > 2 else 1.0)
		r[id] = {"mass": snappedf(float(sm["mass"]), 0.01), "length": snappedf(float(sm["length"]), 0.01),
			"damage_mult": snappedf(float(sm["damage_mult"]), 0.001), "mod": nodes.size() > 2}
		_check(bp.validate().is_empty() and w.build_errors.is_empty(), "weapon %s: handle_long + навершие собирается (CraftedWeapon)" % id,
			[bp.validate(), w.build_errors])
		_check(absf(float(sm["mass"]) - want_mass) < 1e-3 and float(sm["length"]) > 0.4,
			"weapon %s: масса = рукоять + навершие%s, длина > 0.4 м" % [id, " + гвозди" if nodes.size() > 2 else ""],
			[sm["mass"], want_mass, sm["length"]])
		_check(absf(float(sm["damage_mult"]) - want_mult) < 1e-3, "weapon %s: damage_mult = Π weapon_mult" % id, [sm["damage_mult"], want_mult])
		w.queue_free()
	report["weapon_heads"] = r


## validate() отказывает по §4 / §5.2 (строки причин — BodyBlueprint._mat_error / _joint_error).
func _check_rejects() -> void:
	var cases := [
		["kit_human", "1", "mat", "unobtainium", "неизвестный материал", "mat_unknown"],
		["human", "1", "mat", "iron", "не красится", "mat_on_wood"],
		["kit_skull", "D", "joint", "free", "намертво", "joint_on_deco"],   # султан на голове (декор)
		["kit_human", "T", "joint", "motor", "корня", "joint_on_root"],
		["kit_human", "H", "joint", "weld", "голову", "weld_head"],
		["kit_human", "9", "joint", "weld", "управляемую", "weld_control"],
		["kit_brawler", "2", "joint", "weld", "auto", "weld_auto_child"],
		["kit_human", "1", "joint", "hinge", "неизвестный тип", "joint_unknown"],
		# мотор / пружина на суставе без мышцы (Ankle: k = tmax = 0) — энергия без эффекта (§5.2)
		["kit_human", "6", "joint", "motor", "нет мышцы", "motor_on_ankle"],
		["kit_bot", "C", "joint", "spring", "нет мышцы", "spring_on_ankle"],
	]
	for c in cases:
		var bp := _copy_bp("res://data/body/blueprints/%s.tres" % c[0], "kit_probe_" + String(c[5]))
		var n := bp.find_node(String(c[1]))
		if not _check(not n.is_empty(), "validate %s: в %s нет узла %s" % [c[5], c[0], c[1]]):
			continue
		n[String(c[2])] = c[3]
		var errs := bp.validate()
		var hit := false
		for e in errs:
			hit = hit or String(e).contains(String(c[4]))
		report["validate_rejects"][c[5]] = Array(errs)
		_check(hit, "validate отказывает: %s (%s.%s = %s, ждём «%s»)" % [c[5], c[1], c[2], c[3], c[4]], Array(errs))
	# рука мышью на детали без своего тела (бур вместо кисти): ArmAssist не нашёл бы тела — отказ validate()
	var bpc := _copy_bp("res://data/body/blueprints/kit_lantern.tres", "kit_probe_control_fixed")
	bpc.control = PackedStringArray(["9"])
	var errs_c := bpc.validate()
	report["validate_rejects"]["control_on_fixed"] = Array(errs_c)
	_check(Array(errs_c).any(func(e: Variant) -> bool: return String(e).contains("нет своего тела")),
		"validate отказывает: control_on_fixed (kit_lantern control = бур «9», ждём «нет своего тела»)", Array(errs_c))
	# цикл родителей с шарниром на auto-якорях: группа сустава (запрет мотора без мышцы) не зацикливается, validate называет цикл
	var cyc := BodyBlueprint.new()
	cyc.id = "kit_probe_cycle"
	var cn: Array[Dictionary] = [{"uid": "T", "part": "kit_core_barrel", "parent": "", "anchor": "", "name": "Torso"},
		{"uid": "H", "part": "kit_head_round", "parent": "T", "anchor": "Anchor_Neck"},
		{"uid": "A", "part": "kit_limb_basic_s", "parent": "B", "anchor": "Anchor_End", "joint": "motor"},
		{"uid": "B", "part": "kit_limb_basic_s", "parent": "A", "anchor": "Anchor_End", "joint": "spring"}]
	cyc.nodes = cn
	var errs_y := cyc.validate()
	report["validate_rejects"]["cycle_joint"] = Array(errs_y)
	_check(Array(errs_y).any(func(e: Variant) -> bool: return String(e).contains("цикл")),
		"validate: цикл A ↔ B с мотором на auto-якоре — без бесконечной рекурсии, ошибка «цикл»", Array(errs_y))
	# длинная цепь без цикла (6 конечностей на auto-концах, узлов мало): защита от цикла её не режет — группы до конца
	var lng := BodyBlueprint.new()
	lng.id = "kit_probe_long_chain"
	var ln: Array[Dictionary] = [{"uid": "T", "part": "kit_core_barrel", "parent": "", "anchor": "", "name": "Torso"},
		{"uid": "H", "part": "kit_head_round", "parent": "T", "anchor": "Anchor_Neck"}]
	var par := "T"
	var an := "Anchor_Shoulder_L"
	for u in ["1", "2", "3", "4", "5", "6"]:
		ln.append({"uid": u, "part": "kit_limb_thin_s", "parent": par, "anchor": an})
		par = u
		an = "Anchor_End"
	lng.nodes = ln
	var groups: Array = []
	for u in ["1", "2", "3", "4", "5", "6"]:
		groups.append(lng.joint_group_of(u))
	_check(lng.validate().is_empty() and groups == ["Shoulder", "Elbow", "Wrist", "Wrist", "Wrist", "Wrist"],
		"validate: длинная цепь (6 конечностей, 8 узлов) — группы суставов до конца цепи", [Array(lng.validate()), groups])


# --- кукла кита против чертежа ---

## Сборка против чертежа (сразу после add_child: Doll._ready уже прошёл, физики ещё не было). Возвращает сводку для отчёта.
func _check_doll(id: String, d: ModularDoll, bp_id: String) -> Dictionary:
	var bp := d.blueprint
	var r := {
		"title": bp.title, "energy": bp.energy_used(), "budget": bp.energy_budget, "mass": snappedf(d.total_mass, 0.01),
		"bodies": d.parts.size(), "joints": d.joints.size(), "control": Array(d.control_part_names()),
	}
	var errs := bp.validate()
	_check(errs.is_empty() and d.build_errors.is_empty() and bp.id == bp_id, id + ": чертёж собирается (validate пуст)",
		[bp.id, Array(errs), Array(d.build_errors)])
	var sorted := bp.sorted_nodes()
	var fixed := 0
	for n in sorted:
		if bp.is_fixed(String(n["uid"])):
			fixed += 1
	var nn := bp.nodes.size()
	_check(d.parts.size() == nn - fixed and d.joints.size() == nn - fixed - 1, id + ": тел = узлов − fixed, суставов = тел − 1",
		[d.parts.size(), d.joints.size(), nn, fixed])
	_check(bp.energy_used() <= bp.energy_budget, id + ": энергия в бюджете", [bp.energy_used(), bp.energy_budget])
	var ctrl := d.control_part_names()
	var ctrl_ok := ctrl.size() == bp.control.size()
	for cn in ctrl:
		ctrl_ok = ctrl_ok and d.parts.has(cn)
	_check(ctrl_ok, id + ": управляемые тела есть", Array(ctrl))
	var pairs := {}
	for e in (d.get("_muscle_pairs") as Array):
		pairs[String(e[Doll.MP_NAME])] = e
	var mirror := {}
	var exp_mass := {}
	var exp_iron := {}
	var exp_mult := {}
	var bad_node: Array = []
	var bad_joint: Array = []
	var bad_gain: Array = []
	var bad_base: Array = []
	var bad_con: Array = []
	var connectors := 0
	var repainted := 0
	for n in sorted:
		var uid := String(n["uid"])
		var def := BodyBlueprint.part_def(String(n["part"]))
		var parent := String(n.get("parent", ""))
		var a: Dictionary = {}
		var pdef: PartDef = null
		mirror[uid] = false
		if parent != "":
			pdef = BodyBlueprint.part_def(String(bp.find_node(parent).get("part", "")))
			a = BodyBlueprint.part_anchors(pdef).get(String(n.get("anchor", "")), {})
			mirror[uid] = bool(mirror.get(parent, false)) != bool(a.get("mirror", false))
		var bn := String(d.uid_body.get(uid, ""))
		var body := d.parts.get(bn) as RigidBody3D
		if body == null:
			bad_node.append("%s: нет тела «%s»" % [uid, bn])
			continue
		var fixed_n := bp.is_fixed(uid)
		var nm := bp.node_mass(uid)
		exp_mass[bn] = float(exp_mass.get(bn, 0.0)) + nm
		if bp.node_iron(uid):
			exp_iron[bn] = float(exp_iron.get(bn, 0.0)) + nm
		if fixed_n:
			if PartDef.FIXED_KINDS.has(def.kind) and not is_equal_approx(def.body_mult, 1.0):
				exp_mult[bn] = float(exp_mult.get(bn, 1.0)) * def.body_mult
		else:
			if def.base_mat != "":
				var mdn := MaterialDef.get_def(bp.node_mat(uid))
				if mdn != null:
					exp_mult[bn] = float(exp_mult.get(bn, 1.0)) * mdn.body_mult
			exp_mult[bn] = float(exp_mult.get(bn, 1.0)) * def.hit_mult   # форма своего узла (шипы, рога, клешня)
		# поверхности Base_* детали — surface материала узла (слитая деталь: меш переехал в хозяина как Mesh_<uid>)
		if def.base_mat != "":
			var mesh := body.get_node_or_null(("Mesh_" + uid) if fixed_n else "Mesh")
			var want := MaterialDef.get_def(bp.node_mat(uid))
			var got := _base_surfaces(mesh)
			if bp.node_mat(uid) != def.base_mat:
				repainted += 1
			if want == null or want.surface == null or got.is_empty():
				bad_base.append("%s (%s): Base_* нет или нет материала «%s»" % [uid, bn, bp.node_mat(uid)])
			else:
				for pth in got:
					if String(pth) != want.surface.resource_path:
						bad_base.append("%s (%s): %s ≠ %s" % [uid, bn, String(pth).get_file(), want.surface.resource_path.get_file()])
		# коннектор: у детали с connector на суставе не weld — Connector_<uid> на её теле, иначе нигде
		var jt := bp.joint_type_of(uid)
		var cpath := KitJoint.connector_scene(jt)
		var want_con := parent != "" and not fixed_n and def.connector and cpath != "" and ResourceLoader.exists(cpath)
		var cname := "Connector_" + uid
		if not want_con:
			if d.find_child(cname, true, false) != null:
				bad_con.append("%s: лишний %s (connector %s, тип «%s»)" % [uid, cname, def.connector, jt])
		else:
			connectors += 1
			bad_con.append_array(_connector_errors(d, body.get_node_or_null(cname) as Node3D, uid, a, bp.joint_group_of(uid), jt, bn))
		if parent == "" or fixed_n:
			continue
		# сустав: meta joint_type, трение × тип, лимиты KitJoint.limits (левая сторона [−hi, −lo], зеркальная [lo, hi])
		var jn := String(d.uid_joint.get(uid, ""))
		var j := d.joints.get(jn) as Generic6DOFJoint3D
		if j == null:
			bad_joint.append("%s: нет сустава «%s»" % [uid, jn])
			continue
		var g := bp.joint_group_of(uid)
		var ti := KitJoint.info(jt)
		if String(j.get_meta("joint_type", "")) != jt:
			bad_joint.append("%s joint_type «%s» ≠ «%s»" % [jn, j.get_meta("joint_type", ""), jt])
		var ff := float((Tuning.MUSCLE_GROUPS[g] as Dictionary)["friction_factor"]) * float(ti.get("friction", 1.0))
		if absf(float(j.get_meta("friction_factor", -1.0)) - ff) > 1e-5 \
				or absf(float(j.get("angular_motor_z/force_limit")) - Tuning.JOINT_FRICTION * ff) > 1e-5:
			bad_joint.append("%s трение %s / %s ≠ %.3f" % [jn, j.get_meta("friction_factor", null), j.get("angular_motor_z/force_limit"), ff])
		var lim := KitJoint.limits(jt, ModularDoll._limits_for(a, g, def, pdef))
		var l := lim if bool(mirror[uid]) else Vector2(-lim.y, -lim.x)
		var lo := rad_to_deg(float(j.get("angular_limit_z/lower_angle")))
		var hi := rad_to_deg(float(j.get("angular_limit_z/upper_angle")))
		if absf(lo - l.x) > 1e-3 or absf(hi - l.y) > 1e-3:
			bad_joint.append("%s лимиты [%.1f, %.1f] ≠ [%.1f, %.1f]" % [jn, lo, hi, l.x, l.y])
		# мышца: группа × множители типа, c = 2ζ√(k·I) × √k-множителя; free — 0
		var e: Array = pairs.get(jn, [])
		if e.is_empty():
			bad_gain.append(jn + ": нет пары мышцы")
			continue
		var G: Dictionary = Tuning.MUSCLE_GROUPS[g]
		var km := float(ti.get("k", 1.0))
		var k_exp := float(G["k"]) * km
		var t_exp := float(G["tmax"]) * float(ti.get("tmax", 1.0))
		var c_exp := 2.0 * float(G.get("zeta", Tuning.MUSCLE_ZETA)) * sqrt(float(G["k"]) * d._pair_inertia(jn, float(G["inertia"]))) * sqrt(km)
		if km <= 0.0:
			k_exp = 0.0
			t_exp = 0.0
			c_exp = 0.0
		if absf(float(e[Doll.MP_K]) - k_exp) > 1e-4 or absf(float(e[Doll.MP_TMAX]) - t_exp) > 1e-4 or absf(float(e[Doll.MP_C]) - c_exp) > 1e-4:
			bad_gain.append("%s (%s): k/c/tmax %.3f/%.3f/%.3f ≠ %.3f/%.3f/%.3f" % [jn, jt, e[Doll.MP_K], e[Doll.MP_C], e[Doll.MP_TMAX],
				k_exp, c_exp, t_exp])
	# по телам: масса, meta material, meta body_mult
	var bad_mass: Array = []
	var bad_iron: Array = []
	var bad_mult: Array = []
	var bad_grip: Array = []
	var iron_kg := {}
	var mults := {}
	for bn in d.parts:
		var b := d.parts[bn] as RigidBody3D
		# хват оружия (WeaponPickup.hand_grip_global = кисть.to_global(hand_grip_offset)) — в ладони, не в запястье
		if ModularDoll.base_name(String(bn)) == "Hand" and not _inside_shapes(b, grip_offset):
			bad_grip.append("%s %s" % [bn, _shape_boxes(b)])
		if absf(b.mass - float(exp_mass.get(bn, -1.0))) > EPS:
			bad_mass.append("%s %.3f ≠ %.3f" % [bn, b.mass, exp_mass.get(bn, -1.0)])
		var ik := float(exp_iron.get(bn, 0.0))
		if not b.has_meta("material") or typeof(b.get_meta("material")) != TYPE_FLOAT or absf(float(b.get_meta("material")) - ik) > EPS:
			bad_iron.append("%s %s ≠ %.3f" % [bn, b.get_meta("material", null), ik])
		if ik > 0.0:
			iron_kg[bn] = snappedf(ik, 0.01)
		var base := Damage.body_mult_of(String(bn))
		var want := base * float(exp_mult.get(bn, 1.0))
		var has := b.has_meta("body_mult")
		var ok := not has if is_equal_approx(want, base) else (has and absf(float(b.get_meta("body_mult")) - want) < EPS)
		if not ok or absf(Damage.body_mult_of_body(b) - want) > EPS:
			bad_mult.append("%s %s ≠ %.3f (по имени %.3f)" % [bn, b.get_meta("body_mult", null), want, base])
		if has:
			mults[bn] = snappedf(float(b.get_meta("body_mult")), 0.001)
	_check(bad_node.is_empty(), id + ": тело каждого узла есть (uid_body)", bad_node)
	_check(bad_mass.is_empty(), id + ": масса тела = Σ node_mass (§4)", bad_mass)
	_check(absf(d.total_mass - bp.total_mass()) < 1e-3, id + ": total_mass = BodyBlueprint.total_mass()", [d.total_mass, bp.total_mass()])
	_check(bad_iron.is_empty(), id + ": meta material = кг железа (§5.4)", bad_iron)
	_check(bad_mult.is_empty(), id + ": meta body_mult (§5.4) и Damage.body_mult_of_body", bad_mult)
	_check(bad_grip.is_empty(), id + ": хват WeaponPickup %s внутри формы каждой кисти" % grip_offset, bad_grip)
	_check(bad_joint.is_empty(), id + ": суставы — joint_type, трение × тип, лимиты (§5.2)", bad_joint)
	_check(bad_gain.is_empty(), id + ": мышцы — k / tmax × тип, c × √k, free — 0 (§5.4)", bad_gain)
	_check(bad_base.is_empty(), id + ": поверхности Base_* = surface материала узла (§4)", bad_base)
	_check(bad_con.is_empty(), id + ": Connector_<uid> на суставах (§5.4)", bad_con)
	var all_con := d.find_children("Connector_*", "", true, false)
	_check(all_con.size() == connectors, id + ": Connector_* только на суставах с коннектором", [all_con.size(), connectors])
	var sh := _shirt_check(d, d.player_index)
	_check(int(sh[0]) > 0 and (sh[1] as Array).is_empty(), id + ": все Shirt_* в цвете игрока %d после _ready" % d.player_index,
		[sh[0], (sh[1] as Array).slice(0, 4)])
	r["connectors"] = connectors
	r["shirt_surfaces"] = sh[0]
	r["repainted_nodes"] = repainted
	r["iron_kg"] = iron_kg
	r["body_mult"] = mults
	r["joint_types"] = _joint_types(d)
	return r


## Проверки одного коннектора: не тело, без коллизий, meta, точка сустава (по кадрам сборки), масштаб, Shirt_Kit в цвет игрока.
func _connector_errors(d: ModularDoll, con: Node3D, uid: String, a: Dictionary, g: String, jt: String, bn: String) -> Array:
	if con == null:
		return ["%s: нет Connector_%s на %s" % [uid, uid, bn]]
	var out: Array = []
	if con is CollisionObject3D or _collision_count(con) > 0:
		out.append(uid + ": у коннектора есть коллизии")
	if not bool(con.get_meta("rig_mesh", false)):
		out.append(uid + ": нет meta rig_mesh")
	if String(con.get_meta("connector_type", "")) != String(KitJoint.info(jt).get("connector", "")):
		out.append("%s: connector_type «%s» ≠ тип «%s»" % [uid, con.get_meta("connector_type", ""), jt])
	var j := d.joints.get(String(d.uid_joint.get(uid, ""))) as Node3D
	if j != null:
		var want: Vector3 = (d.assembly[bn] as Transform3D).affine_inverse() * j.position
		if con.position.distance_to(want) > 1e-3:
			out.append("%s: не в точке сустава (%.4f м)" % [uid, con.position.distance_to(want)])
	var jr := float(a.get("joint_r", 0.0))
	if jr <= 0.0:
		jr = KitJoint.radius_for(g)
	var sc := con.transform.basis.get_scale()
	if absf(sc.x - jr) > 1e-4 or absf(sc.y - jr) > 1e-4 or absf(sc.z - jr) > 1e-4:
		out.append("%s: масштаб %s ≠ %.3f" % [uid, sc, jr])
	var sh := _shirt_check(con, d.player_index)
	if int(sh[0]) == 0 or not (sh[1] as Array).is_empty():
		out.append("%s: Shirt_Kit коннектора %s" % [uid, sh])
	return out


static func _joint_types(d: Doll) -> Dictionary:
	var out := {}
	for jn in d.joints:
		var t := String((d.joints[jn] as Node).get_meta("joint_type", ""))
		if t != "pin":
			out[jn] = t
	return out


static func _pair(d: Doll, jn: String) -> Array:
	for e in (d.get("_muscle_pairs") as Array):
		if String(e[Doll.MP_NAME]) == jn:
			return e
	return []


# --- кукла-материал: kit_human + mat (§4, §5.4, §6) ---

func _mat_test(pos: Vector3) -> void:
	var P := "mat_test"
	var bp := _copy_bp(KIT_HUMAN_BP, "kit_probe_mats")
	bp.find_node("1")["mat"] = "iron"      # плечо L — железо, на нём шипы
	bp.find_node("4")["mat"] = "rubber"    # бедро L — резина
	bp.find_node("A")["mat"] = "brass"     # бедро R — латунь (тяжёлая, но не железо)
	bp.nodes.append({"uid": "D", "part": "kit_deco_spikes_s", "parent": "1", "anchor": "Anchor_Deco"})
	var arm := BodyBlueprint.part_def("kit_human_upper_arm")
	var leg := BodyBlueprint.part_def("kit_human_upper_leg")
	var spikes := BodyBlueprint.part_def("kit_deco_spikes_s")
	var iron := MaterialDef.get_def("iron")
	var rubber := MaterialDef.get_def("rubber")
	var brass := MaterialDef.get_def("brass")
	if not _check(arm != null and leg != null and spikes != null and iron != null and rubber != null and brass != null,
			P + ": есть kit_human_upper_arm / _upper_leg, kit_deco_spikes_s, материалы iron / rubber / brass"):
		return
	var base_arm := MaterialDef.get_def(arm.base_mat)
	var base_leg := MaterialDef.get_def(leg.base_mat)
	var d := _spawn_bp(bp, pos, 2)
	var r := _check_doll(P, d, bp.id)
	var ua := d.parts.get("UpperArm_L") as RigidBody3D
	var ur := d.parts.get("UpperArm_R") as RigidBody3D
	var ll := d.parts.get("UpperLeg_L") as RigidBody3D
	var lr := d.parts.get("UpperLeg_R") as RigidBody3D
	if not _check(ua != null and ur != null and ll != null and lr != null and base_arm != null and base_leg != null, P + ": тела собраны"):
		report[P] = r
		return
	_watch(P, d)
	# масса = PartDef.mass × density / density base_mat (+ слитые шипы)
	var m_ua := arm.mass * iron.density / base_arm.density + spikes.mass
	var m_ll := leg.mass * rubber.density / base_leg.density
	var m_lr := leg.mass * brass.density / base_leg.density
	_check(absf(ua.mass - m_ua) < EPS and absf(ll.mass - m_ll) < EPS and absf(lr.mass - m_lr) < EPS and absf(ur.mass - arm.mass) < EPS,
		P + ": масса × density (железо 2.2 + шипы, резина 0.8, латунь 2.4, дерево как было)", [ua.mass, m_ua, ll.mass, m_ll, lr.mass, m_lr, ur.mass])
	# физматериал своего тела — материала узла; у непокрашенного — как у сцены детали (= wood_*)
	var fr := (arm.scene.instantiate() as RigidBody3D)
	var pm0 := fr.physics_material_override
	var f0 := [pm0.friction, pm0.bounce] if pm0 != null else [-1.0, -1.0]
	fr.free()
	var ok_pm := true
	var pm_info: Array = []
	for e in [[ua, iron], [ll, rubber], [lr, brass]]:
		var pm := (e[0] as RigidBody3D).physics_material_override
		var md := e[1] as MaterialDef
		ok_pm = ok_pm and pm != null and is_equal_approx(pm.friction, md.friction) and is_equal_approx(pm.bounce, md.bounce)
		pm_info.append([md.id, pm.friction if pm else -1.0, pm.bounce if pm else -1.0])
	var pmr := ur.physics_material_override
	ok_pm = ok_pm and pmr != null and pmr.friction == f0[0] and pmr.bounce == f0[1]
	_check(ok_pm, P + ": PhysicsMaterial = friction / bounce материала узла, у дерева — как в сцене", [pm_info, f0])
	# Base_* заменена, Shirt_Kit — нет (и в цвете игрока)
	var sw := [[ua.get_node_or_null("Mesh"), iron], [ll.get_node_or_null("Mesh"), rubber], [lr.get_node_or_null("Mesh"), brass],
		[ur.get_node_or_null("Mesh"), base_arm], [ua.get_node_or_null("Mesh_D"), iron]]
	var bad_sw: Array = []
	for e in sw:
		var got := _base_surfaces(e[0] as Node)
		var want: String = (e[1] as MaterialDef).surface.resource_path
		if got.is_empty() or got.any(func(x: Variant) -> bool: return String(x) != want):
			bad_sw.append([str((e[0] as Node).name) if e[0] != null else "null", got, want.get_file()])
	_check(bad_sw.is_empty(), P + ": Base_* → Base_Iron / Base_Pink / Base_Brass, у дерева Base_Wood, у шипов Base_Iron", bad_sw)
	var shirt := _shirt_check(ua.get_node_or_null("Mesh"), d.player_index)
	_check(int(shirt[0]) > 0 and (shirt[1] as Array).is_empty(), P + ": Shirt_Kit на перекрашенном плече остался и в цвете игрока", shirt)
	# meta material = кг железа: плечо + шипы; резина и латунь — 0
	var iron_ua := arm.mass * iron.density / base_arm.density + spikes.mass
	_check(absf(float(ua.get_meta("material", -1.0)) - iron_ua) < EPS and float(ll.get_meta("material", -1.0)) == 0.0
		and float(lr.get_meta("material", -1.0)) == 0.0 and float(ur.get_meta("material", -1.0)) == 0.0,
		P + ": meta material — кг железа (плечо + шипы), латунь и резина 0", [ua.get_meta("material", null), iron_ua,
		lr.get_meta("material", null)])
	# meta body_mult: железо × шипы, резина, латунь; у дерева meta нет
	var bm_ua := Damage.body_mult_of("UpperArm_L") * iron.body_mult * spikes.body_mult
	var bm_ll := Damage.body_mult_of("UpperLeg_L") * rubber.body_mult
	var bm_lr := Damage.body_mult_of("UpperLeg_R") * brass.body_mult
	_check(absf(float(ua.get_meta("body_mult", -1.0)) - bm_ua) < EPS and absf(float(ll.get_meta("body_mult", -1.0)) - bm_ll) < EPS
		and absf(float(lr.get_meta("body_mult", -1.0)) - bm_lr) < EPS and not ur.has_meta("body_mult")
		and is_equal_approx(spikes.body_mult, 1.25), P + ": meta body_mult (железо 1.2 × шипы 1.25, резина 0.8, латунь 1.2)",
		[ua.get_meta("body_mult", null), bm_ua, ll.get_meta("body_mult", null), bm_ll, lr.get_meta("body_mult", null), bm_lr])
	var sh_host := 0
	for c in ua.get_children():
		if c is CollisionShape3D and String(c.name).ends_with("_D"):
			sh_host += 1
	_check(sh_host > 0, P + ": формы шипов переехали в плечо (§6: декор бьётся)", sh_host)
	r["UpperArm_L"] = {"mass": ua.mass, "material": ua.get_meta("material", null), "body_mult": ua.get_meta("body_mult", null)}
	report[P] = r


# --- кукла-шарниры: kit_human + joint (§5.2, §5.4) ---

func _joint_test(pos: Vector3) -> void:
	var P := "joint_test"
	var bp := _copy_bp(KIT_HUMAN_BP, "kit_probe_joints")
	bp.find_node("3")["joint"] = "free"      # Wrist_L: кисть болтается
	bp.find_node("2")["joint"] = "spring"    # Elbow_L: пружина
	bp.find_node("7")["joint"] = "motor"     # Shoulder_R: мотор
	bp.find_node("8")["joint"] = "weld"      # LowerArm_R приварено к UpperArm_R
	var ref: ModularDoll = presets.get("kit_human")
	if not _check(ref != null, P + ": нужен пресет kit_human"):
		return
	# энергия по расстоянию (WORKSHOP_V3.md §2): шарнир дорожает вместе с узлом — пружина 2 на локте, мотор 8 на плече ×reach_mult
	var reach := ref.blueprint.node_reach()
	var want := ref.blueprint.energy_used()
	for jj in [["2", 2], ["7", 8]]:
		var base := BodyBlueprint.node_base_energy(ref.blueprint.find_node(jj[0]))
		want += BodyBlueprint.reach_cost(base + int(jj[1]), float(reach[jj[0]])) - BodyBlueprint.reach_cost(base, float(reach[jj[0]]))
	_check(bp.energy_used() == want, P + ": энергия + пружина 2 + мотор 8 (× вынос узла)", [bp.energy_used(), want])
	var d := _spawn_bp(bp, pos, 3)
	var r := _check_doll(P, d, bp.id)
	_watch(P, d)
	var G: Dictionary = Tuning.MUSCLE_GROUPS
	# weld: тел и суставов на один меньше, предплечье слито с плечом, запястье на плече, коннектора нет
	var ur := d.parts.get("UpperArm_R") as RigidBody3D
	var wr := d.joints.get("Wrist_R") as Generic6DOFJoint3D
	var m_w := BodyBlueprint.part_def("kit_human_upper_arm").mass + BodyBlueprint.part_def("kit_human_lower_arm").mass
	_check(d.parts.size() == ref.parts.size() - 1 and d.joints.size() == ref.joints.size() - 1 and not d.parts.has("LowerArm_R")
		and not d.joints.has("Elbow_R") and String(d.uid_body.get("8", "")) == "UpperArm_R", P + ": weld — тел и суставов на один меньше",
		[d.parts.size(), ref.parts.size(), d.joints.size(), ref.joints.size(), d.uid_body.get("8", "")])
	_check(ur != null and absf(ur.mass - m_w) < EPS and ur.get_node_or_null("Mesh_8") != null and wr != null
		and wr.node_a == NodePath("../UpperArm_R"), P + ": weld — масса и меш предплечья в плече, Wrist_R висит на плече",
		[ur.mass if ur else -1.0, m_w, str(wr.node_a) if wr else ""])
	_check(d.find_child("Connector_8", true, false) == null, P + ": weld — коннектора нет")
	# weld держит позу покоя сустава (§5.2, ModularDoll._weld_rest): предплечье приварено под углом локтя (Tuning.POSE Elbow,
	# правая сторона — знак минус) — запястье там, где у kit_human после поворота локтя на угол покоя вокруг точки локтя
	var n8 := bp.find_node("8")
	var a8: Dictionary = BodyBlueprint.part_anchors(BodyBlueprint.part_def(String(bp.find_node("7")["part"]))).get(String(n8["anchor"]), {})
	var g8 := bp.anchor_group_of("8")
	var rel8 := float(n8["rest_deg"]) if n8.has("rest_deg") else (float(Tuning.POSE[g8]) if bool(a8.get("rest_from_pose", false))
		and Tuning.POSE.has(g8) else float(a8.get("rest_deg", 0.0)))
	var js_w := d.joints.get("Shoulder_R") as Node3D
	var js_r := ref.joints.get("Shoulder_R") as Node3D
	var je_r := ref.joints.get("Elbow_R") as Node3D
	var jw_r := ref.joints.get("Wrist_R") as Node3D
	if _check(js_w != null and js_r != null and je_r != null and jw_r != null and wr != null and absf(rel8) > 1.0,
			P + ": weld — есть суставы для сверки позы (угол покоя локтя ≠ 0)", [g8, rel8]):
		var rot := Basis(Vector3(0, 0, 1), deg_to_rad(-rel8))   # UpperArm_R — зеркальная сторона
		var want_w := (je_r.position - js_r.position) + rot * (jw_r.position - je_r.position)
		var got_w := wr.position - js_w.position
		r["weld_rest_deg"] = rel8
		r["weld_wrist_err_m"] = snappedf(got_w.distance_to(want_w), 0.0001)
		_check(got_w.distance_to(want_w) < 1e-3, P + ": weld — предплечье в позе покоя локтя (%.0f°), запястье на месте" % rel8,
			[got_w, want_w])
	# free: k = c = tmax = 0, лимиты ±160°, трение × 0.3
	var jf := d.joints.get("Wrist_L") as Generic6DOFJoint3D
	var ef := _pair(d, "Wrist_L")
	_check(not ef.is_empty() and float(ef[Doll.MP_K]) == 0.0 and float(ef[Doll.MP_C]) == 0.0 and float(ef[Doll.MP_TMAX]) == 0.0,
		P + ": free — k = c = tmax = 0", ef.slice(3, 6))
	_check(jf != null and (_lim_deg(jf) - Vector2(-160, 160)).length() < 1e-3 and is_equal_approx(float(jf.get_meta("friction_factor", -1.0)),
		float(G["Wrist"]["friction_factor"]) * 0.3), P + ": free — лимиты ±160°, трение × 0.3",
		[_lim_deg(jf) if jf else Vector2.ZERO, jf.get_meta("friction_factor", null) if jf else null])
	# spring: k × 0.45, tmax × 0.6, лимиты группы шире на 20° (локоть 0…140 → −20…160; левая сторона у Jolt [−160, 20])
	var js := d.joints.get("Elbow_L") as Generic6DOFJoint3D
	var es := _pair(d, "Elbow_L")
	var el: Vector2 = ModularDoll.JOINT_LIMITS["Elbow"]
	_check(not es.is_empty() and is_equal_approx(float(es[Doll.MP_K]), 0.45 * float(G["Elbow"]["k"]))
		and is_equal_approx(float(es[Doll.MP_TMAX]), 0.6 * float(G["Elbow"]["tmax"])), P + ": spring — k × 0.45, tmax × 0.6", es.slice(3, 6))
	_check(js != null and (_lim_deg(js) - Vector2(-(el.y + 20.0), -(el.x - 20.0))).length() < 1e-3
		and is_equal_approx(float(js.get_meta("friction_factor", -1.0)), float(G["Elbow"]["friction_factor"]) * 0.5),
		P + ": spring — лимиты шире на 20°, трение × 0.5", [_lim_deg(js) if js else Vector2.ZERO, el])
	# motor: k × 1.8, tmax × 2.2, c × √1.8, трение × 1.3; после set_muscle_joint — 1.8 × override, после clear — снова группа
	var jm := d.joints.get("Shoulder_R") as Generic6DOFJoint3D
	var em := _pair(d, "Shoulder_R")
	var ks := float(G["Shoulder"]["k"])
	var ts := float(G["Shoulder"]["tmax"])
	var cs := 2.0 * float(G["Shoulder"].get("zeta", Tuning.MUSCLE_ZETA)) * sqrt(ks * d._pair_inertia("Shoulder_R", float(G["Shoulder"]["inertia"])))
	_check(not em.is_empty() and is_equal_approx(float(em[Doll.MP_K]), 1.8 * ks) and is_equal_approx(float(em[Doll.MP_TMAX]), 2.2 * ts)
		and absf(float(em[Doll.MP_C]) - cs * sqrt(1.8)) < 1e-5, P + ": motor — k × 1.8, tmax × 2.2, c × √1.8",
		[em.slice(3, 6), 1.8 * ks, 2.2 * ts, cs * sqrt(1.8)])
	_check(jm != null and is_equal_approx(float(jm.get_meta("friction_factor", -1.0)), float(G["Shoulder"]["friction_factor"]) * 1.3),
		P + ": motor — трение × 1.3", jm.get_meta("friction_factor", null) if jm else null)
	d.set_muscle_joint("Shoulder_R", 10.0)
	var k_set := float(_pair(d, "Shoulder_R")[Doll.MP_K])
	var t_set := float(_pair(d, "Shoulder_R")[Doll.MP_TMAX])
	d.clear_muscle_joint("Shoulder_R")
	var k_clr := float(_pair(d, "Shoulder_R")[Doll.MP_K])
	_check(is_equal_approx(k_set, 18.0) and is_equal_approx(t_set, 2.2 * ts) and is_equal_approx(k_clr, 1.8 * ks),
		P + ": motor — после set_muscle_joint(10) k = 18, после clear_muscle_joint снова 1.8 × группа", [k_set, t_set, k_clr])
	d.set_muscle_joint("Wrist_L", 10.0)
	var kf_set := float(_pair(d, "Wrist_L")[Doll.MP_K])
	d.clear_muscle_joint("Wrist_L")
	d.set_muscle_group("Elbow", 30.0)
	var ks_grp := float(_pair(d, "Elbow_L")[Doll.MP_K])
	d.set_muscle_group("Elbow", float(G["Elbow"]["k"]), float(G["Elbow"]["tmax"]))
	var ks_back := float(_pair(d, "Elbow_L")[Doll.MP_K])
	_check(kf_set == 0.0 and is_equal_approx(ks_grp, 0.45 * 30.0) and is_equal_approx(ks_back, 0.45 * float(G["Elbow"]["k"])),
		P + ": free остаётся 0 после set_muscle_joint, spring × 0.45 после set_muscle_group", [kf_set, ks_grp, ks_back])
	# pin — числа kit_human (плечо L)
	_check(_pair(d, "Shoulder_L").slice(3, 6) == _pair(ref, "Shoulder_L").slice(3, 6), P + ": pin — как у kit_human",
		[_pair(d, "Shoulder_L").slice(3, 6), _pair(ref, "Shoulder_L").slice(3, 6)])
	report[P] = r


static func _lim_deg(j: Generic6DOFJoint3D) -> Vector2:
	return Vector2(rad_to_deg(float(j.get("angular_limit_z/lower_angle"))), rad_to_deg(float(j.get("angular_limit_z/upper_angle"))))


# --- рука мышью (ArmAssist) на пресетах кита ---

func _arm_attach(d: ModularDoll) -> ArmAssist:
	var a := ArmAssist.new()
	a.name = "ArmAssist"
	a.show_hints = false
	d.add_child(a)
	return a


## Статика (кукла собрана и сразу удалена): хват и досягаемость каждого пресета против human; динамика ARM_DYNAMIC — куклы остаются
## до ARM_END_S (_arm_tick).
func _arm_setup() -> void:
	_floor(Vector3(ARM_X0 + 30.0, 0, 0), 80.0)
	var r := {}
	report["arm_assist"] = r
	var h := _spawn_scene(HUMAN_SCENE, Vector3(ARM_X0, 40.0, 0), true, 0)   # статика — в воздухе, врозь: удаляется в этом же кадре
	var ha := _arm_attach(h)
	var human_reach := ha.reach
	r["human"] = {"part": ha.part_name, "reach": snappedf(ha.reach, 0.001), "grip": ha.grip_local}
	h.queue_free()
	var i := 1
	for id in PRESETS:
		var d := _spawn_scene(PRESETS[id], Vector3(ARM_X0 + 3.0 * i, 40.0, 0), true, 0)
		i += 1
		if d == null:
			continue
		var a := _arm_attach(d)
		var P := "arm %s" % id
		r[id] = {"part": a.part_name, "reach": snappedf(a.reach, 0.001), "grip": a.grip_local}
		if _check(a.part != null, P + ": ArmAssist нашёл управляемое тело", [a.part_name, Array(d.control_part_names())]):
			var g := a.part.get_node_or_null("Grip") as Marker3D
			if a.part_name.begins_with("Hand"):
				_check(_inside_shapes(a.part, a.grip_local) and a.reach >= human_reach - ARM_REACH_TOL,
					P + ": рука мышью на кисти — хват в ладони, досягаемость ≥ human − %.2f м" % ARM_REACH_TOL,
					[a.grip_local, snappedf(a.reach, 0.001), snappedf(human_reach, 0.001), _shape_boxes(a.part)])
			elif ARM_DYNAMIC.has(id):
				_check(g != null and a.grip_local.distance_to(g.position) < 1e-4 and a.reach >= ARM_REACH_MIN,
					P + ": рука мышью на предплечье — хват в Grip на конце, досягаемость ≥ %.2f м" % ARM_REACH_MIN,
					[a.grip_local, g.position if g else null, snappedf(a.reach, 0.001)])
		d.queue_free()
	var k := 0
	for id in ARM_DYNAMIC:
		for off in ARM_TARGETS:
			var d := _spawn_scene(PRESETS[id], Vector3(ARM_X0 + 4.0 * k, 0, 0), true, 0)
			k += 1
			if d == null:
				continue
			arm_runs.append([id, d, _arm_attach(d), off])


## Каждый тик покоя: цель — плечо + смещение (за плечом, как мышь у плеча); в ARM_END_S — ошибка хвата, куклы удаляются.
func _arm_tick() -> void:
	if arm_done or t < ARM_START_S:
		return
	if t < ARM_END_S:
		for e in arm_runs:
			var a := e[2] as ArmAssist
			if is_instance_valid(a) and a.part != null:
				a.set_target_override(a.root_point() + (e[3] as Vector3))
		return
	arm_done = true
	var per := {}
	for e in arm_runs:
		var id := String(e[0])
		var a := e[2] as ArmAssist
		if not per.has(id):
			per[id] = []
		if not is_instance_valid(a) or a.part == null:
			(per[id] as Array).append(INF)
			continue
		var want := a.root_point() + (e[3] as Vector3)
		var g := a.grip_global()
		(per[id] as Array).append(Vector2(g.x - want.x, g.y - want.y).length())
		a.clear_target_override()
		(e[1] as Node).queue_free()
	arm_runs.clear()
	for id in per:
		var errs: Array = per[id]
		var mx := 0.0
		var sum := 0.0
		for x in errs:
			mx = maxf(mx, float(x))
			sum += float(x)
		var mean := sum / maxf(errs.size(), 1)
		var rr: Dictionary = report["arm_assist"].get(id, {})
		rr["target_err_m"] = errs.map(func(x: Variant) -> float: return snappedf(float(x), 0.001))
		rr["target_err_max_m"] = snappedf(mx, 0.001)
		rr["target_err_mean_m"] = snappedf(mean, 0.001)
		report["arm_assist"][id] = rr
		_check(errs.size() == ARM_TARGETS.size() and mx <= ARM_MAX_ERR and mean <= ARM_MEAN_ERR,
			"arm %s: цель в 0.5 м от плеча (%d направлений) — хват у цели за %.0f с: ошибка ≤ %.2f м, средняя ≤ %.2f м" % [id,
			ARM_TARGETS.size(), ARM_END_S - ARM_START_S, ARM_MAX_ERR, ARM_MEAN_ERR], rr["target_err_m"])


# --- старые детали ---

func _check_legacy(id: String, d: ModularDoll) -> void:
	var P := "legacy " + id
	var cons := d.find_children("Connector_*", "", true, false)
	var mult: Array = []
	var mat: Array = []
	var jt: Array = []
	for bn in d.parts:
		var b := d.parts[bn] as Node
		if b.has_meta("body_mult"):
			mult.append(bn)
		if not b.has_meta("material") or typeof(b.get_meta("material")) != TYPE_FLOAT:
			mat.append(bn)
	for jn in d.joints:
		if String((d.joints[jn] as Node).get_meta("joint_type", "")) != "pin":
			jt.append(jn)
	_check(d.build_errors.is_empty(), P + ": собирается", Array(d.build_errors))
	_check(cons.is_empty(), P + ": у старых деталей нет коннекторов", cons.size())
	_check(mult.is_empty(), P + ": нет meta body_mult", mult)
	_check(mat.is_empty(), P + ": meta material (float) у каждого тела", mat)
	_check(jt.is_empty(), P + ": все суставы pin (meta joint_type)", jt)
	report["legacy"][id] = {"bodies": d.parts.size(), "connectors": cons.size(), "body_mult": mult.size()}


# --- kit_human против human (подход tests/body_probe: human против doll.tscn) ---

func _compare_kit_human() -> void:
	var a := human_ref
	var b: ModularDoll = presets["kit_human"]
	var P := "kit_human = human"
	var r := {}
	_check(a.parts.keys() == b.parts.keys(), P + ": тела по порядку", [b.parts.keys(), a.parts.keys()])
	_check(a.joints.keys() == b.joints.keys(), P + ": суставы по порядку", [b.joints.keys(), a.joints.keys()])
	r["total_mass"] = [a.total_mass, b.total_mass]
	_check(absf(a.total_mass - b.total_mass) < EPS, P + ": total_mass", r["total_mass"])
	var bad: Array = []
	for pn in a.parts:
		if not b.parts.has(pn):
			continue
		var pa := a.parts[pn] as RigidBody3D
		var pb := b.parts[pn] as RigidBody3D
		if absf(pa.mass - pb.mass) > 1e-5:
			bad.append("масса %s %.3f ≠ %.3f" % [pn, pb.mass, pa.mass])
		if absf(pa.linear_damp - pb.linear_damp) > 1e-5 or absf(pa.angular_damp - pb.angular_damp) > 1e-5:
			bad.append("дамп " + pn)
		if pa.axis_lock_linear_z != pb.axis_lock_linear_z or pa.continuous_cd != pb.continuous_cd or pa.can_sleep != pb.can_sleep:
			bad.append("флаги " + pn)
		var fa := pa.physics_material_override
		var fb := pb.physics_material_override
		if fa == null or fb == null or absf(fa.friction - fb.friction) > 1e-5 or absf(fa.bounce - fb.bounce) > 1e-5:
			bad.append("физматериал " + pn)
		if _shape_sig(pa) != _shape_sig(pb):
			bad.append("формы %s %s ≠ %s" % [pn, _shape_sig(pb), _shape_sig(pa)])
		if pa.center_of_mass_mode != pb.center_of_mass_mode or pa.center_of_mass.distance_to(pb.center_of_mass) > 1e-5:
			bad.append("центр масс " + pn)
	_check(bad.is_empty(), P + ": массы, дамп, флаги, физматериал, формы, центр масс", bad)
	var max_pos := 0.0
	for pn in a.assembly:
		if not b.assembly.has(pn):
			continue
		var ta: Transform3D = a.assembly[pn]
		var tb: Transform3D = b.assembly[pn]
		max_pos = maxf(max_pos, ta.origin.distance_to(tb.origin))
		max_pos = maxf(max_pos, (ta.basis.x - tb.basis.x).length() + (ta.basis.y - tb.basis.y).length())
	r["assembly_max_diff_m"] = max_pos
	_check(max_pos <= HUMAN_SPAWN_TOL, P + ": кадры сборки ≤ 1 мм", max_pos)
	var pose_a := a.get_pose()
	var pose_b := b.get_pose()
	var jbad: Array = []
	var max_lim := 0.0
	var max_pose := 0.0
	for jn in a.joints:
		if not b.joints.has(jn):
			continue
		var ja := a.joints[jn] as Generic6DOFJoint3D
		var jb := b.joints[jn] as Generic6DOFJoint3D
		for prop in ["angular_limit_z/lower_angle", "angular_limit_z/upper_angle", "angular_motor_z/force_limit"]:
			max_lim = maxf(max_lim, absf(float(ja.get(prop)) - float(jb.get(prop))))
		if bool(ja.get("angular_motor_z/enabled")) != bool(jb.get("angular_motor_z/enabled")):
			jbad.append("мотор " + jn)
		if absf(float(ja.get_meta("friction_factor", 0.0)) - float(jb.get_meta("friction_factor", -1.0))) > 1e-5:
			jbad.append("friction_factor " + jn)
		if ja.node_a != jb.node_a or ja.node_b != jb.node_b:
			jbad.append("тела " + jn)
		if ja.position.distance_to(jb.position) > HUMAN_SPAWN_TOL:
			jbad.append("точка " + jn)
		if absf(float(ja.get_meta("chain_inertia", 0.0)) - float(jb.get_meta("chain_inertia", -1.0))) > 1e-6:
			jbad.append("chain_inertia " + jn)
		if _pair(a, jn).slice(2, 7) != _pair(b, jn).slice(2, 7):
			jbad.append("мышца %s %s ≠ %s" % [jn, _pair(b, jn).slice(2, 7), _pair(a, jn).slice(2, 7)])
		max_pose = maxf(max_pose, absf(float(pose_a.get(jn, 0.0)) - float(pose_b.get(jn, 999.0))))
	r["limits_max_diff"] = max_lim
	r["pose_max_diff_deg"] = max_pose
	_check(jbad.is_empty(), P + ": суставы — мотор-трение, тела, точки, инерция цепи, мышцы", jbad)
	_check(max_lim <= 1e-4, P + ": лимиты и трение суставов", max_lim)
	_check(max_pose <= 1e-3, P + ": поза покоя", max_pose)
	_check(b.find_children("Connector_*", "", true, false).size() == b.joints.size(), P + ": коннектор на каждом суставе kit_human",
		[b.find_children("Connector_*", "", true, false).size(), b.joints.size()])
	report["kit_human_vs_human"] = r


func _compare_rest() -> void:
	var r: Dictionary = report["kit_human_vs_human"]
	var ns := _pair_diff(human_ns, kit_ns)
	var sp := _pair_diff(human_ref, presets.get("kit_human"))
	r["rest_%.0fs_no_snap_max_diff_m" % HUMAN_REST_S] = snappedf(float(ns[0]), 0.0001)
	r["rest_%.0fs_spawn_in_pose_max_diff_m" % HUMAN_REST_S] = snappedf(float(sp[0]), 0.0001)
	_check(float(ns[0]) <= HUMAN_REST_TOL, "kit_human = human: после %.0f с покоя без спавна в позе (%s)" % [HUMAN_REST_S, ns[1]], ns[0])
	_check(float(sp[0]) <= HUMAN_REST_TOL, "kit_human = human: после %.0f с покоя со спавном в позе (%s)" % [HUMAN_REST_S, sp[1]], sp[0])


## [наибольшее расхождение части относительно корня куклы, м; имя части]
func _pair_diff(a: Doll, b: Doll) -> Array:
	if a == null or b == null:
		return [INF, "нет куклы"]
	var m := 0.0
	var worst := ""
	for pn in a.parts:
		if not b.parts.has(pn):
			continue
		var la := (a.parts[pn] as Node3D).global_position - a.global_position
		var lb := (b.parts[pn] as Node3D).global_position - b.global_position
		var dd := la.distance_to(lb)
		if dd > m:
			m = dd
			worst = pn
	return [m, worst]


static func _shape_sig(b: Node) -> String:
	var out: Array = []
	for c in b.get_children():
		if c is CollisionShape3D:
			var s: Shape3D = (c as CollisionShape3D).shape
			var o := (c as Node3D).position.snappedf(0.0001)
			if s is BoxShape3D:
				out.append("box%s@%s" % [(s as BoxShape3D).size.snappedf(0.0001), o])
			elif s is CapsuleShape3D:
				out.append("cap%.4f/%.4f@%s" % [(s as CapsuleShape3D).radius, (s as CapsuleShape3D).height, o])
			elif s is SphereShape3D:
				out.append("sph%.4f@%s" % [(s as SphereShape3D).radius, o])
			elif s is CylinderShape3D:
				out.append("cyl%.4f/%.4f@%s" % [(s as CylinderShape3D).radius, (s as CylinderShape3D).height, o])
			else:
				out.append(s.get_class() if s != null else "null")
	return ",".join(out)


# --- покой, ввод, KO (как tests/body_probe) ---

## Трекинг покоя: точка сустава в локале обоих тел — по кадрам СБОРКИ (d.assembly), длина цепи от торса по суставам.
func _watch(id: String, d: ModularDoll) -> void:
	tracked[id] = d
	var joints: Array = []
	var parent_of := {}
	for j in d.joints.values():
		var jj := j as Generic6DOFJoint3D
		var a := jj.get_node(jj.node_a) as RigidBody3D
		var b := jj.get_node(jj.node_b) as RigidBody3D
		var pa: Vector3 = (d.assembly[String(a.name)] as Transform3D).affine_inverse() * jj.position
		var pb: Vector3 = (d.assembly[String(b.name)] as Transform3D).affine_inverse() * jj.position
		joints.append([a, b, pa, pb])
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
		tr["max_reach_over"] = maxf(float(tr["max_reach_over"]), rb.global_position.distance_to(torso.global_position) - float(tr["chain"][rb]))
	for e in tr["joints"]:
		var gap := (e[0] as RigidBody3D).to_global(e[2]).distance_to((e[1] as RigidBody3D).to_global(e[3]))
		tr["max_gap"] = maxf(float(tr["max_gap"]), gap)


func _section(id: String) -> Dictionary:
	if presets.has(id):
		return report["presets"][id]
	return report[id]


func _idle_verdict() -> void:
	for id in tracked:
		var tr: Dictionary = track[id]
		var d: ModularDoll = tracked[id]
		var r := _section(id)
		r["idle_max_speed"] = snappedf(float(tr["max_speed"]), 0.001)
		r["idle_fastest_part"] = tr["worst"]
		r["idle_max_joint_gap_m"] = snappedf(float(tr["max_gap"]), 0.0001)
		r["idle_max_reach_over_chain_m"] = snappedf(float(tr["max_reach_over"]), 0.0001)
		r["idle_torso_y"] = snappedf(d.torso().global_position.y, 0.01)
		_check(not bool(tr["nan"]), id + ": в покое без NaN")
		_check(float(tr["max_speed"]) <= MAX_IDLE_SPEED, id + ": в покое без взрыва (скорость ≤ %.0f м/с)" % MAX_IDLE_SPEED,
			[tr["worst"], snappedf(float(tr["max_speed"]), 0.01)])
		_check(float(tr["max_gap"]) <= MAX_JOINT_GAP, id + ": суставы целы (≤ %.2f м)" % MAX_JOINT_GAP, snappedf(float(tr["max_gap"]), 0.0001))
		_check(float(tr["max_reach_over"]) <= CHAIN_SLACK, id + ": части не дальше цепи от торса", snappedf(float(tr["max_reach_over"]), 0.0001))
		if presets.has(id):
			_check(d.torso().global_position.y >= STAND_MIN_Y, id + ": стоит (торс выше %.1f м)" % STAND_MIN_Y, r["idle_torso_y"])


func _moving() -> Array:
	var out: Array = presets.values()
	if human_ref != null:
		out.append(human_ref)
	return out


func _start_move() -> void:
	for d in _moving():
		(d as Doll).input_vec = MOVE_INPUT
		(d as Doll).set_meta("com0", (d as Doll).centre_of_mass())


func _stop_move() -> void:
	for d in _moving():
		(d as Doll).input_vec = Vector2.ZERO
	for id in presets:
		var d: ModularDoll = presets[id]
		var dx := d.centre_of_mass().x - Vector3(d.get_meta("com0")).x
		report["presets"][id]["move_dx_m"] = snappedf(dx, 0.001)
		_check(dx >= MIN_MOVE, id + ": ввод (1, 0.4) %.1f с сдвинул ЦМ ≥ %.1f м" % [MOVE_S, MIN_MOVE], snappedf(dx, 0.01))
	if human_ref != null and presets.has("kit_human"):
		var kd: ModularDoll = presets["kit_human"]
		var da := human_ref.centre_of_mass().x - Vector3(human_ref.get_meta("com0")).x
		var db := kd.centre_of_mass().x - Vector3(kd.get_meta("com0")).x
		report["kit_human_vs_human"]["move_dx_m"] = [snappedf(da, 0.001), snappedf(db, 0.001)]
		_check(absf(da - db) <= 0.05, "kit_human = human: одинаковая тяга (ЦМ ±5 см)", [db, da])


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
		var finite := true
		for b in d.parts.values():
			if not is_instance_valid(b) or not (b as Node3D).global_position.is_finite():
				finite = false
		var left := 0
		for c in d.get_children():
			if c is Generic6DOFJoint3D:
				left += 1
		var span := _span(d)
		report["presets"][id]["ko_span_m"] = [snappedf(float(d.get_meta("span0")), 0.01), snappedf(span, 0.01)]
		report["presets"][id]["ko_broken"] = d.is_broken()
		_check(d.is_broken() and not d.alive and d.joints.is_empty() and left == 0 and finite, id + ": knock_out → break_apart",
			[d.is_broken(), d.alive, left, finite])
		_check(span > float(d.get_meta("span0")), id + ": после KO части разлетелись", [d.get_meta("span0"), snappedf(span, 0.01)])


func _physics_process(delta: float) -> void:
	t += delta
	if stage == 0:
		for id in tracked:
			_track_tick(id, tracked[id])
		_arm_tick()
		if t >= HUMAN_REST_S and not rest_done:
			rest_done = true
			if presets.has("kit_human"):
				_compare_rest()
		if t >= IDLE_S:
			_idle_verdict()
			_start_move()
			stage = 1
	elif stage == 1 and t >= IDLE_S + MOVE_S:
		_stop_move()
		_knock_out_all()
		stage = 2
	elif stage == 2 and t >= IDLE_S + MOVE_S + KO_WAIT_S:
		_ko_verdict()
		_finish()
		stage = 3


func _finish() -> void:
	report["checks"] = checks
	report["failed"] = failures.size()
	report["ok"] = failures.is_empty()
	report["failures"] = Array(failures)
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	print("=== KIT PROBE ===")
	for id in report["presets"]:
		var r: Dictionary = report["presets"][id]
		print("  %-11s energy %3d  mass %5.1f  bodies %2d joints %2d  con %2d  shirt %2d  idle vmax %5.2f gap %.4f  torso %.2f  move %.2f m  ko %s  %s" % [
			id, r.get("energy", 0), r.get("mass", 0.0), r.get("bodies", 0), r.get("joints", 0), r.get("connectors", 0),
			r.get("shirt_surfaces", 0), r.get("idle_max_speed", -1.0), r.get("idle_max_joint_gap_m", -1.0), r.get("idle_torso_y", -1.0),
			r.get("move_dx_m", -1.0), r.get("ko_broken", false), r.get("joint_types", {})])
	print("  kit_human vs human: ", report["kit_human_vs_human"])
	for fl in failures:
		print("  FAIL ", fl)
	if failures.is_empty():
		print("KIT PROBE OK (%d checks)" % checks)
	else:
		print("KIT PROBE FAIL (%d of %d checks failed)" % [failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func _floor(pos: Vector3, width: float) -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(width, 0.2, 3.0)
	cs.shape = bs
	f.add_child(cs)
	f.position = pos + Vector3(0, -0.1, 0)
	var phys := PhysicsMaterial.new()
	phys.friction = 0.9
	f.physics_material_override = phys
	add_child(f)
