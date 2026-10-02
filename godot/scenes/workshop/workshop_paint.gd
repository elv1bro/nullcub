## Покраска на стенде мастерской (docs/plan-demo/BODY_PAINT.md §1, §6): инструменты вкладки «Покраска» поверх куклы стенда. Узел —
## ребёнок WorkshopBuild (ws.paint, создаётся в его _ready), полка — scenes/workshop/ui/paint_panel.gd, проба — tests/workshop_probe.gd
## (раздел paint_* / sticker_* / face_*).
##
## Инструмент (tool): spray — баллончик, erase — ластик, fill — заливка детали, pattern — раскраски (клик — деталь и её пара, Shift —
## вся кукла волной от ядра, по PATTERN_BUDGET_US за физкадр; раскраска заменяет краску детали, повторный клик — новый вариант),
## pick — пипетка (краска детали, иначе цвет её материала; Alt+клик баллончиком — то же), stencil — трафарет (маска «stencil:<имя>»
## цветом краски), sticker — наклейка (картинка KitImages), face — фото на голову. "" — инструмент положен (Esc / ПКМ, смена вкладки,
## вида, испытание, любой другой инструмент мастерской — WorkshopBuild.clear_tools).
##
## Попадание — луч камеры по треугольникам ВСЕХ мешей стенда (TriangleMesh.intersect_ray в кадре меша, кэш по мешу), ближайший:
## меш детали (BodyPaint.meshes её корня) даёт uid и корень меша, прочие (коннекторы шарниров, оружие в руке) только заслоняют. Так
## точнее физлуча PICK_LAYER: формы — капсулы и коробки, у декора форм может не быть; краска ложится туда, куда смотришь.
## Точка → кадр корня меша (root.global_transform⁻¹) → PaintLayer живой ручки ModularDoll.ensure_paint(uid) — без пересборки куклы.
##
## Штрих: нажал ЛКМ — stroke_begin, каждый физкадр — путь курсора от прошлой точки до текущей: лучи камеры через STEP_PX по экрану
## (≤ RAY_BUDGET за кадр), между соседними попаданиями в одну деталь мазки идут по поверхности с шагом ≈ 0.35 кисти (_dab_spacing;
## ≤ DAB_BUDGET за кадр, для большой кисти меньше — по числу ячеек), краски на единицу пути столько же при любой скорости (туман и
## точки мазка — доля «мазка на шаг STEP_PX»); update_texture затронутых слоёв. Кисть не мельче BRUSH_CELL_MIN ячейки слоя детали
## (иначе мазок 1 см на ядре с ячейкой 14 мм в 80 % случаев не задевал ни одного центра ячейки), кольцо показывает этот размер.
## Отпустил — stroke_end: одна запись в историю ws (снимок до штриха: чертёж до отпускания не менялся), node.paint = layer.to_dict()
## узлов, чей слой штрих ИЗМЕНИЛ (пустой слой — ключ стирается; штрих, который ничего не поменял, записи не даёт). Отмена — как всё
## в мастерской: снимок → пересборка стенда. Симметрия (вкл.): луч отражается в кадре куклы (x → −x, и начало, и направление — при
## повёрнутом стенде зеркальный луч приходит с другой стороны) и красит то, во что попал; точка у плоскости симметрии — без пары.
##
## Наклейки (stencil / sticker): клик — меш-наклейка (BodyPaint.add_sticker) в точке попадания (Y — нормаль, «верх» картинки — верх
## экрана, повёрнутый на sticker_rot), кадр в кадре корня меша → node.stickers (BODY_PAINT.md §4) + ModularDoll.add_sticker. Над
## наклейкой: колесо / [ ] / щипок и прокрутка трекпада — размер (2–40 см по большей стороне), Q / E — поворот на 15°, тащить —
## переставить (можно на другую деталь), ПКМ / Delete — снять; не над наклейкой они настраивают следующую (и слайдер «Размер» на
## полке). С симметрией правка идёт и «близнецу» (та же картинка в зеркальной точке, TWIN_TOL); наклейка, чья коробка задела бы
## зеркальную копию (у плоскости симметрии), — одна и встаёт ровно на плоскость. Серия колёсиком / Q / E по одной наклейке — одна
## запись истории (COALESCE_S). Меш наклейки — треугольники только ЭТОЙ детали без поясов и шаров (цвет игрока не закрывается);
## превью у курсора — такая же меш-наклейка, полупрозрачная.
## Фото: голова кита — node.face (BodyPaint.set_face, живьём); старая голова (плашка утоплена под поверхность) — наклейка на лицо с
## пометкой face (одна: новое фото её заменяет, «Снять фото» снимает). Клик по картинке на полке — сразу на голову; клик в 3D — только
## по голове; то же фото повторно — без новой записи истории.
## Импорт: import_files (синхронно — проба) / import_files_async (кнопка «Импорт…» — FileDialog с нативным диалогом; файлы, брошенные
## в окно, get_window().files_dropped): KitImages в потоке WorkerThreadPool, окно не замирает; почему не вышло — словами (слишком
## большая, HEIC, не картинка); брошенная над куклой — сразу наклейка в точку курсора. Картинку можно удалить (ПКМ по плитке), если
## её нет на кукле.
## Раскраски — через очередь: каждая деталь рисуется в черновик (PaintLayer.blank_like) частями по PATTERN_BUDGET_US за кадр
## (PaintLayer.pattern_begin / pattern_run) и ложится в живой слой целиком; правая деталь старой куклы (корень меша не зеркальный)
## получает отражённый рисунок (mirror_x), чтобы пара вышла зеркальной, как у кита.
## Стенд поворачивается на 90° (turn_stand, R / Shift+R): кукла и стойка крутятся вокруг оси стойки (тела заморожены — едут с корнем).
## Отклик: кольцо кисти на поверхности (размер = кисть, толщина — в пикселях), кольцо пары при симметрии, превью наклейки,
## брызги и облачко цвета краски (GPUParticles3D), шипение баллончика (assets/audio/paint, шина SFX, иначе Master), «пуф» при заливке,
## раскраске и наклейке. Каждая правка — WorkshopBuild.mark_dirty (автосейв правок).
class_name WorkshopPaint
extends Node3D

signal changed                    # инструмент, цвета, настройки, картинки — полке обновиться
signal images_changed             # список импортированных картинок
signal open_tab                   # файл брошен в окно: полке открыть вкладку «Покраска»

const TOOLS := ["spray", "erase", "fill", "pattern", "pick", "stencil", "sticker", "face"]
const TOOL_TITLES := {
	"spray": "Баллончик", "erase": "Ластик", "fill": "Заливка", "pattern": "Раскраски", "pick": "Пипетка", "stencil": "Трафарет",
	"sticker": "Наклейка", "face": "Фото на голову",
}
const PATTERNS := ["stripes", "camo", "flames", "dots", "gradient", "graffiti"]
const PATTERN_TITLES := {
	"stripes": "Полосы", "camo": "Камуфляж", "flames": "Пламя", "dots": "Горошек", "gradient": "Градиент", "graffiti": "Граффити",
}
const STENCIL_TITLES := {
	"star": "звезда", "crown": "корона", "skull": "череп", "lightning": "молния", "heart": "сердце", "arrow": "стрелка",
	"crossbones": "кости", "gear": "шестерёнка", "target": "мишень", "flame": "огонь",
}
## Палитра полки: 20 цветов (светлые → тёмные, тёплые → холодные, земля и золото).
const PALETTE := [
	Color("f4f1e8"), Color("a8a39a"), Color("55524d"), Color("1b1a19"), Color("d7261e"),
	Color("f26a1b"), Color("f7c21a"), Color("9bd33a"), Color("2f9e44"), Color("1f7a6d"),
	Color("35c6d9"), Color("3a8fe0"), Color("2b45b8"), Color("7a3fc8"), Color("d63fb4"),
	Color("ff8fb1"), Color("7a4a26"), Color("d9b382"), Color("6b7a2a"), Color("c9a227"),
]
const RECENT_MAX := 8
const SIZE_CM := Vector2(1.0, 10.0)        # диаметр кисти
const STICKER_CM := Vector2(2.0, 40.0)     # большая сторона наклейки
const STICKER_START_CM := 12.0
const ROT_STEP_DEG := 15.0
const SCALE_STEP := 1.12
const SYM_EPS := 0.012                     # м от плоскости симметрии: ближе — без пары
const TWIN_TOL := 0.04                     # м: пара детали / наклейки — в зеркальной точке не дальше
const STEP_PX := 6.0                       # шаг лучей штриха по экрану (мазки между лучами — по поверхности)
const RAY_BUDGET := 32                     # лучей штриха за физкадр на сторону (дальше шаг лучей растёт)
const DAB_BUDGET := 48                     # мазков за физкадр на сторону (малая кисть; большой — меньше, см. DAB_CELLS)
const DAB_CELLS := 2400.0                  # ≈ ячеек тумана за физкадр на сторону: мазков не больше DAB_CELLS / ячеек тумана мазка
const DOT_BUDGET := 64                     # точек напыления за физкадр на сторону (≈ как раньше: неподвижный — 48, быстрый — 72)
const DAB_SPACING := 0.35                  # шаг мазков по поверхности — доля эффективного радиуса кисти
const DAB_SPACING_MIN := 0.003             # м
const BRUSH_CELL_MIN := 0.9                # кисть не мельче 0.9 ячейки слоя детали: центр ячейки всегда в радиусе
## Мазок «на шаг STEP_PX»: туман — как два вызова PaintLayer.spray по SPRAY_MIST (баллончик «жирный»), точек — 2 × 24.
const SPRAY_MIST_STEP := 1.0 - (1.0 - PaintLayer.SPRAY_MIST) * (1.0 - PaintLayer.SPRAY_MIST)
const SPRAY_DOTS_STEP := 48
const COALESCE_S := 0.9
const PATTERN_BUDGET_US := 4000            # раскраска: мкс работы за физкадр (деталь 60 000 ячеек — за 5–10 кадров, без рывка)
const PAN_STEP := 1.0                      # трекпад: прокрутка delta.y на один шаг колеса
const PREVIEW_ALPHA := 0.6
const RAY_LEN := 60.0
const TURN_S := 0.35
const ERASE_FLOW := 0.45                   # ластик: доля стирания за мазок × нажим
const RING_PX := 2.6                       # толщина кольца кисти на экране
const HOVER_TOOLS := ["fill", "pattern", "face"]   # подсветка детали под курсором (у остальных — кольцо / превью)
const SND_LOOP := "res://assets/audio/paint/spray_loop.wav"
const SND_START := "res://assets/audio/paint/spray_start.wav"
const SND_RATTLE := "res://assets/audio/paint/can_rattle.wav"
const HISS_DB := -9.0
const ERASE_DB := -17.0

var ws: WorkshopBuild
var tool := ""
var color := Color("d7261e")
var color2 := Color("f7c21a")
var recent: Array = []                     # Array[Color], свежие первыми
var size_cm := 4.0
var pressure := 0.85                       # нажим: потолок альфы баллончика, сила ластика и заливки
var hardness := 0.45
var pattern_kind := "flames"
var own_colors := false                    # раскраска цветом и вторым цветом (иначе — родная палитра узора)
var stencil := "star"
var image := ""                            # id картинки KitImages (наклейка / фото)
var symmetry := true
var stand_turn := 0                        # 0..3 × 90°
var sticker_cm := STICKER_START_CM         # размер следующей наклейки
var sticker_rot := 0.0                     # поворот следующей наклейки, °
var focus_uid := ""                        # деталь последней правки («Очистить деталь»)
var tab_open := false                      # полка «Покраска» открыта (UI): якоря стенда не рисуются
var virtual_mouse := false                 # проба: курсор только из API (stroke_* / set_mouse), не из вьюпорта
var hold_check := true                     # штрих мышью кончается, если ЛКМ уже отпущена (отпустили над панелью)

var _mouse := Vector2(-1, -1)
## {touched, dirty, before: {uid: байты слоя до штриха}, last: Vector2, mouse: bool, erase: bool, hit, prev: [попадание, зеркальное]}
var _stroke: Dictionary = {}
var _sdrag: Dictionary = {}                # перетаскивание наклейки {ref, twin, start, moved, hit, twin_hit, bake}
var _pattern_queue: Array = []             # [[uid, kind, colors, seed, mirror_x]] — раскраски по очереди
var _pattern_job: Dictionary = {}          # деталь в работе: {uid, h, tmp: PaintLayer, job, col}
var _pattern_total := 0
var _pattern_kind_now := ""
var _pan_acc := 0.0                        # трекпад: накопленная прокрутка / щипок до шага колеса
var _mag_acc := 0.0
var _cells: Dictionary = {}                # uid -> ребро ячейки слоя детали в мире (кольцо кисти, шаг мазков)
var _import_tasks: PackedInt64Array = []   # WorkerThreadPool: импорт картинок в работе
var _tool_before_pick := ""
var _turn_angle := 0.0
var _turn_rest: Array = []                 # [[тело, глобальный кадр при 0°]] — тела куклы и оружия стенда (поворот — от них)
var _turn_tween: Tween
var _targets: Array = []                   # [{mi, uid, root}] мешей стенда
var _targets_id := 0                       # instance id стенда, для которого собраны _targets
var _centers: Dictionary = {}              # uid -> центр мешей детали в кадре куклы
var _twins: Dictionary = {}                # uid -> uid пары ("" — нет)
var _push_mark := {"key": "", "t": -10.0, "n": -1}
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _pattern_seed := 0
var _hover_hit: Dictionary = {}
var _tex_avg: Dictionary = {}              # RID текстуры -> средний цвет (пипетка по материалу)

