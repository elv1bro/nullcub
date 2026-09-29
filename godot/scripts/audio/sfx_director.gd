## Звук ударов «как в боевике» (docs/plan-demo/HIT_FX.md §2.5, §4.4). Сцена scenes/audio/sfx_director.tscn: пул из VOICES
## AudioStreamPlayer (Voice00…Voice11) и слои-AudioStreamRandomizer в `layers` (сборка — tools/audio/build_sfx_director_scene.gd
## из папок assets/audio/sfx/<слой>/; ассеты и лицензии — tools/audio/gen_hitfx_audio.py, assets/audio/sfx/LICENSES.md).
## Узел «SfxDirector» — ребёнок Match (Match._ensure_fx_directors) или любой узел сцены с Match в группе "match".
##
## Подписки (через has_signal — работает и до, и после появления сигналов у ядра):
##   Match.hit_fx(ctx) → по ctx.tier: light — «ток» дерева (не чаще раза в 60 мс на жертву); heavy — удар + треск + низкий тумп,
##     «вух» отлёта через 70 мс по скорости ЦМ жертвы; crit/ko_crit — вдох-реверс в стоп-кадре → бум + треск + скрип волокна на
##     крупном плане (мир глохнет: low-pass на шине SFX) → «ох» толпы → второй треск («перелом») → свист и «вух» на выходе;
##     ko — тумп поверх звука KO. Без hit_fx (старое ядро) — Match.hit с упрощённым уровнем light/heavy/ko.
##   Match.env_slam(ctx) → глухой тумп по скорости; в крит-полёте ещё треск и crash.
##   Match.ko → удар KO + треск + рассыпание, аплодисменты через 300 мс (ko_crit — после выхода из крупного плана, 700 мс).
##   Match.announce → FIGHT! — гонг, SUDDEN DEATH — два удара, отсчёт — тихий стук; Match.match_over — три удара гонга.
##   Match.phase_changed → COUNTDOWN (restart) / OVER без KO — abort_all(). CritCinematic.phase — синхронизация крита (иначе
##     свой таймлайн по тем же мс, HIT_FX.md §3.1).
## Шины создаются в рантайме (project.godot и default_bus_layout не нужны): SFX → Master (LowPass выкл. → Compressor →
## HardLimiter −0.5 dB), SFX_PanL2/L1/R1/R2 → SFX (AudioEffectPanner ±0.25/±0.5 — панорама по X экрана), SFX_Crit → Master
## (в обход LowPass, HardLimiter). Громкость обеих — Tuning.HITFX_SFX_VOLUME_DB.
## Время: все задержки по нескалированным часам (SceneTreeTimer с ignore_time_scale); в slow-mo (0.2 ≤ time_scale < 1) новые
## голоса ниже по питчу (× time_scale^0.2, не ниже 0.7; толпа и гонг — без), в стоп-кадре (< 0.2) питч не трогается.
## Лимиты: VOICES голосов (занятые вытесняются по приоритету), слой не чаще раза в LAYER_GAP_MS, не больше MAX_PER_LAYER голосов слоя.
## Пробы читают played ([{layer, ms, db, pitch, bus, voice, ts}]), dropped, stolen (tests/sfx_probe.gd).
class_name SfxDirector
extends Node

const GROUP := "sfx_director"
const SFX_DIR := "res://assets/audio/sfx"
const LAYER_ORDER := ["tok", "punch", "crack", "thud", "boom", "zap_low", "whistle", "whoosh", "inhale", "creak", "crash",
	"shatter", "ko", "gong", "crowd_cheer", "crowd_oof"]
