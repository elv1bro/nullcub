## Проба СТАЗИСА (docs/plan-demo/STASIS.md, задание TASK_STASIS.md §6): время боя идёт, только пока человек жмёт свои действия.
## Ввод — Input.action_press / action_release действий p1_* / p2_* (как клавиатура), время — кадры процесса (--fixed-fps 60:
## кадр = 1/60 реальной секунды). Проверки (номера — §6 задания):
##   core   (Void, P1 человек, P2 RivalBrain) 1 — режим выкл: масштаб ровно 1; 2 — вкл, ввода нет 0.5 с: STASIS_IDLE_SCALE ± 0.005;
##          3 — нажал: масштаб ≥ 0.95 не позже RAMP_UP + 2 кадра; 4 — от нажатия до изменения скорости торса P1 ≤ 5 кадров;
##          5 — отпустил: у IDLE не позже RAMP_DOWN + 2 кадра; 6 — 2 с без ввода: часы матча и путь бота ≈ 2 × IDLE (± 20 %);
##   phases 7 — COUNTDOWN и OVER с вводом и без: 1.0;
##   stop   8 — стоп-кадр поверх режима: минимум из двух, после — снова масштаб режима (и стоя, и в движении);
##   crit   9 — крит-кино при стоящем игроке: длительность в реальном времени ≤ 1.2 × режима «выкл», режим во время кино молчит;
##   nohuman 10 — оба бойца не люди: 1.0; sport — человек в нокауте: 1.0, возврат через SPORT_KO_RESPAWN_S как без режима;
##   coop   11 — PvE вдвоём: P2 не нажимал — не держит время (P1 в нокауте → 1.0); нажал — его ввод двигает время, стоит — замирает;
##   sport  13 — пауза после гола и ввод мяча без ввода игрока: не длиннее, чем с режимом «выкл»;
##   pve    14 — бот-«человек» (жмёт p1_*, как P1 в drive_probe, с паузами «подумать») зачищает волну 1 с режимом: проходит,
##             игровое время ≤ 1.5 × без режима (медиана по trials);
##   mode   — отдельный режим ВСЕ РЕЖИМЫ (playground_stasis.tscn): внутри режим включён и волна ждёт игрока, после выхода Stasis.on
##             как до входа (вкл / выкл);
##   scenes 12 — настоящими клавишами: Esc (пауза: масштаб 1, меню живое, выход — прежний масштаб), R, смена арены 2, «В ГАРАЖ»
##             посреди замирания, закрытие сцены — после масштаб 1.0;
##   15 — масштаб за весь прогон не ниже Tuning.HITFX_TIME_SCALE_MIN; errors — SCRIPT ERROR за прогон 0 (Logger).
## Запуск: godot --headless --path godot --fixed-fps 60 res://tests/stasis_probe.tscn -- "only=core,phases,stop,crit,nohuman,coop,sport,pve,mode,scenes,trials=6,think_s=0.4,out=<json>"
## → JSON между === STASIS PROBE === и === OK / FAIL ===, exit 0/1. scenes — последней: меняет сцену (гараж грузится ≈ 10–30 с).
extends Node


func _ready() -> void:
	var r := Runner.new()
	r.name = "StasisProbeRunner"
	get_tree().root.call_deferred("add_child", r)   # переживает смену сцены (раздел scenes)


## Счётчик SCRIPT ERROR за прогон (как hitfx_core_probe): ошибка скрипта в Godot 4.7 обрывает только свою функцию, проба могла бы
## молча потерять проверки. Ошибки движка не в счёт. Logger зовут из любого потока — под мьютексом.
class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mx.lock()
		count += 1
		if first == "":
			first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


