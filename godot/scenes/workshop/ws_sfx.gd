## Тактильные звуки мастерской (UI/UX spec v0.3 §39). Мастерская — верстак, а не меню, поэтому и звук «из мастерской»: кнопка-
## дощечка глухо стучит, металлическая вкладка щёлкает, деталь поднимается с лёгким механическим «клик-вжих», в сокет садится
## щелчком своего материала (дерево — «ток» с глухим телом, металл — звонкий «клац», пружина — короткий «боинг», верёвка —
## натяжение волокна и узел), удаление — откручивание (ратчет вниз) и «отпустил», отказ — дёрнули запертую защёлку.
## Все звуки короткие (< 250 мс), тихие и в нескольких вариантах: за одну сборку их слышат сотни раз — никакого яркого верха
## и одинаковых повторов подряд.
##
## Как собраны. Каждый (вид, материал, вариант) — один AudioStreamWAV (PCM16 моно 44.1 кГц), смешанный заранее из сэмплов
## assets/audio/sfx/<слой>/*.ogg (дерево «ток», скрип волокна, «вух»: декодируются через AudioStreamPlayback.mix_audio, дальше
## питч, фильтр, обрезка) и процедурных слоёв (щелчок — шумовой всплеск через ФВЧ; звон — затухающие негармонические синусы;
## «боинг» — синус с качанием питча; ратчет — серия щелчков с падающим тоном). Готовый поток ⇒ один голос на звук, пик
## нормирован (PEAK_DB, всегда < −1 dBFS), пробе есть что записать в WAV и измерить.
## Банк статический (общий для всех WsSfx): первый play() варианта печёт его сразу (0.5–6 мс), остальное допекается по одному
## варианту за кадр (весь банк ≈ 45 кадров, ≈ 150 мс работы) — без одного длинного кадра при открытии мастерской.
##
## Воспроизведение: пул VOICES AudioStreamPlayer (звуки накладываются, при нехватке вытесняется самый старый) на шине BUS —
## своя "UI" → Master, а не SFX: ту глушит low-pass крита SfxDirector и жмёт компрессор боя, а щелчок интерфейса должен
## звучать ровно. Питч ± PITCH_JITTER, громкость volume_db ± VOL_JITTER_DB, один вид не чаще GAP_MS (наведение по сетке карточек,
## зажатый Ctrl+Z, спам отказа). В headless (аудио-драйвер Dummy) всё то же самое, просто без звука.
## Проба: tests/ws_sfx_probe.tscn (played / dropped / stream_for, WAV каждого вида для прослушивания).
class_name WsSfx
extends Node

const KINDS := ["hover", "tab", "button", "grab", "snap", "invalid", "unscrew", "delete", "duplicate", "mirror", "undo", "redo",
	"test"]
## Классы материала щелчка в сокет (play("snap", material)); "" — нейтральная защёлка.
const MATERIALS := ["wood", "metal", "spring", "rope"]
## id MaterialDef / PartDef.material, которые звучат металлом.
const METAL_IDS := ["iron", "brass", "rust", "rust_red", "steel", "metal"]
const RATE := 44100
const VOICES := 8
const BUS := "UI"
const SFX_DIR := "res://assets/audio/sfx/"
const TOKS := ["tok/wood_tok_01.ogg", "tok/wood_tok_02.ogg", "tok/wood_tok_03.ogg", "tok/wood_tok_04.ogg", "tok/wood_tok_05.ogg",
	"tok/wood_tok_06.ogg", "tok/wood_tok_07.ogg", "tok/wood_tok_08.ogg"]
const CREAKS := ["creak/fiber_creak_01.ogg", "creak/fiber_creak_02.ogg"]
const WHOOSHES := ["whoosh/whoosh_03.ogg", "whoosh/whoosh_01.ogg"]
## Вариантов на (вид, материал): чередуются случайно, без повтора подряд.
const VARIANTS := {"hover": 3, "tab": 3, "button": 4, "grab": 3, "snap": 3, "invalid": 2, "unscrew": 2, "delete": 2,
	"duplicate": 2, "mirror": 2, "undo": 2, "redo": 2, "test": 2}
