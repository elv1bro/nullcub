## ДРАЙВ — пресет боя «импульс живёт» (docs/plan-demo/DRIVE.md, автор 02.10: «бой сухой, нет драйва как в тех играх и в JS»).
## Одна клавиша J (или кнопка в панели Tab) включает сразу всё, что разбор 02.10 нашёл причиной «сухости»; выключен — игра как раньше:
## каждая функция ниже без ДРАЙВА возвращает прежнюю константу Tuning, гейты и пробы не меняются.
##   • физика: гравитация на куклах × DRIVE_GRAVITY_MULT (gravity_scale частей), меньше дамп управляемого хода, тормоз без ввода
##     (кукла висит, а не оседает), лёгкий дамп полёта после удара — скорость живёт ~1.5 с вместо 0.55;
##   • удар: отброс ∝ урону (3 HP ≈ 2 м/с ЦМ, 30 HP ≈ 12 м/с), больше импульса в ударенную часть, атакующий отскакивает и почти сразу
##     управляет; размен решает сила: встречный удар слабее в DRIVE_TRADE_WIN_RATIO раз — × DRIVE_TRADE_LOSER_MULT (DollCombat);
##   • отклик: свой вариант замедления (HitJuice.variant), heavy ниже порогом, криты чаще и дальше, толчок кадра на каждый удар;
##   • камера купола держит обоих, пока соперник ближе DRIVE_FRAME_BOTH_M; бот кампании давит зигзагом без отхода;
##   • вариант управления ТЕЛО → ГОЛОВА-ТАРАН (если был ТЕЛО), выключили — обратно.
## Состояние общее на все площадки (как ControlFeel), сохраняется вместе с ним в user://control_feel.cfg (только из панели).
## Doll сверяет ControlFeel.rev — смена ДРАЙВА поднимает rev, куклы пересчитывают дамп и gravity_scale на ходу.
class_name Drive
extends RefCounted

static var on: bool = Tuning.DRIVE_DEFAULT
## Вариант, который ДРАЙВ сам поставил при включении (чтобы вернуть ТЕЛО при выключении, если игрок его не менял).
static var _set_variant := ""
## Счётчики для проб (DollCombat): сколько разменов решила сила.
static var stats := {"trades": 0, "trade_cut": 0, "head_soft": 0}


static func set_on(v: bool) -> void:
	if v == on:
		return
	on = v
	if on:
		if ControlFeel.variant == "body":
			ControlFeel.set_variant(Tuning.DRIVE_VARIANT)
			_set_variant = Tuning.DRIVE_VARIANT
	elif _set_variant != "" and ControlFeel.variant == _set_variant:
		ControlFeel.set_variant("body")
		_set_variant = ""
	else:
		_set_variant = ""
	ControlFeel.bump()


static func toggle() -> bool:
	set_on(not on)
	return on


static func title() -> String:
	return TranslationServer.translate("ДРАЙВ") + ": " + TranslationServer.translate("вкл" if on else "выкл")


static func reset_stats() -> void:
	stats = {"trades": 0, "trade_cut": 0, "head_soft": 0}


# --- физика куклы (Doll) ---

static func gravity_scale() -> float:
	return Tuning.DRIVE_GRAVITY_MULT if on else 1.0


static func move_damp_mult() -> float:
	return Tuning.DRIVE_MOVE_DAMP_MULT if on else 1.0


static func brake_damp() -> float:
	return Tuning.DRIVE_BRAKE_DAMP if on else Tuning.IDLE_BRAKE_DAMP


static func flight_damp(core: bool) -> float:
	if on:
		return Tuning.DRIVE_FLIGHT_DAMP_CORE if core else Tuning.DRIVE_FLIGHT_DAMP_LIMB
	return Tuning.FLIGHT_LINEAR_DAMP if core else Tuning.FLIGHT_LIMB_LINEAR_DAMP


static func flight_max_speed() -> float:
	return Tuning.DRIVE_FLIGHT_MAX_SPEED if on else Tuning.FLIGHT_MAX_SPEED


static func kb_torso_share() -> float:
	return Tuning.DRIVE_KB_TORSO_SHARE if on else Tuning.KNOCKBACK_TORSO_SHARE


# --- удар (DollCombat) ---

## Импульс отброса жертве (Н·с) по урону; sd — множитель Sudden Death.
static func knockback_impulse(damage: float, sd: float = 1.0) -> float:
	if not on:
		return Damage.knockback_impulse(damage, sd)
	if damage <= 0.0:
		return 0.0
	return clampf((Tuning.DRIVE_KB_BASE + damage * Tuning.DRIVE_KB_PER_HP) * sd, 0.0, Tuning.DRIVE_KB_MAX * maxf(sd, 1.0))


static func knockback_min() -> float:
	return Tuning.DRIVE_KB_MIN if on else Tuning.KNOCKBACK_MIN


static func recoil() -> float:
	return Tuning.DRIVE_RECOIL if on else Tuning.HIT_ATTACKER_RECOIL


static func thrust_lock_s() -> float:
	return Tuning.DRIVE_THRUST_LOCK_S if on else Tuning.HIT_ATTACKER_THRUST_LOCK_S


# --- уровни удара, крит (HitTier, CritLaunch) ---

static func heavy_score() -> float:
	return Tuning.DRIVE_HEAVY_SCORE if on else Tuning.HITFX_HEAVY_SCORE


static func crit_cooldown_s() -> float:
	return Tuning.DRIVE_CRIT_COOLDOWN_S if on else Tuning.CRIT_COOLDOWN_S


static func crit_attacker_cooldown_s() -> float:
	return Tuning.DRIVE_CRIT_ATTACKER_COOLDOWN_S if on else Tuning.CRIT_ATTACKER_COOLDOWN_S


static func crit_launch_min_speed() -> float:
	return Tuning.DRIVE_CRIT_LAUNCH_MIN_SPEED if on else Tuning.CRIT_LAUNCH_MIN_SPEED


static func crit_flight_max_speed() -> float:
	return Tuning.DRIVE_CRIT_FLIGHT_MAX_SPEED if on else Tuning.CRIT_FLIGHT_MAX_SPEED


# --- отклик (Match, HitJuice, HitFxDirector) ---

static func shake_mult() -> float:
	return Tuning.DRIVE_SHAKE_MULT if on else 1.0


static func heavy_kick_mult() -> float:
	return Tuning.DRIVE_HEAVY_KICK_MULT if on else 1.0


## Толчок кадра в сторону удара (только ДРАЙВ): camera — DynamicCamera, ctx — Match.make_hit_ctx + tier.
static func camera_kick(camera: Node, ctx: Dictionary, shake_k: float) -> void:
	if not on or camera == null or not camera.has_method("kick") or shake_k <= 0.0:
		return
	var dmg := float(ctx.get("damage", 0.0))
	if dmg < Tuning.DRIVE_KICK_MIN_DAMAGE or String(ctx.get("tier", "")) != HitTier.LIGHT:
		return   # heavy / crit / ko толкает HitFxDirector (× heavy_kick_mult)
	var dir: Vector3 = ctx.get("dir", Vector3.RIGHT)
	var hh := float(camera.get("half_height")) if camera.get("half_height") != null else 2.4
	var k := clampf(dmg / 10.0, 0.4, 2.0)
	camera.call("kick", Vector2(dir.x, dir.y), Tuning.DRIVE_KICK_FRAC * hh * k * shake_k, Tuning.DRIVE_KICK_S)


# --- бот-соперник (RivalBrain) ---

static func rival_retreat_s(base: float) -> float:
	return minf(base, Tuning.DRIVE_RIVAL_RETREAT_S) if on else base