## Базовая громкость слоя (дБ; ассеты нормализованы по пику −1 dBFS, RMS разный) — микс по уровням §2.5.
const LAYER_DB := {
	"tok": 0.0, "punch": 0.0, "crack": -1.0, "thud": -6.0, "boom": -4.0, "zap_low": -8.0, "whistle": -7.0, "whoosh": -3.0,
	"inhale": -3.0, "creak": -3.0, "crash": -3.0, "shatter": -1.0, "ko": -2.0, "gong": -2.0, "crowd_cheer": -5.0, "crowd_oof": -6.0,
}
## Приоритет вытеснения: при занятых голосах новый звук забирает голос с приоритетом не выше своего (самый старый).
const LAYER_PRIORITY := {
	"tok": 0, "whoosh": 1, "thud": 1, "crack": 1, "creak": 2, "punch": 2, "crash": 2, "shatter": 2, "zap_low": 2, "whistle": 2,
	"crowd_oof": 2, "crowd_cheer": 2, "inhale": 3, "boom": 3, "ko": 3, "gong": 3,
}
const RANDOM_PITCH := 1.08              # AudioStreamRandomizer: питч ×[1/1.08, 1.08] (±8 %)
const RANDOM_VOLUME_DB := 1.5
const NO_SLOWMO_PITCH := ["gong", "crowd_cheer", "crowd_oof"]
const VOICES := 12
const LAYER_GAP_MS := 40.0
const MAX_PER_LAYER := 4
const LIGHT_VICTIM_GAP_MS := 60.0
const BUS_SFX := "SFX"
const BUS_CRIT := "SFX_Crit"
const PAN_BUSES := {-2: "SFX_PanL2", -1: "SFX_PanL1", 1: "SFX_PanR1", 2: "SFX_PanR2"}
const PAN_STEP := 0.25                  # панорама шины k — k × PAN_STEP
const PAN_WIDTH := 0.55                 # край экрана → |pan|
const LIMITER_CEILING_DB := -0.5
const MUFFLE_HZ := 900.0
const OPEN_HZ := 20000.0
const MUFFLE_IN_MS := 50.0
const MUFFLE_OUT_MS := 80.0
const MUFFLE_MAX_MS := 1500.0           # сторож: глушение не дольше (крит 120–700 мс)
const SLOWMO_PITCH_MIN_SCALE := 0.2
const SLOWMO_PITCH_EXP := 0.2
const SLOWMO_PITCH_MIN := 0.7
const CLOCK_SPAN_S := 1.0e6
# таймлайн крита (мс от удара; зеркало CritCinematic, HIT_FX.md §3.1)
const CRIT_CUT_IN_MS := 120.0
const CRIT_CAPTION_MS := 220.0
const CRIT_CRACK2_MS := 400.0
const CRIT_CUT_OUT_MS := 620.0
const CRIT_DONE_MS := 1300.0
const CRIT_SAME_MS := 30.0              # фаза freeze и hit_fx одного крита приходят в один кадр
const CRIT_SHORT_OOF_MS := 150.0
const CRIT_SHORT_WHOOSH_MS := 200.0
const KO_CHEER_MS := 300.0
const KO_CRIT_CHEER_MS := 700.0
const KO_RECENT_MS := 2500.0
const KO_DEDUPE_MS := 300.0
const HEAVY_WHOOSH_MS := 70.0
const WHOOSH_MIN_SPEED := 2.0           # м/с ЦМ: тише — без «вух»
const WHOOSH_FULL_SPEED := 7.5
const WHOOSH_POLL_SPEED := 5.0          # полёт (Doll.is_flying) быстрее — «вух» сам по себе: выше FLIGHT_MAX_SPEED 4.5 обычного
                                        # отброса RM (крит-полёт, броски); обычные отлёты — только «вух» heavy по событию
const WHOOSH_QUIET_MS := 700.0          # после крита опрос молчит (стоп-кадр — тишина, «вух» крита — на выходе из крупного плана)
const WHOOSH_DOLL_GAP_MS := 600.0
const SD_GONG_GAP_MS := 260.0
const OVER_GONG_GAP_MS := 220.0

@export var layers: Dictionary[String, AudioStreamRandomizer] = {}
@export var match_path: NodePath

var enabled := true
var volume_db: float = Tuning.HITFX_SFX_VOLUME_DB
## Тесты: "" — как решит директор; "cine" / "short" — принудительный вид крита.
var force_crit_mode := ""
var played: Array = []
var dropped := {"gap": 0, "rate": 0, "voices": 0, "layer_cap": 0, "missing": 0}
var stolen := 0
var bound: Array = []                   # имена подключённых сигналов (проба)

var _voices: Array[AudioStreamPlayer] = []
var _voice_until: PackedFloat64Array = PackedFloat64Array()
var _voice_start: PackedFloat64Array = PackedFloat64Array()
var _voice_prio: PackedInt32Array = PackedInt32Array()
var _voice_layer: PackedStringArray = PackedStringArray()
var _layer_len: Dictionary = {}         # слой -> максимальная длина (с)
var _last_layer_ms: Dictionary = {}
var _last_victim_ms: Dictionary = {}    # instance_id жертвы -> мс (лимит light)
var _ko_ms: Dictionary = {}             # instance_id жертвы -> мс звука KO
var _last_ko_ms := -1.0e9
var _whoosh_ms: Dictionary = {}         # instance_id куклы -> мс последнего «вух»
var _was_fast: Dictionary = {}
var _pending: Array = []                # [{at, kind, layer, db, pitch, bus, pan, tag, target}]
var _clock: SceneTreeTimer
var _match: Node
var _cine: Node
var _crit_mode := ""                    # "" | "cine" | "short"
var _crit_t0 := -1.0e9
var _crit_ctx: Dictionary = {}
var _crit_done: Dictionary = {}         # фазы текущего крита, уже озвученные
var _crit_synced := false
var _crit_forced := false               # force_crit_mode = "cine": кинематограф считается идущим (пробы)
var _quiet_poll_until := -1.0e9
var _muffle_target := 0.0               # 0 — открыто, 1 — заглушено
var _muffle_amt := 0.0
var _muffle_since := -1.0
var _rng := RandomNumberGenerator.new()
var _last_process_ms := -1.0


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 29
	_clock = get_tree().create_timer(CLOCK_SPAN_S, true, false, true)
	ensure_buses()
	_apply_volume()
	_collect_voices()
	if layers.is_empty():
		_load_layers_from_dirs()
	for layer in layers.keys():
		var rs: AudioStreamRandomizer = layers[layer]
		var mx := 0.0
		for i in range(rs.streams_count):
			var s := rs.get_stream(i)
			if s != null:
				mx = maxf(mx, s.get_length())
		_layer_len[layer] = mx
	call_deferred("_bind")


func _exit_tree() -> void:
	_pending.clear()
	_muffle_target = 0.0
	_muffle_amt = 0.0
	_apply_muffle()


