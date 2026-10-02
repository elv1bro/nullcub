## Звук боя (docs/plan-demo/AUDIO.md §4.2; история — HIT_FX.md §2.5, §4.4). Сцена scenes/audio/sfx_director.tscn: пул из VOICES
## AudioStreamPlayer (Voice00…) и слои-AudioStreamRandomizer в `layers` (сборка — tools/audio/build_sfx_director_scene.gd из папок
## assets/audio/sfx/<слой>/ и assets/audio/ui/<слой>/; ассеты — tools/audio/build_audio.py, лицензии — assets/audio/LICENSES.md).
## Узел «SfxDirector» — ребёнок Match (Match._ensure_fx_directors), TrainingFeel или любой узел с Match в группе "match".
##
## Основа удара — записанный удар нужной силы, как в JS-версии (src/audio/sfx.ts; автор 02.10: «там было хорошо»): hit_l / hit_m /
## hit_h — «37 hits/punches» Independent.nu + Punch qubodup, разброс питча PUNCH_SPREAD полутонов, громкость по урону; тяжёлый
## приглушает музыку (GameAudio.duck). Материал (SoundMaterial) — тихая подложка: жертва (дерево / металл / кость / резина) ×
## чем били (сковорода — «БОНГ», меч и топор — «чок», молот и булава — звон); голова деревянной куклы — гулкий «бонк».
##   light — hit_l (сильнее — hit_m) + подложка материала; не чаще раза в 60 мс на жертву.
##   heavy — hit_h + бьющий + треск дерева (snap) + низ (sub), тише основы; «вух» отлёта через 70 мс по скорости ЦМ жертвы.
##   crit / ko_crit — вдох (inhale) в стоп-кадре → бум + удар + треск + низ + скрип волокна на крупном плане (мир глохнет: low-pass
##     на SFX и через GameAudio на толпе, фоне и музыке) → второй треск и щепки («перелом») → вух на выходе, мир открывается.
##   ko — удар KO (ko) + рассыпание + треск + низ, музыка проседает. Толпа — CrowdDirector (crit_phase этого узла и сигналы Match).
## Match.env_slam — глухой удар о пол/стену + удар (hit_l / hit_m) по скорости; в крит-полёте ещё hit_h, crash и треск.
## Match.announce: отсчёт — бип, FIGHT! — горн + колокол, SUDDEN DEATH — два колокола + низкий горн, комбо — нота выше с каждым
##   ударом, HEAD / BODY / DOUBLE BLOW — короткий акцент. Match.match_over — три колокола и стингер победы (GameAudio).
## Match.phase_changed → COUNTDOWN (restart) / OVER без KO — abort_all(). CritCinematic.phase — синхронизация крита.
## Каждой кукле Match.dolls() — ребёнок DollAudio (полёт, рывок, замах, скрип суставов, хват, отрыв деталей).
## Шины — GameAudio.ensure_buses(): SFX (+ панорама SFX_Pan*), SFX_Crit (мимо глушения), UI. Громкость — Tuning.HITFX_SFX_VOLUME_DB.
## Время: все задержки по нескалированным часам; в slow-mo (0.2 ≤ time_scale < 1) голоса ниже по питчу (× time_scale^0.2, не ниже
## 0.7; колокол, горн и UI — без), в стоп-кадре (< 0.2) питч не трогается.
## Лимиты: VOICES голосов (занятые вытесняются по приоритету), слой не чаще раза в LAYER_GAP_MS, не больше MAX_PER_LAYER голосов слоя.
## Пробы читают played ([{layer, ms, db, pitch, bus, voice, ts}]), dropped, stolen (tests/sfx_probe.gd, tests/audio_probe.gd).
class_name SfxDirector
extends Node

signal crit_phase(name: String, ms: float)