## Пик готового звука, dBFS — микс видов между собой (поверх — volume_db). Подобран по громкости на слух, а не по пику: LK —
## K-взвешивание BS.1770, максимум по окнам 50 мс (проба ws_sfx_probe, check mix): щелчок в сокет ≈ −18 LK, отказ / удаление /
## испытание ≈ −20, кнопки и вкладки ≈ −23, мелкая механика ≈ −24…−25, наведение ≈ −38 (на 15 дБ тише кнопки — слышно в тишине).
const PEAK_DB := {"hover": -21.0, "tab": -11.0, "button": -9.0, "grab": -10.0, "snap": -4.0, "invalid": -9.0, "unscrew": -8.0,
	"delete": -8.5, "duplicate": -10.0, "mirror": -11.0, "undo": -14.0, "redo": -14.0, "test": -11.0}
## Пик щелчка в сокет по материалу (вместо PEAK_DB["snap"]): у пружины и верёвки низкий тянущийся тон — громче на слух при том
## же пике, поэтому пик ниже; у дерева резкая атака «тока» — пик выше при той же громкости.
const SNAP_PEAK_DB := {"": -4.0, "wood": -3.0, "metal": -6.0, "spring": -10.0, "rope": -7.5}
## Не чаще раза в N мс для одного вида (материал щелчка не различается).
const GAP_MS := {"hover": 60.0, "tab": 50.0, "button": 50.0, "grab": 80.0, "snap": 60.0, "invalid": 150.0, "unscrew": 120.0,
	"delete": 120.0, "duplicate": 90.0, "mirror": 120.0, "undo": 45.0, "redo": 45.0, "test": 400.0}
## Случайный питч ×[1 − j, 1 + j]: у отказа меньше — его надо узнавать.
const PITCH_JITTER := {"hover": 0.05, "tab": 0.03, "button": 0.05, "grab": 0.04, "snap": 0.04, "invalid": 0.02, "unscrew": 0.03,
	"delete": 0.03, "duplicate": 0.03, "mirror": 0.03, "undo": 0.03, "redo": 0.03, "test": 0.03}
const VOL_JITTER_DB := 0.8
## Порядок допекания банка: сначала то, что звучит в первые секунды (наведение, кнопки, взять / поставить).
const WARM_ORDER := ["hover", "button", "tab", "grab", "snap", "invalid", "unscrew", "delete", "undo", "redo", "duplicate",
	"mirror", "test"]
const FADE_MS := 8.0
const LOG_MAX := 512

## Громкость всех звуков мастерской, дБ (плюс PEAK_DB вида).
var volume_db := -6.0
var enabled := true
## Шина голосов; нет такой — Master.
var bus := BUS
## Допекать банк по кадрам после _ready (пробы могут выключить и звать warm_all()).
var warm_up := true
## Журнал для проб: [{kind, material, variant, voice, pitch, db, ms}].
var played: Array = []
var dropped := {"gap": 0, "disabled": 0, "unknown": 0, "not_ready": 0}

var _voices: Array[AudioStreamPlayer] = []
var _voice_until: PackedFloat64Array = PackedFloat64Array()
var _voice_start: PackedFloat64Array = PackedFloat64Array()
var _last_ms: Dictionary = {}           # вид -> мс последнего звука
var _last_variant: Dictionary = {}      # "вид|материал" -> вариант
var _warned: Dictionary = {}
var _warm: Array = []                   # очередь [вид, материал, вариант]
var _rng := RandomNumberGenerator.new()

static var _bank: Dictionary = {}       # "вид|материал|вариант" -> AudioStreamWAV
static var _pcm: Dictionary = {}        # путь сэмпла -> PackedFloat32Array (моно, RATE)


func _ready() -> void:
	_rng.randomize()
	ensure_bus()
	while _voices.size() < VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % _voices.size()
		p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
		add_child(p)
		_voices.append(p)
	_voice_until.resize(VOICES)
	_voice_start.resize(VOICES)
	_voice_until.fill(-1.0)
	_voice_start.fill(-1.0)
	_warm = all_keys()
	set_process(warm_up)


## Допекание: один вариант за кадр (самый тяжёлый ≈ 6 мс) — предсказуемо, без пачки в одном кадре.
func _process(_delta: float) -> void:
	if not _warm.is_empty():
		var k: Array = _warm.pop_front()
		stream_for(k[0], k[1], k[2])
	if _warm.is_empty():
		set_process(false)


## Шина "UI" → Master (идемпотентно). Без эффектов: пики звуков уже ниже −1 dBFS, общий лимитер Master ставит SfxDirector.
static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Master")


# =================================================================== воспроизведение

