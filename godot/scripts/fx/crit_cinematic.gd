## Кинематограф «сокрушительного удара» в духе Mortal Kombat (HIT_FX.md §3, контракт §4.3). Сцена scenes/fx/crit_cinematic.tscn:
##   CritCam (Camera3D, fov 30) → XrayPost (полноэкранный квад «рентгена», assets/shaders/fx/xray.gdshader),
##   CritSplinters (48 крит-щепок) / CritSplinters2 (второй выброс — «перелом»), CritOverlay (scenes/ui/crit_overlay.tscn, слой 30).
## Место — ребёнок HitFxDirector (он вызывает play(ctx) на crit / ko_crit); работает и сам по себе (пробы): Match ищется по группе
## "match", директор — по группе "hit_fx_director", HUD — по группе "hud" (или узлу Hud рядом с Match).
##
## Таймлайн (мс реального времени от засчитанного удара; часы — delta / time_scale кадра, как у Match):
##   0     freeze   — стоп-кадр time_scale 0.02 (тег crit_freeze), 2 кадра инверсии, ImpactFx ×2, HUD скрыт, punch −10 % игровой камеры;
##   33–120         — белая кромка гаснет, леттербокс въезжает;
##   120   cut_in   — кат в CritCam (Match.capture_camera(cam, "crit")), рентген, оверлей волокна на ударенной детали (material_overlay
##                    инстансов, старый возвращается), остальные детали — голубой обод, Decal-трещина на теле детали, 48 щепок,
##                    экранные трещины; time_scale 0.12 (crit_xray); наезд +6 %, крен 0 → 5°, дрейф 0.1 м вдоль удара;
##   220   caption  — CRUSHING BLOW! (2.0 → 1.0 за 90 мс, дрожь 10 px 200 мс);
##   250 / 400      — стадии трещины; 400 crack_2 — вспышка волокна и второй выброс щепок;
##   620   cut_out  — белый кадр, кат назад (Match.release_camera("crit")), рентген и оверлеи сняты; slowmo — time_scale 0.3 на 0.55 с
##                    (crit_slowmo) или для ko_crit KO_SLOWMO_SCALE на 1.4 с (ko_crit_slowmo); DynamicCamera.focus / roll_kick;
##                    линии скорости 620–1050;
##   900–1020       — леттербокс уезжает; Decal гаснет к 1300;
##   1300  done     — HUD вернулся (set_cinematic(false) / announcer.clear()), теги crit_* сняты, сигнал finished(ctx).
## ko_crit: карточка KO откладывается (Hud.defer_ko_card(0.65)); остальное — как crit.
## v2 (HIT_FX.md §11.4–11.5):
##   маска кукол DollMask (у HitFxDirector или своя): кадры-силуэты 0–33 мс — куклы по маске на плоском фоне (одинаково на Void и
##   на светлом небе Руин); рентген 120–620 — фон вне маски плоский тёмно-синий без контуров (xray.gdshader use_mask), щепки крита
##   в маске; CritCam — полувысота по AABB ударенной детали (part_half_height: конечность ≈ 0.55 м, голова/торс ≥ CAM_HALF_MIN_CORE),
##   деталь чуть выше центра кадра (CAM_COMPOSE_UP); надпись — в полосе, которая меньше перекрывает деталь на экране (низ 0.76 /
##   верх 0.25, выбор на 220 мс); на cut_out встаёт над жертвой в игровой камере (0.26; жертва в верхней трети — 0.84), уезжает
##   вверх на 0.08 со scale 0.86 → 0.7 и гаснет к CAPTION_FADE_MS.y (860 мс).
## v3 (HIT_FX.md §12.3): маркер точки удара 33–150 мс (кольцо и лучи с тёмной обводкой, CritOverlay.set_marker; кадр +117 больше не
##   статичен); в рентгене атакующий затемнён (material_overlay xray_dim — тёмный, с тонким ободом: видно, чья «кость» ломается);
##   надпись — в полосе, которая меньше перекрывает ударенную деталь и кукол (крупный план: деталь, затем атакующий; после ката —
##   обе куклы в игровой камере); замедление после ката — лёгкое затемнение фона вокруг жертвы (CritOverlay.set_bg_dim);
##   focus игровой камеры держится до конца замедления + HitFxDirector.CRIT_HOLD_TAIL_S (safe-area ставит директор).
## Прерывание: abort() — restart (phase COUNTDOWN / OVER без KO), doll_replaced жертвы, выход из дерева, сторож 1500 мс;
## повторный play() во время проигрывания — false.
## Модель куклы не важна: только Doll.parts (RigidBody3D), позиции и скорости; меши ударенной детали — MeshInstance3D-потомки,
## найденные в рантайме (нет мешей — оверлей пропускается). Материалы куклы не меняются: меняется свойство material_overlay
## инстанса и возвращается. Decal проецируется только на слой HITFX_DOLL_LAYER (бит 1 << 19).
## Пока у Match нет request_time_scale / capture_camera (ядро делается параллельно), время пишется в Match._time_effects с ключом
## tag, камера переключается make_current с возвратом; без Match — своё Engine.time_scale с гарантированным возвратом к 1.
class_name CritCinematic
extends Node3D

signal phase(name: String, ms: float)
signal finished(ctx: Dictionary)
signal aborted(ctx: Dictionary)

