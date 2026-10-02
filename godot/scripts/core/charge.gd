## Правила Заряда (docs/plan-demo/COMBAT_CHARGE.md): сколько заряда даёт удар. Состояние живёт на Doll (charge, add_charge, расход и
## накопление — Doll._tick_charge); здесь чистые формулы и применение удара. Числа — Tuning (секция «Заряд»).
##
##   атакующему = урон × CHARGE_PER_DAMAGE × (1 + CHARGE_COMBO_STEP·(min(комбо, CHARGE_COMBO_MAX_N) − 1)) [+ CHARGE_CRIT_BONUS на
##                crit / ko_crit] [+ CHARGE_KO_BONUS на ko / ko_crit]; до CHARGE_OVER_MAX, серия держит перезаряд от таяния;
##   жертве      = урон × CHARGE_VICTIM_SHARE, не выше CHARGE_MAX;
##   не считаются: удар слабее CHARGE_MIN_HIT_DAMAGE, DOUBLE BLOW (второй контакт клинча — иначе клинч фармит заряд), урон окружения
##   и себе, удар по своей непустой команде (PvE: враги толкают друг друга).
## Зовёт Match._emit_hit_fx с ctx удара (комбо — n нового удара: у первого удара серии n = 1).
class_name Charge
extends RefCounted


## Заряд атакующему за удар (0 — не считается).
static func hit_gain(damage: float, combo: int, tier: String = "") -> float:
	if damage < Tuning.CHARGE_MIN_HIT_DAMAGE:
		return 0.0
	var n := clampi(combo, 1, Tuning.CHARGE_COMBO_MAX_N)
	var g := damage * Tuning.CHARGE_PER_DAMAGE * (1.0 + Tuning.CHARGE_COMBO_STEP * float(n - 1))
	if tier == HitTier.CRIT or tier == HitTier.KO_CRIT:
		g += Tuning.CHARGE_CRIT_BONUS
	if tier == HitTier.KO or tier == HitTier.KO_CRIT:
		g += Tuning.CHARGE_KO_BONUS
	return g


## Заряд жертве за полученный удар.
static func victim_gain(damage: float) -> float:
	if damage < Tuning.CHARGE_MIN_HIT_DAMAGE:
		return 0.0
	return damage * Tuning.CHARGE_VICTIM_SHARE


## Применяет удар (ctx из Match.make_hit_ctx, tier уже посчитан). Возвращает [заряд атакующему, заряд жертве] — фактически добавленное.
static func apply_hit(ctx: Dictionary) -> Array:
	var none := [0.0, 0.0]
	var a: Variant = ctx.get("attacker", null)
	var v: Variant = ctx.get("victim", null)
	if not (a is Doll) or not (v is Doll) or not is_instance_valid(a) or not is_instance_valid(v) or a == v:
		return none
	if bool(ctx.get("double_blow", false)):
		return none
	var kind := String(ctx.get("kind", ""))
	if kind == "environment" or kind == "self":
		return none
	var ad := a as Doll
	var vd := v as Doll
	if ad.team != "" and ad.team == vd.team:
		return none
	var damage := float(ctx.get("damage", 0.0))
	var got_a := ad.add_charge(hit_gain(damage, int(ctx.get("combo", 0)), String(ctx.get("tier", ""))), true)
	var got_v := vd.add_charge(victim_gain(damage), false)
	return [got_a, got_v]
