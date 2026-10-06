## KO-камера и мини-повтор (проход по картинке, docs/plan-demo/look/cam.md). Ребёнок Match обычного боя — ставит автозагрузка
## LookCam (scripts/look/look_cam.gd); сам Match и камера боя не правятся: время — Match.request_time_scale с тегом "ko_cam", камера —
## Match.capture_camera(cam, "ko_cam") / release_camera, HUD — set_cinematic и defer_ko_card (как крит-кино, HIT_FX.md §3.3).
##
## Когда: последний нокаут обычного боя (после него живых ≤ 1), не ko_crit (у него своё кино), feel_enabled, пресет FX не «выкл»,
## камеру никто не держит. Решает отложенный вызов после сигнала Match.ko — к нему удар уже разобран (hit_fx, крит-кино).
## Таймлайн (реальные секунды, часы FxClock — замедление их не растягивает, пауза Esc останавливает):
##   0      hold   — стоп-кадр: время ×TIME_SCALE (детали висят в воздухе), кадр ещё игровой, HUD прячется (set_cinematic, прочие
##                   экранные слои площадки — подсказки, панели L / Tab, стрелки — тоже),
##                   карточка KO откладывается на всё кино; леттербокс и табло «KO · P2 · IMPACT 18.4G» (HitJuice.impact_caption);
##   0.14   orbit  — своя камера выходит из боковой плоскости: облёт побеждённого по дуге за ORBIT_S на угол по арене (купол 50°,
##                   Void 45°, 2.5D-арены 26° — у них задник плоский, ORBIT_YAW_BY_ARENA) в сторону от победителя (он в глубине
##                   кадра), с подъёмом (у пола — сверху, в воздухе — снизу); центр кадра переезжает на побеждённого, радиус и fov
##                   чуть сжимаются, лёгкий DOF на фоне (если пресет графики его разрешает);
##   1.64   replay — (пункт «Повтор», не в кампании) копии мешей кукол проигрывают последние REPLAY_BACK_S игрового времени до KO
##                   с другой стороны и снизу, быстро → замедление к удару, плашка «ПОВТОР»; настоящие куклы и следы эффектов
##                   спрятаны, мир стоит; Enter / пробел / клик — пропустить;
##   конец  back   — щелчок назад: игровая камера, время отпущено с коротким замедлением (тег ko_cam_out) — детали разлетаются,
##                   HUD вернулся, карточка KO и итоги — как раньше.
## Выключенный пункт «ВИД» (cam_ko / cam_replay) — этой части нет; оба выключены — бой ровно как раньше.
## Прерывание: restart (COUNTDOWN), выход из дерева, сторож. Запись повтора — каждый игровой 1/60 с, только пока идёт бой.
class_name KoCam
extends Node3D

signal stage_changed(stage: String)   # "hold" | "orbit" | "replay" | "back" | "abort"