const FRAME_HALF_MS := 8.34
const INVERT_MS := 33.0
const LETTERBOX_IN_MS := Vector2(33.0, 120.0)
const EDGE_FADE_MS := Vector2(33.0, 120.0)
const FREEZE_MS := 120.0
const CUT_IN_MS := 120.0
const XRAY_MS := 500.0
const CAPTION_MS := 220.0
const CAPTION_IN_MS := 90.0
const CAPTION_SHAKE_MS := 200.0
const CAPTION_SHAKE_PX := 10.0
const CAPTION_OUT_MS := Vector2(620.0, 760.0)     # после ката: уезд вверх OUT_RISE и scale CAPTION_OUT_SCALE_FROM → CAPTION_OUT_SCALE
const CAPTION_OUT_SCALE_FROM := 0.86
const CAPTION_OUT_SLOTS := [0.26, 0.84]           # на кате надпись встаёт над жертвой (или под ней, если жертва в верхней трети)
const CAPTION_OUT_RISE := 0.08
const CAPTION_FADE_MS := Vector2(700.0, 860.0)    # гаснет к 860 мс
const CAPTION_OUT_SCALE := 0.7
const CAPTION_SLOTS := [0.76, 0.25]               # доли высоты: низ (по умолчанию) / верх
const CAPTION_BAND := 0.12                        # полувысота полосы надписи (доля экрана)
const CRACK_1_MS := 250.0
const CRACK_2_MS := 400.0
const SCREEN_CRACK_MS := Vector2(120.0, 450.0)
const CUT_OUT_MS := 620.0
const KO_CARD_MS := 650.0
const SPEED_LINES_MS := Vector2(620.0, 1050.0)
const LETTERBOX_OUT_MS := Vector2(900.0, 1020.0)
const DECAL_GLOW_FADE_MS := Vector2(620.0, 800.0)
const DECAL_FADE_MS := Vector2(620.0, 1300.0)
const TOTAL_MS := 1300.0
const WATCHDOG_MS := 1500.0
const FREEZE_SCALE := 0.02
const XRAY_SCALE := 0.12
const TIME_MARGIN_S := 0.15          # запас длительности тегов: снимаются явно на переходах
const KO_CARD_DEFER_S := 0.65
const KO_CRIT_SLOWMO_S := 1.4
const INVERT_ALPHA := 1.0
const CUT_FLASH_ALPHA := 0.5
const EDGE_ALPHA := 0.6
const CAM_FOV := 30.0
const CAM_HALF_HEIGHT := 0.9           # запасная полувысота (нет AABB детали)
const CAM_HALF_PER_EXTENT := 1.15      # полувысота = протяжённость детали на плоскости × это
const CAM_HALF_MIN := 0.5
const CAM_HALF_MAX := 0.95
const CAM_HALF_MIN_CORE := 0.7         # голова и торс: крупнее конечности, видно шею/плечи
const CAM_COMPOSE_UP := 0.16           # деталь выше центра кадра на эту долю полувысоты × 2 (место надписи снизу)
const MASK_KEY := "crit_xray"
const CAM_YAW_DEG := 14.0
const CAM_PITCH_DEG := 6.0            # камера чуть ниже точки — ракурс снизу
const CAM_PUSH_IN := 0.06
const CAM_ROLL_DEG := 5.0
const CAM_DRIFT_M := 0.1
const CAM_LAG_S := 0.06
const PUNCH_FRAC := -0.10
const OUT_FOCUS_WEIGHT := 0.7
const OUT_FOCUS_S := 0.7              # v2; v3 — HitFxDirector.crit_hold_s / (1 − FOCUS_OUT_FRAC)
const MARKER_MS := Vector2(33.0, 150.0)
const MARKER_R := Vector2(55.0, 175.0) # радиус маркера (ед. Root, высота 1080): рост за окно
const BG_DIM := 0.5                   # затемнение фона в замедлении после ката (вокруг жертвы — чисто)
const BG_DIM_IN_MS := 70.0
const BG_DIM_OUT_MS := 220.0
const CAPTION_EXTRA_SLOTS := [0.84]   # запасная полоса крупного плана (если обе основные закрывают деталь/кукол)
const CAPTION_OUT_CANDIDATES := [0.26, 0.84, 0.2, 0.74]
const CAPTION_HALF_W := 0.31          # полуширина надписи (доля ширины кадра) при scale 1
const CAPTION_HALF_H := 0.07
const ATTACKER_WEIGHT := 0.6          # вес перекрытия атакующего при выборе полосы в крупном плане
const OUT_ROLL_DEG := 2.0
const DECAL_SIZE := 0.35
const DECAL_DEPTH := 0.6
const DECAL_GLOW := 4.0
const CRACK_SIZE_M := 0.45
const DOLL_LAYER_BIT := 1 << 19
const OVERLAY_PRIORITY := 20      # выше ImpactFlash (10) и квада рентгена (0)
const XRAY_FLASH_MS := Vector2(400.0, 540.0)
const IMPACT_MULT := 2.0
const FLASH_HIDE_RADIUS_M := 1.5
const TAGS := ["crit_freeze", "crit_xray", "crit_slowmo", "ko_crit_slowmo"]

const XRAY_WOOD: Shader = preload("res://assets/shaders/fx/xray_wood.gdshader")
const XRAY_GHOST: Shader = preload("res://assets/shaders/fx/xray_ghost.gdshader")
const XRAY_DIM: Shader = preload("res://assets/shaders/fx/xray_dim.gdshader")
const CRACK_SCREEN: Texture2D = preload("res://assets/textures/fx/crack_screen.png")
const CRACK_DECAL: Array[Texture2D] = [
	preload("res://assets/textures/fx/crack_decal_0.png"),
	preload("res://assets/textures/fx/crack_decal_1.png"),
	preload("res://assets/textures/fx/crack_decal_2.png"),
]
const CRACK_GLOW: Array[Texture2D] = [
	preload("res://assets/textures/fx/crack_glow_0.png"),
	preload("res://assets/textures/fx/crack_glow_1.png"),
	preload("res://assets/textures/fx/crack_glow_2.png"),
]

## false — play() отказывает (как HITFX_CRIT_CINEMATIC=false у директора).
@export var enabled := true
## Линии скорости после ката (если их рисует директор — выключить).
@export var speed_lines_enabled := true
## ≥ 0 — своя сила вспышек/инверсий вместо HitFxDirector.flash_intensity / Tuning.HITFX_FLASH_INTENSITY (пробы, меню).
@export var flash_intensity_override := -1.0

@onready var crit_cam: Camera3D = $CritCam
@onready var xray_post: MeshInstance3D = $CritCam/XrayPost
@onready var splinters: GPUParticles3D = $CritSplinters
@onready var splinters_2: GPUParticles3D = $CritSplinters2
@onready var overlay: CritOverlay = $CritOverlay

var played: Array = []               # [{tier, ms_total}] для проб
var phase_log: Array = []            # [[name, ms]] последнего проигрывания

var _playing := false
var _ctx: Dictionary = {}
var _ms := 0.0
var _frame := -1
var _fired: Dictionary = {}
var _clock_ms := 0.0                 # собственные нескалированные часы (всегда идут)
var _scale_seen := 1.0               # Engine.time_scale в конце прошлого кадра = масштаб delta этого кадра
var _match: Node
var _director: Node
var _hud: Node
var _victim: Node3D
var _part: RigidBody3D
var _game_cam: Camera3D
var _prev_cam: Camera3D
var _cam_captured := false
var _hit_pos := Vector3.ZERO
var _hit_local := Vector3.ZERO       # точка удара в пространстве тела детали
var _dir := Vector3.LEFT
var _grain_local := Vector3.UP
var _aim := Vector3.ZERO
var _saved_overlay: Dictionary = {}  # MeshInstance3D -> Material (прежний material_overlay)
var _layer_added: Array = []         # MeshInstance3D, которым добавлен бит слоя Decal
var _wood_mat: ShaderMaterial
var _ghost_mat: ShaderMaterial
var _dim_mat: ShaderMaterial
var _attacker: Node3D
var _marker_pos := Vector2.ZERO       # последняя экранная точка удара (ед. Root)
var _decal: Decal
var _decal_stage := -1
var _flash_ok := true
var _invert_ok := true
var _cut_flash_pending := false
var _flash_times: Array = []
var _hud_hidden: Array = []          # [[node, was_visible]] (запасной путь без Hud.set_cinematic)
var _ko_card_fallback: Node
var _own_time: Dictionary = {}       # tag -> {scale, left} (без Match)
var _signals: Array = []             # [[object, signal, callable]]
var _shake_mult := 1.0
var _flash_mult := 1.0
var _prewarm_frames := 0
var _half_h := CAM_HALF_HEIGHT       # полувысота крупного плана этого проигрывания
var _mask: DollMask
var _own_mask := false
var _caption_y := -1.0               # выбранная полоса надписи (доля высоты), −1 — ещё не выбрана
var _caption_out_y := -1.0           # полоса после ката (над/под жертвой в игровой камере)
var part_half_height := 0.0          # пробы: полувысота CritCam последнего проигрывания
var caption_slot := -1.0             # пробы: полоса надписи последнего проигрывания
var caption_out_slot := -1.0         # пробы: полоса надписи после ката
var part_screen_span := Vector2.ZERO # пробы: деталь на экране (доли высоты y0, y1) в момент выбора надписи
var marker_frames := 0               # пробы: кадров с маркером точки удара последнего проигрывания
var bg_dim_frames := 0               # пробы: кадров с затемнением фона
var attacker_dimmed := 0             # пробы: мешей атакующего с оверлеем затемнения (сейчас)
var caption_overlap := -1.0          # пробы: перекрытие надписи с куклами после ката (доля площади полосы)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000   # после Match._process: время, которое мы ставим, действует с delta следующего кадра
	add_to_group("crit_cinematic")
	_ensure_materials()
	crit_cam.fov = CAM_FOV
	crit_cam.current = false
	xray_post.visible = false
	_ensure_mask()


func _exit_tree() -> void:
	if _playing:
		abort()
	_restore_time_all()


func is_playing() -> bool:
	return _playing


func elapsed_ms() -> float:
	return _ms if _playing else 0.0


