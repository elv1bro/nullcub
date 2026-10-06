## Проба ядра эффектов удара и потолка массы (docs/plan-demo/HIT_FX.md §4.1, §5.2–5.3; 06-combat-hud.md «Потолок массы 29.09»).
## Headless, без HitFxDirector/SfxDirector: проверяет только гейм-хуки ядра — их потребители (эффекты, звук) проверяют свои пробы.
##
## Проверки (checks[].id):
##   tier_*   — HitTier на синтетических ctx (точные значения, v2 HIT_FX.md §11.1): score и бонусы, пороги heavy 9 / crit 18,
##              CRIT_MIN_DAMAGE 15 (v3; слабее — никогда не crit/ko_crit, даже со всеми бонусами), «стильный» удар (HitTier.stylish),
##              исключения (double_blow, environment, self, без атакующего), CRIT_MIN_FIGHT_S 5, кулдауны 8 с (матч) и 15 с (атакующий),
##              засуха 15 с → порог 13.5 только стильным (обычному — 18), флаг crits[].drought, ko_crit сквозь кулдаун, но ≥ 2 с,
##              crit_enabled = false, reset(); v3 (§12.4) tier_bypass_* — сокрушительный удар (урон ≥ 25 или score ≥ 27) crit сквозь
##              кулдауны 8 / 15 с, но ≥ 4 с от прошлого крита и не раньше 5 с боя, ctx.crit_block / crit_bypass, crits[].bypass;
##   mass_*   — потолок массы: стандартное оружие бьёт как до 29.09 (±0.01 HP; молот 6 кг × 0.8 = 4 кг × 1.2), части тела режутся
##              MASS_CAP, мягкий потолок оружия (30 кг → 17.3), крафтовый тяжёлый молот сильнее обычного при той же скорости
##              (формула и физика: оба молота брошены в голову манекена на 8 м/с), Damage.calibration_ok();
##   ts_* / cam_* — Match.request_time_scale / cancel_time_scale / time_scale_tags (heavy_stop HITFX_HEAVY_STOP_S в целых кадрах ± 1 кадр, минимум записей, no-op при
##              feel_enabled = false) и захват камеры (capture/release, restart возвращает игровую камеру и time_scale 1);
##   hit_*    — настоящий удар через Match.on_hit на Void: полный ctx сигнала hit_fx, light без hit stop, heavy с heavy_stop (за ним —
##              heavy_slow сока удара, §13), crit —
##              отлёт ЦМ в [5.5, 7.5] × sd, клэмп 7.5 в окне CRIT_FLIGHT_S, потом снова FLIGHT_MAX_SPEED; тот же отлёт при
##              feel_enabled = false; атакующий в рывке (6 м/с) бьёт крит в упор — ЦМ вдоль kb_dir ≤ CRIT_ATTACKER_STOP_SPEED всё окно
##              0.5 с, через 0.5 с между ЦМ ≥ 2 м (hit_crit_attacker_*); ko_crit — части +3 м/с; после KO time_scale 1 и тегов нет;
##   preset_* — FxPreset (HIT_FX.md §11.2): reduced/off пишут значения в HitFxDirector; при off heavy и крит без стоп-кадра/замедления
##              и тегов, без вспышек/инверсий/ката/punch (stats директора), старый hit_feel без hit stop, крит-отлёт есть, KO slow-mo есть;
##   slam_*   — кукла ~8 м/с в стену Void: env_slam, hp 100, hit_fx не пришёл; удар о стену в крит-полёте — ctx.crit_flight;
##   freq_*   — боты match_probe (наскок) на площадках freq, matches матчей до KO (без KO за freq_s боя — следующий) на каждом
##              сиде seeds: Σ fight_time / Σ(crit + ko_crit) в 25–45 с, ни одного крита слабее CRIT_MIN_DAMAGE, выданных засухой ≤ 20 %, зазоры crit ≥ 8 с (атакующий ≥ 15 с) в матче
##              (crit обходом кулдауна — ≥ CRIT_BYPASS_GAP_S 4 с), freq_crit_power_lost — ни одного heavy ≥ 25 HP / score 27 из-за кулдауна 8 / 15 с,
##              MIN_FIGHT или DOUBLE BLOW (допустим только зазор 4 с от прошлого крита — bypass_gap), ko_crit ≥ 2 с
##              от прошлого крита, heavy 8–20 % ударов, env-ударов 0, env_slam > 0, обычный полёт ≤ FLIGHT_MAX_SPEED, крит-полёт
##              ≤ CRIT_FLIGHT_MAX_SPEED × sd. В отчёте info.freq.hits — все удары [площадка@сид, матч, t, урон, score, eligible, tier,
##              kind, атакующий, double_blow, is_ko, part, dash, combo, weapon_id, crit_block] для перекалибровки порогов; info.freq.power —
##              мощные удары по уровням и причинам, damage_dist — урон crit и heavy по корзинам; crit=0 — те же бои без крита.
## Запуск (≈ 100 с): godot --headless --path . --fixed-fps 60 res://tests/hitfx_core_probe.tscn -- "freq=void+ruins+workshop,matches=6,seeds=29+7+13"
##   (06.10: три сида вместо двух — в «Запасе из деталей», стандарте с 06.10, бои короче, период крита ≈ 30 с вместо ≈ 34 с и с большим
##   разбросом; на 36 матчах 1 прогон из 7 уходил ниже 25 с, на 54 разброс меньше. Коридор 25–45 с прежний.)
##   only=tier — только синтетика HitTier + масса (tests/hit_tier_probe.tscn, секунды); freq=none — без ботов.
## Отчёт tests/hitfx_core_probe_report.json (или out=…), exit 0/1.
extends Node3D

const SCENES := {
	"ruins": "res://scenes/playground.tscn", "workshop": "res://scenes/playground_workshop.tscn",
	"void": "res://scenes/playground_void.tscn", "scrap": "res://scenes/playground_scrap.tscn",
}
const DOLL_SCENE := "res://scenes/doll/doll.tscn"
const DOLL_DARK_SCENE := "res://scenes/doll/doll_dark.tscn"
const CTX_KEYS := ["victim", "attacker", "damage", "kind", "part", "part_base", "striker", "position", "normal", "dir", "speed",
	"weapon_id", "combo", "double_blow", "dash", "score", "tier", "is_ko", "hp_after", "fight_time", "sd_mult", "colour"]
const SLAM_KEYS := ["doll", "part", "speed", "position", "normal", "flying", "crit_flight", "fight_time"]
const TIERS := ["light", "heavy", "crit", "ko", "ko_crit"]
const OLD_WEAPON_MULT := {"hammer": 1.2}   # damage_mult до 29.09 (масса резалась MASS_CAP 4 кг)
const FLING_SPEED := 8.0
const CRIT_WALL_GAP_X := 5.3            # x торса жертвы перед критом (стена Void — x = 7; дамп крит-полёта 1.0 — издали приходит < 4 м/с)
const FRAME_MS := 1000.0 / 60.0
# боты — как tests/match_probe.gd
const RUSH_NEAR := 1.3
const RUSH_RETREAT_S := 1.2
const DASH_FROM_M := 2.0
const STUCK_S := 6.0
const UNSTICK_S := 1.2

## Режим по умолчанию (tests/hit_tier_probe.tscn ставит "tier"); аргумент only= перекрывает.
@export var default_only := ""

var cfg := {"only": "", "freq": "void+ruins+workshop", "freq_s": 60.0, "matches": 6, "crit": true, "seed": 29, "seeds": "29+7+13", "out": "res://tests/hitfx_core_probe_report.json"}
var report := {"ok": true, "checks": [], "info": {}}
var t := 0.0
var pg: Node3D = null
var match_node: Match = null
var fx_ctxs: Array = []
var slam_ctxs: Array = []
var hit_kinds: Dictionary = {}
# монитор полёта (_physics_process идёт ПОСЛЕ кукол: process_physics_priority) — ЦМ после их клэмпа
var fly_max_normal := 0.0
var fly_max_crit := 0.0
var fly_normal_samples := 0
var fly_prev: Dictionary = {}          # doll id -> [режим полёта, |v_ЦМ|] прошлого тика
var fly_crit_samples := 0
# боты
var rush_retreat: Dictionary = {}
var last_hit_t := 0.0
var unstick_until := -1.0
var unstick_n := 0


func _ready() -> void:
	process_physics_priority = 1000
	cfg["only"] = default_only
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"only": cfg["only"] = p[1]
				"freq": cfg["freq"] = p[1]
				"freq_s": cfg["freq_s"] = float(p[1])
				"matches": cfg["matches"] = int(p[1])
				"crit": cfg["crit"] = p[1] != "0"
				"seed": cfg["seed"] = int(p[1])
				"seeds": cfg["seeds"] = p[1]
				"out": cfg["out"] = p[1]
	seed(int(cfg["seed"]))   # break_apart (KO) разлетается через randf — без сида бои после первого KO не повторяются
	call_deferred("_run")


func _run() -> void:
	print("=== HITFX CORE PROBE ===")
	_tier_checks()
	_mass_checks()
	if cfg["only"] != "tier":
		await _fling_checks()
		await _match_checks()
		if cfg["freq"] != "none":
			await _freq_checks()
	_finish()


# ------------------------------------------------------------------ утилиты

func _check(id: String, ok: bool, value: Variant, expect: Variant, detail: String = "") -> void:
	report["checks"].append({"id": id, "ok": ok, "value": _js(value), "expect": _js(expect), "detail": detail})
	if not ok:
		report["ok"] = false
	print("  %s %s: %s (expect %s) %s" % ["ok  " if ok else "FAIL", id, str(_js(value)), str(_js(expect)), detail])


func _js(v: Variant) -> Variant:
	if v is float:
		return snappedf(v, 0.001)
	if v is Vector3:
		return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _js(x))
	return v