var _ring: Node3D
var _ring_twin: Node3D
var _sel_ring: Node3D
var _preview: MeshInstance3D               # превью наклейки у курсора — меш-наклейка (как будет), полупрозрачная
var _preview_twin: MeshInstance3D
var _fx: GPUParticles3D
var _mist: GPUParticles3D
var _fx_mat: ParticleProcessMaterial
var _mist_mat: ParticleProcessMaterial
var _hover_mat: StandardMaterial3D
var _hiss: AudioStreamPlayer
var _click: AudioStreamPlayer
var _rattle: AudioStreamPlayer
var _hiss_tween: Tween

static var _tri_cache: Dictionary = {}     # instance id меша -> TriangleMesh
static var _face_cum: Dictionary = {}      # instance id меша -> PackedInt32Array: треугольников в поверхностях 0..s (накопленно)


func _ready() -> void:
	_rng.seed = 20260930
	_pattern_seed = int(Time.get_ticks_usec() % 100000)
	_make_visuals()
	_make_audio()
	var w := get_window()
	if w != null and not w.files_dropped.is_connected(_on_files_dropped):
		w.files_dropped.connect(_on_files_dropped)


# =================================================================== состояние

## Взять инструмент t (TOOLS; "" — положить). Кладёт «руку мышью», кисть материала, шарнир и протяжку; вид — ТЕЛО.
func set_tool(t: String) -> void:
	if t != "" and not TOOLS.has(t):
		t = ""
	if t == tool:
		return
	_finish_all()
	if t == "pick" and tool != "pick":
		_tool_before_pick = tool
	tool = t
	_pan_acc = 0.0
	_mag_acc = 0.0
	if tool != "":
		ws.control_pick = false
		ws.paint_mat = ""
		ws.joint_pick = ""
		ws.cancel_drag()
		ws.set_view(WorkshopBuild.View.BODY)
		if tool == "spray":
			_play(_rattle)
		if tool in ["sticker", "face"] and image == "":
			var ids := KitImages.list_images()
			if not ids.is_empty():
				image = ids[0]
	_hover_hit = {}
	_update_cursor()
	ws.set_hover({})
	ws._apply_highlights()
	changed.emit()
	ws.changed.emit()


## Цвет краски; компоненты зажаты в 0..1 (ColorPicker с ползунком яркости даёт > 1 — байт слоя переполнился бы).
func set_color(c: Color, remember := true) -> void:
	color = PaintLayer._clamp01(c)
	if remember:
		remember_color(color)
	changed.emit()


func set_color2(c: Color) -> void:
	color2 = PaintLayer._clamp01(c)
	changed.emit()


func swap_colors() -> void:
	var c := color
	color = color2
	color2 = c
	changed.emit()


## В «последние» (свежий — первым, без повторов, не больше RECENT_MAX).
func remember_color(c: Color) -> void:
	for i in range(recent.size() - 1, -1, -1):
		if (recent[i] as Color).is_equal_approx(c):
			recent.remove_at(i)
	recent.insert(0, Color(c.r, c.g, c.b, 1.0))
	while recent.size() > RECENT_MAX:
		recent.pop_back()
	changed.emit()


func set_size_cm(v: float) -> void:
	size_cm = clampf(v, SIZE_CM.x, SIZE_CM.y)
	changed.emit()


func set_pressure(v: float) -> void:
	pressure = clampf(v, 0.05, 1.0)
	changed.emit()


func set_hardness(v: float) -> void:
	hardness = clampf(v, 0.0, 1.0)
	changed.emit()


## Размер следующей наклейки / трафарета (большая сторона, см; слайдер полки).
func set_sticker_cm(v: float) -> void:
	sticker_cm = clampf(v, STICKER_CM.x, STICKER_CM.y)
	changed.emit()


func set_pattern_kind(k: String) -> void:
	if PATTERNS.has(k):
		pattern_kind = k
	if tool != "pattern":
		set_tool("pattern")
	changed.emit()


func set_own_colors(on: bool) -> void:
	own_colors = on
	changed.emit()


func set_stencil(nm: String) -> void:
	stencil = nm
	if tool != "stencil":
		set_tool("stencil")
	changed.emit()


func set_image(id: String) -> void:
	image = id
	if tool == "face":
		set_face_image(id)
	elif tool != "sticker":
		set_tool("sticker")
	changed.emit()


func set_symmetry(on: bool) -> void:
	symmetry = on
	ws._say(tr("Симметрия: вкл — краска и наклейки на обе стороны") if on else tr("Симметрия: выкл"), WorkshopBuild.COL_INFO)
	changed.emit()


## Радиус кисти, м (как на слайдере; на детали — не меньше BRUSH_CELL_MIN ячейки её слоя, eff_radius).
func radius() -> float:
	return size_cm * 0.005


## Радиус кисти на детали uid (м, в мире): радиус слайдера, но не меньше BRUSH_CELL_MIN ячейки слоя детали.
func eff_radius(uid: String) -> float:
	return maxf(radius(), cell_world(uid) * BRUSH_CELL_MIN)


## Ребро ячейки слоя краски детали uid в мире (м); слоя ещё нет — какое будет (PaintLayer.cell_for_aabb). 0 — нет детали.
func cell_world(uid: String) -> float:
	if _cells.has(uid):
		return _cells[uid]
	if ws.stand == null or uid == "":
		return 0.0
	var h := ws.stand.paint_handle(uid)
	var root: Node3D = h["mesh_root"] if not h.is_empty() else BodyPaint.mesh_root_of(ws.stand, uid)
	if root == null:
		return 0.0
	var cell := (h["layer"] as PaintLayer).cell_size() if not h.is_empty() else PaintLayer.cell_for_aabb(BodyPaint.mesh_aabb(root))
	var c := cell * _avg_scale(root.global_basis)
	_cells[uid] = c
	return c


func busy() -> bool:
	return not _stroke.is_empty() or not _sdrag.is_empty() or not _pattern_queue.is_empty() or not _pattern_job.is_empty()


## id картинки для следующей наклейки текущего инструмента ("" — не выбрана).
func current_img() -> String:
	if tool == "stencil":
		return KitImages.STENCIL_PREFIX + stencil
	if tool in ["sticker", "face"]:
		return image
	return ""


func set_mouse(p: Vector2) -> void:
	_mouse = p


# =================================================================== стенд

## Стенд пересобран (правка, отмена, шаблон): кэши лучей и пар — заново, штрих / перетаскивание / очередь раскраски — сброшены,
## поворот стенда — на новую куклу.
func on_stand_rebuilt() -> void:
	_hover_hit = {}
	_targets.clear()
	_targets_id = 0
	_centers.clear()
	_twins.clear()
	_cells.clear()
	_stroke = {}
	_sdrag = {}
	_pattern_queue.clear()
	_pattern_job = {}
	_sound_stop()
	_fx_emit(false)
	_capture_turn_rest()   # новая кукла (и оружие в кисти) собраны прямо — это кадры 0°
	_apply_turn()


## Повернуть стенд на step × 90° (плавно). Кукла и стойка крутятся вокруг оси стойки.
func turn_stand(step: int) -> void:
	if step == 0:
		return
	stand_turn = posmod(stand_turn + step, 4)
	var target := _turn_angle + step * PI * 0.5
	if _turn_tween != null:
		_turn_tween.kill()
		target = snappedf(_turn_angle, PI * 0.5) + step * PI * 0.5
	_turn_tween = create_tween()
	_turn_tween.tween_method(_set_turn_angle, _turn_angle, target, TURN_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_turn_tween.tween_callback(_turn_done.bind(target))
	changed.emit()
	ws.changed.emit()


func _set_turn_angle(a: float) -> void:
	_turn_angle = a
	_apply_turn()


func _turn_done(target: float) -> void:
	_turn_angle = wrapf(target, -PI, PI)
	_apply_turn()
	_twins.clear()
	_centers.clear()


## Стенд прямо (0°), сразу.
func reset_turn() -> void:
	if _turn_tween != null:
		_turn_tween.kill()
		_turn_tween = null
	stand_turn = 0
	_turn_angle = 0.0
	_apply_turn()
	_centers.clear()
	_twins.clear()


func turn_degrees() -> int:
	return stand_turn * 90


## Кадры 0° тел куклы стенда и оружия в кисти (и их корней) — сразу после сборки стенда.
func _capture_turn_rest() -> void:
	_turn_rest.clear()
	var nodes: Array = []
	if ws.stand != null and is_instance_valid(ws.stand):
		nodes.append(ws.stand)
		nodes.append_array(ws.stand.parts.values())
	if ws.held_weapon != null and is_instance_valid(ws.held_weapon):
		nodes.append(ws.held_weapon)
		nodes.append_array(ws.held_weapon.bodies())
	for n in nodes:
		_turn_rest.append([n, (n as Node3D).global_transform])


## Стойка и кукла — на угол _turn_angle вокруг оси стойки. Тела RigidBody3D за корнем куклы не едут (у физтела свой глобальный
## кадр), поэтому каждое тело (и тела оружия в кисти) ставится явно: поворот × кадр 0° (без накопления ошибки кадр за кадром);
## корень куклы — тоже (кадр куклы для симметрии). Замки осей 2.5D у тел стенда сняты (WorkshopBuild._unlock_axes).
func _apply_turn() -> void:
	if ws == null:
		return
	if ws.stand_root != null:
		ws.stand_root.rotation.y = _turn_angle
	var pivot := ws.stand_root.global_position if ws.stand_root != null else Vector3.ZERO
	var xf := Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis(Vector3.UP, _turn_angle), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -pivot)
	for e in _turn_rest:
		var n: Variant = e[0]
		if is_instance_valid(n):
			(n as Node3D).global_transform = xf * (e[1] as Transform3D)


# =================================================================== попадание

## [начало, направление] луча камеры через экранную точку; [] — камеры нет.
func _cam_ray(p: Vector2) -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return []
	return [cam.project_ray_origin(p), cam.project_ray_normal(p)]


## Поверхность куклы под экранной точкой: {uid ("" — заслоняет не красимое), root, point, normal, mi, face, dist} или {}.
func surface_hit(p: Vector2) -> Dictionary:
	var r := _cam_ray(p)
	return ray_hit(r[0], r[1]) if not r.is_empty() else {}


## Ближайшее попадание луча по мешам стенда (only_uid — только меши этой детали).
func ray_hit(from: Vector3, dir: Vector3, only_uid := "") -> Dictionary:
	_ensure_targets()
	var best: Dictionary = {}
	var best_d := RAY_LEN
	for t in _targets:
		if only_uid != "" and String(t["uid"]) != only_uid:
			continue   # фильтр детали — первым: дешевле, чем проверка узла (smoothed_hit — 6 лучей на кадр)
		var mv: Variant = t["mi"]
		if not is_instance_valid(mv):
			continue
		var mi := mv as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		if absf(xf.basis.determinant()) < 1e-12:
			continue
		var inv := xf.affine_inverse()
		var lf := inv * from
		var ld := inv.basis * dir
		if mi.get_aabb().grow(0.002).intersects_ray(lf, ld) == null:
			continue
		var tm := _tri(mi.mesh)
		if tm == null:
			continue
		var r := tm.intersect_ray(lf, ld)
		if r.is_empty():
			continue
		var p: Vector3 = xf * (r["position"] as Vector3)
		var d := (p - from).dot(dir)
		if d <= 0.0 or d >= best_d:
			continue
		var nrm := (xf.basis.inverse().transposed() * (r["normal"] as Vector3)).normalized()
		if nrm.dot(dir) > 0.0:
			nrm = -nrm
		best_d = d
		best = {"uid": String(t["uid"]), "root": t["root"], "point": p, "normal": nrm, "mi": mi, "face": int(r.get("face_index", -1)),
			"dist": d}
	return best


## Копия попадания с нормалью «площадки» вокруг точки: среднее нормалей 6 лучей по кольцу радиуса spread (поперёк луча, только
## меши той же детали). Треугольная нормаль в канавке между досками бочки, на заклёпке или ребре смотрит вбок — наклейка по ней
## легла бы ребром (тонкая полоска), кольцо кисти вставало бы на дыбы. patch — точка площадки: попадание, сдвинутое вдоль нормали
## на среднюю глубину точек кольца (центр коробки наклейки: клик по выступу — ободку окошка ядра, заклёпке — иначе оставил бы доски
## за выступом вне коробки глубиной BodyPaint.STICKER_DEPTH, наклейка легла бы полоской на выступ).
func smoothed_hit(hit: Dictionary, dir: Vector3, spread: float) -> Dictionary:
	if not _paint_hit(hit) or spread <= 0.0:
		return hit
	var p: Vector3 = hit["point"]
	var a := dir.cross(Vector3.UP)
	if a.length() < 0.1:
		a = dir.cross(Vector3.RIGHT)
	a = a.normalized()
	var b := dir.cross(a).normalized()
	var acc: Vector3 = hit["normal"]
	var pts: Array = [p]
	for k in 6:
		var ang := TAU * float(k) / 6.0
		var o := p + (a * cos(ang) + b * sin(ang)) * spread
		var h := ray_hit(o - dir * (spread * 3.0 + 0.05), dir, String(hit["uid"]))
		if not h.is_empty() and absf(((h["point"] as Vector3) - o).dot(dir)) < spread * 2.5:
			acc += h["normal"] as Vector3
			pts.append(h["point"])
	var out := hit.duplicate()
	var n: Vector3 = acc.normalized() if acc.length() > 1e-4 else hit["normal"]
	out["normal"] = n
	var depth := 0.0
	for q in pts:
		depth += ((q as Vector3) - p).dot(n)
	out["patch"] = p + n * (depth / float(pts.size()))
	return out