## Нескалированные часы (мс) — для проб и совместного таймлайна.
func clock_ms() -> float:
	return _clock_ms


## Материалы и шейдеры заранее: оверлеи создаются, рентген и экранный слой рисуются 3 кадра с нулевой силой (не в headless).
func prewarm() -> void:
	_ensure_materials()
	if DisplayServer.get_name() == "headless" or _playing:
		return
	FxPrewarm.spatial(self, [_wood_mat, _ghost_mat, _dim_mat])   # оверлеи деталей рентгена (v3 — xray_dim)
	if overlay != null and overlay.has_method("prewarm"):
		overlay.prewarm()   # затемнение фона и маркер удара (v3)
	_prewarm_frames = 3
	(xray_post.get_surface_override_material(0) as ShaderMaterial).set_shader_parameter("intensity", 0.0)
	xray_post.visible = true


## Маска кукол: у HitFxDirector (его doll_mask) или любая в дереве; нет — своя (ребёнок, пробы без директора).
func _ensure_mask() -> DollMask:
	if _mask != null and is_instance_valid(_mask):
		return _mask
	var d := _find_director() if is_inside_tree() else null
	if d != null:
		var m: Variant = d.get("doll_mask")
		if m is DollMask and is_instance_valid(m):
			_mask = m
	if _mask == null and is_inside_tree():
		_mask = DollMask.find(self)
	if _mask == null:
		_mask = DollMask.new()
		_mask.name = "DollMask"
		add_child(_mask)
		_own_mask = true
	for p in [splinters, splinters_2]:
		_mask.include(p as GeometryInstance3D)
	if overlay != null:
		overlay.set_mask(_mask)
	return _mask


func _ensure_materials() -> void:
	if _wood_mat == null:
		_wood_mat = ShaderMaterial.new()
		_wood_mat.shader = XRAY_WOOD
		_wood_mat.render_priority = OVERLAY_PRIORITY
		_wood_mat.set_shader_parameter("crack_tex", CRACK_SCREEN)
		_wood_mat.set_shader_parameter("crack_size", CRACK_SIZE_M)
	if _ghost_mat == null:
		_ghost_mat = ShaderMaterial.new()
		_ghost_mat.shader = XRAY_GHOST
		_ghost_mat.render_priority = OVERLAY_PRIORITY
	if _dim_mat == null:
		_dim_mat = ShaderMaterial.new()
		_dim_mat.shader = XRAY_DIM
		_dim_mat.render_priority = OVERLAY_PRIORITY - 1


# --- запуск ---

## ctx — как у Match.hit_fx (HIT_FX.md §4.1): victim, attacker, part, position, normal, dir, speed, kind, is_ko, tier, …
## false: уже идёт, выключено или жертва без частей.
func play(ctx: Dictionary) -> bool:
	if _playing or not enabled or not _flag("crit_cinematic", Tuning.HITFX_CRIT_CINEMATIC):
		return false
	var v: Variant = ctx.get("victim")
	if not (v is Node3D) or not is_instance_valid(v) or not (v as Node3D).is_inside_tree():
		return false
	var parts: Variant = (v as Node3D).get("parts")
	if not (parts is Dictionary) or (parts as Dictionary).is_empty():
		return false
	if not is_inside_tree():
		return false
	_prewarm_frames = 0
	_ctx = ctx
	_victim = v
	var att: Variant = ctx.get("attacker")
	_attacker = att if att is Node3D and is_instance_valid(att) and att != v and (att as Node3D).get("parts") is Dictionary else null
	marker_frames = 0
	bg_dim_frames = 0
	caption_overlap = -1.0
	_match = _find_match()
	_director = _find_director()
	_hud = _find_hud()
	_part = _pick_part(parts as Dictionary, String(ctx.get("part", "")), ctx)
	if _part == null:
		_victim = null
		return false
	_hit_pos = _part.global_position
	if ctx.get("position") is Vector3:
		_hit_pos = ctx["position"]
	_hit_pos.z = _part.global_position.z
	_hit_local = _part.to_local(_hit_pos)
	var d := Vector3.ZERO
	if ctx.get("dir") is Vector3:
		d = ctx["dir"]
	if d.length_squared() < 1e-6 and ctx.get("normal") is Vector3:
		d = -(ctx["normal"] as Vector3)
	d.z = 0.0
	_dir = d.normalized() if d.length_squared() > 1e-6 else Vector3.LEFT
	_grain_local = _grain_axis(_part)
	_half_h = _part_half_height(_part, String(ctx.get("part", _part.name)))
	part_half_height = _half_h
	_caption_y = -1.0
	_caption_out_y = -1.0
	_shake_mult = clampf(float(_flag("shake_intensity", Tuning.HITFX_SHAKE_INTENSITY)), 0.0, 1.0)
	_flash_mult = clampf(float(_flag("flash_intensity", Tuning.HITFX_FLASH_INTENSITY)), 0.0, 1.0)
	if flash_intensity_override >= 0.0:
		_flash_mult = clampf(flash_intensity_override, 0.0, 1.0)
	_playing = true
	_ms = 0.0
	_frame = -1
	_fired.clear()
	phase_log.clear()
	_connect_abort()
	return true


func _flag(name: String, fallback: Variant) -> Variant:
	if _director == null or not is_instance_valid(_director):
		_director = _find_director()
	if _director != null:
		var v: Variant = _director.get(name)
		if v != null:
			return v
	return fallback


func _find_match() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("on_hit") and n.has_signal("phase_changed"):
			return n
		n = n.get_parent()
	return get_tree().get_first_node_in_group("match") if is_inside_tree() else null


func _find_director() -> Node:
	var p := get_parent()
	if p != null and (p.is_in_group("hit_fx_director") or p.has_method("clock_ms")):
		return p
	return get_tree().get_first_node_in_group("hit_fx_director") if is_inside_tree() else null


func _find_hud() -> Node:
	var h: Node = get_tree().get_first_node_in_group("hud")
	if h != null:
		return h
	var roots: Array = []
	if _match != null and _match.get_parent() != null:
		roots.append(_match.get_parent())
	if get_tree().current_scene != null:
		roots.append(get_tree().current_scene)
	for r in roots:
		for c in (r as Node).get_children():
			if c is Hud:
				return c
	return null


func _pick_part(parts: Dictionary, name: String, ctx: Dictionary) -> RigidBody3D:
	if parts.has(name) and parts[name] is RigidBody3D and is_instance_valid(parts[name]):
		return parts[name]
	var pos: Variant = ctx.get("position")
	var best: RigidBody3D = null
	var best_d := INF
	for b in parts.values():
		if not (b is RigidBody3D) or not is_instance_valid(b):
			continue
		var dd := 0.0 if not (pos is Vector3) else (b as RigidBody3D).global_position.distance_to(pos)
		if dd < best_d:
			best_d = dd
			best = b
	return best


## Протяжённость детали на плоскости кукол (XY, м): мировой AABB мешей, иначе отладочных мешей коллизий; нет — 0.
func _part_extent(body: RigidBody3D) -> float:
	var box := _part_world_aabb(body)
	return maxf(box.size.x, box.size.y)


func _part_world_aabb(body: RigidBody3D) -> AABB:
	var box := AABB()
	var have := false
	for mi in _meshes_of(body):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := m.global_transform * m.get_aabb()
		box = b if not have else box.merge(b)
		have = true
	if not have:
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				var dm := (c as CollisionShape3D).shape.get_debug_mesh()
				if dm != null:
					var b := (c as CollisionShape3D).global_transform * dm.get_aabb()
					box = b if not have else box.merge(b)
					have = true
	if not have:
		return AABB(body.global_position, Vector3.ZERO)
	return box