# --- шины ---

## Создаёт шины SFX / SFX_PanL2…R2 / SFX_Crit, если их нет (идемпотентно; порядок: панорамные после SFX — посыл только влево).
static func ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) < 0:
		var i := _add_bus(BUS_SFX, "Master")
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = OPEN_HZ
		AudioServer.add_bus_effect(i, lpf)
		AudioServer.set_bus_effect_enabled(i, 0, false)
		var comp := AudioEffectCompressor.new()
		comp.threshold = -14.0
		comp.ratio = 2.5
		comp.attack_us = 3000.0
		comp.release_ms = 150.0
		AudioServer.add_bus_effect(i, comp)
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = LIMITER_CEILING_DB
		AudioServer.add_bus_effect(i, lim)
	for k in PAN_BUSES.keys():
		var name_: String = PAN_BUSES[k]
		if AudioServer.get_bus_index(name_) < 0:
			var j := _add_bus(name_, BUS_SFX)
			var pan := AudioEffectPanner.new()
			pan.pan = float(k) * PAN_STEP
			AudioServer.add_bus_effect(j, pan)
	if AudioServer.get_bus_index(BUS_CRIT) < 0:
		var c := _add_bus(BUS_CRIT, "Master")
		var lim2 := AudioEffectHardLimiter.new()
		lim2.ceiling_db = LIMITER_CEILING_DB
		AudioServer.add_bus_effect(c, lim2)
	# SFX и SFX_Crit ограничены по отдельности, но на Master их сумма клипала (клип hitfx-fight-v1, интеграция 29.09:
	# ~900 сэмплов у 0 dBFS) — общий лимитер на Master, если его ещё нет
	var m := AudioServer.get_bus_index("Master")
	var has_lim := false
	for e in range(AudioServer.get_bus_effect_count(m)):
		if AudioServer.get_bus_effect(m, e) is AudioEffectHardLimiter:
			has_lim = true
	if m >= 0 and not has_lim:
		var lim3 := AudioEffectHardLimiter.new()
		lim3.ceiling_db = LIMITER_CEILING_DB
		AudioServer.add_bus_effect(m, lim3)


static func _add_bus(name_: String, send: String) -> int:
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name_)
	AudioServer.set_bus_send(i, send)
	return i


func _apply_volume() -> void:
	for b in [BUS_SFX, BUS_CRIT]:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, volume_db)


func set_volume_db(db: float) -> void:
	volume_db = db
	_apply_volume()


func _lowpass() -> AudioEffectLowPassFilter:
	var i := AudioServer.get_bus_index(BUS_SFX)
	if i < 0 or AudioServer.get_bus_effect_count(i) == 0:
		return null
	return AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter


## Мир глохнет (крупный план крита): low-pass MUFFLE_HZ на шине SFX за MUFFLE_IN_MS; снятие за MUFFLE_OUT_MS. SFX_Crit не глохнет.
func set_muffle(on: bool, instant: bool = false) -> void:
	_muffle_target = 1.0 if on else 0.0
	if on and _muffle_since < 0.0:
		_muffle_since = clock_ms()
	if not on:
		_muffle_since = -1.0
	if instant:
		_muffle_amt = _muffle_target
		_apply_muffle()


func is_muffled() -> bool:
	return _muffle_target > 0.5


## Текущий срез low-pass шины SFX (OPEN_HZ, если фильтр выключен) — для проб.
func muffle_cutoff_hz() -> float:
	var lpf := _lowpass()
	var i := AudioServer.get_bus_index(BUS_SFX)
	if lpf == null or i < 0 or not AudioServer.is_bus_effect_enabled(i, 0):
		return OPEN_HZ
	return lpf.cutoff_hz


func _apply_muffle() -> void:
	var i := AudioServer.get_bus_index(BUS_SFX)
	var lpf := _lowpass()
	if lpf == null:
		return
	lpf.cutoff_hz = OPEN_HZ * pow(MUFFLE_HZ / OPEN_HZ, _muffle_amt)
	AudioServer.set_bus_effect_enabled(i, 0, _muffle_amt > 0.001)


# --- часы и голоса ---

## Нескалированные часы (мс): SceneTreeTimer с ignore_time_scale идёт шагом кадра Engine (с --fixed-fps 60 — ровно 16.7 мс).
func clock_ms() -> float:
	if _clock == null:
		return 0.0
	return (CLOCK_SPAN_S - _clock.time_left) * 1000.0


func _collect_voices() -> void:
	_voices.clear()
	for c in get_children():
		if c is AudioStreamPlayer:
			_voices.append(c as AudioStreamPlayer)
	while _voices.size() < VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%02d" % _voices.size()
		add_child(p)
		_voices.append(p)
	_voice_until.resize(_voices.size())
	_voice_start.resize(_voices.size())
	_voice_prio.resize(_voices.size())
	_voice_layer.resize(_voices.size())
	for v in range(_voices.size()):
		_voice_until[v] = -1.0
		_voice_start[v] = -1.0
		_voice_layer[v] = ""


## Слои из папок assets/audio/sfx/<слой>/*.ogg — запасной путь, если скрипт создан без сцены.
func _load_layers_from_dirs() -> void:
	for layer in LAYER_ORDER:
		var rs := make_layer(layer)
		if rs.streams_count > 0:
			layers[layer] = rs


