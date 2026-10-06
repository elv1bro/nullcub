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
## Пробный режим «Запас из деталей» (PartHp) переключён клавишей «;» — UI перестраивает полку (❤ на карточках, энергия ядра и головы).
signal parts_hp_toggled
signal toast(text: String, colour: Color)
signal mode_changed(mode: int)
signal view_changed(view: int)
signal dummy_hit(amount: float, position: Vector3, part: String, kind: String)
## Выбор (UI v0.2, контекстная правая панель): {} — ничего; {"source": "shelf", "part": id} — деталь каталога;
## {"source": "stand", "target": "body" | "weapon", "uid": uid} — деталь на кукле / верстаке.
signal selection_changed
## Встроенная мастерская (в гараже меню, scenes/menu/garage_workshop.gd): двойной Esc просит гараж забрать управление.
signal exit_requested

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
const MAGNET_PX := 150.0          # v0.3: в этом радиусе деталь под курсором начинает поворачиваться и тянуться к разъёму
const SNAP_IN_PX := 34.0         # ближе — деталь в руке садится на разъём целиком
const CARRY_DEPTH := 0.35         # деталь под курсором — на столько ближе к камере, чем стенд
const BIG_BRANCH := 5             # удаление ветки от стольких деталей — второе нажатие Del
const ORBIT_YAW_MAX := 70.0
const ORBIT_PITCH := Vector2(-10.0, 35.0)
const ZOOM_RANGE := Vector2(0.55, 1.7)
const EDGE_PAN_PX := 70.0         # протяжка у края рабочей зоны — камера мягко смещается
const FLASH_S := 0.4
const REFUSE_S := 1.1
const DRAG_MOVE_PX := 10.0        # сдвиг, после которого нажатие на карточку — протяжка, а не клик
const HISTORY_MAX := 50
const HOLD_ANGLE_DEG := 90.0      # как WeaponPickup.hold_angle_deg: оружие в кисти в сторону от тела
const HAND_GRIP := Vector3(0, -0.03, 0)   # WeaponPickup.hand_grip_offset
const CAM_FOV := 38.0
## Свободная середина экрана между панелями (UI: слева и справа по 460 px из 1920) — по ней вписывается кукла.
const FREE_W_FRAC := 0.47   # UI v0.2: каталог 606 px + правая панель 404 px — кукле ~47 % ширины
const FREE_CX_FRAC := 0.553  # середина свободной зоны по ширине (606 … 1516 px из 1920)
const FREE_H_FRAC := 0.78    # по высоте: между верхней панелью (92 px) и кнопкой ИСПЫТАТЬ
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
## Арена, чьи bounds() ограничивают камеру испытания: в отдельной сцене — комната «Workshop», в гараже — невидимая сцена-коробка Stage.
@export var test_arena_path := NodePath("../Workshop")
## Кого ведёт камера испытания (DynamicCamera.follow_mode): "humans" — только куклу игрока (во встроенной мастерской манекен висит
## в зале за 16 м — в кадр целиком он не влезет); "all" — всех из группы (отдельная мастерская).
@export var test_follow_mode := "all"
## Наименьшая полувысота кадра камеры испытания, м: в гараже (потолок 3.4 м) меньше, чем в большой комнате мастерской.
@export var test_min_half_height := 1.9
## Встроенная мастерская (в гараже меню): своей комнаты нет (арены $Workshop нет), выход из мастерской — сигналом exit_requested,
## а не сменой сцены. Пока мастерская не активна (set_active(false)), она спит: ввод, процессы, UI и 3D скрыты.
var embedded := false
var active := true
## Встроенная мастерская: «зал готов?» — GarageWorkshop; false — испытание не стартует (зал грузится под лоадером и стартует сам).
var test_ready_check := Callable()
## Мастерская кампании: Esc без инструмента и выбора выходит сразу (в обычной — двойной Esc).
var single_esc_exit := false

var blueprint: BodyBlueprint
var weapon_bp: WeaponBlueprint
var mode := Mode.BUILD
var view := View.BODY
var stand: ModularDoll
var bench_weapon: CraftedWeapon
var held_weapon: CraftedWeapon          # оружие в кисти куклы на стенде (только показ)
var drag: Dictionary = {}                # {part, targets, index, sticky, start, pos, moved}
## Пробные сборки по разъёмам (ветка / копия: решает сборка целиком, ~3–5 мс на разъём) считаются порциями: первые TRIAL_FIRST_MS — в кадре
## захвата, остальное по TRIAL_FRAME_MS за кадр (раньше все разом: 60–130 мс на захват ветки). Пока не досчитано, разъём показывается
## по проверке одной детали; под курсором пробу считаем сразу (_ensure_trial). В пробах (probe_input) — синхронно.
const TRIAL_FIRST_MS := 6.0
const TRIAL_FRAME_MS := 3.0
var _trial_queue: Array = []             # индексы drag["targets"], чья проба впереди
var _trial_hint := false                 # после очереди пересказать «некуда поставить / не хватает энергии»
var control_pick := false
## Цвета тяг: ЛКМ — золото (как прежняя рука мышью), ПКМ — голубой.
const PULL_COLOURS := {"lmb": Color(1.0, 0.78, 0.2), "rmb": Color(0.35, 0.8, 1.0)}
var paint_mat := ""                      # кисть материала: id MaterialDef ("" — выключена)
var joint_pick := ""                     # инструмент шарнира: тип KitJoint ("" — выключен)
var link_pick := ""                      # инструмент связки: вид KitLink ("" — выключен; WORKSHOP_V4.md «Связки»)
var link_from: Dictionary = {}           # первый конец связки: {uid, pa (кадр тела), world}; {} — ещё не выбран
var _link_marker: MeshInstance3D         # шарик на первом конце
var paint: WorkshopPaint                 # покраска (BODY_PAINT.md §6): инструмент, кисть, наклейки, поворот стенда
## Инструмент покраски в руке ("" — нет): WorkshopPaint.tool.
var paint_tool: String:
	get:
		return paint.tool if paint != null else ""
var hover: Dictionary = {}               # {target: "body"|"weapon", uid}
var history: Array = []
var redo_stack: Array = []                 # отменённые правки (Ctrl+Y); любая новая правка его чистит
var selected: Dictionary = {}              # см. selection_changed
var show_com := false                      # Physics Overlay (v0.3: кнопка ФИЗИКА, по умолчанию выключен — модель чистая)
var physics_hints := true                  # при протяжке: ⚡ / кг у детали и «станет» справа
## v0.3: камера — орбита правой кнопкой, колесо — зум, R — сброс; кадр с гистерезисом (не отъезжает от мелких движений)
var cam_yaw := 0.0
var cam_pitch := 0.0
var cam_zoom := 1.0
var _cam_pan := Vector3.ZERO               # сдвиг у края экрана при протяжке (в системе камеры), тает после
var _frame_h := 0.0                        # полувысота кадра, которую держит камера
var _rmb: Dictionary = {}                  # {pos, moved} — зажата ПКМ: орбита или клик
var _lmb: Dictionary = {}                  # {uid, target, pos, moved} — нажатие по детали стенда: выбор или перенос
var _last_click := {"uid": "", "t": -10.0}
var _carry: Node3D                         # v0.3: настоящая 3D-деталь под курсором при протяжке
var _carry_xf := Transform3D.IDENTITY
var _carry_mirror := false
var _carry_see := false                    # деталь в руке полупрозрачная: села на разъём — это ещё предпросмотр, не установка
var _s_pivot := Vector3.ZERO               # сглаженное состояние камеры (кадр, орбита, зум)
var _s_h := 1.0
var _s_yaw := 0.0
var _s_pitch := 0.0
var _s_zoom := 1.0
var _frame_c := Vector3.ZERO
var _edge_t := 0.0
var _hidden_uids: PackedStringArray = []   # перенос ветки: её меши на стенде спрятаны, пока тащишь
var fx_events: Array = []                  # вспышки поверх 3D: [{kind: "flash"|"refuse", pos: Vector3, t0, text}]
var pending_mirror: Dictionary = {}        # предпросмотр зеркала: {uid, trial, new: PackedStringArray}
var _preview_bp: BodyBlueprint = null      # стенд строится из него (предпросмотр зеркала)
var _delete_armed: Dictionary = {}         # {uid, until} — удаление большой ветки ждёт второго Del
var recent_parts: PackedStringArray = []   # недавно поставленные детали (фильтр каталога «Недавние»)
## Настройки игрока в мастерской (избранное, фильтры библиотеки, «первая деталь уже была»); проба подменяет на свой файл.
static var prefs_path := "user://workshop_prefs.cfg"
var _reach_cache: Dictionary = {}          # вид детали -> наименьший вынос свободного подходящего разъёма (cheapest_cost)
var _reach_cache_rev := -1
var _reach_cache_n := -1
var _rev := 0                              # номер правки чертежа: проба протяжки от старого номера не применяется
var sfx: WsSfx                             # звуки мастерской: щелчок по материалу, откручивание, отказ, кнопки
var last_result: Dictionary = {}
## Испытание.
var test_doll: ModularDoll
var test_weapon: CraftedWeapon
var dummy: Node3D                        # training_dummy.gd
var test_cam: DynamicCamera
var feel: TrainingFeel                     # «сок» боя на испытании (эффекты, звук, стоп-кадр, слабые касания)
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

@onready var arena: Node3D = get_node_or_null("Workshop") as Node3D
@onready var build_cam: Camera3D = $BuildCamera
@onready var stand_root: Node3D = $Stand
@onready var bench_spot: Node3D = $BenchSpot
@onready var dummy_spot: Node3D = $DummySpot
@onready var crate_spot: Node3D = $CrateSpot
@onready var barrel_spot: Node3D = $BarrelSpot
@onready var test_root: Node3D = $TestRoot
@onready var test_spot: Node3D = get_node_or_null("TestSpot") as Node3D   # где оживает кукла испытания (есть — встроенная мастерская)
@onready var ui: Node = $UI


## Пропсы арены, которые стоят там, где висит манекен испытания (бочка и козлы у x ≈ 2–4).
const CLEAR_ARENA_PROPS := ["Props/Barrel_2", "Props/Sawhorse_1"]


func _ready() -> void:
	build_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # ездит в _process
	_warm_test_resources.call_deferred()
	embedded = arena == null
	if arena != null:
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
	if not embedded:
		build_cam.make_current()
	sfx = WsSfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
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
	cancel_mirror()
	clear_selection()   # uid у шаблонов одни и те же — выбор указал бы на чужую деталь
	_rebuild()
	_frame_h = 0.0   # новая сборка — кадр заново
	return true   # без «Шаблон: X» над бойцом (v0.3 §44): имя — в верхней панели


## Шаблон оружия на верстак (data/body/weapons/<id>.tres). Если оружие в руке — в руке тоже оно.
func set_weapon_preset(id: String) -> bool:
	var w := CraftEdit.load_weapon_preset(id)
	if w == null:
		return false
	_push_history()
	weapon_bp = w
	_sync_equipped()
	_rebuild()
	_say(tr("Верстак: %s") % w.title, COL_INFO)
	return true


func clear_weapon() -> void:
	_push_history()
	weapon_bp = WeaponBlueprint.new()
	weapon_bp.id = "custom"
	weapon_bp.title = tr("Своё оружие")
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
	var what := tr("Заменено") if String(r.get("replace", "")) != "" else tr("Прикручено")
	var extra := "" if (r.get("drops", PackedStringArray()) as PackedStringArray).is_empty() else tr(" (снято лишнее: %d)") % (r["drops"] as PackedStringArray).size()
	# фото со старой головы: у новой плашка утоплена / её нет (BodyPaint.face_plate_ok) — фото наклейкой на лицо, та же запись истории
	var lost := String(r.get("face_lost", ""))
	if target == "body" and lost != "" and paint != null:
		var rf := paint.set_face_image(lost, false)
		extra += tr(" — фото на лице наклейкой") if bool(rf.get("ok", false)) else tr(" — фото снято (у этой головы нет лица)")
	_say("%s: %s%s" % [what, _pname(d) if d != null else part_id, extra], COL_OK)
	return r


## Открутить деталь с поддеревом. Возвращает снятые uid.
func detach_part(uid: String, target := "body") -> PackedStringArray:
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	var n := CraftEdit.find(bp, uid)
	if n.is_empty():
		return PackedStringArray()
	if target == "body" and String(n.get("parent", "")) == "":
		_say(tr("Ядро не откручивается — перетащи другое ядро поверх, чтобы заменить"), COL_WARN)
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
	var tail := "" if gone.size() <= 1 else tr(" и ещё %d") % (gone.size() - 1)
	_say(tr("Откручено: %s%s") % [_pname(d) if d != null else uid, tail], COL_WARN)
	return gone


## Тяга (WORKSHOP_V3.md §3): клик по детали без тяги — тяга ЛКМ, по ЛКМ-тяге — на ПКМ, по ПКМ-тяге — снять. Инструмент остаётся
## в руке: можно пометить несколько деталей подряд (Esc / ПКМ / Q — положить).
func set_control(uid: String) -> Dictionary:
	var trial := CraftEdit.dup_body(blueprint)
	var r := CraftEdit.set_control(trial, uid)
	if not bool(r["ok"]):
		_say(String(r["reason"]), COL_BAD if String(r.get("code", "")) == "energy" else COL_WARN)
		return r
	_push_history()
	blueprint.control = trial.control
	blueprint.control_rmb = trial.control_rmb
	if blueprint.weapon != null:
		blueprint.weapon_on = String(CraftEdit.weapon_mount(blueprint)["uid"])
	_rebuild()
	var d := CraftEdit.def_of(blueprint, String(r["uid"]))
	var t := d.title if d != null else String(r["uid"])
	match String(r.get("code", "")):
		"cleared":
			_say(tr("Тяга снята: %s") % t, COL_WARN)
		"rmb":
			_say(tr("Тяга %s → ПКМ") % t, PULL_COLOURS["rmb"])
		_:
			var e := blueprint.pull_energy(String(r["uid"]))
			_say(tr("Тяга ЛКМ: %s%s") % [t, "  ·  ⚡%d" % e if e > 0 else tr("  ·  главная, бесплатно")], PULL_COLOURS["lmb"])
	return r


