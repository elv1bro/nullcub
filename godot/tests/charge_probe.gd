## Проба Заряда (docs/plan-demo/COMBAT_CHARGE.md, 02.10): формулы начисления, экономика (расход на ускорение, пауза и накопление,
## выдохся и перевзвод, перезаряд и его таяние, стан, принудительный рывок проб), раскрутка (направление, предел ω, цена, без ввода
## не платит), применение удара Charge.apply_hit (DOUBLE BLOW / окружение / своя команда не считаются, жертва ≤ CHARGE_MAX) и
## «ветряная мельница» — сколько урона даёт соседу куклу с раскруткой против той же куклы без неё (бой через настоящий Match).
## Headless:
##   godot --headless --path . --fixed-fps 60 res://tests/charge_probe.tscn   → код выхода 0/1
extends Node3D

const DollScene := preload("res://scenes/doll/doll.tscn")
const TICK := 1.0 / 60.0

var ok := true
var checks: Array = []
var _world: Node3D


func _check(id: String, cond: bool, detail: String) -> void:
	checks.append({"id": id, "ok": cond})
	if not cond:
		ok = false
	print("  %-28s %s  %s" % [id, "ok  " if cond else "FAIL", detail])


func _near(id: String, value: float, target: float, tol: float, detail: String) -> void:
	_check(id, absf(value - target) <= tol, "%s: %.2f (ожидалось %.2f ± %.2f)" % [detail, value, target, tol])


func _range(id: String, value: float, lo: float, hi: float, detail: String) -> void:
	_check(id, value >= lo and value <= hi, "%s: %.2f (в [%.2f, %.2f])" % [detail, value, lo, hi])


func _new_world() -> void:
	if _world != null:
		remove_child(_world)
		_world.queue_free()
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 4)
	cs.shape = box
	floor_body.add_child(cs)
	_world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)


func _spawn(x: float, y: float = 0.0) -> Doll:
	var d := DollScene.instantiate() as Doll
	d.external_input = true
	_world.add_child(d)
	d.global_position = Vector3(x, y, 0)
	return d


## n тиков физики; boost / spin — просить ускорение / раскрутку каждый тик (как зажатая клавиша), vx — ввод по X.
func _ticks(d: Doll, n: int, boost: bool = false, spin: bool = false, vx: float = 0.0, vy: float = 0.0) -> void:
	d.input_vec = Vector2(vx, vy)
	for i in range(n):
		if boost:
			d.request_dash()
		if spin:
			d.request_spin()
		await get_tree().physics_frame


func _secs(s: float) -> int:
	return int(round(s / TICK))


func _ready() -> void:
	print("=== CHARGE PROBE ===")
	_formulas()
	await _economy()
	await _spin()
	_apply_hit()
	var ww := await _windmill(false)
	var ws := await _windmill(true)
	print("  windmill  без раскрутки: урон соседу %.1f HP, заряд атакующему %.1f" % [ww["damage"], ww["charge_hits"]])
	print("  windmill  с раскруткой:  урон соседу %.1f HP, заряд атакующему %.1f, потрачено %.1f, ω max %.2f рад/с" % [ws["damage"], ws["charge_hits"], ws["spent"], ws["w_max"]])
	_range("windmill_not_dominant", ws["damage"], 0.0, 35.0, "урон раскрутки за 2.5 с не убивает 100 HP")
	_check("windmill_spin_paid", float(ws["spent"]) > 20.0, "раскрутка платила Заряд (%.1f)" % float(ws["spent"]))
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


# --- формулы ---