const TAG := "ko_cam"
const ID_KO := &"cam_ko"            # пункты «ВИД» (LookCam)
const ID_REPLAY := &"cam_replay"
const TAG_OUT := "ko_cam_out"
const TIME_SCALE := 0.03
const HOLD_S := 0.14
const ORBIT_S := 1.5
const ORBIT_YAW_DEG := 50.0           # купол — круглый зал, трибуны со всех сторон
## Угол облёта по арене: у 2.5D-арен задник — плоская панорама, на 50° виден её край (Руины); Void — пустота, смотреть можно с любой
## стороны. Нет в списке — ORBIT_YAW_OTHER_DEG.
const ORBIT_YAW_BY_ARENA := {"NullHallArena": 50.0, "VoidArena": 45.0}
const ORBIT_YAW_OTHER_DEG := 26.0
const ORBIT_PITCH_DEG := 12.0
const ORBIT_RADIUS_K := 0.66          # конечный радиус = дистанция игровой камеры × это …
const ORBIT_RADIUS := Vector2(4.2, 10.0)   # … в этих пределах (м)
const ORBIT_FOV_K := 0.85             # fov в конце облёта = игровой × это (фон «подходит»)
const TARGET_LEAD_U := 0.5            # к этой доле облёта центр кадра уже на побеждённом
const LOW_PIVOT_M := 2.5              # побеждённый ниже (от пола) — камера поднимается и смотрит сверху, выше — снизу
const FLOOR_CLEAR_M := 0.45
const OUT_SLOW_SCALE := 0.35
const OUT_SLOW_S := 0.7
const DOF_AMOUNT := 0.035
const DOF_BEHIND_M := 2.5
const WATCHDOG_PAD_S := 3.0
const SKIP_AFTER_S := 0.3
# --- повтор ---
const REC_DT := 1.0 / 60.0
const REC_KEEP_S := 2.2
const REPLAY_BACK_S := 1.4
const REPLAY_MIN_FRAMES := 12
const REPLAY_SPEED_FAST := 0.75
const REPLAY_SPEED_SLOW := 0.22
const REPLAY_SLOW_FROM_S := 0.42      # за столько игровых секунд до KO скорость начинает падать …
const REPLAY_SLOW_FULL_S := 0.12      # … и к этому моменту она SLOW
const REPLAY_HOLD_S := 0.3
const REPLAY_YAW_DEG := 30.0
const REPLAY_PITCH_DEG := 8.0         # камера ниже бойцов — снизу вверх
const REPLAY_FOV := 34.0
const REPLAY_RADIUS := Vector2(3.4, 13.0)
const REPLAY_MARGIN_M := 1.4
const REPLAY_FOLLOW_TAU := 0.22

var match_node: Match
var cam: Camera3D
var overlay: KoCamOverlay
var playing := false
var stage := ""
## Пробы: сколько раз кино стартовало / дошло до конца, копий в повторе, длительность плана (реальные с).
var plays := 0
var completed := 0
var ghost_count := 0
var planned_s := 0.0
var elapsed_s := 0.0

var _pending := false
var _t := 0.0
var _victim: Doll
var _winner: Doll
var _game_cam: Camera3D
var _hud: Node
var _start_xf := Transform3D.IDENTITY
var _fov0 := 40.0
var _pivot := Vector3.ZERO
var _floor_y := -INF
var _yaw_sign := 1.0
var orbit_yaw_deg := ORBIT_YAW_DEG
var _pitch_sign := 1.0
var _want_orbit := false
var _want_replay := false
var _attr: CameraAttributesPractical
var _dof_ok := false
var _last_ko_ctx := {}
# запись повтора
var _rec: Array = []                 # [{"t": игровые с, "xf": {id тела: Transform3D}}]
var _rec_clock := 0.0
var _rec_acc := 0.0
var _bodies := {}                    # id тела → WeakRef(RigidBody3D)
# проигрывание
var _ghost_root: Node3D
var _ghosts: Array = []              # [[MeshInstance3D, id тела, Transform3D от тела к мешу]]
var _hidden: Array = []              # [[Node3D, был виден]]
var _hidden_layers: Array = []       # [CanvasLayer] — спрятаны на время кино
var _tau := 0.0
var _tau0 := 0.0
var _tau1 := 0.0
var _frame_i := 0
var _replay_end_t := -1.0
var _replay_cam_t := Vector3.ZERO
var _replay_cam_inited := false
var _victim_id := 0
var _winner_id := 0


func _ready() -> void:
	match_node = get_parent() as Match
	if match_node == null:
		queue_free()
		return
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	match_node.ko.connect(_on_ko)
	match_node.phase_changed.connect(_on_phase)
	if match_node.has_signal("hit_fx"):
		match_node.hit_fx.connect(_on_hit_fx)
	cam = Camera3D.new()
	cam.name = "KoCamera"
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	overlay = KoCamOverlay.new()
	overlay.name = "KoCamOverlay"
	add_child(overlay)


func _exit_tree() -> void:
	if playing:
		_abort()


