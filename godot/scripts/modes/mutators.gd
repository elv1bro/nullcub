## Модификаторы режимов (docs/plan-demo/MODES_100.md, 08.10): именованные правки любой площадки с Match. Каждый — запись CATALOG:
##   name / desc — русские строки для tr(); group — поле / кукла / время / предметы / боты / кадр;
##   apply(ctx, args)      — один раз, когда площадка и Match в дереве (ModeRun._attach);
##   on_doll(ctx, args, d) — на каждую куклу: при apply и на Match.doll_replaced (возрождение, R — заново);
##   on_fight(ctx, args)   — на phase_changed(FIGHT): после reset_for_match и PartHp (запас, мышцы);
##   on_hit(ctx, args, victim, attacker, dmg, kind, pos) — на Match.hit;
##   tick(ctx, args, dt)   — каждый кадр, пока Match.combat_active();
##   exit(ctx, args)       — при уходе со сцены (вернуть статики: JointBreak / PartHp / Stasis / зум / гравитацию мира).
## Контекст ctx — ModeCtx (scripts/modes/mode_ctx.gd): mt, scene, arena, field, dolls(), rng, state (словарь модификатора).
## Числа — Tuning.MODES_* (блок в конце tuning.gd).
class_name Mutators
extends RefCounted

const CATALOG := {
	# --- поле ---
	"g_zero": {"name": "Невесомость", "desc": "Гравитации нет", "group": "поле", "apply": "_g_set", "g": 0.0, "dir": Vector2(0, -1)},
	"g_light": {"name": "Лёгкое поле", "desc": "Гравитация ×0.5", "group": "поле", "apply": "_g_set", "g": 0.5, "dir": Vector2(0, -1)},
	"g_heavy": {"name": "Тяжёлое поле", "desc": "Гравитация ×2.5", "group": "поле", "apply": "_g_set", "g": 2.5, "dir": Vector2(0, -1)},
	"g_side": {"name": "Поле вбок", "desc": "«Низ» — справа", "group": "поле", "apply": "_g_set", "g": 1.0, "dir": Vector2(1, 0)},
	"g_up": {"name": "Поле вверх", "desc": "Гравитация вверх", "group": "поле", "apply": "_g_set", "g": 1.0, "dir": Vector2(0, 1)},
	"g_swing": {"name": "Качели", "desc": "Поле качается влево-вправо", "group": "поле", "apply": "_g_mark", "tick": "_g_swing_tick", "period_s": 6.0},
	"g_random": {"name": "Рулетка поля", "desc": "Поле меняется случайно", "group": "поле", "apply": "_g_mark", "tick": "_g_random_tick", "period_s": 8.0},
	"g_pulse": {"name": "Пульс", "desc": "Гравитация бьётся: ноль — двойная", "group": "поле", "apply": "_g_mark", "tick": "_g_pulse_tick", "period_s": 2.0},
	# --- кукла ---
	"fast": {"name": "Турбо", "desc": "Тяга ×1.5", "group": "кукла", "on_doll": "_fast", "mult": 1.5},
	"slow": {"name": "Сироп", "desc": "Тяга ×0.6", "group": "кукла", "on_doll": "_fast", "mult": 0.6},
	"glass": {"name": "Стекло", "desc": "Запас 30", "group": "кукла", "on_fight": "_hp_set", "on_doll": "_hp_doll", "hp": 30.0},
	"tank": {"name": "Танк", "desc": "Запас 300", "group": "кукла", "on_fight": "_hp_set", "on_doll": "_hp_doll", "hp": 300.0},
	"one_hit": {"name": "Один удар", "desc": "Любой удар — нокаут", "group": "кукла", "on_hit": "_one_hit"},
	"shove_only": {"name": "Только толчки", "desc": "Урона нет", "group": "кукла", "on_doll": "_shove_only"},
	"double_damage": {"name": "Двойной урон", "desc": "Урон ×2", "group": "кукла", "apply": "_damage_mult", "mult": 2.0},
	"half_damage": {"name": "Половина урона", "desc": "Урон ×0.5", "group": "кукла", "apply": "_damage_mult", "mult": 0.5},
	"vampire": {"name": "Вампир", "desc": "Удар лечит бьющего", "group": "кукла", "on_hit": "_vampire", "share": 0.5},
	"regen": {"name": "Регенерация", "desc": "Запас восстанавливается", "group": "кукла", "tick": "_regen_tick", "per_s": 4.0},
	"feather": {"name": "Пёрышки", "desc": "Отброс ×2", "group": "кукла", "apply": "_knockback_mult", "mult": 2.0},
	"anchor": {"name": "Якоря", "desc": "Отброс ×0.4", "group": "кукла", "apply": "_knockback_mult", "mult": 0.4},
	"drunk": {"name": "Пьяные", "desc": "Мышцы ×0.4", "group": "кукла", "on_fight": "_drunk", "mult": 0.4},
	"spinner": {"name": "Волчки", "desc": "Раскрутка ×2", "group": "кукла", "on_doll": "_spinner", "mult": 2.0},
	"brittle": {"name": "Хрупкие суставы", "desc": "Прочность суставов включена", "group": "кукла", "apply": "_brittle", "exit": "_restore_hp_mode"},
	"iron": {"name": "Железные", "desc": "Ничего не отлетает, запас 100", "group": "кукла", "apply": "_iron", "exit": "_restore_hp_mode"},
	# --- время ---
	"blitz": {"name": "Блиц", "desc": "60 секунд", "group": "время", "apply": "_time_limit", "limit_s": 60.0},
	"marathon": {"name": "Марафон", "desc": "10 минут", "group": "время", "apply": "_time_limit", "limit_s": 600.0},
	"sudden_start": {"name": "Сразу Sudden Death", "desc": "Sudden Death с первой секунды", "group": "время", "apply": "_time_limit", "limit_s": 0.0},
	"slowmo": {"name": "Замедление", "desc": "Время ×0.6", "group": "время", "apply": "_time_scale", "scale": 0.6},
	"hyper": {"name": "Гипер", "desc": "Время ×1.3", "group": "время", "apply": "_time_scale", "scale": 1.3},
	"stasis_on": {"name": "Стазис", "desc": "Время идёт, пока ты двигаешься", "group": "время", "apply": "_stasis", "exit": "_stasis_exit"},
	# --- предметы ---
	"barrels": {"name": "Бочки", "desc": "Взрывные бочки по арене", "group": "предметы", "apply": "_barrels", "n": 6},
	"barrel_rain": {"name": "Дождь из бочек", "desc": "Бочки падают сверху", "group": "предметы", "tick": "_barrel_rain_tick", "period_s": 5.0},
	"weapons": {"name": "Арсенал", "desc": "Оружие на полу", "group": "предметы", "apply": "_weapons", "on_doll": "_weapon_pickup"},
	"crates": {"name": "Ящики", "desc": "Ящики снабжения", "group": "предметы", "tick": "_crates_tick", "period_s": 12.0, "n": 3},
	# --- боты и люди ---
	"bots": {"name": "Боты", "desc": "Уровень ботов", "group": "боты", "apply": "_bots", "on_doll": "_bots_doll", "level": 2},
	"champion": {"name": "Чемпион лиги", "desc": "Боец лиги вместо P2", "group": "боты", "apply": "_champion"},
	"coop": {"name": "Вдвоём", "desc": "P2 — человек на стрелках", "group": "боты", "apply": "_coop"},
	# --- кадр ---
	"zoom_in": {"name": "Крупный план", "desc": "Камера ближе", "group": "кадр", "apply": "_zoom", "exit": "_zoom_exit", "zoom": 1.3},
	"zoom_out": {"name": "Общий план", "desc": "Камера дальше", "group": "кадр", "apply": "_zoom", "exit": "_zoom_exit", "zoom": 0.5},
}

