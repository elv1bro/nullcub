## Уровень удара для презентации (docs/plan-demo/HIT_FX.md §2.1): light / heavy / crit / ko / ko_crit — только из данных удара.
##
##   score     = damage × (1 + CRIT_HEAD_BONUS·[в голову]) × (1 + CRIT_DASH_BONUS·[атакующий в рывке]) × (1 + CRIT_COMBO_BONUS·[combo ≥ N])
##   eligible  = kind ∈ CRIT_KINDS ∧ ¬double_blow ∧ attacker — Doll ≠ victim ∧ damage ≥ CRIT_MIN_DAMAGE (слабее — никогда не крит)
##   stylish   = в голову ∨ атакующий в рывке ∨ kind weapon ∨ combo ≥ CRIT_COMBO_N
##   threshold = CRIT_SCORE × (CRIT_DROUGHT_SCORE_MULT, если stylish и с последнего крита — или с FIGHT! — прошло ≥ CRIT_DROUGHT_S боя)
##   q         = crit_enabled ∧ eligible ∧ score ≥ threshold
##   KO:       (q ∨ crush) ∧ t − last_crit ≥ CRIT_KO_GAP_S → "ko_crit", иначе "ko"
##   иначе:    q ∧ t ≥ CRIT_MIN_FIGHT_S ∧ t − last_crit ≥ CRIT_COOLDOWN_S ∧ t − last_crit_by[attacker] ≥ CRIT_ATTACKER_COOLDOWN_S → "crit";
##             v3 обход (HIT_FX.md §12.4): crush ∧ t − last_crit ≥ CRIT_BYPASS_GAP_S → "crit" сквозь кулдауны 8 / 15 с, CRIT_MIN_FIGHT_S
##             и исключение DOUBLE BLOW; crush = crit_enabled ∧ eligible(ctx, true) ∧ crushing (score ≥ CRIT_BYPASS_SCORE ∨ damage ≥
##             CRIT_BYPASS_DAMAGE); при KO — ko_crit по (q ∨ crush) и CRIT_KO_GAP_S;
##             score ≥ HITFX_HEAVY_SCORE → "heavy"; иначе "light"
##   ctx["crit_block"] — почему удар, прошедший порог (q ∨ crush), не стал критом: "min_fight" / "cooldown" (8 с матча) /
##             "attacker_cooldown" (15 с атакующего) / "bypass_gap" (сокрушительный, но < CRIT_BYPASS_GAP_S от прошлого крита); "" — иначе.
##             Пробы считают по нему мощные удары, «потерянные» кулдауном (hitfx_core_probe freq_crit_power_lost).
##   ctx["crit_bypass"] — true, если crit выдан только обходом (обычное правило его бы не дало).
##
## t — Match.fight_time (время физики: в headless детерминировано). Удар kind environment уровня не получает ("light", при KO — "ko").
## Экземпляр живёт в Match.hit_tiers, reset() — на COUNTDOWN. Числа — Tuning (секция «удар-презентация и крит»).
class_name HitTier
extends RefCounted

const LIGHT := "light"
const HEAVY := "heavy"
const CRIT := "crit"
const KO := "ko"
const KO_CRIT := "ko_crit"

## Match.fight_time последнего crit/ko_crit (-INF — ещё не было).
var last_crit_t := -INF
## attacker instance_id -> fight_time его последнего crit/ko_crit.
var last_crit_by: Dictionary = {}
## Засчитанные криты для проб: [{t, tier, score, damage, kind, part, attacker (instance_id), attacker_name, drought (score < CRIT_SCORE),
## bypass (v3: crit прошёл сквозь кулдаун как сокрушительный)}].
var crits: Array = []
## Тестовый переключатель (клипы, кадры, perf_probe; в игре всегда ""): следующий удар с уроном (не environment) получает этот
## уровень — "heavy" или "crit" (при KO — "ko" / "ko_crit"); крит фиксирует кулдаун как настоящий. Сбрасывается после удара и в reset().
var force_next := ""


## Оценка удара (без побочных эффектов). ctx: damage, part (имя ударенного тела), dash, combo.
static func score(ctx: Dictionary) -> float:
	var s := float(ctx.get("damage", 0.0))
	if String(ctx.get("part", "")).begins_with("Head"):
		s *= 1.0 + Tuning.CRIT_HEAD_BONUS
	if bool(ctx.get("dash", false)):
		s *= 1.0 + Tuning.CRIT_DASH_BONUS
	if int(ctx.get("combo", 0)) >= Tuning.CRIT_COMBO_N:
		s *= 1.0 + Tuning.CRIT_COMBO_BONUS
	return s


## «Стильный» удар (v2, HIT_FX.md §11.1): только ему засуха снижает порог — в голову, с рывка, оружием, комбо ≥ CRIT_COMBO_N.
static func stylish(ctx: Dictionary) -> bool:
	return String(ctx.get("part", "")).begins_with("Head") or String(ctx.get("kind", "")) == "head" or bool(ctx.get("dash", false)) \
		or String(ctx.get("kind", "")) == "weapon" or int(ctx.get("combo", 0)) >= Tuning.CRIT_COMBO_N