func _look_on(id: StringName) -> bool:
	var lc := get_node_or_null("/root/LookCam")
	return lc == null or bool(lc.call("look_on", id))


# --- запись повтора ---

func _record_on() -> bool:
	return _look_on(ID_REPLAY) and match_node.combat_active()


func _physics_process(delta: float) -> void:
	if playing or _pending:
		return   # буфер заморожен: повтор кончается моментом KO
	if not _record_on():
		if not _rec.is_empty():
			_rec.clear()
			_bodies.clear()
		return
	_rec_clock += delta
	_rec_acc += delta
	if _rec_acc < REC_DT * 0.999 and not _rec.is_empty():
		return
	_rec_acc = fmod(_rec_acc, REC_DT) if _rec_acc < REC_DT * 4.0 else 0.0
	_capture_frame()


func _capture_frame() -> void:
	var xf := {}
	for d in match_node.dolls():
		for b in (d as Doll).parts.values():
			var body := b as RigidBody3D
			if body == null or not is_instance_valid(body) or not body.is_inside_tree():
				continue
			var id := body.get_instance_id()
			xf[id] = body.global_transform
			if not _bodies.has(id):
				_bodies[id] = weakref(body)
	if not _rec.is_empty() and is_equal_approx(float(_rec.back()["t"]), _rec_clock):
		_rec[_rec.size() - 1] = {"t": _rec_clock, "xf": xf}
	else:
		_rec.append({"t": _rec_clock, "xf": xf})
	while _rec.size() > 2 and _rec_clock - float(_rec[0]["t"]) > REC_KEEP_S:
		_rec.pop_front()


## Кадров записи сейчас (пробы).
func recorded_frames() -> int:
	return _rec.size()


func _on_hit_fx(ctx: Dictionary) -> void:
	if bool(ctx.get("is_ko", false)):
		_last_ko_ctx = ctx


# --- старт ---

func _on_ko(victim: Doll, _attacker: Node, _record: Dictionary) -> void:
	if playing or _pending:
		return
	_pending = true
	_begin.call_deferred(victim)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		_pending = false
		if playing:
			_abort()
		_rec.clear()
		_bodies.clear()
		_rec_clock = 0.0
		_last_ko_ctx = {}


## Можно ли кино на этом нокауте (вызывается отложенно после Match.ko — удар уже разобран).
func _eligible(victim: Doll) -> bool:
	if victim == null or not is_instance_valid(victim) or not is_inside_tree():
		return false
	if match_node.alive_dolls().size() > 1:
		return false   # не последний нокаут
	if match_node.crit_playing():
		return false   # ko_crit: у крита своё кино
	if not match_node.feel_enabled or not FxPreset.time_fx():
		return false
	if match_node.camera_owner() != "":
		return false
	var gc := match_node.game_camera()
	return gc != null and is_instance_valid(gc) and gc.is_inside_tree()