## Тяга детали кнопкой (v0.3: строка «Тяга — / ЛКМ / ПКМ» в паспорте детали): want — "" | "lmb" | "rmb". Одна запись истории.
func set_pull(uid: String, want: String) -> Dictionary:
	var trial := CraftEdit.dup_body(blueprint)
	var r := {"ok": true, "uid": uid, "code": "same"}
	var h := CraftEdit.host_uid(blueprint, uid)
	for i in range(3):
		if trial.pull_button(h) == want:
			break
		r = CraftEdit.set_control(trial, uid)
		if not bool(r["ok"]):
			_say(String(r["reason"]), COL_BAD if String(r.get("code", "")) == "energy" else COL_WARN)
			_play_sfx("invalid", null)
			return r
	if trial.control == blueprint.control and trial.control_rmb == blueprint.control_rmb:
		return {"ok": true, "uid": h, "code": "same"}
	_push_history()
	blueprint.control = trial.control
	blueprint.control_rmb = trial.control_rmb
	if blueprint.weapon != null:
		blueprint.weapon_on = String(CraftEdit.weapon_mount(blueprint)["uid"])
	_rebuild()
	var t := _pname(CraftEdit.def_of(blueprint, h))
	match want:
		"":
			_say(tr("Тяга снята: %s") % t, COL_WARN)
		"rmb":
			_say(tr("Тяга ПКМ: %s") % t, PULL_COLOURS["rmb"])
		_:
			_say(tr("Тяга ЛКМ: %s") % t, PULL_COLOURS["lmb"])
	_play_sfx("button", null)
	return {"ok": true, "uid": h, "code": want}


## Переименовать сборку (имя в верхней строке); пустое — не меняем.
func rename_build(title: String) -> bool:
	var t := title.strip_edges().trim_suffix(" *").strip_edges()
	var bp: Resource = weapon_bp if view == View.WEAPON else blueprint
	if t == "" or t == String(bp.get("title")).trim_suffix(" *"):
		return false
	cancel_mirror()
	_push_history()
	bp.set("title", t)
	if view == View.WEAPON:
		_sync_equipped()
	changed.emit()
	return true


func toggle_control_pick() -> void:
	cancel_mirror()
	control_pick = not control_pick
	if control_pick:
		paint_mat = ""
		joint_pick = ""
		_clear_link_tool()
		set_paint_tool("")
		cancel_drag()
		set_view(View.BODY)
	_apply_highlights()
	changed.emit()


# --- инструменты кита v2: кисть материала и тип шарнира (BODY_KIT.md §5.5) ---

## Взять кисть материала mat_id (тот же id ещё раз или "" — положить). Снимает «руку мышью», шарнир и протяжку.
func set_paint_mat(mat_id: String) -> void:
	cancel_mirror()
	if mat_id != "" and (mat_id == paint_mat or MaterialDef.get_def(mat_id) == null):
		mat_id = ""
	paint_mat = mat_id
	if paint_mat != "":
		control_pick = false
		joint_pick = ""
		_clear_link_tool()
		set_paint_tool("")
		cancel_drag()
		set_view(View.BODY)
		_say(tr("Кисть: %s — кликни по детали куклы") % CraftEdit.mat_title(paint_mat), MaterialDef.get_def(paint_mat).swatch.lightened(0.35))
	_apply_highlights()
	changed.emit()


## Взять инструмент шарнира jt (тот же ещё раз или "" — положить).
func set_joint_pick(jt: String) -> void:
	cancel_mirror()
	if jt != "" and (jt == joint_pick or not KitJoint.is_type(jt)):
		jt = ""
	joint_pick = jt
	if joint_pick != "":
		_clear_link_tool()
		control_pick = false
		paint_mat = ""
		set_paint_tool("")
		cancel_drag()
		set_view(View.BODY)
		_say(tr("Шарнир «%s» — кликни по детали куклы") % CraftEdit.joint_title(joint_pick), JointCard.colour(joint_pick))
	_apply_highlights()
	changed.emit()


## Взять инструмент связки вида t (тот же ещё раз или "" — положить; WORKSHOP_V4.md «Связки»): клик по точке одной детали, потом
## другой — связка; клик по связке — снять (у поршня тем же инструментом — сменить канал).
func set_link_pick(t: String) -> void:
	cancel_mirror()
	if t != "" and (t == link_pick or not KitLink.is_type(t)):
		t = ""
	_clear_link_tool()
	link_pick = t
	if link_pick != "":
		control_pick = false
		paint_mat = ""
		joint_pick = ""
		set_paint_tool("")
		cancel_drag()
		set_view(View.BODY)
		_say(tr("Связка «%s» — кликни по первой детали (клик по связке — снять)") % KitLink.title_of(link_pick), KitLink.colour(link_pick))
	_apply_highlights()
	changed.emit()


func _clear_link_tool() -> void:
	link_pick = ""
	_set_link_from({})


func _set_link_from(f: Dictionary) -> void:
	link_from = f
	if f.is_empty():
		if _link_marker != null and is_instance_valid(_link_marker):
			_link_marker.queue_free()
		_link_marker = null
		return
	if _link_marker == null or not is_instance_valid(_link_marker):
		_link_marker = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		_link_marker.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.albedo_color = KitLink.colour(link_pick)
		_link_marker.material_override = m
		add_child(_link_marker)
	_link_marker.global_position = f["world"]


## Клик инструментом связки: по связке — снять (поршень своим инструментом — сменить канал), по детали — первый / второй конец.
func _link_click(h: Dictionary) -> void:
	if h.is_empty():
		_say(tr("Связка: кликни по детали бойца (Esc / ПКМ — отмена)"), COL_WARN)
		return
	if String(h["target"]) == "link":
		var id := String(h["link"])
		var l := blueprint.find_link(id)
		if l.is_empty():
			return
		_push_history()
		if link_pick == "piston" and KitLink.uses_channel(String(l.get("type", ""))):
			var ch := CraftEdit.cycle_link_channel(blueprint, id)
			_name_custom_body()
			_rebuild()
			_say(tr("Поршень → канал %d (%s)") % [ch, ActiveBlocks.key_label("p1", ch)], COL_OK)
			return
		CraftEdit.remove_link(blueprint, id)
		_set_link_from({})
		_name_custom_body()
		_rebuild()
		_play_sfx("unscrew", null)
		_say(tr("Связка «%s» снята") % KitLink.title_of(String(l.get("type", ""))), COL_INFO)
		return
	if String(h["target"]) != "body" or stand == null:
		return
	var uid := String(h["uid"])
	if CraftEdit.is_fixed(blueprint, uid):   # декор, броня, сварка: конец — на детали-хозяине
		uid = String(_own_uid.get(String(stand.uid_body.get(uid, "")), ""))
	var body := stand.parts.get(String(stand.uid_body.get(uid, ""))) as RigidBody3D
	if uid == "" or body == null:
		return
	var world: Vector3 = h.get("pos", body.global_position)
	var local := body.global_transform.affine_inverse() * world
	if link_from.is_empty():
		_set_link_from({"uid": uid, "pa": local, "world": world})
		_play_sfx("button", null)
		_say(tr("Первый конец — %s. Теперь вторая деталь") % uid_title("body", uid), KitLink.colour(link_pick))
		changed.emit()
		return
	var len_m := (world - (link_from["world"] as Vector3)).length()
	var r := CraftEdit.add_link(blueprint, link_pick, String(link_from["uid"]), link_from["pa"], uid, local, len_m, true)
	last_result = r
	if not bool(r["ok"]):
		_say(String(r["reason"]), COL_BAD)
		_play_sfx("invalid", null)
		return
	_push_history()
	r = CraftEdit.add_link(blueprint, link_pick, String(link_from["uid"]), link_from["pa"], uid, local, len_m)
	last_result = r
	_set_link_from({})
	_name_custom_body()
	_rebuild()
	_play_sfx("snap", null)
	_say(tr("Связка «%s»: %.2f м · ⚡ %d") % [KitLink.title_of(link_pick), len_m, KitLink.energy_of(link_pick, len_m)], COL_OK)


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
	if link_pick != "":
		return "link"
	if paint_tool != "":
		return "paint"
	return ""


## Положить инструмент («рука мышью», кисть, шарнир, покраска). true — что-то было в руке.
func clear_tools() -> bool:
	var had := active_tool() != ""
	control_pick = false
	paint_mat = ""
	joint_pick = ""
	_clear_link_tool()
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
		_say(tr("%s — уже %s") % [what, CraftEdit.mat_title(mat_id)], COL_INFO)
		return r
	_push_history()
	r = CraftEdit.set_material(blueprint, uid, mat_id)
	last_result = r
	_name_custom_body()
	_rebuild()
	var dm := float(r["mass_after"]) - float(r["mass_before"])
	var m := MaterialDef.get_def(mat_id)
	_say(tr("%s: %s → %s  (%.1f → %.1f кг%s)") % [what, CraftEdit.mat_title(String(r["mat_before"])), m.title, float(r["mass_before"]),
		float(r["mass_after"]), "" if absf(dm) < 0.05 else ", %+.1f" % dm], m.swatch.lightened(0.35))
	return r


## Тип шарнира jt (по умолчанию — joint_pick) связи детали uid с родителем. История, node["joint"] ("pin" — ключ стирается),
## пересборка. {ok, code, reason, changed, energy_after} — CraftEdit.set_joint; отказ (корень, fixed-деталь, запреты weld, энергия)
## — с причиной.
## Канал активного блока uid (0 — снять, 1…3 — клавиша канала; docs/plan-demo/ACTIVE_BLOCKS.md): история, пересборка, тост.
func set_channel(uid: String, ch: int) -> void:
	var n := CraftEdit.find(blueprint, uid)
	if n.is_empty() or not ActiveBlocks.is_active(String(n.get("part", ""))) or ActiveBlocks.channel_of(n) == ch:
		return
	_push_history()
	CraftEdit.set_channel(blueprint, uid, ch)
	_name_custom_body()
	_rebuild()
	var d := CraftEdit.def_of(blueprint, uid)
	var what := d.title if d != null else uid
	if ch == 0:
		_say(tr("%s — без канала: в бою молчит") % what, COL_INFO)
	else:
		var same := 0
		for m in blueprint.nodes:
			if ActiveBlocks.channel_of(m) == ch:
				same += 1
		_say(tr("%s → канал %d (%s)%s") % [what, ch, ActiveBlocks.key_label("p1", ch), tr("  · на канале блоков: %d") % same if same > 1 else ""],
			COL_OK)


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
		_say(tr("%s — уже «%s»") % [what, CraftEdit.joint_title(jt)], COL_INFO)
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
		_say(tr("Сварка: %s — теперь часть «%s»%s") % [what, host.title if host != null else "", tail], COL_OK)
	else:
		_say(tr("Шарнир «%s» → «%s»: %s%s") % [CraftEdit.joint_title(String(r["joint_before"])), CraftEdit.joint_title(jt), what, tail], COL_OK)
	return r


## «В руку»: оружие верстака — в кисть сборки (blueprint.weapon + weapon_on). Повторно — снять. {ok, uid, kind, reason}.
func weapon_to_hand() -> Dictionary:
	if blueprint.weapon != null:
		_push_history()
		blueprint.weapon = null
		blueprint.weapon_on = ""
		_rebuild()
		_say(tr("Оружие снято с руки"), COL_WARN)
		return {"ok": true, "uid": "", "kind": "", "reason": "", "removed": true}
	if weapon_bp == null or weapon_bp.nodes.is_empty():
		_say(tr("Верстак пуст: положи рукоять"), COL_WARN)
		return {"ok": false, "uid": "", "kind": "", "reason": tr("Верстак пуст")}
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
	_say(tr("%s — в руку: %s%s") % [weapon_bp.title, where, "" if m["kind"] == "hand" else tr(" (на конце детали)")], COL_OK)
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
		blueprint.title = (blueprint.title if blueprint.title != "" else tr("Сборка")) + " *"


func _name_custom_weapon() -> void:
	if not weapon_bp.title.ends_with("*"):
		weapon_bp.title = (weapon_bp.title if weapon_bp.title != "" else tr("Оружие")) + " *"


# --- история ---

func _push_history() -> void:
	_drop_mirror()
	_rev += 1
	redo_stack.clear()
	history.append({"body": CraftEdit.dup_body(blueprint), "weapon": CraftEdit.dup_weapon(weapon_bp)})
	while history.size() > HISTORY_MAX:
		history.remove_at(0)
	mark_dirty()   # запись истории — перед правкой; сейв отложен (AUTOSAVE_DELAY_S), правка к нему уже будет в чертеже


func undo() -> bool:
	if history.is_empty() or mode != Mode.BUILD or (paint != null and paint.busy()):
		return false
	cancel_drag()   # пробы протяжки посчитаны от прежнего чертежа — деталь в руке кладём
	_drop_mirror()
	var s: Dictionary = history.pop_back()
	_rev += 1
	redo_stack.append({"body": CraftEdit.dup_body(blueprint), "weapon": CraftEdit.dup_weapon(weapon_bp)})
	blueprint = s["body"]
	weapon_bp = s["weapon"]
	_rebuild()
	mark_dirty()
	_play_sfx("undo", null)
	_say(tr("Отменено"), COL_INFO)
	return true


## Вернуть отменённое (Ctrl+Y / Ctrl+Shift+Z).
func redo() -> bool:
	if redo_stack.is_empty() or mode != Mode.BUILD or (paint != null and paint.busy()):
		return false
	cancel_drag()
	_drop_mirror()
	var s: Dictionary = redo_stack.pop_back()
	_rev += 1
	history.append({"body": CraftEdit.dup_body(blueprint), "weapon": CraftEdit.dup_weapon(weapon_bp)})
	blueprint = s["body"]
	weapon_bp = s["weapon"]
	_rebuild()
	mark_dirty()
	_play_sfx("redo", null)
	_say(tr("Возвращено"), COL_INFO)
	return true


# --- выбор, установить / дубликат / зеркало / удалить (UI v0.2) ---

func select_shelf(part_id: String) -> void:
	selected = {"source": "shelf", "part": part_id} if CraftEdit.part(part_id) != null else {}
	_apply_highlights()
	selection_changed.emit()


## Выбор детали на кукле / верстаке. branch — вся ветка (деталь и всё, что на ней: Shift-клик / двойной клик): дубликат и
## зеркало тогда — всей ветки.
func select_stand(uid: String, target := "body", branch := false) -> void:
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	var n := CraftEdit.find(bp, uid)
	selected = {"source": "stand", "target": target, "uid": uid, "branch": branch, "part": String(n.get("part", ""))} if not n.is_empty() else {}
	_apply_highlights()
	selection_changed.emit()


## Выбранные uid: деталь или ветка.
func selected_uids() -> PackedStringArray:
	if String(selected.get("source", "")) != "stand":
		return PackedStringArray()
	var bp: Resource = weapon_bp if String(selected["target"]) == "weapon" else blueprint
	if bool(selected.get("branch", false)):
		return CraftEdit.subtree(bp, String(selected["uid"]))
	return PackedStringArray([String(selected["uid"])])


func clear_selection() -> bool:
	if selected.is_empty():
		return false
	selected = {}
	_apply_highlights()
	selection_changed.emit()
	return true