## Полувысота CritCam по детали: протяжённость × CAM_HALF_PER_EXTENT в [CAM_HALF_MIN, CAM_HALF_MAX]; голова/торс — не меньше
## CAM_HALF_MIN_CORE; без AABB — CAM_HALF_HEIGHT.
func _part_half_height(body: RigidBody3D, part_name: String) -> float:
	var ext := _part_extent(body)
	if ext <= 0.01:
		return CAM_HALF_HEIGHT
	var h := clampf(ext * CAM_HALF_PER_EXTENT, CAM_HALF_MIN, CAM_HALF_MAX)
	var base := Doll.part_base_name(part_name)
	if base == "Head" or base == "Torso" or base == "Pelvis":
		h = maxf(h, CAM_HALF_MIN_CORE)
	return h


## Длинная ось детали в пространстве её тела: по AABB мешей, иначе по отладочному мешу коллизии, иначе +Y.
func _grain_axis(body: RigidBody3D) -> Vector3:
	var inv := body.global_transform.affine_inverse()
	var box := AABB()
	var have := false
	for mi in _meshes_of(body):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := (inv * m.global_transform) * m.get_aabb()
		box = b if not have else box.merge(b)
		have = true
	if not have:
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
				var dm := (c as CollisionShape3D).shape.get_debug_mesh()
				if dm != null:
					var b := (inv * (c as CollisionShape3D).global_transform) * dm.get_aabb()
					box = b if not have else box.merge(b)
					have = true
	if not have:
		return Vector3.UP
	var s := box.size
	if s.x >= s.y and s.x >= s.z:
		return Vector3.RIGHT
	if s.z >= s.y:
		return Vector3.BACK
	return Vector3.UP


func _meshes_of(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c.has_meta("hitfx"):
			continue
		if c is MeshInstance3D:
			out.append(c)
		out += _meshes_of(c)
	return out


func _victim_meshes() -> Array:
	var out: Array = []
	if _victim == null or not is_instance_valid(_victim):
		return out
	var parts: Variant = _victim.get("parts")
	if parts is Dictionary:
		for b in (parts as Dictionary).values():
			if b is Node and is_instance_valid(b):
				out += _meshes_of(b)
	return out


# --- кадр ---

func _process(delta: float) -> void:
	var real := delta / maxf(_scale_seen, 1e-4)
	_clock_ms += real * 1000.0
	if _prewarm_frames > 0:
		_prewarm_frames -= 1
		if _prewarm_frames == 0 and not _playing:
			xray_post.visible = false
			(xray_post.get_surface_override_material(0) as ShaderMaterial).set_shader_parameter("intensity", 1.0)
	if _playing:
		if _frame < 0:
			_frame = 0
			_ms = 0.0
			_start()
		else:
			_frame += 1
			_ms += real * 1000.0
		if _playing:
			_step(real)
	_tick_own_time(real)
	_scale_seen = Engine.time_scale


func _due(key: String, at_ms: float) -> bool:
	if _fired.has(key) or _ms + FRAME_HALF_MS < at_ms:
		return false
	_fired[key] = true
	return true


func _emit_phase(name: String) -> void:
	phase_log.append([name, _ms])
	phase.emit(name, _ms)


func _victim_ok() -> bool:
	return _victim != null and is_instance_valid(_victim) and _victim.is_inside_tree() and _part != null and is_instance_valid(_part)


func _start() -> void:
	_fired["freeze"] = true
	var is_ko := bool(_ctx.get("is_ko", false))
	_request_time("crit_freeze", FREEZE_SCALE, FREEZE_MS / 1000.0 + TIME_MARGIN_S)
	_game_cam = _find_game_cam()
	_invert_ok = bool(_flag("impact_frames", Tuning.HITFX_IMPACT_FRAMES)) and _flash_mult > 0.0 and _can_flash()
	if _invert_ok:
		_ensure_mask().pulse(3)
	_hud_cinematic(true)
	if is_ko:
		_defer_ko_card()
	if _victim_ok():
		var kind := String(_ctx.get("kind", "body"))
		var nrm := -_dir
		if _ctx.get("normal") is Vector3 and (_ctx["normal"] as Vector3).length_squared() > 1e-6:
			nrm = _ctx["normal"]
		var host: Node = _victim.get_parent() if _victim.get_parent() != null else get_tree().current_scene
		ImpactFx.spawn_impact(host, _hit_pos, nrm, maxf(float(_ctx.get("speed", 6.0)), 4.0) * IMPACT_MULT, kind)
	if _game_cam != null:
		if _game_cam.has_method("punch"):
			_game_cam.call("punch", _hit_pos, PUNCH_FRAC * _shake_mult, 0.2, FREEZE_MS / 1000.0)
		elif _game_cam.has_method("zoom_impulse") and _shake_mult > 0.0:
			_game_cam.call("zoom_impulse", PUNCH_FRAC * _shake_mult, FREEZE_MS / 1000.0 * FREEZE_SCALE)
	overlay.begin()
	_emit_phase("freeze")


func _step(real: float) -> void:
	if not _victim_ok() and _ms < CUT_OUT_MS:
		abort()
		return
	if _ms >= WATCHDOG_MS:
		abort()
		return
	if _due("cut_in", CUT_IN_MS):
		_cut_in()
	if _due("caption", CAPTION_MS):
		_emit_phase("caption")
	if _due("crack_1", CRACK_1_MS):
		_set_decal_stage(1)
	if _due("crack_2", CRACK_2_MS):
		_crack_2()
	if _due("cut_out", CUT_OUT_MS):
		_cut_out()
	if _due("ko_card", KO_CARD_MS):
		_ko_card_show()
	if _due("done", TOTAL_MS):
		_finish()
		return
	_update_close_up(real)
	_update_overlay()
	_update_decal()


func _cut_in() -> void:
	_cancel_time("crit_freeze")
	_request_time("crit_xray", XRAY_SCALE, XRAY_MS / 1000.0 + TIME_MARGIN_S)
	if _victim_ok():
		_aim = _part.to_global(_hit_local * 0.5)
		_place_cam(0.0)
		_copy_cam_settings()
		_capture_cam()
		var xm := xray_post.get_surface_override_material(0) as ShaderMaterial
		xm.set_shader_parameter("intensity", 1.0)
		var mk := _ensure_mask()
		mk.hold(MASK_KEY)
		xm.set_shader_parameter("mask_tex", mk.texture())
		xm.set_shader_parameter("use_mask", 1.0)
		xray_post.visible = true
		_apply_overlays()
		_make_decal()
		_emit_splinters(splinters, _hit_pos, _dir)
		_hide_flashes_near(_hit_pos)
	_emit_phase("cut_in")


## Новый план — без вспышек ImpactFlash удара: в стоп-кадре они не гаснут и в крупном плане закрыли бы деталь.
## Узлы чужие и живут доли секунды — только visible = false, освобождает их ImpactFx.
func _hide_flashes_near(pos: Vector3) -> void:
	var hosts: Array = []   # DollCombat кладёт ImpactFx под Match, мы — рядом с куклой
	if _match != null and is_instance_valid(_match):
		hosts.append(_match)
	if _victim != null and is_instance_valid(_victim) and _victim.get_parent() != null:
		hosts.append(_victim.get_parent())
	for host in hosts:
		for fx in (host as Node).get_children():
			if not (fx is Node3D) or fx is Doll:
				continue
			if (fx as Node3D).global_position.distance_to(pos) > FLASH_HIDE_RADIUS_M:
				continue
			for c in fx.get_children():
				if c is ImpactFlash:
					(c as Node3D).visible = false


func _crack_2() -> void:
	_set_decal_stage(2)
	if _victim_ok():
		_emit_splinters(splinters_2, _part.global_position, _dir)
	_emit_phase("crack_2")


func _cut_out() -> void:
	_cut_flash_pending = _flash_mult > 0.0 and _can_flash()
	xray_post.visible = false
	_release_mask()
	_restore_overlays()
	_release_cam()
	_cancel_time("crit_xray")
	if bool(_ctx.get("is_ko", false)):
		_request_time("ko_crit_slowmo", Tuning.KO_SLOWMO_SCALE, KO_CRIT_SLOWMO_S)
	else:
		_request_time("crit_slowmo", Tuning.CRIT_SLOWMO_SCALE, Tuning.CRIT_SLOWMO_S)
	var cam := _find_game_cam()
	if cam != null and _victim_ok() and _shake_mult > 0.0:
		if cam.has_method("focus"):
			var hold := HitFxDirector.crit_hold_s(String(_ctx.get("tier", "crit")), true)
			cam.call("focus", _victim, OUT_FOCUS_WEIGHT * _shake_mult, hold / (1.0 - DynamicCamera.FOCUS_OUT_FRAC))
		if cam.has_method("roll_kick"):
			cam.call("roll_kick", OUT_ROLL_DEG * _shake_mult * (-signf(_dir.x) if absf(_dir.x) > 0.01 else 1.0), 0.3)
	_emit_phase("cut_out")
	_emit_phase("slowmo")


func _finish() -> void:
	_emit_phase("done")
	var ctx := _ctx
	played.append({"tier": String(ctx.get("tier", "crit")), "ms": _ms})
	_cleanup(false)
	finished.emit(ctx)


## Прерывание: время, камера, оверлеи, Decal, HUD — всё возвращается сразу.
func abort() -> void:
	if not _playing:
		return
	var ctx := _ctx
	_cleanup(true)
	aborted.emit(ctx)


func _release_mask() -> void:
	if _mask != null and is_instance_valid(_mask):
		_mask.release(MASK_KEY)
	var xm := xray_post.get_surface_override_material(0) as ShaderMaterial
	if xm != null:
		xm.set_shader_parameter("use_mask", 0.0)


func _cleanup(hard: bool) -> void:
	_playing = false
	_disconnect_abort()
	xray_post.visible = false
	_release_mask()
	_restore_overlays()
	_release_cam()
	for t in ["crit_freeze", "crit_xray", "crit_slowmo"]:
		_cancel_time(t)
	if hard:
		_cancel_time("ko_crit_slowmo")
	if _decal != null and is_instance_valid(_decal):
		_decal.queue_free()
	_decal = null
	_decal_stage = -1
	for mi in _layer_added:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).layers &= ~DOLL_LAYER_BIT
	_layer_added.clear()
	overlay.reset()
	_hud_cinematic(false)
	if _ko_card_fallback != null and is_instance_valid(_ko_card_fallback) and not _fired.has("ko_card") and not hard:
		_ko_card_show()
	_ko_card_fallback = null
	_ctx = {}
	_victim = null
	_attacker = null
	_part = null