## Центр наклейки для попадания: точка площадки (smoothed_hit), иначе само попадание.
static func decal_point(hit: Dictionary) -> Vector3:
	return hit.get("patch", hit["point"])


## Попадание по красимой детали (uid не пустой) или {}.
func _paint_hit(hit: Dictionary) -> bool:
	return not hit.is_empty() and String(hit.get("uid", "")) != "" and is_instance_valid(hit.get("mi"))


static func _tri(mesh: Mesh) -> TriangleMesh:
	if mesh == null:
		return null
	var key := mesh.get_instance_id()
	if not _tri_cache.has(key):
		_tri_cache[key] = mesh.generate_triangle_mesh()
	return _tri_cache[key]


func _ensure_targets() -> void:
	var st := ws.stand if ws != null else null
	var sid := st.get_instance_id() if st != null and is_instance_valid(st) else 0
	if sid == _targets_id and (sid == 0 or not _targets.is_empty()):
		return
	_targets.clear()
	_centers.clear()
	_twins.clear()
	_targets_id = sid
	if sid == 0:
		return
	var own := {}
	for n in ws.blueprint.nodes:
		var uid := String(n.get("uid", ""))
		if not st.uid_body.has(uid):
			continue
		var root := BodyPaint.mesh_root_of(st, uid)
		if root == null:
			continue
		for mi in BodyPaint.meshes(root):
			own[mi] = [uid, root]
	var all: Array = []
	_all_meshes(st, all)
	if ws.held_weapon != null and is_instance_valid(ws.held_weapon):
		_all_meshes(ws.held_weapon, all)
	for mi in all:
		var e: Array = own.get(mi, ["", null])
		_targets.append({"mi": mi, "uid": e[0], "root": e[1]})


## MeshInstance3D под n, кроме наклеек (они на 1 мм над деталью: заслонили бы её от кисти).
static func _all_meshes(n: Node, out: Array) -> void:
	if n.has_meta(BodyPaint.STICKER_META):
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_all_meshes(c, out)


## Центры мешей деталей в кадре куклы (для пар и «пуфа»).
func _ensure_centers() -> void:
	_ensure_targets()
	if not _centers.is_empty() or ws.stand == null:
		return
	var inv := ws.stand.global_transform.affine_inverse()
	for n in ws.blueprint.nodes:
		var uid := String(n.get("uid", ""))
		var root := BodyPaint.mesh_root_of(ws.stand, uid) if ws.stand.uid_body.has(uid) else null
		if root == null or BodyPaint.meshes(root).is_empty():
			continue
		_centers[uid] = inv * WorkshopBuild._visual_aabb(root).get_center()


## Мировой центр мешей детали uid (Vector3.INF — нет).
func part_center(uid: String) -> Vector3:
	_ensure_centers()
	if not _centers.has(uid) or ws.stand == null:
		return Vector3.INF
	return ws.stand.global_transform * (_centers[uid] as Vector3)


## Парная деталь (зеркальная в кадре куклы) или "" — нет / деталь на оси симметрии.
func twin_uid(uid: String) -> String:
	_ensure_centers()
	if _twins.has(uid):
		return _twins[uid]
	var out := ""
	if _centers.has(uid):
		var c: Vector3 = _centers[uid]
		if absf(c.x) > SYM_EPS:
			var m := Vector3(-c.x, c.y, c.z)
			var best := TWIN_TOL
			for u in _centers:
				if String(u) == uid:
					continue
				var dd := (_centers[u] as Vector3).distance_to(m)
				if dd < best:
					best = dd
					out = String(u)
	_twins[uid] = out
	return out


## [uid] и, при симметрии, его пара.
func with_twin(uid: String) -> Array:
	var out: Array = [uid]
	if symmetry:
		var t := twin_uid(uid)
		if t != "" and t != uid:
			out.append(t)
	return out


func _to_doll(p: Vector3) -> Vector3:
	return ws.stand.global_transform.affine_inverse() * p


func _mirror_point(p: Vector3) -> Vector3:
	var l := _to_doll(p)
	l.x = -l.x
	return ws.stand.global_transform * l


func _mirror_vec(v: Vector3) -> Vector3:
	var b := ws.stand.global_transform.basis
	var l := b.inverse() * v
	l.x = -l.x
	return b * l


## Зеркальный луч в кадре куклы: [начало, направление].
func _mirror_ray(from: Vector3, dir: Vector3) -> Array:
	return [_mirror_point(from), _mirror_vec(dir).normalized()]


## Экранная точка, где луч попадает в деталь uid (центр детали, дальше — спираль), Vector2(-1, -1) — не нашлась. Проба и кадры.
func screen_point_on(uid: String) -> Vector2:
	var c := part_center(uid)
	var cam := get_viewport().get_camera_3d()
	if c == Vector3.INF or cam == null:
		return Vector2(-1, -1)
	var p0 := cam.unproject_position(c)
	for ring in range(0, 16):
		var n := maxi(1, ring * 6)
		for k in n:
			var a := TAU * float(k) / float(n)
			var p := p0 + Vector2(cos(a), sin(a)) * ring * 5.0
			if String(surface_hit(p).get("uid", "")) == uid:
				return p
	return Vector2(-1, -1)


# =================================================================== ввод (WorkshopBuild._unhandled_input → сюда первым)

## true — событие съедено покраской.
func handle_input(ev: InputEvent) -> bool:
	if tool == "" or ws.mode != WorkshopBuild.Mode.BUILD:
		return false
	if ev is InputEventMouseMotion:
		_mouse = (ev as InputEventMouseMotion).position
		if not _sdrag.is_empty():
			sticker_drag_move(_mouse)
		return false
	# трекпад / Magic Mouse на macOS шлют прокрутку жестом (не колесом): прокрутка и щипок — как колесо (размер кисти / наклейки)
	if ev is InputEventPanGesture:
		if not tool in ["spray", "erase", "stencil", "sticker"]:
			return false
		var pg := ev as InputEventPanGesture
		_pan_acc -= pg.delta.y   # delta.y > 0 — прокрутка вниз = колесо вниз
		while absf(_pan_acc) >= PAN_STEP:
			var sd := 1 if _pan_acc > 0.0 else -1
			_wheel(sd, pg.position)
			_pan_acc -= sd * PAN_STEP
		return true
	if ev is InputEventMagnifyGesture:
		if not tool in ["spray", "erase", "stencil", "sticker"]:
			return false
		var mg := ev as InputEventMagnifyGesture
		_mag_acc += log(maxf(mg.factor, 1e-3))
		var ls := log(SCALE_STEP)
		while absf(_mag_acc) >= ls:
			var md := 1 if _mag_acc > 0.0 else -1
			_wheel(md, mg.position)
			_mag_acc -= md * ls
		return true
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		_mouse = mb.position
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press(mb.position, mb.shift_pressed, mb.alt_pressed)
				else:
					_release()
				return true
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and tool in ["stencil", "sticker"] and _sdrag.is_empty():
					var s := sticker_at(mb.position)
					if not s.is_empty():
						remove_sticker(s)
						return true
				return false
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_wheel(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1, mb.position)
				return true
		return false
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if k.physical_keycode == KEY_SHIFT and tool == "pattern":
			ws._apply_highlights()   # Shift — подсветить всю куклу
			return false
		if not k.pressed or k.echo:
			return false
		match k.physical_keycode:
			KEY_Q, KEY_E:
				if tool in ["stencil", "sticker"]:
					var deg := ROT_STEP_DEG if k.physical_keycode == KEY_Q else -ROT_STEP_DEG
					var s2 := sticker_at(_mouse)
					if not s2.is_empty():
						rotate_sticker(s2, deg)
					else:
						sticker_rot = wrapf(sticker_rot + deg, -180.0, 180.0)
						changed.emit()
					return true
			KEY_DELETE, KEY_BACKSPACE:
				if tool in ["stencil", "sticker"]:
					var s3 := sticker_at(_mouse)
					if not s3.is_empty():
						remove_sticker(s3)
					return true
			KEY_R:
				turn_stand(-1 if k.shift_pressed else 1)
				return true
			KEY_X:
				swap_colors()
				return true
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				_wheel(1 if k.physical_keycode == KEY_BRACKETRIGHT else -1, _mouse)
				return true
	return false


func _press(p: Vector2, shift: bool, alt: bool) -> void:
	if tool != "pattern" and (not _pattern_queue.is_empty() or not _pattern_job.is_empty()):
		_finish_patterns()   # раскраска ещё рисуется — дорисовать, прежде чем класть поверх
	match tool:
		"spray", "erase":
			if alt:
				pick_color_at(p)
			else:
				stroke_begin(p, true)
		"fill":
			var h := surface_hit(p)
			if _paint_hit(h):
				fill_part(String(h["uid"]))
			else:
				ws._say(tr("Заливка: кликни по детали куклы"), WorkshopBuild.COL_WARN)
		"pattern":
			var h2 := surface_hit(p)
			if _paint_hit(h2):
				apply_pattern(String(h2["uid"]), shift)
			else:
				ws._say(tr("Раскраска: кликни по детали (Shift+клик — вся кукла)"), WorkshopBuild.COL_WARN)
		"pick":
			pick_color_at(p)
		"stencil", "sticker":
			var s := sticker_at(p)
			if not s.is_empty():
				sticker_drag_begin(s, p)
			else:
				place_sticker(p)
		"face":
			var hf := surface_hit(p)
			if image == "":
				ws._say(tr("Выбери картинку на полке или нажми «Импорт…»"), WorkshopBuild.COL_WARN)
			elif _paint_hit(hf) and String(hf["uid"]) == head_uid():
				set_face_image(image)
			else:
				ws._say(tr("Фото: кликни по голове (или по картинке на полке — встанет сразу)"), WorkshopBuild.COL_WARN)


func _release() -> void:
	if not _stroke.is_empty():
		stroke_end()
	if not _sdrag.is_empty():
		sticker_drag_end()


func _wheel(dir: int, p: Vector2) -> void:
	if tool in ["stencil", "sticker"]:
		var s := sticker_at(p)
		if not s.is_empty():
			scale_sticker(s, SCALE_STEP if dir > 0 else 1.0 / SCALE_STEP)
		else:
			sticker_cm = clampf(sticker_cm * (SCALE_STEP if dir > 0 else 1.0 / SCALE_STEP), STICKER_CM.x, STICKER_CM.y)
			changed.emit()
	else:
		set_size_cm(size_cm + 0.5 * dir)


## Деталь под курсором для подсветки WorkshopBuild (заливка, раскраска, фото): {target, uid} или {}.
func hover_pick(p: Vector2) -> Dictionary:
	_mouse = p
	if not tool in HOVER_TOOLS:
		return {}
	var h := surface_hit(p)
	if not _paint_hit(h):
		return {}
	if tool == "face" and String(h["uid"]) != head_uid():
		return {}
	return {"target": "body", "uid": String(h["uid"])}


## Подсветка для WorkshopBuild._apply_highlights: [uid] и материал (заливка — цвет краски, раскраска — вся кукла с Shift).
func hover_uids(uid: String) -> Array:
	if tool == "pattern" and Input.is_key_pressed(KEY_SHIFT):
		_ensure_centers()
		return _centers.keys()
	return with_twin(uid) if tool in ["fill", "pattern"] else [uid]


func hover_material() -> Material:
	if tool == "fill":
		_hover_mat.albedo_color = Color(color.r, color.g, color.b, 0.55 * pressure + 0.1)
		return _hover_mat
	return null


# =================================================================== баллончик и ластик

## Начать штрих в экранной точке p (spray / erase). mouse — штрих мыши: кончается сам, когда ЛКМ отпущена.
func stroke_begin(p: Vector2, mouse := false) -> bool:
	if not tool in ["spray", "erase"] or ws.stand == null:
		return false
	if not _stroke.is_empty():
		stroke_end()
	_mouse = p
	_stroke = {"touched": {}, "dirty": {}, "before": {}, "last": p, "mouse": mouse, "erase": tool == "erase", "hit": {},
		"prev": [{}, {}]}
	_fx_colour()
	_sound_start()
	_dab_path(p, p)
	_flush()
	return true


func stroke_move(p: Vector2) -> void:
	_mouse = p


