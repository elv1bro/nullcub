## Формула урона (CONCEPT.md §8, план 06 «HP и формула урона») — чистые статические функции без сцены.
##
##   Damage = m_eff × max(0, v_rel_normal − MIN_IMPACT_SPEED) × DAMAGE_COEF × BodyMult × TargetMult × WeaponMult × combo × sd
##
## m_eff — масса бьющего тела: часть куклы — min(масса, MASS_CAP) (торс 12 кг не давит массой; при ударе об статику — вся кукла,
## кап тот же); оружие (Weapon: стандартное, крафтовое, звено кистеня; брошенный пропс ThrownCredit) — weapon_mass(масса): без
## MASS_CAP до WEAPON_MASS_SOFT_CAP, выше рост по корню (потолок массы 29.09: тяжелее головка — сильнее удар). Чтобы стандартное
## оружие било как прежде, кап 4 кг перенесён в его множитель: молот 6 кг — damage_mult 1.2 × 4/6 = 0.8 (Tuning.WEAPON).
## BodyMult — Tuning.BODY_MULT бьющей части (оружие 1.0); TargetMult — Tuning.HEAD_HIT_MULT, если бьют в голову; WeaponMult — Tuning.WEAPON[id].damage_mult;
## combo — combo_mult(n) = 1 + COMBO_STEP·min(n, COMBO_MAX_N); sd — всегда 1.0 (Sudden Death не растит урон, §12). Итог клэмпится DAMAGE_MAX.
## Скорость удара (DollCombat): v = min(скорость сближения по нормали, max собственных скоростей тел по нормали) — формула
## калибрована на удар по стоящей цели; встречный разбег 9 + 9 м/с считается как удар 9, а не 18 (иначе каждый обычный клинч
## давал капнутые 60 HP). Голова о голову (RM) бьёт обоих той же v без TargetMult.
## Окружение (В6): Damage = min(mass, MASS_CAP) × max(0, v − ENV_MIN_IMPACT_SPEED) × DAMAGE_COEF × ENV_DAMAGE_MULT × TargetMult.
## С 28.09 выключено (Tuning.ENV_DAMAGE_ENABLED = false, решение автора; RM_MECHANICS.md §7: пол и стены — упругие ограничители):
## compute_env = 0, строки «(окруж.)» таблицы ниже проверяются как 0, а env_formula (то, что было бы при включении) — в своей полосе.
##
## Калибровочная таблица при DAMAGE_COEF 0.95, MIN_IMPACT_SPEED 1.5, MASS_CAP 4 (тело), WEAPON_MASS_SOFT_CAP 10 (полосы концепта: касание 1–3, конечность 8–15,
## оружие 20–30, экстрим 30–50; печатает print_calibration_table(), проверяет tests/combat_gate.gd):
##
##   | Контакт                          | Расчёт                          | HP   | Полоса |
##   |----------------------------------|---------------------------------|------|--------|
##   | торс о торс, 3 м/с               | 4 × 1.5 × 0.5 × 0.95            |  2.9 | 1–3    |
##   | кисть в торс, 10 м/с             | 0.5 × 8.5 × 2.0 × 0.95          |  8.1 | 8–15   |
##   | предплечье в торс, 11 м/с        | 1.5 × 9.5 × 1.0 × 0.95          | 13.5 | 8–15   |
##   | стопа, 9 м/с                     | 1.0 × 7.5 × 1.2 × 0.95          |  8.6 | 8–15   |
##   | голень, 8 м/с                    | 3.0 × 6.5 × 0.7 × 0.95          | 13.0 | 8–15   |
##   | голова в торс, 6 м/с             | 4 × 4.5 × 0.35 × 0.95           |  6.0 | 4–15   |
##   | торс о торс, встречные 9 + 9     | 4 × 7.5 × 0.5 × 0.95 (v = 9)    | 14.3 | 8–15   |
##   | голова о голову, встречные 9 + 9 | 4 × 7.5 × 0.35 × 0.95 обоим     | 10.0 | 8–15   |
##   | молот 6 кг ×0.8, 8 м/с           | 6 × 6.5 × 0.8 × 0.95            | 29.6 | 20–30  |
##   | сковородка 2 кг ×1.5, 10 м/с     | 2 × 8.5 × 1.5 × 0.95            | 24.2 | 20–30  |
##   | меч 1.5 кг ×1.6, 12 м/с          | 1.5 × 10.5 × 1.6 × 0.95         | 23.9 | 20–30  |
##   | молот в голову, 8 м/с            | 6 × 6.5 × 0.8 × 1.5 × 0.95      | 44.5 | 30–50  |
##   | торс в голову, 15 м/с            | 4 × 13.5 × 0.5 × 1.5 × 0.95     | 38.5 | 30–50  |
##   | голова в стену, 15 м/с (окруж.)  | 4 × 9 × 0.5 × 1.5 × 0.95        | 25.7 | 15–40  |  (выкл.: 0)
##   | торс в стену, 15 м/с (окруж.)    | 4 × 9 × 0.5 × 0.95              | 17.1 | 15–40  |  (выкл.: 0)
##   | падение с 3 м при g 2 (v ≈ 3.5)  | ниже порога 6                   |  0   | 0      |
##   | крафт: молот 4.1 кг ×1.0, 8 м/с  | 4.1 × 6.5 × 0.95                | 25.3 | 20–30  |
##   | крафт: тяжёлый молот 5.6 кг, 8   | 5.6 × 6.5 × 0.95 (раньше кап 4) | 34.6 | 25–40  |
##   | хлам 30 кг, касание 3 м/с        | 10·√3 = 17.3 × 1.5 × 0.95       | 24.7 | 15–30  |
class_name Damage
extends RefCounted

