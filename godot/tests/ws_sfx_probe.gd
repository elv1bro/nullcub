## Проба тактильных звуков мастерской WsSfx (UI/UX spec v0.3 §39), headless: аудио-драйвер Dummy — звука нет, логика та же.
## Проверки (checks[].id):
##   no_errors — за весь прогон ни одной ошибки движка / скрипта (Logger; предупреждение о неизвестном виде — не ошибка);
##   bus_ui — шина "UI" → Master; voices — пул из 8 AudioStreamPlayer;
##   bank_<вид>[_<материал>] — все варианты: AudioStreamWAV PCM16 моно 44.1 кГц, длина ≥ 15 мс и < 250 мс даже при самом низком
##     случайном питче, пик < −1 dBFS и > −40 dBFS (не тишина), варианты не одинаковые; bake_time — самый долгий вариант;
##   mix — громкость на слух (K-взвешивание BS.1770, максимум по окнам 50 мс, «LK»): ничего громче −14 LK (тихий интерфейс),
##     ничего тише −30 (кроме наведения), наведение хотя бы на 10 LU тише кнопки, щелчки материалов в ±2.5 LU от дерева;
##   play_<вид>[_<материал>] — каждый вызов занял голос: у плеера тот же поток банка (stream != null), питч и громкость в разбросе;
##   snap_alias — play("snap", "brass" / "rust_red" / "iron") звучит металлом; rate_limit — второй "hover" раньше 60 мс съеден,
##     другой вид тут же проходит, "hover" через 70 мс снова звучит; overlap — 5 видов разом на 5 разных голосах;
##   pool_steal — 13 видов разом: все сыграны, голосов не больше 8; disabled / volume / unknown / not_ready;
##   warm_up — узел с допеканием по кадрам (по умолчанию) снимает _process за «вариантов + 2» кадра;
##   material_of — таблица деталей кита (пружина, верёвка, щупальце, железо, латунь, ржавчина, краска, старые wood_* / metal_*,
##     перекраска узла); wire_buttons — наведение, кнопка, вкладка, свой вид, клик по выключенной, повторное подключение.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/ws_sfx_probe.tscn -- "wav=/abs/dir"
## wav= — записать каждый вид в <dir>/<вид>.wav (варианты подряд через 350 мс тишины, уровень банка без volume_db; щелчок —
## snap.wav и snap_<материал>.wav) и _tour.wav — кусок сборки (наведения, взять, поставить, откатить…) с volume_db, как в игре.
## Отчёт tests/ws_sfx_probe_report.json, exit 0/1.
extends Node

const GAP_WAV_MS := 350.0
const LEN_MAX_S := 0.25
const LEN_MIN_S := 0.015
const PEAK_MAX_DB := -1.0
const PEAK_MIN_DB := -40.0
const BAKE_MAX_MS := 100.0
const LOUD_MAX := -14.0
const LOUD_MIN := -30.0
const HOVER_UNDER_LU := 10.0
const SNAP_SPREAD_LU := 2.5


class ErrCount extends Logger:
	var errors := 0
	var warnings := 0
	var last := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			warnings += 1
		else:
			errors += 1
			last = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]

	func _log_message(_message: String, _error: bool) -> void:
		pass


var wav_dir := ""
var sfx: WsSfx
var log_ := ErrCount.new()
var report := {"ok": true, "checks": [], "info": {}}


func _ready() -> void:
	OS.add_logger(log_)
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=", true, 1)
			if p.size() == 2 and p[0] == "wav":
				wav_dir = p[1]
	report["info"]["display"] = DisplayServer.get_name()
	report["info"]["audio_driver"] = AudioServer.get_driver_name()
	report["info"]["mix_rate"] = AudioServer.get_mix_rate()
	_check_bank()
	sfx = WsSfx.new()
	sfx.name = "WsSfx"
	sfx.warm_up = false
	add_child(sfx)
	await get_tree().process_frame
	_check_setup()
	_check_play_all()
	_check_limits()
	_check_material_of()
	await _check_wire()
	await _check_warm_up()
	if wav_dir != "":
		_write_wavs()
	# голоса глушим и даём аудио-потоку их снять — иначе на выходе утечка playback-ов
	sfx.stop_all()
	for i in range(10):
		OS.delay_msec(20)
		await get_tree().process_frame
	_finish()


