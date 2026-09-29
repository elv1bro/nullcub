## №061 Garbage Chute (лист 04): раз в цикл желоб высыпает сверху 3–6 кусков хлама (bit_*) — снаряды для броска (E) и корм для
## пара и магнита. Дерево — scenes/props/scrap/machine_chute.tscn: Model (труба из-за верхнего края кадра в раструб, без коллизий),
## Mouth (Marker3D — центр раструба), Dust (пыль и ржавчина из раструба в WARNING), LampLight, Sfx.
##
## Цикл (ScrapMachine): WARNING — лампа мигает, грохот, пыль сыплется (куски «едут» по трубе); ACTIVE — куски вылетают один за
## другим (active_s / N) из раструба вдоль spit_dir со скоростью spit_speed ± разброс, с закруткой; COOLDOWN — лампа гаснет.
## Куски — инстансы BITS (сцены scenes/props/scrap/bit_*.tscn) в узел junk_path (у арены — Junk: их видят loose_bodies() и пробы;
## пусто — родитель механизма), имя "Chute_<Kind>_<n>", группа GROUP, у железных meta material = "iron" (тянет магнит).
## Живых кусков желоба не больше max_alive: лишние (самые старые, не в руке) удаляются — хлам не копится весь матч.
## Разброс детерминирован (rng_seed).
class_name ChuteMachine
extends ScrapMachine

const GROUP := "chute_junk"
const BIT_DIR := "res://scenes/props/scrap/bit_%s.tscn"
## Вид куска → вес выбора. Лёгкие и средние (0.15–4 кг) — метать; тяжёлые (шестерня 12, торс 8) не сыплются.
const BITS := {
	"bolt": 3, "nut": 3, "gear_small": 2, "gear_medium": 1, "chain_link": 2, "pipe_piece": 2, "scrap_board": 2,
	"rivet_plate": 1, "doll_hand": 2, "doll_foot": 1, "doll_head_sad": 1, "doll_head_scared": 1, "helmet": 1,
	"sword_broken": 1, "doll_limb_lower": 1,
}
const IRON := ["bolt", "nut", "gear_small", "gear_medium", "chain_link", "pipe_piece", "rivet_plate", "helmet", "sword_broken"]

@export var junk_path: NodePath
@export var pieces_min := 3
@export var pieces_max := 6
@export var spit_dir := Vector3(0.55, -0.83, 0.0)
@export var spit_speed := 2.5
@export var spread := 0.35             # м поперёк раструба
@export var max_alive := 14
@export var rng_seed := 61

var mouth: Node3D
var dust: GPUParticles3D
## Все выброшенные за время жизни (живые и удалённые) и живые сейчас.
var spawned_total := 0
var alive_bits: Array = []
var last_batch: Array = []
var _rng := RandomNumberGenerator.new()
var _batch_n := 0
var _batch_done := 0
var _scenes: Dictionary = {}
var _kinds: Array = []
var _weights: Array = []


func _machine_ready() -> void:
	mouth = get_node_or_null("Mouth") as Node3D
	dust = get_node_or_null("Dust") as GPUParticles3D
	_rng.seed = rng_seed
	for k in BITS:
		_kinds.append(k)
		_weights.append(float(BITS[k]))
		_scenes[k] = load(BIT_DIR % k)   # заранее: загрузка glb посреди боя — рывок кадра


func mouth_global() -> Vector3:
	return mouth.global_position if mouth != null else global_position


func _on_state(s: int, _prev: int) -> void:
	match s:
		State.WARNING:
			play_sfx("rumble")
		State.ACTIVE:
			_batch_n = _rng.randi_range(pieces_min, pieces_max)
			_batch_done = 0
			last_batch = []
	if dust != null:
		dust.emitting = s == State.WARNING or s == State.ACTIVE


func _machine_tick(_delta: float) -> void:
	if state != State.ACTIVE or _batch_done >= _batch_n:
		return
	var due := int(floor(state_t / maxf(active_s, 0.05) * _batch_n)) + 1
	while _batch_done < mini(due, _batch_n):
		_spit()
		_batch_done += 1


func _spit() -> void:
	var kind: String = _kinds[_rng.rand_weighted(PackedFloat32Array(_weights))]
	if not _scenes.has(kind):
		_scenes[kind] = load(BIT_DIR % kind)
	var ps := _scenes[kind] as PackedScene
	if ps == null:
		return
	var parent: Node = get_node_or_null(junk_path) if junk_path != NodePath() else null
	if parent == null:
		parent = get_parent()
	var b := ps.instantiate() as RigidBody3D
	if b == null:
		return
	spawned_total += 1
	b.name = "Chute_%s_%d" % [String(b.name), spawned_total]
	if kind in IRON:
		b.set_meta(ScrapMachine.META_MATERIAL, "iron")
	else:
		b.set_meta(ScrapMachine.META_MATERIAL, "wood")
	b.add_to_group(GROUP)
	parent.add_child(b)
	var d := spit_dir.normalized()
	var side := Vector3(-d.y, d.x, 0.0)
	var p := mouth_global() + d * 0.35 + side * _rng.randf_range(-spread, spread)
	p.z = 0.0
	b.global_position = p
	b.rotation = Vector3(0.0, 0.0, _rng.randf_range(-PI, PI))
	b.linear_velocity = d * spit_speed * _rng.randf_range(0.8, 1.25) + side * _rng.randf_range(-0.6, 0.6)
	b.angular_velocity = Vector3(0.0, 0.0, _rng.randf_range(-6.0, 6.0))
	alive_bits.append(b)
	last_batch.append(b)
	_trim()


func _trim() -> void:
	var i := 0
	while i < alive_bits.size():
		if not is_instance_valid(alive_bits[i]):
			alive_bits.remove_at(i)
		else:
			i += 1
	i = 0
	while alive_bits.size() > max_alive and i < alive_bits.size():
		var b := alive_bits[i] as RigidBody3D
		var tc := ThrownCredit.of(b)
		if tc != null and tc.held:
			i += 1
			continue
		alive_bits.remove_at(i)
		b.queue_free()