# --- крупный план ---

func _place_cam(t: float) -> void:
	var dist := _half_h / tan(deg_to_rad(CAM_FOV) * 0.5) * (1.0 - CAM_PUSH_IN * _shake_mult * t)
	var side := signf(_dir.x) if absf(_dir.x) > 0.01 else 1.0
	var drift := _dir * CAM_DRIFT_M * _shake_mult * t
	var off := Basis(Vector3.UP, deg_to_rad(CAM_YAW_DEG * side)) * Basis(Vector3.RIGHT, deg_to_rad(CAM_PITCH_DEG)) * Vector3(0.0, 0.0, dist)
	var target := _aim + drift - Vector3.UP * (_half_h * 2.0 * CAM_COMPOSE_UP)
	var pos := target + off
	var b := Basis.looking_at(target - pos, Vector3.UP)
	var e := 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
	b = b * Basis(Vector3.BACK, deg_to_rad(CAM_ROLL_DEG * _shake_mult * e * -side))
	crit_cam.global_transform = Transform3D(b, pos)


func _update_close_up(real: float) -> void:
	if not _cam_captured or not _victim_ok():
		return
	var aim_now := _part.to_global(_hit_local * 0.5)
	_aim = _aim.lerp(aim_now, 1.0 - exp(-real / CAM_LAG_S))
	_place_cam(clampf((_ms - CUT_IN_MS) / XRAY_MS, 0.0, 1.0))
	var xf := (xray_post.get_surface_override_material(0) as ShaderMaterial)
	xf.set_shader_parameter("flash", _pulse(XRAY_FLASH_MS))
	_wood_mat.set_shader_parameter("world_to_part", Projection(_part.global_transform.affine_inverse()))
	_wood_mat.set_shader_parameter("reveal", clampf((_ms - SCREEN_CRACK_MS.x) / (SCREEN_CRACK_MS.y - SCREEN_CRACK_MS.x), 0.0, 1.0))
	_wood_mat.set_shader_parameter("flash", _pulse(XRAY_FLASH_MS) * 1.5)


func _pulse(win: Vector2) -> float:
	if _ms < win.x or _ms > win.y:
		return 0.0
	return 1.0 - (_ms - win.x) / (win.y - win.x)


func _copy_cam_settings() -> void:
	var g := _find_game_cam()
	if g == null:
		return
	crit_cam.cull_mask = g.cull_mask
	crit_cam.environment = g.environment
	crit_cam.attributes = g.attributes
	crit_cam.compositor = g.compositor


func _find_game_cam() -> Camera3D:
	if _match != null and is_instance_valid(_match):
		if _match.has_method("game_camera"):
			var c: Variant = _match.call("game_camera")
			if c is Camera3D:
				return c
		if _match.has_method("_camera"):
			var c2: Variant = _match.call("_camera")
			if c2 is Camera3D and c2 != crit_cam:
				return c2
	var g := get_tree().get_first_node_in_group("camera")
	if g is Camera3D:
		return g
	if _game_cam != null and is_instance_valid(_game_cam):
		return _game_cam
	return null


func _capture_cam() -> void:
	_prev_cam = get_viewport().get_camera_3d()
	if _prev_cam == crit_cam:
		_prev_cam = null
	if _match != null and is_instance_valid(_match) and _match.has_method("capture_camera"):
		_match.call("capture_camera", crit_cam, "crit")
	else:
		crit_cam.make_current()
	_cam_captured = true


func _release_cam() -> void:
	if not _cam_captured:
		return
	_cam_captured = false
	if _match != null and is_instance_valid(_match) and _match.has_method("release_camera"):
		_match.call("release_camera", "crit")
	if get_viewport() != null and get_viewport().get_camera_3d() == crit_cam:
		var back := _find_game_cam()
		if back == null and _prev_cam != null and is_instance_valid(_prev_cam):
			back = _prev_cam
		if back != null and back.is_inside_tree():
			back.make_current()
		else:
			crit_cam.clear_current(true)
	crit_cam.current = false
	_prev_cam = null