func _check(id: String, ok: bool, value: Variant = null, limit: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value, "limit": limit})
	if not ok:
		report["ok"] = false
	print("%s %s  %s%s" % ["ok  " if ok else "FAIL", id, str(value) if value != null else "",
		("  (limit %s)" % str(limit)) if limit != null else ""])


# --- банк ---

func _bank_ids() -> Array:
	var out: Array = []
	for kind in WsSfx.KINDS:
		if kind == "snap":
			for m in [""] + WsSfx.MATERIALS:
				out.append([kind, m])
		else:
			out.append([kind, ""])
	return out


func _check_bank() -> void:
	var worst_ms := 0.0
	var worst_key := ""
	var t_all := Time.get_ticks_usec()
	for k in WsSfx.all_keys():
		var t0 := Time.get_ticks_usec()
		WsSfx.bake(k[0], k[1], k[2])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms > worst_ms:
			worst_ms = ms
			worst_key = "%s|%s|%d" % k
	var all_ms := (Time.get_ticks_usec() - t_all) / 1000.0
	_check("bake_time", worst_ms < BAKE_MAX_MS, "worst %.1f ms (%s), all %d variants %.0f ms" % [worst_ms, worst_key,
		WsSfx.all_keys().size(), all_ms], "< %.0f ms" % BAKE_MAX_MS)
	WsSfx.warm_all()
	var summary: Array = []
	for id in _bank_ids():
		var kind: String = id[0]
		var mat: String = id[1]
		var nv := WsSfx.variant_count(kind)
		var ok := nv > 0
		var why := ""
		var bodies: Array = []
		var j: float = WsSfx.PITCH_JITTER[kind]
		var lens: Array = []
		var peaks: Array = []
		var rmss: Array = []
		var louds: Array = []
		for v in range(nv):
			var s := WsSfx.stream_for(kind, mat, v)
			if s == null or s.format != AudioStreamWAV.FORMAT_16_BITS or s.stereo or s.mix_rate != WsSfx.RATE:
				ok = false
				why = "формат v%d" % v
				continue
			var st := _stats(s.data)
			var len_s := s.get_length()
			var worst_len := len_s / (1.0 - j)
			lens.append(snappedf(len_s * 1000.0, 1.0))
			peaks.append(snappedf(st["peak_db"], 0.1))
			rmss.append(snappedf(st["rms_db"], 0.1))
			louds.append(snappedf(_loudness(s.data), 0.1))
			if len_s < LEN_MIN_S or worst_len >= LEN_MAX_S:
				ok = false
				why += " длина v%d %.0f мс (при питче −%d%% — %.0f)" % [v, len_s * 1000.0, roundi(j * 100.0), worst_len * 1000.0]
			if st["peak_db"] >= PEAK_MAX_DB or st["peak_db"] <= PEAK_MIN_DB:
				ok = false
				why += " пик v%d %.1f dBFS" % [v, st["peak_db"]]
			if bodies.has(s.data):
				ok = false
				why += " v%d повторяет другой вариант" % v
			bodies.append(s.data)
		var name_ := _file_name(kind, mat)
		_check("bank_" + name_, ok, "мс %s, пик dBFS %s, RMS dBFS %s, LK %s%s" % [lens, peaks, rmss, louds, why],
			"%d–%d мс, пик (%d; %d) dBFS" % [roundi(LEN_MIN_S * 1000.0), roundi(LEN_MAX_S * 1000.0), roundi(PEAK_MIN_DB), roundi(PEAK_MAX_DB)])
		summary.append({"id": name_, "ms": lens, "peak_db": peaks, "rms_db": rmss, "lk": louds})
	report["info"]["bank"] = summary
	_check_mix(summary)