func _ticks(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


static func _com_velocity(d: Doll) -> Vector3:
	var p := Vector3.ZERO
	var m := 0.0
	for b in d.parts.values():
		if b is RigidBody3D and is_instance_valid(b):
			p += (b as RigidBody3D).linear_velocity * (b as RigidBody3D).mass
			m += (b as RigidBody3D).mass
	return p / m if m > 0.0 else Vector3.ZERO


func _physics_process(delta: float) -> void:
	t += delta
	if match_node == null or not is_instance_valid(match_node):
		return
	# отдача атакующего (apply_recoil) и удар, разобранный DollCombat после тика куклы, могут на один тик вынести ЦМ за клэмп —
	# кукла режет его в следующем своём тике. Поэтому в зачёт идёт min двух подряд замеров одной куклы в одном режиме полёта.
	for d in match_node.dolls():
		var dd := d as Doll
		var key := dd.get_instance_id()
		if not dd.alive or not dd.is_flying():
			fly_prev.erase(key)
			continue
		var sp := _com_velocity(dd).length()
		var mode := 1 if dd.flight_cap_active() else 0
		var prev: Array = fly_prev.get(key, [])
		fly_prev[key] = [mode, sp]
		if prev.is_empty() or int(prev[0]) != mode:
			continue
		var held := minf(sp, float(prev[1]))
		if mode == 1:
			fly_max_crit = maxf(fly_max_crit, held)
			fly_crit_samples += 1
		else:
			fly_max_normal = maxf(fly_max_normal, held)
			fly_normal_samples += 1


# ------------------------------------------------------------------ HitTier (синтетика)

func _ctx(att: Variant, vic: Variant, dmg: float, extra: Dictionary = {}) -> Dictionary:
	var c := {"attacker": att, "victim": vic, "damage": dmg, "kind": "body", "part": "Torso", "dash": false, "combo": 1,
		"double_blow": false, "is_ko": false}
	c.merge(extra, true)
	return c


func _tier(id: String, ht: HitTier, ctx: Dictionary, ft: float, want: String, crit_enabled: bool = true) -> void:
	var got := ht.classify(ctx, ft, crit_enabled)
	_check("tier_" + id, got == want, got, want, "score %.3f at t %.2f" % [float(ctx.get("score", 0.0)), ft])


func _tier_checks() -> void:
	print("--- HitTier ---")
	var a := Doll.new()
	a.name = "A"
	var b := Doll.new()
	b.name = "B"
	var c := Doll.new()
	c.name = "C"
	# score и бонусы
	_check("tier_score_plain", is_equal_approx(HitTier.score(_ctx(a, b, 10.0)), 10.0), HitTier.score(_ctx(a, b, 10.0)), 10.0)
	_check("tier_score_head", is_equal_approx(HitTier.score(_ctx(a, b, 10.0, {"part": "Head"})), 12.5), HitTier.score(_ctx(a, b, 10.0, {"part": "Head"})), 12.5)
	_check("tier_score_dash", is_equal_approx(HitTier.score(_ctx(a, b, 10.0, {"dash": true})), 11.5), HitTier.score(_ctx(a, b, 10.0, {"dash": true})), 11.5)
	_check("tier_score_combo2", is_equal_approx(HitTier.score(_ctx(a, b, 10.0, {"combo": 2})), 10.0), HitTier.score(_ctx(a, b, 10.0, {"combo": 2})), 10.0)
	_check("tier_score_combo3", is_equal_approx(HitTier.score(_ctx(a, b, 10.0, {"combo": 3})), 11.0), HitTier.score(_ctx(a, b, 10.0, {"combo": 3})), 11.0)
	var all_b := HitTier.score(_ctx(a, b, 10.0, {"part": "Head", "dash": true, "combo": 4}))
	_check("tier_score_all", is_equal_approx(all_b, 10.0 * 1.25 * 1.15 * 1.1), all_b, 15.8125)
	# пороги (v2, HIT_FX.md §11.1: CRIT_SCORE 18, CRIT_MIN_DAMAGE 14, засуха 15 с × 0.75 только стильным)
	var cs := Tuning.CRIT_SCORE
	_tier("light_below_heavy", HitTier.new(), _ctx(a, b, 8.99), 10.0, "light")
	_tier("heavy_at_9", HitTier.new(), _ctx(a, b, 9.0), 10.0, "heavy")
	_tier("heavy_below_crit", HitTier.new(), _ctx(a, b, cs - 0.01), 10.0, "heavy")
	_tier("crit_at_score", HitTier.new(), _ctx(a, b, cs), 10.0, "crit")
	_tier("crit_by_bonus", HitTier.new(), _ctx(a, b, cs / 1.15 + 1e-4, {"dash": true}), 10.0, "crit")   # 15.65 × 1.15 = 18 (v3: MIN_DAMAGE 15 > 14.4 головы)
	# CRIT_MIN_DAMAGE — в засуху, стильный удар в голову (порог CS × DM ниже урона с бонусом): чуть меньше минимума — heavy, ровно — crit
	var md := Tuning.CRIT_MIN_DAMAGE
	var ds := Tuning.CRIT_DROUGHT_S
	var dthr := cs * Tuning.CRIT_DROUGHT_SCORE_MULT
	_check("tier_min_damage_binds", (md - 0.01) * (1.0 + Tuning.CRIT_HEAD_BONUS) >= dthr, (md - 0.01) * (1.0 + Tuning.CRIT_HEAD_BONUS), ">= %.2f" % dthr,
		"setup: MIN_DAMAGE, not the drought threshold, decides the next two cases")
	_tier("min_damage_below", HitTier.new(), _ctx(a, b, md - 0.01, {"part": "Head"}), ds, "heavy")
	_tier("min_damage_at", HitTier.new(), _ctx(a, b, md, {"part": "Head"}), ds, "crit")
	_tier("min_damage_all_bonus", HitTier.new(), _ctx(a, b, md - 0.01, {"part": "Head", "dash": true, "combo": 5, "kind": "weapon"}), ds, "heavy")
	_check("tier_eligible_min", HitTier.eligible(_ctx(a, b, md)) and not HitTier.eligible(_ctx(a, b, md - 0.01)), md, "eligible from CRIT_MIN_DAMAGE")
	_check("tier_values", is_equal_approx(Tuning.HITFX_HEAVY_SCORE, 9.0) and is_equal_approx(cs, 18.0) and is_equal_approx(md, 15.0)
		and is_equal_approx(ds, 15.0) and is_equal_approx(dthr, 13.5) and is_equal_approx(Tuning.CRIT_ATTACKER_STOP_SPEED, 1.5)
		and is_equal_approx(Tuning.HITFX_HEAVY_STOP_S, 0.083),
		[Tuning.HITFX_HEAVY_SCORE, cs, md, ds, dthr, Tuning.CRIT_ATTACKER_STOP_SPEED, Tuning.HITFX_HEAVY_STOP_S], [9.0, 18.0, 15.0, 15.0, 13.5, 1.5, 0.083],
		"tuning v2 29.09 (docs/plan-demo/HIT_FX.md §11.1), MIN_DAMAGE 15 — v3 §12.4")
	# «стильный» удар: голова, рывок, оружие, комбо ≥ N; обычный удар в торс — нет
	var st := [HitTier.stylish(_ctx(a, b, 15.0, {"part": "Head"})), HitTier.stylish(_ctx(a, b, 15.0, {"kind": "head", "part": "Neck"})),
		HitTier.stylish(_ctx(a, b, 15.0, {"dash": true})), HitTier.stylish(_ctx(a, b, 15.0, {"kind": "weapon"})),
		HitTier.stylish(_ctx(a, b, 15.0, {"combo": Tuning.CRIT_COMBO_N})), HitTier.stylish(_ctx(a, b, 15.0, {"combo": Tuning.CRIT_COMBO_N - 1})),
		HitTier.stylish(_ctx(a, b, 15.0))]
	_check("tier_stylish", st == [true, true, true, true, true, false, false], st, [true, true, true, true, true, false, false],
		"head part, kind head, dash, weapon, combo N, combo N-1, plain torso")
	# исключения
	_tier("excl_double_blow", HitTier.new(), _ctx(a, b, 20.0, {"double_blow": true}), 10.0, "heavy")   # 20 HP: не сокрушительный (v3)
	_tier("excl_environment", HitTier.new(), _ctx(null, b, 30.0, {"kind": "environment"}), 10.0, "light")
	_tier("excl_self_kind", HitTier.new(), _ctx(b, b, 30.0, {"kind": "self"}), 10.0, "heavy")
	_tier("excl_self_attacker", HitTier.new(), _ctx(b, b, 30.0), 10.0, "heavy")
	_tier("excl_no_attacker", HitTier.new(), _ctx(null, b, 30.0), 10.0, "heavy")
	_tier("weapon_kind", HitTier.new(), _ctx(a, b, 30.0, {"kind": "weapon"}), 10.0, "crit")
	_tier("head_kind", HitTier.new(), _ctx(a, b, 30.0, {"kind": "head", "part": "Head"}), 10.0, "crit")
	# CRIT_MIN_FIGHT_S
	_tier("min_fight_4_99", HitTier.new(), _ctx(a, b, 20.0), 4.99, "heavy")
	_tier("min_fight_5", HitTier.new(), _ctx(a, b, 20.0), 5.0, "crit")
	# глобальный кулдаун 8 с: A крит на 10, B на 17.99 — heavy, на 18 — crit (удар 20 HP: ниже порога обхода v3 — 25 HP / score 27)
	var h := HitTier.new()
	_tier("cd_first", h, _ctx(a, b, 20.0), 10.0, "crit")
	var c_blk := _ctx(c, b, 20.0)
	_tier("cd_global_17_99", h, c_blk, 17.99, "heavy")
	_check("tier_block_cooldown", String(c_blk.get("crit_block", "")) == "cooldown", c_blk.get("crit_block", ""), "cooldown", "ctx.crit_block")
	_tier("cd_global_18", h, _ctx(c, b, 20.0), 18.0, "crit")
	# кулдаун атакующего 15 с: A на 10 → A на 18 (глобальный прошёл) — heavy, на 24.99 — heavy, на 25 — crit
	h = HitTier.new()
	_tier("cd_att_first", h, _ctx(a, b, 20.0), 10.0, "crit")
	var a_blk := _ctx(a, b, 20.0)
	_tier("cd_att_18", h, a_blk, 18.0, "heavy")
	_check("tier_block_attacker", String(a_blk.get("crit_block", "")) == "attacker_cooldown", a_blk.get("crit_block", ""), "attacker_cooldown", "ctx.crit_block")
	_tier("cd_att_24_99", h, _ctx(a, b, 20.0), 24.99, "heavy")
	_tier("cd_att_25", h, _ctx(a, b, 20.0), 25.0, "crit")
	_check("tier_crits_logged", h.crits.size() == 2 and is_equal_approx(float(h.crits[1]["t"]), 25.0) and not bool(h.crits[1]["bypass"]), h.crits.size(), 2)
	# засуха: без крита CRIT_DROUGHT_S от FIGHT! (и от последнего крита) — порог CS × CRIT_DROUGHT_SCORE_MULT, но только стильным ударам
	h = HitTier.new()
	_check("tier_threshold_before_drought", is_equal_approx(h.threshold(ds - 0.01), cs), h.threshold(ds - 0.01), cs)
	_check("tier_threshold_drought", is_equal_approx(h.threshold(ds), dthr) and is_equal_approx(h.threshold(ds, false), cs), [h.threshold(ds), h.threshold(ds, false)], [dthr, cs],
		"stylish / plain")
	_tier("drought_plain_heavy", h, _ctx(a, b, cs - 0.01), ds, "heavy")                     # обычный удар: засуха не помогает
	_tier("drought_stylish_early", h, _ctx(a, b, md, {"dash": true}), ds - 0.01, "heavy")   # 14 × 1.15 = 16.1 < 18 до засухи
	_tier("drought_stylish_below_min", h, _ctx(a, b, md - 0.01, {"dash": true}), ds, "heavy")
	_tier("drought_stylish_dash", h, _ctx(a, b, md, {"dash": true}), ds, "crit")           # 16.1 ≥ 13.5
	_check("tier_crit_drought_flag", h.crits.size() == 1 and bool(h.crits[0]["drought"]), h.crits.map(func(x: Dictionary) -> bool: return bool(x["drought"])), [true])
	_check("tier_threshold_after_crit", is_equal_approx(h.threshold(2.0 * ds - 0.01), cs) and is_equal_approx(h.threshold(2.0 * ds), dthr),
		[h.threshold(2.0 * ds - 0.01), h.threshold(2.0 * ds)], [cs, dthr])
	_tier("drought_weapon", HitTier.new(), _ctx(a, b, md, {"kind": "weapon"}), ds, "crit")
	_tier("drought_combo", HitTier.new(), _ctx(a, b, md, {"combo": Tuning.CRIT_COMBO_N}), ds, "crit")
	_tier("drought_combo_low", HitTier.new(), _ctx(a, b, md, {"combo": Tuning.CRIT_COMBO_N - 1}), ds, "heavy")
	# ko_crit: сквозь кулдауны и CRIT_MIN_FIGHT_S, но не ближе CRIT_KO_GAP_S к прошлому криту
	h = HitTier.new()
	_tier("ko_crit_early", h, _ctx(a, b, 30.0, {"is_ko": true}), 1.0, "ko_crit")
	h = HitTier.new()
	_tier("ko_gap_first", h, _ctx(a, b, 30.0), 10.0, "crit")
	_tier("ko_gap_11_99", h, _ctx(a, b, 30.0, {"is_ko": true}), 11.99, "ko")
	_tier("ko_gap_12", h, _ctx(a, b, 30.0, {"is_ko": true}), 12.0, "ko_crit")
	_tier("ko_low_score", HitTier.new(), _ctx(a, b, 10.0, {"is_ko": true}), 10.0, "ko")
	_tier("ko_below_min_damage", HitTier.new(), _ctx(a, b, md - 0.01, {"is_ko": true, "part": "Head", "dash": true, "combo": 5}), 30.0, "ko")
	_tier("ko_double_blow", HitTier.new(), _ctx(a, b, 20.0, {"is_ko": true, "double_blow": true}), 10.0, "ko")
	# выключатель
	_tier("disabled_crit", HitTier.new(), _ctx(a, b, 30.0), 10.0, "heavy", false)
	_tier("disabled_ko", HitTier.new(), _ctx(a, b, 30.0, {"is_ko": true}), 10.0, "ko", false)
	# reset
	h = HitTier.new()
	_tier("reset_first", h, _ctx(a, b, 30.0), 10.0, "crit")
	h.reset()
	_check("tier_reset_state", h.last_crit_t == -INF and h.last_crit_by.is_empty() and h.crits.is_empty(), h.crits.size(), 0)
	_tier("reset_again", h, _ctx(a, b, 30.0), 11.0, "crit")
	_bypass_checks(a, b, c)
	a.free()
	b.free()
	c.free()


## v3 (HIT_FX.md §12.4): «сокрушительный» удар (score ≥ CRIT_BYPASS_SCORE или урон ≥ CRIT_BYPASS_DAMAGE) — крит сквозь кулдауны
## 8 / 15 с, но не ближе CRIT_BYPASS_GAP_S к прошлому криту и не раньше CRIT_MIN_FIGHT_S; обычный крит после него ждёт 8 / 15 с от него.
func _bypass_checks(a: Doll, b: Doll, c: Doll) -> void:
	var bs := Tuning.CRIT_BYPASS_SCORE
	var bd := Tuning.CRIT_BYPASS_DAMAGE
	var bg := Tuning.CRIT_BYPASS_GAP_S
	_check("tier_bypass_values", is_equal_approx(bs, 1.5 * Tuning.CRIT_SCORE) and is_equal_approx(bd, 25.0) and is_equal_approx(bg, 4.0),
		[bs, bd, bg], [27.0, 25.0, 4.0], "tuning v3 (HIT_FX.md §12.4)")
	# зазор обхода длиннее кинематографа (сторож 1.5 с реального времени ≥ любого времени боя внутри него) и ko-зазора
	_check("tier_bypass_gap_covers_cinematic", bg >= CritCinematic.WATCHDOG_MS / 1000.0 and bg >= Tuning.CRIT_KO_GAP_S and bg < Tuning.CRIT_COOLDOWN_S,
		bg, ">= %.1f s (cinematic watchdog), >= KO gap, < 8 s" % (CritCinematic.WATCHDOG_MS / 1000.0))
	_check("tier_crushing", HitTier.crushing(_ctx(a, b, bd)) and not HitTier.crushing(_ctx(a, b, bd - 0.01)) and HitTier.crushing(_ctx(a, b, bs / 1.25 + 1e-4, {"part": "Head"}))
		and not HitTier.crushing(_ctx(a, b, bs / 1.25 - 0.01, {"part": "Head"})), [bd, bs / 1.25], "damage ≥ 25 or score ≥ 27 (21.6 HP in the head)")
	# кулдаун атакующего: A крит на 10 → A урон 25 на 13.99 — heavy (bypass_gap), на 14 — crit (bypass)
	var h := HitTier.new()
	_tier("bypass_att_first", h, _ctx(a, b, 20.0), 10.0, "crit")
	var g := _ctx(a, b, bd)
	_tier("bypass_att_gap_13_99", h, g, 10.0 + bg - 0.01, "heavy")
	_check("tier_bypass_block_gap", String(g.get("crit_block", "")) == "bypass_gap", g.get("crit_block", ""), "bypass_gap")
	var ok_ctx := _ctx(a, b, bd)
	_tier("bypass_att_14", h, ok_ctx, 10.0 + bg, "crit")
	_check("tier_bypass_flag", h.crits.size() == 2 and bool(h.crits[1]["bypass"]) and not bool(h.crits[0]["bypass"]) and String(ok_ctx.get("crit_block", "x")) == "",
		h.crits.map(func(x: Dictionary) -> bool: return bool(x["bypass"])), [false, true])
	# обход фиксирует кулдауны как обычный крит: обычный 20 HP C через 7.99 с — heavy, через 8 — crit
	_tier("bypass_resets_cd_7_99", h, _ctx(c, b, 20.0), 10.0 + bg + 7.99, "heavy")
	_tier("bypass_resets_cd_8", h, _ctx(c, b, 20.0), 10.0 + bg + 8.0, "crit")
	# кулдаун матча: A крит на 10 → C на 14: урон 24.99 в торс (score < 27) — heavy (cooldown); 21.6 в голову (score 27) — crit
	h = HitTier.new()
	_tier("bypass_match_first", h, _ctx(a, b, 20.0), 10.0, "crit")
	var lo := _ctx(c, b, bd - 0.01)
	_tier("bypass_match_below", h, lo, 10.0 + bg, "heavy")
	_check("tier_bypass_below_block", String(lo.get("crit_block", "")) == "cooldown", lo.get("crit_block", ""), "cooldown")
	_tier("bypass_match_by_score", h, _ctx(c, b, bs / 1.25 + 1e-4, {"part": "Head"}), 10.0 + bg, "crit")
	# CRIT_MIN_FIGHT_S и DOUBLE BLOW обход снимает (первая сшибка в 40 HP и молот вторым телом клинча — тоже «сокрушительный удар»)
	var mf := _ctx(a, b, 40.0)
	_tier("bypass_min_fight", HitTier.new(), mf, 1.0, "crit")
	_check("tier_bypass_min_fight_flag", bool(mf.get("crit_bypass", false)), mf.get("crit_bypass", false), true)
	var mf_lo := _ctx(a, b, bd - 0.01)
	_tier("bypass_min_fight_below", HitTier.new(), mf_lo, Tuning.CRIT_MIN_FIGHT_S - 0.01, "heavy")
	_check("tier_block_min_fight", String(mf_lo.get("crit_block", "")) == "min_fight", mf_lo.get("crit_block", ""), "min_fight")
	_tier("bypass_double_blow", HitTier.new(), _ctx(a, b, bd, {"double_blow": true}), 10.0, "crit")
	_tier("bypass_ko_double_blow", HitTier.new(), _ctx(a, b, bd, {"is_ko": true, "double_blow": true}), 10.0, "ko_crit")
	# ... но не CRIT_MIN_DAMAGE / kind / self / выключатель и не зазор: первое тело клинча — крит, второе (молот) через 0.1 с — heavy
	h = HitTier.new()
	_tier("bypass_excl_first", h, _ctx(a, b, 20.0), 10.0, "crit")
	var dbg := _ctx(a, b, 40.0, {"double_blow": true})
	_tier("bypass_excl_double_blow_gap", h, dbg, 10.1, "heavy")
	_check("tier_bypass_double_blow_block", String(dbg.get("crit_block", "")) == "bypass_gap", dbg.get("crit_block", ""), "bypass_gap")
	_tier("bypass_excl_self", h, _ctx(b, b, 40.0), 10.0 + bg, "heavy")
	_tier("bypass_excl_self_kind", h, _ctx(c, b, 40.0, {"kind": "self"}), 10.0 + bg, "heavy")
	_tier("bypass_disabled", h, _ctx(c, b, 40.0), 10.0 + bg, "heavy", false)
	_check("tier_bypass_min_damage_rule", Tuning.CRIT_BYPASS_SCORE / ((1.0 + Tuning.CRIT_HEAD_BONUS) * (1.0 + Tuning.CRIT_DASH_BONUS) * (1.0 + Tuning.CRIT_COMBO_BONUS))
		>= Tuning.CRIT_MIN_DAMAGE, Tuning.CRIT_BYPASS_SCORE / 1.58125, ">= CRIT_MIN_DAMAGE", "score 27 with all bonuses still needs ≥ MIN_DAMAGE HP")
	# два сокрушительных подряд у одного атакующего: 10 → 14 → 17.99 heavy → 18 crit
	h = HitTier.new()
	_tier("bypass_chain_1", h, _ctx(a, b, 30.0), 10.0, "crit")
	_tier("bypass_chain_2", h, _ctx(a, b, 30.0), 10.0 + bg, "crit")
	_tier("bypass_chain_gap", h, _ctx(a, b, 30.0), 10.0 + 2.0 * bg - 0.01, "heavy")
	_tier("bypass_chain_3", h, _ctx(a, b, 30.0), 10.0 + 2.0 * bg, "crit")
	# ko_crit по-прежнему только ≥ CRIT_KO_GAP_S
	_tier("bypass_ko_gap", h, _ctx(c, b, 40.0, {"is_ko": true}), 10.0 + 2.0 * bg + Tuning.CRIT_KO_GAP_S - 0.01, "ko")


# ------------------------------------------------------------------ потолок массы

func _mass_checks() -> void:
	print("--- mass cap ---")
	var worst := 0.0
	var rows: Array = []
	for id in Tuning.WEAPON.keys():
		var e: Dictionary = Tuning.WEAPON[id]
		var m := float(e["mass"])
		var old_mult := float(OLD_WEAPON_MULT.get(id, e["damage_mult"]))
		for v in [3.0, 8.0, 12.0]:
			for tgt in [1.0, Tuning.HEAD_HIT_MULT]:
				var now := Damage.compute(m, v, 1.0, float(e["damage_mult"]), 1.0, 1.0, tgt, true)
				var was := clampf(minf(m, Tuning.MASS_CAP) * maxf(0.0, v - Tuning.MIN_IMPACT_SPEED) * Tuning.DAMAGE_COEF * old_mult * tgt, 0.0, Tuning.DAMAGE_MAX)
				worst = maxf(worst, absf(now - was))
		rows.append({"id": id, "mass": m, "mult": e["damage_mult"], "hp_8": snappedf(Damage.compute(m, 8.0, 1.0, float(e["damage_mult"]), 1.0, 1.0, 1.0, true), 0.01)})
	report["info"]["standard_weapons"] = rows
	_check("mass_standard_weapons_unchanged", worst <= 0.01, worst, "<= 0.01 HP", "5 standard weapons × v 3/8/12 × body/head vs formula before 29.09")
	var ham := Damage.compute(6.0, 8.0, 1.0, float(Tuning.WEAPON["hammer"]["damage_mult"]), 1.0, 1.0, 1.0, true)
	_check("mass_hammer_8", absf(ham - 29.64) <= 0.01, ham, 29.64)
	var torso := Damage.compute(12.0, 9.0, 0.5)
	_check("mass_body_capped", is_equal_approx(torso, 4.0 * 7.5 * 0.5 * Tuning.DAMAGE_COEF), torso, 14.25, "torso 12 kg still min(m, MASS_CAP)")
	_check("mass_body_flag_default", is_equal_approx(Damage.compute(12.0, 9.0, 0.5, 1.0, 1.0, 1.0, 1.0, false), torso), true, true)
	_check("mass_weapon_uncapped", is_equal_approx(Damage.weapon_mass(6.5), 6.5) and is_equal_approx(Damage.weapon_mass(10.0), 10.0),
		[Damage.weapon_mass(6.5), Damage.weapon_mass(10.0)], [6.5, 10.0])
	var junk := Damage.weapon_mass(30.0)
	_check("mass_soft_cap_30", absf(junk - 10.0 * sqrt(3.0)) < 1e-4, junk, 17.321, "S·√(m/S)")
	var junk_touch := Damage.compute(30.0, 3.0, 1.0, 1.0, 1.0, 1.0, 1.0, true)
	_check("mass_junk_touch", junk_touch < 30.0, junk_touch, "< 30 HP", "30-kg junk at 3 m/s does not one-shot")
	_check("mass_calibration_ok", Damage.calibration_ok(), Damage.calibration_ok(), true)
	report["info"]["calibration"] = Damage.calibration_table()
	# крафтовые молоты: реальные массы пресетов
	var masses := {}
	for id in ["hammer", "heavy_hammer"]:
		var bp := CraftedWeapon.preset(id)
		if bp == null:
			continue
		var w := CraftedWeapon.create(bp)
		add_child(w)
		masses[id] = w.mass
		report["info"]["craft_" + id] = {"mass": w.mass, "damage_mult": w.damage_mult}
		w.free()
	if masses.size() == 2:
		var d0 := Damage.compute(float(masses["hammer"]), FLING_SPEED, 1.0, 1.0, 1.0, 1.0, 1.0, true)
		var d1 := Damage.compute(float(masses["heavy_hammer"]), FLING_SPEED, 1.0, 1.0, 1.0, 1.0, 1.0, true)
		_check("mass_craft_heavy_formula", d1 > d0 * 1.2, [d1, d0], "heavy > hammer × 1.2",
			"%.2f vs %.2f kg at %.0f m/s (before 29.09 both capped to 4 kg)" % [masses["heavy_hammer"], masses["hammer"], FLING_SPEED])
	else:
		_check("mass_craft_heavy_formula", false, masses.keys(), ["hammer", "heavy_hammer"], "craft presets missing")


## Оба крафтовых молота (одна скорость, одна геометрия) летят в голову стоящего манекена: урон тяжёлого больше.
func _fling_checks() -> void:
	print("--- fling: craft hammer vs heavy hammer ---")
	var res := {}
	for id in ["hammer", "heavy_hammer"]:
		res[id] = await _fling(id)
	report["info"]["fling"] = res
	var h0: Dictionary = res["hammer"]
	var h1: Dictionary = res["heavy_hammer"]
	var ok_hits := not h0.is_empty() and not h1.is_empty()
	_check("mass_fling_hits", ok_hits, [h0.get("damage", 0.0), h1.get("damage", 0.0)], "both hit (kind weapon)")
	if ok_hits:
		# геометрия касания у разных головок разная (скорость по нормали, часть) — сравнение при одной скорости: урон на (v − v0)
		# без TargetMult, и он же, пересчитанный на FLING_SPEED
		var k0 := float(h0["damage"]) / maxf(float(h0["speed"]) - Tuning.MIN_IMPACT_SPEED, 0.1) / float(h0["target_mult"])
		var k1 := float(h1["damage"]) / maxf(float(h1["speed"]) - Tuning.MIN_IMPACT_SPEED, 0.1) / float(h1["target_mult"])
		var v_ref := FLING_SPEED - Tuning.MIN_IMPACT_SPEED
		_check("mass_fling_heavy_stronger", k1 > k0 * 1.2, [k1 * v_ref, k0 * v_ref], "heavy > hammer × 1.2 at %.0f m/s" % FLING_SPEED,
			"hit %s %.2f HP at %.2f m/s / %s %.2f HP at %.2f m/s" % [h1["part"], h1["damage"], h1["speed"], h0["part"], h0["damage"], h0["speed"]])
		_check("mass_fling_matches_formula", absf(k1 / k0 - float(h1["mass"]) / float(h0["mass"])) < 0.02, k1 / k0, snappedf(float(h1["mass"]) / float(h0["mass"]), 0.001),
			"ratio = mass ratio (no MASS_CAP on weapons)")


func _fling(id: String) -> Dictionary:
	var world := Node3D.new()
	world.name = "Fling_" + id
	add_child(world)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 4.0)
	cs.shape = box
	floor_body.add_child(cs)
	world.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	var victim: Doll = (load(DOLL_DARK_SCENE) as PackedScene).instantiate()
	victim.external_input = true
	victim.player_index = 1
	world.add_child(victim)
	victim.global_position = Vector3(0, 0.05, 0)
	var dc := DollCombat.new()
	dc.name = "DollCombat"
	victim.add_child(dc)
	var attacker: Doll = (load(DOLL_SCENE) as PackedScene).instantiate()
	attacker.external_input = true
	world.add_child(attacker)
	attacker.global_position = Vector3(-9.0, 0.05, 0)
	victim.set_pose({"Shoulder": 12.0, "Elbow": 5.0})
	victim._snap_to_pose(["Shoulder", "Elbow"])
	await _ticks(60)
	var head := victim.head().global_position
	var w := CraftedWeapon.spawn_preset(id, world, Vector3(head.x - 1.5, head.y, 0.0), 0.0)
	var got := {}
	if w != null:
		w.gravity_scale = 0.0
		w.linear_velocity = Vector3(FLING_SPEED, 0, 0)
		w.angular_velocity = Vector3.ZERO
		w.last_holder = attacker
		w.released_at = w._time
		victim.damaged.connect(func(amount: float, _att: Node, part: String, _pos: Vector3, kind: String) -> void:
			if got.is_empty() and kind == "weapon":
				got.merge({"damage": snappedf(amount, 0.01), "part": part, "speed": snappedf(float(victim.last_hit.get("speed", 0.0)), 0.01),
					"mass": w.mass, "target_mult": Damage.target_mult_of(part)}))
		await _ticks(45)
	print("  fling %-13s -> %s" % [id, str(got)])
	world.queue_free()
	await _ticks(2)
	return got