## Деталь выбора (PartDef) — каталога или на кукле; null — ничего.
func selected_def() -> PartDef:
	if String(selected.get("source", "")) == "shelf":
		return CraftEdit.part(String(selected["part"]))
	if String(selected.get("source", "")) == "stand":
		var bp: Resource = weapon_bp if String(selected["target"]) == "weapon" else blueprint
		return CraftEdit.def_of(bp, String(selected["uid"]))
	return null


## «Установить»: деталь каталога — на лучший свободный подходящий разъём (без замены; нет свободного — отказ словами).
func install_part(part_id: String) -> Dictionary:
	var targets := targets_for(part_id)
	var best: Dictionary = {}
	for t in targets:
		if not bool(t["accepts"]) or not bool(t["ok"]):
			continue
		if bool(t.get("root", false)) or String(t["replace"]) == "":
			best = t
			break
	if best.is_empty():
		var energy := false
		for t in targets:
			energy = energy or (bool(t["accepts"]) and String(t["code"]) == "energy")
		var d := CraftEdit.part(part_id)
		var why := tr("не хватает энергии") if energy else tr("нет свободного подходящего разъёма")
		_say("«%s»: %s" % [d.title if d != null else part_id, why], COL_BAD if energy else COL_WARN)
		return {"ok": false, "code": "energy" if energy else "no_socket"}
	var r := attach_part(part_id, "" if bool(best.get("root", false)) else String(best["uid"]), String(best["anchor"]), String(best["target"]))
	if bool(r.get("ok", false)) and String(r.get("uid", "")) != "":
		select_stand(String(r["uid"]), String(best["target"]))
	return r


## «Дубликат»: такая же деталь (материал, шарнир) на свободный подходящий разъём — сначала зеркальный той же детали-родителя.
func duplicate_part(uid: String, target := "body") -> Dictionary:
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	var n := CraftEdit.find(bp, uid)
	if n.is_empty() or String(n.get("parent", "")) == "":
		_say(tr("Ядро не дублируется"), COL_WARN)
		return {"ok": false, "code": "root"}
	var part_id := String(n["part"])
	var want := CraftEdit.mirror_anchor(String(n.get("anchor", "")))
	var best: Dictionary = {}
	for t in targets_for(part_id, target):
		if not bool(t["accepts"]) or not bool(t["ok"]) or String(t["replace"]) != "" or bool(t.get("root", false)):
			continue
		if best.is_empty():
			best = t
		if String(t["uid"]) == String(n["parent"]) and String(t["anchor"]) == want:
			best = t
			break
	if best.is_empty():
		_say(tr("Дубликат некуда поставить: нет свободного разъёма (или энергии)"), COL_WARN)
		return {"ok": false, "code": "no_socket"}
	var r := attach_part(part_id, String(best["uid"]), String(best["anchor"]), target)
	if bool(r.get("ok", false)) and target == "body":
		var n2 := CraftEdit.find(blueprint, String(r["uid"]))
		if n.has("mat"):
			n2["mat"] = n["mat"]
		if n.has(ActiveBlocks.NODE_KEY):
			n2[ActiveBlocks.NODE_KEY] = n[ActiveBlocks.NODE_KEY]
		_rebuild()
		select_stand(String(r["uid"]), target)
	return r


## «Зеркалить»: поддерево детали — на зеркальный разъём (Anchor_*_L ↔ _R той же детали-родителя или зеркальной ветки);
## занятый разъём заменяется. Энергия — как при ручной сборке.
func mirror_part(uid: String) -> Dictionary:
	var trial := CraftEdit.dup_body(blueprint)
	var r := CraftEdit.mirror_subtree(trial, uid)
	if not bool(r["ok"]):
		_say(String(r["reason"]), COL_BAD if String(r.get("code", "")) == "energy" else COL_WARN)
		return r
	_push_history()
	blueprint = trial
	_name_custom_body()
	_rebuild()
	_say(tr("Зеркально: %d дет.%s") % [int(r["count"]), tr(" (замена)") if String(r.get("replaced", "")) != "" else ""], COL_OK)
	select_stand(String(r["uid"]))
	return r


## Зеркало v0.3 (M): сначала предпросмотр — зеркальная копия голубым полупрозрачным на кукле, Enter / M — поставить, Esc / ПКМ —
## отмена. branch false — только сама деталь (её дети на копии не повторяются). Любая правка / отмена / протяжка снимает предпросмотр.
func start_mirror_preview(uid: String, branch := true) -> Dictionary:
	cancel_drag()
	_drop_mirror()
	var trial := CraftEdit.dup_body(blueprint)
	var r := CraftEdit.mirror_subtree(trial, uid) if branch else _mirror_one(trial, uid)
	if not bool(r["ok"]):
		_say(String(r["reason"]), COL_BAD if String(r.get("code", "")) == "energy" else COL_WARN)
		_play_sfx("invalid", null)
		return r
	pending_mirror = {"uid": uid, "trial": trial, "new": CraftEdit.subtree(trial, String(r["uid"])), "root": String(r["uid"]),
		"count": int(r["count"]), "replaced": String(r.get("replaced", ""))}
	_preview_bp = trial
	_rebuild()
	_play_sfx("mirror", CraftEdit.def_of(trial, String(r["uid"])))
	return r


## Зеркало одной детали: на зеркальный разъём ставится (или меняется на месте) только она — дети детали, стоявшей там, остаются,
## если подходят (как замена протяжкой). {ok, code, reason, uid, count, replaced}.
func _mirror_one(trial: BodyBlueprint, uid: String) -> Dictionary:
	var place := CraftEdit.mirror_place(trial, uid)
	if place.is_empty():
		return {"ok": false, "code": "center", "reason": tr("Деталь по центру — зеркалить некуда (выбери деталь сбоку)")}
	var src := CraftEdit.find(trial, uid)
	var part_id := String(src.get("part", ""))
	var occ := CraftEdit.occupant(trial, String(place[0]), String(place[1]))
	var c := CraftEdit.attach(trial, part_id, String(place[0]), String(place[1]))
	if not bool(c["ok"]):
		return c
	var nu := String(c.get("uid", ""))
	var dn := CraftEdit.find(trial, nu)
	for k in ["mat", "joint", "rest_deg"]:
		if src.has(k):
			dn[k] = src[k]
		else:
			dn.erase(k)
	if dn.has("joint") and trial.joint_error(nu, String(dn["joint"])) != "":
		dn.erase("joint")
	if dn.has("mat") and trial.mat_error(nu, String(dn["mat"])) != "":
		dn.erase("mat")
	var errs := CraftEdit.structural_errors(trial)
	if not errs.is_empty():
		return {"ok": false, "code": "invalid", "reason": CraftEdit._friendly(errs[0])}
	if trial.energy_used() > trial.energy_cap():
		return {"ok": false, "code": "energy", "reason": CraftEdit.energy_reason(tr("зеркальную копию"), trial.energy_used(), trial.energy_cap())}
	return {"ok": true, "code": "ok", "reason": "", "uid": nu, "count": 1, "replaced": occ}


## Поставить зеркальную копию из предпросмотра.
func confirm_mirror() -> bool:
	if pending_mirror.is_empty():
		return false
	var trial: BodyBlueprint = pending_mirror["trial"]
	var root := String(pending_mirror["root"])
	var cnt := int(pending_mirror["count"])
	var rep_uid := String(pending_mirror["replaced"])
	_push_history()   # снимает предпросмотр
	blueprint = trial
	_name_custom_body()
	_rebuild()
	for m in part_meshes("body", root):
		fx_events.append({"kind": "flash", "pos": _visual_aabb(m).get_center(), "t0": _time, "text": ""})
	_play_sfx("mirror", CraftEdit.def_of(blueprint, root))
	_say(tr("Зеркально: %d дет.%s") % [cnt, tr(" (замена)") if rep_uid != "" else ""], COL_OK)
	select_stand(root)
	return true


## Отменить предпросмотр зеркала (со стендом заново). false — предпросмотра не было.
func cancel_mirror() -> bool:
	if not _drop_mirror():
		return false
	if stand != null or mode == Mode.BUILD:
		_rebuild()
	return true


func _drop_mirror() -> bool:
	if pending_mirror.is_empty():
		return false
	pending_mirror = {}
	_preview_bp = null
	return true


## Чертёж, по которому собран стенд (предпросмотр зеркала — пробный).
func _stand_bp() -> BodyBlueprint:
	return _preview_bp if _preview_bp != null else blueprint


## «Удалить» выбранного: деталь с тем, что на ней (висеть ей не на чем). Большая ветка (≥ BIG_BRANCH деталей) — только со второго
## нажатия (v0.3 §52), с анимацией откручивания.
func delete_selected() -> PackedStringArray:
	if String(selected.get("source", "")) != "stand":
		return PackedStringArray()
	cancel_drag()
	var uid := String(selected["uid"])
	var tg := String(selected["target"])
	if not confirm_big(uid, tg, "Del"):
		return PackedStringArray()
	var gone := unscrew(uid, tg)
	if not gone.is_empty():
		clear_selection()
	return gone


## Защита от случайного сноса большой ветки: первое нажатие — вопрос, второе (в течение 3 с, та же деталь) — да.
func confirm_big(uid: String, target: String, key: String) -> bool:
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	var n := CraftEdit.subtree(bp, uid).size()
	if n < BIG_BRANCH:
		return true
	if String(_delete_armed.get("uid", "")) == uid and _time < float(_delete_armed.get("until", 0.0)):
		_delete_armed = {}
		return true
	_delete_armed = {"uid": uid, "until": _time + 3.0}
	_say(tr("Снять %s и ещё %d дет.? %s ещё раз — да") % [_pname(CraftEdit.def_of(bp, uid)), n - 1, key], COL_WARN)
	return false


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
	if _feel_keep != null and is_instance_valid(_feel_keep) and not _feel_keep.is_inside_tree():
		_feel_keep.free()


# --- сохранение ---

## Сохранить сборку (с оружием) под названием title → user://blueprints/<slug>.tres. Возвращает путь ("" — ошибка).
func save_as(title: String) -> String:
	var t := title.strip_edges()
	if t != "":
		blueprint.title = t
	blueprint.title = blueprint.title.trim_suffix(" *")
	var path := CraftEdit.save(blueprint, CraftEdit.slug(blueprint.title))
	if path == "":
		_say(tr("Не удалось сохранить"), COL_BAD)
	else:
		_say(tr("Сохранено: %s") % blueprint.title, COL_OK)
	changed.emit()
	return path


func load_path(path: String) -> bool:
	var bp := CraftEdit.load_saved(path)
	if bp == null or not CraftEdit.structural_errors(bp).is_empty():
		_say(tr("Чертёж не читается"), COL_BAD)
		return false
	_push_history()
	_adopt(bp)
	clear_selection()
	_rebuild()
	_frame_h = 0.0
	_say(tr("Загружено: %s") % bp.title.trim_suffix(" *"), COL_OK)
	return true


# =================================================================== стенд и верстак

## Пробный режим «Запас из деталей» (PartHp, docs/plan-demo/WORKSHOP_V4.md) — та же клавиша «;», что в бою: ❤ деталей на карточках,
## в паспорте и сводке, энергию дают ядро и голова (BodyBlueprint.energy_cap), голова сама энергии не стоит. С «Прочностью суставов»
## не совмещается (как в бою, HitJuice).
func toggle_parts_hp() -> void:
	PartHp.toggle()
	if PartHp.on and JointBreak.on:
		JointBreak.set_on(false)
	_say(tr("Запас из деталей: %s   (; — переключить)") % (tr("вкл — ❤ у каждой детали, энергию дают ядро и голова") if PartHp.on else tr("выкл")), COL_INFO)
	parts_hp_toggled.emit()
	_rebuild()


func _rebuild() -> void:
	_clear_ghost()
	if CraftEdit.prune_links(blueprint) > 0:   # сняли / сварили деталь на конце связки — связка уходит вместе с ней
		_say(tr("Связка снята вместе с деталью"), COL_INFO)
	if String(selected.get("source", "")) == "stand":   # выбранную деталь открутили / отменили — выбор снимается
		var sbp: Resource = weapon_bp if String(selected["target"]) == "weapon" else blueprint
		var sn := CraftEdit.find(sbp, String(selected["uid"]))
		if sn.is_empty() or String(sn.get("part", "")) != String(selected.get("part", sn.get("part", ""))):
			selected = {}
			selection_changed.emit()
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
	var sbp := _stand_bp()
	if sbp.nodes.is_empty() or not CraftEdit.structural_errors(sbp).is_empty():
		_update_pole()
		return
	var view_bp := _PreviewBlueprint.new()
	view_bp.id = sbp.id
	view_bp.title = sbp.title
	view_bp.energy_budget = 100000
	view_bp.nodes = CraftEdit._dup_nodes(sbp.nodes)
	view_bp.control = sbp.control.duplicate()
	view_bp.control_rmb = sbp.control_rmb.duplicate()
	view_bp.links = CraftEdit._dup_nodes(sbp.links) if sbp is BodyBlueprint else view_bp.links
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
	for ln in stand.links_rt:   # суставы связок — тоже; тела связок — между концами в позе стенда
		for lj in stand.links_rt[ln]["joints"]:
			(lj as Generic6DOFJoint3D).node_a = NodePath()
			(lj as Generic6DOFJoint3D).node_b = NodePath()
	stand.refresh_links()
	for n in sbp.nodes:
		var uid := String(n.get("uid", ""))
		var def := CraftEdit.part(String(n.get("part", "")))
		if def == null or not stand.uid_body.has(uid):
			continue
		var host := String(stand.uid_body[uid])
		if CraftEdit.is_fixed(sbp, uid):   # слитая деталь (fixed, декор, броня, сварка): формы — <форма>_<uid> в хозяине
			for sn in CraftEdit.shape_names(def):
				_shape_uid["%s/%s_%s" % [host, sn, uid]] = uid
		else:
			_own_uid[host] = uid
	if not pending_mirror.is_empty():   # предпросмотр зеркала: копия — голубым полупрозрачным
		for u in pending_mirror["new"]:
			for m in part_meshes("body", u):
				_set_material_override(m, _mats["mirror_ghost"])
	_update_pole()
	_make_held_weapon()
	_sync_embedded_view()


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
	# сторона: по имени тела (Hand_L / Hand_R), у перенесённой ветки имя Hand_<uid> — по зеркальности узла
	var side := 1.0 if bn.ends_with("_L") else (-1.0 if bn.ends_with("_R") else (-1.0 if CraftEdit.is_mirrored(_stand_bp(), String(mount["uid"])) else 1.0))
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
	var sbp := _stand_bp()
	var n := CraftEdit.find(sbp, uid)
	var d := CraftEdit.part(String(n.get("part", "")))
	var body := stand.parts.get(String(stand.uid_body[uid])) as Node3D
	if body == null or d == null:
		return null
	var fixed := CraftEdit.is_fixed(sbp, uid)
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
func targets_for(part_id: String, target := "", src: Resource = null) -> Array:
	if target == "":
		target = "weapon" if view == View.WEAPON else "body"
	var d := CraftEdit.part(part_id)
	var out: Array = []
	if d == null:
		return out
	var bp: Resource = src if src != null else (weapon_bp if target == "weapon" else blueprint)
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


