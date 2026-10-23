## Удар по массе (docs/plan-demo/IMPACT_MODEL.md, автор 23.10: «главное сейчас скорость, а не масса… чтобы не было: разогнался, ударил
## головой человека в 2 раза больше тебя — и его в нокаут; как в реальной жизни»). Стандартный режим, Tuning.IMPACT_MODEL_DEFAULT;
## клавиша «`» («Ё») в бою (HitJuice) выключает — старая формула Damage.compute без масс тел, как до 23.10. Состояние на диск не пишется.
##
## Старая формула (Damage.compute) видит только деталь, которой бьют: min(её масса, 4 кг) × (v − 1.5). Масса бойцов не входила
## никуда, кроме отброса: 32-кг безногий головой в 68-кг рогатого и 40-кг человек головой в 40-кг человека — один и тот же урон 16.5.
## Новая модель — множители к старой формуле, равные 1.0, когда оба бойца весят IMPACT_REF_BODY_KG (40 кг, «Человек»): калибровка
## Damage.CALIBRATION, полосы combat_gate и бой равных не меняются, меняется только бой разных по массе.
##
##   Эффективная масса детали в ударе: m* = m_детали + κ × (M_бойца − m_детали). κ — доля тела, которая «стоит за» деталью
##   (IMPACT_COUPLING: торс 0.6 — бьёт всем корпусом, голова 0.3 — шея, кисть 0.05 — почти одна кисть). Оружие — своя масса (κ 0).
##   Приведённая масса пары μ = m*_бьющего × m*_жертвы / (m*_бьющего + m*_жертвы) — сколько массы реально участвует в обмене импульсом
##   (импульс удара J = μ·Δv·(1+e)). Тяжёлого бьющего μ больше; если жертва тяжелее, μ тоже растёт, но ей это почти не вредит:
##   урон — это ускорение ударенной детали, Δv_жертвы = J / m*_жертвы.
##   Урон ×  B = [μ / μ_ref] × (m*_жертвы,ref / m*_жертвы)^γ        (ref — те же детали у бойцов по 40 кг; γ = IMPACT_VICTIM_EXP)
##   Отброс ×  K = μ / μ_ref                                        (Doll.apply_knockback дальше делит импульс на массу жертвы)
##   B и K клэмпятся IMPACT_MULT_MIN … IMPACT_MULT_MAX. γ = 0 — урон по импульсу (тяжёлая жертва получает почти столько же),
##   γ = 1 — по Δv ударенной детали (как сотрясение у людей); 0.75 — между.
##   Скорость: выше IMPACT_SPEED_KNEE каждый м/с считается за IMPACT_SPEED_SLOPE (убывающая отдача): разгон ×1.8 всё ещё
##   сильнее шага, но таран 16 м/с — не втрое сильнее 8.
##   Стан: Damage.stun_seconds(урон × S), S = (40 / M_жертвы)^IMPACT_STUN_EXP — тяжёлого труднее «выключить» тем же уроном.
##   Отдача головы (3-й закон Ньютона): бьёшь ГОЛОВОЙ не в голову — своя голова получает IMPACT_HEADBUTT_REACT × нанесённый
##   урон × (B обратного удара / B): налетел на того, кто вдвое тяжелее, — себе почти половину того, что ему. Голова о голову —
##   как и раньше, обоим, но каждый со своим B.
##   Крит-отлёт (CritLaunch): минимум и потолок скорости × S — 70-кг боец от крита улетает медленнее 25-кг.
class_name ImpactModel
extends RefCounted

static var on: bool = Tuning.IMPACT_MODEL_DEFAULT


static func toggle() -> bool:
	on = not on
	return on


static func title() -> String:
	return TranslationServer.translate("Удар по массе") + ": " + TranslationServer.translate("вкл" if on else "выкл")


## Доля тела за деталью по имени узла ("Hand_L" → "Hand"); деталей кита без строки — IMPACT_COUPLING_DEFAULT. Оружие — 0.
static func coupling(part: Node) -> float:
	if part == null or part is Weapon:
		return 0.0
	if part.has_meta("impact_coupling"):
		return float(part.get_meta("impact_coupling"))
	return float(Tuning.IMPACT_COUPLING.get(Doll.part_base_name(String(part.name)), Tuning.IMPACT_COUPLING_DEFAULT))


## m* = m + κ × (M − m).
static func eff_mass(part_kg: float, body_kg: float, kappa: float) -> float:
	var m := maxf(part_kg, 0.01)
	return m + kappa * maxf(body_kg - m, 0.0)


static func reduced(a: float, b: float) -> float:
	return a * b / maxf(a + b, 0.001)


## Множители удара: {"dmg": B, "kb": K, "rev": B обратного удара (бьющая деталь — жертва)}. body_kg ≤ 0 — бьющий не кукла (оружие):
## его m* = масса, без тела. Все — 1.0 при обоих бойцах по IMPACT_REF_BODY_KG.
static func factors(s_kg: float, s_body_kg: float, s_kappa: float, v_kg: float, v_body_kg: float, v_kappa: float) -> Dictionary:
	var ref := Tuning.IMPACT_REF_BODY_KG
	var s_ref_body := ref if s_body_kg > 0.0 else 0.0
	var s := eff_mass(s_kg, s_body_kg, s_kappa)
	var sr := eff_mass(s_kg, s_ref_body, s_kappa)
	var v := eff_mass(v_kg, v_body_kg, v_kappa)
	var vr := eff_mass(v_kg, ref, v_kappa)
	var mu_ratio := reduced(s, v) / maxf(reduced(sr, vr), 0.001)
	var g := Tuning.IMPACT_VICTIM_EXP
	var lo := Tuning.IMPACT_MULT_MIN
	var hi := Tuning.IMPACT_MULT_MAX
	var b := clampf(mu_ratio * pow(vr / v, g), lo, hi)
	var rev := clampf(mu_ratio * pow(sr / s, g), lo, hi)   # та же μ, но «жертва» — бьющая деталь
	return {"dmg": b, "kb": clampf(mu_ratio, lo, hi), "rev": rev}


## Скорость в формуле урона: до колена как есть, выше — с наклоном IMPACT_SPEED_SLOPE.
static func speed_eff(v: float) -> float:
	var k := Tuning.IMPACT_SPEED_KNEE
	if v <= k:
		return v
	return k + (v - k) * Tuning.IMPACT_SPEED_SLOPE


## Множитель стана и крит-отлёта по массе жертвы: (40 / M)^IMPACT_STUN_EXP в IMPACT_STUN_RANGE.
static func mass_resist(body_kg: float) -> float:
	if body_kg <= 0.0:
		return 1.0
	var r: Vector2 = Tuning.IMPACT_STUN_RANGE
	return clampf(pow(Tuning.IMPACT_REF_BODY_KG / body_kg, Tuning.IMPACT_STUN_EXP), r.x, r.y)