# ------------------------------------------------------------------ Match на Void

func _load_scene(id: String) -> void:
	if pg != null and is_instance_valid(pg):
		pg.queue_free()
		await _ticks(2)
	Engine.time_scale = 1.0
	pg = (load(SCENES[id]) as PackedScene).instantiate()
	add_child(pg)
	match_node = pg.get_node("Match") as Match
	for d in _pair():
		(d as Doll).external_input = true
	match_node.hit_fx.connect(func(ctx: Dictionary) -> void: fx_ctxs.append(ctx))
	match_node.env_slam.connect(func(ctx: Dictionary) -> void: slam_ctxs.append(ctx))
	match_node.hit.connect(func(_v: Doll, _a: Node, _d: float, kind: String, _p: Vector3) -> void:
		hit_kinds[kind] = int(hit_kinds.get(kind, 0)) + 1
		last_hit_t = t)


func _pair() -> Array:
	var ds: Array = []
	for d in get_tree().get_nodes_in_group("dolls"):
		if d is Doll and pg.is_ancestor_of(d) and not (d as Node).is_queued_for_deletion():
			ds.append(d)
	ds.sort_custom(func(x: Doll, y: Doll) -> bool: return x.player_index < y.player_index)
	return ds


func _await_fight() -> void:
	var n := 0
	while match_node.phase != Match.Phase.FIGHT and n < 600:
		await _ticks(1)
		n += 1
	await _ticks(50)   # spawn grace 0.7 с после FIGHT!