## Сколько будет стоить деталь part_id на ближайшем свободном подходящем разъёме (цена растёт с выносом от ядра, BodyBlueprint.
## reach_cost); -1 — свободного разъёма нет. Для карточек библиотеки и фильтра «Влезает»: базовая ⚡ обещала бы то, что у дальнего
## разъёма не встанет. Вынос разъёма — вынос детали-родителя + расстояние до якоря (приближённо, без Socket новой детали).
func cheapest_cost(part_id: String) -> int:
	var d := CraftEdit.part(part_id)
	if d == null:
		return -1
	if _reach_cache_rev != _rev or _reach_cache_n != blueprint.nodes.size():
		_reach_cache.clear()
		_reach_cache_rev = _rev
		_reach_cache_n = blueprint.nodes.size()
		var reach := blueprint.node_reach()
		for n in blueprint.nodes:
			var uid := String(n.get("uid", ""))
			var anchors := CraftEdit.anchors_of(blueprint, uid)
			for an in anchors:
				if CraftEdit.occupant(blueprint, uid, an) != "":
					continue
				var a: Dictionary = anchors[an]
				var r := float(reach.get(uid, 0.0)) + (a["xf"] as Transform3D).origin.length()
				var acc: PackedStringArray = a["accepts"]
				for k in (acc if not acc.is_empty() else PackedStringArray(["*"])):
					_reach_cache[k] = minf(float(_reach_cache.get(k, INF)), r)
	var rk := minf(float(_reach_cache.get(d.kind, INF)), float(_reach_cache.get("*", INF)))
	if d.kind == "core":
		rk = 0.0
	if rk == INF:
		return -1
	return BodyBlueprint.reach_cost(d.energy, rk)


## Свободная энергия тела.
func energy_free() -> int:
	return blueprint.energy_cap() - blueprint.energy_used()


# =================================================================== протяжка

## Взять деталь в руку (v0.3 §13–19): part_id — из каталога; opts: {"copy_of": uid, "branch": bool} — дубликат детали / ветки
## (D), {"move": uid} — перенос ветки с куклы. Под курсором — настоящая 3D-деталь; совместимые разъёмы проступают.
func begin_drag(part_id: String, screen_pos: Vector2, opts := {}) -> void:
	if mode != Mode.BUILD:
		return
	cancel_mirror()
	control_pick = false
	paint_mat = ""
	joint_pick = ""
	_clear_link_tool()
	set_paint_tool("")
	var d := CraftEdit.part(part_id)
	if d == null:
		return
	var src := blueprint
	var move := String(opts.get("move", ""))
	if move != "":
		src = CraftEdit.dup_body(blueprint)   # разъёмы — без самой ветки (на себя не повесить)
		CraftEdit.detach(src, move)
		_hidden_uids = CraftEdit.subtree(blueprint, move)
	var targets := targets_for(part_id, "", src)
	drag = {"part": part_id, "targets": targets, "index": -1, "sticky": bool(opts.get("sticky", false)), "start": opts.get("start", screen_pos),
		"pos": screen_pos, "moved": false, "copy_of": String(opts.get("copy_of", "")), "branch": bool(opts.get("branch", false)),
		"move": move, "trials": {}, "rev": _rev}
	_trial_queue.clear()
	if move != "" or bool(drag["branch"]) or String(drag["copy_of"]) != "":   # ветка / копия: решает пробная сборка целиком
		for i in range(targets.size()):
			if bool((targets[i] as Dictionary)["accepts"]):
				_trial_queue.append(i)
		_run_trials(1e9 if probe_input else TRIAL_FIRST_MS, false)
	for u in _hidden_uids:
		for m in part_meshes("body", u):
			(m as Node3D).visible = false
	if held_weapon != null and is_instance_valid(held_weapon) and _hidden_uids.has(String(_mount()["uid"])):
		held_weapon.visible = false
	_make_carry(part_id)
	_apply_highlights()
	_trial_hint = true
	if _trial_queue.is_empty():
		_say_drag_dead_end()
	_play_sfx("grab", d)
	update_drag(screen_pos)
	changed.emit()


## «Некуда поставить» / «не хватает энергии» — когда ни один разъём не принимает деталь в руке.
func _say_drag_dead_end() -> void:
	_trial_hint = false
	if drag.is_empty():
		return
	var any_ok := false
	var energy_block := false
	for t in (drag["targets"] as Array):
		if bool(t["accepts"]) and bool(t["ok"]):
			any_ok = true
		elif bool(t["accepts"]) and String(t["code"]) == "energy":
			energy_block = true
	if not any_ok and energy_block:
		_say(tr("Не хватает энергии — дальше от ядра дороже, свободно ⚡%d") % energy_free(), COL_BAD)
	elif not any_ok:
		_say(tr("Некуда поставить: нет свободного подходящего разъёма"), COL_WARN)


## Посчитать пробу разъёма t и записать итог в его флаги (ok / code / reason).
func _apply_trial(t: Dictionary) -> void:
	var dt := drag_trial(t)
	t["ok"] = bool(dt.get("ok", false))
	t["code"] = String(dt.get("code", ""))
	t["reason"] = String(dt.get("reason", ""))


## Порция очереди проб в бюджет budget_ms. Очередь кончилась — подсветка пересчитывается и (если просили) говорим, что некуда ставить.
func _run_trials(budget_ms: float, notify := true) -> void:
	if drag.is_empty():
		_trial_queue.clear()
		return
	var t0 := Time.get_ticks_usec()
	var targets: Array = drag["targets"]
	var did := false
	while not _trial_queue.is_empty() and float(Time.get_ticks_usec() - t0) / 1000.0 < budget_ms:
		var i := int(_trial_queue.pop_front())
		if i < targets.size():
			_apply_trial(targets[i])
			did = true
	if did and notify:
		_apply_highlights()
		changed.emit()   # UI: энергия «станет» и подсказка — по досчитанным разъёмам
	if _trial_queue.is_empty() and _trial_hint and notify:
		_say_drag_dead_end()


## Проба под курсором — сразу, не дожидаясь очереди (иначе деталь встала бы по неточной проверке одной детали).
func _ensure_trial(t: Dictionary) -> void:
	if _trial_queue.is_empty() or drag.is_empty() or not bool(t["accepts"]):
		return
	var targets: Array = drag["targets"]
	var i := targets.find(t)
	if i >= 0 and _trial_queue.has(i):
		_trial_queue.erase(i)
		_apply_trial(t)


## Доделать все пробы разом (пробы, откат на старую семантику).
func flush_trials() -> void:
	_run_trials(1e9)


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
	if _over_panel(screen_pos):
		best = -1   # над панелью разъёмы не ловятся (деталь не встанет «сквозь» библиотеку)
	if best != int(drag["index"]):
		drag["index"] = best
		if best >= 0:
			_ensure_trial(targets[best])
		_update_ghost()
		_apply_highlights()
		changed.emit()   # UI: энергия «станет» и подсказка


## Пробная сборка для цели протяжки (кэш по индексу): {ok, code, reason, bp, uid, energy_after, mass_after}. Новая деталь, дубликат
## (с материалом и шарниром), дубликат ветки, перенос ветки — одна схема: считаем на копии чертежа, применяем её же.
func drag_trial(t: Dictionary = {}) -> Dictionary:
	if drag.is_empty():
		return {}
	if t.is_empty():
		t = drag_target()
	if t.is_empty() or String(t["target"]) != "body":
		return {}
	var key := "%s/%s" % [t["uid"], t["anchor"]]
	var cache: Dictionary = drag["trials"]
	if cache.has(key):
		return cache[key]
	var part_id := String(drag["part"])
	var r := {}
	if not bool(t["accepts"]):
		r = {"ok": false, "code": "kind", "reason": tr("Сюда эта деталь не встанет")}
	elif String(drag["move"]) != "":
		r = CraftEdit.move_subtree(blueprint, String(drag["move"]), String(t["uid"]), String(t["anchor"]))
	elif String(drag["copy_of"]) != "" and bool(drag["branch"]):
		var tb := CraftEdit.dup_body(blueprint)
		r = CraftEdit.graft_subtree(tb, blueprint, String(drag["copy_of"]), String(t["uid"]), String(t["anchor"]))
		r["bp"] = tb
	else:
		var tb2 := CraftEdit.dup_body(blueprint)
		r = CraftEdit.set_root(tb2, part_id) if bool(t["root"]) else CraftEdit.attach(tb2, part_id, String(t["uid"]), String(t["anchor"]))
		if bool(r.get("ok", false)) and String(drag["copy_of"]) != "":
			var src := CraftEdit.find(blueprint, String(drag["copy_of"]))
			var dn := CraftEdit.find(tb2, String(r.get("uid", "")))
			for k in ["mat", "joint", "rest_deg", ActiveBlocks.NODE_KEY]:
				if src.has(k):
					dn[k] = src[k]
			var nu2 := String(r.get("uid", ""))
			# на новом месте шарнир / материал копии могут быть запрещены (мотор на суставе без мышцы) — там обычная ось / родной
			if dn.has("joint") and tb2.joint_error(nu2, String(dn["joint"])) != "":
				dn.erase("joint")
			if dn.has("mat") and tb2.mat_error(nu2, String(dn["mat"])) != "":
				dn.erase("mat")
			var errs := CraftEdit.structural_errors(tb2)
			if not errs.is_empty():
				r = {"ok": false, "code": "invalid", "reason": CraftEdit._friendly(errs[0])}
			elif tb2.energy_used() > tb2.energy_cap():
				r = {"ok": false, "code": "energy", "reason": CraftEdit.energy_reason(tr("копию"), tb2.energy_used(), tb2.energy_cap())}
		r["bp"] = tb2
	if r.get("bp") is BodyBlueprint:
		var tbp := r["bp"] as BodyBlueprint
		r["energy_after"] = tbp.energy_used()
		r["mass_after"] = tbp.total_mass()
	else:
		r["energy_after"] = blueprint.energy_used()
		r["mass_after"] = blueprint.total_mass()
	cache[key] = r
	return r


## Отпустить: поставить на выбранный разъём (если можно). Возвращает {ok, uid, reason}.
func end_drag(screen_pos: Vector2) -> Dictionary:
	if drag.is_empty():
		return {"ok": false}
	update_drag(screen_pos)
	var i := int(drag["index"])
	var part_id := String(drag["part"])
	var targets: Array = drag["targets"]
	var d := CraftEdit.part(part_id)
	if i < 0:
		_refuse({}, "")
		cancel_drag()
		return {"ok": false, "reason": tr("мимо разъёма")}
	var t: Dictionary = targets[i]
	if String(t["target"]) == "weapon":
		cancel_drag()
		var rw := attach_part(part_id, "" if bool(t["root"]) else String(t["uid"]), String(t["anchor"]), "weapon")
		if bool(rw.get("ok", false)):
			_snap_fx("weapon", String(rw.get("uid", "")), t, d)
		return rw
	if int(drag.get("rev", _rev)) != _rev:   # чертёж поменялся, пока деталь была в руке — пробы устарели
		cancel_drag()
		return {"ok": false, "reason": tr("чертёж изменился")}
	var move0 := String(drag["move"])
	if move0 != "":   # отпустил ветку на её же разъём — ничего не делаем (без записи истории и новых uid)
		var src_n := CraftEdit.find(blueprint, move0)
		if String(t["uid"]) == String(src_n.get("parent", "")) and CraftEdit.anchor_name(String(t["anchor"])) == CraftEdit.anchor_name(String(src_n.get("anchor", ""))):
			cancel_drag()
			select_stand(move0)
			return {"ok": false, "code": "same"}
	var dt := drag_trial(t)
	if not bool(dt.get("ok", false)):
		var why := String(dt.get("reason", t.get("reason", "")))
		_refuse(t, why, String(dt.get("code", t.get("code", ""))))
		cancel_drag()
		return {"ok": false, "reason": why}
	var move := String(drag["move"])
	cancel_drag()
	_push_history()
	blueprint = dt["bp"]
	_name_custom_body()
	var nu := String(dt.get("uid", ""))
	_rebuild()
	if not recent_parts.has(part_id):
		recent_parts.insert(0, part_id)
		if recent_parts.size() > 12:
			recent_parts.resize(12)
	else:
		recent_parts.remove_at(recent_parts.find(part_id))
		recent_parts.insert(0, part_id)
	_snap_fx("body", nu, t, d)
	if move != "" and nu != "":
		select_stand(nu)
	# v0.3 §56: встала — экран чистый (щелчок, вспышка и энергия говорят сами); сообщение — только о замене
	if String(t["replace"]) != "" and move == "":
		_say(tr("Заменено: %s") % _pname(d), COL_INFO)
	return {"ok": true, "uid": nu, "replace": t["replace"]}


func cancel_drag() -> void:
	if drag.is_empty():
		return
	drag = {}
	_trial_queue.clear()
	_trial_hint = false
	for u in _hidden_uids:
		for m in part_meshes("body", u):
			(m as Node3D).visible = true
	if held_weapon != null and is_instance_valid(held_weapon):
		held_weapon.visible = true
	_hidden_uids = PackedStringArray()
	_free_carry()
	_clear_ghost()
	_apply_highlights()
	changed.emit()


## Имя детали для игрока (PartNames: без внутренних id и «(v3)»).
func _pname(d: PartDef) -> String:
	if d == null:
		return ""
	return PartNames.of(d)


# --- деталь под курсором (v0.3 §14–17) ---

func _make_carry(part_id: String, mirror := false) -> void:
	_free_carry()
	var d := CraftEdit.part(part_id)
	if d == null or d.scene == null:
		return
	var inst := d.scene.instantiate()
	_mirror_inst(inst, mirror)   # у правого разъёма — правая версия детали (Mesh_R / зеркало), как её поставит кукла
	var root := Node3D.new()
	root.name = "Carry"
	for c in inst.get_children():
		if c is Node3D and (String(c.name) == "Mesh" or c is Marker3D and String(c.name) == "Socket"):
			var xf := (c as Node3D).transform
			inst.remove_child(c)
			c.owner = null
			root.add_child(c)
			(c as Node3D).transform = xf
	inst.free()
	var mesh := root.get_node_or_null("Mesh")
	if mesh != null:
		_set_overlay_recursive(mesh, _mats["carry_rim"])
	add_child(root)
	_carry = root
	_carry.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # едет за курсором в _process
	_carry_mirror = mirror
	_carry_see = false
	_carry_xf = Transform3D.IDENTITY
	_update_carry(1.0, true)