## Отпустить: одна запись истории, node.paint узлов, чей слой штрих изменил. Изменённые uid (пусто — штрих ничего не сделал:
## ни записи истории, ни «*» у названия).
func stroke_end() -> PackedStringArray:
	if _stroke.is_empty():
		return PackedStringArray()
	_flush()
	var touched: Dictionary = _stroke["touched"]
	var before: Dictionary = _stroke["before"]
	var erase := bool(_stroke["erase"])
	_stroke = {}
	_sound_stop()
	_fx_emit(false)
	var out := PackedStringArray()
	for uid in touched:
		var h := ws.stand.paint_handle(String(uid)) if ws.stand != null else {}
		if not h.is_empty() and (h["layer"] as PaintLayer).data != before.get(uid, PackedByteArray()):
			out.append(String(uid))
	if out.is_empty():
		return out
	_commit_paint(Array(out))
	if not erase:
		remember_color(color)
	return out


func _physics_process(_delta: float) -> void:
	if not _stroke.is_empty():
		if bool(_stroke["mouse"]) and hold_check and not virtual_mouse and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			stroke_end()
		else:
			if not virtual_mouse and bool(_stroke["mouse"]):
				_mouse = get_viewport().get_mouse_position()
			_dab_path(_stroke["last"], _mouse)
			_stroke["last"] = _mouse
			_flush()
	if not _sdrag.is_empty() and hold_check and not virtual_mouse and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		sticker_drag_end()   # отпустили над панелью — отпускание до 3D не дошло
	if not _pattern_queue.is_empty() or not _pattern_job.is_empty():
		_pattern_step()


## Путь курсора от экранной точки a до b: лучи через STEP_PX (≤ RAY_BUDGET; при симметрии — и зеркальный на каждый), мазки — по
## дорожкам попаданий (_track_dabs): основной и зеркальной.
func _dab_path(a: Vector2, b: Vector2) -> void:
	var dist := a.distance_to(b)
	var nr := clampi(ceili(dist / STEP_PX), 1, RAY_BUDGET)
	var mirror_on := symmetry and ws.stand != null
	var hits: Array = []
	for i in nr:
		var p := b if nr == 1 else a.lerp(b, float(i + 1) / float(nr))
		var r := _cam_ray(p)
		if r.is_empty():
			return
		var h := ray_hit(r[0], r[1])
		var mh: Dictionary = {}
		if mirror_on and (h.is_empty() or absf(_to_doll(h["point"]).x) > SYM_EPS):
			var mr := _mirror_ray(r[0], r[1])
			mh = ray_hit(mr[0], mr[1])
		hits.append([h, mh])
	var step_px := dist / float(nr)
	var last := _track_dabs(hits, 0, step_px)
	if mirror_on:
		_track_dabs(hits, 1, step_px)
	_stroke["hit"] = last
	if last.is_empty():
		_fx_emit(false)
	else:
		_fx_at(last)


## Мазки дорожки k (0 — основная, 1 — зеркальная) по попаданиям лучей: соседние попадания в одну деталь, близкие по поверхности
## (не скачок через край детали), соединяются мазками с шагом _dab_spacing — «мазок на шаг» делится между ними (туман 1 − (1 −
## SPRAY_MIST_STEP)^доля, точки — доля SPRAY_DOTS_STEP); первое попадание (и кадр без движения) — целый мазок. Мазков не больше
## бюджета (DAB_BUDGET, DAB_CELLS — для большой кисти), точек — DOT_BUDGET: быстрее — шаг растёт. Последнее попадание дорожки.
func _track_dabs(hits: Array, k: int, step_px: float) -> Dictionary:
	var prev: Dictionary = (_stroke["prev"] as Array)[k]
	var plan: Array = []   # [uid, мировая точка, доля мазка]
	var last: Dictionary = {}
	for e in hits:
		var h: Dictionary = e[k]
		if not _paint_hit(h):
			prev = {}
			continue
		var uid := String(h["uid"])
		var p1: Vector3 = h["point"]
		var sp := _dab_spacing(uid)
		if not prev.is_empty() and String(prev["uid"]) == uid and is_instance_valid(prev.get("mi")):
			var p0: Vector3 = prev["point"]
			var d := p0.distance_to(p1)
			if d <= 4.0 * step_px / _ppm(p1) + 2.0 * sp:
				var n := maxi(ceili(d / sp), 1)
				for j in n:
					plan.append([uid, p0.lerp(p1, float(j + 1) / float(n)), 1.0 / float(n), h])
				prev = h
				last = h
				continue
		plan.append([uid, p1, 1.0, h])
		prev = h
		last = h
	(_stroke["prev"] as Array)[k] = prev
	if plan.is_empty():
		return last
	# бюджет: большая кисть — меньше мазков (туман мазка — ≈ 4.19 (r / ячейка)³ ячеек), точек — не больше DOT_BUDGET
	var cap := DAB_BUDGET
	var u0 := String(plan[0][0])
	var cw := maxf(cell_world(u0), 1e-4)
	var core := eff_radius(u0) * PaintLayer.SPRAY_CORE / cw
	cap = clampi(int(DAB_CELLS / maxf(4.19 * core * core * core, 1.0)), 6, DAB_BUDGET)
	var keep := plan
	if plan.size() > cap:
		keep = []
		var acc := 0.0
		var per := float(plan.size()) / float(cap)
		for i in cap:
			var i0 := int(i * per)
			var i1 := int((i + 1) * per)
			acc = 0.0
			for q in range(i0, i1):
				acc += float(plan[q][2])
			var e2: Array = plan[mini(i1 - 1, plan.size() - 1)]
			keep.append([e2[0], e2[1], acc, e2[3]])
	var dots_total := 0.0
	for e in keep:
		dots_total += SPRAY_DOTS_STEP * float(e[2])
	var dot_k := minf(1.0, float(DOT_BUDGET) / maxf(dots_total, 1.0))
	for e in keep:
		_dab(String(e[0]), e[1], float(e[2]), maxi(roundi(SPRAY_DOTS_STEP * float(e[2]) * dot_k), 2))
	return last


## Шаг мазков по поверхности детали uid (м, в мире).
func _dab_spacing(uid: String) -> float:
	return maxf(eff_radius(uid) * DAB_SPACING, DAB_SPACING_MIN)


## Пикселей экрана на метр в точке p (кольцо кисти, шаг штриха).
func _ppm(p: Vector3) -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 400.0
	var dist := maxf(cam.global_position.distance_to(p), 0.05)
	return get_viewport().get_visible_rect().size.y / (2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5))


## Мазок в мировой точке p детали uid: frac — доля «мазка на шаг» (туман, ластик), dots — точек напыления. Радиус — не меньше
## BRUSH_CELL_MIN ячейки слоя (кисть 1 см на ячейке 14 мм иначе не задевала бы центров: мазок ничего не красил). false — не красится.
func _dab(uid: String, p: Vector3, frac: float, dots: int) -> bool:
	if ws.stand == null:
		return false
	var erase := bool(_stroke.get("erase", false))
	var h: Dictionary = ws.stand.paint_handle(uid) if erase else ws.stand.ensure_paint(uid)
	if h.is_empty():
		return false
	var layer: PaintLayer = h["layer"]
	var root: Node3D = h["mesh_root"]
	var gx := root.global_transform
	var lp := gx.affine_inverse() * p
	var r := maxf(radius() / _avg_scale(gx.basis), layer.cell_size() * BRUSH_CELL_MIN)
	var before: Dictionary = _stroke["before"]
	if not before.has(uid):
		before[uid] = layer.data.duplicate()   # штрих, который ничего не поменял, не записывается (stroke_end)
	var f := clampf(frac, 0.0, 1.0)
	if erase:
		var w := clampf(pressure, 0.1, 1.0) * ERASE_FLOW
		layer.erase(lp, r, 1.0 - pow(1.0 - w, f))
	else:
		layer.spray(lp, r, color, pressure, hardness, _rng, dots, 1.0 - pow(1.0 - SPRAY_MIST_STEP, f))
	(_stroke["touched"] as Dictionary)[uid] = true
	(_stroke["dirty"] as Dictionary)[uid] = h
	return true


func _flush() -> void:
	if _stroke.is_empty():
		return
	var dirty: Dictionary = _stroke["dirty"]
	for uid in dirty:
		var h: Dictionary = dirty[uid]
		(h["layer"] as PaintLayer).update_texture(h["tex"])
	dirty.clear()


static func _avg_scale(b: Basis) -> float:
	return maxf((b.x.length() + b.y.length() + b.z.length()) / 3.0, 1e-4)


## Одна запись истории, node.paint узлов uids из живых слоёв стенда.
func _commit_paint(uids: Array) -> void:
	_push()
	for uid in uids:
		_write_paint(String(uid))
	focus_uid = String(uids[0])
	ws._name_custom_body()
	changed.emit()
	ws.changed.emit()


## node.paint = слой живой ручки (пустой слой / нет ручки — ключ стирается).
func _write_paint(uid: String) -> void:
	var n := CraftEdit.find(ws.blueprint, uid)
	if n.is_empty() or ws.stand == null:
		return
	var h := ws.stand.paint_handle(uid)
	if h.is_empty() or (h["layer"] as PaintLayer).is_empty():
		n.erase("paint")
	else:
		n["paint"] = (h["layer"] as PaintLayer).to_dict()


## Запись в историю ws; key — серия (колесо / Q / E по одной наклейке): повтор той же серии в COALESCE_S — без новой записи (но
## автосейв правок отодвигается — WorkshopBuild.mark_dirty).
func _push(key := "") -> void:
	if key != "" and key == String(_push_mark["key"]) and _time - float(_push_mark["t"]) < COALESCE_S \
			and ws.history.size() == int(_push_mark["n"]):
		_push_mark["t"] = _time
		ws.mark_dirty()
		return
	ws._push_history()
	_push_mark = {"key": key, "t": _time, "n": ws.history.size()}


# =================================================================== заливка, раскраски, пипетка

## Вся деталь (и пара при симметрии) — в цвет краски, сила = нажим. false — не красится.
func fill_part(uid: String) -> bool:
	if ws.stand == null:
		return false
	var done: Array = []
	for u in with_twin(uid):
		var h := ws.stand.ensure_paint(String(u))
		if h.is_empty():
			continue
		(h["layer"] as PaintLayer).fill(color, pressure)
		(h["layer"] as PaintLayer).update_texture(h["tex"])
		done.append(u)
		_puff(String(u), color)
	if done.is_empty():
		ws._say(tr("Эта деталь не красится"), WorkshopBuild.COL_WARN)
		return false
	_commit_paint(done)
	remember_color(color)
	ws._say(tr("Заливка: %s") % _with_pair(ws.uid_title("body", uid), done.size() > 1), _toast_col(color))
	return true


## Раскраска kind (по умолчанию — pattern_kind): деталь uid и её пара (один seed — зеркально) или вся кукла (whole: волной от ядра).
## Краска детали заменяется. Рисуется очередью по PATTERN_BUDGET_US за физкадр (_pattern_step): деталь — в черновик, в живой слой —
## целиком, сразу node.paint. У правой детали старой куклы (корень меша не зеркальный, в отличие от кита) рисунок отражается
## (mirror_x) — пара выходит зеркальной. Число деталей в очереди.
func apply_pattern(uid: String, whole := false, kind := "") -> int:
	if ws.stand == null:
		return 0
	if kind == "":
		kind = pattern_kind
	if not PATTERNS.has(kind):
		return 0
	_pattern_seed += 1
	var cols: Array = [color, color2] if own_colors else []
	var list: Array = []
	if whole:
		_ensure_centers()
		list = _centers.keys()
		var core := _centers.get(CraftEdit.root_uid(ws.blueprint), Vector3.ZERO) as Vector3
		list.sort_custom(func(a: String, b: String) -> bool:
			return (_centers[a] as Vector3).distance_to(core) < (_centers[b] as Vector3).distance_to(core))
	else:
		list = with_twin(uid)
	if list.is_empty():
		return 0
	_push()
	_pattern_queue.clear()
	_pattern_job = {}   # недорисованная деталь прежней раскраски остаётся как была (черновик не лёг)
	for u in list:
		var t := twin_uid(String(u)) if (symmetry or whole) else ""
		var pair := String(u) if t == "" or String(u) < t else t
		var s := _pattern_seed * 7919 + pair.unicode_at(0) * 131
		var mirror := t != "" and String(u) != pair and _same_handed(String(u), t)
		_pattern_queue.append([String(u), kind, cols, s, mirror])
	_pattern_total = list.size()
	_pattern_kind_now = kind
	if whole:
		ws._say(tr("%s — вся кукла…") % _pattern_title(kind), _toast_col(color if own_colors else Color(1.0, 0.8, 0.45)))
	focus_uid = uid if uid != "" else String(list[0])
	return list.size()


## Корни меша деталей a и b в кадрах своих тел одной ориентации (det одного знака): пара старой куклы (Mesh_R не зеркальный) —
## да, пара кита (корень правой — зеркальный) — нет.
func _same_handed(a: String, b: String) -> bool:
	var ra := BodyPaint.mesh_root_of(ws.stand, a)
	var rb := BodyPaint.mesh_root_of(ws.stand, b)
	if ra == null or rb == null:
		return false
	var da := BodyPaint._rel_xf(ra, BodyPaint.body_of(ws.stand, a)).basis.determinant()
	var db := BodyPaint._rel_xf(rb, BodyPaint.body_of(ws.stand, b)).basis.determinant()
	return (da > 0.0) == (db > 0.0)