func _begin(victim: Doll) -> void:
	_pending = false
	if playing:
		return
	_want_orbit = _look_on(ID_KO)
	_want_replay = _look_on(ID_REPLAY) and not _campaign()
	if not _want_orbit and not _want_replay:
		return
	if not _eligible(victim):
		return
	_capture_frame()   # последний кадр повтора — ровно поза, в которой мир сейчас стоит
	_want_replay = _want_replay and _rec.size() >= REPLAY_MIN_FRAMES
	if not _want_orbit and not _want_replay:
		return
	_victim = victim
	_victim_id = victim.get_instance_id()
	_winner = _pick_winner(victim)
	_winner_id = _winner.get_instance_id() if _winner != null else 0
	_game_cam = match_node.game_camera()
	_hud = get_tree().get_first_node_in_group("hud")
	_start_xf = _game_cam.global_transform
	_fov0 = _game_cam.fov
	_pivot = victim.centre_of_mass(true)
	_floor_y = _floor_of(_game_cam)
	var wx := _winner.centre_of_mass(true).x if _winner != null else 0.0
	_yaw_sign = -signf(wx - _pivot.x) if _winner != null and absf(wx - _pivot.x) > 0.05 else (1.0 if _pivot.x <= 0.0 else -1.0)
	_pitch_sign = 1.0 if _pivot.y - _floor_y < LOW_PIVOT_M else -1.0
	orbit_yaw_deg = yaw_for_arena(_game_cam)
	_setup_cam()
	planned_s = (HOLD_S + ORBIT_S if _want_orbit else 0.0) + (replay_duration() if _want_replay else 0.0)
	match_node.request_time_scale(TIME_SCALE, planned_s + WATCHDOG_PAD_S, TAG)
	match_node.capture_camera(cam, TAG)
	if match_node.camera_owner() != TAG:
		match_node.cancel_time_scale(TAG)
		return
	_hide_layers()
	if _hud != null:
		if _hud.has_method("set_cinematic"):
			_hud.call("set_cinematic", true)
		if _hud.has_method("defer_ko_card"):
			_hud.call("defer_ko_card", planned_s)
	playing = true
	plays += 1
	_t = 0.0
	elapsed_s = 0.0
	if _want_orbit:
		overlay.show_ko(_caption_ko(), _victim_tag(victim), _victim_colour(victim), HitJuice.impact_caption(_ctx_for(victim), ""))
		_set_stage("hold")
	else:
		_start_replay()


func _campaign() -> bool:
	var p := match_node.get_parent()
	return p != null and p.has_signal("fight_finished")   # бой кампании: исход через 3.5 с после конца — повтор не успевает


func _pick_winner(victim: Doll) -> Doll:
	for d in match_node.alive_dolls():
		if d != victim:
			return d
	var rec: Dictionary = match_node.ko_records.back() if not match_node.ko_records.is_empty() else {}
	var a: Variant = rec.get("attacker")
	if is_instance_valid(a) and a is Doll and a != victim:
		return a
	return null


## Угол облёта по классу арены игровой камеры (DynamicCamera.arena_path).
static func yaw_for_arena(gc: Camera3D) -> float:
	var ap: Variant = gc.get("arena_path") if gc != null else null
	var arena: Node = gc.get_node_or_null(ap) if ap is NodePath and ap != NodePath() else null
	if arena != null and arena.get_script() is Script:
		var nm := String((arena.get_script() as Script).get_global_name())
		if ORBIT_YAW_BY_ARENA.has(nm):
			return float(ORBIT_YAW_BY_ARENA[nm])
	return ORBIT_YAW_OTHER_DEG


static func _floor_of(gc: Camera3D) -> float:
	if gc != null and gc.has_method("bounds"):
		var b: AABB = gc.call("bounds")
		return b.position.y + 0.6
	return -INF


func _ctx_for(victim: Doll) -> Dictionary:
	if _last_ko_ctx.get("victim") == victim:
		return _last_ko_ctx
	return {}


func _caption_ko() -> String:
	return tr("KO!")


static func _victim_tag(d: Doll) -> String:
	return "P%d" % (d.player_index + 1) if d.player_index >= 0 else ""


static func _victim_colour(d: Doll) -> Color:
	var pi := d.player_index
	return Tuning.PLAYER_COLORS[pi % Tuning.PLAYER_COLORS.size()] if pi >= 0 else Color.WHITE


## Своя камера — как игровая (fov, окружение, экспозиция), плюс DOF на фоне, если пресет графики разрешает.
func _setup_cam() -> void:
	cam.fov = _fov0
	cam.near = _game_cam.near
	cam.far = _game_cam.far
	cam.cull_mask = _game_cam.cull_mask
	cam.environment = _game_cam.environment
	cam.keep_aspect = _game_cam.keep_aspect
	cam.global_transform = _start_xf
	_attr = make_dof_attributes(_game_cam)
	_dof_ok = dof_allowed()
	if _attr != null:
		_attr.dof_blur_far_enabled = _dof_ok
		_attr.dof_blur_near_enabled = false
		_attr.dof_blur_amount = 0.0
		_attr.set_meta(Gfx.META_DOF, [_dof_ok, false])
	cam.attributes = _attr