## Микс видов: средняя громкость вариантов (LK) по правилам из шапки.
func _check_mix(summary: Array) -> void:
	var lk: Dictionary = {}
	for e in summary:
		var sum := 0.0
		for x in e["lk"]:
			sum += float(x)
		lk[e["id"]] = sum / maxf(1.0, float(e["lk"].size()))
	var bad: Array = []
	for id in lk.keys():
		if lk[id] > LOUD_MAX:
			bad.append("%s громко %.1f" % [id, lk[id]])
		if id != "hover" and lk[id] < LOUD_MIN:
			bad.append("%s тихо %.1f" % [id, lk[id]])
	if lk.get("button", 0.0) - lk.get("hover", 0.0) < HOVER_UNDER_LU:
		bad.append("hover всего на %.1f LU тише button" % (lk.get("button", 0.0) - lk.get("hover", 0.0)))
	for m in WsSfx.MATERIALS + [""]:
		var id: String = "snap" if m == "" else "snap_" + m
		if absf(lk.get(id, -99.0) - lk.get("snap_wood", 0.0)) > SNAP_SPREAD_LU:
			bad.append("%s %.1f против дерева %.1f" % [id, lk.get(id, -99.0), lk.get("snap_wood", 0.0)])
	var parts: Array = []
	for id in lk.keys():
		parts.append("%s %.1f" % [id, lk[id]])
	_check("mix", bad.is_empty(), "LK: %s%s" % [", ".join(parts), ("; " + "; ".join(bad)) if not bad.is_empty() else ""],
		"≤ %.0f, ≥ %.0f, hover ≤ button − %.0f, щелчки ±%.1f" % [LOUD_MAX, LOUD_MIN, HOVER_UNDER_LU, SNAP_SPREAD_LU])


## Громкость на слух: K-взвешивание BS.1770 (полка +4 дБ от 1.68 кГц и ФВЧ 38 Гц, биквады по RBJ как в pyloudnorm), максимум
## среднего квадрата по окнам 50 мс с шагом 12.5 мс, −0.691 + 10·lg — для коротких звуков честнее пика и RMS всего файла.
func _loudness(data: PackedByteArray) -> float:
	var n := data.size() / 2
	var x := PackedFloat32Array()
	x.resize(n)
	for i in range(n):
		x[i] = data.decode_s16(i * 2) / 32767.0
	var r := float(WsSfx.RATE)
	# полка
	var a_ := pow(10.0, 3.99984385397 / 40.0)
	var w0 := TAU * 1681.9744509555319 / r
	var al := sin(w0) / (2.0 * 0.7071752369554193)
	var c := cos(w0)
	var sa := 2.0 * sqrt(a_) * al
	var a0 := (a_ + 1.0) - (a_ - 1.0) * c + sa
	x = _biquad(x, a_ * ((a_ + 1.0) + (a_ - 1.0) * c + sa) / a0, -2.0 * a_ * ((a_ - 1.0) + (a_ + 1.0) * c) / a0,
		a_ * ((a_ + 1.0) + (a_ - 1.0) * c - sa) / a0, 2.0 * ((a_ - 1.0) - (a_ + 1.0) * c) / a0, ((a_ + 1.0) - (a_ - 1.0) * c - sa) / a0)
	# ФВЧ
	w0 = TAU * 38.13547087613982 / r
	al = sin(w0) / (2.0 * 0.5003270373253953)
	c = cos(w0)
	a0 = 1.0 + al
	x = _biquad(x, (1.0 + c) / 2.0 / a0, -(1.0 + c) / a0, (1.0 + c) / 2.0 / a0, -2.0 * c / a0, (1.0 - al) / a0)
	var win := int(0.05 * r)
	var best := 0.0
	var i0 := 0
	while i0 < n:
		var e := 0.0
		for i in range(i0, mini(n, i0 + win)):
			e += x[i] * x[i]
		best = maxf(best, e / float(win))
		i0 += win / 4
	return -0.691 + 10.0 * log(best + 1.0e-12) / log(10.0)