func _free_carry() -> void:
	if _carry != null and is_instance_valid(_carry):
		_carry.queue_free()
	_carry = null


static func _set_overlay_recursive(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_overlay = m
	for c in n.get_children():
		_set_overlay_recursive(c, m)


## Точка курсора на плоскости перед стендом (перпендикулярно взгляду камеры, на CARRY_DEPTH ближе стенда).
func _cursor_world(screen: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var fwd := -cam.global_basis.z
	var centre := stand_root.global_position + Vector3(0, 1.0, 0) if view == View.BODY else bench_spot.global_position
	var plane := Plane(fwd, centre - fwd * CARRY_DEPTH)
	var o := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var hit: Variant = plane.intersects_ray(o, dir)
	return hit if hit is Vector3 else o + dir * 2.0


## Поза детали под курсором: свободно — разъём детали (Socket) чуть справа-снизу от курсора (курсор её не закрывает), деталь
## вытянута от ближайшего совместимого разъёма бойца и слегка повёрнута к камере; у разъёма — магнит: к позе призрака.
func _update_carry(delta: float, snap := false) -> void:
	if _carry == null or drag.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mp := drag["pos"] as Vector2
	var cw := _cursor_world(mp + Vector2(26, 22))
	var sock := _carry.get_node_or_null("Socket") as Node3D
	var sock_xf: Transform3D = sock.transform if sock != null else Transform3D.IDENTITY
	# куда смотрит разъём: на ближайший совместимый разъём (на экране), иначе вниз-влево к бойцу
	var aim := Vector3.ZERO
	var best := INF
	for t in (drag["targets"] as Array):
		if not bool(t["accepts"]):
			continue
		var tp: Vector3 = (t["xf"] as Transform3D).origin
		var dd := cam.unproject_position(tp).distance_to(mp)
		if dd < best:
			best = dd
			aim = tp
	var up := (aim - cw) if aim != Vector3.ZERO else (stand_root.global_position + Vector3(0, 1.0, 0) - cw)
	up = up - cam.global_basis.z * up.dot(cam.global_basis.z)
	up = up.normalized() if up.length() > 1e-3 else Vector3.UP
	var z := cam.global_basis.z
	var x := up.cross(z).normalized()
	var free_basis := Basis(x, up, x.cross(up)).rotated(up, 0.35).orthonormalized()   # чуть в три четверти — читается объём
	var free_xf := Transform3D(free_basis, cw) * Transform3D(Basis.IDENTITY, -sock_xf.origin)
	var goal := free_xf
	var t2 := drag_target()
	var see := false
	if not t2.is_empty():
		var g := _ghost_cached(t2)
		var gd := cam.unproject_position((t2["xf"] as Transform3D).origin).distance_to(mp)
		# ближе SNAP_IN_PX к годному разъёму — деталь садится на место целиком (призрак прячется под ней); к негодному — только
		# тянется наполовину, красный призрак виден
		var ok := bool(t2["ok"])
		var k := smoothstep(MAGNET_PX, SNAP_IN_PX, gd) * (1.0 if ok else 0.5)
		var want_mirror := bool(g["mirror"]) and k > 0.5
		if want_mirror != _carry_mirror:   # подлетели к правому разъёму — деталь сменилась на правую (и обратно)
			var keep := _carry_xf
			_make_carry(String(drag["part"]), want_mirror)
			_carry_xf = keep
			return
		var gxf: Transform3D = g["xf"]
		goal = Transform3D(free_xf.basis.slerp(gxf.basis.orthonormalized(), k), free_xf.origin.lerp(gxf.origin, k))
		see = k >= 0.9
		if _ghost != null and is_instance_valid(_ghost):
			_ghost.visible = not see
	if see != _carry_see:
		_carry_see = see
		_fade(_carry, 0.45 if see else 0.0)
	if snap:
		_carry_xf = goal
	else:
		var a := 1.0 - exp(-delta / 0.06)
		_carry_xf = Transform3D(_carry_xf.basis.slerp(goal.basis.orthonormalized(), a), _carry_xf.origin.lerp(goal.origin, a))
	_carry.global_transform = _carry_xf


## Поза призрака для цели (кэш на протяжку: ghost_transform собирает пробный чертёж и сцену детали — не каждый кадр).
func _ghost_cached(t: Dictionary) -> Dictionary:
	var key := "%s/%s/%s" % [t["target"], t["uid"], t["anchor"]]
	if not drag.has("ghosts"):
		drag["ghosts"] = {}
	var gc: Dictionary = drag["ghosts"]
	if not gc.has(key):
		gc[key] = ghost_transform(String(drag["part"]), t)
	return gc[key]


## Экранная точка разъёма детали под курсором (кольцо «конец крепления» — оверлей).
func carry_socket_screen() -> Variant:
	if _carry == null or not is_instance_valid(_carry):
		return null
	var cam := get_viewport().get_camera_3d()
	var sock := _carry.get_node_or_null("Socket") as Node3D
	if cam == null or sock == null:
		return null
	return cam.unproject_position(sock.global_position)


# --- щелчок, отказ, откручивание (v0.3 §22–24) ---

## Деталь встала: вспышка разъёма, щепки / пыль, «усадка» меша, звук по материалу.
func _snap_fx(target: String, uid: String, t: Dictionary, d: PartDef) -> void:
	var p: Vector3 = (t["xf"] as Transform3D).origin
	fx_events.append({"kind": "flash", "pos": p, "t0": _time, "text": ""})
	ImpactFx.spawn_impact(self, p, Vector3.UP, 2.5, "")
	for m in part_meshes(target, uid):
		var n := m as Node3D
		var s0 := n.scale
		n.scale = s0 * 1.12
		var tw := n.create_tween()
		tw.tween_property(n, "scale", s0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var mat := String(CraftEdit.find(blueprint, uid).get("mat", "")) if target == "body" else ""
	_play_sfx("snap", d, mat)


## Не встала: красный пульс у разъёма и короткая причина, деталь мягко отскакивает.
## code — код отказа (CraftEdit: "energy" — не влезает в бюджет); по тексту причины отказ не опознаётся (он переведён).
func _refuse(t: Dictionary, why: String, code: String = "") -> void:
	if not t.is_empty():
		var short := why
		if code == "energy":
			short = tr("Не хватает энергии")
		elif why == "" or why.length() > 34:
			short = tr("Сюда не встанет") if not bool(t.get("accepts", true)) else tr("Соединение занято")
		fx_events.append({"kind": "refuse", "pos": (t["xf"] as Transform3D).origin, "t0": _time, "text": short})
	if _carry != null and is_instance_valid(_carry):
		var c := _carry
		_carry = null
		var away := Vector3.ZERO
		if not t.is_empty():
			away = (c.global_position - (t["xf"] as Transform3D).origin).normalized() * 0.18
		var tw := c.create_tween()
		tw.set_parallel(true)
		tw.tween_property(c, "global_position", c.global_position + away + Vector3(0, 0.05, 0), 0.16).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "scale", Vector3.ONE * 0.6, 0.28).set_delay(0.08)
		tw.chain().tween_callback(c.queue_free)
	_play_sfx("invalid", null)


## Открутить с анимацией (ПКМ по детали): копия мешей ветки чуть отходит от разъёма и тает, в чертеже — сразу.
func unscrew(uid: String, target := "body") -> PackedStringArray:
	var bp: Resource = weapon_bp if target == "weapon" else blueprint
	var n := CraftEdit.find(bp, uid)
	if n.is_empty():
		return PackedStringArray()
	var ghost := Node3D.new()
	ghost.name = "Unscrew"
	add_child(ghost)
	var centre := Vector3.ZERO
	var cnt := 0
	for u in CraftEdit.subtree(bp, uid):
		for m in part_meshes(target, u):
			var mi := (m as Node3D).duplicate() as Node3D
			ghost.add_child(mi)
			mi.global_transform = (m as Node3D).global_transform
			_set_overlay(mi, null)
			centre += mi.global_position
			cnt += 1
	var anchor := centre / maxf(cnt, 1)
	var pxf: Variant = anchor_xf(target, String(n.get("parent", "")), String(n.get("anchor", "")))
	if pxf is Transform3D:
		anchor = (pxf as Transform3D).origin
	var gone := detach_part(uid, target)
	if gone.is_empty():
		ghost.queue_free()
		return gone
	var out := ((centre / maxf(cnt, 1)) - anchor)
	out = out.normalized() * 0.12 if out.length() > 1e-3 else Vector3(0, -0.12, 0)
	fx_events.append({"kind": "flash", "pos": anchor, "t0": _time, "text": ""})
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "position", out, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_property(ghost, "position", out + Vector3(0, -0.5, 0), 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(a: float) -> void: _fade(ghost, a), 0.0, 1.0, 0.3)
	tw.tween_callback(ghost.queue_free)
	_play_sfx("unscrew", CraftEdit.part(String(n.get("part", ""))))
	return gone


static func _fade(n: Node, a: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).transparency = a
	for c in n.get_children():
		_fade(c, a)


func _play_sfx(kind: String, d: PartDef, mat_id := "") -> void:
	if sfx == null or not is_instance_valid(sfx):
		return
	sfx.play(kind, WsSfx.material_of(d, mat_id) if d != null else "")


func _over_panel(p: Vector2) -> bool:
	return ui != null and ui.has_method("is_over_panel") and bool(ui.call("is_over_panel", p))


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
	if target == "body" and not drag.is_empty() and String(drag.get("copy_of", "")) != "":   # копия встанет со своим углом покоя
		var srcn := CraftEdit.find(blueprint, String(drag["copy_of"]))
		if srcn.has("rest_deg"):
			CraftEdit.find(trial, nu)["rest_deg"] = srcn["rest_deg"]
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
		if link_pick != "" and stand.link_of_body.has(String(col.name)):   # связка под курсором — только инструменту связки
			return {"target": "link", "link": String(stand.link_of_body[String(col.name)]).trim_prefix("Link_"), "pos": hit.get("position", Vector3.ZERO)}
		var key := "%s/%s" % [col.name, shape_node.name if shape_node != null else ""]
		var uid2 := String(_shape_uid.get(key, _own_uid.get(String(col.name), "")))
		return {"target": "body", "uid": uid2, "pos": hit.get("position", Vector3.ZERO)} if uid2 != "" else {}
	return {}


func uid_title(target: String, uid: String) -> String:
	var d := CraftEdit.def_of(weapon_bp if target == "weapon" else _stand_bp(), uid)
	return PartNames.of(d) if d != null else ""


## Название детали и (у тела) её материал и шарнир: «Плечо · Железо, 4.4 кг · шарнир «Мотор»».
func part_info(target: String, uid: String) -> String:
	var s := uid_title(target, uid)
	if target != "body" or CraftEdit.find(blueprint, uid).is_empty():
		return s
	var mid := blueprint.node_mat(uid)
	if mid != "":
		s += tr(" · %s, %.1f кг") % [CraftEdit.mat_title(mid), blueprint.node_mass(uid)]
	var jt := blueprint.joint_type_of(uid)
	if jt != "" and jt != KitJoint.DEFAULT:
		s += tr(" · шарнир «%s»") % CraftEdit.joint_title(jt)
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
	var sbp := _stand_bp()
	var n := CraftEdit.find(sbp, uid)
	var d := CraftEdit.part(String(n.get("part", "")))
	var body := stand.parts.get(String(stand.uid_body[uid])) as Node3D
	if body == null or d == null:
		return out
	var fixed := CraftEdit.is_fixed(sbp, uid)
	var mn := body.get_node_or_null("Mesh_" + uid if fixed else "Mesh")
	if mn != null:
		out.append(mn)
	return out


func _make_materials() -> void:
	_mats["control"] = _overlay_mat(Color(PULL_COLOURS["lmb"], 0.42))
	_mats["control_rmb"] = _overlay_mat(Color(PULL_COLOURS["rmb"], 0.42))
	_mats["hover"] = _overlay_mat(Color(1.0, 0.97, 0.85, 0.22))
	_mats["remove"] = _overlay_mat(Color(1.0, 0.25, 0.18, 0.45))
	_mats["replace"] = _overlay_mat(Color(1.0, 0.55, 0.15, 0.4))
	_mats["pick"] = _overlay_mat(Color(1.0, 0.85, 0.35, 0.3))
	var g := StandardMaterial3D.new()
	g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.5, 0.9, 0.45, 0.42)   # встанет — зелёный (язык цветов v0.3 §6)
	g.cull_mode = BaseMaterial3D.CULL_BACK
	g.no_depth_test = false
	_mats["ghost"] = g
	var gb := g.duplicate() as StandardMaterial3D
	gb.albedo_color = Color(1.0, 0.35, 0.3, 0.45)
	_mats["ghost_bad"] = gb
	# v0.3: деталь в руке — тёплый ободок по силуэту (френель), предпросмотр зеркала — голубой полупрозрачный
	var rim := Shader.new()
	rim.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 rim : source_color = vec4(1.0, 0.78, 0.4, 1.0);
uniform float power = 2.2;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = rim.rgb * (0.12 + f);
	ALPHA = clamp(0.1 + f, 0.0, 1.0) * rim.a;
}
"""
	var cr := ShaderMaterial.new()
	cr.shader = rim
	_mats["carry_rim"] = cr
	var mg := g.duplicate() as StandardMaterial3D
	mg.albedo_color = Color(0.5, 0.9, 0.45, 0.32)   # зеркальная копия — будущая установка: зелёный призрак
	_mats["mirror_ghost"] = mg
	# выбранная деталь (§25): тонкий янтарный контур по силуэту — только кромка, без заливки (деталь читается как есть)
	var line := Shader.new()
	line.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 rim : source_color = vec4(1.0, 0.74, 0.3, 0.8);
uniform float power = 4.5;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = rim.rgb * f;
	ALPHA = smoothstep(0.35, 0.9, f) * rim.a;
}
"""
	var sel := ShaderMaterial.new()
	sel.shader = line
	_mats["selected"] = sel


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
		if pulls_visible(c):
			for m in part_meshes("body", c):
				_set_overlay(m, _mats["control_rmb" if blueprint.control_rmb.has(c) else "control"])
	if String(selected.get("source", "")) == "stand":
		for u in selected_uids():
			for m in part_meshes(String(selected["target"]), u):
				_set_overlay(m, _mats["selected"])
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


## Плашки каналов активных блоков на стенде (v0.3 §44: лишнего на кукле не видно): выбран активный блок или открыта категория
## «Активные блоки».
func channels_visible() -> bool:
	if String(selected.get("source", "")) == "stand":
		var n := CraftEdit.find(blueprint, String(selected.get("uid", "")))
		if not n.is_empty() and ActiveBlocks.is_active(String(n.get("part", ""))):
			return true
	var tabs: Variant = ui.get("shelf_tab") if ui != null else null
	return tabs is Dictionary and String((tabs as Dictionary).get("body", "")) == "active"