const BARREL_SCENE := "res://scenes/props/scrap/prop_metal_barrel.tscn"
const WEAPON_IDS := ["hammer", "sword", "axe", "mace", "pan"]
const CRATE_KINDS := ["health", "health", "armor"]


static func has(id: String) -> bool:
	return CATALOG.has(id)


static func ids() -> Array:
	return CATALOG.keys()


static func label(id: String) -> String:
	var e: Dictionary = CATALOG.get(id, {})
	return TranslationServer.translate(String(e.get("name", id)))


## «Турбо · Бочки · Один удар» для карточки.
static func labels_line(mids: Array) -> String:
	var out: Array = []
	for m in mids:
		out.append(label(String(m)))
	return " · ".join(out)


## Подробно, строкой на модификатор: «Турбо — тяга ×1.5».
static func describe(muts: Array) -> String:
	var out: Array = []
	for m in muts:
		var id := String((m as Dictionary).get("id", ""))
		var e: Dictionary = CATALOG.get(id, {})
		if e.is_empty():
			continue
		var line := "%s — %s" % [TranslationServer.translate(String(e["name"])), TranslationServer.translate(String(e["desc"]))]
		var args: Dictionary = (m as Dictionary).get("args", {})
		if args.has("level"):
			line += " %d" % int(args["level"])
		out.append(line)
	return "\n".join(out)


