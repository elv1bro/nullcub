## «Сок» боя на испытании мастерской (WORKSHOP_V3.md §5): удар по манекену выглядит и звучит как в бою — вспышка, волна, щепки,
## стоп-кадр heavy, тряска камеры, звук. Match в мастерскую не ставим (его фазы, таймер и итоги ломают бесконечную тренировку:
## KO манекена закончил бы матч и выключил урон), а эта нода отвечает на тот же утиный контракт, что Match для DollCombat,
## HitFxDirector, SfxDirector, ThrownCredit, DollMask, Explosion: группа "match", on_hit / on_env_slam / combat_active /
## knockback_mult / dolls / game_camera / camera_owner / request_time_scale / cancel_time_scale, сигналы hit, hit_fx, env_slam.
## Уровни — HitTier без крита (кинематограф CRUSHING BLOW! — событие матча, на манекене он был бы шумом): light / heavy / ko.
## Слабые касания (DollCombat.on_weak_contact: контакт частей ниже Tuning.MIN_IMPACT_SPEED — урона 0) — сигнал weak_contact:
## мастерская пишет у манекена серое «0 · 1.2 м/с», чтобы было видно, почему урона нет.
## Узел создаёт WorkshopBuild.start_test до кукол (их DollCombat находит его по группе), stop_test освобождает.
class_name TrainingFeel
extends Node3D

signal hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3)
signal hit_fx(ctx: Dictionary)
signal env_slam(ctx: Dictionary)
signal announce(text: String, colour: Color, kind: String)
signal weak_contact(victim: Doll, speed: float, position: Vector3)

const GROUP := "match"
const HIT_FX_DIRECTOR_SCENE := "res://scenes/fx/hit_fx_director.tscn"
const SFX_DIRECTOR_SCENE := "res://scenes/audio/sfx_director.tscn"
const WEAK_MIN_SPEED := 0.6        # м/с: медленнее — это лежание и трение, не «удар»
const WEAK_COOLDOWN_S := 0.3       # одна пара (бьющее тело, жертва) — не чаще

## Камера испытания (DynamicCamera): тряска и punch HitFxDirector.
var camera: Camera3D
var feel_enabled := true
var fight_time := 0.0
var hit_tiers := HitTier.new()
var hit_fx_count := 0
var weak_count := 0

var _time_effects: Array = []      # [{scale, left, tag}] — реальные секунды
var _weak_seen: Dictionary = {}    # "striker:victim" -> fight_time


func _ready() -> void:
	add_to_group(GROUP)
	if not Tuning.HITFX_ENABLED:
		return
	for e in [[HIT_FX_DIRECTOR_SCENE, "HitFxDirector"], [SFX_DIRECTOR_SCENE, "SfxDirector"]]:
		if not ResourceLoader.exists(String(e[0])):
			continue
		var n := (load(String(e[0])) as PackedScene).instantiate()
		n.name = String(e[1])
		add_child(n)
		if n.is_in_group(FxPreset.DIRECTOR_GROUP):
			FxPreset.apply(n)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 1e-3)
	fight_time += delta
	var scale := 1.0
	for i in range(_time_effects.size() - 1, -1, -1):
		var e: Dictionary = _time_effects[i]
		e["left"] = float(e["left"]) - real
		if float(e["left"]) <= 0.0:
			_time_effects.remove_at(i)
		else:
			scale = minf(scale, float(e["scale"]))
	Engine.time_scale = scale


# --- контракт Match для DollCombat ---

func combat_active() -> bool:
	return true


func knockback_mult() -> float:
	return 1.0


func dolls() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(WorkshopBuild.TEST_GROUP):
		if n is Doll:
			out.append(n)
	return out


func on_hit(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> void:
	hit.emit(victim, attacker, damage, kind, position)
	if victim == null or not is_instance_valid(victim) or damage <= 0.0 or kind == "environment":
		return
	var ctx := _make_ctx(victim, attacker, damage, kind, position, combo_n, double_blow, weapon_id, speed)
	ctx["tier"] = hit_tiers.classify(ctx, fight_time, false)
	ctx["launch_dv"] = Vector3.ZERO
	hit_fx_count += 1
	hit_fx.emit(ctx)


func on_combo(_doll: Doll, _n: int) -> void:
	pass


func on_env_slam(doll: Doll, part: String, speed: float, position: Vector3, normal: Vector3) -> void:
	env_slam.emit({"doll": doll, "part": part, "speed": speed, "position": position, "normal": normal, "fight_time": fight_time})


## Контакт части чужой куклы ниже порога урона (DollCombat): сигнал weak_contact, не чаще WEAK_COOLDOWN_S на пару.
func on_weak_contact(victim: Doll, striker: Node, speed: float, position: Vector3) -> void:
	if victim == null or speed < WEAK_MIN_SPEED or striker == null:
		return
	var key := "%d:%d" % [striker.get_instance_id(), victim.get_instance_id()]
	if fight_time - float(_weak_seen.get(key, -INF)) < WEAK_COOLDOWN_S:
		return
	_weak_seen[key] = fight_time
	weak_count += 1
	weak_contact.emit(victim, speed, position)


# --- контракт Match для HitFxDirector / SfxDirector ---

func game_camera() -> Camera3D:
	return camera if camera != null and is_instance_valid(camera) else get_viewport().get_camera_3d()


func camera_owner() -> String:
	return ""


func request_time_scale(scale: float, real_s: float, tag: String = "") -> bool:
	if not feel_enabled:
		return false
	_time_effects.append({"scale": maxf(scale, Tuning.HITFX_TIME_SCALE_MIN), "left": real_s, "tag": tag})
	return true


func cancel_time_scale(tag: String) -> void:
	for i in range(_time_effects.size() - 1, -1, -1):
		if String(_time_effects[i]["tag"]) == tag:
			_time_effects.remove_at(i)


## ctx по контракту HIT_FX.md §4.1 — как Match.make_hit_ctx (без Sudden Death).
func _make_ctx(victim: Doll, attacker: Node, damage: float, kind: String, position: Vector3, combo_n: int, double_blow: bool, weapon_id: String, speed: float) -> Dictionary:
	var lh: Dictionary = victim.last_hit
	var part := String(lh.get("part", ""))
	var normal: Vector3 = lh.get("normal", Vector3.ZERO)
	var dir: Vector3 = lh.get("dir", Vector3.ZERO)
	dir.z = 0.0
	if dir.length_squared() < 1e-6:
		dir = Vector3(-normal.x, -normal.y, 0.0)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.RIGHT
	var dash := false
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("is_dashing"):
		dash = bool(attacker.call("is_dashing"))
	var pi := victim.player_index
	return {
		"victim": victim, "attacker": attacker if attacker != null and is_instance_valid(attacker) else null, "damage": damage, "kind": kind,
		"part": part, "part_base": Doll.part_base_name(part), "striker": weapon_id if weapon_id != "" else String(lh.get("striker_name", "")),
		"position": position, "normal": normal, "dir": dir, "speed": speed, "weapon_id": weapon_id, "combo": combo_n,
		"double_blow": double_blow, "dash": dash, "score": 0.0, "tier": "", "is_ko": not victim.alive, "hp_after": victim.hp,
		"fight_time": fight_time, "sd_mult": 1.0,
		"colour": Tuning.PLAYER_COLORS[pi % Tuning.PLAYER_COLORS.size()] if pi >= 0 else Color.WHITE,
	}