## Копия атрибутов игровой камеры (или окружения сцены) — экспозиция та же, DOF свой. null, если взять неоткуда и не надо.
static func make_dof_attributes(gc: Camera3D) -> CameraAttributesPractical:
	var src: CameraAttributes = gc.attributes if gc != null else null
	if src == null and gc != null:
		var we := gc.get_viewport().find_child("WorldEnvironment", true, false) as WorldEnvironment
		if we == null:
			for n in gc.get_tree().root.find_children("*", "WorldEnvironment", true, false):
				we = n as WorldEnvironment
				break
		if we != null:
			src = we.camera_attributes
	if src is CameraAttributesPractical:
		var a := (src as CameraAttributesPractical).duplicate() as CameraAttributesPractical
		if a.has_meta(Gfx.META_DOF):
			a.remove_meta(Gfx.META_DOF)
		return a
	if src != null:
		return null   # физические атрибуты: DOF не трогаем
	return CameraAttributesPractical.new()


static func dof_allowed() -> bool:
	return bool(Gfx.values(Gfx.preset).get("dof", true))


## Экранные слои площадки (подсказки клавиш, панели L / Tab, тосты, стрелки за экраном, голосование, реплики N0) прячутся на
## время кино: кадр — только мир, леттербокс и табло. HUD прячет свои панели сам (set_cinematic), вспышки директора не трогаем.
func _hide_layers() -> void:
	_hidden_layers.clear()
	var scene := match_node.get_parent()
	if scene == null:
		return
	var fxd := match_node.get_node_or_null("HitFxDirector")
	for n in scene.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if not cl.visible or cl == overlay or cl == _hud or cl.layer <= 0 or cl.layer >= 60:
			continue
		if fxd != null and fxd.is_ancestor_of(cl):
			continue
		cl.visible = false
		_hidden_layers.append(cl)


func _show_layers() -> void:
	for cl in _hidden_layers:
		if is_instance_valid(cl):
			(cl as CanvasLayer).visible = true
	_hidden_layers.clear()


func _set_stage(s: String) -> void:
	stage = s
	stage_changed.emit(s)


# --- кадр ---

func _process(delta: float) -> void:
	if not playing:
		return
	var real := FxClock.real_delta(delta)
	_t += real
	elapsed_s += real
	if elapsed_s > planned_s + WATCHDOG_PAD_S:
		_back()
		return
	_hold_ko_card()
	match stage:
		"hold":
			if _t >= HOLD_S:
				_set_stage("orbit")
				_orbit_pose(0.0)
		"orbit":
			var u := clampf((_t - HOLD_S) / ORBIT_S, 0.0, 1.0)
			_orbit_pose(u)
			if u >= 1.0:
				if _want_replay:
					_start_replay()
				else:
					_back()
		"replay":
			_replay_step(real)


## Таймер отложенной карточки KO идёт и на паузе (Esc, фоторежим): если она вылезла посреди кино — отложить на остаток плана.
func _hold_ko_card() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	var card := _hud.get("ko_card") as KoCard
	if card != null and card.visible:
		card.defer(maxf(planned_s - elapsed_s, 0.05))


static func ease_io(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)   # smootherstep


## Поза облёта на доле u ∈ [0, 1] (пробы зовут напрямую).
func orbit_transform(u: float) -> Transform3D:
	var c0 := _start_xf.origin
	var fwd := -_start_xf.basis.z
	var depth := maxf((_pivot - c0).dot(fwd), 1.0)
	var t0 := c0 + fwd * depth
	var d0 := (c0 - t0).length()
	var r1 := clampf(d0 * ORBIT_RADIUS_K, ORBIT_RADIUS.x, ORBIT_RADIUS.y)
	var s := ease_io(u)
	var st := smoothstep(0.0, TARGET_LEAD_U, u)
	var tgt := t0.lerp(_pivot, st)
	var dir := (c0 - t0).normalized()
	dir = dir.rotated(Vector3.UP, deg_to_rad(orbit_yaw_deg) * _yaw_sign * s)
	var right := Vector3.UP.cross(dir).normalized()
	dir = dir.rotated(right, -deg_to_rad(ORBIT_PITCH_DEG) * _pitch_sign * s)
	var pos := tgt + dir * lerpf(d0, r1, s)
	pos.y = maxf(pos.y, _floor_y + FLOOR_CLEAR_M)
	if pos.distance_to(tgt) < 0.1:
		return Transform3D(_start_xf.basis, pos)
	return Transform3D(Basis.looking_at(tgt - pos, Vector3.UP), pos)


