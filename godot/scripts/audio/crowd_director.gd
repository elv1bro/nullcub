## Толпа купола (docs/plan-demo/AUDIO.md §4.6) — второй персонаж боя. Ребёнок Match (Match._ensure_fx_directors), шина Crowd.
##
## Возбуждение excitement 0..1 растёт от событий и стекает к базе фазы (BASELINE; HP бойца ≤ LOW_HP_FRAC — «напряжение», база
## выше). Три петли (assets/audio/crowd/loop_calm / loop_engaged / loop_roar) играют всё время, их громкости — равномощное
## смешивание по сглаженному level (подъём ATTACK_S, спад RELEASE_S): гул трибун → оживление → рёв. Музыке GameAudio уходит
## та же величина как «интенсивность» (срез фильтра).
## Реакции (разовые, стерео, задержка REACT_DELAY_MS — живая толпа отвечает не мгновенно, не чаще REACT_GAP_MS):
##   heavy — «ооо» (шанс OOH_CHANCE), удар о стену на скорости — «ооо»; комбо от 4 и шквал (FLURRY_HITS ударов за FLURRY_S) —
##   одобрение; долгий полёт — «ооо»;
##   крит (SfxDirector.crit_phase): стоп-кадр — толпа замирает (DUCK_CRIT_DB), подпись — вздох, выход из крупного плана — рёв;
##   KO — рёв и аплодисменты; FIGHT! — одобрение; SUDDEN DEATH — «ооо»; конец матча — рёв и аплодисменты;
##   никто не бьёт IDLE_BOO_S — свист и «бууу» (и толпа скучает).
## GameAudio.crowd_on = false — шина Crowd заглушена (логика идёт, журнал пишется). reactions — журнал для проб [{ms, layer, why}].
class_name CrowdDirector
extends Node

const GROUP := "crowd_director"
const DIR := "res://assets/audio/crowd/"
const LOOPS := ["loop_calm", "loop_engaged", "loop_roar"]
const SHOTS := ["crowd_ooh", "crowd_gasp", "crowd_cheer", "crowd_roar", "crowd_applause", "crowd_boo"]
const SHOT_DB := {"crowd_ooh": -1.0, "crowd_gasp": -2.0, "crowd_cheer": -1.0, "crowd_roar": 1.0, "crowd_applause": -3.0,
	"crowd_boo": -4.0}
const BUS := "Crowd"
const LOOP_DB := -2.0
const LIFT_DB := 4.0                    # level 0 → −LIFT_DB/2, level 1 → +LIFT_DB/2
const DUCK_CRIT_DB := -12.0
const SHOT_VOICES := 4
## База возбуждения по фазе Match (COUNTDOWN, FIGHT, SUDDEN_DEATH, OVER).
const BASELINE := [0.15, 0.22, 0.5, 0.3]
const LOW_HP_FRAC := 0.25
const LOW_HP_FLOOR := 0.45
const DECAY_PER_S := 0.1
const ATTACK_S := 0.35
const RELEASE_S := 2.5
const REACT_DELAY_MS := Vector2(120.0, 320.0)
const REACT_GAP_MS := 900.0
const OOH_CHANCE := 0.55
const IDLE_BOO_S := 9.0
const IDLE_REPEAT_S := 14.0
const FLURRY_HITS := 4                 # ударов за FLURRY_S — «шквал»: одобрение трибун
const FLURRY_S := 3.0
const FLURRY_GAP_S := 6.0
const FLIGHT_OOH_SPEED := 7.0
const FLIGHT_OOH_S := 0.45

var excitement := 0.15
var level := 0.15
var reactions: Array = []
var enabled := true
## Звуковая доска: возбуждение не стекает к базе (держит ползунок).
var hold := false

