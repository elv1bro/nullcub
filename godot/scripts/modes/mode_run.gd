## Раннер режимов (autoload «ModeRun», docs/plan-demo/MODES_100.md): launch(def) грузит площадку основы под лоадером, ждёт в дереве
## её Match и применяет модификаторы карточки (Mutators) через ModeCtx. Дальше ведёт их: on_doll на возрождение (doll_replaced),
## on_fight на FIGHT, on_hit на удар, tick каждый кадр боя; на уходе со сцены — exit всех и возврат статиков (гравитация мира,
## JointBreak / PartHp / Stasis, зум камеры). Площадки о реестре не знают: любая сцена с Match в группе "match" подходит.
## Избранное и последние — user://modes.cfg. current — карточка, которая идёт сейчас (null — обычный запуск без реестра).
extends Node

signal attached(def: ModeDef)
signal detached(def: ModeDef)

const CFG_PATH := "user://modes.cfg"
const RECENT_MAX := 12
const WAIT_MAX_S := 30.0

var current: ModeDef = null
var opts: Dictionary = {}
## Применено: Match и сцена, к которым привязан раннер.
var mt: Match = null
var scene: Node = null
var shared: Dictionary = {}

var _pending: ModeDef = null
var _pending_path := ""
var _wait_t := 0.0
var _ctxs: Array = []        # [{id, args, ctx}] по порядку карточки
var _seen: Dictionary = {}   # куклы, которым on_doll уже был
var _fav: Dictionary = {}
var _recent: Array = []
var _cfg_loaded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_cfg()


## Запустить карточку. opts: player_blueprint (BodyBlueprint — P1 кукла со стенда мастерской), return_to ("workshop"),
## no_scene_change (проба: сцена уже в дереве — только дождаться Match), scene (проба: узел площадки вместо current_scene),
## p1_bot (проба: P1 тоже бот), seed (случайности модификаторов).
func launch(def: ModeDef, p_opts: Dictionary = {}) -> void:
	if def == null:
		return
	_detach()
	current = def
	opts = p_opts.duplicate()
	shared = {}
	_pending = def
	_pending_path = def.scene_path()
	_wait_t = 0.0
	_prepare_statics(def)
	_touch_recent(def.id)
	if not bool(opts.get("no_scene_change", false)):
		Loading.change_scene(_pending_path, "ПОДКЛЮЧЕНИЕ", tr(def.name))


## Статики, которые площадка читает в _ready (до того, как раннер её увидит).
func _prepare_statics(def: ModeDef) -> void:
	match def.base:
		"squad":
			SquadSettings.ask = false
			SquadSettings.mode = String(def.params.get("squad_mode", "dm"))
			SquadSettings.night = def.map_id() == "night"
			var lv := _bot_level(def)
			if lv > 0:
				SquadSettings.bot_level = lv
		"pve", "stasis":
			PvePlayground.coop = def.has_mutator("coop")


static func _bot_level(def: ModeDef) -> int:
	for m in def.mutators:
		if String(m["id"]) == "bots":
			return int(Mutators.merged_args("bots", m["args"])["level"])
	return 0


func _process(delta: float) -> void:
	if _pending != null:
		_wait_t += delta
		var sc: Node = opts.get("scene", null) if opts.get("scene", null) is Node else get_tree().current_scene
		if sc != null and sc.is_inside_tree() and (bool(opts.get("no_scene_change", false)) or sc.scene_file_path == _pending_path):
			var m := _find_match(sc)
			if m != null:
				var def := _pending
				_pending = null
				_attach(def, sc, m)
		elif _wait_t > WAIT_MAX_S:
			push_warning("ModeRun: площадка %s не появилась за %.0f с" % [_pending_path, WAIT_MAX_S])
			_pending = null
			current = null
		return
	if mt == null or not is_instance_valid(mt):
		return
	_scan_new_dolls()
	if not mt.combat_active():
		return
	for e in _ctxs:
		Mutators.call_hook(String(e["id"]), "tick", e["ctx"], e["args"], [delta])


## Куклы, которых Match зарегистрировал после привязки без doll_replaced (волны PvE, чемпион лиги): on_doll им тоже.
func _scan_new_dolls() -> void:
	var ds := mt.dolls()
	if ds.size() == _seen.size():
		return
	for d in ds:
		if not _seen.has(d):
			_seen[d] = true
			_on_doll(d)
	for k in _seen.keys():
		if not is_instance_valid(k) or not ds.has(k):
			_seen.erase(k)


func _find_match(sc: Node) -> Match:
	for n in get_tree().get_nodes_in_group(Match.GROUP):
		if n is Match and (n == sc or sc.is_ancestor_of(n)) and n.is_inside_tree():
			return n
	return null


static func _find_class(root: Node, cls: Variant) -> Node:
	if is_instance_of(root, cls):
		return root
	for c in root.get_children():
		var f := _find_class(c, cls)
		if f != null:
			return f
	return null


