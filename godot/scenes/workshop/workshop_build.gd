## МАСТЕРСКАЯ — игрушечный редактор тела и оружия (docs/plan-demo/BODY_CRAFT.md, CONCEPT_V2 §4–13, §12: «взял деталь → поднёс
## к anchor → CLICK → установлено»). Сцена scenes/workshop/workshop_build.tscn (арена «Мастерская» фоном, стенд, верстак, камеры,
## UI scenes/workshop/ui/workshop_ui.tscn), здесь — поведение и API (им пользуется tests/workshop_probe.gd, без мыши).
##
## Режим СБОРКИ (Mode.BUILD):
##   • кукла на стенде — ModularDoll по текущему чертежу, в позе покоя чертежа (все группы суставов снапнуты), тела заморожены
##     (FREEZE_MODE_KINEMATIC) и лежат только на слое PICK_LAYER (клик лучом, с ареной не сталкиваются). Чертёж без головы тоже
##     собирается (_PreviewBlueprint: validate() = только ошибки сборки), ошибки правил игры показывает UI;
##   • любая правка → пересборка стенда (новый инстанс ModularDoll), снимок в историю (Ctrl+Z);
##   • тащишь деталь с полки → targets_for(): все якоря текущего вида (тело / верстак), check() каждого; принимают вид — светятся
##     (зелёный — можно, оранжевый — замена, красный — не влезает энергия), остальные гаснут; ближайший подходящий в SNAP_PX от
##     курсора — «призрак» детали в посадке child = anchor × R(поза покоя) × socket⁻¹; отпустил → прикручено. Клик по карточке без
##     протяжки — деталь «в руке», следующий клик ставит (или ПКМ / Esc — отмена);
##   • ПКМ по детали — открутить с поддеревом; Q (кнопка «Рука мышью») и клик — пометить управляемую деталь (светится золотом);
##   • кит v2 (docs/plan-demo/BODY_KIT.md §5.5), инструменты полки: вкладка «Материал» — кисть (paint_mat): клик по детали на стенде
##     → set_material (узел mat, масса × новая плотность / прежняя; деталь без base_mat — отказ с причиной); вкладка «Шарниры» — тип шарнира
##     (joint_pick): клик по детали → set_joint (связь детали с родителем: ось / свободный / пружина / мотор / сварка; корень и
##     запреты §5.2 — отказ). Esc / ПКМ снимают инструмент. Инструменты, «рука мышью» и протяжка взаимно исключают друг друга;
##   • покраска (docs/plan-demo/BODY_PAINT.md §1, §6), вкладка «Покраска»: paint — WorkshopPaint (scenes/workshop/workshop_paint.gd),
##     paint_tool ∈ {"", spray, erase, fill, pattern, pick, stencil, sticker, face} — ещё один инструмент в руке (снимается, как
##     кисть материала: смена вкладки / вида, испытание, Esc / ПКМ); ввод 3D сначала идёт ему (handle_input), штрих рисует в живые слои
##     стенда без пересборки, отпустил — одна запись истории; стенд поворачивается (R) для боков и спины;
##   • ТЕЛО / ОРУЖИЕ (Tab) — камера едет со стенда на верстак; на верстаке тот же drag&drop на WeaponBlueprint (корень — рукоять),
##     живое превью CraftedWeapon, характеристики словами (weapon_stats). «В руку» — blueprint.weapon (копия верстака, дальше
##     синхронизируется) + weapon_on = CraftEdit.weapon_mount(); на стенде оружие видно в кисти (как WeaponPickup.attach).
## Режим ИСПЫТАНИЯ (Mode.TEST, T / Enter / кнопка): кукла оживает на месте стенда (обычная физика: WASD, WeaponPickup, ArmAssist —
##   ЛКМ / E, DollCombat), рядом манекен на верёвке (training_dummy.gd, HP и цифры урона — сигнал dummy_hit), ящик и бочка для
##   броска, камера — DynamicCamera по группе TEST_GROUP. R — заново, Esc / Tab — назад к сборке, чертёж тот же (и автосохранение
##   user://blueprints/_autosave.tres — с ним мастерская и стартует; его же пишет каждая правка через AUTOSAVE_DELAY_S, закрытие
##   окна и выход двойным Esc).
class_name WorkshopBuild
extends Node3D

signal changed
signal toast(text: String, colour: Color)
signal mode_changed(mode: int)
signal view_changed(view: int)
signal dummy_hit(amount: float, position: Vector3, part: String, kind: String)

enum Mode { BUILD, TEST }
enum View { BODY, WEAPON }

const MODULAR_DOLL := preload("res://scenes/body/modular_doll.tscn")
const DummyScript := preload("res://scenes/workshop/training_dummy.gd")
const JointCard := preload("res://scenes/workshop/ui/joint_card.gd")   # цвета типов шарнира (подсветка, сообщения)
const CRATE_SCENE := "res://scenes/props/crate.tscn"
const BARREL_SCENE := "res://scenes/props/barrel.tscn"
const PICK_LAYER := 1 << 19
const TEST_GROUP := "workshop_test"
const POSE_GROUPS := ["Neck", "Shoulder", "Elbow", "Hip", "Knee", "Wrist", "Ankle"]
const SNAP_PX := 110.0            # радиус «прилипания» к якорю на экране (база 1920×1080)
const DRAG_MOVE_PX := 10.0        # сдвиг, после которого нажатие на карточку — протяжка, а не клик
const HISTORY_MAX := 50
const HOLD_ANGLE_DEG := 90.0      # как WeaponPickup.hold_angle_deg: оружие в кисти в сторону от тела
const HAND_GRIP := Vector3(0, -0.03, 0)   # WeaponPickup.hand_grip_offset
const CAM_FOV := 38.0
## Свободная середина экрана между панелями (UI: слева и справа по 460 px из 1920) — по ней вписывается кукла.
const FREE_W_FRAC := 0.5
const CAM_TAU := 0.22
const COL_OK := Color(0.55, 0.95, 0.45)
const COL_WARN := Color(1.0, 0.72, 0.25)
const COL_BAD := Color(1.0, 0.36, 0.28)
const COL_INFO := Color(0.98, 0.93, 0.82)


## Чертёж для стенда: собирается и без головы / сверх бюджета (правила игры показывает UI), лишь бы сошлась сборка.
class _PreviewBlueprint extends BodyBlueprint:
	func validate() -> PackedStringArray:
		return CraftEdit.structural_errors(self)


@export var start_preset := "human"
## Загрузить автосохранение (user://blueprints/_autosave.tres), если оно есть и собирается.
@export var load_autosave := true
## «Испытать» пишет чертёж в user://blueprints/_autosave.tres (проба выключает, чтобы не затирать сборку игрока); с ним же —
## автосейв правок: через AUTOSAVE_DELAY_S после последней правки (деталь, материал, покраска, отмена), при закрытии окна и выходе
## двойным Esc — полчаса покраски не пропадают без «Испытать» / «Сохранить».
@export var autosave_on_test := true
## Имя файла автосейва в user://blueprints (проба ставит своё).
@export var autosave_name := CraftEdit.AUTOSAVE

var blueprint: BodyBlueprint
var weapon_bp: WeaponBlueprint
var mode := Mode.BUILD
var view := View.BODY
var stand: ModularDoll
var bench_weapon: CraftedWeapon
var held_weapon: CraftedWeapon          # оружие в кисти куклы на стенде (только показ)
var drag: Dictionary = {}                # {part, targets, index, sticky, start, pos, moved}
var control_pick := false
var paint_mat := ""                      # кисть материала: id MaterialDef ("" — выключена)
var joint_pick := ""                     # инструмент шарнира: тип KitJoint ("" — выключен)
var paint: WorkshopPaint                 # покраска (BODY_PAINT.md §6): инструмент, кисть, наклейки, поворот стенда
## Инструмент покраски в руке ("" — нет): WorkshopPaint.tool.
var paint_tool: String:
	get:
		return paint.tool if paint != null else ""
var hover: Dictionary = {}               # {target: "body"|"weapon", uid}
var history: Array = []
var last_result: Dictionary = {}
## Испытание.
var test_doll: ModularDoll
var test_weapon: CraftedWeapon
var dummy: Node3D                        # training_dummy.gd
var test_cam: DynamicCamera
var probe_input := false                 # проба: кукла испытания на external_input

var _shape_uid: Dictionary = {}          # "<тело>/<форма>" -> uid (fixed-детали, слитые в хозяина)
var _own_uid: Dictionary = {}            # имя тела -> uid детали-хозяина
var _ghost: Node3D
var _ghost_key := ""
var _mats: Dictionary = {}
var _cam_pos := Vector3.ZERO
var _cam_snap := true
var _esc_armed_until := -1.0
var _time := 0.0
var _autosave_dirty := false
var _autosave_at := 0.0

## Автосейв правок: пауза после последней правки (серия мазков / колёсиком — одна запись).
const AUTOSAVE_DELAY_S := 2.0

@onready var arena: Node3D = $Workshop
@onready var build_cam: Camera3D = $BuildCamera
@onready var stand_root: Node3D = $Stand
@onready var bench_spot: Node3D = $BenchSpot
@onready var dummy_spot: Node3D = $DummySpot
@onready var crate_spot: Node3D = $CrateSpot
@onready var barrel_spot: Node3D = $BarrelSpot
@onready var test_root: Node3D = $TestRoot
@onready var ui: Node = $UI


