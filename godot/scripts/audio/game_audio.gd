## Звук игры целиком (autoload GameAudio, docs/plan-demo/AUDIO.md §4.1): шины и их эффекты, настройки (музыка/толпа вкл-выкл,
## громкости; user://audio.cfg), реверберация арены, «глухота мира» в крите, музыка (плейлист боя, стингеры победы/поражения,
## приглушение под крупные события, «интенсивность» — срез фильтра по возбуждению толпы).
##
## Шины (создаются в рантайме, идемпотентно — ensure_buses(); default_bus_layout не нужен):
##   Master: HardLimiter −0.5 dB
##   Music → Master: LowPass (крит / интенсивность), Compressor (sidechain SFX — приглушение под удары)
##   Crowd → Master: LowPass (крит), Reverb (зал), Compressor (sidechain SFX)
##   Ambience → Master: LowPass (крит), Compressor (sidechain SFX)            UI → Master
##   SFX → Master: LowPass (крит, ведёт SfxDirector), Reverb (арена), Compressor, HardLimiter; SFX_PanL2/L1/R1/R2 → SFX
##   SFX_Crit → Master: HardLimiter (крупный план крита — мимо глушения)
## Клавиши — в площадках (scenes/playground.gd, playground_pve.gd): M — музыка вкл/выкл, N — толпа вкл/выкл.
extends Node

const CFG_PATH := "user://audio.cfg"
const BUS_MUSIC := "Music"
const BUS_CROWD := "Crowd"
const BUS_AMB := "Ambience"
const BUS_SFX := "SFX"
const BUS_CRIT := "SFX_Crit"
const BUS_UI := "UI"
const PAN_BUSES := {-2: "SFX_PanL2", -1: "SFX_PanL1", 1: "SFX_PanR1", 2: "SFX_PanR2"}
const PAN_STEP := 0.25
const LIMITER_CEILING_DB := -0.5
const OPEN_HZ := 20000.0
const MUFFLE_HZ := 900.0
## Музыка в покое (интенсивность 0) звучит через срез INTENSITY_LOW_HZ, на пике — открыто.
const INTENSITY_LOW_HZ := 2600.0
const MUSIC_DIR := "res://assets/audio/music/"
const FIGHT_TRACKS := ["battle_01", "battle_02", "battle_03", "battle_04"]
const MUSIC_FADE_S := 1.5
## Реверберация арен: room_size, damping, wet, predelay_ms, hipass (0..1). Пресет — ArenaAmbience.
const ROOMS := {
	"none": [0.2, 0.5, 0.0, 10.0, 0.2],
	"dome": [0.82, 0.42, 0.14, 45.0, 0.25],     # Свалка: купол над свалкой, долгий хвост
	"hall": [0.68, 0.5, 0.11, 30.0, 0.25],      # Руины
	"room": [0.42, 0.65, 0.09, 12.0, 0.3],      # Мастерская
	"void": [0.95, 0.3, 0.17, 60.0, 0.35],      # Void: пустота без стен — огромный хвост
}
## Громкости шин по умолчанию (дБ), настройки игрока поверх.
const DEFAULT_DB := {"Master": 0.0, "Music": -16.0, "Crowd": -8.0, "Ambience": -9.0, "SFX": 0.0, "UI": -4.0}
## Приглушение под удары (sidechain от шины SFX): [порог дБ, ratio, атака мкс, спад мс]. Клип v1 (02.10): без него тяжёлые удары
## поднимались над фоном музыки, толпы и арены лишь на 2–4 дБ — теперь фон проседает под громкий удар и возвращается за ~0.3 с.
const DUCK := {"Music": [-26.0, 6.0, 2000.0, 320.0], "Crowd": [-22.0, 3.0, 3000.0, 260.0], "Ambience": [-24.0, 3.0, 3000.0, 300.0]}

signal settings_changed

var music_on := true
var crowd_on := true
var volumes: Dictionary = DEFAULT_DB.duplicate()
var room := "none"
## Музыка: контекст ("" — тишина, "fight") и текущий трек — для проб.
var music_context := ""
var music_track := ""
var music_log: Array = []                # [{ms, event, track}]