## «Сокрушительный» удар (v3, HIT_FX.md §12.4): score ≥ CRIT_BYPASS_SCORE или урон ≥ CRIT_BYPASS_DAMAGE — крит сквозь кулдауны
## 8 / 15 с, CRIT_MIN_FIGHT_S и DOUBLE BLOW, если от прошлого крита прошло ≥ CRIT_BYPASS_GAP_S боя. Без eligible (его делает classify).
static func crushing(ctx: Dictionary, sc: float = -1.0) -> bool:
	if sc < 0.0:
		sc = score(ctx)
	return sc >= Tuning.CRIT_BYPASS_SCORE or float(ctx.get("damage", 0.0)) >= Tuning.CRIT_BYPASS_DAMAGE


## Может ли удар вообще стать критом (без порога score и кулдаунов). allow_double_blow — для сокрушительного удара (v3):
## второе тело клинча в 25+ HP (молот после кисти) тоже крит, если первое критом не было (его закрывает CRIT_BYPASS_GAP_S).
static func eligible(ctx: Dictionary, allow_double_blow: bool = false) -> bool:
	if not Tuning.CRIT_KINDS.has(String(ctx.get("kind", ""))):
		return false
	if bool(ctx.get("double_blow", false)) and not allow_double_blow:
		return false
	var attacker: Variant = ctx.get("attacker", null)
	var victim: Variant = ctx.get("victim", null)
	if not (attacker is Doll) or not is_instance_valid(attacker):
		return false
	if victim is Object and is_instance_valid(victim) and attacker == victim:
		return false
	return float(ctx.get("damage", 0.0)) >= Tuning.CRIT_MIN_DAMAGE


## Порог score крита в момент fight_time: после CRIT_DROUGHT_S без крита (или с FIGHT!) — ниже в CRIT_DROUGHT_SCORE_MULT раз,
## но только для «стильного» удара (is_stylish = stylish(ctx)); обычному — всегда CRIT_SCORE.
func threshold(fight_time: float, is_stylish: bool = true) -> float:
	var since_ref := maxf(last_crit_t, 0.0)
	if is_stylish and fight_time - since_ref >= Tuning.CRIT_DROUGHT_S:
		return Tuning.CRIT_SCORE * Tuning.CRIT_DROUGHT_SCORE_MULT
	return Tuning.CRIT_SCORE


## Уровень удара; crit / ko_crit фиксируют кулдаун. Пишет ctx["score"].
func classify(ctx: Dictionary, fight_time: float, crit_enabled: bool = true) -> String:
	var sc := score(ctx)
	ctx["score"] = sc
	ctx["crit_block"] = ""
	ctx["crit_bypass"] = false
	var is_ko := bool(ctx.get("is_ko", false))
	if String(ctx.get("kind", "")) == "environment":
		return KO if is_ko else LIGHT
	if force_next != "":
		var f := force_next
		force_next = ""
		if f == CRIT and crit_enabled and ctx.get("attacker", null) is Doll and is_instance_valid(ctx["attacker"]):
			_record(ctx, fight_time, KO_CRIT if is_ko else CRIT, sc)
			return KO_CRIT if is_ko else CRIT
		if f == HEAVY or f == CRIT:
			return KO if is_ko else HEAVY
	var q := crit_enabled and eligible(ctx) and sc >= threshold(fight_time, stylish(ctx))
	var crush := crit_enabled and eligible(ctx, true) and crushing(ctx, sc)
	if is_ko:
		if (q or crush) and fight_time - last_crit_t >= Tuning.CRIT_KO_GAP_S:
			_record(ctx, fight_time, KO_CRIT, sc)
			return KO_CRIT
		return KO
	var block := _cooldown_block(ctx, fight_time) if q else ""
	if q and block == "":
		_record(ctx, fight_time, CRIT, sc)
		return CRIT
	if crush:
		# v3: сокрушительный удар проходит сквозь кулдауны 8 / 15 с, CRIT_MIN_FIGHT_S и DOUBLE BLOW, но не ближе CRIT_BYPASS_GAP_S
		# к прошлому криту (кинематограф 1.3 с реального времени — доли секунды боя — к этому времени давно закончен)
		if fight_time - last_crit_t >= Tuning.CRIT_BYPASS_GAP_S:
			ctx["crit_bypass"] = true
			_record(ctx, fight_time, CRIT, sc, true)
			return CRIT
		block = "bypass_gap"
	ctx["crit_block"] = block
	return HEAVY if sc >= Drive.heavy_score() else LIGHT


## Что мешает q-удару стать обычным критом: "min_fight" / "cooldown" (матч) / "attacker_cooldown"; "" — ничего.
func _cooldown_block(ctx: Dictionary, fight_time: float) -> String:
	if fight_time < Tuning.CRIT_MIN_FIGHT_S:
		return "min_fight"
	if fight_time - last_crit_t < Drive.crit_cooldown_s():
		return "cooldown"
	var aid := (ctx["attacker"] as Object).get_instance_id()
	if fight_time - float(last_crit_by.get(aid, -INF)) < Drive.crit_attacker_cooldown_s():
		return "attacker_cooldown"
	return ""


func reset() -> void:
	last_crit_t = -INF
	last_crit_by.clear()
	crits.clear()
	force_next = ""


func _record(ctx: Dictionary, fight_time: float, tier: String, sc: float, bypass: bool = false) -> void:
	var a := ctx["attacker"] as Node
	last_crit_t = fight_time
	last_crit_by[a.get_instance_id()] = fight_time
	crits.append({"t": fight_time, "tier": tier, "score": sc, "damage": float(ctx.get("damage", 0.0)), "kind": String(ctx.get("kind", "")),
		"part": String(ctx.get("part", "")), "attacker": a.get_instance_id(), "attacker_name": String(a.name), "drought": sc < Tuning.CRIT_SCORE,
		"bypass": bypass})
