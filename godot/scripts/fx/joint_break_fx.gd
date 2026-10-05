## Вид пробного режима «Прочность суставов» (JointBreak, docs/plan-demo/JOINT_BREAK.md): на языке игры, без полосок и цифр.
##   • повреждённый сустав искрит: запас ниже Tuning.JOINT_SPARK_BELOW — короткий сноп искр в точке сустава, тем чаще, чем меньше
##     осталось (Tuning.JOINT_SPARK_GAP_S: от MAX у порога до MIN у нуля);
##   • сустав сломан (Doll.joint_broken) — вспышка удара с обломками материала детали и сноп искр в точке сустава.
## Ребёнок HitJuice (его родитель — Match: эффекты кладутся туда же, куда ImpactFx ударов). Куклы находит по группе dolls раз в SCAN_S.
class_name JointBreakFx
extends Node

const SCAN_S := 0.2

## Пробы: сколько искр и вспышек отрыва показано.
var stats := {"sparks": 0, "breaks": 0}

var _t := 0.0
var _clock := 0.0
var _hooked: Dictionary = {}   # instance_id куклы -> true (joint_broken подключён)
var _next: Dictionary = {}     # "id куклы:деталь" -> время следующей искры (_clock)
var _rng := RandomNumberGenerator.new()


func _fx_parent() -> Node:
	var p := get_parent()
	return p.get_parent() if p != null and p.get_parent() != null else p


func _process(delta: float) -> void:
	_clock += delta
	_t += delta
	if _t < SCAN_S or not is_inside_tree():
		return
	_t = 0.0
	for n in get_tree().get_nodes_in_group("dolls"):
		var d := n as Doll
		if d == null:
			continue
		var id := d.get_instance_id()
		if not _hooked.has(id):
			_hooked[id] = true
			d.joint_broken.connect(_on_joint_broken.bind(d))
		if (JointBreak.on or PartHp.on) and d.alive:
			_tick_sparks(d, id)


func _tick_sparks(d: Doll, id: int) -> void:
	for part in d.joint_hp:
		var mx := float(d.joint_hp_max.get(part, 0.0))
		if mx <= 0.0:
			continue
		var frac := clampf(float(d.joint_hp[part]) / mx, 0.0, 1.0)
		if frac >= Tuning.JOINT_SPARK_BELOW:
			continue
		var key := "%d:%s" % [id, part]
		if _clock < float(_next.get(key, 0.0)):
			continue
		var u := frac / Tuning.JOINT_SPARK_BELOW
		_next[key] = _clock + lerpf(Tuning.JOINT_SPARK_GAP_S.x, Tuning.JOINT_SPARK_GAP_S.y, u) * _rng.randf_range(0.7, 1.3)
		var b := d.parts.get(part) as RigidBody3D
		if b != null:
			_spark(d.joint_pivot_global(d.hang_joint_name(b)), lerpf(0.6, 0.25, u))


## Сноп искр (scenes/fx/sparks.tscn, тот же, что у ударов по металлу) в точке pos; ratio — доля частиц.
func _spark(pos: Vector3, ratio: float) -> void:
	var parent := _fx_parent()
	if parent == null or not parent.is_inside_tree():
		return
	var p := ImpactFx.SPARKS.instantiate() as GPUParticles3D
	if p == null:
		return
	p.name = "JointSpark"
	parent.add_child(p, true)
	p.global_position = pos
	p.amount_ratio = clampf(ratio, 0.1, 1.0)
	p.finished.connect(p.queue_free)
	p.restart()
	p.emitting = true
	stats["sparks"] = int(stats["sparks"]) + 1


func _on_joint_broken(part: String, _by: Node, pos: Vector3, d: Doll) -> void:
	stats["breaks"] = int(stats["breaks"]) + 1
	var parent := _fx_parent()
	if parent == null or not is_instance_valid(d):
		return
	var body := d.parts.get(part) as Node3D
	var out := pos - d.centre_of_mass()
	out.z = 0.0
	var mat := FxMaterial.id_of(d, body)
	ImpactFx.spawn_impact(parent, pos, out, Tuning.JOINT_BREAK_FX_STRENGTH, "body", mat, FxMaterial.tint_of(mat, d), true)
	_spark(pos, 1.0)