func _biquad(x: PackedFloat32Array, b0: float, b1: float, b2: float, a1: float, a2: float) -> PackedFloat32Array:
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in range(x.size()):
		var v := b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = v
		y[i] = v
	return y


func _stats(data: PackedByteArray) -> Dictionary:
	var n := data.size() / 2
	var pk := 0
	var e := 0.0
	for i in range(n):
		var x := data.decode_s16(i * 2)
		pk = maxi(pk, absi(x))
		e += float(x) * float(x)
	var peak := float(pk) / 32767.0
	var rms := sqrt(e / maxf(1.0, float(n))) / 32767.0
	return {"peak_db": linear_to_db(peak) if peak > 0.0 else -200.0, "rms_db": linear_to_db(rms) if rms > 0.0 else -200.0}


func _file_name(kind: String, mat: String) -> String:
	return kind if mat == "" else "%s_%s" % [kind, mat]


# --- пул и воспроизведение ---

func _check_setup() -> void:
	var bi := AudioServer.get_bus_index(WsSfx.BUS)
	_check("bus_ui", bi >= 0 and AudioServer.get_bus_send(bi) == &"Master", "шина %d → %s" % [bi,
		AudioServer.get_bus_send(bi) if bi >= 0 else "—"], "UI → Master")
	var players := 0
	for c in sfx.get_children():
		if c is AudioStreamPlayer:
			players += 1
	_check("voices", sfx.voice_count() == WsSfx.VOICES and players == WsSfx.VOICES, "%d голосов, %d детей" % [sfx.voice_count(), players],
		WsSfx.VOICES)


## Один вызов play: вернуть запись журнала (или {} — съеден).
func _play(kind: String, mat := "") -> Dictionary:
	var n := sfx.played.size()
	sfx.play(kind, mat)
	return sfx.played[-1] if sfx.played.size() > n else {}


func _check_play_all() -> void:
	var playing := 0
	var total := 0
	for id in _bank_ids():
		var kind: String = id[0]
		var mat: String = id[1]
		OS.delay_msec(int(WsSfx.GAP_MS[kind]) + 5)
		var e := _play(kind, mat)
		var ok := not e.is_empty()
		var val := "съеден"
		if ok:
			var p := sfx.voice(int(e["voice"]))
			var want := WsSfx.stream_for(kind, mat, int(e["variant"]))
			var j: float = WsSfx.PITCH_JITTER[kind]
			ok = p != null and p.stream != null and p.stream == want and e["kind"] == kind and e["material"] == mat \
				and absf(p.pitch_scale - 1.0) <= j + 0.001 and absf(p.volume_db - sfx.volume_db) <= WsSfx.VOL_JITTER_DB + 0.01
			total += 1
			if p != null and p.playing:
				playing += 1
			val = "голос %d, вариант %d, питч %.3f, %.2f dB, playing=%s" % [e["voice"], e["variant"], p.pitch_scale, p.volume_db, p.playing]
		_check("play_" + _file_name(kind, mat), ok, val, "stream банка, питч ±%d%%" % roundi(float(WsSfx.PITCH_JITTER[kind]) * 100.0))
	report["info"]["playing_after_play"] = "%d/%d" % [playing, total]
	var alias_ok := true
	var got: Array = []
	for m in ["brass", "rust_red", "iron"]:
		OS.delay_msec(int(WsSfx.GAP_MS["snap"]) + 5)
		var e := _play("snap", m)
		got.append(e.get("material", "съеден"))
		alias_ok = alias_ok and e.get("material", "") == "metal"
	_check("snap_alias", alias_ok, got, "metal")