func _apply_overlays() -> void:
	_ensure_materials()
	_wood_mat.set_shader_parameter("grain_axis", _grain_local)
	_wood_mat.set_shader_parameter("hit_local", _hit_local)
	var view_local := (_part.global_basis.inverse() * Vector3.BACK).normalized()
	var pv := _grain_local.cross(view_local)
	if pv.length_squared() < 1e-4:
		pv = _grain_local.cross(Vector3.RIGHT if absf(_grain_local.x) < 0.9 else Vector3.UP)
	_wood_mat.set_shader_parameter("proj_u", _grain_local)
	_wood_mat.set_shader_parameter("proj_v", pv.normalized())
	_wood_mat.set_shader_parameter("world_to_part", Projection(_part.global_transform.affine_inverse()))
	_wood_mat.set_shader_parameter("reveal", 0.0)
	var parts: Dictionary = _victim.get("parts")
	for b in parts.values():
		if not (b is Node) or not is_instance_valid(b):
			continue
		for mi in _meshes_of(b):
			var m := mi as MeshInstance3D
			if _saved_overlay.has(m):
				continue
			_saved_overlay[m] = m.material_overlay
			m.material_overlay = _wood_mat if b == _part else _ghost_mat
	# v3: атакующий в рентгене затемнён — «кость» ломается у жертвы
	attacker_dimmed = 0
	if _attacker != null and is_instance_valid(_attacker):
		var ap: Variant = _attacker.get("parts")
		if ap is Dictionary:
			for b in (ap as Dictionary).values():
				if not (b is Node) or not is_instance_valid(b):
					continue
				for mi in _meshes_of(b):
					var m := mi as MeshInstance3D
					if _saved_overlay.has(m):
						continue
					_saved_overlay[m] = m.material_overlay
					m.material_overlay = _dim_mat
					attacker_dimmed += 1


func _restore_overlays() -> void:
	for m in _saved_overlay.keys():
		if is_instance_valid(m):
			(m as MeshInstance3D).material_overlay = _saved_overlay[m]
	_saved_overlay.clear()
	attacker_dimmed = 0


func _make_decal() -> void:
	for mi in _victim_meshes():
		var m := mi as MeshInstance3D
		if m.layers & DOLL_LAYER_BIT == 0:
			m.layers |= DOLL_LAYER_BIT
			_layer_added.append(m)
	var d := Decal.new()
	d.name = "CritCrackDecal"
	d.set_meta("hitfx", true)
	d.size = Vector3(DECAL_SIZE, DECAL_DEPTH, DECAL_SIZE)
	d.cull_mask = DOLL_LAYER_BIT
	d.normal_fade = 0.25
	d.emission_energy = DECAL_GLOW
	_part.add_child(d)
	var gw := _part.global_basis * _grain_local
	gw.z = 0.0
	if gw.length_squared() < 1e-4:
		gw = Vector3(-_dir.y, _dir.x, 0.0)
	var x := gw.normalized()
	var y := Vector3.BACK
	var z := x.cross(y)
	d.global_transform = Transform3D(Basis(x, y, z), _hit_pos)
	_decal = d
	_set_decal_stage(0)


func _set_decal_stage(s: int) -> void:
	if _decal == null or not is_instance_valid(_decal) or s == _decal_stage:
		return
	_decal_stage = s
	_decal.texture_albedo = CRACK_DECAL[s]
	_decal.texture_emission = CRACK_GLOW[s]


func _update_decal() -> void:
	if _decal == null or not is_instance_valid(_decal):
		return
	var glow := 1.0 - clampf((_ms - DECAL_GLOW_FADE_MS.x) / (DECAL_GLOW_FADE_MS.y - DECAL_GLOW_FADE_MS.x), 0.0, 1.0)
	_decal.emission_energy = DECAL_GLOW * glow * (1.0 + _pulse(XRAY_FLASH_MS))
	var a := 1.0 - clampf((_ms - DECAL_FADE_MS.x) / (DECAL_FADE_MS.y - DECAL_FADE_MS.x), 0.0, 1.0)
	_decal.modulate = Color(1.0, 1.0, 1.0, a)


