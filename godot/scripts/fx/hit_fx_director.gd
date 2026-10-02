## Режиссёр эффектов удара (HIT_FX.md §2.2–§2.4, §3.5, §4.2). Сцена scenes/fx/hit_fx_director.tscn, узел «HitFxDirector» —
## ребёнок Match (его создаёт Match._ensure_fx_directors), группа hit_fx_director. Дети: FxRoot (Node3D — волны, послеобразы,
## ленты, доп. щепки/пыль) и ScreenFx (CanvasLayer 5 — вспышка, impact frame, линии скорости; ниже HUD 10).
##
## Вход: play(ctx) — подписан на Match.hit_fx (ctx по контракту §4.1), play_slam(ctx) — на Match.env_slam. Подписка через
## has_signal: пока ядра нет, директор слушает старый Match.hit и сам собирает ctx (уровни light / heavy / ko, без крита).
## Уровни:
##   light   — ничего сверх ImpactFx (его спавнит DollCombat): ни hit-stop, ни камеры;
##   heavy   — белый кадр, ударная волна, доп. щепки/пыль, punch/roll/kick камеры, focus на жертву, 3 послеобраза,
##             ленты (ЦМ, голова, кисти, стопы), дымный след, линии скорости;
##             v2 (§11.3): направленная искра SparkCone вдоль ctx.dir, волна толще (0.3 → 1.8 м) цветом атакующего + белое
##             внутреннее кольцо, звезда ImpactFlash удара сжимается и гаснет за HEAVY_FLASH_COLLAPSE_MS реального времени;
##   ko      — 2 кадра-силуэта (маска кукол DollMask, §11.4), большая волна, punch −12 %, roll 3°, focus 1.2 с, ленты на голове и торсе разлетающихся частей;
##   crit / ko_crit — CritCinematic.play(ctx) (если сцена/скрипт есть и crit_cinematic); после ката (620 мс) директор
##             добавляет отлёт: послеобразы каждые 40 мс, ленты, дым, линии скорости. Иначе — крит без ката (§3.5):
##             стоп 80 мс, надпись CRUSHING BLOW! через Match.announce, slow-mo 0.3× 0.4 с, усиленные следы.
##   slam    — пыль и мелкие щепки без вспышки, тряска от HITFX_SLAM_SHAKE_SPEED; в крит-полёте ещё полукольцо, roll 2°.
## Время — нескалированные часы кадра clock_ms() (Σ delta / time_scale). Время игры — только через Match.request_time_scale
## (теги); пока его нет — через Match._time_effect. Камера — только методы DynamicCamera (punch/roll_kick/focus/kick),
## при Match.feel_enabled = false камера и время не трогаются (визуальные эффекты идут).
## Маска кукол: ребёнок DollMask (doll_mask) — кадры-силуэты ScreenFx и CritOverlay, фон рентгена CritCinematic.
## Интенсивность (одна точка, §11.3): flash_intensity / shake_intensity / impact_frames / crit_cinematic ниже — их меняет пресет FX.
## v3 (§12.1): крит-полёт виден целиком — DynamicCamera.keep_safe держит жертву в safe-area кадра (вне углов HUD и полос
##   леттербокса/подсказки) до конца замедления + CRIT_HOLD_TAIL_S и дальше, пока идёт крит-полёт (≤ CRIT_SAFE_MAX_S); ko_crit — ещё и
##   корпус вне карточки KO; послеобразы, ленты и дымный след — на всё это окно. Пресет reduced уменьшает кольца по размеру
##   (WAVE_SIZE_MIN при flash 0 → 1 при flash 1), не только альфой.
## Лимиты: одновременных лент MAX_TRAILS, послеобразов MAX_AFTERIMAGES, волн MAX_WAVES, облачков MAX_PUFFS — старые снимаются.
## Всё освобождается само; abort_all() — сразу (рестарт, выход из дерева).
class_name HitFxDirector
extends Node

const GROUP := "hit_fx_director"
const SHOCKWAVE_SCENE: PackedScene = preload("res://scenes/fx/shockwave.tscn")
const SPLINTERS: PackedScene = preload("res://scenes/fx/splinters.tscn")
const DUST_PUFF: PackedScene = preload("res://scenes/fx/dust_puff.tscn")
const CRIT_SCENE := "res://scenes/fx/crit_cinematic.tscn"
const CRIT_SCRIPT := "res://scripts/fx/crit_cinematic.gd"

# --- лимиты ---
const MAX_TRAILS := 4
const MAX_AFTERIMAGES := 4
const MAX_WAVES := 6
const MAX_PUFFS := 24
const PARTICLE_LIFE_S := 1.6      # страховка освобождения частиц (время сцены, как ImpactFx.MAX_LIFE_S)
const SLAM_COOLDOWN_MS := 120.0   # на куклу, поверх кулдауна ядра 0.25 с

# --- heavy (§2.2) ---
const HEAVY_FLASH_ALPHA := 0.25
const HEAVY_WAVE_R := Vector2(0.3, 1.8)
const HEAVY_WAVE_MS := 210.0
const HEAVY_WAVE_THICK := 0.3        # доля радиуса (в сцене волны 0.16)
const HEAVY_WAVE_ALPHA := 0.95
const HEAVY_INNER_WAVE_R := Vector2(0.15, 0.95)
const HEAVY_INNER_WAVE_MS := 150.0
const HEAVY_INNER_WAVE_THICK := 0.14
const HEAVY_FLASH_COLLAPSE_MS := 65.0   # звезда ImpactFlash: хлопок и сжатие/гашение в реальном времени
const HEAVY_SPARK_K := 1.0
const FLASH_COLLAPSE_RADIUS_M := 1.5
const FLASH_COLLAPSE_WINDOW_MS := 300.0
const HEAVY_PUNCH_FRAC := -0.08
const HEAVY_PUNCH_PULL := 0.2
const HEAVY_PUNCH_S := 0.25
const HEAVY_ROLL_DEG := 1.5
const HEAVY_ROLL_S := 0.25
const HEAVY_KICK_M := 0.06
const HEAVY_KICK_S := 0.18
const HEAVY_FOCUS_W := 0.35
const HEAVY_FOCUS_S := 0.5
const HEAVY_GHOSTS := 3
const HEAVY_GHOST_INTERVAL_MS := 50.0
const HEAVY_GHOST_FADE_MS := 150.0
const HEAVY_GHOST_WINDOW_MS := 400.0
const HEAVY_TRAIL_MS := 400.0
const HEAVY_SMOKE_MS := 600.0
const HEAVY_LINES_MS := 450.0
const HEAVY_LINES_ALPHA := 0.3
const HEAVY_SPLINTER_K := 1.35
const TRAIL_PARTS := ["Head", "Hand", "Foot"]
const GHOST_ALPHA := 0.5