static func make_layer(layer: String) -> AudioStreamRandomizer:
	var rs := AudioStreamRandomizer.new()
	rs.resource_name = layer
	rs.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	rs.random_pitch = RANDOM_PITCH
	rs.random_volume_offset_db = RANDOM_VOLUME_DB
	var dir := "%s/%s" % [SFX_DIR, layer]
	var names: Array = []
	for f in DirAccess.get_files_at(dir):
		var n := String(f).trim_suffix(".import").trim_suffix(".remap")
		if n.ends_with(".ogg") and not names.has(n):
			names.append(n)
	names.sort()
	for n in names:
		var s := load("%s/%s" % [dir, n]) as AudioStream
		if s != null:
			rs.add_stream(-1, s, 1.0)
	return rs


func voice_count() -> int:
	return _voices.size()


func voice(i: int) -> AudioStreamPlayer:
	return _voices[i] if i >= 0 and i < _voices.size() else null


func active_voices() -> int:
	var now := clock_ms()
	var n := 0
	for v in range(_voices.size()):
		if _voice_busy(v, now):
			n += 1
	return n


func _voice_busy(v: int, now: float) -> bool:
	return _voice_until[v] > now and _voices[v].playing


func _layer_active(layer: String, now: float) -> int:
	var n := 0
	for v in range(_voices.size()):
		if _voice_layer[v] == layer and _voice_busy(v, now):
			n += 1
	return n


func _pick_voice(now: float, prio: int) -> int:
	var steal := -1
	for v in range(_voices.size()):
		if not _voice_busy(v, now):
			return v
		if _voice_prio[v] <= prio and (steal < 0 or _voice_prio[v] < _voice_prio[steal]
				or _voice_prio[v] == _voice_prio[steal] and _voice_start[v] < _voice_start[steal]):
			steal = v
	if steal >= 0:
		_voices[steal].stop()
		stolen += 1
	return steal


## Питч-множитель замедления: в slow-mo (0.2 ≤ time_scale < 1) ниже, в стоп-кадре и на 1× — 1.
static func time_pitch(ts: float) -> float:
	if ts >= 0.999 or ts < SLOWMO_PITCH_MIN_SCALE:
		return 1.0
	return clampf(pow(ts, SLOWMO_PITCH_EXP), SLOWMO_PITCH_MIN, 1.0)


func _route_bus(bus: String, pan: float) -> String:
	if bus != BUS_SFX:
		return bus
	var k := clampi(roundi(pan / PAN_STEP), -2, 2)
	return PAN_BUSES[k] if k != 0 else BUS_SFX


## Играет слой: громкость LAYER_DB + volume_db, питч (× замедление), шина (SFX + панорама pan −1…1 | SFX_Crit).
## Возвращает индекс голоса или −1 (выключен, слоя нет, чаще LAYER_GAP_MS, MAX_PER_LAYER, нет голоса по приоритету).
func play_layer(layer: String, volume_db_: float = 0.0, pitch: float = 1.0, bus: String = BUS_SFX, pan: float = 0.0) -> int:
	if not enabled:
		return -1
	var rs: AudioStreamRandomizer = layers.get(layer, null)
	if rs == null or rs.streams_count == 0:
		dropped["missing"] = int(dropped["missing"]) + 1
		return -1
	var now := clock_ms()
	if now - float(_last_layer_ms.get(layer, -1.0e9)) < LAYER_GAP_MS:
		dropped["gap"] = int(dropped["gap"]) + 1
		return -1
	if _layer_active(layer, now) >= MAX_PER_LAYER:
		dropped["layer_cap"] = int(dropped["layer_cap"]) + 1
		return -1
	var prio: int = LAYER_PRIORITY.get(layer, 1)
	var v := _pick_voice(now, prio)
	if v < 0:
		dropped["voices"] = int(dropped["voices"]) + 1
		return -1
	var ts := Engine.time_scale
	var p := pitch * (1.0 if NO_SLOWMO_PITCH.has(layer) else time_pitch(ts))
	var pl := _voices[v]
	pl.stream = rs
	pl.volume_db = float(LAYER_DB.get(layer, 0.0)) + volume_db_
	pl.pitch_scale = clampf(p, 0.25, 4.0)
	pl.bus = _route_bus(bus, pan)
	pl.play()
	_voice_until[v] = now + float(_layer_len.get(layer, 0.5)) * RANDOM_PITCH / pl.pitch_scale * 1000.0 + 20.0
	_voice_start[v] = now
	_voice_prio[v] = prio
	_voice_layer[v] = layer
	_last_layer_ms[layer] = now
	played.append({"layer": layer, "ms": snappedf(now, 0.1), "db": snappedf(pl.volume_db, 0.01), "pitch": snappedf(pl.pitch_scale, 0.001),
		"bus": String(pl.bus), "voice": v, "ts": snappedf(ts, 0.001)})
	if played.size() > 4096:
		played.remove_at(0)
	return v


func _schedule(delay_ms: float, layer: String, db: float, pitch: float, bus: String, pan: float, tag: String) -> void:
	_pending.append({"at": clock_ms() + delay_ms, "kind": "layer", "layer": layer, "db": db, "pitch": pitch, "bus": bus, "pan": pan, "tag": tag})