## Аргументы модификатора: значения из CATALOG, поверх — args карточки.
static func merged_args(id: String, args: Dictionary) -> Dictionary:
	var out: Dictionary = (CATALOG.get(id, {}) as Dictionary).duplicate()
	for k in args:
		out[k] = args[k]
	return out


## Вызов крючка hook ("apply" | "on_doll" | …) модификатора id, если он есть.
static func call_hook(id: String, hook: String, ctx: ModeCtx, args: Dictionary, extra: Array = []) -> void:
	var e: Dictionary = CATALOG.get(id, {})
	var fn := String(e.get(hook, ""))
	if fn == "":
		return
	var all: Array = [ctx, args]
	all.append_array(extra)
	Callable(Mutators, fn).callv(all)


static func has_hook(id: String, hook: String) -> bool:
	return String((CATALOG.get(id, {}) as Dictionary).get(hook, "")) != ""


# ============================================================ поле

static func _g_set(ctx: ModeCtx, a: Dictionary) -> void:
	ctx.set_gravity(float(a["g"]), a["dir"], 0.0)


static func _g_mark(ctx: ModeCtx, _a: Dictionary) -> void:
	ctx.state["t"] = 0.0
	ctx.state["phase"] = 0


static func _g_swing_tick(ctx: ModeCtx, a: Dictionary, dt: float) -> void:
	var period := float(a["period_s"])
	var t := float(ctx.state.get("t", 0.0)) + dt
	ctx.state["t"] = t
	var ph := int(t / (period * 0.5)) % 2
	if ph != int(ctx.state.get("phase", -1)):
		ctx.state["phase"] = ph
		var dir := Vector2(0.7, -0.7) if ph == 0 else Vector2(-0.7, -0.7)
		ctx.set_gravity(1.4, dir, Tuning.MODES_FIELD_BLEND_S)


static func _g_random_tick(ctx: ModeCtx, a: Dictionary, dt: float) -> void:
	var period := float(a["period_s"])
	var t := float(ctx.state.get("t", 0.0)) + dt
	ctx.state["t"] = t
	var ph := int(t / period)
	if ph != int(ctx.state.get("phase", -1)):
		ctx.state["phase"] = ph
		var g: float = [0.0, 0.5, 1.0, 1.0, 2.0, 2.5][ctx.rng.randi() % 6]
		var dir := Vector2.from_angle(ctx.rng.randf_range(0.0, TAU))
		if ctx.rng.randf() < 0.5:
			dir = Vector2(0, -1)
		ctx.set_gravity(g, dir, Tuning.MODES_FIELD_BLEND_S)
		ctx.announce(TranslationServer.translate("ПОЛЕ: ×%.1f") % g, Color(0.5, 0.9, 1.0))