func _emit_splinters(p: GPUParticles3D, pos: Vector3, dir: Vector3) -> void:
	var dd := dir if dir.length_squared() > 1e-6 else Vector3.UP
	var up := Vector3.UP if absf(dd.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	p.global_transform = Transform3D(Basis.looking_at(-dd.normalized(), up), pos)
	p.restart()
	p.emitting = true


# --- экранный слой ---

func _update_overlay() -> void:
	var inv := 0
	if _invert_ok and _ms < INVERT_MS - FRAME_HALF_MS:
		inv = 1 if _frame == 0 else 2
	var flash := 0.0
	if _cut_flash_pending:
		_cut_flash_pending = false   # ровно один кадр — кадр ката
		flash = CUT_FLASH_ALPHA * _flash_mult
	var edge := 0.0
	if _flash_mult > 0.0 and _ms >= EDGE_FADE_MS.x - FRAME_HALF_MS and _ms < EDGE_FADE_MS.y:
		edge = EDGE_ALPHA * _flash_mult * (1.0 - (_ms - EDGE_FADE_MS.x) / (EDGE_FADE_MS.y - EDGE_FADE_MS.x))
	overlay.set_screen(inv, flash, clampf(edge, 0.0, 1.0))
	var lb := 0.0
	if _ms < LETTERBOX_OUT_MS.x:
		lb = clampf((_ms - LETTERBOX_IN_MS.x) / (LETTERBOX_IN_MS.y - LETTERBOX_IN_MS.x), 0.0, 1.0)
	else:
		lb = 1.0 - clampf((_ms - LETTERBOX_OUT_MS.x) / (LETTERBOX_OUT_MS.y - LETTERBOX_OUT_MS.x), 0.0, 1.0)
	overlay.set_letterbox(lb * lb * (3.0 - 2.0 * lb))
	if _cam_captured and _victim_ok():
		var c := overlay.to_overlay(crit_cam.unproject_position(_part.to_global(_hit_local)))
		overlay.set_crack(c, clampf((_ms - SCREEN_CRACK_MS.x) / (SCREEN_CRACK_MS.y - SCREEN_CRACK_MS.x), 0.02, 1.0), 1.0)
	else:
		overlay.set_crack(Vector2.ZERO, 0.0, 0.0)
	_update_marker()
	_update_bg_dim()
	if _fired.has("caption"):
		var since := _ms - CAPTION_MS
		var shake := Vector2.ZERO
		var sh_t := since - CAPTION_IN_MS
		if sh_t >= 0.0 and sh_t < CAPTION_SHAKE_MS:
			var k := 1.0 - sh_t / CAPTION_SHAKE_MS
			shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * CAPTION_SHAKE_PX * k
		if _caption_y < 0.0:
			_caption_y = _pick_caption_slot()
		var a := 1.0 - clampf((_ms - CAPTION_FADE_MS.x) / (CAPTION_FADE_MS.y - CAPTION_FADE_MS.x), 0.0, 1.0)
		var y := _caption_y
		var sc_mult := 1.0
		if _fired.has("cut_out"):
			# кат назад — жёсткая смена плана: надпись встаёт в полосу над жертвой в игровой камере (не поверх кукол),
			# уезжает вверх на CAPTION_OUT_RISE, сжимается до CAPTION_OUT_SCALE и гаснет к CAPTION_FADE_MS.y
			if _caption_out_y < 0.0:
				_caption_out_y = _pick_caption_out_slot()
			var out_k := clampf((_ms - CAPTION_OUT_MS.x) / (CAPTION_OUT_MS.y - CAPTION_OUT_MS.x), 0.0, 1.0)
			var eo := 1.0 - (1.0 - out_k) * (1.0 - out_k)
			y = _caption_out_y - CAPTION_OUT_RISE * eo
			sc_mult = lerpf(CAPTION_OUT_SCALE_FROM, CAPTION_OUT_SCALE, eo)
		overlay.set_caption(since, a, shake, CAPTION_IN_MS, y, sc_mult)
	var sl := 0.0
	if speed_lines_enabled and _ms >= SPEED_LINES_MS.x and _ms < SPEED_LINES_MS.y and _victim != null and is_instance_valid(_victim):
		var cam := get_viewport().get_camera_3d()
		if cam != null and cam != crit_cam and _victim.has_method("centre_of_mass"):
			var u := (_ms - SPEED_LINES_MS.x) / (SPEED_LINES_MS.y - SPEED_LINES_MS.x)
			sl = sin(u * PI)
			overlay.set_speed_lines(overlay.to_overlay(cam.unproject_position(_victim.call("centre_of_mass"))), sl, u)
	if sl <= 0.0:
		overlay.set_speed_lines(Vector2.ZERO, 0.0, 0.0)


## v3: маркер точки удара MARKER_MS — кольцо растёт MARKER_R, гаснет; точка — в игровой камере до ката, в CritCam после.
func _update_marker() -> void:
	if _ms < MARKER_MS.x - FRAME_HALF_MS or _ms > MARKER_MS.y or not _victim_ok():
		overlay.set_marker(Vector2.ZERO, 0.0, 0.0, 0.0)
		return
	var p := _part.to_global(_hit_local)
	var cam: Camera3D = crit_cam if _cam_captured else get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(p):
		overlay.set_marker(Vector2.ZERO, 0.0, 0.0, 0.0)
		return
	_marker_pos = overlay.to_overlay(cam.unproject_position(p))
	var u := clampf((_ms - MARKER_MS.x) / (MARKER_MS.y - MARKER_MS.x), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 3.0)
	overlay.set_marker(_marker_pos, lerpf(MARKER_R.x, MARKER_R.y, e), 1.0 - u * u, u)
	marker_frames += 1


## v3: замедление после ката — фон вокруг жертвы темнеет (BG_DIM), жертва в чистом круге; к концу замедления гаснет.
func _update_bg_dim() -> void:
	var slow_ms := (KO_CRIT_SLOWMO_S if bool(_ctx.get("is_ko", false)) else Tuning.CRIT_SLOWMO_S) * 1000.0
	var t0 := CUT_OUT_MS
	var t1 := CUT_OUT_MS + slow_ms
	var cam := get_viewport().get_camera_3d()
	if _ms < t0 or _ms > minf(t1, TOTAL_MS) or cam == null or cam == crit_cam or _victim == null or not is_instance_valid(_victim) \
			or not _victim.has_method("centre_of_mass"):
		overlay.set_bg_dim(Vector2.ZERO, 0.0, 0.0)
		return
	var k := minf(clampf((_ms - t0) / BG_DIM_IN_MS, 0.0, 1.0), clampf((minf(t1, TOTAL_MS) - _ms) / BG_DIM_OUT_MS, 0.0, 1.0))
	var r := _screen_rect(cam, _victim)
	var area := overlay.area()
	var centre := Vector2((r.position.x + r.size.x * 0.5) * area.x, (r.position.y + r.size.y * 0.5) * area.y)
	var radius := maxf(r.size.x * area.x, r.size.y * area.y) * 0.6 + 60.0
	overlay.set_bg_dim(centre, BG_DIM * k, radius)
	if k > 0.0:
		bg_dim_frames += 1


## Прямоугольник куклы на экране cam (доли кадра, y сверху): углы AABB мешей её частей; без мешей — позиции частей ± 0.3 м.
func _screen_rect(cam: Camera3D, doll: Node3D) -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	if cam == null or doll == null or not is_instance_valid(doll) or vs.x <= 1.0 or vs.y <= 1.0:
		return Rect2()
	var parts: Variant = doll.get("parts")
	if not (parts is Dictionary):
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b in (parts as Dictionary).values():
		if not (b is Node3D) or not is_instance_valid(b):
			continue
		var boxes: Array = []
		for mi in _meshes_of(b):
			var m := mi as MeshInstance3D
			if m.mesh != null:
				boxes.append(m.global_transform * m.get_aabb())
		if boxes.is_empty():
			boxes.append(AABB((b as Node3D).global_position - Vector3.ONE * 0.3, Vector3.ONE * 0.6))
		for bx in boxes:
			for i in range(8):
				var c := (bx as AABB).get_endpoint(i)
				if cam.is_position_behind(c):
					continue
				var p := cam.unproject_position(c) / vs
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	if lo.x > hi.x:
		return Rect2()
	return Rect2(lo, hi - lo)


## Доля полосы надписи (центр y, x — CAPTION_HALF_W × scale), закрытая прямоугольником r (доли кадра).
static func _caption_cover(y: float, r: Rect2, scale_k: float = 1.0, rise: float = 0.0) -> float:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return 0.0
	var band := Rect2(0.5 - CAPTION_HALF_W * scale_k, y - CAPTION_HALF_H * scale_k - rise, CAPTION_HALF_W * scale_k * 2.0, CAPTION_HALF_H * scale_k * 2.0 + rise)
	var ov := band.intersection(r)
	if ov.size.x <= 0.0 or ov.size.y <= 0.0:
		return 0.0
	return ov.get_area() / band.get_area()


## Полоса надписи: та из CAPTION_SLOTS, что меньше перекрывает ударенную деталь на экране CritCam (при равенстве — первая, низ).
## v3: при равном перекрытии детали — меньше перекрывает атакующего; обе основные закрыты — запасная CAPTION_EXTRA_SLOTS.
func _pick_caption_slot() -> float:
	var slot: float = CAPTION_SLOTS[0]
	if not _cam_captured or not _victim_ok():
		caption_slot = slot
		return slot
	var box := _part_world_aabb(_part)
	var vs := get_viewport().get_visible_rect().size
	if vs.y <= 1.0:
		caption_slot = slot
		return slot
	var y0 := INF
	var y1 := -INF
	for i in range(8):
		var c := box.get_endpoint(i)
		if crit_cam.is_position_behind(c):
			continue
		var py := crit_cam.unproject_position(c).y / vs.y
		y0 = minf(y0, py)
		y1 = maxf(y1, py)
	var hp := crit_cam.unproject_position(_part.to_global(_hit_local)).y / vs.y
	y0 = minf(y0, hp)
	y1 = maxf(y1, hp)
	part_screen_span = Vector2(y0, y1)
	var best := INF
	for sv in CAPTION_SLOTS:
		var s_y: float = sv
		var ov := maxf(0.0, minf(y1, s_y + CAPTION_BAND) - maxf(y0, s_y - CAPTION_BAND))
		ov += ATTACKER_WEIGHT * _caption_cover(s_y, _screen_rect(crit_cam, _attacker)) * CAPTION_BAND
		if ov < best - 1e-4:
			best = ov
			slot = s_y
	if best > 1e-3:
		for sv in CAPTION_EXTRA_SLOTS:
			var s_y: float = sv
			var ov := maxf(0.0, minf(y1, s_y + CAPTION_BAND) - maxf(y0, s_y - CAPTION_BAND))
			ov += ATTACKER_WEIGHT * _caption_cover(s_y, _screen_rect(crit_cam, _attacker)) * CAPTION_BAND
			if ov < best * 0.5:
				best = ov
				slot = s_y
	caption_slot = slot
	return slot


## Полоса надписи после ката: над жертвой (CAPTION_OUT_SLOTS[0]), если жертва в игровой камере не в верхней трети; иначе под ней.
## v3: из CAPTION_OUT_CANDIDATES — полоса с наименьшим перекрытием обеих кукол (с учётом уезда вверх и сжатия); при равенстве — v2-правило.
func _pick_caption_out_slot() -> float:
	var slot: float = CAPTION_OUT_SLOTS[0]
	var cam := get_viewport().get_camera_3d()
	var vs := get_viewport().get_visible_rect().size
	if cam != null and cam != crit_cam and _victim != null and is_instance_valid(_victim) and _victim.has_method("centre_of_mass") and vs.y > 1.0:
		var p: Vector3 = _victim.call("centre_of_mass")
		if not cam.is_position_behind(p) and cam.unproject_position(p).y / vs.y < 0.36:
			slot = CAPTION_OUT_SLOTS[1]
		var rects: Array = [_screen_rect(cam, _victim)]
		if _attacker != null and is_instance_valid(_attacker):
			rects.append(_screen_rect(cam, _attacker))
		var cover := func(y: float) -> float:
			var c := 0.0
			for r in rects:
				c += _caption_cover(y, r, CAPTION_OUT_SCALE_FROM, CAPTION_OUT_RISE)
			return c
		var best: float = cover.call(slot)
		for cv in CAPTION_OUT_CANDIDATES:
			var y: float = cv
			var c: float = cover.call(y)
			if c < best - 0.02:
				best = c
				slot = y
		caption_overlap = best
	caption_out_slot = slot
	return slot


func _can_flash() -> bool:
	if _director != null and is_instance_valid(_director) and _director.has_method("can_flash"):
		return bool(_director.call("can_flash"))
	var i := 0
	while i < _flash_times.size():
		if _clock_ms - float(_flash_times[i]) > 1000.0:
			_flash_times.remove_at(i)
		else:
			i += 1
	if _flash_times.size() >= Tuning.HITFX_MAX_FLASHES_PER_S:
		return false
	_flash_times.append(_clock_ms)
	return true


# --- HUD ---

func _hud_cinematic(on: bool) -> void:
	if _hud == null or not is_instance_valid(_hud):
		_hud_hidden.clear()
		return
	if _hud.has_method("set_cinematic"):
		_hud.call("set_cinematic", on)
		return
	if on:
		_hud_hidden.clear()
		for path in ["Root/Players", "Root/TimerBox", "Root/Announcer"]:
			var n := _hud.get_node_or_null(path) as CanvasItem
			if n != null:
				_hud_hidden.append([n, n.visible])
				n.visible = false
	else:
		for e in _hud_hidden:
			if is_instance_valid(e[0]):
				(e[0] as CanvasItem).visible = bool(e[1])
		_hud_hidden.clear()
		var ann: Variant = _hud.get("announcer")
		if ann is Node and (ann as Node).has_method("clear"):
			(ann as Node).call("clear")


func _defer_ko_card() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	if _hud.has_method("defer_ko_card"):
		_hud.call("defer_ko_card", KO_CARD_DEFER_S)
		return
	var kc: Variant = _hud.get("ko_card")
	if kc is Node and (kc as Node).has_method("defer"):
		(kc as Node).call("defer", KO_CARD_DEFER_S)
		return
	if kc is CanvasItem and (kc as CanvasItem).visible:
		(kc as CanvasItem).visible = false   # запасной путь: карточка вернётся на KO_CARD_MS
		_ko_card_fallback = kc


func _ko_card_show() -> void:
	var kc := _ko_card_fallback
	_ko_card_fallback = null
	if kc == null or not is_instance_valid(kc) or not kc.has_method("show_card"):
		return
	var idx := int(_victim.get("player_index")) if _victim != null and is_instance_valid(_victim) and _victim.get("player_index") != null else -1
	var colour: Color = Tuning.PLAYER_COLORS[clampi(idx, 0, Tuning.PLAYER_COLORS.size() - 1)] if idx >= 0 else Color.WHITE
	kc.call("show_card", "P%d" % (idx + 1) if idx >= 0 else "", colour)


# --- прерывание ---

func _connect_abort() -> void:
	_disconnect_abort()
	if _match != null and is_instance_valid(_match):
		_link(_match, "phase_changed", _on_phase_changed)
		_link(_match, "doll_replaced", _on_doll_replaced)
	if _victim != null:
		_link(_victim, "tree_exiting", abort)


func _link(obj: Object, sig: String, cb: Callable) -> void:
	if obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)
		_signals.append([obj, sig, cb])