func _schedule_call(delay_ms: float, kind: String, tag: String, target: Variant = null, extra: Dictionary = {}) -> void:
	var e := {"at": clock_ms() + delay_ms, "kind": kind, "tag": tag, "target": target}
	e.merge(extra)
	_pending.append(e)


func cancel_tag(tag: String) -> void:
	var i := 0
	while i < _pending.size():
		if String(_pending[i]["tag"]) == tag:
			_pending.remove_at(i)
		else:
			i += 1


func pending_count() -> int:
	return _pending.size()


## Сброс: отложенные звуки сняты, глушение снято сразу, крит забыт (restart, OVER без KO, выход).
func abort_all() -> void:
	_pending.clear()
	_crit_mode = ""
	_crit_done.clear()
	_crit_synced = false
	_crit_forced = false
	set_muffle(false, true)


func _process(_delta: float) -> void:
	var now := clock_ms()
	var dt_ms := 16.7 if _last_process_ms < 0.0 else clampf(now - _last_process_ms, 1.0, 100.0)
	_last_process_ms = now
	if not _pending.is_empty():
		var due: Array = []
		var i := 0
		while i < _pending.size():
			if float(_pending[i]["at"]) <= now:
				due.append(_pending[i])
				_pending.remove_at(i)
			else:
				i += 1
		due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))
		for e in due:
			_run_pending(e)
	# глушение: плавный срез, сторож
	if _muffle_target > 0.5 and _muffle_since >= 0.0 and now - _muffle_since > MUFFLE_MAX_MS:
		set_muffle(false)
	if not is_equal_approx(_muffle_amt, _muffle_target):
		var step := dt_ms / (MUFFLE_IN_MS if _muffle_target > _muffle_amt else MUFFLE_OUT_MS)
		_muffle_amt = move_toward(_muffle_amt, _muffle_target, step)
		_apply_muffle()
	if _crit_mode == "cine":
		if not is_instance_valid(_cine):
			_bind_cinematic()
		if now - _crit_t0 > CRIT_DONE_MS + 400.0:
			_crit_phase("done")
	_poll_flights(now)



func _run_pending(e: Dictionary) -> void:
	match String(e["kind"]):
		"layer":
			play_layer(String(e["layer"]), float(e["db"]), float(e["pitch"]), String(e["bus"]), float(e["pan"]))
		"phase":
			_crit_phase(String(e["phase"]))
		"whoosh":
			var target: Variant = e["target"]
			if is_instance_valid(target) and target is Node:
				_whoosh(target as Node, float(e.get("min_db", -99.0)), String(e.get("bus", BUS_SFX)))


# --- подписки ---

func _find_match() -> Node:
	if match_path != NodePath():
		var m := get_node_or_null(match_path)
		if m != null:
			return m
	var p := get_parent()
	if p != null and p.is_in_group("match"):
		return p
	return get_tree().get_first_node_in_group("match") if is_inside_tree() else null


func _bind() -> void:
	_match = _find_match()
	if _match == null:
		return
	bound.clear()
	if _match.has_signal("hit_fx"):
		_connect(_match, "hit_fx", handle_hit_fx)
	elif _match.has_signal("hit"):
		_connect(_match, "hit", _on_legacy_hit)
	for pair in [["env_slam", handle_env_slam], ["ko", handle_ko], ["announce", handle_announce],
			["phase_changed", handle_phase], ["match_over", handle_match_over]]:
		if _match.has_signal(pair[0]):
			_connect(_match, pair[0], pair[1])
	_bind_cinematic()


func _connect(obj: Object, sig: String, cb: Callable) -> void:
	if not obj.is_connected(sig, cb):
		obj.connect(sig, cb)
	if not bound.has(sig):
		bound.append(sig)


func _hit_fx_director() -> Node:
	if _match != null and is_instance_valid(_match):
		for c in _match.get_children():
			if c.is_in_group("hit_fx_director"):
				return c
	return get_tree().get_first_node_in_group("hit_fx_director") if is_inside_tree() else null


## Ищет CritCinematic (узел с сигналом phase и is_playing() под HitFxDirector) и подписывается на phase.
func _bind_cinematic() -> void:
	if is_instance_valid(_cine):
		return
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group("crit_cinematic"):
			if n.has_signal("phase") and n.has_method("is_playing"):
				bind_cinematic(n)
				return
	var hfd := _hit_fx_director()
	if hfd == null:
		return
	for n in hfd.find_children("*", "", true, false):
		if n.has_signal("phase") and n.has_method("is_playing"):
			bind_cinematic(n)
			return


func bind_cinematic(n: Node) -> void:
	_cine = n
	var cb := Callable(self, "handle_cine_phase")
	if not n.is_connected("phase", cb):
		n.connect("phase", cb)
	if not bound.has("phase"):
		bound.append("phase")
	if n.has_signal("aborted"):
		var cb2 := Callable(self, "handle_cine_aborted")
		if not n.is_connected("aborted", cb2):
			n.connect("aborted", cb2)
		if not bound.has("aborted"):
			bound.append("aborted")