class Runner extends Node:
	const VOID := "res://scenes/playground_void.tscn"
	const WORKSHOP := "res://scenes/playground_workshop.tscn"
	const SPORT := "res://scenes/playground_sport.tscn"
	const PVE := "res://scenes/playground_pve.tscn"
	const STASIS_PG := "res://scenes/playground_stasis.tscn"
	const MENU := "res://scenes/menu/garage_menu.tscn"
	const FPS := 60.0
	const SECTIONS := ["core", "phases", "stop", "crit", "nohuman", "coop", "sport", "pve", "mode", "scenes"]
	const THINK_EVERY_S := 2.5      # бот-«человек» PvE: раз в столько реальных секунд отпускает всё…
	const THINK_S := 0.4            # …на столько (думает) — мир в это время стоит
	const WAVE_MAX_S := 120.0       # реальных секунд на волну 1

	var ok := true
	var checks: Array = []
	var info := {}
	var errs := ScriptErrors.new()
	var min_ts := 1.0
	var min_ts_at := ""
	var frames := 0
	var section := ""
	var pg: Node = null
	var m: Match = null
	var p1: Doll = null
	var p2: Doll = null
	var args := {"only": ",".join(SECTIONS), "trials": "6", "out": "", "think_s": str(THINK_S)}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		OS.add_logger(errs)
		get_tree().physics_frame.connect(_track_ts)
		_parse_args()
		_run.call_deferred()

	func _parse_args() -> void:
		for a in OS.get_cmdline_user_args():
			var key := ""
			for part in String(a).split(","):
				var kv := part.split("=")
				if kv.size() == 2 and args.has(kv[0]):
					key = kv[0]
					args[key] = kv[1]
				elif key == "only":
					args[key] = String(args[key]) + "," + part

	func _run() -> void:
		print("=== STASIS PROBE ===")
		var only := String(args["only"]).split(",", false)
		for s in SECTIONS:
			if only.has(s):
				section = s
				print("--- %s" % s)
				await call("_s_" + s)
				await _unload()
		section = "end"
		_release_all()
		Stasis.set_on(false)
		_check("15_min_time_scale", min_ts >= Tuning.HITFX_TIME_SCALE_MIN - 1e-6, snappedf(min_ts, 0.0001),
			">= %.2f (HITFX_TIME_SCALE_MIN), min at %s" % [Tuning.HITFX_TIME_SCALE_MIN, min_ts_at])
		_check("errors_script", errs.count == 0, errs.count, "ошибок скриптов 0 (Logger); первая: %s" % errs.first)
		var report := {"ok": ok, "checks": checks, "info": info, "tuning": {"idle": Tuning.STASIS_IDLE_SCALE,
			"ramp_up_s": Tuning.STASIS_RAMP_UP_S, "ramp_down_s": Tuning.STASIS_RAMP_DOWN_S}}
		print(JSON.stringify(report, " "))
		if String(args["out"]) != "":
			var f := FileAccess.open(String(args["out"]), FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(report, " "))
				f.close()
		var n_ok := 0
		for c in checks:
			if c["ok"]:
				n_ok += 1
		print("stasis_probe: %d/%d ok" % [n_ok, checks.size()])
		print("=== OK ===" if ok else "=== FAIL ===")
		OS.remove_logger(errs)
		get_tree().quit(0 if ok else 1)

	# ---------------------------------------------------------------- помощники

	func _check(id: String, cond: bool, value: Variant, limit: String) -> void:
		checks.append({"id": id, "ok": cond, "value": value, "limit": limit})
		if not cond:
			ok = false
		print("  %-34s %s  %s  (%s)" % [id, "ok  " if cond else "FAIL", str(value), limit])

	func _track_ts() -> void:
		if Engine.time_scale < min_ts:
			min_ts = Engine.time_scale
			min_ts_at = "%s, frame %d" % [section, frames]

	## Кадр процесса: код после него идёт раньше Match._process этого кадра (сигнал process_frame — до узлов), масштаб — тот, что
	## Match поставил в прошлом кадре.
	func _frame() -> void:
		await get_tree().process_frame
		frames += 1
		_track_ts()

	func _frames(n: int) -> void:
		for i in n:
			await _frame()

	func _until(cond: Callable, max_frames: int) -> int:
		for i in max_frames:
			if cond.call():
				return i
			await _frame()
		return max_frames if not cond.call() else max_frames

	func _press(a: String, s := 1.0) -> void:
		if s > 0.02:
			Input.action_press(a, clampf(s, 0.0, 1.0))
		else:
			Input.action_release(a)

	func _release_all() -> void:
		for pre in ["p1", "p2"]:
			for a in Stasis.actions_of(pre):
				Input.action_release(a)

	func _key(code: Key) -> void:
		for p in [true, false]:
			var e := InputEventKey.new()
			e.physical_keycode = code
			e.keycode = code
			e.pressed = p
			Input.parse_input_event(e)
		await _frames(2)

	func _ts_near(v: float, eps := 0.005) -> bool:
		return absf(Engine.time_scale - v) <= eps

	func _load(path: String, setup := Callable(), feel := false, countdown := 0.3) -> void:
		await _unload()
		Engine.time_scale = 1.0
		pg = (load(path) as PackedScene).instantiate()
		m = pg.get_node_or_null("Match") as Match
		if m == null:
			m = pg.get_node_or_null("WaveDirector") as Match
		m.feel_enabled = feel
		m.countdown_s = countdown
		p1 = pg.get_node_or_null("P1") as Doll
		p2 = pg.get_node_or_null("P2") as Doll
		if setup.is_valid():
			setup.call()
		add_child(pg)
		await _frames(2)

	func _unload() -> void:
		_release_all()
		if pg != null and is_instance_valid(pg):
			pg.queue_free()
		pg = null
		m = null
		await _frames(3)

	func _brain(d: Doll, level := 3) -> void:
		var b := RivalBrain.new()
		b.name = "Brain"
		b.level = level
		d.add_child(b)

	func _void_bot_p2() -> void:
		p1.add_to_group("players")
		p2.add_to_group("rivals")
		_brain(p2)

	func _fight(max_s := 4.0) -> bool:
		await _until(func() -> bool: return m != null and m.combat_active(), int(max_s * FPS))
		return m != null and m.combat_active()

	static func _com_v(d: Doll) -> Vector3:
		var p := Vector3.ZERO
		for b in d.parts.values():
			p += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
		return p / maxf(d.total_mass, 0.001)

	# ---------------------------------------------------------------- 1–6: Void, P1 человек, P2 бот

	func _s_core() -> void:
		Stasis.set_on(false)
		await _load(VOID, _void_bot_p2)
		var fought := await _fight()
		_check("core_fight", fought and p2.external_input and not p1.external_input, m.phase, "FIGHT, P2 — бот, P1 — человек")
		# 1 — режим выкл: масштаб ровно 1 (замедлений нет: feel_enabled = false)
		var worst := 0.0
		for i in 30:
			await _frame()
			worst = maxf(worst, absf(Engine.time_scale - 1.0))
		_check("01_off_scale", worst == 0.0 and m.stasis_scale() == 1.0, worst, "max |time_scale − 1| == 0 за 0.5 с")
		# 2 — вкл, ввода нет 0.5 с
		Stasis.set_on(true)
		await _frames(30)
		_check("02_idle_scale", _ts_near(Tuning.STASIS_IDLE_SCALE), snappedf(Engine.time_scale, 0.0001), "%.2f ± 0.005" % Tuning.STASIS_IDLE_SCALE)
		# 3, 4 — нажал вправо: время ≥ 0.95 и торс P1 поехал
		var v0 := p1.torso().linear_velocity.x
		_press("p1_right")
		var n3 := -1
		var n4 := -1
		for i in range(1, 31):
			await _frame()
			if n3 < 0 and Engine.time_scale >= 0.95:
				n3 = i
			if n4 < 0 and is_instance_valid(p1) and p1.torso().linear_velocity.x - v0 >= 0.05:
				n4 = i
		var lim3 := int(ceil(Tuning.STASIS_RAMP_UP_S * FPS)) + 2
		_check("03_ramp_up_frames", n3 > 0 and n3 <= lim3, n3, "<= %d кадров (RAMP_UP_S %.2f + 2)" % [lim3, Tuning.STASIS_RAMP_UP_S])
		_check("04_input_to_torso_frames", n4 > 0 and n4 <= 5, n4, "<= 5 кадров (Δv_x торса ≥ 0.05 м/с)")
		# 5 — отпустил
		_release_all()
		var n5 := await _until(func() -> bool: return _ts_near(Tuning.STASIS_IDLE_SCALE), 60)
		var lim5 := int(ceil(Tuning.STASIS_RAMP_DOWN_S * FPS)) + 2
		_check("05_ramp_down_frames", n5 <= lim5, n5, "<= %d кадров (RAMP_DOWN_S %.2f + 2)" % [lim5, Tuning.STASIS_RAMP_DOWN_S])
		# 6 — окно «стоит» 2 с реального времени между двумя окнами «идёт» по 0.1 с игрового (P1 жмёт влево, прочь от бота): часы
		# матча — 2 × IDLE; путь бота — его скорость в игровом времени против средней из окон «идёт» (бот разгоняется — среднее
		# до и после убирает разгон). Утечка реального времени (толчок за тик без delta) дала бы ×20.
		m.restart()   # куклы пересоздаются (Match.respawn_doll) — ссылки заново
		p1 = pg.get_node("P1") as Doll
		p2 = pg.get_node("P2") as Doll
		await _fight()
		_press("p1_left")
		await _frames(18)   # бот тронулся
		var before := await _bot_window(6)
		_release_all()
		await _until(func() -> bool: return _ts_near(Tuning.STASIS_IDLE_SCALE), 60)
		var swin := await _bot_window(120)
		_press("p1_left")
		await _until(func() -> bool: return Engine.time_scale >= 0.999, 30)
		var after := await _bot_window(6)
		_release_all()
		var want := 2.0 * Tuning.STASIS_IDLE_SCALE
		var clock_k := float(swin["clock"]) / want
		var v_b := float(before["path"]) / maxf(float(before["clock"]), 1e-6)
		var v_a := float(after["path"]) / maxf(float(after["clock"]), 1e-6)
		var v_n := 0.5 * (v_b + v_a)
		var v_s := float(swin["path"]) / maxf(float(swin["clock"]), 1e-6)
		var bot_k := v_s / maxf(v_n, 1e-6)
		info["06"] = {"before": before, "frozen": swin, "after": after, "speed_before": snappedf(v_b, 0.01), "speed_after": snappedf(v_a, 0.01),
			"speed_frozen_game": snappedf(v_s, 0.01), "path_expected_m": snappedf(v_n * want, 0.0001)}
		_check("06_clock_2s_idle", absf(clock_k - 1.0) <= 0.2, snappedf(float(swin["clock"]), 0.0001), "%.2f с ± 20 %% (2 × IDLE)" % want)
		_check("06_bot_path_2s_idle", absf(bot_k - 1.0) <= 0.2 and v_n > 0.5, snappedf(bot_k, 0.001),
			"путь бота за 2 с / (средняя скорость окон «идёт» × 2 × IDLE) = 1 ± 20 %%: %.3f м против %.3f м (скорость до %.2f, после %.2f м/с)" % [
			float(swin["path"]), v_n * want, v_b, v_a])
		# 12d — закрыть сцену посреди замирания
		await _until(func() -> bool: return _ts_near(Tuning.STASIS_IDLE_SCALE), 60)
		var frozen_before := _ts_near(Tuning.STASIS_IDLE_SCALE)
		pg.queue_free()
		pg = null
		m = null
		await _frames(2)
		_check("12_close_scene_frozen", frozen_before and Engine.time_scale == 1.0, Engine.time_scale, "1.0 после закрытия сцены (до — IDLE)")

	## Окно n кадров: путь ЦМ бота P2 (сумма |Δ| по кадрам) и сколько прошло часов матча.
	func _bot_window(n: int) -> Dictionary:
		var c0 := m.fight_time
		var prev := p2.centre_of_mass()
		var path := 0.0
		for i in n:
			await _frame()
			var c := p2.centre_of_mass()
			path += Vector2(c.x - prev.x, c.y - prev.y).length()
			prev = c
		return {"frames": n, "clock": snappedf(m.fight_time - c0, 0.00001), "path": snappedf(path, 0.0001)}

	# ---------------------------------------------------------------- 7: отсчёт и итоги

	func _s_phases() -> void:
		Stasis.set_on(true)
		await _load(VOID, _void_bot_p2, false, 1.0)
		var worst := 0.0
		var n := 0
		while m.phase == Match.Phase.COUNTDOWN and n < 120:
			if n == 20:
				_press("p1_right")
			if n == 40:
				_release_all()
			await _frame()
			worst = maxf(worst, absf(Engine.time_scale - 1.0))
			n += 1
		_check("07_countdown", n >= 30 and worst == 0.0, worst, "max |time_scale − 1| == 0 за %d кадров отсчёта (с вводом и без)" % n)
		await _fight()
		await _frames(30)
		var frozen := _ts_near(Tuning.STASIS_IDLE_SCALE)
		p2.knock_out()
		await _until(func() -> bool: return m.phase == Match.Phase.OVER, 30)
		worst = 0.0
		for i in 60:
			if i == 20:
				_press("p1_up")
			if i == 40:
				_release_all()
			await _frame()
			worst = maxf(worst, absf(Engine.time_scale - 1.0))
		_check("07_over", frozen and m.phase == Match.Phase.OVER and worst == 0.0, worst,
			"до KO — IDLE (%s); в итогах max |time_scale − 1| == 0 (с вводом и без)" % frozen)

	# ---------------------------------------------------------------- 8: стоп-кадр поверх режима

	func _s_stop() -> void:
		Stasis.set_on(true)
		await _load(VOID, _void_bot_p2, true)
		await _fight()
		await _frames(30)
		var idle := Tuning.STASIS_IDLE_SCALE
		var stop := Tuning.HITFX_TIME_SCALE_MIN
		var a0 := Engine.time_scale
		var put := m.request_time_scale(stop, 0.1, "stasis_probe_stop")
		var a1 := Engine.time_scale
		var held := true
		for i in 4:
			await _frame()
			held = held and absf(Engine.time_scale - stop) < 1e-5
		var back := await _until(func() -> bool: return _ts_near(idle) and not m.time_scale_tags().has("stasis_probe_stop"), 30)
		var a := {"before": snappedf(a0, 0.0001), "at_put": snappedf(a1, 0.0001), "held": held, "back_frames": back}
		_check("08_stop_over_idle", put and _ts_near(idle, 0.005) and absf(a1 - stop) < 1e-5 and held and back <= 6 + 3, str(a),
			"стоя: min(%.2f, %.2f) = %.2f сразу и 0.1 с, потом снова %.2f" % [stop, idle, stop, idle])
		_press("p1_left")   # прочь от бота: удар поставил бы свой стоп-кадр посреди замера
		await _until(func() -> bool: return Engine.time_scale >= 0.999, 30)
		var b0 := Engine.time_scale
		m.request_time_scale(0.3, 0.1, "stasis_probe_slow")
		var b1 := Engine.time_scale
		var back2 := await _until(func() -> bool: return Engine.time_scale >= 0.999 and not m.time_scale_tags().has("stasis_probe_slow"), 30)
		_release_all()
		var b := {"before": snappedf(b0, 0.0001), "at_put": snappedf(b1, 0.0001), "back_frames": back2}
		_check("08_stop_over_moving", b0 >= 0.999 and absf(b1 - 0.3) < 1e-5 and back2 <= 6 + 3, str(b), "в движении: 0.3 поверх 1, потом снова 1")

	# ---------------------------------------------------------------- 9: крит-кино

	func _s_crit() -> void:
		var ms := {}
		for mode in ["off", "on"]:
			Stasis.set_on(mode == "on")
			await _load(VOID, _void_bot_p2, true)
			await _fight()
			await _frames(30)
			var cc: CritCinematic = null
			var dir_node := m.get_node_or_null("HitFxDirector")
			if dir_node != null:
				for c in dir_node.get_children():
					if c is CritCinematic:
						cc = c
			if cc == null:
				_check("09_crit_" + mode, false, "нет CritCinematic", "HitFxDirector/CritCinematic")
				continue
			var ts0 := Engine.time_scale
			var played := cc.play(_crit_ctx(p2, p1))
			var n := 0
			var loud := 0
			while cc.is_playing() and n < 300:
				await _frame()
				n += 1
				if m.stasis_scale() < 1.0:
					loud += 1
			ms[mode] = {"frames": n, "ms": snappedf(float(cc.played[-1]["ms"]) if not cc.played.is_empty() else -1.0, 0.1),
				"scale_before": snappedf(ts0, 0.0001), "played": played, "stasis_frames_during": loud}
		info["09"] = ms
		if ms.has("off") and ms.has("on"):
			var k := float(ms["on"]["frames"]) / maxf(float(ms["off"]["frames"]), 1.0)
			_check("09_crit_real_time", bool(ms["on"]["played"]) and float(ms["on"]["scale_before"]) < 0.1 and k <= 1.2 and int(ms["on"]["stasis_frames_during"]) == 0,
				snappedf(k, 0.001), "кадров кино вкл / выкл ≤ 1.2 (%d / %d), до кино стоял, во время кино режим молчит" % [ms["on"]["frames"], ms["off"]["frames"]])

	func _crit_ctx(victim: Doll, attacker: Doll) -> Dictionary:
		var body: RigidBody3D = victim.parts.get("Head", victim.torso())
		var dir := body.global_position - attacker.centre_of_mass()
		dir.z = 0.0
		dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.LEFT
		return {
			"victim": victim, "attacker": attacker, "damage": 26.0, "kind": "head", "part": "Head", "part_base": "Head",
			"striker": "Hand_R", "position": body.global_position - dir * 0.1, "normal": -dir, "dir": dir, "speed": 8.0,
			"weapon_id": "", "combo": 1, "double_blow": false, "dash": true, "score": 32.5, "tier": "crit", "is_ko": false,
			"hp_after": victim.hp, "fight_time": m.fight_time, "sd_mult": 1.0, "colour": Color.WHITE,
		}

	# ---------------------------------------------------------------- 10: людей нет / человек в нокауте

	func _s_nohuman() -> void:
		Stasis.set_on(true)
		await _load(VOID, func() -> void:
			_void_bot_p2()
			p1.external_input = true)   # P1 тоже не человек (ввод не читает)
		await _fight()
		var worst := 0.0
		for i in 60:
			await _frame()
			worst = maxf(worst, absf(Engine.time_scale - 1.0))
		_check("10_no_humans", worst == 0.0 and m.stasis_drive < 0.0, worst, "max |time_scale − 1| == 0 за 1 с, людей нет")
		# человек в нокауте (спорт-зал: нокаут матч не кончает, P2 — бот)
		var spans := {}
		for mode in ["off", "on"]:
			Stasis.set_on(mode == "on")
			await _load(SPORT, Callable(), false, 0.2)
			(m as SportMatch).kickoff_s = 0.2
			await _until(func() -> bool: return (m as SportMatch).play_state == "play", 300)
			await _frames(30)
			var frozen := _ts_near(Tuning.STASIS_IDLE_SCALE)
			var me := _sport_doll(0)
			me.knock_out()
			var worst_ko := 0.0
			var n := 0
			await _frame()
			while n < 600:
				var cur := _sport_doll(0)
				if cur != null and cur != me and cur.alive:
					break
				worst_ko = maxf(worst_ko, absf(Engine.time_scale - 1.0))
				await _frame()
				n += 1
			spans[mode] = {"frozen_before": frozen, "respawn_frames": n, "worst_ko": worst_ko}
		info["10_sport_ko"] = spans
		var on: Dictionary = spans["on"]
		_check("10_human_ko", bool(on["frozen_before"]) and float(on["worst_ko"]) == 0.0 and int(on["respawn_frames"]) <= int(spans["off"]["respawn_frames"]) + 2,
			str(on), "до нокаута — IDLE; в нокауте 1.0; возврат не дольше, чем без режима (%d кадров)" % spans["off"]["respawn_frames"])

	func _sport_doll(index: int) -> Doll:
		for d in m.dolls():
			if (d as Doll).player_index == index:
				return d
		return null

	# ---------------------------------------------------------------- 11: двое людей (PvE, кооп)

	func _s_coop() -> void:
		Stasis.set_on(true)
		PvePlayground.coop = true
		await _load(PVE, func() -> void: (m as WaveDirector).auto_waves = false)
		var wd := m as WaveDirector
		wd.begin_manual()
		p1 = pg.get_node_or_null("P1") as Doll
		p2 = pg.get_node_or_null("P2") as Doll
		var two := p1 != null and p2 != null and not p1.external_input and not p2.external_input
		await _frames(30)
		var a_idle := _ts_near(Tuning.STASIS_IDLE_SCALE)
		p1.knock_out()
		await _frames(3)
		var a_ko := Engine.time_scale
		_check("11_p2_not_joined", two and a_idle and a_ko == 1.0 and wd.wave_state == "manual", "стоя %s, P1 в нокауте → %.3f" % [a_idle, a_ko],
			"P2 ни разу не нажимал: не держит время — P1 в нокауте → 1.0")
		_press("p2_left")   # первое нажатие P2: с этого кадра он считается
		await _frames(10)
		_release_all()
		var down := await _until(func() -> bool: return _ts_near(Tuning.STASIS_IDLE_SCALE), 60)
		_press("p2_left")
		var up := await _until(func() -> bool: return Engine.time_scale >= 0.95, 30)
		_release_all()
		await _until(func() -> bool: return _ts_near(Tuning.STASIS_IDLE_SCALE), 60)
		_press("p2_up", 0.5)   # стик наполовину — время ползёт на полпути
		await _frames(30)
		var half := Engine.time_scale
		_release_all()
		_check("11_p2_joined", up <= 6 and down <= 15 and absf(half - Stasis.target(0.5)) < 0.01, "вниз %d, вверх %d кадров; ввод 0.5 → %.3f" % [down, up, half],
			"P2 нажал — теперь он человек: отпустил — IDLE за ≤ 15 кадров (P1 в нокауте), нажал — ≥ 0.95 за ≤ 6; стик 0.5 → %.3f" % Stasis.target(0.5))
		PvePlayground.coop = false

	# ---------------------------------------------------------------- 13: спорт — гол и ввод мяча

	func _s_sport() -> void:
		var spans := {}
		for mode in ["off", "on"]:
			Stasis.set_on(mode == "on")
			await _load(SPORT, Callable(), false, 0.2)
			var sm := m as SportMatch
			sm.kickoff_s = 0.2
			await _until(func() -> bool: return sm.play_state == "play", 300)
			await _frames(30)
			var frozen := _ts_near(Tuning.STASIS_IDLE_SCALE)
			var ball := pg.get_node("Ball") as SportBall
			var r: Dictionary = Tuning.SPORTS["football"]
			var spot := Vector2(float(r["goal_x"]) + 1.0, 1.0)
			ball.freeze = false
			ball.global_transform = Transform3D(Basis.IDENTITY, Vector3(spot.x, spot.y, 0.0))
			ball.linear_velocity = Vector3.ZERO
			ball.untouched_s = 0.0
			sm._ball_prev = spot
			ball.last_touch = _sport_doll(0)
			var g := await _until(func() -> bool: return sm.play_state == "goal", 120)
			var n := await _until(func() -> bool: return sm.play_state == "play", 1200)
			spans[mode] = {"frozen_before": frozen, "goal_after_frames": g, "goal_to_play_frames": n, "score": sm.score.duplicate()}
		info["13"] = spans
		var on: Dictionary = spans["on"]
		_check("13_goal_pause", bool(on["frozen_before"]) and int(on["goal_to_play_frames"]) <= int(spans["off"]["goal_to_play_frames"]) + 1
			and int(on["goal_to_play_frames"]) < 1200, "%d против %d кадров" % [on["goal_to_play_frames"], spans["off"]["goal_to_play_frames"]],
			"пауза после гола и ввод мяча без ввода игрока не длиннее, чем без режима (+1 кадр)")

	# ---------------------------------------------------------------- 14: PvE, волна 1, бот-«человек»

	func _s_pve() -> void:
		var runs := {"off": [], "on": []}
		for i in int(args["trials"]):
			for mode in ["off", "on"]:
				Stasis.set_on(mode == "on")
				var r := await _pve_wave1(i)
				(runs[mode] as Array).append(r)
				print("  pve %s #%d: %s" % [mode, i + 1, str(r)])
		info["14"] = runs
		var game := {"off": [], "on": []}
		var cleared_on := 0
		for mode in ["off", "on"]:
			for r in runs[mode]:
				if bool(r["cleared"]):
					(game[mode] as Array).append(float(r["game_s"]))
					if mode == "on":
						cleared_on += 1
		var med_off := _median(game["off"])
		var med_on := _median(game["on"])
		_check("14_pve_wave1_cleared", cleared_on == (runs["on"] as Array).size() and cleared_on > 0, "%d / %d" % [cleared_on, (runs["on"] as Array).size()],
			"бот-«человек» зачищает волну 1 с режимом в каждом прогоне")
		_check("14_pve_wave1_time", med_off > 0.0 and med_on <= med_off * 1.5, "%.1f с против %.1f с" % [med_on, med_off],
			"игровое время зачистки (медиана) с режимом ≤ 1.5 × без режима")

	func _pve_wave1(i: int) -> Dictionary:
		seed(20261005 + i)
		await _load(PVE, Callable(), false)
		var wd := m as WaveDirector
		p1 = pg.get_node("P1") as Doll
		var hammer := pg.get_node_or_null("Weapons/Hammer") as Weapon
		for c in p1.get_children():
			if c is WeaponPickup and hammer != null:
				(c as WeaponPickup).attach("Hand_R", hammer)
		var st := {"retreat_until": -1.0, "boost": false}
		var t_wave := -1.0
		var f_wave := -1
		var n := 0
		var frozen_frames := 0
		while n < int(WAVE_MAX_S * FPS):
			await _frame()
			n += 1
			if not is_instance_valid(p1) or not p1.alive or wd.result != "":
				break
			if t_wave < 0.0 and wd.wave_state in ["spawning", "fight"]:
				t_wave = wd.run_t
				f_wave = n
			if wd.wave_index == 0 and wd.wave_state == "pause":
				break
			if Engine.time_scale < 0.5:
				frozen_frames += 1
			var think := fmod(float(n) / FPS, THINK_EVERY_S) > THINK_EVERY_S - float(args["think_s"])
			if think:
				_release_all()
			else:
				_rush(p1, _nearest_enemy(wd), st, wd.run_t)
		_release_all()
		var cleared := wd.wave_index == 0 and wd.wave_state == "pause"
		var r := {"cleared": cleared, "game_s": snappedf(wd.run_t - t_wave, 0.1) if t_wave >= 0.0 else -1.0,
			"real_s": snappedf(float(n - f_wave) / FPS, 0.1) if f_wave >= 0 else -1.0, "frozen_share": snappedf(float(frozen_frames) / maxf(float(n), 1.0), 0.01),
			"p1_hp": snappedf(p1.hp, 0.1) if is_instance_valid(p1) else -1.0, "state": wd.wave_state}
		await _unload()
		return r

	func _nearest_enemy(wd: WaveDirector) -> Doll:
		var best: Doll = null
		var best_d := INF
		for e in wd.alive_enemies():
			var dd := (e as Doll).centre_of_mass().distance_to(p1.centre_of_mass())
			if dd < best_d:
				best_d = dd
				best = e
		return best

	## Наскок как pve_probe._bot_rush, но клавишами p1_* (человек): разбег → отход 0.9 с → разбег, ускорение издалека.
	func _rush(d: Doll, target: Doll, st: Dictionary, t: float) -> void:
		if target == null:
			# врагов ещё нет (желоб предупреждает): человек в этом режиме не стоит столбом — покачивается, и время идёт
			_release_all()
			_press("p1_up", 0.6)
			return
		var dc := d.centre_of_mass()
		var oc := target.centre_of_mass()
		var dx := oc.x - dc.x
		var dy := oc.y - dc.y
		var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
		var vy := clampf(dy / 1.2, -1.0, 1.0) if absf(dy) > 0.5 else 0.0
		var v := Vector2(sgn, vy)
		var boost := false
		if t < float(st["retreat_until"]):
			v = Vector2(-sgn, 0.3)
		elif absf(dx) < 1.2 and absf(dy) < 1.2:
			st["retreat_until"] = t + 0.9
			v = Vector2(-sgn, 0.3)
		else:
			boost = Vector2(dx, dy).length() > 2.5 and (d.charge >= 90.0 or (bool(st["boost"]) and d.charge > 5.0))
		st["boost"] = boost
		_press("p1_right", maxf(v.x, 0.0))
		_press("p1_left", maxf(-v.x, 0.0))
		_press("p1_up", maxf(v.y, 0.0))
		_press("p1_down", maxf(-v.y, 0.0))
		_press("p1_dash", 1.0 if boost else 0.0)

	static func _median(a: Array) -> float:
		if a.is_empty():
			return -1.0
		var s := a.duplicate()
		s.sort()
		var k := s.size() / 2
		return float(s[k]) if s.size() % 2 == 1 else 0.5 * (float(s[k - 1]) + float(s[k]))

	# ---------------------------------------------------------------- режим «СТАЗИС» отдельным пунктом ВСЕ РЕЖИМЫ

	## playground_stasis.tscn: режим включён, пока площадка в дереве; волна ждёт игрока; уходя — Stasis.on как до входа.
	func _s_mode() -> void:
		for before in [false, true]:
			Stasis.set_on(before)
			await _load(STASIS_PG)
			var wd := m as WaveDirector
			var on_inside := Stasis.on
			await _until(func() -> bool: return wd.wave_state == "spawning" or wd.wave_state == "fight", 6 * 60)
			await _frames(30)
			var frozen := _ts_near(Tuning.STASIS_IDLE_SCALE)
			var t0 := wd.wave_t
			await _frames(60)
			var crawl := wd.wave_t - t0
			await _unload()
			_check("mode_scene_%s" % ("on_before" if before else "off_before"), on_inside and frozen and absf(crawl - Tuning.STASIS_IDLE_SCALE) < 0.01
				and Stasis.on == before and Engine.time_scale == 1.0,
				"внутри вкл %s, стоит %s, волна за 1 с — %.3f с; после выхода Stasis.on %s, масштаб %.2f" % [on_inside, frozen, crawl, Stasis.on, Engine.time_scale],
				"внутри режим вкл и волна ждёт игрока (≈ %.2f с за секунду), после выхода — как до входа (%s), 1.0" % [Tuning.STASIS_IDLE_SCALE, before])
		Stasis.set_on(false)

	# ---------------------------------------------------------------- 12: пауза, R, смена арены, в гараж — настоящими клавишами

	func _s_scenes() -> void:
		Stasis.set_on(true)
		get_tree().change_scene_to_file(VOID)
		await _wait_scene(VOID)
		m = get_tree().current_scene.get_node("Match") as Match
		await _until(func() -> bool: return m.combat_active(), 8 * 60)
		await _frames(30)
		var frozen := _ts_near(Tuning.STASIS_IDLE_SCALE)
		var flow := get_node("/root/Flow")
		await _key(KEY_ESCAPE)
		await _frames(8)
		var paused: bool = flow.is_paused() and get_tree().paused
		var ts_pause := Engine.time_scale
		var buttons: Array = flow.find_children("*", "Button", true, false)
		var f0: Control = get_viewport().gui_get_focus_owner()
		var down := InputEventAction.new()
		down.action = "ui_down"
		down.pressed = true
		Input.parse_input_event(down)
		await _frames(3)
		var f1: Control = get_viewport().gui_get_focus_owner()
		var menu_alive := buttons.size() >= 2 and f0 != null and f1 != null and f0 != f1
		await _key(KEY_ESCAPE)
		await _frames(2)
		var ts_back := Engine.time_scale
		await _frames(20)
		var still := _ts_near(Tuning.STASIS_IDLE_SCALE)
		_check("12_pause", frozen and paused and ts_pause == 1.0 and menu_alive and not get_tree().paused and absf(ts_back - Tuning.STASIS_IDLE_SCALE) < 0.01 and still,
			"пауза %s, масштаб %.3f, меню живое %s, после %.3f" % [paused, ts_pause, menu_alive, ts_back],
			"до — IDLE; на паузе 1.0 и фокус ходит по меню; после — снова IDLE")
		# R посреди замирания
		await _key(KEY_R)
		var ts_r := Engine.time_scale
		var cd := m.phase == Match.Phase.COUNTDOWN
		_check("12_restart_r", ts_r == 1.0 and cd, "%.3f, отсчёт %s" % [ts_r, cd], "R посреди замирания → 1.0 и отсчёт")
		await _until(func() -> bool: return m.combat_active(), 8 * 60)
		await _frames(30)
		frozen = _ts_near(Tuning.STASIS_IDLE_SCALE)
		# смена арены «2» посреди замирания
		await _key(KEY_2)
		var load_ok := await _wait_scene(WORKSHOP, 30.0)
		var ts_arena := Engine.time_scale
		_check("12_arena_switch", frozen and load_ok and ts_arena == 1.0, "%.3f, загружена %s" % [ts_arena, load_ok], "клавиша 2 посреди замирания → 1.0 в новой сцене")
		m = get_tree().current_scene.get_node("Match") as Match
		await _until(func() -> bool: return m.combat_active() and not Loading.showing, 10 * 60)
		await _frames(30)
		frozen = _ts_near(Tuning.STASIS_IDLE_SCALE)
		info["12_workshop_before_garage"] = {"phase": m.phase, "loader": Loading.showing, "ts": Engine.time_scale, "drive": m.stasis_drive,
			"stasis_scale": m.stasis_scale()}
		# в гараж из паузы посреди замирания
		await _key(KEY_ESCAPE)
		await _frames(8)
		var to_garage: Button = null
		for b in flow.find_children("*", "Button", true, false):
			if (b as Button).text == tr("В ГАРАЖ"):
				to_garage = b
		var found := to_garage != null   # до нажатия: кнопка освобождается вместе с паузой
		if found:
			to_garage.pressed.emit()
		var garage := await _wait_scene(MENU, 60.0)
		_check("12_to_garage", frozen and found and garage and Engine.time_scale == 1.0 and not get_tree().paused,
			"%.3f, гараж %s, до — IDLE %s, кнопка %s, пауза %s" % [Engine.time_scale, garage, frozen, found, get_tree().paused],
			"«В ГАРАЖ» посреди замирания → 1.0, пауза снята")

	func _scene() -> String:
		var s := get_tree().current_scene
		return s.scene_file_path if s != null else ""

	func _wait_scene(path: String, timeout := 15.0) -> bool:
		var n := 0
		while _scene() != path and n < int(timeout * FPS):
			await _frame()
			n += 1
		await _frames(5)
		return _scene() == path
