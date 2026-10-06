## Тяжёлое в руке — тяга меньше (docs/plan-demo/PUZZLE.md «Ящик вдвоём»). Ребёнок куклы игрока головоломок (ставит PuzzlePlayground;
## Match.respawn_doll переносит его, как ArmAssist).
## Зачем. Средний предмет (PropHeft.MEDIUM / HEAVY, не приваренный) рука держит пружиной до ArmAssist.HOLD_F_MAX (150 Н), а тяга куклы
## 480 Н: вдвоём с ящиком 60 кг (вес 210 Н) пружины разгоняют его вверх на (300 − 210) / 60 = 1.5 м/с², а куклы — на
## (480 − 80 − 150) / 40 = 6.2 м/с²: улетают, пружины растягиваются за предел срыва, ящик падает (проба: подъём 0.1 м, срыв через 0.6 с).
## Пока главная рука держит такой предмет, тяга куклы × Tuning.PUZZLE_CARRY_THRUST_MULT (0.55: 264 − 80 − 150 = 34 Н → 0.85 м/с² —
## медленнее ящика, он догоняет, пружины не растягиваются без конца). Предел срыва у тяжёлых ящиков головоломок свой
## (Tuning.PUZZLE_CRATE_SLIP_M, meta ArmAssist.SLIP_META): пока две пружины делят груз, одна тянется дальше 0.45 м.
## Поводок: пружина растянута дальше Tuning.PUZZLE_CARRY_LEASH_FROM_M — скорость ЦМ куклы «от груза» (вдоль растяжения, относительно
## точки хвата на грузе) не больше PUZZLE_CARRY_AWAY_MAX × доля, которая падает до 0 к PUZZLE_CARRY_LEASH_TO_M; лишнее снимается
## со всех деталей поровну (сдвиг скоростей целиком — суставы не трогаются). Тот, кто тянет сильнее, не убегает, пока второй не
## натянет свою пружину, — груз делится поровну; один ящик «вдвоём» не поднимет (150 < 210) и висит над ним, натянув руку.
## Лёгкое (приваривается) — как было.
class_name PuzzleCarry
extends Node

const NODE_NAME := "PuzzleCarry"

var doll: Doll
var _set := false


static func attach_to(d: Doll) -> PuzzleCarry:
	var have := d.get_node_or_null(NODE_NAME) as PuzzleCarry
	if have != null:
		return have
	var c := PuzzleCarry.new()
	c.name = NODE_NAME
	d.add_child(c)
	return c


func _ready() -> void:
	doll = get_parent() as Doll


func _exit_tree() -> void:
	if _set and doll != null and is_instance_valid(doll):
		doll.thrust_mult = 1.0
	_set = false


## Держит ли кукла тяжёлое (средний или тяжёлый класс, не приварено).
static func carrying_heavy(d: Doll) -> bool:
	var a := PuzzlePlayground._arm(d)
	if a == null or not a.is_holding() or a.is_welded():
		return false
	return PropHeft.heft_of(a.held) != PropHeft.Heft.LIGHT


## Доля допустимой скорости «от груза» по растяжению пружины: 1 до LEASH_FROM_M, 0 с LEASH_TO_M.
static func leash(stretch: float) -> float:
	var from: float = Tuning.PUZZLE_CARRY_LEASH_FROM_M
	var to: float = Tuning.PUZZLE_CARRY_LEASH_TO_M
	return clampf(1.0 - (stretch - from) / maxf(to - from, 0.01), 0.0, 1.0)


func _physics_process(_delta: float) -> void:
	if doll == null or not is_instance_valid(doll):
		return
	if not (doll.alive and carrying_heavy(doll)):
		if _set:
			doll.thrust_mult = 1.0
			_set = false
		return
	doll.thrust_mult = Tuning.PUZZLE_CARRY_THRUST_MULT
	_set = true
	var a := PuzzlePlayground._arm(doll)
	var s := a.hold_distance()
	if s <= Tuning.PUZZLE_CARRY_LEASH_FROM_M:
		return
	var anchor := a.held.to_global(a.anchor_local)
	var away := a.grip_global() - anchor
	away.z = 0.0
	if away.length() < 1e-4:
		return
	away = away.normalized()
	var cap: float = Tuning.PUZZLE_CARRY_AWAY_MAX * leash(s)
	var rel := (doll.com_velocity() - ArmAssist._point_velocity(a.held, anchor)).dot(away)
	if rel <= cap:
		return
	var dv := away * (rel - cap)
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		if rb != null and is_instance_valid(rb):
			rb.linear_velocity -= dv