## Тяги видны не всегда (v0.3 §28: на модели без настроек управления): только с инструментом «Тяги» (Q).
func pulls_visible(_uid := "") -> bool:
	return control_pick   # тяга детали — в «Настроить» паспорта; на модели кольца ЛКМ / ПКМ только с инструментом Q


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

## Захваченные жесты мыши (v0.3 §39): зажатая ПКМ — орбита (без сдвига — клик: открутить / положить инструмент / отменить);
## зажатая ЛКМ на детали куклы — перенос ветки (без сдвига — выбор); деталь в руке — протяжка. Движение и отпускание ловим здесь,
## даже над панелями.
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
	if not _rmb.is_empty():
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT == 0:
				_rmb = {}   # отпустили вне окна (отпускание не пришло) — жест кончился, без клика
				return
			if not bool(_rmb["moved"]) and mm.position.distance_to(_rmb["pos"]) > 6.0:
				_rmb["moved"] = true
			if bool(_rmb["moved"]):
				orbit(mm.relative)
			if not drag.is_empty():
				update_drag(mm.position)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT \
				and not (event as InputEventMouseButton).pressed:
			var r := _rmb
			_rmb = {}
			if not bool(r["moved"]):
				_right_click(r)
			get_viewport().set_input_as_handled()
			return
	if not _lmb.is_empty():
		if event is InputEventMouseMotion:
			var lm := event as InputEventMouseMotion
			if lm.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
				_lmb = {}
				return
			if lm.position.distance_to(_lmb["pos"]) > DRAG_MOVE_PX:
				var l := _lmb
				_lmb = {}
				_start_move(l, lm.position)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and not (event as InputEventMouseButton).pressed:
			var l2 := _lmb
			_lmb = {}
			_left_click(l2, (event as InputEventMouseButton).shift_pressed)
			get_viewport().set_input_as_handled()
			return
	if drag.is_empty():
		return
	if event is InputEventMouseMotion:
		var dm := event as InputEventMouseMotion
		if not bool(drag["sticky"]) and bool(drag["moved"]) and dm.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			drag["sticky"] = true   # отпускание потерялось (окно без фокуса) — деталь остаётся в руке, ставится кликом
		update_drag(dm.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_rmb = {"pos": mb.position, "moved": false, "drag": true}   # тащишь и крутишь; ПКМ без сдвига — отмена
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not bool(drag["sticky"]):
			if bool(drag["moved"]) and _over_panel(mb.position):
				cancel_drag()   # передумал — бросил обратно на библиотеку / панель
			elif bool(drag["moved"]):
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
	# колесо / жесты над панелью (библиотека в конце списка, правая панель, всплывашки) — не камере и не кисти
	if (event is InputEventMouseButton or event is InputEventPanGesture or event is InputEventMagnifyGesture) \
			and _over_panel((event as InputEventMouse).position if event is InputEventMouse else (event as InputEventGesture).position):
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		get_viewport().gui_release_focus()   # клик по сцене: поле поиска отдаёт клавиши (D, M, Del, T — снова мастерской)
	if not pending_mirror.is_empty() and paint_tool != "":
		cancel_mirror()   # взял баллончик — предпросмотр зеркала снимается (штрих лёг бы на пробный стенд)
	if paint != null and paint.handle_input(event):   # покраска: штрих, наклейки, колесо, Q / E, R — первыми
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mp := (event as InputEventMouseMotion).position
		set_hover(paint.hover_pick(mp) if paint_tool != "" else pick(mp))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var steps := mb.factor if mb.factor > 0.0 else 1.0
			zoom_by(steps if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -steps)
			get_viewport().set_input_as_handled()
			return
		var h := pick(mb.position)
		var on_body := not h.is_empty() and String(h["target"]) == "body"
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = {"pos": mb.position, "moved": false, "hit": h}
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if not pending_mirror.is_empty():   # предпросмотр зеркала: клик по копии — поставить, мимо — отмена
				if on_body and (pending_mirror["new"] as PackedStringArray).has(String(h["uid"])):
					confirm_mirror()
				else:
					cancel_mirror()
			elif control_pick:
				if on_body:
					set_control(String(h["uid"]))
				else:
					_say(tr("Кликни по детали бойца (Esc — отмена)"), COL_WARN)
			elif paint_mat != "":
				if on_body:
					set_material(String(h["uid"]))
				else:
					_say(tr("Кисть: кликни по детали бойца (Esc / ПКМ — убрать кисть)"), COL_WARN)
			elif link_pick != "":
				_link_click(h)
			elif joint_pick != "":
				if on_body:
					set_joint(String(h["uid"]))
				else:
					_say(tr("Шарнир: кликни по детали бойца (Esc / ПКМ — отмена)"), COL_WARN)
			elif not h.is_empty() and drag.is_empty():
				_lmb = {"pos": mb.position, "uid": String(h["uid"]), "target": String(h["target"])}   # клик — выбор, сдвиг — перенос
			else:
				clear_selection()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		var sel_stand := String(selected.get("source", "")) == "stand"
		match k.physical_keycode:
			KEY_Q:
				toggle_control_pick()
			KEY_SEMICOLON:
				toggle_parts_hp()
			KEY_T:
				start_test()
			KEY_ENTER, KEY_KP_ENTER:
				if not confirm_mirror():
					start_test()
			KEY_TAB:
				set_view(View.WEAPON if view == View.BODY else View.BODY)
			KEY_Z:
				if (k.ctrl_pressed or k.meta_pressed) and k.shift_pressed:
					redo()
				elif k.ctrl_pressed or k.meta_pressed:
					undo()
				else:
					return
			KEY_Y:
				if k.ctrl_pressed or k.meta_pressed:
					redo()
				else:
					return
			KEY_D:
				if sel_stand:
					duplicate_to_hand(String(selected["uid"]), String(selected["target"]), bool(selected.get("branch", false)))
				elif String(selected.get("source", "")) == "shelf":
					begin_drag(String(selected["part"]), get_viewport().get_mouse_position(), {"sticky": true})
				else:
					return
			KEY_M:
				if not pending_mirror.is_empty():
					confirm_mirror()
				elif sel_stand and String(selected["target"]) == "body":
					start_mirror_preview(String(selected["uid"]), bool(selected.get("branch", false)))
				else:
					return
			KEY_DELETE, KEY_BACKSPACE:
				delete_selected()
			KEY_R:
				if paint != null and paint.tab_open and view == View.BODY:
					paint.turn_stand(-1 if k.shift_pressed else 1)   # полка «Покраска» без инструмента: тоже крутит стенд
				else:
					reset_camera()
			KEY_ESCAPE:
				if not cancel_mirror() and not clear_tools() and not clear_selection():   # иначе двойной Esc — в гараж (Flow)
					if single_esc_exit and embedded:
						_flush_autosave(true)
						exit_requested.emit()
					elif _time < _esc_armed_until:
						_flush_autosave(true)
						if embedded:
							exit_requested.emit()
						else:
							Flow.to_menu()
					else:
						_esc_armed_until = _time + 1.5
						_say(tr("Esc ещё раз — в гараж"), COL_INFO)
			_:
				return
		get_viewport().set_input_as_handled()


## ПКМ без сдвига: деталь в руке — положить; предпросмотр зеркала — отмена; инструмент — положить; по детали — открутить.
func _right_click(r: Dictionary) -> void:
	if bool(r.get("drag", false)):
		cancel_drag()
		return
	if cancel_mirror() or clear_tools():
		return
	var h: Dictionary = r.get("hit", {})
	if h.is_empty():
		return
	hover = {}
	if confirm_big(String(h["uid"]), String(h["target"]), tr("ПКМ")):
		unscrew(String(h["uid"]), String(h["target"]))


## ЛКМ без сдвига по детали: выбор; Shift или двойной клик — вся ветка.
func _left_click(l: Dictionary, shift: bool) -> void:
	var uid := String(l["uid"])
	var dbl := String(_last_click["uid"]) == uid and _time - float(_last_click["t"]) < 0.35
	_last_click = {"uid": uid, "t": _time}
	select_stand(uid, String(l["target"]), shift or dbl)
	_play_sfx("button", null)


## Потянул деталь с куклы: ветка едет в руку (ядро и оружие верстака не переносятся — только выбор).
func _start_move(l: Dictionary, pos: Vector2) -> void:
	var uid := String(l["uid"])
	if String(l["target"]) != "body":
		select_stand(uid, String(l["target"]))
		return
	var n := CraftEdit.find(blueprint, uid)
	if n.is_empty() or String(n.get("parent", "")) == "":
		select_stand(uid)
		_say(tr("Ядро не переносится — перетащи другое ядро поверх"), COL_WARN)
		return
	clear_selection()
	begin_drag(String(n["part"]), pos, {"move": uid, "start": l["pos"]})


## Дубликат в руку (D, v0.3 §33): копия детали (или ветки) под курсором — поставь кликом у разъёма. Верстак — как раньше, сразу.
func duplicate_to_hand(uid: String, target := "body", branch := false) -> bool:
	if target == "weapon":
		return bool(duplicate_part(uid, target).get("ok", false))
	var n := CraftEdit.find(blueprint, uid)
	if n.is_empty() or String(n.get("parent", "")) == "":
		_say(tr("Ядро не дублируется"), COL_WARN)
		return false
	branch = branch and CraftEdit.subtree(blueprint, uid).size() > 1
	begin_drag(String(n["part"]), get_viewport().get_mouse_position(), {"copy_of": uid, "branch": branch, "sticky": true})
	if not drag.is_empty():
		_play_sfx("duplicate", CraftEdit.part(String(n["part"])))
	return not drag.is_empty()


func set_view(v: int) -> void:
	if v == view:
		return
	cancel_drag()
	cancel_mirror()
	clear_selection()   # выбор — в одном виде: uid верстака и тела пересекаются
	view = v
	_frame_h = 0.0
	if view == View.WEAPON:
		control_pick = false
		paint_mat = ""
		joint_pick = ""
		_clear_link_tool()
		set_paint_tool("")
		if paint != null:
			paint.reset_turn()
	set_hover({})
	_sync_embedded_view()
	view_changed.emit(view)
	changed.emit()


# =================================================================== встроенная мастерская (гараж меню)

## Свет комнаты испытаний во встроенной мастерской (узел TestLights: у гаража лампы расставлены по зонам, а бой идёт посреди комнаты).
func _set_test_lights(on: bool) -> void:
	var tl := get_node_or_null("TestLights") as Node3D
	if tl != null:
		tl.visible = on


## В гараже стенд стоит между камерой и верстаком: в виде «Оружие» кукла со стендом прячутся, чтобы не закрывать оружие.
func _sync_embedded_view() -> void:
	if not embedded:
		return
	var body_view := view == View.BODY
	stand_root.visible = body_view
	if stand != null:
		stand.visible = body_view


## Где оживает кукла испытания: у встроенной мастерской это точка TestSpot на плоскости боя z = 0 (стенд гаража стоит у задней
## стены, а бой 2.5D идёт в плоскости z = 0), иначе — место стенда.
func test_origin() -> Vector3:
	return test_spot.global_position if test_spot != null else stand_root.global_position


## Поза камеры сборки «с нуля» (ни перетаскивания, ни орбиты): куда гаражу вести свою камеру, чтобы передать её мастерской без скачка.
func snap_camera_pose() -> Transform3D:
	_frame_h = 0.0
	var g := _camera_goal()
	return cam_transform(g["pivot"] as Vector3, float(g["h"]), cam_yaw, cam_pitch, cam_zoom)


## Камера сборки встаёт на место камеры гаража (from_cam; null — остаётся где была) и кадр «приклеивается» к бойцу.
func take_camera_from(from_cam: Camera3D) -> void:
	if from_cam != null:
		build_cam.global_transform = from_cam.global_transform
	_cam_snap = true
	build_cam.make_current()


## Включить / усыпить встроенную мастерскую. Включённая берёт камеру (поза — как была у гаража, кадр сразу «приклеивается»),
## спящая не слушает ввод, не считает кадры и не рисуется; автосейв при засыпании пишется сразу.
func set_active(on: bool, take_camera := true) -> void:
	if on == active:
		return
	active = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	set_process_unhandled_input(on)
	set_process_input(on)
	visible = on
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = on
	if on:
		if take_camera:
			take_camera_from(null)
	else:
		if mode == Mode.TEST:
			stop_test()
		cancel_drag()
		_flush_autosave(true)


# =================================================================== испытание

## Кукла оживает: обычная физика, WASD, рука мышью, подбор оружия, манекен и предметы рядом. false — чертёж с ошибками.
var _feel_keep: TrainingFeel                 # живёт между испытаниями (HitFxDirector + SfxDirector внутри)
static var _prop_scenes: Dictionary = {}     # путь -> PackedScene: ящик и бочка испытания не перечитываются с диска
static var _warm_keep: Array = []            # ресурсы испытания, догруженные в фоне (держим — кэш ресурсов Godot слабый)
static var _warm_started := false


## Первый «Испытать» поднимал HitFxDirector и SfxDirector, манекена и пропсы с диска (≈ 270 мс): через 1.5 с после открытия мастерской
## догружаем их в потоке, а слои звука собираем по одному за кадр. Headless-пробы не греют (им фон не нужен).
func _warm_test_resources() -> void:
	if _warm_started or DisplayServer.get_name() == "headless":
		return
	_warm_started = true
	await get_tree().create_timer(1.5).timeout
	var left: Array = [TrainingFeel.HIT_FX_DIRECTOR_SCENE, TrainingFeel.SFX_DIRECTOR_SCENE, DummyScript.DUMMY_SCENE, CRATE_SCENE, BARREL_SCENE]
	for p in left:
		ResourceLoader.load_threaded_request(String(p))
	var guard := 0
	while not left.is_empty() and guard < 200 and is_inside_tree():
		await get_tree().create_timer(0.1).timeout
		guard += 1
		for p in left.duplicate():
			var st := ResourceLoader.load_threaded_get_status(String(p))
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				_warm_keep.append(ResourceLoader.load_threaded_get(String(p)))
				left.erase(p)
			elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				left.erase(p)
	for layer in SfxDirector.LAYER_ORDER:
		if not is_inside_tree():
			return
		SfxDirector.warm_layer(String(layer))
		await get_tree().process_frame


static func _prop_scene(path: String) -> PackedScene:
	if not _prop_scenes.has(path):
		_prop_scenes[path] = load(path) as PackedScene
	return _prop_scenes[path]


func start_test() -> bool:
	if mode == Mode.TEST:
		return true
	if embedded and test_ready_check.is_valid() and not bool(test_ready_check.call()):
		_say("Готовим зал за воротами…", COL_INFO)
		return false
	var errs := CraftEdit.friendly_errors(blueprint)
	if not errs.is_empty():
		_say(errs[0], COL_BAD)
		return false
	cancel_drag()
	control_pick = false
	paint_mat = ""
	joint_pick = ""
	_clear_link_tool()
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
	# «сок» боя до кукол: их DollCombat находит TrainingFeel по группе "match" (WORKSHOP_V3.md §5)
	if _feel_keep == null or not is_instance_valid(_feel_keep):
		_feel_keep = TrainingFeel.new()
		_feel_keep.name = "TrainingFeel"
	else:
		_feel_keep.reset_for_test()
	feel = _feel_keep
	test_root.add_child(feel)
	feel.rebind_directors()
	var d := MODULAR_DOLL.instantiate() as ModularDoll
	d.name = "Player"
	d.blueprint = CraftEdit.dup_body(blueprint)
	d.player_index = 0
	d.input_prefix = "p1"
	d.external_input = probe_input
	d.position = test_origin() + Vector3(0, 0.02, 0)
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
		var ps := _prop_scene(String(spec[0]))
		if ps != null:
			var it := ps.instantiate() as Node3D
			it.position = (spec[1] as Node3D).global_position
			test_root.add_child(it)
	test_cam = DynamicCamera.new()
	test_cam.name = "TestCamera"
	test_cam.fov = 45.0
	test_cam.target_group = TEST_GROUP
	test_cam.arena_path = test_arena_path
	test_cam.follow_mode = test_follow_mode
	test_cam.floor_inset = 0.0
	test_cam.min_half_height = test_min_half_height
	test_cam.padding = 1.5
	test_cam.padding_y = 1.0
	add_child(test_cam)
	test_cam.make_current()
	test_cam.snap()
	feel.camera = test_cam
	_set_test_lights(true)
	mode_changed.emit(mode)
	changed.emit()
	_say(tr("Испытание! Esc / Tab — назад к сборке"), COL_OK)
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
		if c == _feel_keep:
			_feel_keep.abort_fx()   # эффекты прежнего испытания гасим сразу, сам узел живёт до следующего
			continue
		c.queue_free()
	test_doll = null
	test_weapon = null
	dummy = null
	feel = null
	Engine.time_scale = 1.0   # стоп-кадр heavy мог остаться (TrainingFeel уже в очереди на удаление)
	if test_cam != null:
		_free_node(test_cam)
		test_cam = null
	build_cam.make_current()
	_cam_snap = true
	mode = Mode.BUILD
	_set_test_lights(false)
	_rebuild()
	mode_changed.emit(mode)
	_say(tr("Назад к сборке"), COL_INFO)


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
	var pulls: PackedStringArray = []
	for c in blueprint.control:
		pulls.append("%s (%s)" % [uid_title("body", c), tr("ПКМ") if blueprint.control_rmb.has(c) else tr("ЛКМ")])
	ctrl = ", ".join(pulls)
	var weapon_line := ""
	if blueprint.weapon != null:
		var m := _mount()
		weapon_line = "%s → %s" % [(blueprint.weapon as WeaponBlueprint).title.trim_suffix(" *"),
			uid_title("body", String(m["uid"])) if String(m["uid"]) != "" else tr("некуда")]
	var accel := ref / maxf(mass + wmass, 0.1)
	return {"title": blueprint.title, "energy": blueprint.energy_used(), "budget": blueprint.energy_cap(), "mass": mass, "hp": blueprint.parts_hp_total(),
		"links": blueprint.links.size(),
		"weapon_mass": wmass, "bodies": bodies, "parts": blueprint.nodes.size(), "accel": accel, "ref": ref,
		"control": ctrl, "weapon": weapon_line, "errors": CraftEdit.friendly_errors(blueprint),
		"warnings": CraftEdit.warnings(blueprint)}


## Что станет со сборкой, если отпустить деталь в руке (v0.3 §19: справа «было → станет»): {mass, energy, accel, parts, ok, code, reason};
## {} — не над разъёмом тела.
func drag_preview() -> Dictionary:
	var t := drag_target()
	if t.is_empty() or String(t["target"]) != "body":
		return {}
	var dt := drag_trial(t)
	if dt.is_empty():
		return {}
	var s := body_stats()
	var ref := float(s["ref"])
	var bp: BodyBlueprint = dt.get("bp") if dt.get("bp") is BodyBlueprint else null
	if PartHp.on and bp != null and (stand == null or (stand as ModularDoll).thrust_ref_mass <= 0.0):
		ref = bp.thrust_n() / Tuning.MOVE_FORCE_PER_KG   # запас из деталей: другое ядро — другой мотор
	var mass := float(dt.get("mass_after", s["mass"]))
	return {"ok": bool(dt.get("ok", false)), "code": String(dt.get("code", "")), "reason": String(dt.get("reason", "")), "mass": mass, "energy": int(dt.get("energy_after", s["energy"])),
		"parts": bp.nodes.size() if bp != null else int(s["parts"]), "accel": ref / maxf(mass + float(s["weapon_mass"]), 0.1),
		"hp": bp.parts_hp_total() if bp != null else int(s["hp"])}


## Центр массы стенда (мир); без стенда — ноль.
func stand_com() -> Vector3:
	if stand == null:
		return Vector3.ZERO
	var sm := 0.0
	var acc := Vector3.ZERO
	for b in stand.parts.values():
		var rb := b as RigidBody3D
		acc += rb.global_transform * ModularDoll._com_local(rb) * rb.mass
		sm += rb.mass
	return acc / sm if sm > 0.0 else Vector3.ZERO


## Центр массы с деталью из протяжки на выбранном разъёме (Physics Overlay: куда он сместится); null — не тащим / не на теле.
func drag_com() -> Variant:
	if drag.is_empty() or stand == null:
		return null
	var t := drag_target()
	if t.is_empty() or String(t["target"]) != "body" or not bool(t["ok"]):
		return null
	var g := _ghost_cached(t)
	if not (g.get("xf") is Transform3D):
		return null
	var sm := 0.0
	var acc := Vector3.ZERO
	var gone := {}   # тела, которых не станет: заменяемое поддерево и переносимая ветка (своё тело — не слитые fixed-детали)
	var off: PackedStringArray = CraftEdit.subtree(blueprint, String(t["replace"])) if String(t["replace"]) != "" else PackedStringArray()
	off.append_array(_hidden_uids)
	for u in off:
		if not CraftEdit.is_fixed(blueprint, u):
			gone[String(stand.uid_body.get(u, ""))] = true
	for bn in stand.parts:
		var rb := stand.parts[bn] as RigidBody3D
		if gone.has(String(bn)):
			continue
		acc += rb.global_transform * ModularDoll._com_local(rb) * rb.mass
		sm += rb.mass
	# что встанет: деталь, копия ветки или вся переносимая ветка — масса по пробному чертежу, в точке призрака (приближённо)
	var add := 0.0
	var dt := drag_trial(t)
	var tbp: BodyBlueprint = dt.get("bp") if dt.get("bp") is BodyBlueprint else null
	if tbp != null and String(dt.get("uid", "")) != "":
		for u in CraftEdit.subtree(tbp, String(dt["uid"])):
			add += tbp.node_mass(u)
	else:
		var d := CraftEdit.part(String(drag["part"]))
		add = d.mass if d != null else 0.0
	acc += (g["xf"] as Transform3D).origin * add
	sm += add
	return acc / sm if sm > 0.0 else null


## Оружие верстака: цифры CraftedWeapon.summary() и слова. [{id (mass / com / length / spin / damage — для иконок), label, value, value_short (без «от хвата»), word, frac}] + ошибки.
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
		{"id": "mass", "label": tr("Масса"), "value": tr("%.1f кг") % mass, "value_short": tr("%.1f кг") % mass, "frac": mass / 8.0,
			"word": tr("пёрышко") if mass < 1.5 else (tr("в самый раз") if mass < 3.0 else (tr("тяжёлое") if mass < 5.0 else (tr("очень тяжёлое") if mass < 7.5 else tr("неподъёмное"))))},
		{"id": "com", "label": tr("Центр масс"), "value": tr("%.2f м от хвата") % com, "value_short": tr("%.2f м") % com, "frac": bal,
			"word": tr("у руки: послушное") if bal < 0.35 else (tr("посередине") if bal < 0.62 else tr("в головке: тянет в замах"))},
		{"id": "length", "label": tr("Длина"), "value": tr("%.2f м") % ln, "value_short": tr("%.2f м") % ln, "frac": ln / 2.0,
			"word": tr("короткое") if ln < 0.5 else (tr("среднее") if ln < 0.95 else tr("длинное: большой рычаг"))},
		{"id": "spin", "label": tr("Раскрутка"), "value": tr("%.2f кг·м²") % inertia, "value_short": tr("%.2f кг·м²") % inertia, "frac": inertia / 3.0,
			"word": tr("вертится легко") if inertia < 0.15 else (tr("надо раскрутить") if inertia < 0.6 else (tr("туго, зато не остановить") if inertia < 1.6 else tr("мельница")))},
		{"id": "damage", "label": tr("Урон"), "value": "×%.2f" % mult, "value_short": "×%.2f" % mult, "frac": (mult - 1.0) / 1.5,
			"word": tr("тупое — бьёт массой") if mult < 1.05 else (tr("шипы / крюк") if mult < 1.3 else tr("лезвие: режет"))},
	]
	out["bodies"] = int(s["bodies"])
	out["summary"] = s
	return out