func _formulas() -> void:
	print("-- формулы")
	var k := Tuning.CHARGE_PER_DAMAGE
	_near("gain_light", Charge.hit_gain(12.0, 1, "light"), 12.0 * k, 0.01, "12 HP, комбо 1")
	_near("gain_combo3", Charge.hit_gain(16.0, 3, "heavy"), 16.0 * k * 1.5, 0.01, "16 HP, комбо 3 (×1.5)")
	_near("gain_series", Charge.hit_gain(12.0, 1) + Charge.hit_gain(14.0, 2) + Charge.hit_gain(16.0, 3), k * (12.0 + 14.0 * 1.25 + 16.0 * 1.5), 0.05, "серия 12/14/16 HP")
	_near("gain_crit", Charge.hit_gain(35.0, 3, "crit"), 35.0 * k * 1.5 + Tuning.CHARGE_CRIT_BONUS, 0.01, "крит 35 HP, комбо 3")
	_near("gain_ko", Charge.hit_gain(20.0, 1, "ko"), 20.0 * k + Tuning.CHARGE_KO_BONUS, 0.01, "KO 20 HP")
	_near("gain_ko_crit", Charge.hit_gain(30.0, 1, "ko_crit"), 30.0 * k + Tuning.CHARGE_CRIT_BONUS + Tuning.CHARGE_KO_BONUS, 0.01, "ko_crit 30 HP")
	_near("gain_below_min", Charge.hit_gain(4.9, 3, "heavy"), 0.0, 0.0001, "слабее порога — 0")
	_near("gain_combo_cap", Charge.hit_gain(10.0, 9), Charge.hit_gain(10.0, Tuning.CHARGE_COMBO_MAX_N), 0.0001, "комбо выше потолка = потолок")
	_near("gain_victim", Charge.victim_gain(30.0), 30.0 * Tuning.CHARGE_VICTIM_SHARE, 0.0001, "жертве доля от 30 HP")
	_near("gain_victim_min", Charge.victim_gain(3.0), 0.0, 0.0001, "жертве слабее порога — 0")


# --- экономика ---

func _economy() -> void:
	print("-- экономика")
	_new_world()
	var d := _spawn(0.0, 1.0)
	_check("start_full", is_equal_approx(d.charge, Tuning.CHARGE_MAX) and not d.charge_locked, "полный бак на старте (%.1f)" % d.charge)
	await _ticks(d, _secs(0.3))
	_near("idle_no_change", d.charge, 100.0, 0.001, "без трат заряд полный")

	# ускорение: расход 35/с
	await _ticks(d, _secs(1.0), true)
	_check("boost_on", d.is_dashing(), "ускорение включено, пока просят")
	_near("boost_drain_1s", d.charge, 100.0 - Tuning.CHARGE_DRAIN_PER_S, 1.5, "после 1.0 с ускорения")
	var c_after := d.charge
	await _ticks(d, _secs(0.5))
	_check("boost_off", not d.is_dashing(), "перестали просить — ускорение выключено")
	_near("regen_pause", d.charge, c_after, 0.3, "пауза накопления 0.6 с (через 0.5 с без изменений)")
	await _ticks(d, _secs(1.5))
	_near("regen_after_pause", d.charge, c_after + Tuning.CHARGE_REGEN_PER_S * (2.0 - Tuning.CHARGE_REGEN_PAUSE_S), 1.5, "через 2.0 с после отпускания")
	await _ticks(d, _secs(6.0))
	_near("regen_cap", d.charge, 100.0, 0.001, "накопление не выше CHARGE_MAX")

	# выдохся
	d.reset_charge()
	var t_empty := 0.0
	var n := 0
	while not d.charge_locked and n < _secs(6.0):
		await _ticks(d, 1, true)
		n += 1
	t_empty = float(n) * TICK
	_near("exhaust_time", t_empty, Tuning.CHARGE_MAX / Tuning.CHARGE_DRAIN_PER_S, 0.1, "полный бак до нуля, с")
	_check("exhaust_locked", d.charge_locked and d.charge <= 0.001, "выдохся: запор, заряд 0")
	await _ticks(d, 3, true)
	_check("exhaust_no_boost", not d.is_dashing(), "в запоре ускорения нет")
	_check("exhaust_stat", int(d.stats["charge_empty"]) == 1, "stats.charge_empty = %d" % int(d.stats["charge_empty"]))
	# Shift всё ещё зажат: после возврата до CHARGE_RESTART ускорение само не включается (перевзвод)
	await _ticks(d, _secs(5.0), true)
	_check("restart_reached", d.charge >= Tuning.CHARGE_RESTART and not d.charge_locked, "запор снят при заряде %.1f ≥ %.0f" % [d.charge, Tuning.CHARGE_RESTART])
	_check("rearm_needs_release", not d.is_dashing(), "Shift не отпускали — ускорение не мерцает")
	await _ticks(d, 3)
	await _ticks(d, 2, true)
	_check("rearm_after_release", d.is_dashing(), "отпустили и нажали снова — ускорение есть")

	# принудительный рывок проб и отмена
	d.reset_charge()
	d.dash_until = d._time + 1.0
	await _ticks(d, _secs(0.5))
	_check("forced_dash", d.is_dashing(), "dash_until: рывок пробы без траты")
	_near("forced_free", d.charge, 100.0, 0.001, "принудительный рывок заряд не тратит")
	d.cancel_boost()
	_check("cancel_boost", not d.is_dashing(), "cancel_boost снимает рывок")

	# стан
	d.reset_charge()
	d.stun(1.0)
	await _ticks(d, _secs(0.4), true)
	_check("stun_blocks", not d.is_dashing(), "в стане ускорения нет")
	_near("stun_free", d.charge, 100.0, 0.001, "в стане заряд не тратится")
	await _ticks(d, _secs(1.5))

	# перезаряд
	d.reset_charge()
	var added := d.add_charge(40.0, true)
	_near("over_added", added, 40.0, 0.001, "перезаряд +40 за удар (до 140)")
	_near("over_value", d.charge, 140.0, 0.001, "заряд 140")
	await _ticks(d, _secs(1.0))
	_near("over_held", d.charge, 140.0, 0.01, "серия идёт (≤ 1.5 с) — перезаряд не тает")
	await _ticks(d, _secs(2.0))
	_near("over_decay", d.charge, 140.0 - Tuning.CHARGE_OVER_DECAY_PER_S * (3.0 - Tuning.CHARGE_OVER_HOLD_S), 1.5, "через 3.0 с после удара")
	d.reset_charge()
	d.add_charge(80.0, true)
	_near("over_cap", d.charge, Tuning.CHARGE_OVER_MAX, 0.001, "потолок перезаряда")
	d.charge = 60.0
	_near("victim_cap_add", d.add_charge(60.0, false), 40.0, 0.001, "жертве не выше CHARGE_MAX")
	d.charge = 120.0
	_near("victim_no_over", d.add_charge(30.0, false), 0.0, 0.001, "жертве выше сотни не набрать, перезаряд не трогаем")
	_near("victim_over_kept", d.charge, 120.0, 0.001, "перезаряд остался")

	# reset_for_match
	d.charge = 5.0
	d.charge_locked = true
	d.reset_for_match()
	_check("reset_for_match", is_equal_approx(d.charge, 100.0) and not d.charge_locked, "полный бак после reset_for_match")