func _check_limits() -> void:
	# лимит частоты: второй hover сразу — съеден, другой вид проходит, через 70 мс hover снова звучит
	sfx.reset_limits()
	var g0: int = sfx.dropped["gap"]
	var a := _play("hover")
	var b := _play("hover")
	var c := _play("tab")
	OS.delay_msec(70)
	var d := _play("hover")
	_check("rate_limit", not a.is_empty() and b.is_empty() and not c.is_empty() and not d.is_empty() and sfx.dropped["gap"] == g0 + 1,
		"hover %s, hover сразу %s, tab %s, hover через 70 мс %s, gap +%d" % [not a.is_empty(), not b.is_empty(), not c.is_empty(),
		not d.is_empty(), sfx.dropped["gap"] - g0], "1-й да, 2-й нет, tab да, через 70 мс да")
	# наложение: 5 видов разом — 5 разных голосов
	OS.delay_msec(450)
	sfx.reset_limits()
	var vs: Array = []
	for k in ["button", "grab", "snap", "unscrew", "test"]:
		var e := _play(k, "wood" if k == "snap" else "")
		if not e.is_empty() and not vs.has(e["voice"]):
			vs.append(e["voice"])
	_check("overlap", vs.size() == 5 and sfx.active_voices() >= 5, "голоса %s, звучит %d" % [vs, sfx.active_voices()], "5 разных")
	# вытеснение: 13 видов разом — все сыграны, голосов не больше пула
	OS.delay_msec(450)
	sfx.reset_limits()
	var n := 0
	var max_v := -1
	for k in WsSfx.KINDS:
		var e := _play(k)
		if not e.is_empty():
			n += 1
			max_v = maxi(max_v, int(e["voice"]))
	_check("pool_steal", n == WsSfx.KINDS.size() and max_v < WsSfx.VOICES and sfx.active_voices() <= WsSfx.VOICES,
		"сыграно %d/%d, макс. голос %d, звучит %d" % [n, WsSfx.KINDS.size(), max_v, sfx.active_voices()], "все, голосов ≤ %d" % WsSfx.VOICES)
	# выключен — тишина
	sfx.reset_limits()
	sfx.enabled = false
	var dis0: int = sfx.dropped["disabled"]
	var e1 := _play("button")
	sfx.enabled = true
	_check("disabled", e1.is_empty() and sfx.dropped["disabled"] == dis0 + 1, "съеден %s" % e1.is_empty(), "enabled = false — без звука")
	# громкость
	sfx.reset_limits()
	sfx.volume_db = -20.0
	var e2 := _play("button")
	var db: float = e2.get("db", 0.0)
	sfx.volume_db = -6.0
	_check("volume", not e2.is_empty() and absf(db + 20.0) <= WsSfx.VOL_JITTER_DB + 0.01, "%.2f dB" % db, "−20 ± %.1f" % WsSfx.VOL_JITTER_DB)
	# неизвестный вид — счётчик и одно предупреждение, не ошибка
	var u0: int = sfx.dropped["unknown"]
	sfx.play("nope")
	sfx.play("nope")
	_check("unknown", sfx.dropped["unknown"] == u0 + 2, "unknown +%d" % (sfx.dropped["unknown"] - u0), "+2, без ошибок")
	# вне дерева — тихо съеден
	var loose := WsSfx.new()
	loose.play("button")
	var nr: int = loose.dropped["not_ready"]
	loose.free()
	_check("not_ready", nr == 1, "not_ready %d" % nr, 1)


func _check_material_of() -> void:
	var cases := [
		["kit_limb_spring_l", "", "spring"], ["kit_foot_spring", "", "spring"], ["kit_limb_spring_s", "wood", "spring"],
		["kit_limb_rope_s", "", "rope"], ["kit_limb_tentacle_l", "", "rope"], ["kit_limb_rope_l", "iron", "rope"],
		["kit_limb_thin_l", "", "metal"], ["kit_head_lantern", "", "metal"], ["kit_hand_fist", "", "metal"],
		["kit_core_boiler", "", "metal"], ["chain_segment", "", "metal"], ["metal_head", "", "metal"],
		["kit_limb_basic_l", "", "wood"], ["kit_head_bot", "", "wood"], ["kit_head_skull", "", "wood"], ["wood_hand", "", "wood"],
		["kit_limb_basic_l", "iron", "metal"], ["kit_limb_basic_l", "brass", "metal"], ["kit_limb_thin_l", "wood", "wood"],
		["kit_limb_thin_l", "paint_red", "wood"], ["", "rust", "metal"], ["", "steel", "metal"], ["", "", "wood"],
		["", "planks", "wood"],
	]
	var bad: Array = []
	for c in cases:
		var part: PartDef = null
		if c[0] != "":
			part = load("res://data/body/parts/%s.tres" % c[0]) as PartDef
			if part == null:
				bad.append("%s: нет детали" % c[0])
				continue
		var got := WsSfx.material_of(part, c[1])
		if got != c[2]:
			bad.append("%s/%s → %s (ждали %s)" % [c[0], c[1], got, c[2]])
	_check("material_of", bad.is_empty(), "%d/%d %s" % [cases.size() - bad.size(), cases.size(), bad if not bad.is_empty() else ""],
		"все случаи")