## Пропсы арены, которые стоят там, где висит манекен испытания (бочка и козлы у x ≈ 2–4).
const CLEAR_ARENA_PROPS := ["Props/Barrel_2", "Props/Sawhorse_1"]


func _ready() -> void:
	for p in CLEAR_ARENA_PROPS:
		var n := arena.get_node_or_null(p)
		if n != null:
			n.queue_free()
	_make_materials()
	paint = WorkshopPaint.new()
	paint.name = "Paint"
	paint.ws = self
	add_child(paint)
	build_cam.fov = CAM_FOV
	build_cam.make_current()
	weapon_bp = CraftEdit.load_weapon_preset("hammer")
	var bp: BodyBlueprint = null
	if load_autosave:
		bp = CraftEdit.load_saved(CraftEdit.save_path(CraftEdit.AUTOSAVE))
		if bp != null and not CraftEdit.structural_errors(bp).is_empty():
			bp = null
	if bp == null:
		bp = CraftEdit.load_body_preset(start_preset)
	_adopt(bp)
	if ui != null and ui.has_method("bind"):
		ui.call("bind", self)
	_rebuild()


# =================================================================== чертёж

func _adopt(bp: BodyBlueprint) -> void:
	blueprint = bp
	if blueprint.weapon is WeaponBlueprint:
		weapon_bp = CraftEdit.dup_weapon(blueprint.weapon as WeaponBlueprint)


## Шаблон тела (id пресета data/body/blueprints). Оружие пресета (если есть) — на верстак.
func set_preset(id: String) -> bool:
	var bp := CraftEdit.load_body_preset(id)
	if bp == null:
		return false
	_push_history()
	_adopt(bp)
	_rebuild()
	_say("Шаблон: %s" % bp.title, COL_INFO)
	return true


## Шаблон оружия на верстак (data/body/weapons/<id>.tres). Если оружие в руке — в руке тоже оно.
func set_weapon_preset(id: String) -> bool:
	var w := CraftEdit.load_weapon_preset(id)
	if w == null:
		return false
	_push_history()
	weapon_bp = w
	_sync_equipped()
	_rebuild()
	_say("Верстак: %s" % w.title, COL_INFO)
	return true


func clear_weapon() -> void:
	_push_history()
	weapon_bp = WeaponBlueprint.new()
	weapon_bp.id = "custom"
	weapon_bp.title = "Своё оружие"
	blueprint.weapon = null
	blueprint.weapon_on = ""
	_rebuild()


## Прикрутить деталь на якорь (target "body" — тело, "weapon" — верстак). anchor "" у parent_uid "" — корень (ядро / рукоять).
## Возвращает результат CraftEdit.check/attach: {ok, uid, code, reason, replace, drops}.
func attach_part(part_id: String, parent_uid: String, anchor: String, target := "") -> Dictionary:
	if target == "":
		target = "weapon" if view == View.WEAPON else "body"
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	var r := CraftEdit.check_root(bp, part_id) if parent_uid == "" else CraftEdit.check(bp, part_id, parent_uid, anchor)
	if not bool(r["ok"]):
		last_result = r
		_say(String(r["reason"]), COL_BAD)
		return r
	_push_history()
	r = CraftEdit.set_root(bp, part_id) if parent_uid == "" else CraftEdit.attach(bp, part_id, parent_uid, anchor)
	last_result = r
	if target == "weapon":
		_name_custom_weapon()
		_sync_equipped()
	else:
		_name_custom_body()
	_rebuild()
	var d := CraftEdit.part(part_id)
	var what := "Заменено" if String(r.get("replace", "")) != "" else "Прикручено"
	var extra := "" if (r.get("drops", PackedStringArray()) as PackedStringArray).is_empty() else " (снято лишнее: %d)" % (r["drops"] as PackedStringArray).size()
	# фото со старой головы: у новой плашка утоплена / её нет (BodyPaint.face_plate_ok) — фото наклейкой на лицо, та же запись истории
	var lost := String(r.get("face_lost", ""))
	if target == "body" and lost != "" and paint != null:
		var rf := paint.set_face_image(lost, false)
		extra += " — фото на лице наклейкой" if bool(rf.get("ok", false)) else " — фото снято (у этой головы нет лица)"
	_say("%s: %s%s" % [what, d.title if d != null else part_id, extra], COL_OK)
	return r


## Открутить деталь с поддеревом. Возвращает снятые uid.
func detach_part(uid: String, target := "body") -> PackedStringArray:
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	var n := CraftEdit.find(bp, uid)
	if n.is_empty():
		return PackedStringArray()
	if target == "body" and String(n.get("parent", "")) == "":
		_say("Ядро не откручивается — перетащи другое ядро поверх, чтобы заменить", COL_WARN)
		return PackedStringArray()
	_push_history()
	var d := CraftEdit.part(String(n.get("part", "")))
	var gone := CraftEdit.detach(bp, uid)
	if target == "weapon":
		_name_custom_weapon()
		_sync_equipped()
	else:
		_name_custom_body()
	_rebuild()
	var tail := "" if gone.size() <= 1 else " и ещё %d" % (gone.size() - 1)
	_say("Откручено: %s%s" % [d.title if d != null else uid, tail], COL_WARN)
	return gone


## Рука мышью: пометить деталь (или снять пометку повторным кликом).
func set_control(uid: String) -> Dictionary:
	var trial := CraftEdit.dup_body(blueprint)
	var r := CraftEdit.set_control(trial, uid)
	if not bool(r["ok"]):
		_say(String(r["reason"]), COL_WARN)
		return r
	_push_history()
	blueprint.control = trial.control
	if blueprint.weapon != null:
		blueprint.weapon_on = String(CraftEdit.weapon_mount(blueprint)["uid"])
	control_pick = false
	_rebuild()
	var d := CraftEdit.def_of(blueprint, String(r["uid"]))
	if bool(r.get("cleared", false)):
		_say("Рука мышью снята", COL_WARN)
	else:
		_say("Рука мышью: %s" % (d.title if d != null else String(r["uid"])), Color(1.0, 0.85, 0.35))
	return r


func toggle_control_pick() -> void:
	control_pick = not control_pick
	if control_pick:
		paint_mat = ""
		joint_pick = ""
		set_paint_tool("")
		cancel_drag()
		set_view(View.BODY)
	_apply_highlights()
	changed.emit()


# --- инструменты кита v2: кисть материала и тип шарнира (BODY_KIT.md §5.5) ---

## Взять кисть материала mat_id (тот же id ещё раз или "" — положить). Снимает «руку мышью», шарнир и протяжку.
func set_paint_mat(mat_id: String) -> void:
	if mat_id != "" and (mat_id == paint_mat or MaterialDef.get_def(mat_id) == null):
		mat_id = ""
	paint_mat = mat_id
	if paint_mat != "":
		control_pick = false
		joint_pick = ""
		set_paint_tool("")
		cancel_drag()
		set_view(View.BODY)
		_say("Кисть: %s — кликни по детали куклы" % CraftEdit.mat_title(paint_mat), MaterialDef.get_def(paint_mat).swatch.lightened(0.35))
	_apply_highlights()
	changed.emit()


## Взять инструмент шарнира jt (тот же ещё раз или "" — положить).
func set_joint_pick(jt: String) -> void:
	if jt != "" and (jt == joint_pick or not KitJoint.is_type(jt)):
		jt = ""
	joint_pick = jt
	if joint_pick != "":
		control_pick = false
		paint_mat = ""
		set_paint_tool("")
		cancel_drag()
		set_view(View.BODY)
		_say("Шарнир «%s» — кликни по детали куклы" % CraftEdit.joint_title(joint_pick), JointCard.colour(joint_pick))
	_apply_highlights()
	changed.emit()


## Инструмент покраски t (WorkshopPaint.TOOLS; "" — положить). Кладёт «руку мышью», кисть материала, шарнир и протяжку.
func set_paint_tool(t: String) -> void:
	if paint != null:
		paint.set_tool(t)


## Какой инструмент в руке: "control" | "material" | "joint" | "paint" | "".
func active_tool() -> String:
	if control_pick:
		return "control"
	if paint_mat != "":
		return "material"
	if joint_pick != "":
		return "joint"
	if paint_tool != "":
		return "paint"
	return ""


## Положить инструмент («рука мышью», кисть, шарнир, покраска). true — что-то было в руке.
func clear_tools() -> bool:
	var had := active_tool() != ""
	control_pick = false
	paint_mat = ""
	joint_pick = ""
	if paint_tool != "":
		paint.set_tool("")
	if had:
		_apply_highlights()
		changed.emit()
	return had