# --- ko (§2.2) ---
const KO_WAVE_R := Vector2(0.4, 2.2)
const KO_WAVE_MS := 260.0
const KO_PUNCH_FRAC := -0.12
const KO_PUNCH_PULL := 0.25
const KO_PUNCH_S := 0.4
const KO_ROLL_DEG := 3.0
const KO_ROLL_S := 0.4
const KO_FOCUS_W := 0.6
const KO_FOCUS_S := 1.2
const KO_TRAIL_MS := 1200.0
const KO_TRAIL_PARTS := ["Head", "Torso"]
const KO_SPLINTER_K := 1.8
const KO_FLASH_COLLAPSE_MS := 90.0
const KO_SPARK_K := 1.35
const IMPACT_FRAME_MASK_FRAMES := 3   # кадров маски на кадры-силуэты (2 кадра + запас)

# --- crit без ката (§3.5) и отлёт после ката (§3.1, 620–1050 мс) ---
const CRIT_CUT_OUT_MS := 620.0
const CRIT_STOP_S := 0.08
const CRIT_FALLBACK_SLOWMO_S := 0.4
const CRIT_GHOSTS := 10
const CRIT_GHOST_INTERVAL_MS := 40.0
const CRIT_GHOST_FADE_MS := 180.0
const CRIT_GHOST_WINDOW_MS := 430.0
const CRIT_TRAIL_MS := 900.0
const CRIT_SMOKE_MS := 700.0
const CRIT_LINES_MS := 430.0
const CRIT_LINES_ALPHA := 0.35
const CRIT_PUNCH_FRAC := -0.10
const CRIT_ROLL_DEG := 2.0
const CRIT_FOCUS_W := 0.7
const CRIT_FOCUS_S := 0.7
const CRIT_HOLD_TAIL_S := 0.3        # v3: камера держит жертву до конца замедления + это (реальные с)
const CRIT_SAFE_MAX_S := 2.2          # v3: safe-area не дольше (реальные с от ката), даже если крит-полёт ещё идёт
const CRIT_SAFE_STEP_S := 0.25        # продление safe, пока жертва в крит-полёте (Doll.flight_cap_active)
const CRIT_FLIGHT_GHOST_INTERVAL_MS := 45.0
const CRIT_SMOKE_MAX := 18
const KO_CARD_AVOID := Rect2(0.3, 0.3, 0.4, 0.36)   # доли кадра: «KO!» карточки (ko_card.tscn: 680×340 в центре 1920×1080, −40 px)
const WAVE_SIZE_MIN := 0.55           # v3: радиус кольца × lerp(WAVE_SIZE_MIN, 1, flash_intensity) — reduced (0.4) → 0.73
const CRIT_CAPTION := "CRUSHING BLOW!"

# --- стиль «серьёзный» (HIT_FX.md §13, HitJuice.impact_style): свет удара, волна воздуха, плотная пыль, камера; без белого кадра,
# цветных колец, конуса искр цвета атакующего, инверсии, послеобразов, лент и линий скорости (стиль «мульт» — прежний, RM) ---
const SERIOUS_HEAVY_LIGHT := 7.0      # энергия ImpactLight
const SERIOUS_HEAVY_RANGE := 3.2      # м
const SERIOUS_HEAVY_LIGHT_S := 0.12   # реальные с
const SERIOUS_HEAVY_SHOCK_R := 1.3    # м: волна воздуха AirShock
const SERIOUS_HEAVY_SHOCK_S := 0.16
const SERIOUS_HEAVY_SHOCK_K := 0.028  # сдвиг экрана на кольце
const SERIOUS_HEAVY_DUST := 2.0       # × скорость клубов пыли (плотный выброс)
const SERIOUS_KO_LIGHT := 12.0
const SERIOUS_KO_RANGE := 4.2
const SERIOUS_KO_LIGHT_S := 0.2
const SERIOUS_KO_SHOCK_R := 2.0
const SERIOUS_KO_SHOCK_S := 0.24
const SERIOUS_KO_SHOCK_K := 0.04
const CRIT_COLOUR := Color(1.0, 0.8, 0.2)

# --- удар о стену (§2.4) ---
const SLAM_SHAKE_PER_MS := 0.012
const SLAM_SHAKE_MAX := 0.12
const SLAM_WAVE_R := Vector2(0.3, 1.6)
const SLAM_WAVE_MS := 220.0
const SLAM_ROLL_DEG := 2.0
const SLAM_ROLL_S := 0.3
const SLAM_COLOUR := Color(0.85, 0.8, 0.7, 0.7)
const SLAM_DUST_VEL := 1.8        # × скорость частиц dust_puff (по нормали, от стены)
const SLAM_DUST_SCALE := 2.6      # × размер клубов при 8 м/с

# --- настройки (копии Tuning; меню может менять на лету) ---
var enabled := true
var flash_intensity: float = Tuning.HITFX_FLASH_INTENSITY
var shake_intensity: float = Tuning.HITFX_SHAKE_INTENSITY
var impact_frames: bool = Tuning.HITFX_IMPACT_FRAMES
var crit_cinematic: bool = Tuning.HITFX_CRIT_CINEMATIC

## Лог для проб: [{tier, ms, mode}] (mode: "light" | "heavy" | "ko" | "cinematic" | "crit_fallback" | "slam").
var played: Array = []
## Счётчики эффектов (пробы): flashes, impact_frames, waves, afterimages, trails, bursts, puffs, lines, punches, slams.
var stats: Dictionary = {}

@onready var fx_root: Node3D = $FxRoot
@onready var screen_fx: ScreenFx = $ScreenFx
## Маска кукол (кадры-силуэты, фон рентгена крита).
var doll_mask: DollMask

var _match: Node = null
var _clock := 0.0
var _flash_times: Array = []      # clock_ms вспышек/инверсий за последнюю секунду
var _sched: Array = []            # [[at_ms, Callable]]
var _trails: Array = []           # FlightTrail (живые, по порядку)
var _ghosts: Array = []           # AfterimageTrail
var _waves: Array = []            # Shockwave
var _puffs: Array = []            # GPUParticles3D дыма/пыли/щепок директора
var _slam_ms: Dictionary = {}     # doll instance_id -> clock_ms последнего slam
var _cinematic: Node = null
var _cine_checked := false
var _guard_until := -1.0          # до этого clock_ms сторож возвращает игровую камеру (после крита)
var _collapse_zones: Array = []   # [pos, до clock_ms, real_ms] — окна гашения звёзд ImpactFlash
var _hit_legacy := false          # подписан на старый Match.hit (ядра hit_fx ещё нет)