func _orbit_pose(u: float) -> void:
	cam.global_transform = orbit_transform(u)
	var s := ease_io(u)
	cam.fov = lerpf(_fov0, _fov0 * ORBIT_FOV_K, s)
	_dof(cam.global_position.distance_to(_pivot), smoothstep(0.0, 0.35, u))


func _dof(focus_m: float, k: float) -> void:
	if _attr == null or not _dof_ok:
		return
	_attr.dof_blur_far_distance = focus_m + DOF_BEHIND_M
	_attr.dof_blur_far_transition = maxf(focus_m, 4.0)
	_attr.dof_blur_amount = DOF_AMOUNT * clampf(k, 0.0, 1.0)


## Угол (°) между направлением взгляда сейчас и игровым в начале кино (пробы: камера вышла из боковой плоскости).
func view_angle_deg() -> float:
	return rad_to_deg((-_start_xf.basis.z).angle_to(-cam.global_transform.basis.z))


# --- повтор ---

## Скорость проигрывания (доля игрового времени за реальную с) на моменте tau записи.
func _speed_at(tau: float) -> float:
	var k := smoothstep(_tau1 - REPLAY_SLOW_FROM_S, _tau1 - REPLAY_SLOW_FULL_S, tau)
	return lerpf(REPLAY_SPEED_FAST, REPLAY_SPEED_SLOW, k)


## Длина повтора в реальных секундах по нынешнему буферу (план для карточки KO и итогов).
func replay_duration() -> float:
	if _rec.size() < 2:
		return 0.0
	_tau1 = float(_rec.back()["t"])
	_tau0 = maxf(float(_rec[0]["t"]), _tau1 - REPLAY_BACK_S)
	var real := 0.0
	var tau := _tau0
	var step := 1.0 / 240.0
	while tau < _tau1:
		real += step / _speed_at(tau)
		tau += step
	return real + REPLAY_HOLD_S


func _start_replay() -> void:
	_build_ghosts()
	if _ghosts.is_empty():
		_back()
		return
	_tau1 = float(_rec.back()["t"])
	_tau0 = maxf(float(_rec[0]["t"]), _tau1 - REPLAY_BACK_S)
	_tau = _tau0
	_frame_i = 0
	_replay_end_t = -1.0
	_replay_cam_inited = false
	_t = 0.0
	cam.fov = REPLAY_FOV
	_set_stage("replay")
	overlay.show_replay()
	_pose_ghosts()
	_replay_camera(0.0, 1.0)


func _build_ghosts() -> void:
	_clear_ghosts()
	_ghost_root = Node3D.new()
	_ghost_root.name = "ReplayGhosts"
	_ghost_root.top_level = true
	_ghost_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_ghost_root)
	for id in _bodies:
		var body := (_bodies[id] as WeakRef).get_ref() as RigidBody3D
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var inv := body.global_transform.affine_inverse()
		for mi in body.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.is_visible_in_tree() or m.skin != null or m.has_meta("hitfx"):
				continue
			var g := copy_mesh(m)
			_ghost_root.add_child(g)
			_ghosts.append([g, id, inv * m.global_transform])
	ghost_count = _ghosts.size()
	if _ghosts.is_empty():
		return
	# настоящие куклы и следы эффектов прячутся: мир стоит в моменте KO, повтор — копиями
	for d in match_node.dolls():
		_hide(d as Node3D)
	var dir := match_node.get_node_or_null("HitFxDirector")
	if dir != null:
		_hide(dir.get_node_or_null("FxRoot") as Node3D)
	var juice := match_node.get_node_or_null("HitJuice")
	if juice != null:
		_hide(juice.get("digits") as Node3D)
	var scene := match_node.get_parent()
	if scene != null:
		for ch in scene.get_children():
			if ch is Node3D and String(ch.name).begins_with("ImpactFx"):
				_hide(ch as Node3D)