## CritCinematic.aborted (restart, замена куклы, сторож): крит-звуки из очереди сняты, мир открыт сразу.
func handle_cine_aborted(_ctx: Variant = null) -> void:
	if _crit_mode != "cine":
		return
	cancel_tag("crit_phase")
	_crit_mode = ""
	_crit_done.clear()
	_crit_synced = false
	_crit_forced = false
	set_muffle(false, true)


# --- события ---

## Match.hit_fx(ctx) — HIT_FX.md §4.1: victim, attacker, damage, kind, part, position, tier, is_ko, …
func handle_hit_fx(ctx: Dictionary) -> void:
	if not enabled:
		return
	var tier := String(ctx.get("tier", "light"))
	var pos: Vector3 = ctx.get("position", Vector3.ZERO)
	var pan := pan_for(pos)
	match tier:
		"light":
			_play_light(ctx, pan)
		"heavy":
			_play_heavy(ctx, pan)
		"ko":
			_play_ko_hit(ctx, pan)
		"crit":
			_play_crit(ctx, pan, false)
		"ko_crit":
			_play_ko_hit(ctx, pan)
			_play_crit(ctx, pan, true)


## Старое ядро без hit_fx: уровень из урона (light/heavy по HITFX_HEAVY_SCORE, ko — жертва мертва), без крита.
func _on_legacy_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3) -> void:
	if damage <= 0.0 or kind == "environment":
		return
	var part := String(victim.last_hit.get("part", "")) if victim != null else ""
	var score := damage * (1.0 + Tuning.CRIT_HEAD_BONUS * float(part.begins_with("Head")))
	var tier := "heavy" if score >= Tuning.HITFX_HEAVY_SCORE else "light"
	if victim != null and not victim.alive:
		tier = "ko"
	handle_hit_fx({"victim": victim, "attacker": attacker, "damage": damage, "kind": kind, "position": position, "tier": tier,
		"score": score, "is_ko": tier == "ko", "part": part})


func _victim_id(ctx: Dictionary) -> int:
	var v: Variant = ctx.get("victim", null)
	return (v as Object).get_instance_id() if is_instance_valid(v) else 0


func _play_light(ctx: Dictionary, pan: float) -> void:
	var now := clock_ms()
	var vid := _victim_id(ctx)
	if now - float(_last_victim_ms.get(vid, -1.0e9)) < LIGHT_VICTIM_GAP_MS:
		dropped["rate"] = int(dropped["rate"]) + 1
		return
	_last_victim_ms[vid] = now
	var k := clampf(float(ctx.get("damage", 0.0)) / maxf(Tuning.HITFX_HEAVY_SCORE, 0.01), 0.0, 1.0)
	play_layer("tok", lerpf(-10.0, -4.0, k), _rng.randf_range(1.15, 1.3), BUS_SFX, pan)


func _play_heavy(ctx: Dictionary, pan: float) -> void:
	var k := clampf((float(ctx.get("damage", 0.0)) - Tuning.HITFX_HEAVY_SCORE) / 20.0, 0.0, 1.0)
	play_layer("punch", lerpf(-3.0, 0.0, k), _rng.randf_range(0.95, 1.05), BUS_SFX, pan)
	play_layer("crack", lerpf(-5.0, -2.0, k), _rng.randf_range(1.15, 1.35), BUS_SFX, pan)
	play_layer("thud", -3.0, 0.7, BUS_SFX, pan)
	_schedule_call(HEAVY_WHOOSH_MS, "whoosh", "whoosh", ctx.get("victim", null))


func _play_ko_hit(ctx: Dictionary, pan: float) -> void:
	var vid := _victim_id(ctx)
	var now := clock_ms()
	if now - float(_ko_ms.get(vid, -1.0e9)) > KO_DEDUPE_MS:
		# Match.ko не пришёл (порядок сигналов другой) — звук KO отсюда
		var v: Variant = ctx.get("victim", null)
		handle_ko(v as Doll if is_instance_valid(v) and v is Doll else null, ctx.get("attacker", null), {"position": ctx.get("position", Vector3.ZERO)})
	play_layer("thud", -2.0, 0.65, BUS_SFX, pan)


func handle_ko(victim: Doll, _attacker: Node, record: Dictionary) -> void:
	if not enabled:
		return
	var pos: Vector3 = record.get("position", victim.centre_of_mass() if victim != null and is_instance_valid(victim) else Vector3.ZERO)
	var pan := pan_for(pos)
	var now := clock_ms()
	var vid := victim.get_instance_id() if victim != null and is_instance_valid(victim) else 0
	_ko_ms[vid] = now
	_last_ko_ms = now
	play_layer("ko", 0.0, _rng.randf_range(0.95, 1.05), BUS_SFX, pan)
	play_layer("crack", 0.0, 0.85, BUS_SFX, pan)
	play_layer("shatter", 0.0, 1.0, BUS_SFX, pan)
	cancel_tag("ko_cheer")
	var cheer_ms := KO_CHEER_MS
	if _crit_mode == "cine" and now - _crit_t0 < CRIT_CUT_OUT_MS:
		cheer_ms = maxf(KO_CRIT_CHEER_MS - (now - _crit_t0), KO_CHEER_MS)
	_schedule(cheer_ms, "crowd_cheer", 0.0, 1.0, BUS_SFX, 0.0, "ko_cheer")