func _disconnect_abort() -> void:
	for e in _signals:
		var o: Object = e[0]
		if is_instance_valid(o) and o.is_connected(String(e[1]), e[2]):
			o.disconnect(String(e[1]), e[2])
	_signals.clear()


func _on_phase_changed(p: int) -> void:
	if p == Match.Phase.COUNTDOWN or (p == Match.Phase.OVER and not bool(_ctx.get("is_ko", false))):
		abort()


func _on_doll_replaced(old_doll: Node, _new_doll: Node) -> void:
	if old_doll == _victim:
		abort()


# --- время ---

func _request_time(tag: String, scale: float, real_s: float) -> void:
	var s := maxf(scale, Tuning.HITFX_TIME_SCALE_MIN)
	if _match != null and is_instance_valid(_match):
		if _match.has_method("request_time_scale"):
			_match.call("request_time_scale", s, real_s, tag)
			return
		if _match.get("feel_enabled") == false:
			return
		var fx: Variant = _match.get("_time_effects")
		if fx is Array:
			_erase_tag(fx as Array, tag)
			(fx as Array).append({"scale": s, "left": real_s, "tag": tag})
			Engine.time_scale = minf(Engine.time_scale, s)
			return
	_own_time[tag] = {"scale": s, "left": real_s}
	_apply_own_time()


func _cancel_time(tag: String) -> void:
	if _own_time.has(tag):
		_own_time.erase(tag)
		_apply_own_time()
	if _match == null or not is_instance_valid(_match):
		return
	if _match.has_method("cancel_time_scale"):
		_match.call("cancel_time_scale", tag)
		return
	var fx: Variant = _match.get("_time_effects")
	if fx is Array and _erase_tag(fx as Array, tag):
		var sc := 1.0
		for e in fx:
			sc = minf(sc, float((e as Dictionary).get("scale", 1.0)))
		Engine.time_scale = sc


func _erase_tag(fx: Array, tag: String) -> bool:
	var hit := false
	var i := 0
	while i < fx.size():
		if fx[i] is Dictionary and String((fx[i] as Dictionary).get("tag", "")) == tag:
			fx.remove_at(i)
			hit = true
		else:
			i += 1
	return hit


func _tick_own_time(real: float) -> void:
	if _own_time.is_empty():
		return
	for tag in _own_time.keys():
		var e: Dictionary = _own_time[tag]
		e["left"] = float(e["left"]) - real
		if float(e["left"]) <= 0.0:
			_own_time.erase(tag)
	_apply_own_time()


func _apply_own_time() -> void:
	var sc := 1.0
	for e in _own_time.values():
		sc = minf(sc, float((e as Dictionary)["scale"]))
	Engine.time_scale = sc


func _restore_time_all() -> void:
	if not _own_time.is_empty():
		_own_time.clear()
		Engine.time_scale = 1.0


## Теги времени этого кинематографа, которые сейчас стоят (для проб): Match.time_scale_tags() или записи _time_effects.
func active_time_tags() -> Array:
	var out: Array = []
	var all: Array = []
	if _match != null and is_instance_valid(_match):
		if _match.has_method("time_scale_tags"):
			all = _match.call("time_scale_tags")
		else:
			var fx: Variant = _match.get("_time_effects")
			if fx is Array:
				for e in fx:
					if e is Dictionary and (e as Dictionary).has("tag"):
						all.append(String(e["tag"]))
	all += _own_time.keys()
	for t in all:
		if TAGS.has(String(t)) and not out.has(String(t)):
			out.append(String(t))
	return out


## Узлы, которые кинематограф держит сверх своей сцены (проба утечек): Decal + сохранённые оверлеи.
func fx_node_count() -> int:
	return (1 if _decal != null and is_instance_valid(_decal) else 0) + _saved_overlay.size()


## Подключение без директора: экземпляр под parent (Match или площадка), подписка на Match.hit_fx (tier crit / ko_crit).
static func attach(parent: Node, match_node: Node = null) -> CritCinematic:
	var cc := (load("res://scenes/fx/crit_cinematic.tscn") as PackedScene).instantiate() as CritCinematic
	parent.add_child(cc)
	if match_node != null and match_node.has_signal("hit_fx"):
		match_node.connect("hit_fx", func(ctx: Dictionary) -> void:
			var tier := String(ctx.get("tier", ""))
			if tier == "crit" or tier == "ko_crit":
				cc.play(ctx))
	return cc