static func _g_pulse_tick(ctx: ModeCtx, a: Dictionary, dt: float) -> void:
	var period := float(a["period_s"])
	var t := float(ctx.state.get("t", 0.0)) + dt
	ctx.state["t"] = t
	var ph := int(t / (period * 0.5)) % 2
	if ph != int(ctx.state.get("phase", -1)):
		ctx.state["phase"] = ph
		ctx.set_gravity(0.0 if ph == 0 else 2.0, Vector2(0, -1), 0.0)


# ============================================================ кукла

static func _fast(_ctx: ModeCtx, a: Dictionary, d: Doll) -> void:
	d.mode_thrust_mult = float(a["mult"])   # не thrust_mult: его пишут класс стычки и держатель бомбы


## Запас: на FIGHT (после PartHp) — всем; на возрождение — новой кукле. Мета parts_hp снимается: иначе Match пересчитает при respawn.
static func _hp_set(ctx: ModeCtx, a: Dictionary) -> void:
	for d in ctx.dolls():
		_hp_doll(ctx, a, d)


static func _hp_doll(ctx: ModeCtx, a: Dictionary, d: Doll) -> void:
	var hp := float(a["hp"])
	if d.has_meta("parts_hp"):
		d.remove_meta("parts_hp")
	d.max_hp = hp
	d.hp = hp
	if ctx.mt != null:
		ctx.mt.hp_changed.emit(d, d.hp, d.max_hp)


static func _one_hit(_ctx: ModeCtx, _a: Dictionary, victim: Doll, attacker: Node, dmg: float, kind: String, _pos: Vector3) -> void:
	if dmg <= 0.0 or kind == "environment" or victim == null or not is_instance_valid(victim) or not victim.alive:
		return
	victim.knock_out(attacker)


static func _shove_only(_ctx: ModeCtx, _a: Dictionary, d: Doll) -> void:
	d.incoming_mult = 0.0


static func _damage_mult(ctx: ModeCtx, a: Dictionary) -> void:
	ctx.mt.mode_damage_mult *= float(a["mult"])


static func _knockback_mult(ctx: ModeCtx, a: Dictionary) -> void:
	ctx.mt.mode_knockback_mult *= float(a["mult"])


static func _vampire(ctx: ModeCtx, a: Dictionary, victim: Doll, attacker: Node, dmg: float, kind: String, _pos: Vector3) -> void:
	if dmg <= 0.0 or kind == "environment":
		return
	var d := ModeCtx.doll_of(attacker)
	if d == null or d == victim or not d.alive:
		return
	d.hp = minf(d.max_hp, d.hp + dmg * float(a["share"]))
	ctx.mt.hp_changed.emit(d, d.hp, d.max_hp)


static func _regen_tick(ctx: ModeCtx, a: Dictionary, dt: float) -> void:
	var acc := float(ctx.state.get("acc", 0.0)) + dt
	var emit := acc >= 0.25
	if emit:
		acc = 0.0
	ctx.state["acc"] = acc
	for d in ctx.dolls():
		if not d.alive or d.hp >= d.max_hp:
			continue
		d.hp = minf(d.max_hp, d.hp + float(a["per_s"]) * dt)
		if emit:
			ctx.mt.hp_changed.emit(d, d.hp, d.max_hp)


static func _drunk(ctx: ModeCtx, a: Dictionary) -> void:
	for d in ctx.dolls():
		d.set_stability(float(a["mult"]))


static func _spinner(_ctx: ModeCtx, a: Dictionary, d: Doll) -> void:
	d.spin_torque_mult *= float(a["mult"])


static func _brittle(ctx: ModeCtx, _a: Dictionary) -> void:
	_remember_hp_mode(ctx)
	JointBreak.set_on(true)
	ctx.mt.refresh_parts_hp()


static func _iron(ctx: ModeCtx, _a: Dictionary) -> void:
	_remember_hp_mode(ctx)
	PartHp.set_on(false)
	JointBreak.set_on(false)
	ctx.mt.refresh_parts_hp()