const GameAudioScript := preload("res://scripts/audio/game_audio.gd")
const GROUP := "sfx_director"
const SFX_DIR := "res://assets/audio/sfx"
const UI_DIR := "res://assets/audio/ui"
const LAYER_ORDER := ["hit_l", "hit_m", "hit_h", "ko", "wood_l", "wood_m", "wood_h", "metal_l", "metal_m", "metal_h", "head", "pan", "blade", "bone", "rubber",
	"snap", "splinter", "sub", "thud", "boom", "inhale", "creak", "crash", "shatter", "whoosh", "swing_l", "swing_h", "dash", "flip",
	"grab", "equip", "detach", "attach", "bell", "horn", "explosion", "clank", "scrape", "stun",
	"countdown", "combo", "callout", "tick", "heartbeat"]
const UI_LAYERS := ["countdown", "combo", "callout", "tick", "heartbeat"]
## Базовая громкость слоя (дБ). Ассеты выровнены по громкости (sfx −14 LUFS-M, ui −18) — здесь только микс.
const LAYER_DB := {
	"hit_l": 0.0, "hit_m": 0.0, "hit_h": 1.0, "ko": 1.0,
	"wood_l": -6.0, "wood_m": -2.0, "wood_h": 2.0, "metal_l": -8.0, "metal_m": -4.0, "metal_h": 0.0, "head": 0.0, "pan": 1.0,
	"blade": -1.0, "bone": -3.0, "rubber": -4.0, "snap": -3.0, "splinter": -9.0, "sub": -1.0, "thud": -3.0, "boom": 0.0,
	"inhale": -2.0, "creak": -7.0, "crash": 0.0, "shatter": -1.0, "whoosh": -6.0, "swing_l": -9.0, "swing_h": -7.0, "dash": -6.0,
	"flip": -9.0, "grab": -9.0, "equip": -7.0, "detach": -3.0, "attach": -7.0, "bell": -3.0, "horn": -5.0, "explosion": 0.0,
	"clank": -7.0, "scrape": -9.0, "stun": -11.0,
	"countdown": -2.0, "combo": -3.0, "callout": -6.0, "tick": -8.0, "heartbeat": -6.0,
}
## Приоритет вытеснения: при занятых голосах новый звук забирает голос с приоритетом не выше своего (самый старый).
const LAYER_PRIORITY := {
	"hit_l": 1, "hit_m": 2, "hit_h": 2, "ko": 3,
	"wood_l": 0, "metal_l": 0, "rubber": 0, "bone": 1, "scrape": 0, "clank": 0, "splinter": 0, "swing_l": 0, "flip": 0, "grab": 0,
	"creak": 0, "attach": 0, "tick": 0, "stun": 1, "equip": 1, "whoosh": 1, "swing_h": 1, "dash": 1, "wood_m": 1, "metal_m": 1,
	"thud": 1, "snap": 1, "detach": 2, "wood_h": 2, "metal_h": 2, "head": 2, "pan": 2, "blade": 2, "sub": 2, "crash": 2,
	"shatter": 3, "explosion": 3, "boom": 3, "inhale": 3, "bell": 3, "horn": 3, "countdown": 2, "combo": 2,
	"callout": 2, "heartbeat": 1,
}
const RANDOM_PITCH := 1.06              # AudioStreamRandomizer: питч ×[1/1.06, 1.06]
const RANDOM_VOLUME_DB := 1.5
const NO_SLOWMO_PITCH := ["bell", "horn", "countdown", "combo", "callout", "tick", "heartbeat"]
## Разброс питча основы удара, ± полутонов (как PITCH_SPREAD в src/audio/sfx.ts).
const PUNCH_SPREAD := {"hit_l": 2.5, "hit_m": 2.0, "hit_h": 1.5, "ko": 0.8}
## Подложка материала под основой удара, дБ (материал — характер, удар — тело звука).
const ACCENT_DB := -10.0
## Музыка под тяжёлым ударом и KO (GameAudio.duck): [дБ, удержание с] — как duckMusic в JS-версии.
const DUCK_HEAVY := [-5.0, 0.22]
const DUCK_KO := [-13.0, 0.8]
const VOICES := 24
const LAYER_GAP_MS := 40.0
const MAX_PER_LAYER := 4
const LIGHT_VICTIM_GAP_MS := 60.0
const BUS_SFX := "SFX"
const BUS_CRIT := "SFX_Crit"
const BUS_UI := "UI"
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
const CRIT_SHORT_WHOOSH_MS := 200.0
const KO_RECENT_MS := 2500.0
const KO_DEDUPE_MS := 300.0
const HEAVY_WHOOSH_MS := 70.0
const WHOOSH_MIN_SPEED := 2.0           # м/с ЦМ: тише — без «вух»
const WHOOSH_FULL_SPEED := 7.5
const WHOOSH_POLL_SPEED := 5.0          # полёт (Doll.is_flying) быстрее — «вух» сам по себе (крит-полёт, броски)
const WHOOSH_QUIET_MS := 700.0          # после крита опрос молчит (стоп-кадр — тишина, «вух» крита — на выходе из крупного плана)
const WHOOSH_DOLL_GAP_MS := 600.0
const SD_BELL_GAP_MS := 260.0
const OVER_BELL_GAP_MS := 220.0
const DOLL_SYNC_MS := 500.0

