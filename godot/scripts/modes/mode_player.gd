## Кукла игрока со стенда мастерской в любом режиме реестра (docs/plan-demo/MODES_100.md §B, «Испытать в режиме…»): swap_p1 меняет
## куклу P1 площадки на ModularDoll из чертежа — те же имя, точка, группы, скриптовые дети (WeaponPickup, ArmAssist: как
## Match.respawn_doll), регистрирует в Match и шлёт doll_replaced. Чертёж — копия в памяти (CraftEdit.dup_body): KO / R его
## переживают (Match.respawn_doll переносит чертёж без resource_path).
class_name ModePlayer
extends RefCounted

const DOLL_SCENE := "res://scenes/body/modular_doll.tscn"


static func swap_p1(m: Match, _scene: Node, bp: Resource) -> Doll:
	if m == null or bp == null or not (bp is BodyBlueprint):
		return null
	var old: Doll = null
	for d in m.dolls():
		if (d as Doll).player_index == 0:
			old = d
			break
	if old == null or old.get_parent() == null:
		return null
	var errs: Array = CraftEdit.friendly_errors(bp)
	if not errs.is_empty():
		push_warning("ModePlayer: чертёж с ошибками (%s), кукла со стенда не ставится" % String(errs[0]))
		return null
	var ps := load(DOLL_SCENE) as PackedScene
	if ps == null:
		return null
	var d := ps.instantiate() as Doll
	d.set("blueprint", CraftEdit.dup_body(bp))
	d.player_index = old.player_index
	d.input_prefix = old.input_prefix
	d.external_input = old.external_input
	d.control_enabled = old.control_enabled
	d.team = old.team
	d.team_damage_mult = old.team_damage_mult
	for g in old.get_groups():
		d.add_to_group(g)
	if not d.is_in_group(m.dolls_group):
		d.add_to_group(m.dolls_group)
	var extra: Array = []
	var has_arm := false
	for c in old.get_children():
		if c is DollCombat or c is RigidBody3D or c is Joint3D or c.get_script() == null:
			continue
		if c is ArmAssist:
			has_arm = true
			continue
		var scr: Script = c.get_script()
		var n: Object = scr.new()
		if n is Node:
			(n as Node).name = c.name
			extra.append(n)
	var parent := old.get_parent()
	var pos := old.global_position
	var name_ := old.name
	var idx := old.get_index()
	m._unregister(old)
	parent.remove_child(old)
	old.queue_free()
	d.name = name_
	parent.add_child(d)
	parent.move_child(d, idx)
	d.global_position = pos
	for n in extra:
		d.add_child(n)
	if has_arm or not d.external_input:
		ArmAssist.attach_to(d)
	m.register(d)
	m.doll_replaced.emit(old, d)
	return d