## Очередь раскраски — не дольше budget_us мкс (0 — до конца): деталь рисуется в черновик срезами (PaintLayer.pattern_run), готовая —
## в живой слой, текстура, node.paint, «пуф». Очередь кончилась — подсказка, «*» у названия.
func _pattern_step(budget_us := PATTERN_BUDGET_US) -> void:
	var t0 := Time.get_ticks_usec()
	while true:
		if _pattern_job.is_empty():
			if _pattern_queue.is_empty():
				break
			if ws.stand == null:
				_pattern_queue.clear()
				break
			var e: Array = _pattern_queue.pop_front()
			var uid := String(e[0])
			var h := ws.stand.ensure_paint(uid)
			if h.is_empty():
				continue
			var tmp := (h["layer"] as PaintLayer).blank_like()
			_pattern_job = {"uid": uid, "h": h, "tmp": tmp, "job": tmp.pattern_begin(String(e[1]), e[2], int(e[3]), Vector3.UP, bool(e[4])),
				"col": (e[2] as Array)[0] if not (e[2] as Array).is_empty() else Color(1.0, 0.8, 0.5)}
		var left := 0
		if budget_us > 0:
			left = budget_us - int(Time.get_ticks_usec() - t0)
			if left <= 0:
				break
		var tl: PaintLayer = _pattern_job["tmp"]
		if not tl.pattern_run(_pattern_job["job"], left):
			continue
		var hj: Dictionary = _pattern_job["h"]
		var uid2 := String(_pattern_job["uid"])
		var layer: PaintLayer = hj["layer"]
		layer.set_data(tl.data)
		layer.update_texture(hj["tex"])
		_write_paint(uid2)
		_puff(uid2, _pattern_job["col"])
		_pattern_job = {}
	if _pattern_queue.is_empty() and _pattern_job.is_empty() and _pattern_total > 0:
		var kind := _pattern_kind_now
		ws._name_custom_body()
		var what := tr("вся кукла") if _pattern_total > 2 else _with_pair(ws.uid_title("body", focus_uid), _pattern_total == 2)
		ws._say("%s: %s" % [_pattern_title(kind), what], _toast_col(color if own_colors else Color(1.0, 0.8, 0.45)))
		_pattern_total = 0
		changed.emit()
		ws.changed.emit()


## Раскраску в очереди — дорисовать сейчас (другой инструмент кладёт краску поверх, смена инструмента).
func _finish_patterns() -> void:
	while not _pattern_queue.is_empty() or not _pattern_job.is_empty():
		_pattern_step(0)


## Пипетка: цвет краски в точке (если краска плотная), иначе цвет материала поверхности. Пипетка-инструмент возвращает прежний.
func pick_color_at(p: Vector2) -> bool:
	var hit := surface_hit(p)
	if not _paint_hit(hit):
		ws._say(tr("Пипетка: кликни по детали куклы"), WorkshopBuild.COL_WARN)
		return false
	var c := surface_color(hit)
	set_color(c)
	ws._say(tr("Пипетка: цвет взят"), _toast_col(c))
	if tool == "pick" and _tool_before_pick != "" and _tool_before_pick != "pick":
		set_tool(_tool_before_pick)
	return true


## Цвет в точке попадания: краска (альфа ≥ 0.35), иначе материал (MaterialDef.swatch у Base_*, иначе albedo × средний цвет текстуры).
func surface_color(hit: Dictionary) -> Color:
	var uid := String(hit["uid"])
	var h := ws.stand.paint_handle(uid) if ws.stand != null else {}
	if not h.is_empty():
		var root: Node3D = h["mesh_root"]
		var c := (h["layer"] as PaintLayer).sample(root.global_transform.affine_inverse() * (hit["point"] as Vector3))
		if c.a >= 0.35:
			return Color(c.r, c.g, c.b)
	var mi := hit["mi"] as MeshInstance3D
	var s := _surface_of_face(mi.mesh, int(hit.get("face", -1)))
	var m := BodyPaint.surface_material(mi, s)
	if m != null and m.has_meta(BodyPaint.INPASS_META):
		m = m.get_meta(BodyPaint.INPASS_META)   # двойник с краской в том же проходе — цвет исходного материала
	if m == null:
		return color
	if m.resource_name.begins_with("Base_"):
		for id in MaterialDef.all_ids():
			var md := MaterialDef.get_def(id)
			if md != null and md.surface != null and md.surface.resource_name == m.resource_name:
				return md.swatch
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		var c2 := bm.albedo_color
		if bm.albedo_texture != null:
			c2 *= _avg_colour(bm.albedo_texture)
		return Color(c2.r, c2.g, c2.b)
	return color


## Поверхность меша по номеру треугольника TriangleMesh (треугольники идут по поверхностям подряд; счёт — кэш по мешу).
static func _surface_of_face(mesh: Mesh, face: int) -> int:
	if mesh == null or face < 0:
		return 0
	var key := mesh.get_instance_id()
	if not _face_cum.has(key):
		var cum := PackedInt32Array()
		var acc := 0
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX] if arr.size() > Mesh.ARRAY_INDEX else null
			var n := 0
			if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
				n = (idx as PackedInt32Array).size()
			elif arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				n = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			acc += n / 3
			cum.append(acc)
		_face_cum[key] = cum
	var c: PackedInt32Array = _face_cum[key]
	for s in c.size():
		if face < c[s]:
			return s
	return 0


## Попадание в поверхность цвета игрока / фото (Shirt*, Face*): краска там не видна (BODY_PAINT.md: цвет игрока не закрашивается).
func protected_hit(hit: Dictionary) -> bool:
	var v: Variant = hit.get("mi")
	if not is_instance_valid(v):
		return false
	var mi := v as MeshInstance3D
	if mi == null or mi.mesh == null:
		return false
	return BodyPaint.is_protected(BodyPaint.surface_material(mi, _surface_of_face(mi.mesh, int(hit.get("face", -1)))))


func _avg_colour(t: Texture2D) -> Color:
	var key := t.get_rid()
	if _tex_avg.has(key):
		return _tex_avg[key]
	var c := Color.WHITE
	var img := t.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
		c = img.get_pixel(0, 0)
	_tex_avg[key] = c
	return c


# =================================================================== наклейки и трафареты

## Кадр наклейки: Y — нормаль (наружу), «верх» картинки — up (проекция на касательную), Z = −верх, X = Y × Z (правый поворот).
static func sticker_frame(point: Vector3, normal: Vector3, up: Vector3) -> Transform3D:
	var y := normal.normalized()
	var u := up - y * up.dot(y)
	if u.length() < 1e-3:
		u = Vector3.BACK - y * Vector3.BACK.dot(y)
		if u.length() < 1e-3:
			u = Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	var z := -u.normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), point)


## Размер наклейки картинки tex: большая сторона — side (м), пропорции картинки.
static func sticker_size(tex: Texture2D, side: float) -> Vector2:
	if tex == null or tex.get_height() <= 0:
		return Vector2(side, side)
	var a := float(tex.get_width()) / float(tex.get_height())
	return Vector2(side, side / a) if a >= 1.0 else Vector2(side * a, side)


## Поставить наклейку текущего инструмента (или img) в экранную точку p; с симметрией — и зеркальную. Коробка у плоскости симметрии
## задела бы зеркальную копию (_sticker_on_axis) — одна наклейка, ровно на плоскости (_snap_to_axis). {ok, uid, twin_uid}.
func place_sticker(p: Vector2, img := "") -> Dictionary:
	if img == "":
		img = current_img()
	if img == "":
		ws._say(tr("Сначала выбери картинку: «Импорт…» или перетащи файл в окно"), WorkshopBuild.COL_WARN)
		return {"ok": false}
	var tex := KitImages.texture(img)
	if tex == null:
		ws._say(tr("Картинка не читается"), WorkshopBuild.COL_BAD)
		return {"ok": false}
	var r := _cam_ray(p)
	if r.is_empty():
		return {"ok": false}
	var hit := ray_hit(r[0], r[1])
	if not _paint_hit(hit):
		ws._say(tr("Мимо: наклейка ставится на деталь куклы"), WorkshopBuild.COL_WARN)
		return {"ok": false}
	var side := sticker_cm * 0.01
	hit = smoothed_hit(hit, r[1], side * 0.3)
	var single := symmetry and _sticker_on_axis(hit, sticker_size(tex, side))
	if single:
		hit = _snap_to_axis(hit, side)
	var cam := get_viewport().get_camera_3d()
	var up := cam.global_basis.y.rotated((hit["normal"] as Vector3), deg_to_rad(sticker_rot))
	var col := color if img.begins_with(KitImages.STENCIL_PREFIX) else Color.WHITE
	_push()
	var st := _make_sticker(hit, img, tex, up, side, col)
	_add_sticker_live(String(hit["uid"]), st)
	var out := {"ok": true, "uid": String(hit["uid"]), "twin_uid": ""}
	if symmetry and not single:
		var mr := _mirror_ray(r[0], r[1])
		var mh := smoothed_hit(ray_hit(mr[0], mr[1]), mr[1], side * 0.3)
		if _paint_hit(mh):
			_add_sticker_live(String(mh["uid"]), _make_sticker(mh, img, tex, _mirror_vec(up), side, col))
			out["twin_uid"] = String(mh["uid"])
	focus_uid = String(hit["uid"])
	ws._name_custom_body()
	_play(_click, 1.7)
	_puff_at(hit["point"], hit["normal"], col if col != Color.WHITE else Color(1.0, 0.95, 0.8))
	if img.begins_with(KitImages.STENCIL_PREFIX):
		remember_color(color)
	ws._say("%s: %s" % [tr("Трафарет") if img.begins_with(KitImages.STENCIL_PREFIX) else tr("Наклейка"),
		_with_pair(ws.uid_title("body", out["uid"]), String(out["twin_uid"]) != "")], _toast_col(col))
	changed.emit()
	ws.changed.emit()
	return out


## Наклейка размера size в попадании hit — у плоскости симметрии: её коробка (половина большей стороны) задела бы зеркальную копию,
## две вышли бы кашей — ставится одна (и не ближе 2.4 см, как раньше, у совсем маленьких).
func _sticker_on_axis(hit: Dictionary, size: Vector2) -> bool:
	return absf(_to_doll(decal_point(hit)).x) < maxf(SYM_EPS * 2.0, maxf(size.x, size.y) * 0.5)


## Попадание, сдвинутое на плоскость симметрии куклы (x = 0 в её кадре): луч вдоль нормали в ту же деталь; не вышло — как было.
func _snap_to_axis(hit: Dictionary, side: float) -> Dictionary:
	var q := _to_doll(decal_point(hit))
	q.x = 0.0
	var qw := ws.stand.global_transform * q
	var n: Vector3 = hit["normal"]
	var h := ray_hit(qw + n * 0.3, -n, String(hit["uid"]))
	if not _paint_hit(h):
		return hit
	return smoothed_hit(h, -n, side * 0.3)


func _make_sticker(hit: Dictionary, img: String, tex: Texture2D, up: Vector3, side: float, col: Color) -> Dictionary:
	var frame := sticker_frame(decal_point(hit), hit["normal"], up)
	var root: Node3D = hit["root"]
	return {"img": img, "xf": root.global_transform.affine_inverse() * frame, "size": sticker_size(tex, side), "color": col}


## Наклейка st в node.stickers узла uid и живая меш-наклейка на стенде.
func _add_sticker_live(uid: String, st: Dictionary) -> MeshInstance3D:
	var n := CraftEdit.find(ws.blueprint, uid)
	if n.is_empty():
		return null
	var arr: Array = n["stickers"] if n.get("stickers") is Array else []
	arr.append(st.duplicate())
	n["stickers"] = arr
	return ws.stand.add_sticker(uid, st.duplicate()) if ws.stand != null else null


## Наклейка под экранной точкой: {uid, node, index} или {} (index — номер в node.stickers).
func sticker_at(p: Vector2) -> Dictionary:
	var hit := surface_hit(p)
	if hit.is_empty():
		return {}
	return sticker_near(hit["point"])


## Наклейка, чья коробка содержит мировую точку p (меньшая — поверх большой).
func sticker_near(p: Vector3, skip: Node3D = null) -> Dictionary:
	if ws.stand == null:
		return {}
	var best: Dictionary = {}
	var best_area := INF
	for n in ws.blueprint.nodes:
		var uid := String(n.get("uid", ""))
		for d in ws.stand.stickers_of(uid):
			var sn := d as Node3D
			if sn == skip or not sn.is_inside_tree():
				continue
			var l := sn.global_transform.affine_inverse() * p
			var hs := BodyPaint.sticker_dims(sn) * 0.5
			if absf(l.x) <= hs.x and absf(l.z) <= hs.y and absf(l.y) <= BodyPaint.STICKER_DEPTH * 0.5 + 0.01:
				var area := hs.x * hs.y
				if area < best_area:
					best_area = area
					best = {"uid": uid, "node": sn}
	if not best.is_empty():
		best["index"] = _sticker_index(String(best["uid"]), best["node"])
		if int(best["index"]) < 0:
			return {}
	return best