static func _remember_hp_mode(ctx: ModeCtx) -> void:
	if not ctx.shared.has("joint_break_was"):
		ctx.shared["joint_break_was"] = JointBreak.on
		ctx.shared["part_hp_was"] = PartHp.on


static func _restore_hp_mode(ctx: ModeCtx, _a: Dictionary) -> void:
	if ctx.shared.has("joint_break_was"):
		PartHp.on = bool(ctx.shared["part_hp_was"])
		JointBreak.on = bool(ctx.shared["joint_break_was"])
		ctx.shared.erase("joint_break_was")
		ctx.shared.erase("part_hp_was")


# ============================================================ время

static func _time_limit(ctx: ModeCtx, a: Dictionary) -> void:
	var lim := float(a["limit_s"])
	ctx.mt.time_limit_s = lim
	ctx.mt.hard_timeout_s = maxf(ctx.mt.hard_timeout_s, lim + Tuning.MODES_HARD_TIMEOUT_EXTRA_S)
	if lim >= 600.0:
		ctx.mt.hard_timeout_s = lim + Tuning.MODES_HARD_TIMEOUT_EXTRA_S


static func _time_scale(ctx: ModeCtx, a: Dictionary) -> void:
	ctx.mt.mode_time_scale = float(a["scale"])
	ctx.mt._apply_time_scale()


static func _stasis(ctx: ModeCtx, _a: Dictionary) -> void:
	ctx.shared["stasis_was"] = Stasis.on
	Stasis.set_on(true)


static func _stasis_exit(ctx: ModeCtx, _a: Dictionary) -> void:
	if ctx.shared.has("stasis_was"):
		Stasis.set_on(bool(ctx.shared["stasis_was"]))
		ctx.shared.erase("stasis_was")


# ============================================================ предметы

static func _barrels(ctx: ModeCtx, a: Dictionary) -> void:
	var ps := load(BARREL_SCENE) as PackedScene
	if ps == null:
		return
	var b := ctx.bounds()
	for i in int(a["n"]):
		var p := ps.instantiate() as Node3D
		var x := lerpf(b.position.x + 2.0, b.end.x - 2.0, (float(i) + 0.5) / float(a["n"]))
		var y := b.position.y + 1.0 + ctx.rng.randf_range(0.0, maxf(0.0, b.size.y * 0.5 - 1.0))
		ctx.props_root().add_child(p)
		p.global_position = Vector3(x, y, 0.0)
		p.add_to_group("mode_props")


static func _barrel_rain_tick(ctx: ModeCtx, a: Dictionary, dt: float) -> void:
	var t := float(ctx.state.get("t", 0.0)) + dt
	if t < float(a["period_s"]):
		ctx.state["t"] = t
		return
	ctx.state["t"] = 0.0
	var ps := load(BARREL_SCENE) as PackedScene
	if ps == null:
		return
	var b := ctx.bounds()
	var p := ps.instantiate() as Node3D
	ctx.props_root().add_child(p)
	p.global_position = Vector3(ctx.rng.randf_range(b.position.x + 2.0, b.end.x - 2.0), b.end.y - 1.0, 0.0)
	p.add_to_group("mode_props")
	if p.has_method("ignite"):
		p.call("ignite", Tuning.MODES_RAIN_FUSE_S)


static func _weapons(ctx: ModeCtx, _a: Dictionary) -> void:
	var b := ctx.bounds()
	var n := WEAPON_IDS.size()
	for i in n:
		var x := lerpf(b.position.x + 3.0, b.end.x - 3.0, (float(i) + 0.5) / float(n))
		var w := Weapon.spawn(String(WEAPON_IDS[i]), ctx.props_root(), Vector3(x, b.position.y + 0.6, 0.0), 0.0)
		if w != null:
			w.add_to_group("mode_props")


static func _weapon_pickup(_ctx: ModeCtx, _a: Dictionary, d: Doll) -> void:
	for c in d.get_children():
		if c is WeaponPickup:
			return
	var wp := WeaponPickup.new()
	wp.name = "WeaponPickup"
	d.add_child(wp)