## Удар «как DollCombat»: hit_meta, take_damage, обычный отброс, Match.on_hit; возвращает ctx сигнала hit_fx.
func _strike(att: Doll, vic: Doll, dmg: float, part: String = "Torso", kind: String = "body") -> Dictionary:
	var dir := Vector3(signf(vic.torso().global_position.x - att.torso().global_position.x), 0, 0)
	if dir == Vector3.ZERO:
		dir = Vector3.RIGHT
	var pos: Vector3 = vic.torso().global_position
	if vic.parts.has(part):
		pos = (vic.parts[part] as Node3D).global_position
	var n0 := fx_ctxs.size()
	vic.hit_meta = {"speed": 12.0, "weapon_id": "", "striker": att.torso(), "combo_mult": 1.0, "double_blow": false,
		"knockback_mult": match_node.knockback_mult(), "stun_s": 0.0, "dir": dir, "striker_name": "Hand_R"}
	vic.take_damage(dmg, att, part, pos, -dir, kind)
	var j := Damage.knockback_impulse(dmg, match_node.knockback_mult())
	if not vic.is_broken():
		vic.apply_knockback(Damage.knockback_dir(dir) * j, vic.torso(), 0.0, dir, Tuning.KNOCKBACK_MIN)
	match_node.on_hit(vic, att, dmg, kind, pos, 1, false, "", 12.0)
	return fx_ctxs[fx_ctxs.size() - 1] if fx_ctxs.size() > n0 else {}