var _loops: Array[AudioStreamPlayer] = []
var _shots: Array[AudioStreamPlayer] = []
var _rs: Dictionary = {}                # слой -> AudioStreamRandomizer
var _match: Node
var _sfx: SfxDirector
var _phase := 0
var _pending: Array = []                # [{at, layer, db, why}]
var _last_react_ms := -1.0e9
var _last_hit_ms := -1.0e9
var _last_idle_ms := -1.0e9
var _crit_duck := false
var _duck_db := 0.0
var _hit_times: Array = []              # мс ударов за последние FLURRY_S
var _flurry_ms := -1.0e9
var _flight_t: Dictionary = {}          # instance_id куклы -> с в быстром полёте
var _flight_done: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _t0 := -1.0


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 53
	_t0 = Time.get_ticks_msec()
	SfxDirector.ensure_buses()
	for i in LOOPS.size():
		var p := AudioStreamPlayer.new()
		p.name = "Loop_" + String(LOOPS[i])
		p.bus = BUS
		var s := load(DIR + String(LOOPS[i]) + ".ogg") as AudioStream
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		_loops.append(p)
		if s != null:
			p.play(_rng.randf_range(0.0, maxf(s.get_length() - 1.0, 0.0)))
	for i in SHOT_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Shot%d" % i
		p.bus = BUS
		add_child(p)
		_shots.append(p)
	for layer in SHOTS:
		_rs[layer] = _make_layer(String(layer))
	call_deferred("_bind")


static func _make_layer(layer: String) -> AudioStreamRandomizer:
	return _make_layer_at(DIR + layer)


## AudioStreamRandomizer из всех *.ogg папки dir (без повторов подряд, питч ±4 %, громкость ±1 дБ).
static func _make_layer_at(dir: String) -> AudioStreamRandomizer:
	var rs := AudioStreamRandomizer.new()
	rs.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	rs.random_pitch = 1.04
	rs.random_volume_offset_db = 1.0
	var names: Array = []
	for f in DirAccess.get_files_at(dir):
		var n := String(f).trim_suffix(".import").trim_suffix(".remap")
		if n.ends_with(".ogg") and not names.has(n):
			names.append(n)
	names.sort()
	for n in names:
		var s := load(dir + "/" + n) as AudioStream
		if s != null:
			rs.add_stream(-1, s, 1.0)
	return rs


func _now() -> float:
	return Time.get_ticks_msec() - _t0 if _sfx == null or not is_instance_valid(_sfx) else _sfx.clock_ms()


func _bind() -> void:
	_match = get_parent() if get_parent() != null and get_parent().is_in_group("match") else get_tree().get_first_node_in_group("match")
	_sfx = get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	if _match != null:
		for pair in [["hit_fx", _on_hit_fx], ["env_slam", _on_env_slam], ["ko", _on_ko], ["announce", _on_announce],
				["match_over", _on_match_over], ["phase_changed", _on_phase]]:
			if _match.has_signal(pair[0]) and not _match.is_connected(pair[0], pair[1]):
				_match.connect(pair[0], pair[1])
		var ph: Variant = _match.get("phase")
		if ph is int:
			_phase = int(ph)
	if _sfx != null and not _sfx.crit_phase.is_connected(_on_crit_phase):
		_sfx.crit_phase.connect(_on_crit_phase)
	_last_hit_ms = _now()


# --- события ---

func _on_hit_fx(ctx: Dictionary) -> void:
	var now := _now()
	_last_hit_ms = now
	_hit_times.append(now)
	while not _hit_times.is_empty() and now - float(_hit_times[0]) > FLURRY_S * 1000.0:
		_hit_times.remove_at(0)
	if _hit_times.size() >= FLURRY_HITS and now - _flurry_ms >= FLURRY_GAP_S * 1000.0:
		_flurry_ms = now
		bump(0.12)
		react("crowd_cheer", -3.0, "flurry")
	var tier := String(ctx.get("tier", "light"))
	var combo := int(ctx.get("combo", 0))
	match tier:
		"light":
			bump(0.025 * (1.0 + 0.2 * float(combo)))
		"heavy":
			bump(0.12)
			if _rng.randf() < OOH_CHANCE:
				react("crowd_ooh", 0.0, "heavy")
		"ko", "ko_crit", "crit":
			bump(0.2)