static func _crates_tick(ctx: ModeCtx, a: Dictionary, dt: float) -> void:
	var t := float(ctx.state.get("t", 0.0)) + dt
	var first := not ctx.state.has("t")
	ctx.state["t"] = t
	if not first and t < float(a["period_s"]):
		return
	ctx.state["t"] = 0.0
	if ctx.mt.get_tree().get_nodes_in_group("squad_supply").size() >= int(a["n"]):
		return
	var b := ctx.bounds()
	var kind := String(CRATE_KINDS[ctx.rng.randi() % CRATE_KINDS.size()])
	var c := SupplyCrate.make(kind, Vector3(ctx.rng.randf_range(b.position.x + 2.0, b.end.x - 2.0),
		ctx.rng.randf_range(b.position.y + 1.0, b.position.y + maxf(1.5, b.size.y * 0.6)), 0.0))
	ctx.props_root().add_child(c)
	c.add_to_group("mode_props")


# ============================================================ боты и люди

static func _bots(ctx: ModeCtx, a: Dictionary) -> void:
	var lv := clampi(int(a["level"]), 1, 3)
	ctx.state["level"] = lv
	if ctx.scene != null and ctx.scene.has_method("set_bot_level"):
		ctx.scene.call("set_bot_level", lv)
		return
	# дуэль: P2 (и любой не-человек без мозга) — RivalBrain; P1 в группе players, боты — rivals
	for d in ctx.dolls():
		_bots_doll(ctx, a, d)


static func _bots_doll(ctx: ModeCtx, a: Dictionary, d: Doll) -> void:
	var lv := clampi(int(ctx.state.get("level", a["level"])), 1, 3)
	if ctx.scene != null and ctx.scene.has_method("set_bot_level"):
		return   # площадка сама ведёт уровень (гонка, бомба, стычка)
	for c in d.get_children():
		if "level" in c and (c is RivalBrain or c.has_method("steer")):
			c.set("level", lv)
			return
	var human := (d.player_index == 0 and not bool(ctx.opts.get("p1_bot", false))) or (d.player_index == 1 and bool(ctx.opts.get("coop", false)))
	if human:
		d.add_to_group("players")
		return
	var b := RivalBrain.new()
	b.name = "Brain"
	b.level = lv
	if d.player_index == 0:   # проба: P1 тоже бот — он «игрок» для остальных, а сам целится в rivals
		d.add_to_group("players")
		b.players_group = "rivals"
		b.enemies_group = "players"
	else:
		d.add_to_group("rivals")
	d.add_child(b)


static func _champion(ctx: ModeCtx, _a: Dictionary) -> void:
	if ctx.arena == null or not ctx.arena.has_method("call_champion"):
		return
	if not ctx.opts.get("coop", false):
		var p2 := ctx.doll(1)
		if p2 != null:
			ctx.mt._unregister(p2)
			p2.queue_free()
	ctx.arena.call("call_champion")
	if "debug_keys" in ctx.arena:
		ctx.arena.set("debug_keys", false)


static func _coop(ctx: ModeCtx, _a: Dictionary) -> void:
	ctx.opts["coop"] = true
	if ctx.scene == null:
		return
	if ctx.scene.has_method("set_p2_human"):
		ctx.scene.call("set_p2_human", true)
	elif ctx.scene.has_method("set_p2_bot"):
		ctx.scene.call("set_p2_bot", false)


# ============================================================ кадр

static func _zoom(ctx: ModeCtx, a: Dictionary) -> void:
	if not ctx.shared.has("zoom_was"):
		ctx.shared["zoom_was"] = DynamicCamera.user_zoom
	DynamicCamera.user_zoom = float(a["zoom"])


static func _zoom_exit(ctx: ModeCtx, _a: Dictionary) -> void:
	if ctx.shared.has("zoom_was"):
		DynamicCamera.user_zoom = float(ctx.shared["zoom_was"])
		ctx.shared.erase("zoom_was")
