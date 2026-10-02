## Звук тела куклы (docs/plan-demo/AUDIO.md §4.4): ребёнок «DollAudio» каждой куклы Match (создаёт SfxDirector._sync_doll_audio).
##   Ветер полёта — петля loops/wind_flight.ogg на AudioStreamPlayer3D (затухание по расстоянию выключено, панорама — от камеры):
##     громкость, питч и срез по скорости ЦМ (WIND_MIN_SPEED → тишина, WIND_FULL_SPEED → WIND_MAX_DB), в slow-mo ниже питч.
##   Рывок (Doll.dashed) — dash; переворот (Doll.flipped) — flip; стан — stun; отрыв / возврат детали — detach / attach.
##   Замах: конец оружия быстрее SWING_WEAPON_SPEED (передний фронт, не чаще SWING_GAP_MS) — swing_h (тяжёлое) / swing_l;
##     кисть без оружия быстрее SWING_HAND_SPEED — swing_l тише.
##   Скрип суставов: относительная угловая скорость частей сустава выше CREAK_REL_W (передний фронт, шанс CREAK_CHANCE, не чаще
##     CREAK_GAP_MS) — creak (дерево) / scrape (металл). Живой куклой, не в крите.
##   Хват (ArmAssist.grabbed) — grab; отпустил без броска — grab ниже; подобрал оружие — equip.
## Звуки идут через SfxDirector.play_layer (лимиты, приоритеты, журнал played). events — журнал для проб [{ev, ms}].
class_name DollAudio
extends Node

const WIND_STREAM := "res://assets/audio/loops/wind_flight.ogg"
const WIND_MIN_SPEED := 3.0
const WIND_FULL_SPEED := 13.0
const WIND_MIN_DB := -34.0
const WIND_MAX_DB := -5.0
const WIND_OFF_DB := -80.0
const WIND_ATTACK_DB_S := 260.0         # подъём громкости, дБ/с: ветер «подхватывает» за ~0.2 с
const WIND_RELEASE_DB_S := 45.0
const WIND_CRIT_DB := -8.0              # в крите ветер тише (крупный план — тишина и бум)
const SWING_WEAPON_SPEED := 7.5         # м/с конца оружия
const SWING_HAND_SPEED := 9.5
const SWING_GAP_MS := 260.0
const SWING_HEAVY_MASS := 3.0
const CREAK_REL_W := 11.0               # рад/с: резкий излом сустава (удар, падение), не работа мышц в полёте
const CREAK_GAP_MS := 1400.0
const CREAK_CHANCE := 0.3
const WEAPON_SCAN_MS := 250.0

var sfx: SfxDirector
var doll: Doll
var wind: AudioStreamPlayer3D
var wind_db := WIND_OFF_DB
var events: Array = []

var _rng := RandomNumberGenerator.new()
var _was_fast_weapon: Dictionary = {}   # instance_id оружия -> bool
var _was_fast_hand: Dictionary = {}
var _was_creak: Dictionary = {}         # имя сустава -> bool
var _swing_ms := -1.0e9
var _creak_ms := -1.0e9
var _held: Array = []                   # оружие в руках (Weapon)
var _scan_ms := -1.0e9
var _arm: Node


func _ready() -> void:
	doll = get_parent() as Doll
	_rng.seed = hash(doll.name) if doll != null else 7
	process_mode = Node.PROCESS_MODE_ALWAYS
	if doll == null:
		return
	wind = AudioStreamPlayer3D.new()
	wind.name = "Wind"
	var s := load(WIND_STREAM) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	wind.stream = s
	wind.bus = SfxDirector.BUS_SFX
	wind.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	wind.panning_strength = 0.6
	wind.volume_db = WIND_OFF_DB
	wind.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(wind)
	for pair in [["dashed", _on_dashed], ["flipped", _on_flipped], ["stunned", _on_stunned], ["part_detached", _on_detached],
			["part_reattached", _on_reattached]]:
		if doll.has_signal(pair[0]) and not doll.is_connected(pair[0], pair[1]):
			doll.connect(pair[0], pair[1])
	for c in doll.get_children():
		if c is ArmAssist:
			_arm = c
			(c as ArmAssist).grabbed.connect(_on_grabbed)
			(c as ArmAssist).released.connect(_on_released)