func _on_env_slam(ctx: Dictionary) -> void:
	var sp := float(ctx.get("speed", 0.0))
	bump(clampf((sp - 4.0) / 8.0, 0.0, 1.0) * 0.1 + 0.03)
	if sp >= 9.0 and _rng.randf() < 0.45:
		react("crowd_ooh", -2.0, "slam")


func _on_ko(_victim: Node, _attacker: Node, _record: Dictionary) -> void:
	_last_hit_ms = _now()
	excitement = 1.0
	if _crit_duck:
		react("crowd_applause", 0.0, "ko", true, 2200.0)   # ko_crit: рёв — на выходе из крупного плана (crit_phase cut_out)
		return
	react("crowd_roar", 0.0, "ko", true, 150.0)
	react("crowd_applause", 0.0, "ko", true, 1600.0)


func _on_announce(text: String, _c: Color, kind: String) -> void:
	match kind:
		"fight":
			excitement = maxf(excitement, 0.55)
			react("crowd_cheer", 0.0, "fight", true, 250.0)
		"sudden_death":
			excitement = maxf(excitement, 0.6)
			react("crowd_ooh", 0.0, "sudden_death", true)
		"combo":
			var n := text.to_int()
			bump(0.05 * float(maxi(n - 2, 0)))
			if n >= 4:
				react("crowd_cheer", -2.0, "combo")


func _on_match_over(_winner: Node, _results: Dictionary) -> void:
	excitement = maxf(excitement, 0.9)
	react("crowd_roar", 0.0, "over", true, 350.0)
	react("crowd_applause", 0.0, "over", true, 1400.0)


func _on_phase(p: int) -> void:
	_phase = p
	if p == Match.Phase.COUNTDOWN:
		_pending.clear()
		_crit_duck = false
		excitement = BASELINE[0]
		_last_hit_ms = _now()
		_last_idle_ms = -1.0e9


## SfxDirector.crit_phase: freeze — толпа замирает, caption — вздох, cut_out — рёв, short — рёв сразу.
func _on_crit_phase(name_: String, _ms: float) -> void:
	_last_hit_ms = _now()
	match name_:
		"freeze":
			_crit_duck = true
		"caption":
			react("crowd_gasp", 2.0, "crit", true, 0.0)
		"cut_out":
			_crit_duck = false
			excitement = 1.0
			react("crowd_roar", 0.0, "crit", true, 0.0)
		"done", "aborted":
			_crit_duck = false
		"short":
			excitement = 1.0
			react("crowd_roar", -1.0, "crit_short", true, 150.0)


## Поднять возбуждение.
func bump(x: float) -> void:
	excitement = clampf(excitement + x, 0.0, 1.0)


## Реакция толпы: слой SHOTS через REACT_DELAY_MS (или delay_ms ≥ 0); force — мимо REACT_GAP_MS.
func react(layer: String, db: float, why: String, force := false, delay_ms := -1.0) -> void:
	var now := _now()
	if not force and now - _last_react_ms < REACT_GAP_MS:
		return
	_last_react_ms = now
	var d := delay_ms if delay_ms >= 0.0 else _rng.randf_range(REACT_DELAY_MS.x, REACT_DELAY_MS.y)
	_pending.append({"at": now + d, "layer": layer, "db": db, "why": why})


func _play_shot(layer: String, db: float, why: String) -> void:
	var rs: AudioStreamRandomizer = _rs.get(layer, null)
	if not enabled or rs == null or rs.streams_count == 0:
		return
	var best := 0
	for i in _shots.size():
		if not _shots[i].playing:
			best = i
			break
		if _shots[i].get_playback_position() > _shots[best].get_playback_position():
			best = i                        # все заняты — самый давний
	var p := _shots[best]
	p.stream = rs
	p.volume_db = float(SHOT_DB.get(layer, 0.0)) + db
	p.play()
	reactions.append({"ms": snappedf(_now(), 0.1), "layer": layer, "why": why})
	if reactions.size() > 512:
		reactions.remove_at(0)