## Номер наклейки-узла в node.stickers: живые наклейки узла идут по порядку годных записей (битые / без картинки не собираются).
func _sticker_index(uid: String, node: Node3D) -> int:
	var n := CraftEdit.find(ws.blueprint, uid)
	var arr: Array = n["stickers"] if n.get("stickers") is Array else []
	var valid: Array = []
	for i in arr.size():
		var st: Variant = arr[i]
		if BodyPaint.sticker_error(st) == "" and KitImages.texture(String((st as Dictionary)["img"])) != null:
			valid.append(i)
	var k := ws.stand.stickers_of(uid).find(node)
	return int(valid[k]) if k >= 0 and k < valid.size() else -1


## «Близнец» наклейки при симметрии: та же картинка в зеркальной точке ({} — нет / наклейка на оси).
func _twin_ref(ref: Dictionary) -> Dictionary:
	if not symmetry or ws.stand == null:
		return {}
	var d := ref["node"] as Node3D
	var p := d.global_position
	if absf(_to_doll(p).x) <= SYM_EPS * 2.0:
		return {}
	var mp := _mirror_point(p)
	var img := String((d.get_meta(BodyPaint.STICKER_META, {}) as Dictionary).get("img", ""))
	for n in ws.blueprint.nodes:
		var uid := String(n.get("uid", ""))
		for o in ws.stand.stickers_of(uid):
			var od := o as Node3D
			if od == d:
				continue
			if String((od.get_meta(BodyPaint.STICKER_META, {}) as Dictionary).get("img", "")) != img:
				continue
			if od.global_position.distance_to(mp) < TWIN_TOL:
				var idx := _sticker_index(uid, od)
				if idx >= 0:
					return {"uid": uid, "node": od, "index": idx}
	return {}


## Запись наклейки ref в чертёж и на живой узел (кадр — нынешний глобальный кадр узла, размер — size), меш — заново по детали.
func _store_sticker(ref: Dictionary, size := Vector2.ZERO) -> void:
	var d := ref["node"] as MeshInstance3D
	var uid := String(ref["uid"])
	var root := BodyPaint.mesh_root_of(ws.stand, uid)
	var n := CraftEdit.find(ws.blueprint, uid)
	var idx := _sticker_index(uid, d)
	if root == null or n.is_empty() or idx < 0:
		return
	var st: Dictionary = (n["stickers"] as Array)[idx].duplicate()
	if size != Vector2.ZERO:
		st["size"] = size
	st["xf"] = root.global_transform.affine_inverse() * d.global_transform
	(n["stickers"] as Array)[idx] = st
	d.set_meta(BodyPaint.STICKER_META, st.duplicate())
	BodyPaint.bake_sticker(d, root)


## Масштаб наклейки ×f (большая сторона 2–40 см), с близнецом. Серия — одна запись истории.
func scale_sticker(ref: Dictionary, f: float) -> bool:
	if ref.is_empty():
		return false
	var twin := _twin_ref(ref)
	_push("scale:%s" % (ref["node"] as Node).get_instance_id())
	_store_sticker(ref, _scaled(ref["node"], f))
	if not twin.is_empty():
		_store_sticker(twin, _scaled(twin["node"], f))
	focus_uid = String(ref["uid"])
	changed.emit()
	ws.changed.emit()
	return true


static func _scaled(d: Node3D, f: float) -> Vector2:
	var s := BodyPaint.sticker_dims(d)
	var big := maxf(s.x, s.y)
	var nb := clampf(big * f, STICKER_CM.x * 0.01, STICKER_CM.y * 0.01)
	return s * (nb / maxf(big, 1e-5))


## Поворот наклейки на deg вокруг её нормали (Q +15°, E −15°), близнец — зеркально. Серия — одна запись истории.
func rotate_sticker(ref: Dictionary, deg: float) -> bool:
	if ref.is_empty():
		return false
	var twin := _twin_ref(ref)
	_push("rot:%s" % (ref["node"] as Node).get_instance_id())
	_rotate_node(ref["node"], deg)
	_store_sticker(ref)
	if not twin.is_empty():
		_rotate_node(twin["node"], -deg)
		_store_sticker(twin)
	focus_uid = String(ref["uid"])
	changed.emit()
	ws.changed.emit()
	return true


static func _rotate_node(d: Node3D, deg: float) -> void:
	var g := d.global_transform
	g.basis = Basis(g.basis.y.normalized(), deg_to_rad(deg)) * g.basis
	d.global_transform = g


## Снять наклейку (и близнеца): запись из node.stickers, узел — сразу.
func remove_sticker(ref: Dictionary) -> bool:
	if ref.is_empty():
		return false
	var twin := _twin_ref(ref)
	_push()
	var refs: Array = [ref]
	if not twin.is_empty():
		refs.append(twin)
	for r in refs:
		_drop_sticker(r)
	ws._name_custom_body()
	_play(_click, 0.8)
	ws._say(tr("Наклейка снята (и пара)") if refs.size() > 1 else tr("Наклейка снята"), WorkshopBuild.COL_WARN)
	changed.emit()
	ws.changed.emit()
	return true


func _drop_sticker(ref: Dictionary) -> void:
	var d := ref["node"] as Node3D
	var uid := String(ref["uid"])
	var idx := _sticker_index(uid, d)
	var n := CraftEdit.find(ws.blueprint, uid)
	if idx >= 0 and not n.is_empty():
		var arr: Array = n["stickers"]
		arr.remove_at(idx)
		if arr.is_empty():
			n.erase("stickers")
	if is_instance_valid(d):
		if d.get_parent() != null:
			d.get_parent().remove_child(d)
		d.free()


func sticker_drag_begin(ref: Dictionary, p: Vector2) -> void:
	_sdrag = {"ref": ref, "twin": _twin_ref(ref), "start": p, "moved": false, "hit": {}, "twin_hit": {}, "bake": false}


## Тащим наклейку: узел едет по поверхности под курсором (и близнец — по зеркальному лучу); меш — раз в кадр (_process), по детали
## под курсором.
func sticker_drag_move(p: Vector2) -> void:
	if _sdrag.is_empty():
		return
	if not bool(_sdrag["moved"]):
		if p.distance_to(_sdrag["start"]) < 4.0:
			return
		_sdrag["moved"] = true
		_push()
	var r := _cam_ray(p)
	if r.is_empty():
		return
	var d := (_sdrag["ref"] as Dictionary)["node"] as Node3D
	var dims := BodyPaint.sticker_dims(d)
	var spread := maxf(dims.x, dims.y) * 0.3
	var hit := smoothed_hit(ray_hit(r[0], r[1]), r[1], spread)
	if not _paint_hit(hit):
		return
	var up := -d.global_basis.z
	d.global_transform = sticker_frame(decal_point(hit), hit["normal"], up)
	_sdrag["hit"] = hit
	_sdrag["bake"] = true
	var twin: Dictionary = _sdrag["twin"]
	if not twin.is_empty():
		var mr := _mirror_ray(r[0], r[1])
		var mh := smoothed_hit(ray_hit(mr[0], mr[1]), mr[1], spread)
		if _paint_hit(mh):
			(twin["node"] as Node3D).global_transform = sticker_frame(decal_point(mh), mh["normal"], _mirror_vec(up))
			_sdrag["twin_hit"] = mh


## Меш тащимой наклейки (и близнеца) — по детали, над которой она сейчас.
func _drag_rebake() -> void:
	if _sdrag.is_empty() or not bool(_sdrag.get("bake", false)):
		return
	_sdrag["bake"] = false
	for pair in [[_sdrag["ref"], _sdrag["hit"]], [_sdrag["twin"], _sdrag["twin_hit"]]]:
		var ref: Dictionary = pair[0]
		var hit: Dictionary = pair[1]
		if ref.is_empty() or hit.is_empty() or not is_instance_valid(ref.get("node")) or not is_instance_valid(hit.get("root")):
			continue
		BodyPaint.bake_sticker(ref["node"], hit["root"])


## Отпустили: наклейка остаётся там, где узел (на другой детали — переезжает в её node.stickers).
func sticker_drag_end() -> void:
	if _sdrag.is_empty():
		return
	var s := _sdrag
	_sdrag = {}
	if not bool(s["moved"]):
		return
	for pair in [[s["twin"], s["twin_hit"]], [s["ref"], s["hit"]]]:
		var ref: Dictionary = pair[0]
		var hit: Dictionary = pair[1]
		if ref.is_empty() or hit.is_empty() or not is_instance_valid(ref["node"]):
			continue
		_commit_move(ref, String(hit["uid"]))
	focus_uid = String((s["ref"] as Dictionary)["uid"])
	ws._name_custom_body()
	_play(_click, 1.4)
	changed.emit()
	ws.changed.emit()


func _commit_move(ref: Dictionary, new_uid: String) -> void:
	var d := ref["node"] as Node3D
	var uid := String(ref["uid"])
	if new_uid == uid:
		_store_sticker(ref)
		return
	var frame := d.global_transform
	var idx := _sticker_index(uid, d)
	var n := CraftEdit.find(ws.blueprint, uid)
	if idx < 0 or n.is_empty():
		return
	var st: Dictionary = (n["stickers"] as Array)[idx].duplicate()
	_drop_sticker({"uid": uid, "node": d})
	var root := BodyPaint.mesh_root_of(ws.stand, new_uid)
	if root == null:
		return
	st["xf"] = root.global_transform.affine_inverse() * frame
	_add_sticker_live(new_uid, st)


# =================================================================== фото, импорт, очистка

## Узел головы ("" — нет головы).
func head_uid() -> String:
	for n in ws.blueprint.nodes:
		var d := CraftEdit.part(String(n.get("part", "")))
		if d != null and d.kind == "head":
			return String(n.get("uid", ""))
	return ""


## Фото id на голову: у головы кита — node.face (плашка лица, живьём); у старой головы плашка утоплена под поверхность — фото
## наклейкой на лицо с пометкой face (размер — 60 % ширины головы): она одна, новое фото её заменяет. Уже стоит то же фото — ничего
## не делает (без записи истории). push — своя запись истории (замена головы в мастерской зовёт с false: запись уже есть; и молча).
## {ok, mode: "face" | "sticker", uid, same?}.
func set_face_image(id: String, push := true) -> Dictionary:
	var hu := head_uid()
	if hu == "" or ws.stand == null:
		if push:
			ws._say(tr("Фото некуда: у куклы нет головы"), WorkshopBuild.COL_BAD)
		return {"ok": false}
	var tex := KitImages.texture(id)
	if tex == null:
		if push:
			ws._say(tr("Картинка не читается"), WorkshopBuild.COL_BAD)
		return {"ok": false}
	image = id
	var d := CraftEdit.def_of(ws.blueprint, hu)
	var root := BodyPaint.mesh_root_of(ws.stand, hu)
	var node := CraftEdit.find(ws.blueprint, hu)
	if BodyPaint.face_plate_ok(d) and root != null:
		if String(node.get("face", "")) == id:
			if push:
				ws._say(tr("Это фото уже на голове"), WorkshopBuild.COL_INFO)
			return {"ok": true, "mode": "face", "uid": hu, "same": true}
		if push:
			_push()
		node["face"] = id
		if not BodyPaint.set_face(root, tex):
			ws._rebuild()
		_face_done(hu, push, tr("Фото на голове!"))
		return {"ok": true, "mode": "face", "uid": hu}
	# старая голова: наклейкой по центру лица (луч спереди куклы в голову), прежняя фото-наклейка — долой
	var old := _face_stickers(hu)
	for r in old:
		if String(((r["node"] as Node).get_meta(BodyPaint.STICKER_META, {}) as Dictionary).get("img", "")) == id:
			if push:
				ws._say(tr("Это фото уже на голове"), WorkshopBuild.COL_INFO)
			return {"ok": true, "mode": "sticker", "uid": hu, "same": true}
	var hit := _face_hit(hu)
	if not _paint_hit(hit):
		if push:
			ws._say(tr("Не нашлось лицо у этой головы"), WorkshopBuild.COL_BAD)
		return {"ok": false}
	var box := WorkshopBuild._visual_aabb(root) if root != null else AABB(part_center(hu), Vector3.ONE * 0.2)
	if push:
		_push()
	for r in old:
		_drop_sticker(r)
	var st := _make_sticker(hit, id, tex, ws.stand.global_basis.y, clampf(minf(box.size.x, box.size.y) * 0.6, 0.05, 0.3), Color.WHITE)
	st["face"] = true
	_add_sticker_live(hu, st)
	_face_done(hu, push, tr("У этой головы плашка утоплена — фото наклейкой на лицо"))
	return {"ok": true, "mode": "sticker", "uid": hu}


func _face_done(hu: String, loud: bool, text: String) -> void:
	focus_uid = hu
	ws._name_custom_body()
	if loud:
		_play(_click, 1.2)
		_puff(hu, Color(1.0, 0.95, 0.85))
		ws._say(text, Color(1.0, 0.9, 0.6))
	changed.emit()
	ws.changed.emit()