## Играет звук вида kind (KINDS); material — только для "snap": "wood" | "metal" | "spring" | "rope" | "" (нейтральная
## защёлка), любой другой id прогоняется через material_of (play("snap", "brass") — металл).
func play(kind: String, material := "") -> void:
	if not enabled:
		_drop("disabled")
		return
	if not VARIANTS.has(kind):
		_drop("unknown")
		if not _warned.has(kind):
			_warned[kind] = true
			push_warning("WsSfx: неизвестный вид звука '%s'" % kind)
		return
	if not is_inside_tree() or _voices.is_empty():
		_drop("not_ready")
		return
	var now := clock_ms()
	if now - float(_last_ms.get(kind, -1.0e9)) < float(GAP_MS.get(kind, 40.0)):
		_drop("gap")
		return
	var mat := snap_class(material) if kind == "snap" else ""
	var v := _pick_variant(kind, mat)
	var s := stream_for(kind, mat, v)
	var i := _pick_voice(now)
	var p := _voices[i]
	var j: float = PITCH_JITTER.get(kind, 0.03)
	p.stream = s
	p.pitch_scale = _rng.randf_range(1.0 - j, 1.0 + j)
	p.volume_db = volume_db + _rng.randf_range(-VOL_JITTER_DB, VOL_JITTER_DB)
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	p.play()
	_voice_until[i] = now + s.get_length() / p.pitch_scale * 1000.0 + 10.0
	_voice_start[i] = now
	_last_ms[kind] = now
	played.append({"kind": kind, "material": mat, "variant": v, "voice": i, "pitch": snappedf(p.pitch_scale, 0.001),
		"db": snappedf(p.volume_db, 0.01), "ms": snappedf(now, 0.1)})
	if played.size() > LOG_MAX:
		played.remove_at(0)


## Класс материала щелчка: "" и классы MATERIALS как есть, остальное — через material_of (id материала).
static func snap_class(material: String) -> String:
	if material == "" or MATERIALS.has(material):
		return material
	return material_of(null, material)


## Материал детали для звука щелчка: форма важнее покраски — пружина звенит пружиной, верёвка / щупальце шуршат волокном,
## даже перекрашенные. Дальше материал узла чертежа (mat_id, MaterialDef меняет и физику детали), затем материал детали по
## умолчанию (PartDef.base_mat кита v2), затем старое PartDef.material. Железо, латунь, ржавчина, сталь — металл, ткань —
## верёвка, остальное (дерево, краска по дереву, кость, резина) — дерево.
static func material_of(part: PartDef, mat_id := "") -> String:
	var pid := part.id if part != null else ""
	if pid.contains("spring"):
		return "spring"
	if pid.contains("rope") or pid.contains("tentacle"):
		return "rope"
	var m := mat_id
	if m == "" and part != null:
		m = part.base_mat if part.base_mat != "" else part.material
	if MATERIALS.has(m):
		return m
	if METAL_IDS.has(m):
		return "metal"
	if m.contains("spring"):
		return "spring"
	if m.contains("rope") or m.contains("tentacle") or m == "cloth":
		return "rope"
	return "wood"


## Нескалированные часы, мс (UI не замедляется вместе с боем в комнате испытаний).
func clock_ms() -> float:
	return Time.get_ticks_usec() / 1000.0


func voice_count() -> int:
	return _voices.size()


func voice(i: int) -> AudioStreamPlayer:
	return _voices[i] if i >= 0 and i < _voices.size() else null


## Сколько голосов сейчас звучит (по длине потока и питчу — не зависит от аудио-драйвера).
func active_voices() -> int:
	var now := clock_ms()
	var n := 0
	for i in range(_voices.size()):
		if _voice_until[i] > now:
			n += 1
	return n


## Сбрасывает лимит частоты (пробы; смена экрана, где первый клик не должен глотаться).
func reset_limits() -> void:
	_last_ms.clear()


## Глушит все голоса (уход из мастерской, выход): иначе при выходе из игры AudioServer держит живые playback-и (утечка).
func stop_all() -> void:
	for i in range(_voices.size()):
		_voices[i].stop()
		_voice_until[i] = -1.0


func _exit_tree() -> void:
	stop_all()


func _drop(why: String) -> void:
	dropped[why] = int(dropped.get(why, 0)) + 1


func _pick_variant(kind: String, mat: String) -> int:
	var n: int = VARIANTS.get(kind, 1)
	var key := kind + "|" + mat
	var last: int = _last_variant.get(key, -1)
	var v := _rng.randi_range(0, n - 1)
	if n > 1 and v == last:
		v = (v + 1 + _rng.randi_range(0, n - 2)) % n
	_last_variant[key] = v
	return v