# --- кадр ---

func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	var now := _now()
	if not _pending.is_empty():
		var due: Array = []
		var i := 0
		while i < _pending.size():
			if float(_pending[i]["at"]) <= now:
				due.append(_pending[i])
				_pending.remove_at(i)
			else:
				i += 1
		for e in due:
			_play_shot(String(e["layer"]), float(e["db"]), String(e["why"]))
	var base := _baseline()
	if _phase == Match.Phase.FIGHT or _phase == Match.Phase.SUDDEN_DEATH:
		var idle_s := (now - _last_hit_ms) / 1000.0
		if idle_s >= IDLE_BOO_S:
			base = minf(base, 0.08)
			if now - _last_idle_ms >= IDLE_REPEAT_S * 1000.0:
				_last_idle_ms = now
				react("crowd_boo", 0.0, "idle", true)
		_tick_flights(real, now)
	if not hold:
		excitement = move_toward(excitement, base, DECAY_PER_S * real) if excitement > base else lerpf(excitement, base, minf(real * 2.0, 1.0))
	var tau := ATTACK_S if excitement > level else RELEASE_S
	level = lerpf(level, excitement, 1.0 - exp(-real / tau))
	_duck_db = move_toward(_duck_db, DUCK_CRIT_DB if _crit_duck else 0.0, real * (80.0 if _crit_duck else 30.0))
	_apply_loops()
	var ga := get_node_or_null("/root/GameAudio")
	if ga != null:
		ga.set_intensity(level)


func _baseline() -> float:
	var b: float = BASELINE[clampi(_phase, 0, BASELINE.size() - 1)]
	if _match != null and is_instance_valid(_match) and _match.has_method("dolls"):
		for d in _match.call("dolls"):
			var doll := d as Doll
			if doll != null and doll.alive and doll.hp <= doll.max_hp * LOW_HP_FRAC:
				b = maxf(b, LOW_HP_FLOOR)
	return b


## Веса петель (равномощно): calm → engaged → roar по level.
static func loop_weights(x: float) -> PackedFloat32Array:
	var w_calm := clampf(1.0 - x * 2.0, 0.0, 1.0)
	var w_eng := clampf(1.0 - absf(x - 0.5) * 2.0, 0.0, 1.0)
	var w_roar := clampf(x * 2.0 - 1.0, 0.0, 1.0)
	return PackedFloat32Array([w_calm, w_eng, w_roar])


func _apply_loops() -> void:
	var w := loop_weights(level)
	var lift := (level - 0.5) * LIFT_DB + _duck_db
	for i in _loops.size():
		var g := sqrt(w[i])
		_loops[i].volume_db = LOOP_DB + lift + (linear_to_db(g) if g > 0.001 else -80.0)


func _tick_flights(real: float, _now_ms: float) -> void:
	if _match == null or not is_instance_valid(_match) or not _match.has_method("dolls"):
		return
	for d in _match.call("dolls"):
		var doll := d as Doll
		if doll == null or not doll.alive:
			continue
		var id := doll.get_instance_id()
		var fast := doll.is_flying() and SfxDirector.com_velocity(doll).length() >= FLIGHT_OOH_SPEED
		if fast:
			_flight_t[id] = float(_flight_t.get(id, 0.0)) + real
			if float(_flight_t[id]) >= FLIGHT_OOH_S and not bool(_flight_done.get(id, false)):
				_flight_done[id] = true
				bump(0.1)
				react("crowd_ooh", -1.0, "flight")
		else:
			_flight_t[id] = 0.0
			_flight_done[id] = false


## Петли играют (проба: crowd жив и не молчит).
func loops_playing() -> int:
	var n := 0
	for p in _loops:
		if p.playing:
			n += 1
	return n


func loop_volumes() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in _loops:
		out.append(p.volume_db)
	return out