func _hide(n: Node3D) -> void:
	if n == null or not is_instance_valid(n):
		return
	_hidden.append([n, n.visible])
	n.visible = false


## Копия меша для повтора: тот же меш и материалы (с оверлеем и параметрами инстанса — краска, обводка), без скрипта и детей.
static func copy_mesh(m: MeshInstance3D) -> MeshInstance3D:
	var g := MeshInstance3D.new()
	g.mesh = m.mesh
	g.material_override = m.material_override
	g.material_overlay = m.material_overlay
	for i in m.get_surface_override_material_count():
		g.set_surface_override_material(i, m.get_surface_override_material(i))
	g.cast_shadow = m.cast_shadow
	g.layers = m.layers
	g.transparency = m.transparency
	g.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for p in m.get_property_list():
		var nm := String(p["name"])
		if nm.begins_with("instance_shader_parameters/"):
			g.set(nm, m.get(nm))
	return g


func _clear_ghosts() -> void:
	for e in _hidden:
		if is_instance_valid(e[0]):
			(e[0] as Node3D).visible = bool(e[1])
	_hidden.clear()
	_ghosts.clear()
	if _ghost_root != null and is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null


func _replay_step(real: float) -> void:
	if _tau < _tau1:
		_tau = minf(_tau + _speed_at(_tau) * real, _tau1)
		_pose_ghosts()
	elif _replay_end_t < 0.0:
		_replay_end_t = _t
	_replay_camera(real, (_tau - _tau0) / maxf(_tau1 - _tau0, 1e-3))
	if _replay_end_t >= 0.0 and _t - _replay_end_t >= REPLAY_HOLD_S:
		_back()


## Поза тела на моменте _tau (интерполяция между соседними кадрами записи).
func _body_xf(id: int, i: int, w: float) -> Variant:
	var a: Dictionary = _rec[i]["xf"]
	var b: Dictionary = _rec[mini(i + 1, _rec.size() - 1)]["xf"]
	if not a.has(id):
		return b.get(id)
	if not b.has(id):
		return a[id]
	return (a[id] as Transform3D).interpolate_with(b[id], w)


func _frame_at(tau: float) -> Array:
	while _frame_i < _rec.size() - 2 and float(_rec[_frame_i + 1]["t"]) <= tau:
		_frame_i += 1
	var t0 := float(_rec[_frame_i]["t"])
	var t1 := float(_rec[mini(_frame_i + 1, _rec.size() - 1)]["t"])
	var w := clampf((tau - t0) / (t1 - t0), 0.0, 1.0) if t1 > t0 else 1.0
	return [_frame_i, w]


func _pose_ghosts() -> void:
	var fw := _frame_at(_tau)
	for g in _ghosts:
		var xf: Variant = _body_xf(int(g[1]), int(fw[0]), float(fw[1]))
		var mi := g[0] as MeshInstance3D
		if xf == null:
			mi.visible = false
			continue
		mi.visible = true
		mi.global_transform = (xf as Transform3D) * (g[2] as Transform3D)


## Центр масс куклы в записи (среднее положений её тел) на текущем моменте — для камеры повтора.
func _doll_centre(d: Doll) -> Variant:
	if d == null or not is_instance_valid(d):
		return null
	var fw := _frame_at(_tau)
	var sum := Vector3.ZERO
	var n := 0
	for b in d.parts.values():
		if not (b is RigidBody3D) or not is_instance_valid(b):
			continue
		var xf: Variant = _body_xf((b as Node).get_instance_id(), int(fw[0]), float(fw[1]))
		if xf != null:
			sum += (xf as Transform3D).origin
			n += 1
	return sum / n if n > 0 else null