func _check_wire() -> void:
	var root := Control.new()
	add_child(root)
	var box := HBoxContainer.new()
	root.add_child(box)
	var plain := Button.new()
	var tab := Button.new()
	tab.toggle_mode = true
	tab.button_group = ButtonGroup.new()
	var off := Button.new()
	off.disabled = true
	var fight := Button.new()
	fight.set_meta(&"ws_sfx_kind", "test")
	var mute := Button.new()
	mute.set_meta(&"ws_sfx_off", true)
	for bt in [plain, tab, off, fight, mute]:
		box.add_child(bt)
	await get_tree().process_frame
	var n := sfx.wire_buttons(root)
	var n2 := sfx.wire_buttons(root)
	var got: Array = []
	var steps := [
		[func() -> void: plain.mouse_entered.emit(), "hover"],
		[func() -> void: plain.pressed.emit(), "button"],
		[func() -> void: tab.pressed.emit(), "tab"],
		[func() -> void: fight.pressed.emit(), "test"],
		[func() -> void: off.mouse_entered.emit(), ""],
		[func() -> void: off.gui_input.emit(_click_event()), "invalid"],
		[func() -> void: mute.pressed.emit(), ""],
	]
	var ok := n == 4 and n2 == 0
	for s in steps:
		sfx.reset_limits()
		var k0 := sfx.played.size()
		(s[0] as Callable).call()
		var kind: String = sfx.played[-1]["kind"] if sfx.played.size() > k0 else ""
		got.append(kind if kind != "" else "—")
		ok = ok and kind == s[1]
	_check("wire_buttons", ok, "подключено %d, повторно %d, звуки %s" % [n, n2, got],
		"4, 0, [hover, button, tab, test, —, invalid, —]")
	root.queue_free()


func _check_warm_up() -> void:
	var w := WsSfx.new()
	add_child(w)
	var busy_after_ready := w.is_processing()
	var frames := 0
	var limit := WsSfx.all_keys().size() + 2
	while w.is_processing() and frames < limit + 10:
		await get_tree().process_frame
		frames += 1
	_check("warm_up", busy_after_ready and not w.is_processing() and frames <= limit, "допекание %s, снято за %d кадров" % [
		busy_after_ready, frames], "≤ %d кадров" % limit)
	w.queue_free()


func _click_event() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


# --- WAV для прослушивания ---

func _write_wavs() -> void:
	DirAccess.make_dir_recursive_absolute(wav_dir)
	var gap := PackedByteArray()
	gap.resize(int(GAP_WAV_MS * 0.001 * WsSfx.RATE) * 2)
	gap.fill(0)
	var written: Array = []
	var ok := true
	for id in _bank_ids():
		var body := PackedByteArray()
		for v in range(WsSfx.variant_count(id[0])):
			if v > 0:
				body.append_array(gap)
			body.append_array(WsSfx.stream_for(id[0], id[1], v).data)
		var path := wav_dir.path_join(_file_name(id[0], id[1]) + ".wav")
		ok = _save_wav(path, body) and ok
		written.append(path.get_file())
	var tour := _tour()
	ok = _save_wav(wav_dir.path_join("_tour.wav"), tour["data"]) and ok
	_check("tour_peak", tour["peak_db"] < PEAK_MAX_DB, "%.1f dBFS" % tour["peak_db"], "< %.0f dBFS" % PEAK_MAX_DB)
	_check("wav_written", ok, "%s + _tour.wav → %s" % [written.size(), wav_dir], "RIFF PCM16 моно 44.1 кГц")