func _ready() -> void:
	add_to_group(GROUP)
	FxClock.ensure(self)
	_reset_stats()
	doll_mask = DollMask.new()
	doll_mask.name = "DollMask"
	add_child(doll_mask)
	if screen_fx != null:
		screen_fx.set_mask(doll_mask)
	_match = get_parent() if get_parent() is Match else get_tree().get_first_node_in_group(Match.GROUP)
	_connect_match()
	_ensure_cinematic()
	call_deferred("prewarm")
	FxPreset.apply(self)   # пресет FX игрока (§11.2), идемпотентно с Match._ensure_fx_directors


func _exit_tree() -> void:
	abort_all()
	if get_tree() != null and get_tree().get_nodes_in_group(GROUP).size() <= 1:
		AfterimageTrail.clear_cache()
		FlightTrail.clear_cache()


func _reset_stats() -> void:
	stats = {"flashes": 0, "impact_frames": 0, "waves": 0, "afterimages": 0, "trails": 0, "bursts": 0, "puffs": 0,
		"lines": 0, "punches": 0, "slams": 0, "cinematic": 0, "crit_fallback": 0, "time_requests": 0, "sparks": 0,
		"flash_collapses": 0}


func _connect_match() -> void:
	if _match == null:
		return
	if _match.has_signal("hit_fx"):
		_match.connect("hit_fx", play)
	elif _match.has_signal("hit"):
		_match.connect("hit", _on_legacy_hit)
		_hit_legacy = true
	if _match.has_signal("env_slam"):
		_match.connect("env_slam", play_slam)
	if _match.has_signal("phase_changed"):
		_match.connect("phase_changed", _on_phase_changed)