## Кисть: материал mat_id (по умолчанию — paint_mat) детали uid. История, node["mat"] (для base_mat ключ стирается), пересборка.
## {ok, code, reason, changed, mass_before, mass_after} — CraftEdit.set_material; отказ — с причиной (деталь не красится и т. п.).
func set_material(uid: String, mat_id := "") -> Dictionary:
	if mat_id == "":
		mat_id = paint_mat
	var r := CraftEdit.check_material(blueprint, uid, mat_id)
	var d := CraftEdit.def_of(blueprint, uid)
	var what := d.title if d != null else uid
	if not bool(r["ok"]):
		last_result = r
		_say(String(r["reason"]), COL_BAD)
		return r
	if not bool(r["changed"]):
		last_result = r
		_say("%s — уже %s" % [what, CraftEdit.mat_title(mat_id)], COL_INFO)
		return r
	_push_history()
	r = CraftEdit.set_material(blueprint, uid, mat_id)
	last_result = r
	_name_custom_body()
	_rebuild()
	var dm := float(r["mass_after"]) - float(r["mass_before"])
	var m := MaterialDef.get_def(mat_id)
	_say("%s: %s → %s  (%.1f → %.1f кг%s)" % [what, CraftEdit.mat_title(String(r["mat_before"])), m.title, float(r["mass_before"]),
		float(r["mass_after"]), "" if absf(dm) < 0.05 else ", %+.1f" % dm], m.swatch.lightened(0.35))
	return r


## Тип шарнира jt (по умолчанию — joint_pick) связи детали uid с родителем. История, node["joint"] ("pin" — ключ стирается),
## пересборка. {ok, code, reason, changed, energy_after} — CraftEdit.set_joint; отказ (корень, fixed-деталь, запреты weld, энергия)
## — с причиной.
func set_joint(uid: String, jt := "") -> Dictionary:
	if jt == "":
		jt = joint_pick
	var r := CraftEdit.check_joint(blueprint, uid, jt)
	var d := CraftEdit.def_of(blueprint, uid)
	var what := d.title if d != null else uid
	if not bool(r["ok"]):
		last_result = r
		_say(String(r["reason"]), COL_BAD)
		return r
	if not bool(r["changed"]):
		last_result = r
		_say("%s — уже «%s»" % [what, CraftEdit.joint_title(jt)], COL_INFO)
		return r
	_push_history()
	r = CraftEdit.set_joint(blueprint, uid, jt)
	last_result = r
	if blueprint.weapon != null and blueprint.weapon_on != "" and CraftEdit.is_fixed(blueprint, blueprint.weapon_on):
		blueprint.weapon_on = String(CraftEdit.weapon_mount(blueprint)["uid"])   # сварили держатель оружия — в другую кисть
	_name_custom_body()
	_rebuild()
	var e := KitJoint.energy_of(jt) - KitJoint.energy_of(String(r["joint_before"]))
	var tail := "" if e == 0 else "  (⚡%+d)" % e
	if KitJoint.is_weld(jt):
		var host := CraftEdit.def_of(blueprint, CraftEdit.host_uid(blueprint, uid))
		_say("Сварка: %s — теперь часть «%s»%s" % [what, host.title if host != null else "", tail], COL_OK)
	else:
		_say("Шарнир «%s» → «%s»: %s%s" % [CraftEdit.joint_title(String(r["joint_before"])), CraftEdit.joint_title(jt), what, tail], COL_OK)
	return r


## «В руку»: оружие верстака — в кисть сборки (blueprint.weapon + weapon_on). Повторно — снять. {ok, uid, kind, reason}.
func weapon_to_hand() -> Dictionary:
	if blueprint.weapon != null:
		_push_history()
		blueprint.weapon = null
		blueprint.weapon_on = ""
		_rebuild()
		_say("Оружие снято с руки", COL_WARN)
		return {"ok": true, "uid": "", "kind": "", "reason": "", "removed": true}
	if weapon_bp == null or weapon_bp.nodes.is_empty():
		_say("Верстак пуст: положи рукоять", COL_WARN)
		return {"ok": false, "uid": "", "kind": "", "reason": "Верстак пуст"}
	var werr := CraftEdit.structural_errors(weapon_bp)
	if not werr.is_empty():
		_say(CraftEdit._capital(werr[0]), COL_BAD)
		return {"ok": false, "uid": "", "kind": "", "reason": werr[0]}
	var m := CraftEdit.weapon_mount(blueprint)
	if String(m["uid"]) == "":
		_say(String(m["reason"]), COL_BAD)
		return {"ok": false, "uid": "", "kind": "", "reason": m["reason"]}
	_push_history()
	blueprint.weapon = CraftEdit.dup_weapon(weapon_bp)
	blueprint.weapon_on = String(m["uid"])
	_rebuild()
	var d := CraftEdit.def_of(blueprint, blueprint.weapon_on)
	var where := d.title if d != null else blueprint.weapon_on
	_say("%s — в руку: %s%s" % [weapon_bp.title, where, "" if m["kind"] == "hand" else " (на конце детали)"], COL_OK)
	var r := m.duplicate()
	r["ok"] = true
	return r


## Верстак поменялся — оружие в руке тоже (оно и есть «то, что на верстаке»).
func _sync_equipped() -> void:
	if blueprint.weapon == null:
		return
	if weapon_bp.nodes.is_empty() or not CraftEdit.structural_errors(weapon_bp).is_empty():
		blueprint.weapon = null
		blueprint.weapon_on = ""
		return
	blueprint.weapon = CraftEdit.dup_weapon(weapon_bp)


func _name_custom_body() -> void:
	if not blueprint.title.ends_with("*"):
		blueprint.title = (blueprint.title if blueprint.title != "" else "Сборка") + " *"


func _name_custom_weapon() -> void:
	if not weapon_bp.title.ends_with("*"):
		weapon_bp.title = (weapon_bp.title if weapon_bp.title != "" else "Оружие") + " *"


# --- история ---

func _push_history() -> void:
	history.append({"body": CraftEdit.dup_body(blueprint), "weapon": CraftEdit.dup_weapon(weapon_bp)})
	while history.size() > HISTORY_MAX:
		history.remove_at(0)
	mark_dirty()   # запись истории — перед правкой; сейв отложен (AUTOSAVE_DELAY_S), правка к нему уже будет в чертеже


func undo() -> bool:
	if history.is_empty() or mode != Mode.BUILD or (paint != null and paint.busy()):
		return false
	var s: Dictionary = history.pop_back()
	blueprint = s["body"]
	weapon_bp = s["weapon"]
	_rebuild()
	mark_dirty()
	_say("Отменено", COL_INFO)
	return true


# --- автосейв правок ---

## Чертёж поменялся: автосейв через AUTOSAVE_DELAY_S (каждая новая правка отодвигает срок). Зовут _push_history, undo и
## WorkshopPaint._push (и серия колёсиком / Q / E по наклейке без новой записи истории).
func mark_dirty() -> void:
	_autosave_dirty = true
	_autosave_at = _time + AUTOSAVE_DELAY_S


## Записать автосейв, если есть несохранённые правки. Не пишет: автосейв выключен (проба), испытание, идёт штрих / перетаскивание /
## раскраска (слой ляжет в чертёж только по отпусканию — попробуем в следующем кадре; force — пишем как есть), чертёж не собирается
## (старт мастерской отверг бы его и откатил к шаблону — пусть лежит прежний хороший).
func _flush_autosave(force := false) -> bool:
	if not _autosave_dirty or not autosave_on_test or mode != Mode.BUILD or blueprint == null:
		return false
	if paint != null and paint.busy() and not force:
		return false
	_autosave_dirty = false
	if not CraftEdit.structural_errors(blueprint).is_empty():
		return false
	return CraftEdit.save(blueprint, autosave_name) != ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if paint != null and paint.busy() and mode == Mode.BUILD:
			paint._finish_all()   # окно закрыли посреди штриха / перетаскивания / раскраски — сначала в чертёж, потом сейв
		_flush_autosave(true)   # auto_accept_quit по умолчанию: уведомление приходит до выхода, сейв — синхронно


func _exit_tree() -> void:
	_flush_autosave(true)


# --- сохранение ---

## Сохранить сборку (с оружием) под названием title → user://blueprints/<slug>.tres. Возвращает путь ("" — ошибка).
func save_as(title: String) -> String:
	var t := title.strip_edges()
	if t != "":
		blueprint.title = t
	blueprint.title = blueprint.title.trim_suffix(" *")
	var path := CraftEdit.save(blueprint, CraftEdit.slug(blueprint.title))
	if path == "":
		_say("Не удалось сохранить", COL_BAD)
	else:
		_say("Сохранено: %s" % blueprint.title, COL_OK)
	changed.emit()
	return path


func load_path(path: String) -> bool:
	var bp := CraftEdit.load_saved(path)
	if bp == null or not CraftEdit.structural_errors(bp).is_empty():
		_say("Чертёж не читается", COL_BAD)
		return false
	_push_history()
	_adopt(bp)
	_rebuild()
	_say("Загружено: %s" % bp.title, COL_OK)
	return true


# =================================================================== стенд и верстак

func _rebuild() -> void:
	_clear_ghost()
	if mode == Mode.BUILD:
		_rebuild_stand()
		if paint != null:
			paint.on_stand_rebuilt()   # кэши лучей покраски, поворот стенда — на новую куклу
		_rebuild_bench()
		_apply_highlights()
	changed.emit()