@export var layers: Dictionary[String, AudioStreamRandomizer] = {}
@export var match_path: NodePath

var enabled := true
var volume_db: float = Tuning.HITFX_SFX_VOLUME_DB
## Тесты: "" — как решит директор; "cine" / "short" — принудительный вид крита.
var force_crit_mode := ""
## DollAudio каждой кукле Match (false — пробы, где кукол озвучивать не нужно).
var doll_audio := true
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
var _doll_sync_ms := -1.0e9


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

## Шины игры (GameAudio.ensure_buses: SFX, SFX_Pan*, SFX_Crit, Music, Crowd, Ambience, UI) — идемпотентно.
static func ensure_buses() -> void:
	GameAudioScript.ensure_buses()


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


## Мир глохнет (крупный план крита): low-pass MUFFLE_HZ на шине SFX за MUFFLE_IN_MS (и через GameAudio на толпе, фоне, музыке);
## снятие за MUFFLE_OUT_MS. SFX_Crit не глохнет.
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
	if lpf != null:
		lpf.cutoff_hz = OPEN_HZ * pow(MUFFLE_HZ / OPEN_HZ, _muffle_amt)
		AudioServer.set_bus_effect_enabled(i, 0, _muffle_amt > 0.001)
	var ga := _game_audio()
	if ga != null:
		ga.set_world_muffle(_muffle_amt)


func _game_audio() -> Node:
	return get_node_or_null("/root/GameAudio") if is_inside_tree() else null


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


## Слои из папок — запасной путь, если скрипт создан без сцены.
## Слои, собранные из каталогов, — один раз на процесс: директор создаётся на каждый матч и каждое испытание мастерской, а make_layer читает
## сотни ogg (≈ 64 мс, кэш ресурсов Godot слабый — без владельца потоки перечитываются). AudioStreamRandomizer делится между директорами.
static var _layer_cache: Dictionary = {}   # слой -> AudioStreamRandomizer (null — каталога нет)


func _load_layers_from_dirs() -> void:
	for layer in LAYER_ORDER:
		warm_layer(layer)
		var rs: AudioStreamRandomizer = _layer_cache[layer]
		if rs != null:
			layers[layer] = rs


## Собрать слой заранее (мастерская греет их по одному за кадр, пока игрок собирает куклу).
static func warm_layer(layer: String) -> void:
	if not _layer_cache.has(layer):
		var made := make_layer(layer)
		_layer_cache[layer] = made if made.streams_count > 0 else null


static func layer_dir(layer: String) -> String:
	return "%s/%s" % [UI_DIR if UI_LAYERS.has(layer) else SFX_DIR, layer]