## Свободный голос; все заняты — самый старый (обрывается: новый щелчок важнее хвоста прошлого).
func _pick_voice(now: float) -> int:
	var oldest := 0
	for i in range(_voices.size()):
		if _voice_until[i] <= now:
			return i
		if _voice_start[i] < _voice_start[oldest]:
			oldest = i
	_voices[oldest].stop()
	return oldest


## Подключает звуки ко всем BaseButton под root: наведение — "hover", нажатие — "tab" (переключатель / ButtonGroup) или
## "button", клик по выключенной — "invalid"; meta "ws_sfx_kind" задаёт свой вид нажатия ("test", "delete"…), meta "ws_sfx_off"
## — без звука. Уже подключённые пропускает. Возвращает число подключённых кнопок. Необязательно: экран может звать play() сам.
func wire_buttons(root: Node) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		stack.append_array(nd.get_children())
		var bt := nd as BaseButton
		if bt == null or bt.has_meta(&"ws_sfx") or bt.has_meta(&"ws_sfx_off"):
			continue
		bt.set_meta(&"ws_sfx", true)
		bt.mouse_entered.connect(_on_button_hover.bind(bt))
		bt.pressed.connect(_on_button_pressed.bind(bt))
		bt.gui_input.connect(_on_button_input.bind(bt))
		n += 1
	return n


func _on_button_hover(bt: BaseButton) -> void:
	if is_instance_valid(bt) and not bt.disabled:
		play("hover")


func _on_button_pressed(bt: BaseButton) -> void:
	if not is_instance_valid(bt):
		return
	if bt.has_meta(&"ws_sfx_kind"):
		play(String(bt.get_meta(&"ws_sfx_kind")))
	elif bt.toggle_mode or bt.button_group != null:
		play("tab")
	else:
		play("button")


func _on_button_input(ev: InputEvent, bt: BaseButton) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(bt) and bt.disabled:
		play("invalid")


# =================================================================== банк

## Все ключи банка [вид, материал, вариант] в порядке WARM_ORDER.
static func all_keys() -> Array:
	var out: Array = []
	for kind in WARM_ORDER:
		var mats: Array = [""] + MATERIALS if kind == "snap" else [""]
		for m in mats:
			for v in range(int(VARIANTS[kind])):
				out.append([kind, m, v])
	return out


static func variant_count(kind: String) -> int:
	return int(VARIANTS.get(kind, 0))


## Готовый поток варианта (печёт при первом обращении; банк общий для всех WsSfx).
static func stream_for(kind: String, material := "", variant := 0) -> AudioStreamWAV:
	var key := "%s|%s|%d" % [kind, material, variant]
	var s: AudioStreamWAV = _bank.get(key, null)
	if s == null:
		s = bake(kind, material, variant)
		_bank[key] = s
	return s


## Печёт все варианты сразу (пробы, экспорт WAV).
static func warm_all() -> void:
	for k in all_keys():
		stream_for(k[0], k[1], k[2])


