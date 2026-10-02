## Бот-соперник кампании (docs/plan-demo/17-career-trophy.md): боец лиги, а не враг PvE.
## Поведение — наскок бота tests/match_probe.gd (разбег → удар → отход RUSH → разбег, рывок с разбега), поверх EnemyBrain:
## восприятие с задержкой reaction_s, упреждение lead_s, ошибка прицела, плавный ввод, выход из застревания, зависание против
## поля NULL (hover_vec — поле купола может тянуть вбок и вверх).
## Отличия от врага PvE: без EnemyLook (соперник лиги не «сломанная программа» — своя краска и цвет игрока P2), цель — группа
## "players", свои — "rivals". Уровень 1..4 — Tuning.RIVAL_LEVELS (реакция, прицел, упреждение, отход, рывок).
class_name RivalBrain
extends EnemyBrain

const NEAR_X_M := 1.3        # ближе по x (и по y NEAR_Y_M) — наскок состоялся, отход
const NEAR_Y_M := 1.2
const DASH_FROM_M := 2.0     # рывок с разбега не ближе этого (кулдаун — у куклы, Tuning.DASH_COOLDOWN_S)
const CLIMB_FROM_M := 0.8    # цель выше / ниже больше этого — тяга по вертикали к ней
const CLIMB_SCALE_M := 1.5

@export var level := 1

var retreat_s := 1.2
var use_dash := true


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	doll.external_input = true
	arena = get_tree().get_first_node_in_group("arena")
	doll.damaged.connect(_on_damaged)
	doll.knocked_out.connect(func(_a: Node, _r: Dictionary) -> void: _on_ko())
	_brain_ready()


func _brain_ready() -> void:
	players_group = "players"
	enemies_group = "rivals"
	var p: Dictionary = Tuning.RIVAL_LEVELS.get(level, Tuning.RIVAL_LEVELS[1])
	reaction_s = float(p.get("reaction_s", reaction_s))
	aim_error_m = float(p.get("aim_error_m", aim_error_m))
	lead_s = float(p.get("lead_s", lead_s))
	retreat_s = float(p.get("retreat_s", retreat_s))
	use_dash = bool(p.get("dash", true))
	go("approach")


func _think(_delta: float) -> void:
	if target == null or not is_instance_valid(target) or not target.alive:
		want = hover_vec()
		return
	var to := predicted() - my_pos()
	var sgn := signf(to.x) if absf(to.x) > 0.05 else 1.0
	var vy := clampf(to.y / CLIMB_SCALE_M, -1.0, 1.0) if absf(to.y) > CLIMB_FROM_M else hover_vec().y
	match state:
		"retreat":
			want = Vector2(-sgn, hover_vec().y)
			if state_t >= retreat_s:
				go("approach")
		_:
			if absf(to.x) < NEAR_X_M and absf(to.y) < NEAR_Y_M:
				note_attack()
				go("retreat")
				want = Vector2(-sgn, hover_vec().y)
				return
			want = Vector2(sgn, vy)
			if use_dash and absf(to.x) > DASH_FROM_M:
				dash()


func _stuck_allowed() -> bool:
	return state in ["approach", "retreat"]