## Крит: "cine" — стоп-кадр → крупный план (свой таймлайн или фазы CritCinematic), "short" — без крупного плана
## (HITFX_CRIT_CINEMATIC=false, нет HitFxDirector, или кинематограф занят прошлым критом).
func _play_crit(ctx: Dictionary, _pan: float, ko: bool) -> void:
	_bind_cinematic()
	var now := clock_ms()
	var mode := _crit_mode_for()
	_quiet_poll_until = now + WHOOSH_QUIET_MS
	if mode == "same":
		_crit_ctx = ctx
	elif mode == "cine":
		_crit_mode = "cine"
		_crit_t0 = now
		_crit_ctx = ctx
		_crit_done.clear()
		_crit_synced = false
		_crit_forced = force_crit_mode == "cine"
		cancel_tag("crit_phase")
		_crit_phase("freeze")
		for pair in [[CRIT_CUT_IN_MS, "cut_in"], [CRIT_CAPTION_MS, "caption"], [CRIT_CRACK2_MS, "crack_2"],
				[CRIT_CUT_OUT_MS, "cut_out"], [CRIT_DONE_MS, "done"]]:
			_schedule_call(float(pair[0]), "phase", "crit_phase", null, {"phase": pair[1]})
	else:
		play_layer("punch", 0.0, 0.8, BUS_CRIT)
		play_layer("thud", 0.0, 0.6, BUS_CRIT)
		play_layer("boom", -3.0, 1.0, BUS_CRIT)
		play_layer("crack", 0.0, 0.9, BUS_CRIT)
		play_layer("zap_low", -2.0, 0.5, BUS_CRIT)
		_schedule(CRIT_SHORT_OOF_MS, "crowd_oof", 0.0, 0.9, BUS_CRIT, 0.0, "crit_short")
		_schedule_call(CRIT_SHORT_WHOOSH_MS, "whoosh", "crit_short", ctx.get("victim", null), {"min_db": -6.0, "bus": BUS_CRIT})
	if ko and (mode == "cine" or mode == "same"):
		cancel_tag("ko_cheer")
		_schedule(maxf(KO_CRIT_CHEER_MS - (now - _crit_t0), 0.0), "crowd_cheer", 0.0, 1.0, BUS_SFX, 0.0, "ko_cheer")


func _crit_mode_for() -> String:
	var now := clock_ms()
	if _crit_mode == "cine" and now - _crit_t0 <= CRIT_SAME_MS and _crit_synced and not _crit_done.has("cut_in"):
		return "same"                       # фаза freeze этого крита пришла раньше hit_fx
	if _crit_mode == "cine" and now - _crit_t0 < CRIT_DONE_MS:
		return "short"                      # кинематограф занят прошлым критом (HIT_FX.md §3.3)
	if force_crit_mode != "":
		return force_crit_mode
	if is_instance_valid(_cine) and _cine.has_method("is_playing") and bool(_cine.call("is_playing")):
		var el := float(_cine.call("elapsed_ms")) if _cine.has_method("elapsed_ms") else 0.0
		return "cine" if el <= CRIT_SAME_MS else "short"
	var hfd := _hit_fx_director()
	if hfd == null:
		return "short"
	var on: Variant = hfd.get("crit_cinematic")
	var hfd_on: Variant = hfd.get("enabled")
	if on is bool and not on or hfd_on is bool and not hfd_on:
		return "short"
	return "cine"


## CritCinematic.phase(name, ms): фазы кинематографа ведут звук; свой таймлайн крита снимается.
func handle_cine_phase(name_: String, ms: float) -> void:
	if not enabled:
		return
	var now := clock_ms()
	if _crit_mode != "cine" or name_ == "freeze" and now - _crit_t0 > CRIT_SAME_MS:
		_crit_mode = "cine"
		_crit_t0 = now - ms
		_crit_done.clear()
		_quiet_poll_until = now + WHOOSH_QUIET_MS
	_crit_synced = true
	cancel_tag("crit_phase")
	_crit_phase(name_)


func _crit_phase(name_: String) -> void:
	if _crit_mode != "cine" or _crit_done.has(name_):
		return
	_crit_done[name_] = clock_ms() - _crit_t0
	match name_:
		"freeze":
			# «вдох»: короткий сухой удар и развёрнутый назад треск — обрывается на пике, дальше тишина стоп-кадра
			play_layer("punch", -8.0, 0.9, BUS_CRIT)
			play_layer("inhale", 0.0, 1.0, BUS_CRIT)
			set_muffle(true)
		"cut_in":
			play_layer("boom", 0.0, 1.0, BUS_CRIT)
			play_layer("thud", 0.0, 0.6, BUS_CRIT)
			play_layer("punch", 0.0, 0.8, BUS_CRIT)
			play_layer("zap_low", -2.0, 0.5, BUS_CRIT)
			play_layer("crack", 0.0, 0.9, BUS_CRIT)
			play_layer("creak", 0.0, 1.0, BUS_CRIT)
			if not _crit_synced and not _crit_forced and is_instance_valid(_cine) and _cine.has_method("is_playing") \
					and not bool(_cine.call("is_playing")):
				set_muffle(false)           # кинематограф не пошёл — мир не глушим
			else:
				set_muffle(true)
		"caption":
			play_layer("crowd_oof", 0.0, 0.9, BUS_CRIT)
		"crack_2":
			play_layer("crack", -1.0, 0.7, BUS_CRIT)
		"cut_out":
			play_layer("whistle", 0.0, 0.6, BUS_CRIT)
			var v: Variant = _crit_ctx.get("victim", null)
			if is_instance_valid(v) and v is Node:
				_whoosh(v as Node, -6.0, BUS_CRIT)
			set_muffle(false)
		"done":
			set_muffle(false)
			_crit_mode = ""
			_crit_synced = false
			_crit_forced = false