func _ctx_complete(ctx: Dictionary) -> Array:
	var missing: Array = []
	for k in CTX_KEYS:
		if not ctx.has(k):
			missing.append(k)
	return missing


func _match_checks() -> void:
	print("--- Match hooks (Void) ---")
	await _load_scene("void")
	await _await_fight()
	var ds := _pair()
	var p1: Doll = ds[0]
	var p2: Doll = ds[1]
	# --- время ---
	match_node.feel_enabled = false
	var r_off := match_node.request_time_scale(0.05, 0.05, "heavy_stop")
	_check("ts_feel_off_noop", not r_off and match_node.time_scale_tags().is_empty() and is_equal_approx(Engine.time_scale, 1.0), r_off, false)
	match_node.feel_enabled = true
	var r_on := match_node.request_time_scale(0.05, Tuning.HITFX_HEAVY_STOP_S, "heavy_stop")
	var frames := 0
	while match_node.time_scale_tags().has("heavy_stop") and frames < 60:
		await _frames(1)
		frames += 1

	var stop_ms := float(frames) * FRAME_MS
	var want_ms := ceilf(Tuning.HITFX_HEAVY_STOP_S * 60.0 - 1e-3) * FRAME_MS   # целых кадров (0.083 → 5 = 83.3 мс)
	_check("ts_heavy_stop_ms", r_on and absf(stop_ms - want_ms) <= FRAME_MS + 0.01, stop_ms, "%.1f ± 16.7 ms" % want_ms)
	await _frames(1)
	_check("ts_restored_after_stop", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0)
	match_node.request_time_scale(0.3, 2.0, "a")
	match_node.request_time_scale(0.12, 2.0, "b")
	var s_ab := Engine.time_scale
	match_node.request_time_scale(0.001, 2.0, "c")
	var s_min := Engine.time_scale
	match_node.cancel_time_scale("c")
	match_node.cancel_time_scale("b")
	var s_a := Engine.time_scale
	var tags_a := match_node.time_scale_tags()
	match_node.cancel_time_scale("a")
	_check("ts_min_of_entries", is_equal_approx(s_ab, 0.12) and is_equal_approx(s_min, Tuning.HITFX_TIME_SCALE_MIN) and is_equal_approx(s_a, 0.3)
		and tags_a == ["a"] and is_equal_approx(Engine.time_scale, 1.0), [s_ab, s_min, s_a, Engine.time_scale], [0.12, 0.02, 0.3, 1.0])
	# --- камера ---
	var game_cam := match_node.game_camera()
	var cam := Camera3D.new()
	cam.name = "ProbeCritCam"
	pg.add_child(cam)
	match_node.capture_camera(cam, "crit")
	var cur_cap := get_viewport().get_camera_3d()
	var game_during := match_node.game_camera()
	match_node.release_camera("other")
	var owner_other := match_node.camera_owner()
	match_node.release_camera("crit")
	_check("cam_capture_release", cur_cap == cam and game_during == game_cam and owner_other == "crit" and match_node.camera_owner() == ""
		and get_viewport().get_camera_3d() == game_cam and game_cam is DynamicCamera,
		[cur_cap == cam, game_during == game_cam, owner_other, get_viewport().get_camera_3d() == game_cam], [true, true, "crit", true])
	# --- light / heavy (fight_time < CRIT_MIN_FIGHT_S: крита быть не может) ---
	match_node.fight_time = 1.0
	var c_light := await _strike(p1, p2, 5.0)
	var tags_light := match_node.time_scale_tags()
	_check("hit_light_tier", String(c_light.get("tier", "")) == "light" and not tags_light.has("heavy_stop"), [c_light.get("tier", ""), tags_light], ["light", []])
	var miss := _ctx_complete(c_light)
	_check("hit_ctx_complete", miss.is_empty(), miss, [], "keys of hit_fx ctx (HIT_FX.md §4.1)")
	_check("hit_ctx_values", c_light.get("victim") == p2 and c_light.get("attacker") == p1 and c_light.get("part") == "Torso"
		and c_light.get("part_base") == "Torso" and c_light.get("striker") == "Hand_R" and is_equal_approx((c_light["dir"] as Vector3).length(), 1.0)
		and not bool(c_light["is_ko"]) and is_equal_approx(float(c_light["hp_after"]), p2.hp) and c_light["colour"] == Tuning.PLAYER_COLORS[1]
		and is_equal_approx(float(c_light["sd_mult"]), 1.0) and is_equal_approx(float(c_light["score"]), 5.0),
		[c_light.get("part"), c_light.get("striker"), c_light.get("dir"), c_light.get("hp_after"), c_light.get("score")], "Torso, Hand_R, |dir| 1, hp, 5")
	await _ticks(60)
	var c_heavy := await _strike(p1, p2, 12.0)
	var tags_heavy := match_node.time_scale_tags()
	var ts_heavy := Engine.time_scale
	_check("hit_heavy_stop", String(c_heavy.get("tier", "")) == "heavy" and tags_heavy.has("heavy_stop") and is_equal_approx(ts_heavy, Tuning.HIT_STOP_TIME_SCALE),
		[c_heavy.get("tier", ""), tags_heavy, ts_heavy], ["heavy", ["heavy_stop"], Tuning.HIT_STOP_TIME_SCALE])
	await _frames(8)
	# сок удара (HIT_FX.md §13): за стоп-кадром heavy — замедление heavy_slow варианта HitJuice (по умолчанию А: 0.4× 0.3 с), потом 1×
	var slow_tags := match_node.time_scale_tags().duplicate()
	var ts_slow := Engine.time_scale
	var want_slow := float(HitJuice.variant()["heavy_scale"]) if Tuning.JUICE_ENABLED else 1.0
	var nf := 0
	while (Engine.time_scale < 1.0 or not match_node.time_scale_tags().is_empty()) and nf < 90:
		await _frames(1)
		nf += 1
	_check("hit_heavy_stop_gone", not slow_tags.has("heavy_stop") and (want_slow >= 1.0 or (slow_tags.has("heavy_slow")
		and absf(ts_slow - want_slow) < 0.01)) and is_equal_approx(Engine.time_scale, 1.0) and match_node.time_scale_tags().is_empty(),
		[slow_tags, ts_slow, nf], [["heavy_slow"], want_slow, "then 1.0 within 90 frames"])
	await _ticks(30)
	_check("hit_normal_flight_cap", _com_velocity(p2).length() <= Tuning.FLIGHT_MAX_SPEED + 0.01 and not p2.flight_cap_active(),
		_com_velocity(p2).length(), "<= %.1f" % Tuning.FLIGHT_MAX_SPEED)
	# --- crit: отлёт, свой клэмп, стена (свежие куклы) ---
	match_node.restart()
	await _await_fight()
	ds = _pair()
	p1 = ds[0]
	p2 = ds[1]
	var launch_on := await _crit_run(p1, p2, "on")
	# тот же удар при feel_enabled = false на свежих куклах — тот же отлёт (баланс, не презентация)
	match_node.restart()
	await _await_fight()
	ds = _pair()
	p1 = ds[0]
	p2 = ds[1]
	_check("hit_tiers_reset_on_countdown", match_node.hit_tiers.crits.is_empty() and match_node.hit_tiers.last_crit_t == -INF,
		match_node.hit_tiers.crits.size(), 0)
	match_node.feel_enabled = false
	var launch_off := await _crit_run(p1, p2, "off")
	match_node.feel_enabled = true
	_check("hit_crit_launch_feel_off", absf(launch_on - launch_off) <= 0.05, [launch_on, launch_off], "same ±0.05 m/s")
	# --- крит: атакующий в рывке не летит следом (v2, CRIT_ATTACKER_STOP_SPEED) ---
	match_node.restart()
	await _await_fight()
	ds = _pair()
	await _crit_attacker_run(ds[0], ds[1])
	# --- пресеты FX игрока (v2, FxPreset; HIT_FX.md §11.2) ---
	match_node.restart()
	await _await_fight()
	ds = _pair()
	await _preset_checks(ds[0], ds[1])
	match_node.restart()
	await _await_fight()
	ds = _pair()
	p1 = ds[0]
	p2 = ds[1]
	# --- ko_crit: части +CRIT_KO_LAUNCH_SPEED ---
	await _ticks(60)
	match_node.fight_time = maxf(match_node.fight_time, 30.0)
	p2.hp = 10.0
	var c_ko := await _strike(p1, p2, 24.0)
	var dv: Vector3 = c_ko.get("launch_dv", Vector3.ZERO)
	_check("hit_ko_crit", String(c_ko.get("tier", "")) == "ko_crit" and bool(c_ko.get("is_ko", false)) and is_equal_approx(float(c_ko.get("hp_after", -1.0)), 0.0)
		and absf(dv.length() - Tuning.CRIT_KO_LAUNCH_SPEED) < 1e-3, [c_ko.get("tier", ""), dv.length()], ["ko_crit", Tuning.CRIT_KO_LAUNCH_SPEED])
	var wait := 0
	while (Engine.time_scale < 1.0 or not match_node.time_scale_tags().is_empty()) and wait < 240:
		await _frames(1)
		wait += 1
	_check("hit_ko_time_restored", is_equal_approx(Engine.time_scale, 1.0) and match_node.time_scale_tags().is_empty(),
		[Engine.time_scale, wait * FRAME_MS], "1.0 within 4 s real")
	# --- restart во время «захвата»: камера и время возвращаются ---
	await _ticks(30)
	match_node.restart()
	await _await_fight()
	var cam2 := Camera3D.new()
	pg.add_child(cam2)
	match_node.capture_camera(cam2, "crit")
	match_node.request_time_scale(0.02, 5.0, "crit_freeze")
	await _frames(2)
	match_node.restart()
	await _frames(1)
	_check("cam_restart_restores", is_equal_approx(Engine.time_scale, 1.0) and match_node.camera_owner() == ""
		and get_viewport().get_camera_3d() == match_node.game_camera() and match_node.time_scale_tags().is_empty(),
		[Engine.time_scale, match_node.camera_owner(), get_viewport().get_camera_3d() == match_node.game_camera()], [1.0, "", true])
	cam2.queue_free()
	cam.queue_free()
	# --- удар о стену без урона ---
	await _await_fight()
	await _slam_run()