## Собирает звук вида kind / материала / варианта (детерминированно: шум и разброс — от сида ключа).
static func bake(kind: String, material := "", variant := 0) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%d" % [kind, material, variant])
	var v := variant
	var b := PackedFloat32Array()
	var peak: float = PEAK_DB.get(kind, -10.0)
	match kind:
		"hover":
			# сухой «тик» ногтем по дереву: 4 мс шума выше 2.5 кГц и совсем короткий призвук
			b = _buf(30.0)
			_click(b, 0.0, 1.0, 2500.0, 4.0, rng)
			_ping(b, 0.3, [4200.0, 4700.0, 3900.0][v % 3] * rng.randf_range(0.97, 1.03), 0.45, 5.0)
		"tab":
			# металлическая вкладка: щелчок, звон пластинки (негармонические моды), дощелк защёлки и глухое дерево под ней
			b = _buf(90.0)
			var f0: float = [2100.0, 2250.0, 1980.0][v % 3]
			_click(b, 0.0, 1.0, 1800.0, 3.0, rng)
			_modal(b, 0.0, f0, [1.0, 2.32, 3.87, 5.1], [0.6, 0.35, 0.2, 0.1], [28.0, 18.0, 10.0, 7.0], 0.8)
			var t2 := rng.randf_range(16.0, 20.0)
			_click(b, t2, 0.45, 3000.0, 2.0, rng)
			_ping(b, t2, f0 * 1.45, 0.2, 8.0)
			_ping(b, 0.0, 420.0, 0.25, 10.0, 1.4, 6.0)
		"button":
			# дощечка: «ток» дерева ниже тоном и мягче (ФНЧ), под ним короткое тело
			b = _buf(120.0)
			_sample(b, 0.0, TOKS[[0, 2, 4, 6][v % 4]], rng.randf_range(0.82, 0.9), 1.0, 2600.0, 115.0)
			_ping(b, 0.0, 210.0, 0.35, 18.0, 1.5, 8.0)
		"grab":
			# лёгкий механический подъём: защёлка отпускает (два тика), деталь выходит из гнезда (тело), воздух вверх
			b = _buf(160.0)
			var fg := rng.randf_range(0.95, 1.05)
			_click(b, 0.0, 0.7, 2000.0, 2.5, rng)
			_ping(b, 0.0, 1650.0 * fg, 0.45, 12.0)
			_ping(b, 0.0, 260.0, 0.3, 12.0, 1.3, 6.0)
			var t2 := rng.randf_range(21.0, 27.0)
			_click(b, t2, 0.4, 2500.0, 2.0, rng)
			_ping(b, t2, 2300.0 * fg, 0.3, 8.0)
			_band(b, 20.0, 135.0, 500.0, 1600.0, 2.0, 0.35, 60.0, false, rng)
		"snap":
			peak = SNAP_PEAK_DB.get(material, -4.0)
			b = _bake_snap(material, v, rng)
		"invalid":
			# отказ: дёрнули запертую защёлку — глухой стук, дребезг, второй стук ниже (без писка и «ошибки» из ОС)
			b = _buf(175.0)
			var fi: float = [1.0, 0.94][v % 2]
			_ping(b, 0.0, 185.0 * fi, 0.9, 22.0, 1.5, 6.0)
			_click(b, 0.0, 0.3, 700.0, 3.0, rng)
			for k in range(3):
				var tk := 30.0 + 12.0 * k + rng.randf_range(-1.5, 1.5)
				_click(b, tk, 0.25, 2000.0, 1.5, rng)
				_ping(b, tk, 1400.0 * fi * rng.randf_range(0.96, 1.04), 0.15, 5.0)
			_ping(b, 75.0, 150.0 * fi, 0.8, 30.0, 1.5, 6.0)
			_click(b, 75.0, 0.3, 700.0, 3.0, rng)
		"unscrew":
			# откручивание: шесть щелчков храповика, тон и сила падают, под ними тихое трение резьбы
			b = _buf(190.0)
			_ratchet(b, 0.0, 6, 26.0, [3100.0, 3300.0][v % 2], 1700.0, 0.9, 0.5, rng)
			_band(b, 0.0, 165.0, 420.0, 380.0, 1.5, 0.08, 20.0, false, rng)
		"delete":
			# удаление: три щелчка вниз (открутил), «отпустил» — деталь отложена на верстак, короткий выдох воздуха
			b = _buf(225.0)
			_ratchet(b, 0.0, 3, 24.0, [2600.0, 2800.0][v % 2], 1900.0, 0.8, 0.55, rng)
			_ping(b, 80.0, 240.0, 0.7, 25.0, 1.6, 8.0)
			_sample(b, 80.0, TOKS[[3, 7][v % 2]], 0.72, 0.55, 1800.0, 130.0)
			_band(b, 70.0, 75.0, 1200.0, 400.0, 1.5, 0.2, 10.0, false, rng)
		"duplicate":
			# дубликат: «ка-чик» штампа — два щелчка, второй выше
			b = _buf(110.0)
			var fd: float = [1.0, 1.06][v % 2]
			_click(b, 0.0, 0.8, 1500.0, 2.5, rng)
			_ping(b, 0.0, 1500.0 * fd, 0.5, 10.0)
			_ping(b, 0.0, 260.0, 0.35, 12.0, 1.3, 6.0)
			_click(b, 48.0, 0.7, 1800.0, 2.5, rng)
			_ping(b, 48.0, 2100.0 * fd, 0.45, 10.0)
		"mirror":
			# зеркало: симметрично — тик, шорох переворота (полоса шума вверх и обратно), такой же тик
			b = _buf(150.0)
			var fm: float = [2400.0, 2250.0][v % 2]
			_click(b, 0.0, 0.5, 2000.0, 2.0, rng)
			_ping(b, 0.0, fm, 0.5, 8.0)
			_band(b, 10.0, 100.0, 900.0, 2600.0, 2.5, 0.3, 50.0, true, rng)
			_click(b, 118.0, 0.5, 2000.0, 2.0, rng)
			_ping(b, 118.0, fm, 0.5, 8.0)
		"undo", "redo":
			# шаг назад — два тика вниз, вперёд — вверх
			b = _buf(90.0)
			var hi: float = [2600.0, 2500.0][v % 2]
			var lo: float = hi * 0.73
			var a := hi if kind == "undo" else lo
			var z := lo if kind == "undo" else hi
			_click(b, 0.0, 0.4, 2000.0, 1.5, rng)
			_ping(b, 0.0, a, 0.5, 9.0)
			_click(b, 40.0, 0.4, 2000.0, 1.5, rng)
			_ping(b, 40.0, z, 0.5, 9.0)
		"test":
			# в комнату испытаний: рычаг (глухой щелчок) и короткий «вух» выше тоном
			b = _buf(235.0)
			_sample(b, 0.0, WHOOSHES[v % 2], 1.55, 1.0, 6000.0, 235.0, 0.0, 60.0)
			_ping(b, 0.0, 200.0, 0.35, 20.0, 1.5, 8.0)
			_click(b, 0.0, 0.3, 1500.0, 2.5, rng)
		_:
			b = _buf(20.0)
	return _finish(b, peak)