func _replay_camera(real: float, progress: float) -> void:
	var v: Variant = _doll_centre(_victim) if is_instance_valid(_victim) else null
	var w: Variant = _doll_centre(_winner) if is_instance_valid(_winner) else null
	var mid: Vector3 = _pivot if v == null else v
	var span := 0.0
	if v != null and w != null:
		mid = ((v as Vector3) + (w as Vector3)) * 0.5
		span = Vector2((v as Vector3).x - (w as Vector3).x, (v as Vector3).y - (w as Vector3).y).length()
	if not _replay_cam_inited:
		_replay_cam_t = mid
		_replay_cam_inited = true
	else:
		_replay_cam_t = _replay_cam_t.lerp(mid, 1.0 - exp(-real / REPLAY_FOLLOW_TAU))
	# обе куклы в кадре между полосами леттербокса: полупролёт + запас на руки и ноги
	var half := tan(deg_to_rad(REPLAY_FOV) * 0.5) * (1.0 - 2.0 * KoCamOverlay.BAR_FRAC)
	var r := clampf((span * 0.5 + REPLAY_MARGIN_M) / half, REPLAY_RADIUS.x, REPLAY_RADIUS.y) * lerpf(1.06, 0.94, ease_io(progress))
	var dir := Vector3.BACK.rotated(Vector3.UP, -deg_to_rad(minf(REPLAY_YAW_DEG, orbit_yaw_deg * 0.6)) * _yaw_sign)
	var right := Vector3.UP.cross(dir).normalized()
	dir = dir.rotated(right, deg_to_rad(REPLAY_PITCH_DEG))   # + — камера ниже цели
	var pos := _replay_cam_t + dir * r
	pos.y = maxf(pos.y, _floor_y + FLOOR_CLEAR_M)
	cam.global_transform = Transform3D(Basis.looking_at(_replay_cam_t - pos, Vector3.UP), pos)
	_dof(r, 1.0)


func replay_progress() -> float:
	return clampf((_tau - _tau0) / maxf(_tau1 - _tau0, 1e-3), 0.0, 1.0) if stage == "replay" else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not playing or stage != "replay" or _t < SKIP_AFTER_S:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).physical_keycode
		skip = kc == KEY_ENTER or kc == KEY_KP_ENTER or kc == KEY_SPACE
	elif event is InputEventMouseButton and event.pressed:
		skip = (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if skip:
		get_viewport().set_input_as_handled()
		_back()


# --- конец ---

## Щелчок назад: игровая камера, время отпущено (короткое замедление разлёта), HUD и карточка KO — как раньше.
func _back() -> void:
	if not playing:
		return
	_clear_ghosts()
	overlay.cut()
	_restore(true)
	completed += 1
	_set_stage("back")


func _abort() -> void:
	_clear_ghosts()
	overlay.hide_all()
	_restore(false)
	_set_stage("abort")


func _restore(slow_out: bool) -> void:
	playing = false
	_show_layers()
	if match_node != null and is_instance_valid(match_node):
		match_node.release_camera(TAG)
		match_node.cancel_time_scale(TAG)
		if slow_out:
			match_node.request_time_scale(OUT_SLOW_SCALE, OUT_SLOW_S, TAG_OUT, OUT_SLOW_S * 0.85)
	if _hud != null and is_instance_valid(_hud):
		if _hud.has_method("set_cinematic"):
			_hud.call("set_cinematic", false)
		# кино кончилось раньше плана (пропуск) — карточка KO сейчас, а не по старому таймеру
		var card := _hud.get("ko_card") as KoCard
		if slow_out and card != null and not card.visible and card.remaining_s() > KoCard.SHOW_S + 0.05:
			card.defer(0.0)
	if _attr != null:
		_attr.dof_blur_amount = 0.0