## Метка «бьющее тело — оружие» в столбце BodyMult строки калибровки (масса без MASS_CAP, weapon_mass).
const WEAPON_ROW := "Weapon"

## Строки калибровки: [подпись, масса, скорость, BodyMult, TargetMult, WeaponMult, окружение?, полоса min, полоса max].
const CALIBRATION := [
	["torso_torso_3", 12.0, 3.0, "Torso", 1.0, 1.0, false, 1.0, 3.0],
	["hand_torso_10", 0.5, 10.0, "Hand", 1.0, 1.0, false, 8.0, 15.0],
	["lowerarm_torso_11", 1.5, 11.0, "LowerArm", 1.0, 1.0, false, 8.0, 15.0],
	["foot_9", 1.0, 9.0, "Foot", 1.0, 1.0, false, 8.0, 15.0],
	["lowerleg_8", 3.0, 8.0, "LowerLeg", 1.0, 1.0, false, 8.0, 15.0],
	["head_torso_6", 4.0, 6.0, "Head", 1.0, 1.0, false, 4.0, 15.0],
	["torso_torso_9_9", 12.0, 9.0, "Torso", 1.0, 1.0, false, 8.0, 15.0],
	["head_head_9_9", 4.0, 9.0, "Head", 1.0, 1.0, false, 8.0, 15.0],
	["hammer_8", 6.0, 8.0, WEAPON_ROW, 1.0, 0.8, false, 20.0, 30.0],        # Tuning.WEAPON.hammer: 1.2 × 4/6
	["pan_10", 2.0, 10.0, WEAPON_ROW, 1.0, 1.5, false, 20.0, 30.0],
	["sword_12", 1.5, 12.0, WEAPON_ROW, 1.0, 1.6, false, 20.0, 30.0],
	["hammer_head_8", 6.0, 8.0, WEAPON_ROW, 1.5, 0.8, false, 30.0, 50.0],
	["torso_head_15", 12.0, 15.0, "Torso", 1.5, 1.0, false, 30.0, 50.0],
	["head_wall_15", 39.0, 15.0, "", 1.5, 1.0, true, 15.0, 40.0],
	["torso_wall_15", 39.0, 15.0, "", 1.0, 1.0, true, 15.0, 40.0],
	["fall_3m_g2", 39.0, 3.5, "", 1.0, 1.0, true, 0.0, 0.0],
	# потолок массы 29.09: крафтовое оружие (data/body/weapons, damage_mult 1.0) — тяжелее головка, сильнее удар при той же скорости
	["craft_hammer_8", 4.1, 8.0, WEAPON_ROW, 1.0, 1.0, false, 20.0, 30.0],
	["craft_heavy_hammer_8", 5.6, 8.0, WEAPON_ROW, 1.0, 1.0, false, 25.0, 40.0],
	["junk_30kg_touch_3", 30.0, 3.0, WEAPON_ROW, 1.0, 1.0, false, 15.0, 30.0],   # мягкий потолок: не убивает с касания
]