func _clock() -> float:
	return sfx.clock_ms() if sfx != null and is_instance_valid(sfx) else Time.get_ticks_msec()


func _log(ev: String) -> void:
	events.append({"ev": ev, "ms": snappedf(_clock(), 0.1)})
	if events.size() > 512:
		events.remove_at(0)


func _play(layer: String, db: float, pitch: float, pos: Vector3) -> int:
	if sfx == null or not is_instance_valid(sfx):
		return -1
	var v := sfx.play_layer(layer, db, pitch, SfxDirector.BUS_SFX, sfx.pan_for(pos))
	if v >= 0:
		_log(layer)
	return v


func _com() -> Vector3:
	return doll.centre_of_mass() if is_instance_valid(doll) else Vector3.ZERO


# --- события куклы ---

func _on_dashed() -> void:
	_play("dash", 0.0, _rng.randf_range(0.95, 1.08), _com())


func _on_flipped(_dir: float) -> void:
	_play("flip", 0.0, _rng.randf_range(0.95, 1.15), _com())


func _on_stunned(_s: float) -> void:
	_play("stun", 0.0, _rng.randf_range(0.95, 1.05), doll.head().global_position if doll.head() != null else _com())


func _on_detached(part_name: String, _by: Node) -> void:
	var b: Variant = doll.parts.get(part_name, null)
	_play("detach", 0.0, _rng.randf_range(0.95, 1.1), (b as Node3D).global_position if b is Node3D else _com())


func _on_reattached(_part_name: String) -> void:
	_play("attach", 0.0, _rng.randf_range(0.95, 1.1), _com())


func _on_grabbed(b: RigidBody3D) -> void:
	_play("grab", 0.0, _rng.randf_range(0.95, 1.1), b.global_position if is_instance_valid(b) else _com())


func _on_released(b: RigidBody3D, reason: String) -> void:
	if reason == "toggle":
		return                              # бросок — свой «вух» в ArmAssist._throw
	_play("grab", -4.0, _rng.randf_range(0.78, 0.86), b.global_position if is_instance_valid(b) and b.is_inside_tree() else _com())


# --- непрерывное ---

func _physics_process(delta: float) -> void:
	if doll == null or not is_instance_valid(doll) or sfx == null or not is_instance_valid(sfx):
		return
	var crit := sfx.crit_active()
	_tick_wind(delta, crit)
	if not doll.alive or crit:
		return
	var now := _clock()
	if now - _scan_ms >= WEAPON_SCAN_MS:
		_scan_ms = now
		_scan_weapons()
	_tick_swings(now)
	_tick_creaks(now)


func _tick_wind(delta: float, crit: bool) -> void:
	if wind == null:
		return
	var sp := SfxDirector.com_velocity(doll).length() if doll.alive else 0.0
	var k := clampf((sp - WIND_MIN_SPEED) / (WIND_FULL_SPEED - WIND_MIN_SPEED), 0.0, 1.0)
	var target := WIND_OFF_DB if sp < WIND_MIN_SPEED else lerpf(WIND_MIN_DB, WIND_MAX_DB, sqrt(k))
	if crit and target > WIND_OFF_DB:
		target += WIND_CRIT_DB
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	var rate := WIND_ATTACK_DB_S if target > wind_db else WIND_RELEASE_DB_S
	wind_db = move_toward(wind_db, target, rate * real_dt)
	wind.volume_db = wind_db
	wind.pitch_scale = lerpf(0.75, 1.35, k) * SfxDirector.time_pitch(Engine.time_scale)
	if is_inside_tree():
		wind.global_position = _com()
	if target > WIND_OFF_DB and wind_db < WIND_MIN_DB - 12.0:
		wind_db = WIND_MIN_DB - 12.0        # старт с порога слышимости, а не с −80
		wind.volume_db = wind_db
	var audible := wind_db > WIND_OFF_DB + 1.0
	if audible and not wind.playing:
		wind.play(_rng.randf_range(0.0, 5.0))
	elif not audible and wind.playing:
		wind.stop()