func _rebuild_stand() -> void:
	_free_node(held_weapon)
	held_weapon = null
	_free_node(stand)
	stand = null
	_shape_uid.clear()
	_own_uid.clear()
	if blueprint.nodes.is_empty() or not CraftEdit.structural_errors(blueprint).is_empty():
		_update_pole()
		return
	var view_bp := _PreviewBlueprint.new()
	view_bp.id = blueprint.id
	view_bp.title = blueprint.title
	view_bp.energy_budget = 100000
	view_bp.nodes = CraftEdit._dup_nodes(blueprint.nodes)
	view_bp.control = blueprint.control.duplicate()
	var d := MODULAR_DOLL.instantiate() as ModularDoll
	d.name = "StandDoll"
	d.blueprint = view_bp
	d.external_input = true
	d.control_enabled = false
	d.player_index = 0
	d.position = stand_root.global_position
	add_child(d)
	stand = d
	stand._snap_pose(POSE_GROUPS)   # кисти, стопы и шея тоже в позу покоя (Doll снапает только плечи/бёдра/локти/колени)
	for b in stand.parts.values():
		var rb := b as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.collision_layer = PICK_LAYER
		rb.collision_mask = 0
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		_unlock_axes(rb)   # стенд поворачивается (покраска, R): замки 2.5D вернули бы телам прежний поворот
	for j in stand.joints.values():   # суставы между замороженными телами не нужны (и Jolt не должен их решать)
		(j as Generic6DOFJoint3D).node_a = NodePath()
		(j as Generic6DOFJoint3D).node_b = NodePath()
	for n in blueprint.nodes:
		var uid := String(n.get("uid", ""))
		var def := CraftEdit.part(String(n.get("part", "")))
		if def == null or not stand.uid_body.has(uid):
			continue
		var host := String(stand.uid_body[uid])
		if CraftEdit.is_fixed(blueprint, uid):   # слитая деталь (fixed, декор, броня, сварка): формы — <форма>_<uid> в хозяине
			for sn in CraftEdit.shape_names(def):
				_shape_uid["%s/%s_%s" % [host, sn, uid]] = uid
		else:
			_own_uid[host] = uid
	_update_pole()
	_make_held_weapon()


func _rebuild_bench() -> void:
	_free_node(bench_weapon)
	bench_weapon = null
	if weapon_bp == null or weapon_bp.nodes.is_empty() or not CraftEdit.structural_errors(weapon_bp).is_empty():
		return
	var w := CraftedWeapon.create(CraftEdit.dup_weapon(weapon_bp))
	w.name = "BenchWeapon"
	w.transform = bench_spot.global_transform
	add_child(w)
	w.remove_from_group(Weapon.GROUP)   # не подбирается и не считается оружием арены
	for b in w.bodies():
		var rb := b as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.collision_layer = PICK_LAYER
		rb.collision_mask = 0
	bench_weapon = w


## Оружие в кисти куклы на стенде (показ): поза как у WeaponPickup.attach (хват в точку хвата, +X оружия — в сторону от тела).
func _make_held_weapon() -> void:
	if stand == null or blueprint.weapon == null:
		return
	var m := _mount()
	if String(m["uid"]) == "" or not stand.uid_body.has(String(m["uid"])):
		return
	var w := CraftedWeapon.create(CraftEdit.dup_weapon(blueprint.weapon as WeaponBlueprint))
	w.name = "HeldWeapon"
	w.transform = mount_transform(stand, m)
	add_child(w)
	w.remove_from_group(Weapon.GROUP)
	for b in w.bodies():
		var rb := b as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
		_unlock_axes(rb)
	held_weapon = w


## Замороженное тело стенда без замков осей (кукла 2.5D: вращение только вокруг Z, без сдвига по Z) — стенд крутится на 90°.
static func _unlock_axes(rb: RigidBody3D) -> void:
	rb.axis_lock_angular_x = false
	rb.axis_lock_angular_y = false
	rb.axis_lock_angular_z = false
	rb.axis_lock_linear_x = false
	rb.axis_lock_linear_y = false
	rb.axis_lock_linear_z = false


## Куда висит оружие: weapon_on чертежа, если он ещё есть, иначе CraftEdit.weapon_mount().
func _mount() -> Dictionary:
	var m := CraftEdit.weapon_mount(blueprint)
	if blueprint.weapon_on != "" and not CraftEdit.find(blueprint, blueprint.weapon_on).is_empty() \
			and not CraftEdit.is_fixed(blueprint, blueprint.weapon_on):   # сваренная кисть — не держатель
		var d := CraftEdit.def_of(blueprint, blueprint.weapon_on)
		return {"uid": blueprint.weapon_on, "kind": "hand" if d != null and d.kind == "hand" else "end", "reason": ""}
	return m


## Точка хвата на детали mount в осях её тела: кисть — как WeaponPickup (0, −0.03, 0); иначе конец детали — самый нижний якорь
## (−Y — направление роста), без якорей — низ габарита форм.
func grip_offset(doll: ModularDoll, mount: Dictionary) -> Vector3:
	if String(mount.get("kind", "")) == "hand":
		return HAND_GRIP
	var uid := String(mount["uid"])
	var body := doll.parts.get(String(doll.uid_body.get(uid, ""))) as RigidBody3D
	var best := Vector3.ZERO
	var found := false
	if body != null:
		for c in body.get_children():
			if c is Marker3D and String(c.name).begins_with("Anchor_") and (not found or (c as Marker3D).position.y < best.y):
				best = (c as Marker3D).position
				found = true
		if not found:
			var ext := ModularDoll._local_extent(body)
			best = Vector3(0, -ext.y * 0.5, 0)
	return best


func mount_transform(doll: ModularDoll, mount: Dictionary) -> Transform3D:
	var bn := String(doll.uid_body[String(mount["uid"])])
	var h := doll.parts[bn] as RigidBody3D
	var side := 1.0 if bn.ends_with("L") else -1.0
	var basis := h.global_transform.basis * Basis(Vector3(0, 0, 1), deg_to_rad(-90.0 + HOLD_ANGLE_DEG * side))
	return Transform3D(basis, h.to_global(grip_offset(doll, mount)))


func _update_pole() -> void:
	var pole := stand_root.get_node_or_null("Pole") as Node3D
	if pole == null:
		return
	var h := 1.15
	if stand != null and stand.parts.has("Torso"):
		h = maxf((stand.parts["Torso"] as Node3D).global_position.y - stand_root.global_position.y, 0.2)
	pole.scale = Vector3(1, h, 1)
	pole.position = Vector3(0, h * 0.5, pole.position.z)


func _free_node(n: Node) -> void:
	if n != null and is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()


# =================================================================== якоря и цели

## Мировой кадр якоря anchor детали uid (тело на стенде или оружие на верстаке); null — нет.
func anchor_xf(target: String, uid: String, anchor: String) -> Variant:
	var an := CraftEdit.anchor_name(anchor)
	if target == "weapon":
		if bench_weapon == null or not bench_weapon.parts_info.has(uid):
			return null
		var info: Dictionary = bench_weapon.parts_info[uid]
		if not (info["anchors"] as Dictionary).has(an):
			return null
		return bench_weapon.global_transform * (info["rest"] as Transform3D) * (info["anchors"][an] as Transform3D)
	if stand == null or not stand.uid_body.has(uid):
		return null
	var n := CraftEdit.find(blueprint, uid)
	var d := CraftEdit.part(String(n.get("part", "")))
	var body := stand.parts.get(String(stand.uid_body[uid])) as Node3D
	if body == null or d == null:
		return null
	var fixed := CraftEdit.is_fixed(blueprint, uid)
	var m := body.get_node_or_null(an + ("_" + uid if fixed else "")) as Node3D
	return m.global_transform if m != null else null


## Кадр корня (ядро / рукоять) — цель замены корня или места для нового.
func root_xf(target: String) -> Transform3D:
	if target == "weapon":
		return bench_weapon.global_transform if bench_weapon != null else bench_spot.global_transform
	if stand != null and stand.parts.has("Torso"):
		return (stand.parts["Torso"] as Node3D).global_transform
	return Transform3D(Basis.IDENTITY, stand_root.global_position + Vector3(0, 1.17, 0))


## Все цели для детали part_id в текущем виде: [{target, uid, anchor, xf, accepts, ok, code, reason, replace, root}].
## accepts — якорь принимает вид детали (только такие светятся); ok — можно поставить сейчас (check()).
func targets_for(part_id: String, target := "") -> Array:
	if target == "":
		target = "weapon" if view == View.WEAPON else "body"
	var d := CraftEdit.part(part_id)
	var out: Array = []
	if d == null:
		return out
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	var root_kind := "handle" if target == "weapon" else "core"
	if d.kind == root_kind:
		var c := CraftEdit.check_root(bp, part_id)
		out.append({"target": target, "uid": CraftEdit.root_uid(bp), "anchor": "", "xf": root_xf(target), "accepts": true,
			"ok": c["ok"], "code": c["code"], "reason": c["reason"], "replace": c["replace"], "root": true})
		return out
	for n in CraftEdit.nodes_of(bp):
		var uid := String(n.get("uid", ""))
		var anchors := CraftEdit.anchors_of(bp, uid)
		for an in anchors:
			var xf: Variant = anchor_xf(target, uid, an)
			if xf == null:
				continue
			var acc: PackedStringArray = anchors[an]["accepts"]
			var accepts := acc.is_empty() or acc.has(d.kind)
			var e := {"target": target, "uid": uid, "anchor": an, "xf": xf, "accepts": accepts, "ok": false, "code": "kind",
				"reason": "", "replace": CraftEdit.occupant(bp, uid, an), "root": false}
			if accepts:
				var c := CraftEdit.check(bp, part_id, uid, an)
				e["ok"] = c["ok"]
				e["code"] = c["code"]
				e["reason"] = c["reason"]
				e["replace"] = c["replace"]
				if String(c["code"]) == "head" or String(c["code"]) == "core":
					e["accepts"] = false
			out.append(e)
	return out