## Урон удара тела массой mass_kg с относительной скоростью по нормали rel_speed_normal (м/с).
## is_weapon — бьёт оружие (Weapon, брошенный пропс): масса weapon_mass без MASS_CAP; иначе (часть куклы) min(масса, MASS_CAP).
static func compute(mass_kg: float, rel_speed_normal: float, body_mult: float, weapon_mult: float = 1.0, combo_mult: float = 1.0, sd_mult: float = 1.0, target_mult: float = 1.0, is_weapon: bool = false) -> float:
	var v := maxf(0.0, rel_speed_normal - Tuning.MIN_IMPACT_SPEED)
	var m := effective_mass(mass_kg, is_weapon)
	var d := m * v * Tuning.DAMAGE_COEF * body_mult * target_mult * weapon_mult * combo_mult * sd_mult
	return clampf(d, 0.0, Tuning.DAMAGE_MAX)


## Масса в формуле урона: оружие — weapon_mass, часть тела — min(масса, MASS_CAP).
static func effective_mass(mass_kg: float, is_weapon: bool) -> float:
	var m := maxf(mass_kg, 0.0)
	return weapon_mass(m) if is_weapon else minf(m, Tuning.MASS_CAP)


## Масса оружия в формуле урона (потолок массы 29.09): до WEAPON_MASS_SOFT_CAP как есть, выше — рост по корню
## S·√(m/S) (непрерывно в S): 30-кг хлам считается как 17.3 кг и не убивает с касания, 6.5-кг крафт — как 6.5 кг.
static func weapon_mass(mass_kg: float) -> float:
	var m := maxf(mass_kg, 0.0)
	var s := Tuning.WEAPON_MASS_SOFT_CAP
	if m <= s or s <= 0.0:
		return m
	return s * sqrt(m / s)


## Урон от статики/пропса (В6): порог ENV_MIN_IMPACT_SPEED и множитель ENV_DAMAGE_MULT; mass_kg — кукла (статика) или пропс.
## 0, пока Tuning.ENV_DAMAGE_ENABLED = false (решение автора 28.09).
static func compute_env(mass_kg: float, rel_speed_normal: float, target_mult: float = 1.0) -> float:
	if not Tuning.ENV_DAMAGE_ENABLED:
		return 0.0
	return env_formula(mass_kg, rel_speed_normal, target_mult)


## Формула урона от окружения без флага — для калибровки на случай, если автор включит ENV_DAMAGE_ENABLED обратно.
static func env_formula(mass_kg: float, rel_speed_normal: float, target_mult: float = 1.0) -> float:
	var v := maxf(0.0, rel_speed_normal - Tuning.ENV_MIN_IMPACT_SPEED)
	var m := minf(maxf(mass_kg, 0.0), Tuning.MASS_CAP)
	return clampf(m * v * Tuning.DAMAGE_COEF * Tuning.ENV_DAMAGE_MULT * target_mult, 0.0, Tuning.DAMAGE_MAX)


## Множитель части тела по имени узла ("Hand_L" → "Hand"); оружие и неизвестное — 1.0.
static func body_mult_of(part_name: String) -> float:
	var base := part_name
	var us := base.rfind("_")
	if us > 0 and base.length() - us <= 2:
		base = base.substr(0, us)
	return float(Tuning.BODY_MULT.get(base, 1.0))


## Множитель бьющей части по самому телу: meta "body_mult" детали (ModularDoll, кит тела v2: шипастый декор, железо сильнее
## дерева) важнее таблицы по имени; без meta — body_mult_of(имя), как раньше (у doll.tscn meta нет, числа human не меняются).
static func body_mult_of_body(b: Node) -> float:
	if b == null:
		return 1.0
	if b.has_meta("body_mult"):
		return float(b.get_meta("body_mult"))
	return body_mult_of(String(b.name))


static func target_mult_of(part_name: String) -> float:
	return Tuning.HEAD_HIT_MULT if part_name.begins_with("Head") else 1.0


## Множитель комбо по числу предыдущих ударов атакующего в окне COMBO_WINDOW_S.
static func combo_mult(n: int) -> float:
	return 1.0 + Tuning.COMBO_STEP * float(mini(maxi(n, 0), Tuning.COMBO_MAX_N))