var _players: Array[AudioStreamPlayer] = []
var _cur := 0
var _fade := {}                          # индекс плеера -> [from_db, to_db, t0_ms, dur_ms, stop_at_end]
var _base_db := PackedFloat32Array([-80.0, -80.0])   # громкость плееров без приглушения
var _duck_db := 0.0
var _duck_target := 0.0
var _duck_until := -1.0
var _duck_release_s := 0.8
var _intensity := 0.5
var _world_muffle := 0.0
var _rng := RandomNumberGenerator.new()
var _last_track := ""
var _stinger: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	ensure_buses()
	load_settings()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.bus = BUS_MUSIC
		p.volume_db = -80.0
		add_child(p)
		p.finished.connect(_on_track_finished.bind(i))
		_players.append(p)
	_stinger = AudioStreamPlayer.new()
	_stinger.name = "Stinger"
	_stinger.bus = BUS_MUSIC
	add_child(_stinger)
	apply_settings()
	set_room("none")


static func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


# --- шины ---

## Все шины игры (идемпотентно). Порядок эффектов SFX: 0 LowPass (глушение крита), 1 Reverb, 2 Compressor, 3 HardLimiter.
static func ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) < 0:
		var i := _add_bus(BUS_SFX, "Master")
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = OPEN_HZ
		AudioServer.add_bus_effect(i, lpf)
		AudioServer.set_bus_effect_enabled(i, 0, false)
		AudioServer.add_bus_effect(i, _reverb())
		var comp := AudioEffectCompressor.new()   # мягкий: атака 10 мс пропускает щелчок удара, держит сумму стука
		comp.threshold = -9.0
		comp.ratio = 2.0
		comp.attack_us = 10000.0
		comp.release_ms = 120.0
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
	for b in [BUS_MUSIC, BUS_CROWD, BUS_AMB]:
		if AudioServer.get_bus_index(b) < 0:
			var k2 := _add_bus(b, "Master")
			var lp2 := AudioEffectLowPassFilter.new()
			lp2.cutoff_hz = OPEN_HZ
			AudioServer.add_bus_effect(k2, lp2)
			AudioServer.set_bus_effect_enabled(k2, 0, false)
			if b == BUS_CROWD:
				var rv := _reverb()
				rv.room_size = 0.7
				rv.wet = 0.12
				rv.dry = 1.0
				AudioServer.add_bus_effect(k2, rv)
			var d: Array = DUCK[b]
			var duck := AudioEffectCompressor.new()
			duck.sidechain = BUS_SFX
			duck.threshold = d[0]
			duck.ratio = d[1]
			duck.attack_us = d[2]
			duck.release_ms = d[3]
			AudioServer.add_bus_effect(k2, duck)
	if AudioServer.get_bus_index(BUS_UI) < 0:
		_add_bus(BUS_UI, "Master")
	# сумма шин на Master клипала (клип hitfx-fight-v1, 29.09) — общий лимитер на Master
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


static func _reverb() -> AudioEffectReverb:
	var rv := AudioEffectReverb.new()
	rv.room_size = 0.5
	rv.damping = 0.5
	rv.spread = 0.8
	rv.dry = 1.0
	rv.wet = 0.0
	rv.predelay_msec = 20.0
	rv.hipass = 0.25
	return rv


static func bus_effect(bus: String, cls: String) -> AudioEffect:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return null
	for e in range(AudioServer.get_bus_effect_count(i)):
		var fx := AudioServer.get_bus_effect(i, e)
		if fx.is_class(cls):
			return fx
	return null


static func _bus_effect_index(bus: String, cls: String) -> int:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return -1
	for e in range(AudioServer.get_bus_effect_count(i)):
		if AudioServer.get_bus_effect(i, e).is_class(cls):
			return e
	return -1