static func make_layer(layer: String) -> AudioStreamRandomizer:
	var rs := AudioStreamRandomizer.new()
	rs.resource_name = layer
	rs.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	rs.random_pitch = RANDOM_PITCH
	rs.random_volume_offset_db = RANDOM_VOLUME_DB
	var dir := layer_dir(layer)
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


func has_layer(layer: String) -> bool:
	return layers.has(layer)


## Играет слой: громкость LAYER_DB + volume_db, питч (× замедление), шина (SFX + панорама pan −1…1 | SFX_Crit | UI; слои UI —
## всегда UI). Возвращает индекс голоса или −1 (выключен, слоя нет, чаще LAYER_GAP_MS, MAX_PER_LAYER, нет голоса по приоритету).
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
	if UI_LAYERS.has(layer) and bus == BUS_SFX:
		bus = BUS_UI
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
	if doll_audio and now - _doll_sync_ms >= DOLL_SYNC_MS:
		_doll_sync_ms = now
		_sync_doll_audio()


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


## Повторная привязка к Match / куклам: директор пережил смену кукол (испытание мастерской держит его между запусками).
func rebind() -> void:
	_bind()


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
	_sync_doll_audio()


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
	crit_phase.emit("aborted", 0.0)


## DollAudio каждой живой кукле Match.dolls() (ребёнок куклы — уходит вместе с ней).
func _sync_doll_audio() -> void:
	if not doll_audio or _match == null or not is_instance_valid(_match) or not _match.has_method("dolls"):
		return
	for d in _match.call("dolls"):
		if d is Doll and is_instance_valid(d) and (d as Node).get_node_or_null("DollAudio") == null:
			var da := DollAudio.new()
			da.name = "DollAudio"
			da.sfx = self
			(d as Node).add_child(da)


# --- удары ---

## Match.hit_fx(ctx) — HIT_FX.md §4.1: victim, attacker, damage, kind, part, striker, weapon_id, position, tier, is_ko, …
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


## Материалы удара: [жертва (часть ctx.part), чем били (оружие по weapon_id, иначе часть бьющего ctx.striker)].
static func hit_materials(ctx: Dictionary) -> Array:
	var vm := SoundMaterial.of_doll_part(ctx.get("victim", null), String(ctx.get("part", "")))
	var wid := String(ctx.get("weapon_id", ""))
	var sm := SoundMaterial.weapon_class(wid) if wid != "" else ""
	if sm == "":
		var att: Variant = ctx.get("attacker", null)
		var st := String(ctx.get("striker", ""))
		sm = SoundMaterial.of_doll_part(att, st) if att is Doll and (att as Doll).parts.has(st) else SoundMaterial.WOOD
	return [vm, sm]


static func _is_head(ctx: Dictionary) -> bool:
	return String(ctx.get("part", "")).begins_with("Head")


## Питч основы: случайно ± PUNCH_SPREAD[layer] полутонов.
func _punch_pitch(layer: String) -> float:
	return pow(2.0, _rng.randf_range(-1.0, 1.0) * float(PUNCH_SPREAD.get(layer, 1.0)) / 12.0)


func _duck(d: Array) -> void:
	var ga := _game_audio()
	if ga != null:
		ga.duck(float(d[0]), float(d[1]))