func _attach(def: ModeDef, sc: Node, m: Match) -> void:
	scene = sc
	mt = m
	var arena: Node = null
	if "arena" in sc and sc.get("arena") is Node:
		arena = sc.get("arena")
	if arena == null:
		for c in sc.get_children():
			if c is Node3D and c.has_method("spawn_points"):
				arena = c
				break
	var field := _find_class(sc, NullField) as NullField
	var uses_field := false
	_ctxs.clear()
	for mu in def.mutators:
		var id := String(mu["id"])
		if not Mutators.has(id):
			push_warning("ModeRun: нет модификатора %s" % id)
			continue
		var ctx := ModeCtx.new()
		ctx.mt = m
		ctx.scene = sc
		ctx.arena = arena
		ctx.field = field
		ctx.opts = opts
		ctx.shared = shared
		ctx.rng.seed = hash(def.id) + int(opts.get("seed", 0)) if opts.has("seed") else randi()
		_ctxs.append({"id": id, "args": Mutators.merged_args(id, mu["args"]), "ctx": ctx})
		if String((Mutators.CATALOG[id] as Dictionary).get("group", "")) == "поле":
			uses_field = true
	if uses_field:
		var vote := sc.get_node_or_null("AudienceVote")   # голосование зрителей само меняет поле купола
		if vote != null:
			vote.queue_free()
		if arena != null and "debug_keys" in arena:
			arena.set("debug_keys", false)
	if opts.has("player_blueprint"):
		ModePlayer.swap_p1(m, sc, opts["player_blueprint"])
	# порядок: apply (coop раньше ботов: карточка пишет их в нужном порядке) → on_doll всем
	for e in _ctxs:
		Mutators.call_hook(String(e["id"]), "apply", e["ctx"], e["args"])
	_seen.clear()
	for d in m.dolls():
		_seen[d] = true
		_on_doll(d)
	m.doll_replaced.connect(_on_doll_replaced)
	m.phase_changed.connect(_on_phase)
	m.hit.connect(_on_hit)
	m.match_over.connect(_on_match_over)
	sc.tree_exiting.connect(_on_scene_exiting.bind(sc))
	if m.phase == Match.Phase.FIGHT or m.phase == Match.Phase.SUDDEN_DEATH:
		_on_phase(Match.Phase.FIGHT)
	_show_title(def)
	attached.emit(def)


func _on_doll(d: Doll) -> void:
	for e in _ctxs:
		Mutators.call_hook(String(e["id"]), "on_doll", e["ctx"], e["args"], [d])


func _on_doll_replaced(old: Doll, new_doll: Doll) -> void:
	_seen.erase(old)
	_seen[new_doll] = true
	_on_doll(new_doll)


func _on_phase(p: int) -> void:
	if p == Match.Phase.FIGHT:
		for e in _ctxs:
			Mutators.call_hook(String(e["id"]), "on_fight", e["ctx"], e["args"])


func _on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3) -> void:
	for e in _ctxs:
		Mutators.call_hook(String(e["id"]), "on_hit", e["ctx"], e["args"], [victim, attacker, damage, kind, position])


func _on_match_over(_winner: Doll, _results: Dictionary) -> void:
	pass


func _show_title(def: ModeDef) -> void:
	if _ctxs.is_empty() and def.mutators.is_empty():
		return
	var line := Mutators.labels_line(def.mutator_ids())
	var ctx: ModeCtx = _ctxs[0]["ctx"] if not _ctxs.is_empty() else null
	if ctx != null:
		ctx.toast("%s   ·   %s" % [tr(def.name), line], 4.0)


func _on_scene_exiting(sc: Node) -> void:
	if sc == scene:
		_detach()


## Снять всё: exit модификаторов, статики, гравитация мира.
func _detach() -> void:
	var def := current
	if mt != null and is_instance_valid(mt):
		if mt.doll_replaced.is_connected(_on_doll_replaced):
			mt.doll_replaced.disconnect(_on_doll_replaced)
		if mt.phase_changed.is_connected(_on_phase):
			mt.phase_changed.disconnect(_on_phase)
		if mt.hit.is_connected(_on_hit):
			mt.hit.disconnect(_on_hit)
		if mt.match_over.is_connected(_on_match_over):
			mt.match_over.disconnect(_on_match_over)
		mt.mode_knockback_mult = 1.0
		mt.mode_damage_mult = 1.0
		mt.mode_time_scale = 1.0
	if scene != null and is_instance_valid(scene) and scene.tree_exiting.is_connected(_on_scene_exiting):
		scene.tree_exiting.disconnect(_on_scene_exiting)
	for e in _ctxs:
		Mutators.call_hook(String(e["id"]), "exit", e["ctx"], e["args"])
	_ctxs.clear()
	_seen.clear()
	if not shared.is_empty():
		Mutators._restore_hp_mode(_shared_ctx(), {})
		Mutators._stasis_exit(_shared_ctx(), {})
		Mutators._zoom_exit(_shared_ctx(), {})
	ModeCtx.restore_world_gravity(get_tree())
	Engine.time_scale = 1.0
	mt = null
	scene = null
	_pending = null
	current = null
	shared = {}
	if def != null:
		detached.emit(def)


func _shared_ctx() -> ModeCtx:
	var c := ModeCtx.new()
	c.shared = shared
	return c


func is_active() -> bool:
	return current != null and mt != null and is_instance_valid(mt)


# --- избранное и последние ---

func _load_cfg() -> void:
	_cfg_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	for id in cfg.get_value("modes", "favorites", []):
		_fav[String(id)] = true
	_recent = Array(cfg.get_value("modes", "recent", []))


func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("modes", "favorites", _fav.keys())
	cfg.set_value("modes", "recent", _recent)
	cfg.save(CFG_PATH)


func is_favorite(id: String) -> bool:
	return _fav.has(id)


func set_favorite(id: String, on: bool) -> void:
	if on:
		_fav[id] = true
	else:
		_fav.erase(id)
	_save_cfg()


func favorites() -> Array:
	return _fav.keys()


func recent() -> Array:
	return _recent.duplicate()


func _touch_recent(id: String) -> void:
	_recent.erase(id)
	_recent.push_front(id)
	while _recent.size() > RECENT_MAX:
		_recent.pop_back()
	_save_cfg()