## Крит через настоящий on_hit: tier crit, ЦМ в [5.5, 7.5] × sd, клэмп 7.5 в окне, после окна — FLIGHT_MAX_SPEED. Возвращает |v_ЦМ| после.
func _crit_run(p1: Doll, p2: Doll, tag: String) -> float:
	match_node.fight_time = maxf(match_node.fight_time, 6.0)
	# жертва ~2.3 м от правой стены Void: крит-полёт (дамп 1.0) доходит до стены быстрее HITFX_SLAM_SPEED
	var shift := CRIT_WALL_GAP_X - p2.torso().global_position.x
	for b in p2.parts.values():
		(b as RigidBody3D).global_position += Vector3(shift, 0.0, 0.0)
	await _ticks(20)
	var slams0 := slam_ctxs.size()
	var c := await _strike(p1, p2, 24.0)
	var t0 := p2._time
	var sp := _com_velocity(p2).length()
	var sd := float(c.get("sd_mult", 1.0))
	_check("hit_crit_tier_" + tag, String(c.get("tier", "")) == "crit" and float(c.get("score", 0.0)) >= Tuning.CRIT_SCORE, [c.get("tier", ""), c.get("score", 0.0)], "crit")
	_check("hit_crit_launch_" + tag, sp >= Tuning.CRIT_LAUNCH_MIN_SPEED * sd - 1e-3 and sp <= Tuning.CRIT_FLIGHT_MAX_SPEED * sd + 1e-3 and p2.flight_cap_active(),
		sp, "[%.1f, %.1f] × sd, flight_cap_active" % [Tuning.CRIT_LAUNCH_MIN_SPEED, Tuning.CRIT_FLIGHT_MAX_SPEED])
	# время — физическое (Doll._time): hit stop / замедление растягивают тики
	var mx := 0.0
	var n := 0
	while p2._time < t0 + 0.5 and n < 600:
		await _ticks(1)
		n += 1
		mx = maxf(mx, _com_velocity(p2).length())
	_check("hit_crit_cap_0_5s_" + tag, mx <= Tuning.CRIT_FLIGHT_MAX_SPEED * sd + 0.01, mx, "<= %.1f" % Tuning.CRIT_FLIGHT_MAX_SPEED)
	while p2._time < t0 + Tuning.CRIT_FLIGHT_S + 0.05 and n < 1200:
		await _ticks(1)
		n += 1
	var crit_slams := 0
	for i in range(slams0, slam_ctxs.size()):
		if (slam_ctxs[i] as Dictionary).get("doll") == p2 and bool((slam_ctxs[i] as Dictionary).get("crit_flight", false)):
			crit_slams += 1
	_check("slam_crit_flight_" + tag, crit_slams >= 1, crit_slams, ">= 1", "crit flight reaches the Void wall (env_slam ctx.crit_flight)")
	_check("hit_crit_window_over_" + tag, not p2.flight_cap_active(), p2.flight_cap_active(), false, "CRIT_FLIGHT_S passed — FLIGHT_MAX_SPEED again")
	report["info"]["crit_" + tag] = {"com_speed": sp, "max_0_5s": mx, "launch_dv": c.get("launch_dv", Vector3.ZERO), "slams": crit_slams}
	return sp


## Атакующий в рывке (6 м/с к жертве, тяга вперёд) бьёт крит в упор: скорость его ЦМ вдоль kb_dir сразу ≤ CRIT_ATTACKER_STOP_SPEED и
## не выше всё окно 0.5 с (физических), через 0.5 с между ЦМ ≥ 2 м. Без клэмпа атакующий догонял жертву (HIT_FX.md §10).
func _crit_attacker_run(p1: Doll, p2: Doll) -> void:
	match_node.fight_time = maxf(match_node.fight_time, 6.0)
	var vx := -1.5
	var gap := 1.1
	var sv := vx - p2.torso().global_position.x
	var sa := vx - gap - p1.torso().global_position.x
	for b in p2.parts.values():
		(b as RigidBody3D).global_position += Vector3(sv, 0.0, 0.0)
	for b in p1.parts.values():
		(b as RigidBody3D).global_position += Vector3(sa, 0.0, 0.0)
	await _ticks(2)
	for b in p1.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3(6.0, 0.0, 0.0)
	p1.dash_until = p1._time + Tuning.DASH_DURATION_S
	p1.input_vec = Vector2(1.0, 0.0)
	var c := await _strike(p1, p2, 24.0)
	var kb := Damage.knockback_dir(c.get("dir", Vector3.RIGHT) as Vector3)
	var along0 := _com_velocity(p1).dot(kb)
	var t0 := p1._time
	var mx := along0
	var n := 0
	while p1._time < t0 + 0.5 and n < 600:
		await _ticks(1)
		n += 1
		mx = maxf(mx, _com_velocity(p1).dot(kb))
	var along1 := _com_velocity(p1).dot(kb)
	var dist := (p2.centre_of_mass() - p1.centre_of_mass()).length()
	p1.input_vec = Vector2.ZERO
	var cap := Tuning.CRIT_ATTACKER_STOP_SPEED + 0.05
	_check("hit_crit_attacker_tier", String(c.get("tier", "")) == "crit" and not p1.is_dashing(), [c.get("tier", ""), p1.is_dashing()], ["crit", false])
	_check("hit_crit_attacker_stop", along0 <= cap and mx <= cap and along1 <= cap, [along0, mx, along1], "<= %.1f m/s along kb_dir (at hit, max 0.5 s, at 0.5 s)" % Tuning.CRIT_ATTACKER_STOP_SPEED)
	_check("hit_crit_attacker_gap", dist >= 2.0, dist, ">= 2.0 m", "COM distance attacker-victim 0.5 s (physics) after the crit")
	report["info"]["crit_attacker"] = {"along_at_hit": along0, "along_max_0_5s": mx, "along_0_5s": along1, "dist_0_5s": dist}