## Свободная энергия тела.
func energy_free() -> int:
	return blueprint.energy_budget - blueprint.energy_used()


# =================================================================== протяжка

func begin_drag(part_id: String, screen_pos: Vector2) -> void:
	if mode != Mode.BUILD:
		return
	control_pick = false
	paint_mat = ""
	joint_pick = ""
	set_paint_tool("")
	var d := CraftEdit.part(part_id)
	if d == null:
		return
	var targets := targets_for(part_id)
	drag = {"part": part_id, "targets": targets, "index": -1, "sticky": false, "start": screen_pos, "pos": screen_pos, "moved": false}
	var any_ok := false
	var energy_block := false
	for t in targets:
		if bool(t["accepts"]) and bool(t["ok"]):
			any_ok = true
		elif bool(t["accepts"]) and String(t["code"]) == "energy":
			energy_block = true
	if not any_ok and energy_block:
		_say("Не хватает энергии: %s стоит %d, свободно %d" % [d.title, d.energy, energy_free()], COL_BAD)
	elif not any_ok:
		_say("Некуда поставить деталь «%s»: нет свободного подходящего якоря" % d.title, COL_WARN)
	update_drag(screen_pos)
	changed.emit()


func update_drag(screen_pos: Vector2) -> void:
	if drag.is_empty():
		return
	drag["pos"] = screen_pos
	if (screen_pos - (drag["start"] as Vector2)).length() > DRAG_MOVE_PX:
		drag["moved"] = true
	var best := -1
	var best_d := SNAP_PX
	var cam := get_viewport().get_camera_3d()
	var targets: Array = drag["targets"]
	for i in range(targets.size()):
		var t: Dictionary = targets[i]
		if not bool(t["accepts"]):
			continue
		var p := (t["xf"] as Transform3D).origin
		if cam == null or cam.is_position_behind(p):
			continue
		var dd := cam.unproject_position(p).distance_to(screen_pos)
		if dd < best_d:
			best_d = dd
			best = i
	if best != int(drag["index"]):
		drag["index"] = best
		_update_ghost()
		_apply_highlights()
		changed.emit()   # UI: энергия «станет» и подсказка


## Отпустить: прикрутить на выбранную цель (если можно). Возвращает результат attach_part или {ok: false}.
func end_drag(screen_pos: Vector2) -> Dictionary:
	if drag.is_empty():
		return {"ok": false}
	update_drag(screen_pos)
	var i := int(drag["index"])
	var part_id := String(drag["part"])
	var targets: Array = drag["targets"]
	cancel_drag()
	if i < 0:
		return {"ok": false, "reason": "мимо якоря"}
	var t: Dictionary = targets[i]
	if not bool(t["ok"]):
		_say(String(t["reason"]), COL_BAD)
		return {"ok": false, "reason": t["reason"]}
	if bool(t["root"]):
		return attach_part(part_id, "", "", String(t["target"]))
	return attach_part(part_id, String(t["uid"]), String(t["anchor"]), String(t["target"]))


func cancel_drag() -> void:
	if drag.is_empty():
		return
	drag = {}
	_clear_ghost()
	_apply_highlights()
	changed.emit()


func dragging() -> bool:
	return not drag.is_empty()


func drag_target() -> Dictionary:
	if drag.is_empty() or int(drag["index"]) < 0:
		return {}
	return (drag["targets"] as Array)[int(drag["index"])]


## Экранная точка цели i текущей протяжки (для пробы и кадров).
func target_screen_pos(t: Dictionary) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	return cam.unproject_position((t["xf"] as Transform3D).origin) if cam != null else Vector2.ZERO


# --- призрак ---

func _clear_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_key = ""


func _update_ghost() -> void:
	var t := drag_target()
	if t.is_empty():
		_clear_ghost()
		return
	var key := "%s/%s/%s/%s" % [drag["part"], t["target"], t["uid"], t["anchor"]]
	if key == _ghost_key:
		return
	_clear_ghost()
	_ghost_key = key
	_ghost = _make_ghost(String(drag["part"]), t)
	if _ghost != null:
		add_child(_ghost)


## Призрак детali: только меши сцены детали, прозрачный материал, в посадке child = anchor × R(поза покоя) × socket⁻¹
## (у тела — зеркало правой стороны и угол покоя сустава, как ModularDoll._build + _snap_pose; у оружия — как CraftedWeapon).
func ghost_transform(part_id: String, t: Dictionary) -> Dictionary:
	var d := CraftEdit.part(part_id)
	var target := String(t["target"])
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	if bool(t["root"]):
		var rx := root_xf(target)
		if target == "weapon":
			var inst0 := d.scene.instantiate()
			var s0 := inst0.get_node_or_null("Socket") as Node3D
			var sx: Transform3D = s0.transform if s0 != null else Transform3D.IDENTITY
			inst0.free()
			return {"xf": rx * CraftedWeapon.GRIP_FRAME * sx.affine_inverse(), "mirror": false}
		return {"xf": rx, "mirror": false}
	var trial: Resource = CraftEdit.dup_body(bp as BodyBlueprint) if target == "body" else CraftEdit.dup_weapon(bp as WeaponBlueprint)
	var res := CraftEdit._apply_attach(trial, part_id, String(t["uid"]), CraftEdit.anchor_name(String(t["anchor"])))
	var nu := String(res.get("uid", ""))
	var mirror := target == "body" and CraftEdit.is_mirrored(trial, nu)
	var rel := 0.0
	# слитая по PartDef деталь (декор, броня, навершие) — без угла покоя; сварка (при замене сваренной) — в позе покоя сустава, как
	# ModularDoll._weld_rest
	if target == "weapon" or not BodyBlueprint.is_fixed_part(d):
		rel = CraftEdit.rest_rel_deg(trial, nu)
	if target == "body" and mirror:
		rel = -rel
	var inst := d.scene.instantiate()
	_mirror_inst(inst, mirror)
	var sock := inst.get_node_or_null("Socket") as Node3D
	var sock_xf: Transform3D = sock.transform if sock != null else Transform3D.IDENTITY
	inst.free()
	var axf: Transform3D = t["xf"]
	return {"xf": axf * Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(rel)), Vector3.ZERO) * sock_xf.affine_inverse(), "mirror": mirror}


func _make_ghost(part_id: String, t: Dictionary) -> Node3D:
	var d := CraftEdit.part(part_id)
	if d == null or d.scene == null:
		return null
	var g := ghost_transform(part_id, t)
	var inst := d.scene.instantiate()
	_mirror_inst(inst, bool(g["mirror"]))
	var root := Node3D.new()
	root.name = "Ghost"
	for c in inst.get_children():
		if c is Node3D and String(c.name) == "Mesh":
			var xf := (c as Node3D).transform
			inst.remove_child(c)
			c.owner = null
			root.add_child(c)
			(c as Node3D).transform = xf
	inst.free()
	root.transform = g["xf"]
	var mat: Material = _mats["ghost"] if bool(t["ok"]) else _mats["ghost_bad"]
	_set_material_override(root, mat)
	return root


## Зеркало детали правой стороны — как ModularDoll._mirror_part (меш Mesh_R, если есть, иначе M·T; маркеры M·T·M).
static func _mirror_inst(inst: Node, on: bool) -> void:
	var mesh_r := inst.get_node_or_null("Mesh_R") as Node3D
	var mesh := inst.get_node_or_null("Mesh") as Node3D
	if not on:
		if mesh_r != null:
			inst.remove_child(mesh_r)
			mesh_r.free()
		return
	if mesh_r != null:
		if mesh != null:
			inst.remove_child(mesh)
			mesh.free()
		mesh_r.name = "Mesh"
		mesh_r.visible = true
		mesh_r.transform = ModularDoll._mirrored(mesh_r.transform)
	elif mesh != null:
		mesh.transform = Transform3D(ModularDoll.MIRROR_X, Vector3.ZERO) * mesh.transform
	for c in inst.get_children():
		if c is Marker3D or c is CollisionShape3D:
			(c as Node3D).transform = ModularDoll._mirrored((c as Node3D).transform)


# =================================================================== выбор мышью, подсветка