## Кусок сборки с volume_db (как в игре): наведение по карточкам, взять, поставить (дерево, металл, пружина, верёвка),
## отказ, откатить / вернуть, зеркало, дубликат, откручивание, удалить, в комнату испытаний.
func _tour() -> Dictionary:
	var ev := [[0, "hover", ""], [90, "hover", ""], [170, "hover", ""], [260, "hover", ""], [600, "button", ""], [1000, "tab", ""],
		[1400, "hover", ""], [1700, "grab", ""], [2300, "snap", "wood"], [2900, "grab", ""], [3500, "invalid", ""],
		[3900, "snap", "metal"], [4500, "grab", ""], [5100, "snap", "spring"], [5700, "grab", ""], [6300, "snap", "rope"],
		[6900, "snap", ""], [7500, "undo", ""], [7700, "undo", ""], [8000, "redo", ""], [8500, "mirror", ""],
		[9100, "duplicate", ""], [9700, "unscrew", ""], [10300, "delete", ""], [10900, "tab", ""], [11300, "test", ""]]
	var total := int(12.0 * WsSfx.RATE)
	var mix := PackedFloat32Array()
	mix.resize(total)
	mix.fill(0.0)
	var g := db_to_linear(-6.0)
	var nv: Dictionary = {}
	for e in ev:
		var key := "%s|%s" % [e[1], e[2]]
		var v: int = nv.get(key, 0)
		nv[key] = v + 1
		var s := WsSfx.stream_for(e[1], e[2], v % WsSfx.variant_count(e[1]))
		var i0 := int(float(e[0]) * 0.001 * WsSfx.RATE)
		for i in range(s.data.size() / 2):
			if i0 + i < total:
				mix[i0 + i] += s.data.decode_s16(i * 2) / 32767.0 * g
	var out := PackedByteArray()
	out.resize(total * 2)
	var pk := 0.0
	for i in range(total):
		pk = maxf(pk, absf(mix[i]))
		out.encode_s16(i * 2, clampi(roundi(mix[i] * 32767.0), -32768, 32767))
	return {"data": out, "peak_db": linear_to_db(pk) if pk > 0.0 else -200.0}


## RIFF WAVE: заголовок 44 байта (fmt PCM 1, моно, 16 бит, RATE) + data; проверка — размер файла на диске.
func _save_wav(path: String, pcm: PackedByteArray) -> bool:
	var h := PackedByteArray()
	h.resize(44)
	var rate := WsSfx.RATE
	h.encode_u32(0, 0x46464952)          # "RIFF"
	h.encode_u32(4, 36 + pcm.size())
	h.encode_u32(8, 0x45564157)          # "WAVE"
	h.encode_u32(12, 0x20746d66)         # "fmt "
	h.encode_u32(16, 16)
	h.encode_u16(20, 1)                  # PCM
	h.encode_u16(22, 1)                  # моно
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164)         # "data"
	h.encode_u32(40, pcm.size())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(h)
	f.store_buffer(pcm)
	f.close()
	return FileAccess.get_file_as_bytes(path).size() == 44 + pcm.size()


func _finish() -> void:
	_check("no_errors", log_.errors == 0, "ошибок %d, предупреждений %d %s" % [log_.errors, log_.warnings, log_.last], 0)
	var failed := 0
	for c in report["checks"]:
		if not c["ok"]:
			failed += 1
	var f := FileAccess.open("res://tests/ws_sfx_probe_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	print("=== %s (%d/%d) ===" % ["OK" if report["ok"] else "FAIL", report["checks"].size() - failed, report["checks"].size()])
	print("WS SFX OK" if report["ok"] else "WS SFX FAIL")
	OS.remove_logger(log_)
	get_tree().quit(0 if report["ok"] else 1)