## Подсказка внизу экрана по состоянию.
func hint_text() -> String:
	if mode == Mode.TEST:
		return tr("WASD — лететь · Shift — ускорение · Space + A/D — раскрутка · ЛКМ / ПКМ — тяги · E — схватить / бросить · R — заново · Esc — к сборке")
	if paint_tool != "":
		return paint.hint_text()
	if paint != null and paint.tab_open and view == View.BODY:
		return tr("Выбери инструмент на полке «Покраска»: баллончик, трафарет, наклейка, фото…   ·   R — повернуть стенд")
	if control_pick:
		return tr("Клик по детали — тяга ЛКМ (золотая), ещё клик — ПКМ (голубая), ещё — снять   ·   первая бесплатно, дальше ⚡ × вынос   ·   Esc / ПКМ — готово")
	if paint_mat != "":
		var mt := CraftEdit.mat_title(paint_mat)
		if not hover.is_empty() and String(hover["target"]) == "body":
			var hu := String(hover["uid"])
			var c := CraftEdit.check_material(blueprint, hu, paint_mat)
			if not bool(c["ok"]):
				return String(c["reason"])
			if not bool(c["changed"]):
				return tr("%s — уже %s   ·   Esc / ПКМ — убрать кисть") % [uid_title("body", hu), mt]
			return tr("Клик — %s: %s → %s, %.1f → %.1f кг   ·   Esc / ПКМ — убрать кисть") % [uid_title("body", hu),
				CraftEdit.mat_title(String(c["mat_before"])), mt, float(c["mass_before"]), float(c["mass_after"])]
		return tr("Кисть «%s»: кликни по детали куклы — перекрасить (масса × новая плотность / прежняя)   ·   Esc / ПКМ — убрать кисть") % mt
	if joint_pick != "":
		var jt := CraftEdit.joint_title(joint_pick)
		if not hover.is_empty() and String(hover["target"]) == "body":
			var hu2 := String(hover["uid"])
			var cj := CraftEdit.check_joint(blueprint, hu2, joint_pick)
			if not bool(cj["ok"]):
				return String(cj["reason"])
			if not bool(cj["changed"]):
				return tr("%s — уже «%s»   ·   Esc / ПКМ — отмена") % [uid_title("body", hu2), jt]
			return tr("Клик — %s: «%s» → «%s»   ·   Esc / ПКМ — отмена") % [uid_title("body", hu2),
				CraftEdit.joint_title(String(cj["joint_before"])), jt]
		return tr("Шарнир «%s»: кликни по детали — так она будет держаться за родителя   ·   Esc / ПКМ — отмена") % jt
	if not drag.is_empty():
		var t := drag_target()
		if not t.is_empty() and not bool(t["ok"]):
			return String(t["reason"])
		if not t.is_empty() and String(t["replace"]) != "":
			return tr("Отпусти — заменить «%s»   ·   ПКМ / Esc — отмена") % uid_title(String(t["target"]), String(t["replace"]))
		if bool(drag["sticky"]):
			return tr("Кликни у зелёного якоря — поставить   ·   ПКМ / Esc — убрать деталь")
		return tr("Поднеси к зелёному якорю и отпусти   ·   ПКМ / Esc — отмена")
	if not hover.is_empty():
		var bp: Resource = weapon_bp if String(hover["target"]) == "weapon" else blueprint
		var n := CraftEdit.subtree(bp, String(hover["uid"])).size()
		var more := "" if n <= 1 else " (+%d)" % (n - 1)
		return tr("%s   ·   ПКМ — открутить%s   ·   Q — тяги") % [part_info(String(hover["target"]), String(hover["uid"])), more]
	if view == View.WEAPON:
		return tr("Тащи рукоять, навершие или мод на верстак   ·   ПКМ по детали — снять   ·   «В руку» — дать кукле   ·   Tab — к телу")
	return tr("Тащи деталь с полки на светящийся якорь   ·   ПКМ — открутить   ·   Q — тяги   ·   Ctrl+Z — отмена   ·   T — испытать")


## Короткая подсказка по ситуации (v0.3 §36: вместо постоянной строки клавиш) — одна строка, «клавиша — действие»; ничего не
## выбрано и ничего в руке — пусто (подсказку для первого раза показывает UI, пока игрок не поставил первую деталь).
func context_help() -> String:
	if mode == Mode.TEST:
		return tr("WASD — движение  ·  ЛКМ / ПКМ — тяги  ·  R — заново  ·  Esc — к сборке")
	if paint_tool != "" or (paint != null and paint.tab_open and view == View.BODY):
		return paint.hint_text() if paint_tool != "" else ""
	if control_pick:
		return tr("Клик по детали — тяга ЛКМ → ПКМ → снять  ·  Esc — готово")
	if paint_mat != "":
		return _tool_help(CraftEdit.check_material(blueprint, String(hover.get("uid", "")), paint_mat) if _hover_body() else {},
			"mat", CraftEdit.mat_title(paint_mat))
	if joint_pick != "":
		return _tool_help(CraftEdit.check_joint(blueprint, String(hover.get("uid", "")), joint_pick) if _hover_body() else {},
			"joint", CraftEdit.joint_title(joint_pick))
	if link_pick != "":
		var tail := tr("  ·  клик по поршню — канал") if link_pick == "piston" else ""
		if link_from.is_empty():
			return tr("Клик — первый конец связки  ·  клик по связке — снять%s  ·  Esc — готово") % tail
		return tr("Клик по второй детали — поставить связку  ·  Esc — отмена")
	if not pending_mirror.is_empty():
		return tr("Enter или клик по копии — поставить  ·  Esc — отмена")
	if not drag.is_empty():
		var t := drag_target()
		if not t.is_empty():
			var bad := _drag_refusal(t)
			if bad != "":
				return bad
			if String(t["replace"]) != "":
				return tr("ЛКМ — заменить: %s  ·  ПКМ — отменить") % _pname(CraftEdit.def_of(weapon_bp if String(t["target"]) == "weapon" else blueprint,
					String(t["replace"])))
		return tr("ЛКМ — установить  ·  ПКМ — отменить")
	if String(selected.get("source", "")) == "stand":
		if String(selected["target"]) == "weapon":
			return tr("D — копия  ·  Del — снять  ·  Tab — к бойцу")
		return tr("D — копия  ·  M — зеркало  ·  Del — снять  ·  тащи — перенести")
	if String(selected.get("source", "")) == "shelf":
		return tr("Тащи на бойца  ·  D — в руку")
	return ""