## Попадание в лицо головы hu: луч спереди куклы в центр головы (только её меши).
func _face_hit(hu: String) -> Dictionary:
	var c := part_center(hu)
	if c == Vector3.INF:
		return {}
	var fwd := ws.stand.global_basis.z.normalized()
	return smoothed_hit(ray_hit(c + fwd * 0.6, -fwd, hu), -fwd, 0.03)


## Фото-наклейки головы hu (пометка face в словаре наклейки): [{uid, node, index}].
func _face_stickers(hu: String) -> Array:
	var out: Array = []
	if ws.stand == null:
		return out
	for sn in ws.stand.stickers_of(hu):
		if bool(((sn as Node).get_meta(BodyPaint.STICKER_META, {}) as Dictionary).get("face", false)):
			var idx := _sticker_index(hu, sn)
			if idx >= 0:
				out.append({"uid": hu, "node": sn, "index": idx})
	return out


## Снять фото с головы: ключ face (кукла пересобирается — у плашки снова своё лицо) и фото-наклейки старой головы (с пометкой face;
## у сборок до пометки — картинки, наклеенные ровно в точку лица). Всегда с подсказкой. false — снимать нечего.
func clear_face() -> bool:
	var hu := head_uid()
	var n := CraftEdit.find(ws.blueprint, hu)
	if n.is_empty():
		ws._say(tr("У куклы нет головы"), WorkshopBuild.COL_INFO)
		return false
	var refs := _face_stickers(hu)
	if refs.is_empty() and ws.stand != null:
		var fh := _face_hit(hu)
		if _paint_hit(fh):
			var fp := decal_point(fh)
			for sn in ws.stand.stickers_of(hu):
				var img := String(((sn as Node).get_meta(BodyPaint.STICKER_META, {}) as Dictionary).get("img", ""))
				if KitImages.is_image_id(img) and (sn as Node3D).global_position.distance_to(fp) < 0.03:
					var idx := _sticker_index(hu, sn)
					if idx >= 0:
						refs.append({"uid": hu, "node": sn, "index": idx})
	if not n.has("face") and refs.is_empty():
		ws._say(tr("Фото на голове нет"), WorkshopBuild.COL_INFO)
		return false
	_push()
	var had_face := n.has("face")
	n.erase("face")
	for r in refs:
		if is_instance_valid(r["node"]):
			_drop_sticker(r)
	if had_face:
		ws._rebuild()
	ws._name_custom_body()
	ws._say(tr("Фото снято"), WorkshopBuild.COL_WARN)
	changed.emit()
	ws.changed.emit()
	return true


## Импорт картинок с диска (пути ОС) — синхронно (проба; окно — import_files_async). id импортированных; последний — текущая картинка.
func import_files(paths: PackedStringArray) -> PackedStringArray:
	var res: Array = []
	for p in paths:
		res.append([p, KitImages.import_file_ex(p)])
	return _import_report(res)


## Импорт в потоке (WorkerThreadPool): окно не замирает на больших фото. По готовности — _import_report и done(ids) на главном потоке.
func import_files_async(paths: PackedStringArray, done := Callable()) -> void:
	if paths.is_empty():
		return
	ws._say(tr("Импорт картинки…") if paths.size() == 1 else tr("Импорт картинок: %d…") % paths.size(), COL_IMPORT)
	var list := paths.duplicate()
	var task := WorkerThreadPool.add_task(func() -> void:
		var res: Array = []
		for p in list:
			res.append([p, KitImages.import_file_ex(p)])
		_import_finished.call_deferred(res, done))
	_import_tasks.append(task)


func _import_finished(res: Array, done: Callable) -> void:
	var left: PackedInt64Array = []
	for t in _import_tasks:
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			left.append(t)
	_import_tasks = left
	if ws == null or not is_inside_tree():
		return
	var ids := _import_report(res)
	if done.is_valid():
		done.call(ids)


## Итог импорта [[путь, KitImages.import_file_ex]]: новые id (последний — текущая картинка), подсказки — по причинам отказа.
func _import_report(res: Array) -> PackedStringArray:
	var ids := PackedStringArray()
	var bad := {}   # причина -> [имена файлов]
	for e in res:
		var r: Dictionary = e[1]
		var id := String(r["id"])
		if id == "":
			var why := String(r["error"])
			if not bad.has(why):
				bad[why] = []
			(bad[why] as Array).append(String(e[0]).get_file())
		elif not ids.has(id):
			ids.append(id)
	if not ids.is_empty():
		image = ids[ids.size() - 1]
		ws._say(tr("Картинка добавлена") if ids.size() == 1 else tr("Картинок добавлено: %d") % ids.size(), COL_IMPORT)
		images_changed.emit()
		changed.emit()
	for why in bad:
		ws._say(import_error_text(String(why), bad[why]), WorkshopBuild.COL_BAD)
	return ids


## Подсказка к отказу импорта (KitImages.ERR_*) по файлам names.
static func import_error_text(why: String, names: Array) -> String:
	var f := ", ".join(PackedStringArray(names))
	match why:
		KitImages.ERR_NOT_FOUND, KitImages.ERR_UNREADABLE:
			return TranslationServer.translate("Не прочитать файл: %s") % f
		KitImages.ERR_TOO_BIG_FILE:
			return TranslationServer.translate("Слишком большой файл (больше %d МБ): %s") % [KitImages.MAX_FILE_BYTES / (1024 * 1024), f]
		KitImages.ERR_TOO_BIG_PIXELS:
			return TranslationServer.translate("Слишком большая картинка (больше %d Мп): %s — уменьши её") % [KitImages.MAX_PIXELS / 1000000, f]
		KitImages.ERR_HEIC:
			return TranslationServer.translate("HEIC с iPhone не читается — сохрани как JPG: %s") % f
		KitImages.ERR_WRITE:
			return TranslationServer.translate("Не записать картинку на диск: %s") % f
	return TranslationServer.translate("Не картинка: %s (нужен png, jpg, webp, bmp, tga или svg)") % f


const COL_IMPORT := Color(0.6, 0.95, 1.0)


## Картинка id есть на кукле (наклейки / фото чертежа).
func image_used(id: String) -> bool:
	for n in ws.blueprint.nodes:
		if String(n.get("face", "")) == id:
			return true
		var sts: Variant = n.get("stickers")
		if sts is Array:
			for st in (sts as Array):
				if st is Dictionary and String((st as Dictionary).get("img", "")) == id:
					return true
	return false


## Удалить импортированную картинку id из «Моих картинок» (файл). Картинку на кукле — нельзя (кукла потеряла бы наклейку). false — нет.
func delete_image(id: String) -> bool:
	if image_used(id):
		ws._say(tr("Эта картинка на кукле — сначала сними её наклейки и фото"), WorkshopBuild.COL_WARN)
		return false
	if not KitImages.delete_image(id):
		ws._say(tr("Картинку не удалить"), WorkshopBuild.COL_BAD)
		return false
	if image == id:
		image = ""
	ws._say(tr("Картинка удалена"), WorkshopBuild.COL_WARN)
	images_changed.emit()
	changed.emit()
	return true


## Файлы, брошенные в окно: импорт в потоке; готово — вкладка «Покраска», над куклой — сразу наклейка под курсором (в режиме фото —
## фото на голову).
func _on_files_dropped(files: PackedStringArray) -> void:
	if ws == null or ws.mode != WorkshopBuild.Mode.BUILD:
		return
	import_files_async(files, func(ids: PackedStringArray) -> void:
		if ids.is_empty() or ws.mode != WorkshopBuild.Mode.BUILD:
			return
		open_tab.emit()
		if tool == "face":
			set_face_image(ids[ids.size() - 1])
			return
		if tool != "sticker":
			set_tool("sticker")
		var p := get_viewport().get_mouse_position()
		if _paint_hit(surface_hit(p)):
			place_sticker(p, ids[ids.size() - 1]))


func _exit_tree() -> void:
	for t in _import_tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_import_tasks = PackedInt64Array()


## Очистить деталь uid (по умолчанию — последнюю правленную) и её пару: краска, наклейки, фото. false — нечего.
func clear_part(uid := "") -> bool:
	if uid == "":
		uid = focus_uid
	var uids := with_twin(uid)
	var any := false
	for u in uids:
		var n := CraftEdit.find(ws.blueprint, String(u))
		any = any or n.has("paint") or n.has("stickers") or n.has("face")
	if not any:
		ws._say(tr("На этой детали нет краски"), WorkshopBuild.COL_INFO)
		return false
	_push()
	for u in uids:
		var n2 := CraftEdit.find(ws.blueprint, String(u))
		for k in ["paint", "stickers", "face"]:
			n2.erase(k)
	ws._rebuild()
	ws._say(tr("Очищено: %s") % _with_pair(ws.uid_title("body", uid), uids.size() > 1), WorkshopBuild.COL_WARN)
	return true


## Вся кукла без краски, наклеек и фото (одна запись истории). false — и так чисто.
func clear_all() -> bool:
	var any := false
	for n in ws.blueprint.nodes:
		any = any or n.has("paint") or n.has("stickers") or n.has("face")
	if not any:
		ws._say(tr("Кукла и так чистая"), WorkshopBuild.COL_INFO)
		return false
	_push()
	for n in ws.blueprint.nodes:
		for k in ["paint", "stickers", "face"]:
			n.erase(k)
	ws._rebuild()
	ws._say(tr("Вся покраска снята — Ctrl+Z вернёт"), WorkshopBuild.COL_WARN)
	return true


## Узел с краской / наклейками / фото есть.
func has_paint(uid := "") -> bool:
	for n in ws.blueprint.nodes:
		if uid != "" and String(n.get("uid", "")) != uid:
			continue
		if n.has("paint") or n.has("stickers") or n.has("face"):
			return true
	return false


# =================================================================== подсказка

## Название раскраски для игрока.
static func _pattern_title(kind: String) -> String:
	return TranslationServer.translate(String(PATTERN_TITLES.get(kind, kind)))


## «Рука» или «Рука и пара» (симметрия) — для сообщений.
static func _with_pair(title: String, pair: bool) -> String:
	return TranslationServer.translate("%s и пара") % title if pair else title


func hint_text() -> String:
	var turn := tr("R — повернуть стенд (%d°)") % turn_degrees()
	if tool in ["spray", "erase"] and _paint_hit(_hover_hit) and protected_hit(_hover_hit):
		return tr("Тут цвет игрока (пояс, шары суставов, лицо) — он не закрашивается   ·   %s") % turn
	match tool:
		"spray", "erase":
			var sz := tr("%s см") % String.num(snappedf(size_cm, 0.5))
			if _paint_hit(_hover_hit):
				var eff := eff_radius(String(_hover_hit["uid"])) * 200.0
				if eff > size_cm + 0.05:
					sz = tr("%s см (тут не мельче %s)") % [String.num(snappedf(size_cm, 0.5)), String.num(snappedf(eff, 0.1))]
			if tool == "spray":
				return tr("Зажми ЛКМ — красить · колесо / [ ] — размер %s · Alt+клик — пипетка · %s · Esc — положить") % [sz, turn]
			return tr("Зажми ЛКМ — стирать краску · колесо / [ ] — размер %s · %s · Esc — положить") % [sz, turn]
		"fill":
			return (tr("Клик по детали — залить целиком (и пару) · нажим = плотность · %s") if symmetry \
				else tr("Клик по детали — залить целиком · нажим = плотность · %s")) % turn
		"pattern":
			return (tr("Клик — «%s» на деталь и пару · Shift+клик — вся кукла · ещё клик — новый вариант · %s") if symmetry \
				else tr("Клик — «%s» на деталь · Shift+клик — вся кукла · ещё клик — новый вариант · %s")) % [_pattern_title(pattern_kind), turn]
		"pick":
			return tr("Клик по детали — взять её цвет · Esc — отмена")
		"stencil", "sticker":
			if tool == "sticker" and image == "":
				return tr("Нажми «Импорт…» на полке или перетащи картинку в окно игры")
			var s := sticker_at(_mouse) if _mouse.x >= 0.0 else {}
			if not s.is_empty():
				return tr("Над наклейкой: колесо / [ ] — размер · Q / E — поворот · тащи — переставить · ПКМ / Delete — снять")
			return tr("Клик — поставить (%d см, %d°) · колесо / [ ] — размер · Q / E — поворот · %s · Esc — положить") % [roundi(sticker_cm),
				roundi(sticker_rot), turn]
		"face":
			return tr("Кликни по картинке на полке (или по голове) — фото на лицо · «Импорт…» или перетащи файл в окно")
	return ""


# =================================================================== отклик: кольцо, превью, брызги, звук

func _process(delta: float) -> void:
	_time += delta
	_drag_rebake()
	_update_cursor()