func _play_light(ctx: Dictionary, pan: float) -> void:
	var now := clock_ms()
	var vid := _victim_id(ctx)
	if now - float(_last_victim_ms.get(vid, -1.0e9)) < LIGHT_VICTIM_GAP_MS:
		dropped["rate"] = int(dropped["rate"]) + 1
		return
	_last_victim_ms[vid] = now
	var k := clampf(float(ctx.get("damage", 0.0)) / maxf(Tuning.HITFX_HEAVY_SCORE, 0.01), 0.0, 1.0)
	var mats := hit_materials(ctx)
	var vm: String = mats[0]
	var sm: String = mats[1]
	var punch := "hit_m" if k >= 0.5 else "hit_l"
	play_layer(punch, lerpf(-6.0, 0.0, k), _punch_pitch(punch), BUS_SFX, pan)
	if sm == SoundMaterial.PAN:
		play_layer("pan", lerpf(-10.0, -5.0, k), _rng.randf_range(1.05, 1.2), BUS_SFX, pan)
	elif _is_head(ctx) and vm == SoundMaterial.WOOD:
		play_layer("head", ACCENT_DB + lerpf(-2.0, 2.0, k), _rng.randf_range(1.0, 1.12), BUS_SFX, pan)
	elif (sm == SoundMaterial.METAL or sm == SoundMaterial.BLADE) and vm != SoundMaterial.METAL:
		play_layer("metal_l", ACCENT_DB - 2.0, _rng.randf_range(1.0, 1.15), BUS_SFX, pan)
	elif vm != SoundMaterial.WOOD:
		play_layer(SoundMaterial.hit_layer(vm, 0), ACCENT_DB, _rng.randf_range(0.96, 1.1), BUS_SFX, pan)


func _play_heavy(ctx: Dictionary, pan: float) -> void:
	var k := clampf((float(ctx.get("damage", 0.0)) - Tuning.HITFX_HEAVY_SCORE) / 20.0, 0.0, 1.0)
	var mats := hit_materials(ctx)
	var vm: String = mats[0]
	var sm: String = mats[1]
	play_layer("hit_h", lerpf(-1.0, 1.0, k), _punch_pitch("hit_h"), BUS_SFX, pan)
	_play_striker(sm, vm, ACCENT_DB + 4.0, pan, BUS_SFX)
	if _is_head(ctx) and vm == SoundMaterial.WOOD:
		play_layer("head", ACCENT_DB + 2.0, _rng.randf_range(0.9, 1.0), BUS_SFX, pan)
	elif vm != SoundMaterial.WOOD:
		play_layer(SoundMaterial.hit_layer(vm, 1), ACCENT_DB, _rng.randf_range(0.94, 1.04), BUS_SFX, pan)
	if vm == SoundMaterial.WOOD or vm == SoundMaterial.BONE:
		play_layer("snap", ACCENT_DB + lerpf(-2.0, 2.0, k), _rng.randf_range(0.95, 1.15), BUS_SFX, pan)
	play_layer("sub", lerpf(-9.0, -5.0, k), _rng.randf_range(0.95, 1.05), BUS_SFX, pan)
	_duck(DUCK_HEAVY)
	_schedule_call(HEAVY_WHOOSH_MS, "whoosh", "whoosh", ctx.get("victim", null))


## Слой бьющего поверх основы удара (db — уже уровень подложки): сковорода — «БОНГ» (громче, это её фирменный звук), лезвие —
## «чок», металл — звон, часть тела — её материал, если отличается от жертвы.
func _play_striker(sm: String, vm: String, db: float, pan: float, bus: String) -> void:
	match sm:
		SoundMaterial.PAN:
			play_layer("pan", db + 4.0, _rng.randf_range(0.95, 1.05), bus, pan)
		SoundMaterial.BLADE:
			play_layer("blade", db, _rng.randf_range(0.95, 1.08), bus, pan)
		SoundMaterial.METAL:
			if vm != SoundMaterial.METAL:
				play_layer("metal_m", db - 2.0, _rng.randf_range(0.95, 1.08), bus, pan)
		_:
			if sm != vm:
				play_layer(SoundMaterial.hit_layer(sm, 1), db - 4.0, _rng.randf_range(0.95, 1.08), bus, pan)