func _on_phase_changed(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		abort_all()


# --- часы, лимиты ---

## Нескалированные часы кадра (мс): Σ delta / Engine.time_scale.
func clock_ms() -> float:
	return _clock


## Полноэкранная вспышка/инверсия разрешена (не больше HITFX_MAX_FLASHES_PER_S в скользящую секунду) — и слот сразу занят.
## Общий лимит директора и CritCinematic: кто показывает вспышку, спрашивает здесь (один вызов на вспышку).
func can_flash() -> bool:
	while not _flash_times.is_empty() and _clock - float(_flash_times[0]) >= 1000.0:
		_flash_times.remove_at(0)
	if _flash_times.size() >= Tuning.HITFX_MAX_FLASHES_PER_S:
		return false
	_flash_times.append(_clock)
	return true


## Вспышек за последнюю секунду (пробы).
func flashes_last_second() -> int:
	var n := 0
	for t in _flash_times:
		if _clock - float(t) < 1000.0:
			n += 1
	return n


## Узлы эффектов директора (FxRoot + ScreenFx, все потомки) — проба утечек.
func fx_node_count() -> int:
	var n := 0
	for root in [fx_root, screen_fx]:
		if root != null and is_instance_valid(root):
			n += _count_desc(root)
	return n


static func _count_desc(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch.is_queued_for_deletion():
			continue
		c += 1 + _count_desc(ch)
	return c


## Идёт ли что-то (для сторожа и проб).
func busy() -> bool:
	return not _sched.is_empty() or not _live(_trails).is_empty() or not _live(_ghosts).is_empty() \
		or not _live(_waves).is_empty() or (screen_fx != null and screen_fx.active())


func _process(delta: float) -> void:
	_clock += FxClock.real_delta(delta) * 1000.0
	if not _sched.is_empty():
		var due: Array = []
		var i := 0
		while i < _sched.size():
			if _clock >= float(_sched[i][0]):
				due.append(_sched[i][1])
				_sched.remove_at(i)
			else:
				i += 1
		for c in due:
			var cb: Callable = c
			if cb.is_valid():
				cb.call()
	if not _collapse_zones.is_empty():
		_sweep_collapse_zones()
	_guard_camera()


## Сторож (§3.4): после крита, если камеру никто не держит (Match.camera_owner() == ""), текущей должна быть игровая.
func _guard_camera() -> void:
	if _match == null or _clock > _guard_until:
		return
	if not _match.has_method("camera_owner") or not _match.has_method("game_camera"):
		return
	if String(_match.call("camera_owner")) != "":
		return
	var gc := _match.call("game_camera") as Camera3D
	if gc != null and gc.is_inside_tree() and get_viewport().get_camera_3d() != gc:
		gc.make_current()


func _after(ms: float, cb: Callable) -> void:
	_sched.append([_clock + ms, cb])


# --- вход ---

## Алиасы для проб до появления сигналов ядра.
func on_hit_fx(ctx: Dictionary) -> void:
	play(ctx)


func on_env_slam(ctx: Dictionary) -> void:
	play_slam(ctx)


## Диспетчер по ctx.tier (подписан на Match.hit_fx).
func play(ctx: Dictionary) -> void:
	if not enabled:
		return
	var tier := String(ctx.get("tier", "light"))
	var mode := tier
	match tier:
		"heavy":
			_play_heavy(ctx)
		"ko":
			_play_ko(ctx)
		"crit", "ko_crit":
			mode = _play_crit(ctx)
		_:
			mode = "light"
	played.append({"tier": tier, "ms": _clock, "mode": mode})


## Удар о стену/пол без урона (подписан на Match.env_slam). ctx: doll, part, speed, position, normal, flying, crit_flight.
func play_slam(ctx: Dictionary) -> void:
	if not enabled:
		return
	var doll := ctx.get("doll") as Doll
	var id := doll.get_instance_id() if doll != null else 0
	if _slam_ms.has(id) and _clock - float(_slam_ms[id]) < SLAM_COOLDOWN_MS:
		return
	_slam_ms[id] = _clock
	var v := float(ctx.get("speed", 0.0))
	var pos: Vector3 = ctx.get("position", Vector3.ZERO)
	var nrm: Vector3 = ctx.get("normal", Vector3.UP)
	# нормаль контакта (Jolt) может смотреть в стену: пыль — наружу, к кукле
	if doll != null and is_instance_valid(doll) and nrm.dot(doll.centre_of_mass() - pos) < 0.0:
		nrm = -nrm
	var crit_flight := bool(ctx.get("crit_flight", false))
	var k := clampf(v / 8.0, 0.35, 1.6)
	_burst(DUST_PUFF, pos + nrm * 0.05, nrm, k * SLAM_DUST_VEL, clampf(0.4 + 0.75 * k, 0.3, 1.0), SLAM_DUST_SCALE * clampf(k, 0.5, 1.4))
	_burst(SPLINTERS, pos + nrm * 0.05, nrm, k * 0.6, clampf(0.3 * k, 0.1, 0.5))
	var cam := _cam()
	if _feel() and cam != null:
		if v >= Tuning.HITFX_SLAM_SHAKE_SPEED and cam.has_method("shake"):
			var amp := minf(SLAM_SHAKE_PER_MS * (v - Tuning.HITFX_SLAM_SPEED), SLAM_SHAKE_MAX) * shake_intensity
			if crit_flight:
				amp *= 2.0
			cam.call("shake", amp)
		if crit_flight and cam.has_method("roll_kick"):
			cam.call("roll_kick", SLAM_ROLL_DEG * shake_intensity * (1.0 if nrm.x >= 0.0 else -1.0), SLAM_ROLL_S)
	if crit_flight and not _serious():
		_wave(pos, SLAM_WAVE_R, SLAM_WAVE_MS, SLAM_COLOUR, Vector2(nrm.x, nrm.y))
	elif crit_flight:
		_air_shock(pos, SLAM_WAVE_R.y, SLAM_WAVE_MS / 1000.0, SERIOUS_HEAVY_SHOCK_K)
	stats["slams"] = int(stats["slams"]) + 1
	played.append({"tier": "slam", "ms": _clock, "mode": "crit_slam" if crit_flight else "slam"})


# --- уровни ---

func _play_heavy(ctx: Dictionary, boost: float = 1.0) -> void:
	var victim := _victim(ctx)
	var pos: Vector3 = ctx.get("position", Vector3.ZERO)
	var nrm: Vector3 = ctx.get("normal", Vector3.BACK)
	var dir := _dir(ctx)
	var colour := _colour(ctx)
	var kind := String(ctx.get("kind", "body"))
	# hit-stop: ядро (Match._emit_hit_fx) ставит его само; без ядра — здесь (§2.2: < HIT_STOP_DAMAGE_1 → 50 мс)
	if _match != null and not _match.has_method("_emit_hit_fx") and float(ctx.get("damage", 0.0)) < Tuning.HIT_STOP_DAMAGE_1:
		_time_scale(Tuning.HIT_STOP_TIME_SCALE, Tuning.HITFX_HEAVY_STOP_S, "heavy_stop")
	if _serious():
		_serious_hit(ctx, pos, nrm, dir, victim, boost, false)
		return
	_white_flash(HEAVY_FLASH_ALPHA * boost)
	_collapse_flashes(pos, HEAVY_FLASH_COLLAPSE_MS)
	var ring := _attacker_colour(ctx, _kind_colour(kind))
	ring.a = HEAVY_WAVE_ALPHA
	_wave(pos, HEAVY_WAVE_R * boost, HEAVY_WAVE_MS, ring, Vector2.ZERO, HEAVY_WAVE_THICK)
	_wave(pos, HEAVY_INNER_WAVE_R * boost, HEAVY_INNER_WAVE_MS, Color(1.0, 1.0, 1.0, 0.75), Vector2.ZERO, HEAVY_INNER_WAVE_THICK)
	_spark(pos, dir, _attacker_colour(ctx, _kind_colour(kind)), HEAVY_SPARK_K * boost)
	_burst(SPLINTERS, pos, nrm, HEAVY_SPLINTER_K * boost, 1.0)
	_burst(DUST_PUFF, pos, nrm, 1.1 * boost, 0.9, 1.3)
	_camera_hit(pos, dir, HEAVY_PUNCH_FRAC, HEAVY_PUNCH_PULL, HEAVY_PUNCH_S, HEAVY_ROLL_DEG, HEAVY_ROLL_S)
	if victim != null:
		_camera_focus(victim, HEAVY_FOCUS_W, HEAVY_FOCUS_S)
		_afterimages(victim, HEAVY_GHOSTS, HEAVY_GHOST_INTERVAL_MS, HEAVY_GHOST_FADE_MS, HEAVY_GHOST_WINDOW_MS, colour)
		_trail(victim, TRAIL_PARTS, true, HEAVY_TRAIL_MS, colour, HEAVY_SMOKE_MS)
		_lines(victim, HEAVY_LINES_MS, HEAVY_LINES_ALPHA)


func _play_ko(ctx: Dictionary) -> void:
	var victim := _victim(ctx)
	var pos: Vector3 = ctx.get("position", Vector3.ZERO)
	var nrm: Vector3 = ctx.get("normal", Vector3.BACK)
	var dir := _dir(ctx)
	var colour := _colour(ctx)
	if _serious():
		_serious_hit(ctx, pos, nrm, dir, victim, 1.0, true)
		return
	_inversion()
	_collapse_flashes(pos, KO_FLASH_COLLAPSE_MS)
	_wave(pos, KO_WAVE_R, KO_WAVE_MS, _kind_colour(String(ctx.get("kind", "body"))))
	_spark(pos, dir, _attacker_colour(ctx, _kind_colour(String(ctx.get("kind", "body")))), KO_SPARK_K)
	_burst(SPLINTERS, pos, nrm, KO_SPLINTER_K, 1.0)
	_burst(DUST_PUFF, pos, nrm, 1.4, 1.0, 1.6)
	_camera_hit(pos, dir, KO_PUNCH_FRAC, KO_PUNCH_PULL, KO_PUNCH_S, KO_ROLL_DEG, KO_ROLL_S)
	if victim != null:
		_camera_focus(victim, KO_FOCUS_W, KO_FOCUS_S)
		_trail(victim, KO_TRAIL_PARTS, false, KO_TRAIL_MS, colour, 0.0)
		_afterimages(victim, 2, 70.0, 180.0, 250.0, colour)


## crit / ko_crit: кинематограф, если есть и свободен; иначе крит без ката (§3.5). Возвращает mode для лога.
func _play_crit(ctx: Dictionary) -> String:
	var tier := String(ctx.get("tier", "crit"))
	var cc: Node = _ensure_cinematic() if crit_cinematic else null
	if cc != null and cc.has_method("play") and bool(cc.call("play", ctx)):
		stats["cinematic"] = int(stats["cinematic"]) + 1
		_guard_until = _clock + 2500.0
		var victim := _victim(ctx)
		if victim != null:
			var wr: WeakRef = weakref(victim)
			var colour := _colour(ctx)
			var hold := crit_hold_s(tier, true)
			# safe-area сразу: игровая камера за крупным планом уже кадрирует жертву — кадр ката назад без скачка из угла
			var cam := _cam()
			if cam != null and _feel() and cam.has_method("keep_safe"):
				cam.call("keep_safe", victim, CRIT_CUT_OUT_MS / 1000.0 + hold, KO_CARD_AVOID if tier == "ko_crit" else Rect2())
			_after(CRIT_CUT_OUT_MS, func() -> void: _crit_flight_fx(wr.get_ref() as Doll, colour, cc, hold, tier == "ko_crit"))
		return "cinematic"
	if cc != null and cc.has_method("is_playing") and bool(cc.call("is_playing")):
		# кинематограф занят другим ударом (§3.3): этот — как heavy / ko, уровень в ctx остаётся честным
		if tier == "ko_crit":
			_play_ko(ctx)
			return "ko"
		_play_heavy(ctx)
		return "heavy"
	_crit_fallback(ctx)
	return "crit_fallback"


## Крит без ката (§3.5): стоп 80 мс, CRUSHING BLOW! через Match.announce, slow-mo 0.3× 0.4 с (ko_crit — slow-mo KO уже идёт),
## удар как ko (инверсия, большая волна) + усиленный отлёт.
func _crit_fallback(ctx: Dictionary) -> void:
	stats["crit_fallback"] = int(stats["crit_fallback"]) + 1
	var tier := String(ctx.get("tier", "crit"))
	var victim := _victim(ctx)
	var pos: Vector3 = ctx.get("position", Vector3.ZERO)
	var nrm: Vector3 = ctx.get("normal", Vector3.BACK)
	var colour := _colour(ctx)
	_time_scale(Tuning.HITFX_TIME_SCALE_MIN, CRIT_STOP_S, "crit_freeze")
	if tier != "ko_crit":
		_after(CRIT_STOP_S * 1000.0, func() -> void:
			_time_scale(Tuning.CRIT_SLOWMO_SCALE, CRIT_FALLBACK_SLOWMO_S, "crit_slowmo"))
	if _match != null and _match.has_signal("announce"):
		_match.emit_signal("announce", HitJuice.impact_caption(ctx, CRIT_CAPTION), CRIT_COLOUR, "crit")   # табло: «IMPACT xG» (§13)
	if _serious():
		_impact_light(pos, SERIOUS_KO_LIGHT, SERIOUS_KO_RANGE, SERIOUS_KO_LIGHT_S)
		_air_shock(pos, SERIOUS_KO_SHOCK_R, SERIOUS_KO_SHOCK_S, SERIOUS_KO_SHOCK_K)
	else:
		_inversion()
		_wave(pos, KO_WAVE_R, KO_WAVE_MS, CRIT_COLOUR)
	_burst(SPLINTERS, pos, nrm, KO_SPLINTER_K, 1.0)
	_burst(DUST_PUFF, pos, nrm, 1.4, 1.0)
	_camera_hit(pos, _dir(ctx), CRIT_PUNCH_FRAC, KO_PUNCH_PULL, KO_PUNCH_S, CRIT_ROLL_DEG, KO_ROLL_S)
	if victim != null:
		_camera_focus(victim, CRIT_FOCUS_W, CRIT_FOCUS_S)
		if tier == "ko_crit" and not _serious():
			_trail(victim, KO_TRAIL_PARTS, false, KO_TRAIL_MS, colour, 0.0)
		_crit_flight_fx(victim, colour, null, crit_hold_s(tier, false) + CRIT_STOP_S, tier == "ko_crit")


## Сколько реальных секунд после ката (с катом) или после удара (без ката) держать жертву в кадре: замедление + CRIT_HOLD_TAIL_S.
static func crit_hold_s(tier: String, cinematic: bool) -> float:
	var slow := Tuning.CRIT_SLOWMO_S if cinematic else CRIT_FALLBACK_SLOWMO_S
	if tier == "ko_crit" and cinematic:
		slow = CritCinematic.KO_CRIT_SLOWMO_S
	return slow + CRIT_HOLD_TAIL_S


## Отлёт крита (после ката или сразу без ката) на всё окно hold_s: послеобразы, ленты, дымный след, линии скорости; камера — focus с
## упреждением и safe-area (DynamicCamera.keep_safe) на то же окно, дальше — пока жертва в крит-полёте (≤ CRIT_SAFE_MAX_S).
func _crit_flight_fx(victim: Doll, colour: Color, cc: Node, hold_s: float = 0.85, ko: bool = false) -> void:
	if victim == null or not is_instance_valid(victim) or not victim.is_inside_tree():
		return
	if cc != null and is_instance_valid(cc) and cc.has_method("is_playing") and not bool(cc.call("is_playing")):
		return   # кинематограф прерван (abort) — отлёт не показываем
	var win_ms := hold_s * 1000.0
	if _serious():
		_crit_camera_hold(victim, hold_s, ko, 0.0)   # стиль «серьёзный»: без послеобразов, лент и линий скорости — камера и пыль
		return
	var n := clampi(int(ceil(win_ms / CRIT_FLIGHT_GHOST_INTERVAL_MS)), CRIT_GHOSTS, AfterimageTrail.MAX_SNAPSHOTS)
	_afterimages(victim, n, CRIT_FLIGHT_GHOST_INTERVAL_MS, CRIT_GHOST_FADE_MS, win_ms, colour, 0.06)
	var tr := _trail(victim, TRAIL_PARTS, true, win_ms + FlightTrail.FADE_MS, colour, win_ms)
	tr.smoke_max = CRIT_SMOKE_MAX
	if cc == null:
		_lines(victim, CRIT_LINES_MS, CRIT_LINES_ALPHA)   # с катом линии скорости рисует CritOverlay
	_crit_camera_hold(victim, hold_s, ko, 0.0)


## Камера крит-полёта: focus (с упреждением, полный вес до конца hold_s) и safe-area; продление safe шагами CRIT_SAFE_STEP_S, пока
## жертва в крит-полёте, но не дольше CRIT_SAFE_MAX_S от ката.
func _crit_camera_hold(victim: Doll, real_s: float, ko: bool, since_s: float) -> void:
	var cam := _cam()
	if cam == null or not _feel() or victim == null or not is_instance_valid(victim) or not victim.is_inside_tree():
		return
	if since_s <= 0.0:
		if shake_intensity > 0.0 and cam.has_method("focus"):
			cam.call("focus", victim, CRIT_FOCUS_W * shake_intensity, real_s / (1.0 - DynamicCamera.FOCUS_OUT_FRAC))
	if cam.has_method("keep_safe"):
		cam.call("keep_safe", victim, real_s, KO_CARD_AVOID if ko else Rect2())
		stats["safe_holds"] = int(stats.get("safe_holds", 0)) + 1
	var t_next := since_s + real_s
	if t_next >= CRIT_SAFE_MAX_S:
		return
	var wr: WeakRef = weakref(victim)
	_after(real_s * 1000.0 - 20.0, func() -> void:
		var d := wr.get_ref() as Doll
		if d != null and is_instance_valid(d) and d.is_inside_tree() and d.has_method("flight_cap_active") and bool(d.call("flight_cap_active")):
			_crit_camera_hold(d, minf(CRIT_SAFE_STEP_S, CRIT_SAFE_MAX_S - t_next) + 0.02, ko, t_next))


# --- старый Match.hit (пока нет Match.hit_fx) ---

func _on_legacy_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3) -> void:
	if kind == "environment" or damage <= 0.0 or victim == null:
		return
	var lh: Dictionary = victim.last_hit
	var part := String(lh.get("part", ""))
	var normal: Vector3 = lh.get("normal", Vector3.BACK)
	var dir: Vector3 = lh.get("dir", -normal)
	var head := Doll.part_base_name(part) == "Head"
	var score := damage * (1.0 + Tuning.CRIT_HEAD_BONUS * (1.0 if head else 0.0))
	var tier := "ko" if not victim.alive else ("heavy" if score >= Tuning.HITFX_HEAVY_SCORE else "light")
	play({"victim": victim, "attacker": attacker, "damage": damage, "kind": kind, "part": part,
		"part_base": Doll.part_base_name(part), "position": position, "normal": normal, "dir": dir,
		"score": score, "tier": tier, "is_ko": not victim.alive, "hp_after": victim.hp,
		"colour": Tuning.PLAYER_COLORS[clampi(victim.player_index, 0, Tuning.PLAYER_COLORS.size() - 1)]})


# --- стиль «серьёзный» (HIT_FX.md §13) ---

func _serious() -> bool:
	return HitJuice.impact_style == "serious"


## heavy / ko «серьёзно»: свет удара, волна воздуха, плотная пыль, удар камеры и фокус. Обломки по материалу уже дал ImpactFx.
func _serious_hit(ctx: Dictionary, pos: Vector3, nrm: Vector3, dir: Vector3, victim: Doll, boost: float, ko: bool) -> void:
	_collapse_flashes(pos, HEAVY_FLASH_COLLAPSE_MS)   # горячее пятно этого удара гаснет быстрее (и звёзды «мульт», если были)
	if ko:
		_impact_light(pos, SERIOUS_KO_LIGHT, SERIOUS_KO_RANGE, SERIOUS_KO_LIGHT_S)
		_air_shock(pos, SERIOUS_KO_SHOCK_R, SERIOUS_KO_SHOCK_S, SERIOUS_KO_SHOCK_K)
		_burst(DUST_PUFF, pos, nrm, SERIOUS_HEAVY_DUST * 1.3, 1.0, 1.8)
		_camera_hit(pos, dir, KO_PUNCH_FRAC, KO_PUNCH_PULL, KO_PUNCH_S, KO_ROLL_DEG, KO_ROLL_S)
		if victim != null:
			_camera_focus(victim, KO_FOCUS_W, KO_FOCUS_S)
		return
	_impact_light(pos, SERIOUS_HEAVY_LIGHT * boost, SERIOUS_HEAVY_RANGE, SERIOUS_HEAVY_LIGHT_S)
	_air_shock(pos, SERIOUS_HEAVY_SHOCK_R * boost, SERIOUS_HEAVY_SHOCK_S, SERIOUS_HEAVY_SHOCK_K)
	_burst(DUST_PUFF, pos, nrm, SERIOUS_HEAVY_DUST * boost, 1.0, 1.5)
	_camera_hit(pos, dir, HEAVY_PUNCH_FRAC, HEAVY_PUNCH_PULL, HEAVY_PUNCH_S, HEAVY_ROLL_DEG, HEAVY_ROLL_S)
	if victim != null:
		_camera_focus(victim, HEAVY_FOCUS_W, HEAVY_FOCUS_S)


func _impact_light(pos: Vector3, energy: float, range_m: float, life_s: float) -> void:
	if ImpactLight.flash(fx_root, pos, energy * flash_intensity, range_m, life_s) != null:
		stats["lights"] = int(stats.get("lights", 0)) + 1


func _air_shock(pos: Vector3, radius: float, life_s: float, strength: float) -> void:
	if flash_intensity <= 0.001:
		return   # пресет FX off — без искажений
	if AirShock.spawn(fx_root, pos, radius * lerpf(WAVE_SIZE_MIN, 1.0, flash_intensity), life_s, strength * flash_intensity) != null:
		stats["air_shocks"] = int(stats.get("air_shocks", 0)) + 1


# --- строительные блоки (публичные — ими пользуется CritCinematic) ---

## Полноэкранная белая вспышка на 1 кадр (альфа × flash_intensity), в лимите вспышек.
func white_flash(alpha: float, frames: int = 1) -> bool:
	return _white_flash(alpha, frames)


func _white_flash(alpha: float, frames: int = 1) -> bool:
	var a := alpha * flash_intensity
	if a <= 0.001 or screen_fx == null or not can_flash():
		return false
	screen_fx.flash(a, frames)
	stats["flashes"] = int(stats["flashes"]) + 1
	return true


## 2 кадра инверсии (impact frame), если разрешены и есть лимит.
func inversion(modes: Array = [0, 1]) -> bool:
	return _inversion(modes)


func _inversion(modes: Array = [0, 1]) -> bool:
	if not impact_frames or flash_intensity <= 0.001 or screen_fx == null or not can_flash():
		return false
	if doll_mask != null and is_instance_valid(doll_mask):
		doll_mask.pulse(IMPACT_FRAME_MASK_FRAMES)
	screen_fx.impact_frame(modes, flash_intensity)
	stats["impact_frames"] = int(stats["impact_frames"]) + 1
	return true


func _wave(pos: Vector3, r: Vector2, ms: float, colour: Color, arc_dir: Vector2 = Vector2.ZERO, thickness: float = -1.0) -> Shockwave:
	_trim(_waves, MAX_WAVES - 1)
	var w := SHOCKWAVE_SCENE.instantiate() as Shockwave
	fx_root.add_child(w)
	var c := colour
	c.a *= clampf(flash_intensity, 0.0, 1.0)   # пресет FX (§11.6): reduced — кольцо прозрачнее, off — невидимо
	var size_k := lerpf(WAVE_SIZE_MIN, 1.0, clampf(flash_intensity, 0.0, 1.0))   # v3: reduced — и меньше
	w.setup(pos, r.x * size_k, r.y * size_k, ms, c, arc_dir, thickness)
	_waves.append(w)
	stats["waves"] = int(stats["waves"]) + 1
	return w


func spawn_wave(pos: Vector3, r0: float, r1: float, ms: float, colour: Color) -> Node3D:
	return _wave(pos, Vector2(r0, r1), ms, colour)


## Направленная искра (SparkCone) от точки удара вдоль dir цветом colour.
func _spark(pos: Vector3, dir: Vector3, colour: Color, k: float) -> SparkCone:
	if fx_root == null or flash_intensity <= 0.001:
		return null
	var sc := SparkCone.new()
	sc.name = "SparkCone"
	fx_root.add_child(sc)
	sc.setup(pos, dir, colour, k, flash_intensity)
	stats["sparks"] = int(stats["sparks"]) + 1
	return sc


## Звёзды ImpactFlash удара рядом с pos (ImpactFx под Match / сценой) — хлопок и гашение за real_ms реального времени: в hit-stop
## они не висят над торсами. Окно FLASH_COLLAPSE_WINDOW_MS: вторичные контакты того же сшиба (DollCombat спавнит ImpactFx и после
## Match.on_hit) гасятся так же.
func _collapse_flashes(pos: Vector3, real_ms: float) -> void:
	_collapse_zones.append([pos, _clock + FLASH_COLLAPSE_WINDOW_MS, real_ms])
	_collapse_flashes_now(pos, real_ms)


func _sweep_collapse_zones() -> void:
	var i := 0
	while i < _collapse_zones.size():
		var z: Array = _collapse_zones[i]
		if _clock > float(z[1]):
			_collapse_zones.remove_at(i)
			continue
		_collapse_flashes_now(z[0], float(z[2]), false)
		i += 1


func _collapse_flashes_now(pos: Vector3, real_ms: float, pop: bool = true) -> void:
	if not is_inside_tree():
		return
	var hosts: Array = []
	if _match != null and is_instance_valid(_match):
		hosts.append(_match)
		if _match.get_parent() != null:
			hosts.append(_match.get_parent())
	var cs := get_tree().current_scene
	if cs != null and not hosts.has(cs):
		hosts.append(cs)
	for host in hosts:
		for fx in (host as Node).get_children():
			if not (fx is Node3D) or fx.is_queued_for_deletion():
				continue
			for c in fx.get_children():
				if c is ImpactFlash and (c as Node3D).global_position.distance_to(pos) <= FLASH_COLLAPSE_RADIUS_M + 0.2:
					if not (c as ImpactFlash).collapsing():
						stats["flash_collapses"] = int(stats["flash_collapses"]) + 1
					(c as ImpactFlash).collapse(real_ms, pop)


func _afterimages(victim: Doll, count: int, interval_ms: float, fade_ms: float, window_ms: float, colour: Color, min_step: float = 0.1) -> AfterimageTrail:
	_trim(_ghosts, MAX_AFTERIMAGES - 1)
	var a := AfterimageTrail.new()
	a.name = "Afterimages"
	fx_root.add_child(a)
	var gc := colour.lerp(Color.WHITE, 0.3)
	gc.a = GHOST_ALPHA
	a.setup(victim, count, interval_ms, fade_ms, window_ms, gc, min_step)
	_ghosts.append(a)
	stats["afterimages"] = int(stats["afterimages"]) + 1
	return a


func _trail(victim: Doll, parts: Array, with_com: bool, life_ms: float, colour: Color, smoke_ms: float) -> FlightTrail:
	_trim(_trails, MAX_TRAILS - 1)
	var t := FlightTrail.new()
	t.name = "FlightTrail"
	fx_root.add_child(t)
	t.setup(victim, parts, with_com, life_ms, colour.lerp(Color.WHITE, 0.45), smoke_ms, self)
	_trails.append(t)
	stats["trails"] = int(stats["trails"]) + 1
	return t


func _lines(victim: Doll, ms: float, alpha: float) -> void:
	if screen_fx == null or flash_intensity <= 0.001:   # пресет FX off (§11.6) — без линий скорости
		return
	screen_fx.speed_lines(victim, ms, alpha * clampf(flash_intensity, 0.0, 1.0))
	stats["lines"] = int(stats["lines"]) + 1


## Клуб дыма за летящей куклой (зовёт FlightTrail).
func puff(pos: Vector3, normal: Vector3, k: float) -> void:
	_burst(DUST_PUFF, pos, normal, k * 0.6, clampf(0.25 * k, 0.15, 0.4), 1.2)
	stats["puffs"] = int(stats["puffs"]) + 1


## Одноразовая система частиц (щепки/пыль из ImpactFx) без вспышки: +Z вдоль normal, скорость × vel_k, доля частиц ratio.
func _burst(scene: PackedScene, pos: Vector3, normal: Vector3, vel_k: float, ratio: float, scale_k: float = 1.0) -> GPUParticles3D:
	_trim(_puffs, MAX_PUFFS - 1)
	var p := scene.instantiate() as GPUParticles3D
	if p == null:
		return null
	fx_root.add_child(p)
	var n := normal
	if n.length_squared() < 1e-6:
		n = Vector3.UP
	n = n.normalized()
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	p.global_transform = Transform3D(Basis.looking_at(-n, up), pos)
	var pm := p.process_material as ParticleProcessMaterial
	if pm != null:
		pm = pm.duplicate() as ParticleProcessMaterial
		pm.initial_velocity_min *= vel_k
		pm.initial_velocity_max *= vel_k
		if not is_equal_approx(scale_k, 1.0):
			pm.scale_min *= scale_k
			pm.scale_max *= scale_k
		p.process_material = pm
	p.amount_ratio = clampf(ratio, 0.05, 1.0)
	var wr: WeakRef = weakref(p)
	p.finished.connect(func() -> void: _free_ref(wr))
	get_tree().create_timer(PARTICLE_LIFE_S * maxf(p.lifetime, 0.5)).timeout.connect(func() -> void: _free_ref(wr))
	p.restart()
	p.emitting = true
	_puffs.append(p)
	stats["bursts"] = int(stats["bursts"]) + 1
	return p


static func _free_ref(wr: WeakRef) -> void:
	var n := wr.get_ref() as Node
	if n != null and is_instance_valid(n) and not n.is_queued_for_deletion():
		n.queue_free()


## Оставляет в списке не больше keep живых; лишние старые освобождает.
func _trim(list: Array, keep: int) -> void:
	var live := _live(list)
	list.clear()
	list.append_array(live)
	while list.size() > maxi(keep, 0):
		var old: Node = list.pop_front()
		if old.has_method("stop"):
			old.call("stop")
		else:
			old.queue_free()


static func _live(list: Array) -> Array:
	var out: Array = []
	for n in list:
		if is_instance_valid(n) and not (n as Node).is_queued_for_deletion():
			out.append(n)
	return out


# --- камера, время ---

func _feel() -> bool:
	return _match == null or bool(_match.get("feel_enabled"))


func _cam() -> Node:
	if _match != null:
		if _match.has_method("game_camera"):
			return _match.call("game_camera") as Node
		if _match.has_method("_camera"):
			return _match.call("_camera") as Node
	return get_viewport().get_camera_3d()


func _camera_hit(pos: Vector3, dir: Vector3, frac: float, pull: float, punch_s: float, roll_deg: float, roll_s: float) -> void:
	var cam := _cam()
	if cam == null or not _feel() or shake_intensity <= 0.0:
		return
	if cam.has_method("punch"):
		cam.call("punch", pos, frac * shake_intensity, pull * shake_intensity, punch_s)
		stats["punches"] = int(stats["punches"]) + 1
	if cam.has_method("roll_kick"):
		var s := -1.0 if dir.x >= 0.0 else 1.0     # кадр кренится вслед удару
		cam.call("roll_kick", roll_deg * s * shake_intensity, roll_s)
	if cam.has_method("kick"):
		cam.call("kick", Vector2(dir.x, dir.y), HEAVY_KICK_M * shake_intensity, HEAVY_KICK_S)


func _camera_focus(victim: Doll, w: float, s: float) -> void:
	var cam := _cam()
	if cam == null or not _feel() or shake_intensity <= 0.0 or not cam.has_method("focus"):
		return
	cam.call("focus", victim, w * shake_intensity, s)


## Время игры: Match.request_time_scale (ядро, с тегом), иначе старый Match._time_effect. При feel_enabled = false — ничего.
func _time_scale(scale: float, real_s: float, tag: String) -> void:
	if _match == null or not _feel():
		return
	stats["time_requests"] = int(stats["time_requests"]) + 1
	if _match.has_method("request_time_scale"):
		_match.call("request_time_scale", scale, real_s, tag)
	elif _match.has_method("_time_effect"):
		_match.call("_time_effect", maxf(scale, Tuning.HITFX_TIME_SCALE_MIN), real_s)


# --- кинематограф крита ---

func _ensure_cinematic() -> Node:
	if _cinematic != null and is_instance_valid(_cinematic):
		return _cinematic
	var n := get_node_or_null("CritCinematic")
	if n == null and not _cine_checked:
		_cine_checked = true
		if ResourceLoader.exists(CRIT_SCENE) and ResourceLoader.exists(CRIT_SCRIPT):
			var ps := load(CRIT_SCENE) as PackedScene
			if ps != null:
				n = ps.instantiate()
		elif ResourceLoader.exists(CRIT_SCRIPT):
			var scr := load(CRIT_SCRIPT) as Script
			if scr != null and scr.can_instantiate():
				n = scr.new() as Node
		if n != null:
			n.name = "CritCinematic"
			add_child(n)
	_cinematic = n
	return n


# --- прогрев, сброс ---

## Материалы и шейдеры всех эффектов заранее: по экземпляру волны / послеобраза / ленты далеко внизу, экранные шейдеры.
func prewarm() -> void:
	if not is_inside_tree():
		return
	# материалы рисуются FxPrewarm перед камерой (вне кадра пайплайн не компилируется — волна на y −500 не прогревала)
	FxPrewarm.spatial(self, [AfterimageTrail.ghost_material(Color.WHITE), FlightTrail.ribbon_material(), SparkCone.material()])
	var near: Variant = FxPrewarm.camera_point(self)
	var w := SHOCKWAVE_SCENE.instantiate() as Shockwave
	fx_root.add_child(w)
	w.setup(near as Vector3 if near != null else Vector3(0.0, -500.0, 0.0), 0.002, 0.003, 60.0, Color(1, 1, 1, 0))
	if screen_fx != null:
		screen_fx.prewarm()
	var cc := _ensure_cinematic()
	if cc != null and cc.has_method("prewarm"):
		cc.call("prewarm")


## Снять всё сразу: эффекты, расписание, экран, FX камеры, свои теги времени, кинематограф.
func abort_all() -> void:
	_sched.clear()
	_collapse_zones.clear()
	for list in [_trails, _ghosts, _waves, _puffs]:
		for n in _live(list):
			(n as Node).queue_free()
		(list as Array).clear()
	if fx_root != null and is_instance_valid(fx_root):
		for c in fx_root.get_children():
			c.queue_free()
	if screen_fx != null and is_instance_valid(screen_fx):
		screen_fx.clear()
	if _cinematic != null and is_instance_valid(_cinematic) and _cinematic.has_method("abort"):
		if not _cinematic.has_method("is_playing") or bool(_cinematic.call("is_playing")):
			_cinematic.call("abort")
	var cam := _cam() if is_inside_tree() else null
	if cam != null and is_instance_valid(cam) and cam.has_method("clear_fx"):
		cam.call("clear_fx")
	if _match != null and is_instance_valid(_match) and _match.has_method("cancel_time_scale"):
		for tag in ["heavy_stop", "crit_freeze", "crit_slowmo"]:
			if not _match.has_method("_emit_hit_fx") or tag != "heavy_stop":
				_match.call("cancel_time_scale", tag)


# --- ctx ---

static func _victim(ctx: Dictionary) -> Doll:
	var v = ctx.get("victim")
	if v is Doll and is_instance_valid(v) and (v as Doll).is_inside_tree():
		return v
	return null


static func _dir(ctx: Dictionary) -> Vector3:
	var d: Vector3 = ctx.get("dir", Vector3.ZERO)
	if d.length_squared() < 1e-6:
		var n: Vector3 = ctx.get("normal", Vector3.ZERO)
		d = -n
	d.z = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.RIGHT


static func _colour(ctx: Dictionary) -> Color:
	if ctx.has("colour"):
		return ctx["colour"]
	var v := _victim(ctx)
	var i := v.player_index if v != null else 0
	return Tuning.PLAYER_COLORS[clampi(i, 0, Tuning.PLAYER_COLORS.size() - 1)]


## Цвет атакующего (цвет игрока, Tuning.PLAYER_COLORS) — кольцо и искра heavy; нет атакующего-куклы — fallback.
static func _attacker_colour(ctx: Dictionary, fallback: Color) -> Color:
	var a: Variant = ctx.get("attacker")
	if a is Node and is_instance_valid(a):
		var pi: Variant = (a as Node).get("player_index")
		if pi != null and int(pi) >= 0:
			var c: Color = Tuning.PLAYER_COLORS[int(pi) % Tuning.PLAYER_COLORS.size()]
			return Color(c.r, c.g, c.b, fallback.a)
	return fallback


static func _kind_colour(kind: String) -> Color:
	var c: Color = ImpactFx.FLASH_COLOURS.get(kind, Color.WHITE)
	return Color(c.r, c.g, c.b, 0.85)