func _update_cursor() -> void:
	var ring := false
	var ring2 := false
	var sel := false
	var prev := false
	var prev2 := false
	if ws != null and tool != "" and ws.mode == WorkshopBuild.Mode.BUILD and ws.stand != null and _pattern_queue.is_empty() \
			and _pattern_job.is_empty():
		if not virtual_mouse:
			_mouse = get_viewport().get_mouse_position()
		var over_ui := ws.ui != null and ws.ui.has_method("is_over_panel") and bool(ws.ui.call("is_over_panel", _mouse))
		var r := _cam_ray(_mouse) if not over_ui and _mouse.x >= 0.0 else []
		var hit := ray_hit(r[0], r[1]) if not r.is_empty() else {}
		_hover_hit = hit
		if _paint_hit(hit):
			match tool:
				"spray", "erase", "pick":
					# кольцо — настоящий размер мазка на этой детали (не мельче BRUSH_CELL_MIN ячейки её слоя)
					var rr := eff_radius(String(hit["uid"])) if tool != "pick" else 0.006
					hit = smoothed_hit(hit, r[1], maxf(rr * 0.7, 0.006))
					var col := color if tool == "spray" else (Color(1, 1, 1) if tool == "erase" else color)
					var guarded := tool != "pick" and protected_hit(hit)   # цвет игрока: краска не ляжет — кольцо серое
					_place_ring(_ring, hit, rr, Color(0.6, 0.6, 0.6) if guarded else col, 0.6 if guarded else 0.95)
					ring = true
					if symmetry and tool != "pick" and absf(_to_doll(hit["point"]).x) > SYM_EPS:
						var mr := _mirror_ray(r[0], r[1])
						var mh := ray_hit(mr[0], mr[1])
						if _paint_hit(mh):
							var rm := eff_radius(String(mh["uid"]))
							mh = smoothed_hit(mh, mr[1], maxf(rm * 0.7, 0.006))
							_place_ring(_ring_twin, mh, rm, col, 0.45)
							ring2 = true
				"stencil", "sticker":
					var s := sticker_near(hit["point"]) if _sdrag.is_empty() else {}
					if not s.is_empty():
						var d := s["node"] as Node3D
						var dm := BodyPaint.sticker_dims(d)
						_place_ring(_sel_ring, {"point": d.global_position, "normal": d.global_basis.y.normalized()},
							maxf(dm.x, dm.y) * 0.62, Color(1.0, 0.82, 0.3), 1.0)
						sel = true
					elif _sdrag.is_empty():
						var img := current_img()
						var tex := KitImages.texture(img) if img != "" else null
						if tex != null:
							var side := sticker_cm * 0.01
							hit = smoothed_hit(hit, r[1], side * 0.3)
							var single := symmetry and _sticker_on_axis(hit, sticker_size(tex, side))
							if single:
								hit = _snap_to_axis(hit, side)   # как встанет: одна, на плоскости симметрии
							var cam := get_viewport().get_camera_3d()
							var up := cam.global_basis.y.rotated((hit["normal"] as Vector3), deg_to_rad(sticker_rot))
							var col2 := color if img.begins_with(KitImages.STENCIL_PREFIX) else Color.WHITE
							_place_preview(_preview, hit, img, tex, up, col2)
							prev = true
							if symmetry and not single:
								var mr2 := _mirror_ray(r[0], r[1])
								var mh2 := smoothed_hit(ray_hit(mr2[0], mr2[1]), mr2[1], side * 0.3)
								if _paint_hit(mh2):
									_place_preview(_preview_twin, mh2, img, tex, _mirror_vec(up), col2)
									prev2 = true
	_ring.visible = ring
	_ring_twin.visible = ring2
	_sel_ring.visible = sel
	_preview.visible = prev
	_preview_twin.visible = prev2


func _place_ring(ring: Node3D, hit: Dictionary, r: float, col: Color, alpha: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var p: Vector3 = hit["point"]
	var n: Vector3 = hit["normal"]
	var w := RING_PX / maxf(_ppm(p), 1.0)
	var halo := ((ring.get_child(0) as MeshInstance3D).mesh) as TorusMesh
	var line := ((ring.get_child(1) as MeshInstance3D).mesh) as TorusMesh
	_set_torus(halo, r + w, maxf(r - w * 2.0, w * 0.5))
	_set_torus(line, r, maxf(r - w, w * 0.25))
	var lm := (ring.get_child(1) as MeshInstance3D).material_override as StandardMaterial3D
	lm.albedo_color = Color(col.r, col.g, col.b, alpha)
	var hm := (ring.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	hm.albedo_color = Color(0.03, 0.02, 0.02, 0.55 * alpha) if col.get_luminance() > 0.35 else Color(1, 1, 1, 0.6 * alpha)
	ring.global_transform = sticker_frame(p + n * 0.0015, n, cam.global_basis.y)


static func _set_torus(t: TorusMesh, outer: float, inner: float) -> void:
	if absf(t.outer_radius - outer) > outer * 0.01 or absf(t.inner_radius - inner) > inner * 0.02 + 1e-5:
		t.outer_radius = outer
		t.inner_radius = minf(inner, outer * 0.999)


## Превью наклейки у курсора — меш-наклейка, как ляжет (без поясов и шаров, только на эту деталь), полупрозрачная. Меш — заново,
## только когда сдвинулась / сменилась (картинка, цвет, размер, деталь).
func _place_preview(n: MeshInstance3D, hit: Dictionary, img: String, tex: Texture2D, up: Vector3, col: Color) -> void:
	var frame := sticker_frame(decal_point(hit), hit["normal"], up)
	var sz := sticker_size(tex, sticker_cm * 0.01)
	var root: Node3D = hit["root"]
	var key := [img, col, sz, root.get_instance_id()]
	var old: Array = n.get_meta("bake_key", [])
	var last: Transform3D = n.get_meta("bake_xf", Transform3D())
	if old == key and last.origin.distance_to(frame.origin) < 5e-4 and last.basis.y.dot(frame.basis.y) > 0.9999 \
			and last.basis.z.dot(frame.basis.z) > 0.9999:
		return
	n.global_transform = frame
	n.set_meta(BodyPaint.STICKER_META, {"img": img, "size": sz, "color": col})
	BodyPaint.bake_sticker(n, root, PREVIEW_ALPHA)
	n.set_meta("bake_key", key)
	n.set_meta("bake_xf", frame)


func _make_visuals() -> void:
	_ring = _make_ring("BrushRing")
	_ring_twin = _make_ring("BrushRingTwin")
	_sel_ring = _make_ring("StickerRing")
	_preview = _make_preview("StickerPreview")
	_preview_twin = _make_preview("StickerPreviewTwin")
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.albedo_color = Color(1, 1, 1, 0.5)
	# брызги: капельки летят от «сопла» (7 см над поверхностью) в поверхность
	_fx = GPUParticles3D.new()
	_fx.name = "SprayDrops"
	_fx.amount = 120
	_fx.lifetime = 0.2
	_fx.randomness = 0.4
	_fx.local_coords = false
	_fx.emitting = false
	_fx.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_mat = ParticleProcessMaterial.new()
	_fx_mat.direction = Vector3(0, -1, 0)
	_fx_mat.spread = 16.0
	_fx_mat.initial_velocity_min = 0.35
	_fx_mat.initial_velocity_max = 0.7
	_fx_mat.gravity = Vector3(0, -1.2, 0)
	_fx_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_fx_mat.emission_sphere_radius = 0.01
	_fx_mat.scale_min = 0.5
	_fx_mat.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, 0.35))
	var sct := CurveTexture.new()
	sct.curve = sc
	_fx_mat.scale_curve = sct
	_fx.process_material = _fx_mat
	var drop := SphereMesh.new()
	drop.radius = 0.004
	drop.height = 0.008
	drop.radial_segments = 6
	drop.rings = 3
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.roughness = 0.35
	drop.material = dm
	_fx.draw_pass_1 = drop
	add_child(_fx)
	# облачко: мягкие полупрозрачные пятна того же цвета
	_mist = GPUParticles3D.new()
	_mist.name = "SprayMist"
	_mist.amount = 14
	_mist.lifetime = 0.35
	_mist.local_coords = false
	_mist.emitting = false
	_mist.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	_mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mist_mat = ParticleProcessMaterial.new()
	_mist_mat.direction = Vector3(0, -1, 0)
	_mist_mat.spread = 30.0
	_mist_mat.initial_velocity_min = 0.08
	_mist_mat.initial_velocity_max = 0.2
	_mist_mat.gravity = Vector3.ZERO
	_mist_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_mist_mat.emission_sphere_radius = 0.01
	var gc := Curve.new()
	gc.add_point(Vector2(0, 0.5))
	gc.add_point(Vector2(1, 1.4))
	var gct := CurveTexture.new()
	gct.curve = gc
	_mist_mat.scale_curve = gct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	_mist_mat.color_ramp = gtex
	_mist.process_material = _mist_mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var soft := GradientTexture2D.new()
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 1))
	sg.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = sg
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	qm.albedo_texture = soft
	quad.material = qm
	_mist.draw_pass_1 = quad
	add_child(_mist)


func _make_ring(nm: String) -> Node3D:
	var root := Node3D.new()
	root.name = nm
	root.visible = false
	for i in 2:
		var t := TorusMesh.new()
		t.rings = 48
		t.ring_segments = 6
		t.inner_radius = 0.9
		t.outer_radius = 1.0
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = 10 + i
		mi.material_override = m
		root.add_child(mi)
	add_child(root)
	return root


func _make_preview(nm: String) -> MeshInstance3D:
	var d := MeshInstance3D.new()
	d.name = nm
	d.visible = false
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(d)
	return d


func _fx_colour() -> void:
	var erase := tool == "erase"
	_fx_mat.color = Color(0.85, 0.8, 0.72) if erase else color
	_mist_mat.color = Color(0.9, 0.86, 0.8, 0.15) if erase else Color(color.r, color.g, color.b, 0.38)
	_fx.amount_ratio = 0.35 if erase else 1.0


func _fx_at(hit: Dictionary) -> void:
	var n: Vector3 = hit["normal"]
	var cam := get_viewport().get_camera_3d()
	var up := cam.global_basis.y if cam != null else Vector3.UP
	var xf := sticker_frame((hit["point"] as Vector3) + n * 0.07, n, up)
	_fx.global_transform = xf
	_mist.global_transform = sticker_frame((hit["point"] as Vector3) + n * 0.03, n, up)
	_fx_mat.emission_sphere_radius = radius() * 0.5
	_mist_mat.emission_sphere_radius = radius() * 0.4
	_fx_emit(true)


func _fx_emit(on: bool) -> void:
	if _fx == null:
		return
	if _fx.emitting != on:
		_fx.emitting = on
	if _mist.emitting != on:
		_mist.emitting = on


## «Пуф» брызг у детали uid цветом col (заливка, раскраска, фото).
func _puff(uid: String, col: Color) -> void:
	var c := part_center(uid)
	if c == Vector3.INF:
		return
	var cam := get_viewport().get_camera_3d()
	var n := (cam.global_position - c).normalized() if cam != null else Vector3.BACK
	_puff_at(c + n * 0.08, n, col)


func _puff_at(p: Vector3, n: Vector3, col: Color) -> void:
	var fx := GPUParticles3D.new()
	fx.name = "Puff"
	fx.one_shot = true
	fx.explosiveness = 0.9
	fx.amount = 26
	fx.lifetime = 0.45
	fx.local_coords = false
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, -2.5, 0)
	pm.color = col
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.scale_curve = (_fx_mat.scale_curve as CurveTexture)
	fx.process_material = pm
	fx.draw_pass_1 = _fx.draw_pass_1
	add_child(fx)
	var cam := get_viewport().get_camera_3d()
	fx.global_transform = sticker_frame(p, n, cam.global_basis.y if cam != null else Vector3.UP)
	fx.emitting = true
	get_tree().create_timer(1.0).timeout.connect(fx.queue_free)


func _make_audio() -> void:
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_hiss = _player(SND_LOOP, bus)
	_click = _player(SND_START, bus)
	_rattle = _player(SND_RATTLE, bus)


func _player(path: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = load(path) if ResourceLoader.exists(path) else null
	add_child(p)
	return p


func _play(p: AudioStreamPlayer, pitch := 1.0) -> void:
	if p == null or p.stream == null:
		return
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func _sound_start() -> void:
	if _hiss == null or _hiss.stream == null:
		return
	var erase := tool == "erase"
	if not erase:
		_play(_click)
	if _hiss_tween != null:
		_hiss_tween.kill()
	_hiss.pitch_scale = 0.55 if erase else randf_range(0.97, 1.03)
	_hiss.volume_db = -40.0
	if not _hiss.playing:
		_hiss.play()
	_hiss_tween = create_tween()
	_hiss_tween.tween_property(_hiss, "volume_db", ERASE_DB if erase else HISS_DB, 0.06)


func _sound_stop() -> void:
	if _hiss == null or not _hiss.playing:
		return
	if _hiss_tween != null:
		_hiss_tween.kill()
	_hiss_tween = create_tween()
	_hiss_tween.tween_property(_hiss, "volume_db", -45.0, 0.075)
	_hiss_tween.tween_callback(_hiss.stop)


## Штрих, перетаскивание и очередь раскраски — довести (при смене инструмента): штрих и перетаскивание записываются, раскраска —
## докрашивается сразу.
func _finish_all() -> void:
	if not _stroke.is_empty():
		stroke_end()
	if not _sdrag.is_empty():
		sticker_drag_end()
	_finish_patterns()
	_sound_stop()
	_fx_emit(false)


## Цвет сообщения по краске: тёмные — светлее (читаются на тёмной плашке).
static func _toast_col(c: Color) -> Color:
	return c.lightened(0.45) if c.get_luminance() < 0.45 else c