## Реверберация арены на SFX (пресет ROOMS). Неизвестный — "none".
func set_room(preset: String) -> void:
	room = preset if ROOMS.has(preset) else "none"
	var rv := bus_effect(BUS_SFX, "AudioEffectReverb") as AudioEffectReverb
	if rv == null:
		return
	var r: Array = ROOMS[room]
	rv.room_size = r[0]
	rv.damping = r[1]
	rv.wet = r[2]
	rv.predelay_msec = r[3]
	rv.hipass = r[4]
	var i := AudioServer.get_bus_index(BUS_SFX)
	AudioServer.set_bus_effect_enabled(i, _bus_effect_index(BUS_SFX, "AudioEffectReverb"), float(r[2]) > 0.001)


## «Глухота мира» 0..1 на Music / Crowd / Ambience (SFX глушит сам SfxDirector) — крупный план крита.
func set_world_muffle(amount: float) -> void:
	_world_muffle = clampf(amount, 0.0, 1.0)
	for b in [BUS_CROWD, BUS_AMB]:
		_set_lowpass(b, _world_muffle, OPEN_HZ)
	_apply_music_filter()


func world_muffle() -> float:
	return _world_muffle


func _set_lowpass(bus: String, amt: float, open_hz: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	var e := _bus_effect_index(bus, "AudioEffectLowPassFilter")
	if i < 0 or e < 0:
		return
	var lpf := AudioServer.get_bus_effect(i, e) as AudioEffectLowPassFilter
	lpf.cutoff_hz = open_hz * pow(MUFFLE_HZ / open_hz, amt)
	AudioServer.set_bus_effect_enabled(i, e, lpf.cutoff_hz < OPEN_HZ - 1.0)


func bus_cutoff_hz(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	var e := _bus_effect_index(bus, "AudioEffectLowPassFilter")
	if i < 0 or e < 0 or not AudioServer.is_bus_effect_enabled(i, e):
		return OPEN_HZ
	return (AudioServer.get_bus_effect(i, e) as AudioEffectLowPassFilter).cutoff_hz


# --- настройки ---

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return
	music_on = bool(cf.get_value("audio", "music_on", music_on))
	crowd_on = bool(cf.get_value("audio", "crowd_on", crowd_on))
	for b in DEFAULT_DB.keys():
		volumes[b] = float(cf.get_value("volume", b, volumes[b]))


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "music_on", music_on)
	cf.set_value("audio", "crowd_on", crowd_on)
	for b in volumes.keys():
		cf.set_value("volume", b, volumes[b])
	cf.save(CFG_PATH)


func apply_settings() -> void:
	for b in volumes.keys():
		var i := AudioServer.get_bus_index(String(b))
		if i >= 0:
			AudioServer.set_bus_volume_db(i, float(volumes[b]))
	var ci := AudioServer.get_bus_index(BUS_CROWD)
	if ci >= 0:
		AudioServer.set_bus_mute(ci, not crowd_on)
	var mi := AudioServer.get_bus_index(BUS_MUSIC)
	if mi >= 0:
		AudioServer.set_bus_mute(mi, not music_on)
	settings_changed.emit()


func set_music_on(on: bool, save := true) -> void:
	music_on = on
	apply_settings()
	if on and music_context != "" and not _any_music_playing():
		_start_track(music_context)
	if save:
		save_settings()


func set_crowd_on(on: bool, save := true) -> void:
	crowd_on = on
	apply_settings()
	if save:
		save_settings()


## M: музыка вкл/выкл. Возвращает подпись для тоста.
func toggle_music() -> String:
	set_music_on(not music_on)
	return "Музыка: %s" % ("вкл" if music_on else "выкл")


## N: толпа вкл/выкл.
func toggle_crowd() -> String:
	set_crowd_on(not crowd_on)
	return "Толпа: %s" % ("вкл" if crowd_on else "выкл")


func set_volume_db(bus: String, db: float, save := true) -> void:
	volumes[bus] = db
	apply_settings()
	if save:
		save_settings()


# --- музыка ---

## Контекст музыки: "fight" — плейлист боя (уже играет — продолжает), "" — затухание и тишина.
func play_context(ctx: String) -> void:
	if ctx == "":
		if music_context != "":
			_log("context_off", music_track)
		music_context = ""
		_fade_player(_cur, -80.0, MUSIC_FADE_S * 1000.0, true)
		return
	var same := ctx == music_context
	music_context = ctx
	if same and _players[_cur].playing:
		_fade_player(_cur, 0.0, 400.0, false)   # отменить начатое затухание
		return
	_start_track(ctx)


func _start_track(ctx: String) -> void:
	if ctx != "fight":
		return
	var pool: Array = FIGHT_TRACKS.filter(func(t: String) -> bool: return t != _last_track)
	var t: String = pool[_rng.randi() % pool.size()]
	var s := load(MUSIC_DIR + t + ".ogg") as AudioStream
	if s == null:
		return
	var nxt := 1 - _cur
	_fade_player(_cur, -80.0, MUSIC_FADE_S * 1000.0, true)
	_cur = nxt
	var p := _players[_cur]
	p.stream = s
	_base_db[_cur] = -30.0
	p.volume_db = -30.0 + _duck_db
	p.play()
	_fade_player(_cur, 0.0, MUSIC_FADE_S * 1000.0, false)
	_last_track = t
	music_track = t
	_log("track", t)


func _on_track_finished(i: int) -> void:
	if i == _cur and music_context != "":
		_start_track(music_context)


func _any_music_playing() -> bool:
	for p in _players:
		if p.playing:
			return true
	return false


func is_music_playing() -> bool:
	return _players.size() > _cur and _players[_cur].playing and not _fade.get(_cur, [0, 0, 0, 0, false])[4]


func _fade_player(i: int, to_db: float, dur_ms: float, stop_at_end: bool) -> void:
	if i < 0 or i >= _players.size():
		return
	_fade[i] = [_base_db[i], to_db, now_ms(), maxf(dur_ms, 1.0), stop_at_end]


## Стингер поверх музыки (victory / defeat): трек боя приглушается на время стингера.
func stinger(name_: String) -> void:
	var s := load(MUSIC_DIR + name_ + ".ogg") as AudioStream
	if s == null:
		return
	_stinger.stream = s
	_stinger.volume_db = 0.0
	_stinger.play()
	duck(-14.0, s.get_length(), 1.2)
	_log("stinger", name_)


## Приглушить музыку на db (≤ 0) на hold_s секунд, затем вернуть за release_s.
func duck(db: float, hold_s: float, release_s: float = 0.8) -> void:
	_duck_target = minf(_duck_target, db) if now_ms() < _duck_until else db
	_duck_until = maxf(_duck_until, now_ms() + hold_s * 1000.0)
	_duck_release_s = release_s


## Интенсивность боя 0..1 (CrowdDirector по возбуждению толпы): срез фильтра музыки INTENSITY_LOW_HZ → открыто.
func set_intensity(x: float) -> void:
	_intensity = clampf(x, 0.0, 1.0)
	_apply_music_filter()


func _apply_music_filter() -> void:
	var open := INTENSITY_LOW_HZ * pow(OPEN_HZ / INTENSITY_LOW_HZ, _intensity)
	_set_lowpass(BUS_MUSIC, _world_muffle, open)


func _log(ev: String, track: String) -> void:
	music_log.append({"ms": snappedf(now_ms(), 0.1), "event": ev, "track": track})
	if music_log.size() > 256:
		music_log.remove_at(0)


func _process(_dt: float) -> void:
	var now := now_ms()
	# приглушение
	var tgt := _duck_target if now < _duck_until else 0.0
	if now >= _duck_until:
		_duck_target = 0.0
	var rate := 60.0 if tgt < _duck_db else 12.0 / maxf(_duck_release_s, 0.05)
	_duck_db = move_toward(_duck_db, tgt, rate * _dt)
	for i in _players.size():
		var p := _players[i]
		if _fade.has(i):
			var f: Array = _fade[i]
			var k := clampf((now - float(f[2])) / float(f[3]), 0.0, 1.0)
			_base_db[i] = lerpf(float(f[0]), float(f[1]), k)
			if k >= 1.0:
				_fade.erase(i)
				if bool(f[4]):
					p.stop()
		p.volume_db = _base_db[i] + _duck_db