func _play_ko_hit(ctx: Dictionary, pan: float) -> void:
	var vid := _victim_id(ctx)
	var now := clock_ms()
	if now - float(_ko_ms.get(vid, -1.0e9)) > KO_DEDUPE_MS:
		# Match.ko не пришёл (порядок сигналов другой) — звук KO отсюда
		var v: Variant = ctx.get("victim", null)
		handle_ko(v as Doll if is_instance_valid(v) and v is Doll else null, ctx.get("attacker", null), {"position": ctx.get("position", Vector3.ZERO)})
	var mats := hit_materials(ctx)
	play_layer("hit_h", 0.0, _punch_pitch("hit_h") * 0.94, BUS_SFX, pan)
	_play_striker(mats[1], mats[0], ACCENT_DB + 4.0, pan, BUS_SFX)


func handle_ko(victim: Doll, _attacker: Node, record: Dictionary) -> void:
	if not enabled:
		return
	var pos: Vector3 = record.get("position", victim.centre_of_mass() if victim != null and is_instance_valid(victim) else Vector3.ZERO)
	var pan := pan_for(pos)
	var now := clock_ms()
	var vid := victim.get_instance_id() if victim != null and is_instance_valid(victim) else 0
	if now - float(_ko_ms.get(vid, -1.0e9)) <= KO_DEDUPE_MS:
		return
	_ko_ms[vid] = now
	_last_ko_ms = now
	play_layer("ko", 0.0, _punch_pitch("ko"), BUS_SFX, pan)
	play_layer("shatter", -3.0, 1.0, BUS_SFX, pan)
	play_layer("snap", -6.0, 0.85, BUS_SFX, pan)
	play_layer("sub", -4.0, 0.9, BUS_SFX, pan)
	_duck(DUCK_KO)


## Крит: "cine" — стоп-кадр → крупный план (свой таймлайн или фазы CritCinematic), "short" — без крупного плана
## (HITFX_CRIT_CINEMATIC=false, нет HitFxDirector, или кинематограф занят прошлым критом).
func _play_crit(ctx: Dictionary, _pan: float, _ko: bool) -> void:
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
		var mats := hit_materials(ctx)
		play_layer("boom", -2.0, 1.0, BUS_CRIT)
		play_layer("hit_h", 1.0, _punch_pitch("hit_h") * 0.9, BUS_CRIT)
		_play_striker(mats[1], mats[0], ACCENT_DB + 4.0, 0.0, BUS_CRIT)
		play_layer("snap", -4.0, 0.9, BUS_CRIT)
		play_layer("sub", -2.0, 0.85, BUS_CRIT)
		_duck(DUCK_KO)
		_schedule_call(CRIT_SHORT_WHOOSH_MS, "whoosh", "crit_short", ctx.get("victim", null), {"min_db": -6.0, "bus": BUS_CRIT})
		crit_phase.emit("short", 0.0)


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
	var mats := hit_materials(_crit_ctx) if not _crit_ctx.is_empty() else [SoundMaterial.WOOD, SoundMaterial.WOOD]
	match name_:
		"freeze":
			# «вдох»: развёрнутый назад бум, обрыв на пике — дальше тишина стоп-кадра
			play_layer("inhale", 0.0, 1.0, BUS_CRIT)
			set_muffle(true)
		"cut_in":
			play_layer("boom", 0.0, 1.0, BUS_CRIT)
			play_layer("hit_h", 2.0, _punch_pitch("hit_h") * 0.85, BUS_CRIT)
			_play_striker(mats[1], mats[0], ACCENT_DB + 4.0, 0.0, BUS_CRIT)
			play_layer("sub", -2.0, 0.8, BUS_CRIT)
			play_layer("snap", -3.0, 0.9, BUS_CRIT)
			play_layer("creak", 0.0, 0.8, BUS_CRIT)
			_duck(DUCK_KO)
			if not _crit_synced and not _crit_forced and is_instance_valid(_cine) and _cine.has_method("is_playing") \
					and not bool(_cine.call("is_playing")):
				set_muffle(false)           # кинематограф не пошёл — мир не глушим
			else:
				set_muffle(true)
		"caption":
			pass                            # «ох» толпы — CrowdDirector по crit_phase
		"crack_2":
			play_layer("snap", -1.0, 0.7, BUS_CRIT)
			play_layer("splinter", 2.0, 0.85, BUS_CRIT)
		"cut_out":
			play_layer("swing_h", -2.0, 0.6, BUS_CRIT)
			var v: Variant = _crit_ctx.get("victim", null)
			if is_instance_valid(v) and v is Node:
				_whoosh(v as Node, -6.0, BUS_CRIT)
			set_muffle(false)
		"done":
			set_muffle(false)
			_crit_mode = ""
			_crit_synced = false
			_crit_forced = false
	crit_phase.emit(name_, float(_crit_done[name_]))