## Длительность стана по урону (В7); 0, если удар ниже порога.
static func stun_seconds(damage: float) -> float:
	if damage < Tuning.STUN_DAMAGE_THRESHOLD:
		return 0.0
	return clampf(Tuning.STUN_BASE_S + Tuning.STUN_PER_DAMAGE_S * damage, Tuning.STUN_MIN_S, Tuning.STUN_MAX_S)


## Импульс отброса (Н·с) по урону с множителем Sudden Death.
static func knockback_impulse(damage: float, sd_knockback_mult: float = 1.0) -> float:
	return clampf(damage * Tuning.KNOCKBACK_PER_DAMAGE * sd_knockback_mult, 0.0, Tuning.KNOCKBACK_MAX)


## Направление отброса: dir (от бьющего к жертве, в плоскости XY) с прибавкой KNOCKBACK_UP_BIAS по y, нормализованное.
static func knockback_dir(dir: Vector3) -> Vector3:
	var d := Vector3(dir.x, dir.y, 0.0)
	if d.length_squared() < 1e-6:
		d = Vector3.UP
	d = d.normalized()
	d.y += Tuning.KNOCKBACK_UP_BIAS
	return d.normalized()


## Множители Sudden Death по шагу n (CONCEPT.md §12, В8).
static func sd_knockback_mult(step: int) -> float:
	return 1.0 + Tuning.SUDDEN_DEATH_KNOCKBACK_STEP * float(maxi(step, 0))


static func sd_stability_mult(step: int) -> float:
	return maxf(Tuning.SUDDEN_DEATH_STABILITY_MIN, 1.0 - Tuning.SUDDEN_DEATH_STABILITY_STEP * float(maxi(step, 0)))


## Таблица калибровки: массив словарей {id, hp, lo, hi, ok}. ok = попадание в полосу (для fall — ровно 0).
## Строки окружения при ENV_DAMAGE_ENABLED = false: полоса 0–0 (hp = compute_env = 0), плюс formula_hp = env_formula в исходной
## полосе band_if_enabled (ok требует обоих).
static func calibration_table() -> Array:
	var out: Array = []
	for row in CALIBRATION:
		var id: String = row[0]
		var mass: float = row[1]
		var speed: float = row[2]
		var part: String = row[3]
		var target: float = row[4]
		var weapon: float = row[5]
		var env: bool = row[6]
		var lo: float = row[7]
		var hi: float = row[8]
		var hp := 0.0
		var formula_ok := true
		var extra := {}
		if env:
			hp = compute_env(mass, speed, target)
			if not Tuning.ENV_DAMAGE_ENABLED:
				var f := env_formula(mass, speed, target)
				formula_ok = f >= lo - 1e-6 and f <= hi + 1e-6
				extra = {"env_disabled": true, "formula_hp": snappedf(f, 0.01), "band_if_enabled": [lo, hi], "formula_ok": formula_ok}
				lo = 0.0
				hi = 0.0
		else:
			var is_weapon := part == WEAPON_ROW
			hp = compute(mass, speed, body_mult_of(part) if part != "" and not is_weapon else 1.0, weapon, 1.0, 1.0, target, is_weapon)
		var ok := hp >= lo - 1e-6 and hp <= hi + 1e-6 and formula_ok
		var rec := {"id": id, "mass": mass, "speed": speed, "hp": snappedf(hp, 0.01), "lo": lo, "hi": hi, "ok": ok}
		rec.merge(extra)
		out.append(rec)
	return out


static func calibration_ok() -> bool:
	for r in calibration_table():
		if not bool(r["ok"]):
			return false
	return true


static func print_calibration_table() -> void:
	print("=== DAMAGE CALIBRATION (coef %.2f, min %.1f m/s, cap %.1f kg body, weapon soft cap %.1f kg) ===" % [Tuning.DAMAGE_COEF, Tuning.MIN_IMPACT_SPEED, Tuning.MASS_CAP, Tuning.WEAPON_MASS_SOFT_CAP])
	for r in calibration_table():
		var note := ""
		if r.has("formula_hp"):
			var b: Array = r["band_if_enabled"]
			note = "  (env off; formula %.2f HP, band %.0f-%.0f)" % [r["formula_hp"], b[0], b[1]]
		print("  %-20s m=%5.1f v=%5.1f -> %6.2f HP  band %4.0f-%-4.0f %s%s" % [r["id"], r["mass"], r["speed"], r["hp"], r["lo"], r["hi"], "ok" if r["ok"] else "OUT", note])