# --- раскрутка ---

func _spin() -> void:
	print("-- раскрутка")
	_new_world()
	var d := _spawn(0.0, 5.0)
	await _ticks(d, _secs(0.5))
	var w0 := d.torso().angular_velocity.z
	await _ticks(d, _secs(0.8), false, true, 1.0)
	var w_right := d.torso().angular_velocity.z
	_check("spin_active", d.is_spinning(), "раскрутка включена (Space + ввод)")
	_check("spin_dir_right", w_right < w0 - 3.0, "ввод вправо — по часовой: ω %.2f → %.2f рад/с" % [w0, w_right])
	_range("spin_w_cap", absf(w_right), 3.5, Tuning.SPIN_MAX_W * 1.35, "ω не выше предела (%.1f рад/с)" % Tuning.SPIN_MAX_W)
	_near("spin_cost", d.charge, 100.0 - Tuning.CHARGE_SPIN_DRAIN_PER_S * 0.8, 2.5, "заряд после 0.8 с раскрутки")
	var c1 := d.charge
	await _ticks(d, _secs(1.5), false, true, -1.0)
	var w_left := d.torso().angular_velocity.z
	_check("spin_dir_left", w_left > 1.0, "ввод влево — против часовой: ω %.2f рад/с" % w_left)
	var c2 := d.charge
	_check("spin_cost_left", c2 < c1 - 10.0, "заряд %.1f → %.1f" % [c1, c2])
	# без ввода X раскрутки нет и заряд не тратится
	d.reset_charge()
	await _ticks(d, _secs(0.5), false, true, 0.0)
	_check("spin_needs_dir", not d.is_spinning(), "Space без A/D раскрутки не включает")
	_near("spin_free_idle", d.charge, 100.0, 0.001, "Space без A/D заряд не тратит")
	# после отпускания: сколько вертится (справочно)
	await _ticks(d, _secs(0.6), false, true, 1.0)
	var w_rel := absf(d.torso().angular_velocity.z)
	await _ticks(d, _secs(1.0))
	var w_1s := absf(d.torso().angular_velocity.z)
	print("  spin_release_info          ω при отпускании %.2f → через 1 с %.2f рад/с" % [w_rel, w_1s])
	# ускорение и раскрутка вместе платят суммой
	d.reset_charge()
	await _ticks(d, _secs(0.5), true, true, 1.0)
	_near("spin_boost_sum", d.charge, 100.0 - (Tuning.CHARGE_DRAIN_PER_S + Tuning.CHARGE_SPIN_DRAIN_PER_S) * 0.5, 2.5, "ускорение + раскрутка 0.5 с")
	# разовый импульс переворота остался хуком
	d.reset_charge()
	await _ticks(d, _secs(0.4))
	var wb := d.torso().angular_velocity.z
	d.input_vec = Vector2(1, 0)
	d.request_flip()
	await _ticks(d, 2, false, false, 1.0)
	_check("flip_hook", absf(d.torso().angular_velocity.z - wb) > 1.0, "request_flip: ω %.2f → %.2f" % [wb, d.torso().angular_velocity.z])