func handle_env_slam(ctx: Dictionary) -> void:
	if not enabled:
		return
	var speed := float(ctx.get("speed", 0.0))
	var k := clampf((speed - Tuning.HITFX_SLAM_SPEED) / 6.0, 0.0, 1.0)
	var pan := pan_for(ctx.get("position", Vector3.ZERO))
	var punch := "hit_m" if k >= 0.5 else "hit_l"
	play_layer("thud", lerpf(-10.0, -2.0, k), 0.8 * _rng.randf_range(0.95, 1.05), BUS_SFX, pan)
	play_layer(punch, lerpf(-8.0, -2.0, k), _punch_pitch(punch) * 0.9, BUS_SFX, pan)
	if bool(ctx.get("crit_flight", false)):
		play_layer("hit_h", 0.0, _punch_pitch("hit_h") * 0.85, BUS_SFX, pan)
		play_layer("snap", -4.0, 0.9, BUS_SFX, pan)
		play_layer("crash", -2.0, 1.0, BUS_SFX, pan)


# --- объявления ---

func handle_announce(text: String, _color: Color, kind: String) -> void:
	if not enabled:
		return
	match kind:
		"fight":
			play_layer("horn", 0.0, 1.0)
			play_layer("bell", 0.0, 1.0)
		"sudden_death":
			play_layer("bell", 0.0, 0.94)
			play_layer("horn", -2.0, 0.8)
			_schedule(SD_BELL_GAP_MS, "bell", 0.0, 0.94, BUS_SFX, 0.0, "bell")
		"countdown":
			play_layer("countdown", 0.0, 1.0)
		"combo":
			var n := text.to_int()
			play_layer("combo", 0.0, clampf(1.0 + 0.09 * float(maxi(n - 2, 0)), 1.0, 1.6))
		"head", "body", "double":
			play_layer("callout", 0.0, {"head": 1.12, "body": 0.92, "double": 1.0}[kind])


func handle_match_over(winner: Node, _results: Dictionary) -> void:
	if not enabled:
		return
	play_layer("bell", 0.0, 1.0)
	_schedule(OVER_BELL_GAP_MS, "bell", 0.0, 1.0, BUS_SFX, 0.0, "bell")
	_schedule(OVER_BELL_GAP_MS * 2.0, "bell", 0.0, 1.0, BUS_SFX, 0.0, "bell")
	var ga := _game_audio()
	if ga != null and winner != null:
		ga.stinger("victory")


func handle_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		abort_all()
	elif p == Match.Phase.OVER and clock_ms() - _last_ko_ms > KO_RECENT_MS:
		abort_all()


# --- «вух» отлёта ---

static func com_velocity(d: Node) -> Vector3:
	if not d is Doll:
		return (d as RigidBody3D).linear_velocity if d is RigidBody3D else Vector3.ZERO
	return (d as Doll).com_velocity()   # кэш на физический кадр


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


## Идёт ли крит (стоп-кадр / крупный план) — DollAudio и ImpactAudio молчат.
func crit_active() -> bool:
	return _crit_mode != "" or clock_ms() < _quiet_poll_until


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
