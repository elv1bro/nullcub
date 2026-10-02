## Мозг чемпиона лиги (docs/plan-demo/ACTIVE_BLOCKS.md «Боты», ART_NULL.md «Детали лиги v2»): дуэлянт на базе EnemyBrain — то же
## восприятие с задержкой, ошибка прицела, плавный ввод и страховка от пропасти, но без EnemyLook (у лиги свой вид — LeagueLook) и
## без телеграфа-надписей:
##   • approach — к упреждённой цели не быстрее APPROACH_SPEED; ближе STRIKE_M — наскок: рывок и удар (strike);
##   • strike — тяга в цель STRIKE_S, управляемая рука (blueprint.control, ArmAssist.set_target_override) всё время тянется к цели;
##   • retreat — отскок RETREAT_S и снова подход;
##   • особые модули и активные блоки жмёт автопилот ActiveRig (set_brain: его цель — эта же);
##   • цели — живые куклы группы dolls, кроме себя и своей команды (team "league"); кукла в дыму (ActiveBlocks.is_hidden) видна
##     только вплотную, ослеплённый прожектором мозг (ActiveBlocks.is_blinded) целится мимо — как у EnemyBrain.
class_name LeagueBrain
extends EnemyBrain

const APPROACH_SPEED := 4.5
const STRIKE_M := 1.5
const STRIKE_S := 0.7
const RETREAT_S := 0.45
const TEAM := "league"

var arm: ArmAssist


func _init() -> void:
	players_group = "dolls"
	reaction_s = 0.2
	aim_error_m = 0.25


## Как EnemyBrain._setup, но без EnemyLook (он перекрасил бы вид лиги в ржавчину врагов PvE).
func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	if doll.team == "":
		doll.team = TEAM
	arena = get_tree().get_first_node_in_group("arena")
	doll.damaged.connect(_on_damaged)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	for c in doll.get_children():
		if c is ArmAssist:
			arm = c
	if arm == null:
		arm = ArmAssist.attach_to(doll)
	var rig: Variant = doll.get("active_rig")
	if rig is ActiveRig:
		(rig as ActiveRig).set_brain(self)
	_brain_ready()


func players() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group(players_group):
		if n == doll or not (n is Doll) or not (n as Doll).alive or not n.is_inside_tree():
			continue
		if doll.team != "" and (n as Doll).team == doll.team:
			continue
		if ActiveBlocks.is_hidden(n) and my_pos().distance_to(com2(n)) > 1.5:
			continue
		out.append(n)
	return out


func _think(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		go("idle")
		want = hover_vec()
		if arm != null:
			arm.clear_target_override()
		return
	var tp := predicted()
	var d := my_pos().distance_to(com2(target))
	match state:
		"strike":
			want = steer(tp, 1.0)
			if state_t > STRIKE_S:
				go("retreat")
		"retreat":
			var away := (my_pos() - tp).normalized() if my_pos().distance_to(tp) > 0.01 else Vector2.RIGHT
			want = steer(my_pos() + away * 2.0, 0.8)
			if state_t > RETREAT_S:
				go("approach")
		_:
			go("approach")
			want = steer_speed(tp, APPROACH_SPEED)
			if d < STRIKE_M:
				go("strike")
				note_attack()
				dash()
	if arm != null:
		arm.set_target_override(Vector3(tp.x, tp.y, 0.0))


func _silenced(_why: String) -> void:
	if arm != null:
		arm.clear_target_override()


## Чемпион лиги из пресета (scenes/body/presets/league_*.tscn) с этим мозгом в точке pos: в матче — регистрация (DollCombat, HUD),
## группа dolls. parent — куда положить куклу (к остальным куклам арены).
static func spawn(parent: Node, preset_id: String, pos: Vector3) -> ModularDoll:
	var ps := load("res://scenes/body/presets/%s.tscn" % preset_id) as PackedScene
	if ps == null:
		return null
	var d := ps.instantiate() as ModularDoll
	d.external_input = true
	d.team = TEAM
	d.player_index = 3
	d.position = pos
	d.add_to_group("dolls")
	parent.add_child(d)
	var b := LeagueBrain.new()
	b.name = "LeagueBrain"
	d.add_child(b)
	var m := parent.get_tree().get_first_node_in_group("match")
	if m != null and m.has_method("register"):
		m.call("register", d)
	return d