## Деталь под экранной точкой: {target: "body"|"weapon", uid} или {}.
func pick(screen_pos: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null or mode != Mode.BUILD:
		return {}
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 60.0
	var q := PhysicsRayQueryParameters3D.create(from, to, PICK_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var col := hit.get("collider") as CollisionObject3D
	if col == null:
		return {}
	var sidx := int(hit.get("shape", 0))
	var owner_id := col.shape_find_owner(sidx)
	var shape_node := col.shape_owner_get_owner(owner_id) as Node
	if bench_weapon != null and (col == bench_weapon or bench_weapon.links.has(col)):
		var uid := String(shape_node.name).get_slice("_", 0) if shape_node != null else ""
		return {"target": "weapon", "uid": uid} if not CraftEdit.find(weapon_bp, uid).is_empty() else {}
	if stand != null and col.get_parent() == stand:
		var key := "%s/%s" % [col.name, shape_node.name if shape_node != null else ""]
		var uid2 := String(_shape_uid.get(key, _own_uid.get(String(col.name), "")))
		return {"target": "body", "uid": uid2} if uid2 != "" else {}
	return {}


func uid_title(target: String, uid: String) -> String:
	var d := CraftEdit.def_of(weapon_bp if target == "weapon" else blueprint, uid)
	return d.title if d != null else uid


## Название детали и (у тела) её материал и шарнир: «Плечо · Железо, 4.4 кг · шарнир «Мотор»».
func part_info(target: String, uid: String) -> String:
	var s := uid_title(target, uid)
	if target != "body" or CraftEdit.find(blueprint, uid).is_empty():
		return s
	var mid := blueprint.node_mat(uid)
	if mid != "":
		s += " · %s, %.1f кг" % [CraftEdit.mat_title(mid), blueprint.node_mass(uid)]
	var jt := blueprint.joint_type_of(uid)
	if jt != "" and jt != KitJoint.DEFAULT:
		s += " · шарнир «%s»" % CraftEdit.joint_title(jt)
	return s


## Меши детали uid: у детали-хозяина — узел Mesh её тела; у fixed-детали — Mesh_<uid> в теле-хозяине; у оружия — <uid>_<id>.
func part_meshes(target: String, uid: String) -> Array:
	var out: Array = []
	if target == "weapon":
		if bench_weapon == null or not bench_weapon.parts_info.has(uid):
			return out
		var m: Variant = bench_weapon.parts_info[uid].get("mesh")
		if m is Node3D and is_instance_valid(m):
			out.append(m)
		return out
	if stand == null or not stand.uid_body.has(uid):
		return out
	var n := CraftEdit.find(blueprint, uid)
	var d := CraftEdit.part(String(n.get("part", "")))
	var body := stand.parts.get(String(stand.uid_body[uid])) as Node3D
	if body == null or d == null:
		return out
	var fixed := CraftEdit.is_fixed(blueprint, uid)
	var mn := body.get_node_or_null("Mesh_" + uid if fixed else "Mesh")
	if mn != null:
		out.append(mn)
	return out


func _make_materials() -> void:
	_mats["control"] = _overlay_mat(Color(1.0, 0.78, 0.2, 0.42))
	_mats["hover"] = _overlay_mat(Color(1.0, 0.97, 0.85, 0.22))
	_mats["remove"] = _overlay_mat(Color(1.0, 0.25, 0.18, 0.45))
	_mats["replace"] = _overlay_mat(Color(1.0, 0.55, 0.15, 0.4))
	_mats["pick"] = _overlay_mat(Color(1.0, 0.85, 0.35, 0.3))
	var g := StandardMaterial3D.new()
	g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.55, 0.9, 1.0, 0.5)
	g.cull_mode = BaseMaterial3D.CULL_BACK
	g.no_depth_test = false
	_mats["ghost"] = g
	var gb := g.duplicate() as StandardMaterial3D
	gb.albedo_color = Color(1.0, 0.35, 0.3, 0.45)
	_mats["ghost_bad"] = gb


static func _overlay_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	return m


static func _set_material_override(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = m
	for c in n.get_children():
		_set_material_override(c, m)


static func _set_overlay(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = m
	for c in n.get_children():
		_set_overlay(c, m)


## Подсветка: золото — управляемая деталь; белый — под курсором; красный — будет откручено (ПКМ по наведённой) / заменено.
func _apply_highlights() -> void:
	if stand != null:
		for b in stand.parts.values():
			_set_overlay(b, null)
	if bench_weapon != null:
		for b in bench_weapon.bodies():
			_set_overlay(b, null)
	if mode != Mode.BUILD:
		return
	for c in blueprint.control:
		for m in part_meshes("body", c):
			_set_overlay(m, _mats["control"])
	if not drag.is_empty():
		var t := drag_target()
		if not t.is_empty() and String(t["replace"]) != "":
			var bp: Resource = weapon_bp if String(t["target"]) == "weapon" else blueprint
			for u in CraftEdit.subtree(bp, String(t["replace"])):
				for m in part_meshes(String(t["target"]), u):
					_set_overlay(m, _mats["replace"])
		return
	if not hover.is_empty():
		var tg := String(hover["target"])
		var hu := String(hover["uid"])
		var mat: Material = _mats["pick"] if control_pick else _mats["hover"]
		var uids: PackedStringArray = [hu]
		if control_pick:
			uids = [CraftEdit.host_uid(blueprint, hu)]
		elif tg == "body" and paint_mat != "":   # кисть: цвет материала — покрасится, красный — не красится
			var md := MaterialDef.get_def(paint_mat)
			var sw := md.swatch if md != null else Color.WHITE
			mat = _tint("paint_" + paint_mat, sw) if bool(CraftEdit.check_material(blueprint, hu, paint_mat)["ok"]) else _mats["remove"]
		elif tg == "body" and joint_pick != "":   # шарнир: цвет типа — можно, красный — нельзя (корень, fixed, запреты)
			mat = _tint("joint_" + joint_pick, JointCard.colour(joint_pick)) if bool(CraftEdit.check_joint(blueprint, hu, joint_pick)["ok"]) \
				else _mats["remove"]
		elif tg == "body" and paint_tool != "":   # покраска: заливка — цветом краски (и пара), раскраска — деталь и пара / вся кукла
			var pm := paint.hover_material()
			if pm != null:
				mat = pm
			uids = PackedStringArray(paint.hover_uids(hu))
		for u in uids:
			for m in part_meshes(tg, u):
				_set_overlay(m, mat)


## Подсветка инструмента цветом c (плашка материала, тип шарнира), кэш в _mats[key].
func _tint(key: String, c: Color) -> Material:
	if not _mats.has(key):
		_mats[key] = _overlay_mat(Color(c.r, c.g, c.b, 0.5).lightened(0.1))
	return _mats[key]


func set_hover(h: Dictionary) -> void:
	if h == hover:
		return
	hover = h
	_apply_highlights()
	changed.emit()


# =================================================================== ввод

func _input(event: InputEvent) -> void:
	if mode == Mode.TEST:
		if event is InputEventKey and event.pressed and not event.echo:
			var k := (event as InputEventKey).physical_keycode
			if k == KEY_ESCAPE or k == KEY_TAB:
				stop_test()
				get_viewport().set_input_as_handled()
			elif k == KEY_R:
				restart_test()
				get_viewport().set_input_as_handled()
		return
	if drag.is_empty():
		return
	if event is InputEventMouseMotion:
		update_drag((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel_drag()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not bool(drag["sticky"]):
			if bool(drag["moved"]):
				end_drag(mb.position)
			else:
				drag["sticky"] = true   # клик по карточке: деталь «в руке», ставится следующим кликом
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and bool(drag["sticky"]):
			if ui != null and ui.has_method("is_over_panel") and bool(ui.call("is_over_panel", mb.position)):
				cancel_drag()   # клик по другой карточке — начнёт новую протяжку
			else:
				end_drag(mb.position)
				get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		cancel_drag()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.BUILD:
		return
	if paint != null and paint.handle_input(event):   # покраска: штрих, наклейки, колесо, Q / E, R — первыми
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mp := (event as InputEventMouseMotion).position
		set_hover(paint.hover_pick(mp) if paint_tool != "" else pick(mp))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		var h := pick(mb.position)
		var on_body := not h.is_empty() and String(h["target"]) == "body"
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if active_tool() != "":
				clear_tools()   # ПКМ с инструментом в руке — положить его, а не откручивать
			elif not h.is_empty():
				hover = {}
				detach_part(String(h["uid"]), String(h["target"]))
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if control_pick:
				if on_body:
					set_control(String(h["uid"]))
				else:
					_say("Кликни по детали куклы (Esc — отмена)", COL_WARN)
				get_viewport().set_input_as_handled()
			elif paint_mat != "":
				if on_body:
					set_material(String(h["uid"]))
				else:
					_say("Кисть: кликни по детали куклы (Esc / ПКМ — убрать кисть)", COL_WARN)
				get_viewport().set_input_as_handled()
			elif joint_pick != "":
				if on_body:
					set_joint(String(h["uid"]))
				else:
					_say("Шарнир: кликни по детали куклы (Esc / ПКМ — отмена)", COL_WARN)
				get_viewport().set_input_as_handled()
			elif not h.is_empty():
				_say("%s — ПКМ: открутить%s" % [part_info(String(h["target"]), String(h["uid"])),
					"" if String(h["target"]) == "weapon" else ",  Q и клик: рука мышью"], COL_INFO)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.physical_keycode:
			KEY_Q:
				toggle_control_pick()
			KEY_T, KEY_ENTER, KEY_KP_ENTER:
				start_test()
			KEY_TAB:
				set_view(View.WEAPON if view == View.BODY else View.BODY)
			KEY_Z:
				if k.ctrl_pressed or k.meta_pressed:
					undo()
			KEY_R:
				if paint != null and paint.tab_open and view == View.BODY:
					paint.turn_stand(-1 if k.shift_pressed else 1)   # полка «Покраска» без инструмента: тоже крутит стенд
			KEY_ESCAPE:
				if not clear_tools():   # инструмент в руке — Esc его кладёт; иначе двойной Esc — выход
					if _time < _esc_armed_until:
						_flush_autosave(true)
						get_tree().quit()
					else:
						_esc_armed_until = _time + 1.5
						_say("Esc ещё раз — выход", COL_INFO)
			_:
				return
		get_viewport().set_input_as_handled()


func set_view(v: int) -> void:
	if v == view:
		return
	cancel_drag()
	view = v
	if view == View.WEAPON:
		control_pick = false
		paint_mat = ""
		joint_pick = ""
		set_paint_tool("")
		if paint != null:
			paint.reset_turn()
	set_hover({})
	view_changed.emit(view)
	changed.emit()


# =================================================================== испытание

## Кукла оживает: обычная физика, WASD, рука мышью, подбор оружия, манекен и предметы рядом. false — чертёж с ошибками.
func start_test() -> bool:
	if mode == Mode.TEST:
		return true
	var errs := CraftEdit.friendly_errors(blueprint)
	if not errs.is_empty():
		_say(errs[0], COL_BAD)
		return false
	cancel_drag()
	control_pick = false
	paint_mat = ""
	joint_pick = ""
	set_paint_tool("")
	if paint != null:
		paint.reset_turn()
	hover = {}
	if autosave_on_test:
		CraftEdit.save(blueprint, autosave_name)
		_autosave_dirty = false
	mode = Mode.TEST
	_clear_ghost()
	_free_node(held_weapon)
	held_weapon = null
	_free_node(stand)
	stand = null
	_free_node(bench_weapon)
	bench_weapon = null
	var d := MODULAR_DOLL.instantiate() as ModularDoll
	d.name = "Player"
	d.blueprint = CraftEdit.dup_body(blueprint)
	d.player_index = 0
	d.input_prefix = "p1"
	d.external_input = probe_input
	d.position = stand_root.global_position + Vector3(0, 0.02, 0)
	test_root.add_child(d)
	d.add_to_group(TEST_GROUP)
	test_doll = d
	var pickup := WeaponPickup.attach_to(d)
	ArmAssist.attach_to(d)
	var combat := DollCombat.new()
	combat.name = "DollCombat"
	d.add_child(combat)
	if blueprint.weapon != null:
		var m := _mount_for(d)
		if String(m["uid"]) != "":
			var w := CraftedWeapon.create(CraftEdit.dup_weapon(blueprint.weapon as WeaponBlueprint))
			w.name = "CraftedWeapon"
			w.transform = mount_transform(d, m)
			test_root.add_child(w)
			var saved := pickup.hand_grip_offset
			pickup.hand_grip_offset = grip_offset(d, m)
			pickup.attach(String(d.uid_body[String(m["uid"])]), w)
			pickup.hand_grip_offset = saved
			test_weapon = w
	dummy = DummyScript.new()
	dummy.name = "TrainingDummy"
	dummy.position = dummy_spot.global_position
	test_root.add_child(dummy)
	dummy.connect("hit", func(a: float, p: Vector3, part: String, kind: String) -> void: dummy_hit.emit(a, p, part, kind))
	dummy.connect("respawned", func(dd: Doll) -> void: dd.add_to_group(TEST_GROUP))
	var dd: Doll = dummy.get("doll")
	if dd != null:
		dd.add_to_group(TEST_GROUP)
	for spec in [[CRATE_SCENE, crate_spot], [BARREL_SCENE, barrel_spot]]:
		var ps := load(String(spec[0])) as PackedScene
		if ps != null:
			var it := ps.instantiate() as Node3D
			it.position = (spec[1] as Node3D).global_position
			test_root.add_child(it)
	test_cam = DynamicCamera.new()
	test_cam.name = "TestCamera"
	test_cam.fov = 45.0
	test_cam.target_group = TEST_GROUP
	test_cam.arena_path = NodePath("../Workshop")
	test_cam.floor_inset = 0.0
	test_cam.min_half_height = 1.9
	test_cam.padding = 1.5
	test_cam.padding_y = 1.0
	add_child(test_cam)
	test_cam.make_current()
	test_cam.snap()
	mode_changed.emit(mode)
	changed.emit()
	_say("Испытание! Esc / Tab — назад к сборке", COL_OK)
	return true


## R в испытании: всё заново (кукла на стенде, манекен и предметы — новые).
func restart_test() -> void:
	if mode != Mode.TEST:
		return
	var probe := probe_input
	stop_test()
	probe_input = probe
	start_test()


## Кисть или конец детали для оружия у куклы испытания (uid должен быть в кукле).
func _mount_for(d: ModularDoll) -> Dictionary:
	var m := _mount()
	if String(m["uid"]) == "" or not d.uid_body.has(String(m["uid"])):
		return {"uid": "", "kind": "", "reason": m.get("reason", "")}
	return m


func stop_test() -> void:
	if mode != Mode.TEST:
		return
	for c in test_root.get_children():
		test_root.remove_child(c)
		c.queue_free()
	test_doll = null
	test_weapon = null
	dummy = null
	if test_cam != null:
		_free_node(test_cam)
		test_cam = null
	build_cam.make_current()
	_cam_snap = true
	mode = Mode.BUILD
	_rebuild()
	mode_changed.emit(mode)
	_say("Назад к сборке", COL_INFO)


# =================================================================== сводки для UI

## Сводка тела для правой панели. Масса — Σ BodyBlueprint.node_mass (материал узла × плотность, BODY_KIT.md §4), тела — узлы
## не is_fixed (сварка тело убирает).
func body_stats() -> Dictionary:
	var mass := blueprint.total_mass()
	var wmass := 0.0
	if blueprint.weapon != null:
		for n in (blueprint.weapon as WeaponBlueprint).nodes:
			var d := CraftEdit.part(String(n.get("part", "")))
			if d != null:
				wmass += d.mass
	var bodies := 0
	for n in blueprint.nodes:
		var d2 := CraftEdit.part(String(n.get("part", "")))
		if d2 != null and not CraftEdit.is_fixed(blueprint, String(n.get("uid", ""))):
			bodies += 1
	var ref := 40.0
	if stand != null:
		ref = stand.thrust_mass()
	var ctrl := ""
	if not blueprint.control.is_empty():
		ctrl = uid_title("body", blueprint.control[0])
	var weapon_line := ""
	if blueprint.weapon != null:
		var m := _mount()
		weapon_line = "%s → %s" % [(blueprint.weapon as WeaponBlueprint).title.trim_suffix(" *"),
			uid_title("body", String(m["uid"])) if String(m["uid"]) != "" else "некуда"]
	return {"title": blueprint.title, "energy": blueprint.energy_used(), "budget": blueprint.energy_budget, "mass": mass,
		"weapon_mass": wmass, "bodies": bodies, "parts": blueprint.nodes.size(), "accel": ref / maxf(mass + wmass, 0.1),
		"control": ctrl, "weapon": weapon_line, "errors": CraftEdit.friendly_errors(blueprint),
		"warnings": CraftEdit.warnings(blueprint)}


## Оружие верстака: цифры CraftedWeapon.summary() и слова. [{label, value, word, frac}] + ошибки.
func weapon_stats() -> Dictionary:
	var out := {"title": weapon_bp.title if weapon_bp != null else "", "rows": [], "errors": CraftEdit.friendly_errors(weapon_bp),
		"empty": weapon_bp == null or weapon_bp.nodes.is_empty(), "equipped": blueprint.weapon != null}
	if bench_weapon == null:
		return out
	var s := bench_weapon.summary()
	var mass := float(s["mass"])
	var com := float(s["com_from_grip"])
	var ln := float(s["length"])
	var inertia := float(s["inertia_grip"])
	var mult := float(s["damage_mult"])
	var bal := com / maxf(ln, 0.01)
	out["rows"] = [
		{"label": "Масса", "value": "%.1f кг" % mass, "frac": mass / 8.0,
			"word": "пёрышко" if mass < 1.5 else ("в самый раз" if mass < 3.0 else ("тяжёлое" if mass < 5.0 else ("очень тяжёлое" if mass < 7.5 else "неподъёмное")))},
		{"label": "Центр масс", "value": "%.2f м от хвата" % com, "frac": bal,
			"word": "у руки: послушное" if bal < 0.35 else ("посередине" if bal < 0.62 else "в головке: тянет в замах")},
		{"label": "Длина", "value": "%.2f м" % ln, "frac": ln / 2.0,
			"word": "короткое" if ln < 0.5 else ("среднее" if ln < 0.95 else "длинное: большой рычаг")},
		{"label": "Раскрутка", "value": "%.2f кг·м²" % inertia, "frac": inertia / 3.0,
			"word": "вертится легко" if inertia < 0.15 else ("надо раскрутить" if inertia < 0.6 else ("туго, зато не остановить" if inertia < 1.6 else "мельница"))},
		{"label": "Урон", "value": "×%.2f" % mult, "frac": (mult - 1.0) / 1.5,
			"word": "тупое — бьёт массой" if mult < 1.05 else ("шипы / крюк" if mult < 1.3 else "лезвие: режет")},
	]
	out["bodies"] = int(s["bodies"])
	out["summary"] = s
	return out


## Подсказка внизу экрана по состоянию.
func hint_text() -> String:
	if mode == Mode.TEST:
		return "WASD — лететь · Shift — рывок · Space — кувырок · ЛКМ — рука · E — схватить / бросить · R — заново · Esc — к сборке"
	if paint_tool != "":
		return paint.hint_text()
	if paint != null and paint.tab_open and view == View.BODY:
		return "Выбери инструмент на полке «Покраска»: баллончик, трафарет, наклейка, фото…   ·   R — повернуть стенд"
	if control_pick:
		return "Кликни по детали, которой будешь управлять мышью (золотая)   ·   Esc / ПКМ — отмена"
	if paint_mat != "":
		var mt := CraftEdit.mat_title(paint_mat)
		if not hover.is_empty() and String(hover["target"]) == "body":
			var hu := String(hover["uid"])
			var c := CraftEdit.check_material(blueprint, hu, paint_mat)
			if not bool(c["ok"]):
				return String(c["reason"])
			if not bool(c["changed"]):
				return "%s — уже %s   ·   Esc / ПКМ — убрать кисть" % [uid_title("body", hu), mt]
			return "Клик — %s: %s → %s, %.1f → %.1f кг   ·   Esc / ПКМ — убрать кисть" % [uid_title("body", hu),
				CraftEdit.mat_title(String(c["mat_before"])), mt, float(c["mass_before"]), float(c["mass_after"])]
		return "Кисть «%s»: кликни по детали куклы — перекрасить (масса × новая плотность / прежняя)   ·   Esc / ПКМ — убрать кисть" % mt
	if joint_pick != "":
		var jt := CraftEdit.joint_title(joint_pick)
		if not hover.is_empty() and String(hover["target"]) == "body":
			var hu2 := String(hover["uid"])
			var cj := CraftEdit.check_joint(blueprint, hu2, joint_pick)
			if not bool(cj["ok"]):
				return String(cj["reason"])
			if not bool(cj["changed"]):
				return "%s — уже «%s»   ·   Esc / ПКМ — отмена" % [uid_title("body", hu2), jt]
			return "Клик — %s: «%s» → «%s»   ·   Esc / ПКМ — отмена" % [uid_title("body", hu2),
				CraftEdit.joint_title(String(cj["joint_before"])), jt]
		return "Шарнир «%s»: кликни по детали — так она будет держаться за родителя   ·   Esc / ПКМ — отмена" % jt
	if not drag.is_empty():
		var t := drag_target()
		if not t.is_empty() and not bool(t["ok"]):
			return String(t["reason"])
		if not t.is_empty() and String(t["replace"]) != "":
			return "Отпусти — заменить «%s»   ·   ПКМ / Esc — отмена" % uid_title(String(t["target"]), String(t["replace"]))
		if bool(drag["sticky"]):
			return "Кликни у зелёного якоря — поставить   ·   ПКМ / Esc — убрать деталь"
		return "Поднеси к зелёному якорю и отпусти   ·   ПКМ / Esc — отмена"
	if not hover.is_empty():
		var bp: Resource = weapon_bp if String(hover["target"]) == "weapon" else blueprint
		var n := CraftEdit.subtree(bp, String(hover["uid"])).size()
		var more := "" if n <= 1 else " (+%d)" % (n - 1)
		return "%s   ·   ПКМ — открутить%s   ·   Q — рука мышью" % [part_info(String(hover["target"]), String(hover["uid"])), more]
	if view == View.WEAPON:
		return "Тащи рукоять, навершие или мод на верстак   ·   ПКМ по детали — снять   ·   «В руку» — дать кукле   ·   Tab — к телу"
	return "Тащи деталь с полки на светящийся якорь   ·   ПКМ — открутить   ·   Q — рука мышью   ·   Ctrl+Z — отмена   ·   T — испытать"


## Что рисовать поверх 3D (scenes/workshop/ui/anchor_overlay.gd): [{pos, dir, state, label, joint?}] в экранных точках.
## state: target (выбран), ok, replace, bad (не влезает), idle (свободный якорь без протяжки), control (рука мышью),
## joint / joint_hover (инструмент шарнира: точка связи детали с родителем, joint — тип KitJoint, наведённая — joint_hover).
func overlay_items() -> Array:
	var out: Array = []
	var cam := get_viewport().get_camera_3d()
	if cam == null or mode != Mode.BUILD:
		return out
	if not drag.is_empty():
		var targets: Array = drag["targets"]
		for i in range(targets.size()):
			var t: Dictionary = targets[i]
			if not bool(t["accepts"]):
				continue
			var st := "ok"
			if i == int(drag["index"]):
				st = "target" if bool(t["ok"]) else "bad"
			elif not bool(t["ok"]):
				st = "bad"
			elif String(t["replace"]) != "":
				st = "replace"
			out.append(_overlay_item(cam, t["xf"], st, ""))
		return out
	var target := "weapon" if view == View.WEAPON else "body"
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	if target == "body" and paint != null and (paint_tool != "" or paint.tab_open):
		return out   # покраска: точки якорей мешали бы красить
	# инструмент шарнира: на каждой связи — кружок цвета типа и подпись (кроме обычной оси), наведённая деталь — крупнее
	if target == "body" and joint_pick != "":
		var hu := String(hover.get("uid", "")) if String(hover.get("target", "")) == "body" else ""
		for n in blueprint.nodes:
			var uid := String(n.get("uid", ""))
			var jt := blueprint.joint_type_of(uid)
			if jt == "":
				continue
			var xf: Variant = anchor_xf("body", String(n.get("parent", "")), String(n.get("anchor", "")))
			if xf == null:
				continue
			var it := _overlay_item(cam, xf, "joint_hover" if uid == hu else "joint", "" if jt == KitJoint.DEFAULT else CraftEdit.joint_title(jt))
			it["joint"] = jt
			out.append(it)
		return out
	# без протяжки: свободные якоря текущего вида — маленькие точки
	for n in CraftEdit.nodes_of(bp):
		var uid := String(n.get("uid", ""))
		for an in CraftEdit.anchors_of(bp, uid):
			if CraftEdit.occupant(bp, uid, an) != "":
				continue
			var xf: Variant = anchor_xf(target, uid, an)
			if xf != null:
				out.append(_overlay_item(cam, xf, "idle", ""))
	if target == "body" and stand != null:
		for c in blueprint.control:
			var ms := part_meshes("body", c)
			if not ms.is_empty():
				var box := _visual_aabb(ms[0])
				out.append({"pos": cam.unproject_position(box.get_center()), "dir": Vector2.ZERO, "state": "control", "label": "РУКА"})
	return out


func _overlay_item(cam: Camera3D, xf: Transform3D, state: String, label: String) -> Dictionary:
	var p := cam.unproject_position(xf.origin)
	var tip := cam.unproject_position(xf.origin - xf.basis.y.normalized() * 0.12)
	var dir := (tip - p)
	return {"pos": p, "dir": dir.normalized() if dir.length() > 0.5 else Vector2.ZERO, "state": state, "label": label}


static func _visual_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is VisualInstance3D and (cur as Node3D).is_visible_in_tree():
			var b := (cur as VisualInstance3D).global_transform * (cur as VisualInstance3D).get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in cur.get_children():
			stack.append(c)
	return out


# =================================================================== камера сборки

func _process(delta: float) -> void:
	_time += delta
	if mode != Mode.BUILD:
		return
	if _autosave_dirty and _time >= _autosave_at:
		_flush_autosave()
	var goal := _camera_goal()
	if _cam_snap:
		_cam_pos = goal
		_cam_snap = false
	else:
		_cam_pos = _cam_pos.lerp(goal, 1.0 - exp(-delta / CAM_TAU))
	build_cam.global_transform = Transform3D(Basis.IDENTITY, _cam_pos)


## Куда встать камере: кукла (или оружие на верстаке) целиком в свободной середине экрана между панелями.
func _camera_goal() -> Vector3:
	var box := AABB(stand_root.global_position + Vector3(-0.5, 0.0, -0.2), Vector3(1.0, 1.9, 0.4))
	var min_h := 1.25
	if view == View.WEAPON:
		box = AABB(bench_spot.global_position + Vector3(-0.1, -0.35, -0.1), Vector3(1.3, 0.7, 0.2))
		if bench_weapon != null:
			box = _visual_aabb(bench_weapon)
		min_h = 0.55
	elif stand != null:
		box = _visual_aabb(stand)
		if held_weapon != null:
			box = box.merge(_visual_aabb(held_weapon))
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_w_frac := FREE_W_FRAC   # доля ширины экрана, где кукла
	var need_h := maxf(box.size.y * 0.5 + 0.28, (box.size.x * 0.5 + 0.25) / (aspect * half_w_frac))
	need_h = maxf(need_h, min_h)
	var dist := need_h / tan(deg_to_rad(CAM_FOV) * 0.5)
	var c := box.get_center()
	# низ экрана занят подсказкой — кукла чуть выше середины
	return Vector3(c.x, c.y - need_h * 0.06, c.z + dist)


func _say(text: String, colour: Color) -> void:
	if text == "":
		return
	toast.emit(text, colour)