# --- применение удара ---

func _apply_hit() -> void:
	print("-- удар")
	_new_world()
	var a := _spawn(-2.0, 1.0)
	var b := _spawn(2.0, 1.0)
	var ctx := {"attacker": a, "victim": b, "damage": 14.0, "combo": 2, "tier": "heavy", "kind": "body", "double_blow": false}
	a.charge = 50.0
	b.charge = 50.0
	var got := Charge.apply_hit(ctx)
	_near("hit_attacker", a.charge, 50.0 + Charge.hit_gain(14.0, 2, "heavy"), 0.01, "атакующий получил за удар")
	_near("hit_victim", b.charge, 50.0 + Charge.victim_gain(14.0), 0.01, "жертва получила долю урона")
	_check("hit_returns", is_equal_approx(float(got[0]), Charge.hit_gain(14.0, 2, "heavy")), "apply_hit вернул начисленное")
	var dbl := ctx.duplicate()
	dbl["double_blow"] = true
	a.charge = 50.0
	Charge.apply_hit(dbl)
	_near("hit_double_blow", a.charge, 50.0, 0.0001, "DOUBLE BLOW заряд не даёт")
	var env := ctx.duplicate()
	env["kind"] = "environment"
	Charge.apply_hit(env)
	env["kind"] = "self"
	Charge.apply_hit(env)
	_near("hit_env_self", a.charge, 50.0, 0.0001, "окружение и «себе» заряд не дают")
	a.team = "enemy"
	b.team = "enemy"
	Charge.apply_hit(ctx)
	_near("hit_same_team", a.charge, 50.0, 0.0001, "своя команда заряд не даёт")
	a.team = ""
	b.team = ""
	var weak := ctx.duplicate()
	weak["damage"] = 4.0
	Charge.apply_hit(weak)
	_near("hit_weak", a.charge, 50.0, 0.0001, "слабее 5 HP заряд не даёт")
	a.charge = 100.0
	b.charge = 100.0
	var big := ctx.duplicate()
	big["damage"] = 40.0
	big["tier"] = "crit"
	Charge.apply_hit(big)
	_range("hit_attacker_over", a.charge, 101.0, Tuning.CHARGE_OVER_MAX, "атакующий уходит в перезаряд")
	_near("hit_victim_capped", b.charge, 100.0, 0.0001, "жертва не выше CHARGE_MAX")
	var dead := _spawn(6.0, 1.0)
	dead.alive = false
	dead.charge = 10.0
	var kctx := ctx.duplicate()
	kctx["victim"] = dead
	Charge.apply_hit(kctx)
	_near("hit_dead_victim", dead.charge, 10.0, 0.0001, "мёртвой жертве заряд не идёт")


# --- «ветряная мельница»: урон раскрутки через настоящий Match ---

func _windmill(spin: bool) -> Dictionary:
	_new_world()
	var a := _spawn(-1.8, 1.0)
	var b := _spawn(0.0, 0.0)
	a.player_index = 0
	b.player_index = 1
	a.add_to_group("dolls")
	b.add_to_group("dolls")
	var m := Match.new()
	m.name = "Match"
	m.countdown_s = 0.0
	m.time_limit_s = 90.0
	m.feel_enabled = false
	_world.add_child(m)
	await _ticks(a, _secs(1.2))   # куклы встали, FIGHT
	var w_max := 0.0
	var spent0 := float(a.stats["charge_spent"])
	for i in range(_secs(2.5)):
		a.input_vec = Vector2(1.0, 0.2)
		if spin:
			a.request_spin()
		await get_tree().physics_frame
		w_max = maxf(w_max, absf(a.torso().angular_velocity.z))
	var out := {
		"damage": float(b.stats["damage_taken"]), "charge_hits": float(a.stats["charge_from_hits"]),
		"spent": float(a.stats["charge_spent"]) - spent0, "w_max": w_max,
	}
	return out