## FxPreset: reduced/off пишут значения в HitFxDirector; при off нет вспышек, инверсий, кинематографа и стоп-кадров/замедлений
## (heavy_stop, крит, старый hit stop), крит-отлёт (баланс) остаётся, KO slow-mo — тоже. В конце — снова full.
func _preset_checks(p1: Doll, p2: Doll) -> void:
	var dir := match_node.get_node_or_null("HitFxDirector")
	var tree := get_tree()
	FxPreset.set_preset("reduced", tree)
	var got_r: Array = [dir.get("flash_intensity"), dir.get("shake_intensity"), dir.get("impact_frames"), dir.get("crit_cinematic")] if dir != null else []
	_check("preset_reduced_applied", dir != null and got_r == [0.4, 0.5, false, false], got_r, [0.4, 0.5, false, false], "HitFxDirector var after FxPreset.set_preset")
	FxPreset.set_preset("off", tree)
	var got_o: Array = [dir.get("flash_intensity"), dir.get("shake_intensity"), dir.get("impact_frames"), dir.get("crit_cinematic")] if dir != null else []
	_check("preset_off_applied", dir != null and got_o == [0.0, 0.0, false, false] and not FxPreset.time_fx(), got_o, [0.0, 0.0, false, false])
	var st0: Dictionary = (dir.get("stats") as Dictionary).duplicate() if dir != null else {}
	# heavy без hit stop
	match_node.fight_time = 1.0
	var c_h := await _strike(p1, p2, 12.0)
	_check("preset_off_heavy_no_stop", String(c_h.get("tier", "")) == "heavy" and match_node.time_scale_tags().is_empty() and is_equal_approx(Engine.time_scale, 1.0),
		[c_h.get("tier", ""), match_node.time_scale_tags(), Engine.time_scale], ["heavy", [], 1.0])
	await _ticks(30)
	# крит: отлёт есть, стоп-кадра/замедления/ката нет
	match_node.fight_time = maxf(match_node.fight_time, 10.0)
	match_node.hit_tiers.force_next = "crit"
	var c_c := await _strike(p1, p2, 24.0)
	var ts_min := Engine.time_scale
	var tags: Array = match_node.time_scale_tags().duplicate()
	for i in range(30):
		await _frames(1)
		ts_min = minf(ts_min, Engine.time_scale)
		for tg in match_node.time_scale_tags():
			if not tags.has(tg):
				tags.append(tg)
	var dv: Vector3 = c_c.get("launch_dv", Vector3.ZERO)
	_check("preset_off_crit_no_time", String(c_c.get("tier", "")) == "crit" and is_equal_approx(ts_min, 1.0) and tags.is_empty(),
		[c_c.get("tier", ""), ts_min, tags], ["crit", 1.0, []], "30 frames after a forced crit")
	_check("preset_off_crit_launch_kept", dv.length() > 0.1 or _com_velocity(p2).length() >= Tuning.CRIT_LAUNCH_MIN_SPEED - 0.5, dv.length(), "> 0 (balance, not presentation)")
	# старый hit_feel: без hit stop
	match_node.hit_feel(30.0, p2.centre_of_mass())
	_check("preset_off_hit_feel_no_stop", is_equal_approx(Engine.time_scale, 1.0), Engine.time_scale, 1.0, "Match.hit_feel(30 HP)")
	if dir != null:
		var st1: Dictionary = dir.get("stats")
		var d_fl := int(st1["flashes"]) - int(st0.get("flashes", 0))
		var d_if := int(st1["impact_frames"]) - int(st0.get("impact_frames", 0))
		var d_ci := int(st1["cinematic"]) - int(st0.get("cinematic", 0))
		var d_pu := int(st1["punches"]) - int(st0.get("punches", 0))
		_check("preset_off_no_flashes", d_fl == 0 and d_if == 0 and d_ci == 0 and d_pu == 0, [d_fl, d_if, d_ci, d_pu], [0, 0, 0, 0],
			"HitFxDirector.stats flashes / impact_frames / cinematic / punches during heavy + crit")
	else:
		_check("preset_off_no_flashes", false, "no HitFxDirector", "director under Match")
	# KO: slow-mo остаётся
	await _ticks(30)
	p2.hp = 5.0
	var c_k := await _strike(p1, p2, 12.0)
	var ts_ko := Engine.time_scale
	_check("preset_off_ko_slowmo", bool(c_k.get("is_ko", false)) and ts_ko <= Tuning.KO_SLOWMO_SCALE + 1e-3, [c_k.get("tier", ""), ts_ko], ["ko", "<= %.2f" % Tuning.KO_SLOWMO_SCALE])
	FxPreset.set_preset("full", tree)
	var got_f: Array = [dir.get("flash_intensity"), dir.get("shake_intensity"), dir.get("impact_frames"), dir.get("crit_cinematic")] if dir != null else []
	_check("preset_full_restored", FxPreset.current == "full" and got_f == [Tuning.HITFX_FLASH_INTENSITY, Tuning.HITFX_SHAKE_INTENSITY, Tuning.HITFX_IMPACT_FRAMES,
		Tuning.HITFX_CRIT_CINEMATIC], got_f, "Tuning.HITFX_* defaults")
	var wait := 0
	while (Engine.time_scale < 1.0 or not match_node.time_scale_tags().is_empty()) and wait < 240:
		await _frames(1)
		wait += 1


func _slam_run() -> void:
	var ds := _pair()
	var p2: Doll = ds[1]
	p2.control_enabled = false   # без тяги нет клэмпа MAX_MOVE_SPEED торса
	var wall_x := 7.0
	var shift := wall_x - 1.6 - p2.torso().global_position.x
	for b in p2.parts.values():
		(b as RigidBody3D).global_position += Vector3(shift, 0.0, 0.0)
	await _ticks(2)
	var slams0 := slam_ctxs.size()
	var cnt0 := match_node.env_slam_count
	var fx0 := fx_ctxs.size()
	var hp0 := p2.hp
	for b in p2.parts.values():
		(b as RigidBody3D).linear_velocity = Vector3(8.0, 0.0, 0.0)
	await _ticks(60)
	var mine: Array = []
	for i in range(slams0, slam_ctxs.size()):
		if (slam_ctxs[i] as Dictionary).get("doll") == p2:
			mine.append(slam_ctxs[i])
	var miss: Array = []
	if not mine.is_empty():
		for k in SLAM_KEYS:
			if not (mine[0] as Dictionary).has(k):
				miss.append(k)
	_check("slam_wall", mine.size() >= 1 and mine.size() <= 2 and match_node.env_slam_count - cnt0 == mine.size(), mine.size(), "1 (≤ 2)",
		"speed %s" % str(mine.map(func(x: Dictionary) -> float: return snappedf(float(x["speed"]), 0.01))))
	_check("slam_no_damage", is_equal_approx(p2.hp, hp0) and is_equal_approx(p2.hp, Tuning.MAX_HP) and fx_ctxs.size() == fx0, [p2.hp, fx_ctxs.size() - fx0], [100.0, 0])
	_check("slam_ctx_complete", not mine.is_empty() and miss.is_empty() and float((mine[0] as Dictionary)["speed"]) >= Tuning.HITFX_SLAM_SPEED,
		miss, [], "doll, part, speed ≥ HITFX_SLAM_SPEED, position, normal, flying, crit_flight, fight_time")
	p2.control_enabled = true


# ------------------------------------------------------------------ частота крита (боты)

func _rush(d: Doll, other: Doll) -> void:
	if d == null or other == null or not d.alive or not other.alive:
		return
	var dc := d.centre_of_mass()
	var oc := other.centre_of_mass()
	var dx := oc.x - dc.x
	var dy := oc.y - dc.y
	var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
	var vy := clampf(dy / 1.5, -1.0, 1.0) if absf(dy) > 0.8 else 0.0
	# как match_probe (HIT_FX §11.6): чётная попытка — вверх и через препятствие к сопернику, нечётная — врозь
	if t - last_hit_t > STUCK_S and t > unstick_until + STUCK_S:
		unstick_until = t + UNSTICK_S
		unstick_n += 1
	if t < unstick_until:
		var first_half := t < unstick_until - UNSTICK_S * 0.5
		if unstick_n % 2 == 0:
			d.input_vec = Vector2(sgn * 0.35, 1.0) if first_half else Vector2(sgn, 0.3)
		else:
			d.input_vec = Vector2(-sgn, 1.0 if first_half else -1.0)
		return
	var until := float(rush_retreat.get(d, -1.0))
	if t < until:
		d.input_vec = Vector2(-sgn, 0.0)
	elif absf(dx) < RUSH_NEAR and absf(dy) < 1.2:
		rush_retreat[d] = t + RUSH_RETREAT_S
		d.input_vec = Vector2(-sgn, 0.0)
	else:
		if absf(dx) > DASH_FROM_M and d._time >= d.dash_ready_at and not d.is_stunned():
			d.dash_until = d._time + Tuning.DASH_DURATION_S
			d.dash_ready_at = d._time + Tuning.DASH_COOLDOWN_S
		d.input_vec = Vector2(sgn, vy)