## Подсказка — отказ (красным в UI): деталь в руке над разъёмом, куда она не встанет.
func context_help_bad() -> bool:
	if drag.is_empty() or mode != Mode.BUILD:
		return false
	var t := drag_target()
	return not t.is_empty() and _drag_refusal(t) != ""


## Причина отказа коротко: энергия — «Не хватает энергии: будет 104 / 100», иначе первая фраза причины.
func _drag_refusal(t: Dictionary) -> String:
	var dt := drag_trial(t) if String(t["target"]) == "body" else {}
	var ok := bool(t["ok"]) and (dt.is_empty() or bool(dt.get("ok", false)))
	if ok:
		return ""
	var why := String(dt.get("reason", t.get("reason", ""))) if not dt.is_empty() else String(t.get("reason", ""))
	var code := String(dt.get("code", t.get("code", ""))) if not dt.is_empty() else String(t.get("code", ""))
	if code == "energy":
		var e := int(dt.get("energy_after", 0)) if not dt.is_empty() else 0
		return tr("Не хватает энергии: будет %d / %d") % [e, blueprint.energy_cap()] if e > 0 else tr("Не хватает энергии")
	if why == "":
		return tr("Сюда не встанет")
	var dot := why.find(". ")
	return why.substr(0, dot) if dot > 0 else why


func _hover_body() -> bool:
	return not hover.is_empty() and String(hover["target"]) == "body"


## Кисть материала / шарнир: над деталью — «Плечо: дерево → железо, 2.0 → 4.4 кг» или отказ; иначе — что делать.
func _tool_help(c: Dictionary, kind: String, what: String) -> String:
	if c.is_empty():
		return tr("Кликай по деталям бойца — «%s»  ·  Esc — положить") % what
	var hu := String(hover.get("uid", ""))
	if not bool(c.get("ok", false)):
		var why := String(c.get("reason", ""))
		var dot := why.find(". ")
		return why.substr(0, dot) if dot > 0 else why
	if not bool(c.get("changed", true)):
		return tr("%s — уже «%s»") % [uid_title("body", hu), what]
	if kind == "mat":
		return tr("%s: %s → %s, %.1f → %.1f кг") % [uid_title("body", hu), CraftEdit.mat_title(String(c["mat_before"])).to_lower(),
			what.to_lower(), float(c["mass_before"]), float(c["mass_after"])]
	return "%s: «%s» → «%s»" % [uid_title("body", hu), CraftEdit.joint_title(String(c["joint_before"])), what]


## Что рисовать поверх 3D (scenes/workshop/ui/anchor_overlay.gd): [{pos, dir, state, label, joint?}] в экранных точках.
## state: target (выбран), ok, replace, bad (не влезает), idle (свободный якорь без протяжки), control (рука мышью),
## joint / joint_hover (инструмент шарнира: точка связи детали с родителем, joint — тип KitJoint, наведённая — joint_hover).
func overlay_items() -> Array:
	var out: Array = []
	var cam := get_viewport().get_camera_3d()
	if cam == null or mode != Mode.BUILD:
		return out
	_fx_items(cam, out)
	if not drag.is_empty():
		# v0.3 §15: разъёмы видны только пока деталь в руке — совместимые, ярче ближе к курсору; несовместимые не рисуем
		var targets: Array = drag["targets"]
		var mp := drag["pos"] as Vector2
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
			var it := _overlay_item(cam, t["xf"], st, "")
			it["near"] = clampf(1.0 - (it["pos"] as Vector2).distance_to(mp) / 420.0, 0.0, 1.0)
			out.append(it)
		var sp: Variant = carry_socket_screen()
		if sp is Vector2:
			out.append({"pos": sp, "dir": Vector2.ZERO, "state": "carry", "label": "",
				"ok": not drag_target().is_empty() and bool(drag_target()["ok"])})
		_com_items(cam, out)
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
	# выбранная деталь (§25): её точка крепления — маленькое янтарное кольцо
	if String(selected.get("source", "")) == "stand" and String(selected["target"]) == target:
		var sn := CraftEdit.find(bp, String(selected["uid"]))
		if String(sn.get("parent", "")) != "":
			var jxf: Variant = anchor_xf(target, String(sn["parent"]), String(sn.get("anchor", "")))
			if jxf is Transform3D:
				out.append(_overlay_item(cam, jxf, "joint_sel", ""))
	# без протяжки разъёмов не видно (v0.3 §44); тяги — только с инструментом Q
	if target == "body" and stand != null:
		for c in blueprint.control:
			if not pulls_visible(c):
				continue
			var ms := part_meshes("body", c)
			if not ms.is_empty():
				var box := _visual_aabb(ms[0])
				out.append({"pos": cam.unproject_position(box.get_center()), "dir": Vector2.ZERO, "state": "control",
					"rmb": blueprint.control_rmb.has(c), "label": tr("ПКМ") if blueprint.control_rmb.has(c) else tr("ЛКМ")})
	# активные блоки: значок клавиши канала у каждого (docs/plan-demo/ACTIVE_BLOCKS.md) — когда видны (channels_visible)
	if target == "body" and stand != null and channels_visible():
		for n in blueprint.nodes:
			if not ActiveBlocks.is_active(String(n.get("part", ""))):
				continue
			var msa := part_meshes("body", String(n.get("uid", "")))
			if msa.is_empty():
				continue
			var ch := ActiveBlocks.channel_of(n)
			out.append({"pos": cam.unproject_position(_visual_aabb(msa[0]).get_center()), "dir": Vector2.ZERO, "state": "channel",
				"channel": ch, "label": ActiveBlocks.key_label("p1", ch) if ch > 0 else "—"})
	_com_items(cam, out)
	return out


## Вспышка у разъёма (деталь встала / открутилась) и красный пульс с причиной (не встала).
func _fx_items(cam: Camera3D, out: Array) -> void:
	for e in fx_events:
		var p: Vector3 = e["pos"]
		if cam.is_position_behind(p):
			continue
		var life := REFUSE_S if String(e["kind"]) == "refuse" else FLASH_S
		out.append({"pos": cam.unproject_position(p), "dir": Vector2.ZERO, "state": String(e["kind"]), "label": String(e["text"]),
			"age": clampf((_time - float(e["t0"])) / life, 0.0, 1.0)})


## Physics Overlay (ФИЗИКА, выключен по умолчанию): центр массы, куда он сместится при протяжке. Рисует WsPhysics в UI —
## здесь только точки для кольцевого слоя.
func _com_items(cam: Camera3D, out: Array) -> void:
	if view != View.BODY or stand == null or (paint != null and paint.tab_open) or not show_com:
		return
	var floor_y := stand_root.global_position.y if stand_root != null else 0.0
	if show_com:
		var c := stand_com()
		out.append({"pos": cam.unproject_position(c), "floor": cam.unproject_position(Vector3(c.x, floor_y, c.z)), "dir": Vector2.ZERO,
			"state": "com", "label": ""})
	if physics_hints:
		var g: Variant = drag_com()
		if g is Vector3:
			var c0 := stand_com()
			var dx := ((g as Vector3).x - c0.x) * 100.0
			var dy := ((g as Vector3).y - c0.y) * 100.0
			out.append({"pos": cam.unproject_position(g), "from": cam.unproject_position(c0), "dir": Vector2.ZERO, "state": "com_ghost",
				"label": tr("ЦМ %s%.0f / %s%.0f см") % ["→" if dx >= 0 else "←", absf(dx), "↑" if dy >= 0 else "↓", absf(dy)]})


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
	_prune_fx()
	if not _trial_queue.is_empty():
		_run_trials(TRIAL_FRAME_MS)
	_edge_pan(delta)
	_update_carry(delta)
	var g := _camera_goal()
	var pivot: Vector3 = g["pivot"]
	var h := float(g["h"])
	if _cam_snap:
		_s_pivot = pivot
		_s_h = h
		_s_yaw = cam_yaw
		_s_pitch = cam_pitch
		_s_zoom = cam_zoom
		_cam_snap = false
	else:
		var a := 1.0 - exp(-delta / CAM_TAU)
		var b := 1.0 - exp(-delta / 0.07)   # орбита и зум — сразу за мышью, кадр — мягко
		_s_pivot = _s_pivot.lerp(pivot, a)
		_s_h = lerpf(_s_h, h, a)
		_s_yaw = lerpf(_s_yaw, cam_yaw, b)
		_s_pitch = lerpf(_s_pitch, cam_pitch, b)
		_s_zoom = lerpf(_s_zoom, cam_zoom, b)
	build_cam.global_transform = cam_transform(_s_pivot, _s_h, _s_yaw, _s_pitch, _s_zoom)


## Кадр камеры: точка pivot (середина сборки) — в середине свободной зоны экрана (free_rect), полувысота кадра h × zoom, орбита
## yaw / pitch вокруг неё (v0.3 §39: ПКМ — вращать, колесо — ближе / дальше, R — сброс).
func cam_transform(pivot: Vector3, h: float, yaw: float, pitch: float, zoom: float) -> Transform3D:
	var basis := Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0.0))
	var hz := h * zoom
	var dist := hz / tan(deg_to_rad(CAM_FOV) * 0.5)
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var fr := free_rect()
	var cx := fr.get_center().x / maxf(vp.x, 1.0)
	var cy := fr.get_center().y / maxf(vp.y, 1.0)
	var look := pivot + basis * Vector3(-(cx - 0.5) * 2.0 * hz * aspect, (cy - 0.5) * 2.0 * hz, 0.0)
	return Transform3D(basis, look + basis.z * dist)


## Свободная зона экрана для бойца (между библиотекой, правой панелью, верхней строкой и кнопкой испытания): у UI — free_rect(),
## без UI — доли FREE_*.
func free_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	if ui != null and ui.has_method("free_rect"):
		var r: Rect2 = ui.call("free_rect")
		if r.size.x > 50.0 and r.size.y > 50.0:
			return r
	var w := vp.x * FREE_W_FRAC
	var hh := vp.y * FREE_H_FRAC
	return Rect2(vp.x * FREE_CX_FRAC - w * 0.5, vp.y * 0.46 - hh * 0.5, w, hh)


## Что держит камера: {pivot, h}. Кадр не дёргается (v0.3 §40): растёт сразу, сжимается, только если сборка стала заметно меньше,
## центр переезжает, только если ушёл дальше 12 % кадра; пока тащишь деталь или вращаешь — кадр стоит.
func _camera_goal() -> Dictionary:
	var busy := not drag.is_empty() or not _rmb.is_empty() or not _lmb.is_empty() or not pending_mirror.is_empty()
	if busy and _frame_h > 0.0:
		return {"pivot": _frame_c + _cam_pan, "h": _frame_h}
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
	var fr := free_rect()
	var wf := fr.size.x / maxf(vp.x, 1.0)
	var hf := fr.size.y / maxf(vp.y, 1.0)
	var need_h := maxf(box.size.y * 0.5 / hf + 0.1, (box.size.x * 0.5 + 0.2) / (aspect * wf))
	need_h = maxf(need_h, min_h)
	var c := box.get_center()
	if _frame_h <= 0.0 or need_h > _frame_h or need_h < _frame_h * 0.82:
		_frame_h = need_h
		_frame_c = c
	elif c.distance_to(_frame_c) > _frame_h * 0.12:
		_frame_c = c
	return {"pivot": _frame_c + _cam_pan, "h": _frame_h}


## Камера в исходный кадр (R).
func reset_camera() -> void:
	cam_yaw = 0.0
	cam_pitch = 0.0
	cam_zoom = 1.0
	_cam_pan = Vector3.ZERO
	_frame_h = 0.0


func orbit(rel: Vector2) -> void:
	cam_yaw = clampf(cam_yaw - rel.x * 0.3, -ORBIT_YAW_MAX, ORBIT_YAW_MAX)
	cam_pitch = clampf(cam_pitch + rel.y * 0.22, ORBIT_PITCH.x, ORBIT_PITCH.y)


func zoom_by(steps: float) -> void:
	cam_zoom = clampf(cam_zoom * pow(0.9, steps), ZOOM_RANGE.x, ZOOM_RANGE.y)


## Тащишь деталь у края рабочей зоны дольше 0.35 с — камера мягко едет туда (приближенную сборку можно «довести» до разъёма).
func _edge_pan(delta: float) -> void:
	if drag.is_empty() or build_cam == null:
		_edge_t = 0.0
		_cam_pan = _cam_pan.lerp(Vector3.ZERO, 1.0 - exp(-delta / 0.6)) if drag.is_empty() and _frame_h > 0.0 else _cam_pan
		if drag.is_empty() and _cam_pan.length() < 0.002:
			_cam_pan = Vector3.ZERO
		return
	var p := drag["pos"] as Vector2
	var fr := free_rect()
	var v := Vector2.ZERO
	if fr.has_point(p):
		if p.x < fr.position.x + EDGE_PAN_PX:
			v.x = -1.0
		elif p.x > fr.end.x - EDGE_PAN_PX:
			v.x = 1.0
		if p.y < fr.position.y + EDGE_PAN_PX:
			v.y = 1.0
		elif p.y > fr.end.y - EDGE_PAN_PX:
			v.y = -1.0
	if v == Vector2.ZERO:
		_edge_t = 0.0
		return
	_edge_t += delta
	if _edge_t < 0.35:
		return
	var b := build_cam.global_basis
	_cam_pan += (b.x * v.x + b.y * v.y) * _frame_h * cam_zoom * 0.6 * delta
	_cam_pan = _cam_pan.limit_length(_frame_h * 0.7)


## Вспышки щелчка / отказа: живут FLASH_S / REFUSE_S.
func _prune_fx() -> void:
	var keep: Array = []
	for e in fx_events:
		var life := REFUSE_S if String(e["kind"]) == "refuse" else FLASH_S
		if _time - float(e["t0"]) < life:
			keep.append(e)
	fx_events = keep


func _say(text: String, colour: Color) -> void:
	if text == "":
		return
	toast.emit(text, colour)