func handle_env_slam(ctx: Dictionary) -> void:
	if not enabled:
		return
	var speed := float(ctx.get("speed", 0.0))
	var k := clampf((speed - Tuning.HITFX_SLAM_SPEED) / 6.0, 0.0, 1.0)
	var pan := pan_for(ctx.get("position", Vector3.ZERO))
	play_layer("thud", lerpf(-10.0, 0.0, k), 0.6 * _rng.randf_range(0.95, 1.05), BUS_SFX, pan)
	if bool(ctx.get("crit_flight", false)):
		play_layer("crack", -1.0, 0.9, BUS_SFX, pan)
		play_layer("crash", 0.0, 1.0, BUS_SFX, pan)


func handle_announce(_text: String, _color: Color, kind: String) -> void:
	if not enabled:
		return
	match kind:
		"fight":
			play_layer("gong", 0.0, 1.0)
		"sudden_death":
			play_layer("gong", 0.0, 0.94)
			_schedule(SD_GONG_GAP_MS, "gong", 0.0, 0.94, BUS_SFX, 0.0, "gong")
		"countdown":
			play_layer("tok", -12.0, 0.62)


func handle_match_over(_winner: Node, _results: Dictionary) -> void:
	if not enabled:
		return
	play_layer("gong", 0.0, 1.0)
	_schedule(OVER_GONG_GAP_MS, "gong", 0.0, 1.0, BUS_SFX, 0.0, "gong")
	_schedule(OVER_GONG_GAP_MS * 2.0, "gong", 0.0, 1.0, BUS_SFX, 0.0, "gong")


func handle_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		abort_all()
	elif p == Match.Phase.OVER and clock_ms() - _last_ko_ms > KO_RECENT_MS:
		abort_all()


# --- «вух» отлёта ---

static func com_velocity(d: Node) -> Vector3:
	if not d is Doll:
		return (d as RigidBody3D).linear_velocity if d is RigidBody3D else Vector3.ZERO
	var p := Vector3.ZERO
	var m := 0.0
	for b in (d as Doll).parts.values():
		if is_instance_valid(b):
			p += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
			m += (b as RigidBody3D).mass
	return p / m if m > 0.0 else Vector3.ZERO


## «Вух» по скорости ЦМ: WHOOSH_MIN_SPEED → −12 dB / питч 0.85, WHOOSH_FULL_SPEED → 0 dB / 1.2; min_db — пол громкости (крит).
func _whoosh(d: Node, min_db: float = -99.0, bus: String = BUS_SFX) -> void:
	var now := clock_ms()
	var id := d.get_instance_id()
	if now - float(_whoosh_ms.get(id, -1.0e9)) < WHOOSH_DOLL_GAP_MS:
		return
	var sp := com_velocity(d).length()
	if sp < WHOOSH_MIN_SPEED and min_db < -90.0:
		return
	var k := clampf((sp - WHOOSH_MIN_SPEED) / (WHOOSH_FULL_SPEED - WHOOSH_MIN_SPEED), 0.0, 1.0)
	var pos: Vector3 = (d as Doll).centre_of_mass() if d is Doll else (d as Node3D).global_position if d is Node3D else Vector3.ZERO
	if play_layer("whoosh", maxf(lerpf(-12.0, 0.0, k), min_db), lerpf(0.85, 1.2, k), bus, pan_for(pos)) >= 0:
		_whoosh_ms[id] = now


func _poll_flights(now: float) -> void:
	if _match == null or not is_instance_valid(_match) or not _match.has_method("dolls"):
		return
	var quiet := _crit_mode != "" or now < _quiet_poll_until
	for d in _match.call("dolls"):
		var doll := d as Doll
		if doll == null or not doll.alive:
			continue
		var id := doll.get_instance_id()
		var fast := doll.is_flying() and com_velocity(doll).length() >= WHOOSH_POLL_SPEED
		if fast and not quiet and not bool(_was_fast.get(id, false)) and now - float(_whoosh_ms.get(id, -1.0e9)) >= WHOOSH_DOLL_GAP_MS:
			_whoosh(doll)
		_was_fast[id] = fast


# --- панорама ---

## Панорама по X экрана (−PAN_WIDTH…PAN_WIDTH) через текущую камеру; без камеры / за камерой — 0.
func pan_for(pos: Vector3) -> float:
	if not is_inside_tree():
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(pos):
		return 0.0
	var w := get_viewport().get_visible_rect().size.x
	if w <= 1.0:
		return 0.0
	return clampf((cam.unproject_position(pos).x / w * 2.0 - 1.0) * PAN_WIDTH, -PAN_WIDTH, PAN_WIDTH)