func _freq_checks() -> void:
	print("--- crit frequency (bots) ---")
	var scenes: Array = String(cfg["freq"]).split("+", false)
	var total_fight := 0.0
	var tiers: Dictionary = {}
	for k in TIERS:
		tiers[k] = 0
	var crit_events: Array = []   # {scene, match, t, tier, attacker, score, damage}
	var all_hits: Array = []      # [scene, match, t, damage, score, eligible, tier, kind, attacker, double_blow, is_ko, part, dash, combo, weapon_id, crit_block]
	var slams := 0
	var env_hits := 0
	var per_scene: Dictionary = {}
	fly_max_normal = 0.0
	fly_max_crit = 0.0
	var runs: Array = []
	for sd in String(cfg["seeds"]).split("+", false):
		for sid in scenes:
			runs.append([int(sd), sid])
	for run in runs:
		var sid: String = run[1]
		if not SCENES.has(sid):
			continue
		seed(int(run[0]))   # частота — статистика: два сида × матчи, чтобы один хаотичный бой не решал
		hit_kinds.clear()
		fx_ctxs.clear()
		slam_ctxs.clear()
		await _load_scene(sid)
		match_node.crit_enabled = bool(cfg["crit"])   # crit=0 — распределение ударов без крит-отлёта (калибровка порога)
		var fight_sum := 0.0
		var match_i := 0
		var ticks := 0
		var max_ticks := int(float(cfg["freq_s"]) * 60.0 * 4.0 * float(cfg["matches"]))
		var ko_wait := -1
		var fx_seen := 0
		var capped := 0
		while match_i < int(cfg["matches"]) and ticks < max_ticks:
			await _ticks(1)
			ticks += 1
			# матч до KO, как match_probe и калибровка 29.09; без KO за freq_s боя — следующий матч
			if match_node.combat_active() and match_node.fight_time >= float(cfg["freq_s"]):
				capped += 1
				fight_sum += match_node.fight_time
				match_i += 1
				rush_retreat.clear()
				match_node.restart()
				last_hit_t = t
				continue
			var ds := _pair()
			if ds.size() < 2:
				continue
			for i in range(fx_seen, fx_ctxs.size()):
				var c: Dictionary = fx_ctxs[i]
				tiers[c["tier"]] = int(tiers.get(c["tier"], 0)) + 1
				all_hits.append(["%s@%d" % [sid, int(run[0])], match_i, snappedf(float(c["fight_time"]), 0.01), snappedf(float(c["damage"]), 0.01), snappedf(float(c["score"]), 0.01),
					1 if HitTier.eligible(c) else 0, c["tier"], c["kind"], (c["attacker"] as Doll).player_index if is_instance_valid(c["attacker"]) and c["attacker"] is Doll else -1,
					1 if bool(c["double_blow"]) else 0, 1 if bool(c["is_ko"]) else 0, String(c["part"]), 1 if bool(c["dash"]) else 0, int(c["combo"]),
					String(c.get("weapon_id", "")), String(c.get("crit_block", ""))])
				if c["tier"] == "crit" or c["tier"] == "ko_crit":
					var att: Variant = c["attacker"]
					crit_events.append({"scene": "%s@%d" % [sid, int(run[0])], "match": match_i, "t": float(c["fight_time"]), "tier": c["tier"],
						"attacker": (att as Doll).player_index if att is Doll and is_instance_valid(att) else -1,
						"score": snappedf(float(c["score"]), 0.01), "damage": snappedf(float(c["damage"]), 0.01), "kind": c["kind"], "part": c["part"],
						"drought": float(c["score"]) < Tuning.CRIT_SCORE, "stylish": HitTier.stylish(c), "bypass": bool(c.get("crit_bypass", false))})
			fx_seen = fx_ctxs.size()
			if match_node.combat_active():
				_rush(ds[0], ds[1])
				_rush(ds[1], ds[0])
				ko_wait = -1
			else:
				for d in ds:
					(d as Doll).input_vec = Vector2.ZERO
				if match_node.phase == Match.Phase.OVER:
					if ko_wait < 0:
						ko_wait = 90
					ko_wait -= 1
					if ko_wait == 0:
						fight_sum += match_node.fight_time
						match_i += 1
						rush_retreat.clear()
						match_node.restart()
						last_hit_t = t
		total_fight += fight_sum
		slams += match_node.env_slam_count
		env_hits += int(hit_kinds.get("environment", 0))
		per_scene["%s@%d" % [sid, int(run[0])]] = {"fight_s": snappedf(fight_sum, 0.01), "matches": match_i, "capped": capped, "env_slam": match_node.env_slam_count,
			"hits": hit_kinds.duplicate()}
		print("  %s seed %d: fight %.1f s, %d matches (%d without KO in %.0f s), env_slam %d" % [sid, int(run[0]), fight_sum, match_i, capped, float(cfg["freq_s"]), match_node.env_slam_count])
	var n_crit := 0
	var hits_total := 0
	for k in tiers.keys():
		hits_total += int(tiers[k])
	for e in crit_events:
		n_crit += 1
	var per_crit := total_fight / float(n_crit) if n_crit > 0 else INF
	report["info"]["freq"] = {"scenes": per_scene, "fight_s": snappedf(total_fight, 0.01), "tiers": tiers, "crits": crit_events,
		"hits": all_hits, "fly_max_normal": fly_max_normal, "fly_max_crit": fly_max_crit, "fly_samples": [fly_normal_samples, fly_crit_samples]}
	_check("freq_crit_period", per_crit >= 25.0 and per_crit <= 45.0, per_crit if n_crit > 0 else -1.0, "25–45 s per crit",
		"%d crit+ko_crit in %.1f s fight" % [n_crit, total_fight])
	# v2 (HIT_FX.md §11.1): крит честный — ни одного слабее CRIT_MIN_DAMAGE, выданных засухой (score < CRIT_SCORE) не больше 20 %
	var min_dmg := INF
	var n_drought := 0
	for e in crit_events:
		min_dmg = minf(min_dmg, float(e["damage"]))
		if bool(e["drought"]):
			n_drought += 1
	_check("freq_crit_min_damage", n_crit == 0 or min_dmg >= Tuning.CRIT_MIN_DAMAGE - 1e-3, min_dmg if n_crit > 0 else -1.0, ">= %.0f HP" % Tuning.CRIT_MIN_DAMAGE)
	var drought_share := float(n_drought) / float(maxi(n_crit, 1))
	_check("freq_crit_drought_share", drought_share <= 0.2, drought_share, "<= 0.20", "%d of %d crits below CRIT_SCORE (drought, stylish only)" % [n_drought, n_crit])
	# зазоры: обычный crit — ≥ 8 с от прошлого crit (атакующего — ≥ 15 с); v3 обход (crit_bypass) — ≥ CRIT_BYPASS_GAP_S от любого прошлого
	var gap_min := INF
	var gap_att_min := INF
	var ko_gap_min := INF
	var bypass_gap_min := INF
	var n_bypass := 0
	for i in range(crit_events.size()):
		var e: Dictionary = crit_events[i]
		if bool(e["bypass"]):
			n_bypass += 1
		for j in range(i):
			var p: Dictionary = crit_events[j]
			if p["scene"] != e["scene"] or p["match"] != e["match"]:
				continue
			var gap := float(e["t"]) - float(p["t"])
			if e["tier"] == "crit" and bool(e["bypass"]):
				bypass_gap_min = minf(bypass_gap_min, gap)
			elif e["tier"] == "crit" and p["tier"] == "crit":
				gap_min = minf(gap_min, gap)
				if p["attacker"] == e["attacker"]:
					gap_att_min = minf(gap_att_min, gap)
			if e["tier"] == "ko_crit":
				ko_gap_min = minf(ko_gap_min, gap)
	_check("freq_crit_gap", gap_min >= Tuning.CRIT_COOLDOWN_S - 1e-6, gap_min if gap_min < INF else -1.0, ">= 8.0 s (-1 = one crit per match)", "crits without bypass")
	_check("freq_crit_gap_attacker", gap_att_min >= Tuning.CRIT_ATTACKER_COOLDOWN_S - 1e-6, gap_att_min if gap_att_min < INF else -1.0, ">= 15.0 s", "crits without bypass")
	_check("freq_crit_bypass_gap", bypass_gap_min >= Tuning.CRIT_BYPASS_GAP_S - 1e-6, bypass_gap_min if bypass_gap_min < INF else -1.0, ">= %.1f s" % Tuning.CRIT_BYPASS_GAP_S,
		"%d crits through the cooldown (crushing: damage ≥ %.0f HP or score ≥ %.0f)" % [n_bypass, Tuning.CRIT_BYPASS_DAMAGE, Tuning.CRIT_BYPASS_SCORE])
	_check("freq_ko_crit_gap", ko_gap_min >= Tuning.CRIT_KO_GAP_S - 1e-6, ko_gap_min if ko_gap_min < INF else -1.0, ">= 2.0 s")
	# v3 (HIT_FX.md §12.4): мощный удар не теряется — ни один удар ≥ CRIT_BYPASS_DAMAGE (или score ≥ CRIT_BYPASS_SCORE) не остался heavy
	# только из-за кулдаунов 8 / 15 с (ctx.crit_block cooldown / attacker_cooldown). Остальные причины — в info.freq.power.
	var power := {"hits": 0, "tiers": {}, "blocks": {}, "lost": []}
	var dist := {"crit": {}, "heavy": {}}
	var bins := [[9.0, "9-14"], [14.0, "14-18"], [18.0, "18-25"], [25.0, "25-30"], [30.0, "30+"]]
	for hrow in all_hits:
		var dmg := float(hrow[3])
		var sc := float(hrow[4])
		var tr := String(hrow[6])
		var blk := String(hrow[15])
		var key := ""
		for bn in bins:
			if dmg >= float(bn[0]):
				key = String(bn[1])
		var dk := "crit" if tr == "crit" or tr == "ko_crit" else tr
		if dist.has(dk) and key != "":
			(dist[dk] as Dictionary)[key] = int((dist[dk] as Dictionary).get(key, 0)) + 1
		if dmg < Tuning.CRIT_BYPASS_DAMAGE and sc < Tuning.CRIT_BYPASS_SCORE:
			continue
		power["hits"] = int(power["hits"]) + 1
		(power["tiers"] as Dictionary)[tr] = int((power["tiers"] as Dictionary).get(tr, 0)) + 1
		var why := blk
		var could := int(hrow[5]) == 1 or (int(hrow[9]) == 1 and Tuning.CRIT_KINDS.has(String(hrow[7])) and int(hrow[8]) >= 0)   # eligible(ctx, true)
		if tr == "heavy" and why == "":
			why = "?" if could else "not_eligible"
		if why != "":
			(power["blocks"] as Dictionary)[why] = int((power["blocks"] as Dictionary).get(why, 0)) + 1
		# потерян: heavy не из-за зазора кинематографа (bypass_gap) и не из-за правил (kind / self) — кулдаун 8 / 15 с, MIN_FIGHT, DOUBLE BLOW
		if tr == "heavy" and could and blk != "bypass_gap":
			(power["lost"] as Array).append(hrow)
	report["info"]["freq"]["power"] = power
	report["info"]["freq"]["damage_dist"] = dist
	report["info"]["freq"]["bypass"] = n_bypass
	_check("freq_crit_power_lost", (power["lost"] as Array).is_empty(), (power["lost"] as Array).size(), 0,
		"heavy hits ≥ %.0f HP / score ≥ %.0f lost to the 8 / 15 s cooldowns, MIN_FIGHT or DOUBLE BLOW (of %d such hits: tiers %s, blocks %s)"
		% [Tuning.CRIT_BYPASS_DAMAGE, Tuning.CRIT_BYPASS_SCORE, int(power["hits"]), str(power["tiers"]), str(power["blocks"])])
	var heavy_share := float(tiers["heavy"]) / float(maxi(hits_total, 1))
	_check("freq_heavy_share", heavy_share >= 0.08 and heavy_share <= 0.20, heavy_share, "0.08–0.20 (target 10–15 %)", "tiers %s" % str(tiers))
	_check("freq_env_hits", env_hits == 0, env_hits, 0, "kind environment hits (ENV_DAMAGE_ENABLED = false)")
	_check("freq_env_slam", slams > 0, slams, "> 0")
	_check("freq_normal_flight", fly_max_normal <= Tuning.FLIGHT_MAX_SPEED + 0.01, fly_max_normal, "<= %.1f" % Tuning.FLIGHT_MAX_SPEED,
		"COM speed of flying dolls outside crit flight, held 2 ticks (after Doll._cap_flight_speed)")
	_check("freq_crit_flight", fly_max_crit <= Tuning.CRIT_FLIGHT_MAX_SPEED * Damage.sd_knockback_mult(maxi(match_node.sd_step, 0)) + 0.01, fly_max_crit,
		"<= %.1f × sd" % Tuning.CRIT_FLIGHT_MAX_SPEED)


# ------------------------------------------------------------------ итог

func _finish() -> void:
	Engine.time_scale = 1.0
	var fails := 0
	for c in report["checks"]:
		if not bool(c["ok"]):
			fails += 1
	report["info"]["godot"] = Engine.get_version_info()["string"]
	var js := JSON.stringify(report, "  ", false)
	var f := FileAccess.open(ProjectSettings.globalize_path(String(cfg["out"])), FileAccess.WRITE)
	if f != null:
		f.store_string(js)
		f.close()
	print("=== hitfx_core_probe: %d checks, %d failed → %s ===" % [report["checks"].size(), fails, "OK" if report["ok"] else "FAIL"])
	get_tree().quit(0 if report["ok"] else 1)