func _scan_weapons() -> void:
	var now_held: Array = []
	for w in get_tree().get_nodes_in_group(Weapon.GROUP):
		var wp := w as Weapon
		if wp == null or wp.holder == null or not is_instance_valid(wp.holder):
			continue
		if wp.holder.get("doll") == doll:
			now_held.append(wp)
	for wp in now_held:
		if not _held.has(wp):
			_play("equip", 0.0, 1.1 if SoundMaterial.weapon_class(wp.weapon_id) == SoundMaterial.BLADE else 0.95, wp.global_position)
	_held = now_held


func _tick_swings(now: float) -> void:
	for wp in _held:
		if not is_instance_valid(wp):
			continue
		var w := wp as Weapon
		var tip := w.to_global(w.grip_local + Vector3.RIGHT * w.length)
		var v := w.linear_velocity + w.angular_velocity.cross(tip - w.global_position)
		var sp := Vector2(v.x, v.y).length()
		var id := w.get_instance_id()
		var fast := sp >= SWING_WEAPON_SPEED
		if fast and not bool(_was_fast_weapon.get(id, false)) and now - _swing_ms >= SWING_GAP_MS:
			var heavy := w.mass >= SWING_HEAVY_MASS
			var k := clampf((sp - SWING_WEAPON_SPEED) / SWING_WEAPON_SPEED, 0.0, 1.0)
			if _play("swing_h" if heavy else "swing_l", lerpf(-8.0, 0.0, k), lerpf(0.85, 1.15, k) * (0.9 if heavy else 1.05), tip) >= 0:
				_swing_ms = now
		_was_fast_weapon[id] = fast
	for hn in ["Hand_L", "Hand_R"]:
		var h: Variant = doll.parts.get(hn, null)
		if not h is RigidBody3D or not is_instance_valid(h):
			continue
		var holding := false
		for wp in _held:
			if is_instance_valid(wp) and (wp as Weapon).holder_hand == h:
				holding = true
		var sp := ((h as RigidBody3D).linear_velocity * Vector3(1, 1, 0)).length()
		var fast := sp >= SWING_HAND_SPEED and not holding
		if fast and not bool(_was_fast_hand.get(hn, false)) and now - _swing_ms >= SWING_GAP_MS:
			if _play("swing_l", -6.0, _rng.randf_range(1.05, 1.25), (h as Node3D).global_position) >= 0:
				_swing_ms = now
		_was_fast_hand[hn] = fast


func _tick_creaks(now: float) -> void:
	for jn in doll.joints.keys():
		var j := doll.joints[jn] as Joint3D
		if j == null or not is_instance_valid(j):
			continue
		var a := j.get_node_or_null(j.node_a) as RigidBody3D
		var b := j.get_node_or_null(j.node_b) as RigidBody3D
		if a == null or b == null:
			continue
		var rel := (b.angular_velocity - a.angular_velocity).length()
		var hot := rel >= CREAK_REL_W
		if hot and not bool(_was_creak.get(jn, false)) and now - _creak_ms >= CREAK_GAP_MS and _rng.randf() < CREAK_CHANCE:
			var mat := SoundMaterial.of_body(b)
			var k := clampf((rel - CREAK_REL_W) / CREAK_REL_W, 0.0, 1.0)
			var layer := "scrape" if mat == SoundMaterial.METAL else "creak"
			if mat != SoundMaterial.RUBBER and _play(layer, lerpf(-10.0, -3.0, k), _rng.randf_range(0.9, 1.35), b.global_position) >= 0:
				_creak_ms = now
		_was_creak[jn] = hot