## Щелчок в сокет по классу материала.
static func _bake_snap(material: String, v: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	match material:
		"wood":
			# шип входит в гнездо (короткий шорох) и садится: «ток» + глухое тело
			b = _buf(170.0)
			_band(b, 0.0, 26.0, 1400.0, 1100.0, 2.0, 0.15, 18.0, false, rng)
			_sample(b, 22.0, TOKS[[1, 3, 5][v % 3]], rng.randf_range(1.0, 1.08), 1.0, 5000.0, 125.0)
			_ping(b, 22.0, 150.0, 0.55, 30.0, 1.5, 8.0)
		"metal":
			# подводка, затем «клац»: резкий щелчок и звон стержня (моды 1 : 2.76 : 5.40 : 8.93); звон короткий — это защёлка,
			# а не колокол: на сотом щелчке длинный хвост звенел бы в ушах
			b = _buf(170.0)
			var f0: float = [1250.0, 1330.0, 1180.0][v % 3]
			_click(b, 0.0, 0.35, 2500.0, 2.0, rng)
			_click(b, 18.0, 1.0, 1200.0, 3.0, rng)
			_modal(b, 18.0, f0, [1.0, 2.76, 5.40, 8.93], [0.5, 0.35, 0.18, 0.08], [45.0, 30.0, 15.0, 8.0], 0.8)
			_ping(b, 18.0, 330.0, 0.4, 14.0, 1.4, 6.0)
		"spring":
			# «боинг»: защёлка и пружина, качающая тон (~17 Гц, размах качания гаснет вместе со звуком), призвук витка
			b = _buf(235.0)
			_click(b, 0.0, 0.5, 1500.0, 2.0, rng)
			_ping(b, 0.0, 900.0, 0.25, 10.0)
			_boing(b, 6.0, [280.0, 300.0, 265.0][v % 3], 0.9, 70.0, rng.randf_range(16.0, 19.0), 0.18, 80.0)
		"rope":
			# верёвка: натяжение волокна (шорох вниз и скрип), узел затянулся — мягкий глухой стук
			b = _buf(200.0)
			_band(b, 0.0, 80.0, 900.0, 600.0, 1.8, 0.45, 25.0, false, rng)
			_sample(b, 10.0, CREAKS[v % 2], 1.35, 0.4, 3500.0, 90.0, [0.0, 60.0, 120.0][v % 3])
			_ping(b, 55.0, 120.0, 0.8, 35.0, 1.5, 10.0)
			_sample(b, 55.0, TOKS[[6, 0, 2][v % 3]], 0.7, 0.35, 1500.0, 120.0)
		_:
			# нейтральная защёлка: щелчок и небольшой «ток»
			b = _buf(130.0)
			_click(b, 0.0, 0.8, 1500.0, 2.5, rng)
			_ping(b, 0.0, 1800.0, 0.35, 12.0)
			_sample(b, 8.0, TOKS[[7, 0, 2][v % 3]], 1.12, 0.8, 4000.0, 100.0)
			_ping(b, 8.0, 190.0, 0.4, 20.0, 1.5, 8.0)
	return b


# =================================================================== синтез (моно float, RATE)

static func _n(ms: float) -> int:
	return int(ms * 0.001 * RATE)


static func _buf(ms: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(_n(ms))
	b.fill(0.0)
	return b


## Щелчок: шумовой всплеск со спадом e^(−3) за len_ms через ФВЧ первого порядка hp_hz — сухая атака без тона.
static func _click(b: PackedFloat32Array, at_ms: float, gain: float, hp_hz: float, len_ms: float, rng: RandomNumberGenerator) -> void:
	var i0 := _n(at_ms)
	var n := mini(_n(len_ms * 2.0), b.size() - i0)
	var dt := 1.0 / RATE
	var rc := 1.0 / (TAU * hp_hz)
	var a := rc / (rc + dt)
	var dec := exp(-dt / (len_ms * 0.001 / 3.0))
	var env := 1.0
	var px := 0.0
	var py := 0.0
	for i in range(n):
		var x := rng.randf_range(-1.0, 1.0) * env
		py = a * (py + x - px)
		px = x
		b[i0 + i] += py * gain
		env *= dec


## Затухающий синус (tau_ms — до e^−1); glide > 1 — тон начинается выше и за glide_ms спадает к hz (глухой удар телом).
static func _ping(b: PackedFloat32Array, at_ms: float, hz: float, gain: float, tau_ms: float, glide := 1.0, glide_ms := 20.0) -> void:
	var i0 := _n(at_ms)
	var n := mini(_n(tau_ms * 7.0), b.size() - i0)
	var dec := exp(-1.0 / (tau_ms * 0.001 * RATE))
	var gdec := exp(-1.0 / (glide_ms * 0.001 * RATE))
	var g := glide - 1.0
	var env := 1.0
	var ph := 0.0
	var w := TAU * hz / RATE
	for i in range(n):
		b[i0 + i] += sin(ph) * env * gain
		ph += w * (1.0 + g)
		g *= gdec
		env *= dec


## Звон: набор затухающих мод f0 × ratios (негармонические отношения — металл, а не нота).
static func _modal(b: PackedFloat32Array, at_ms: float, f0: float, ratios: Array, gains: Array, taus: Array, gain: float) -> void:
	for k in range(ratios.size()):
		var f := f0 * float(ratios[k])
		if f < RATE * 0.45:
			_ping(b, at_ms, f, float(gains[k]) * gain, float(taus[k]))


## Храповик: count щелчков через step_ms (±2 мс), тон от f_from к f_to (геометрически), сила от g_from к g_to.
static func _ratchet(b: PackedFloat32Array, at_ms: float, count: int, step_ms: float, f_from: float, f_to: float, g_from: float,
		g_to: float, rng: RandomNumberGenerator) -> void:
	for k in range(count):
		var u := float(k) / maxf(1.0, float(count - 1))
		var t := at_ms + step_ms * k + (rng.randf_range(-2.0, 2.0) if k > 0 else 0.0)
		var g := lerpf(g_from, g_to, u)
		var f := f_from * pow(f_to / f_from, u)
		_click(b, t, g, 2200.0, 2.0, rng)
		_ping(b, t, f, 0.4 * g, 7.0)


## Полоса шума (SVF Чемберлена, центр от f_from к f_to; arc — туда и обратно; коэффициент — раз в 16 сэмплов, на слух то же,
## а pow / sin на каждый сэмпл — половина времени выпечки), огибающая: подъём за att_ms, спад квадратом.
static func _band(b: PackedFloat32Array, at_ms: float, len_ms: float, f_from: float, f_to: float, q: float, gain: float, att_ms: float,
		arc: bool, rng: RandomNumberGenerator) -> void:
	var i0 := _n(at_ms)
	var n := mini(_n(len_ms), b.size() - i0)
	var na := maxi(1, _n(att_ms))
	var damp := 1.0 / q
	var low := 0.0
	var band := 0.0
	var f := 0.0
	for i in range(n):
		if i % 16 == 0:
			var u := float(i) / float(maxi(1, n - 1))
			var fu := sin(PI * u) if arc else u
			f = 2.0 * sin(PI * minf(f_from * pow(f_to / f_from, fu), 6000.0) / RATE)
		var env := float(i) / na if i < na else pow(1.0 - float(i - na) / float(maxi(1, n - na)), 2.0)
		var x := rng.randf_range(-1.0, 1.0) * env
		low += f * band
		var high := x - low - damp * band
		band += f * high
		b[i0 + i] += band * damp * gain


## «Боинг»: синус hz с качанием тона (wob_hz, глубина wob_depth, спад wob_tau_ms), тон входит снизу (×0.85 → 1 за 30 мс),
## огибающая e^(−t/tau_ms); плюс призвук витка ×2.76 (быстро гаснет).
static func _boing(b: PackedFloat32Array, at_ms: float, hz: float, gain: float, tau_ms: float, wob_hz: float, wob_depth: float,
		wob_tau_ms: float) -> void:
	var i0 := _n(at_ms)
	var n := b.size() - i0
	var na := 0.002 * RATE
	# спады — умножением на сэмпл (exp на каждый сэмпл втрое дороже всей остальной математики)
	var k_rise := exp(-1.0 / (0.03 * RATE))
	var k_wob := exp(-1.0 / (wob_tau_ms * 0.001 * RATE))
	var k_env := exp(-1.0 / (tau_ms * 0.001 * RATE))
	var k_2 := exp(-1.0 / (0.025 * RATE))
	var rise := 0.15
	var wob := wob_depth
	var env := 1.0
	var e2 := 0.18
	var ph := 0.0
	var ph2 := 0.0
	var w_wob := TAU * wob_hz / RATE
	for i in range(n):
		var f := hz * (1.0 - rise) * (1.0 + wob * sin(w_wob * i))
		var att := minf(1.0, float(i) / na)
		b[i0 + i] += (sin(ph) + e2 * sin(ph2)) * env * att * gain
		ph += TAU * f / RATE
		ph2 += TAU * f * 2.76 / RATE
		rise *= k_rise
		wob *= k_wob
		env *= k_env
		e2 *= k_2


## Сэмпл path (от from_ms) с питчем pitch, ФНЧ lp_hz, длиной len_ms (в конце затухание fade_ms, со середины — ещё и вход 3 мс).
static func _sample(b: PackedFloat32Array, at_ms: float, path: String, pitch: float, gain: float, lp_hz: float, len_ms: float,
		from_ms := 0.0, fade_ms := 16.0) -> void:
	var src := _decode(path)
	if src.is_empty():
		return
	var i0 := _n(at_ms)
	var n := mini(_n(len_ms), b.size() - i0)
	var nf := maxi(1, mini(_n(fade_ms), n))
	var ni := _n(3.0) if from_ms > 0.0 else 0
	var dt := 1.0 / RATE
	var rc := 1.0 / (TAU * lp_hz)
	var a := dt / (rc + dt)
	var y := 0.0
	var pos := from_ms * 0.001 * RATE
	for i in range(n):
		var k := int(pos)
		if k + 1 >= src.size():
			break
		var x := lerpf(src[k], src[k + 1], pos - float(k))
		y += a * (x - y)
		var e := 1.0
		if i >= n - nf:
			e = float(n - i) / float(nf)
		if i < ni:
			e *= float(i) / float(ni)
		b[i0 + i] += y * gain * e
		pos += pitch


## Сэмпл как моно float на RATE (mix_audio отдаёт на частоте микшера — на 48 кГц пересэмплируем); нет файла — пусто.
static func _decode(path: String) -> PackedFloat32Array:
	if _pcm.has(path):
		return _pcm[path]
	var out := PackedFloat32Array()
	var full := SFX_DIR + path
	var s: AudioStream = load(full) if ResourceLoader.exists(full) else null
	if s != null:
		var pb := s.instantiate_playback()
		if pb != null:
			var mr := AudioServer.get_mix_rate()
			pb.start(0.0)
			var st: PackedVector2Array = pb.mix_audio(1.0, int(ceil(s.get_length() * mr)) + 64)
			pb.stop()
			var n := int(float(st.size()) * RATE / mr)
			out.resize(n)
			for i in range(n):
				var p := float(i) * mr / RATE
				var k := mini(int(p), st.size() - 1)
				var k2 := mini(k + 1, st.size() - 1)
				var fr := p - float(k)
				out[i] = lerpf((st[k].x + st[k].y) * 0.5, (st[k2].x + st[k2].y) * 0.5, fr)
	_pcm[path] = out
	return out


## Затухание хвоста FADE_MS, пик в peak_db (dBFS), PCM16 моно.
static func _finish(b: PackedFloat32Array, peak_db: float) -> AudioStreamWAV:
	var n := b.size()
	var nf := mini(_n(FADE_MS), n)
	for i in range(nf):
		b[n - 1 - i] *= float(i) / float(nf)
	var pk := 0.0
	for x in b:
		pk = maxf(pk, absf(x))
	var sc := db_to_linear(peak_db) / pk if pk > 1.0e-6 else 0.0
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		data.encode_s16(i * 2, clampi(roundi(b[i] * sc * 32767.0), -32768, 32767))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
