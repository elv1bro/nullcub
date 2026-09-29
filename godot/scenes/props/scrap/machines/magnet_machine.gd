## №079 Swinging Magnet / №070 Magnetic Crane (лист 04): электромагнит на цепи раскачивается маятником под балкой-рельсом и,
## когда включён, тянет железо. Дерево — scenes/props/scrap/machine_magnet.tscn: Gantry (балка, декор без коллизий) → Pivot (точка
## подвеса, поворот вокруг z) → Chain_* (цепь 2-метровыми модулями) и Head (AnimatableBody3D: цилиндр-«таблетка» на плоскости боя,
## о него бьются и на нём стоят) → Pole (Marker3D, центр рабочей поверхности), LampLight (свет снизу), Sparks (искры по кромке).
##
## Маятник кинематический: угол = swing_deg · sin(2π t / swing_period_s), всегда (и в OFF) — медленная качка, |v| ≤ 2.5 м/с.
## Цикл (ScrapMachine): WARNING — лампы мигают, гудок, гул и искры; ACTIVE — рабочее кольцо светится, тянет; COOLDOWN — сила
## гаснет за RELEASE_S, всё прилипшее падает (вечного прилипания нет: тянет только active_s из цикла).
## Сила на тело — к полюсу, в плоскости XY: F = min(accel · m_железа, force_max) · спад(r) · близость(r) · мощность, где
##   спад = 1 при r ≤ full_radius, плавно до 0 к pull_radius; близость = clamp(r / near_radius, NEAR_MIN, 1) — вплотную тянет
##   слабее (предмет висит под магнитом, а не вминается); мощность — нарастает RAMP_S в начале ACTIVE;
##   плюс демпфер относительной скорости damp · m · спад (без «пинг-понга» у полюса).
## Кг железа — ScrapMachine.iron_mass(): meta "material" тела (железные пропсы, куски, лут; у модульной куклы — итоговый материал
## детали), иначе оружие и детали крафта PartDef.material "iron" (у ModularDoll — части с железными деталями: кукла с железной
## рукой тянется сама), куски хлама по имени. Дерево (ящики, куклы-клёны) — 0: не трогает.
## Сумма сил на одну куклу ≤ doll_force_max (меньше её веса 80 Н: не поднимает целиком, тянет железную руку / оружие).
## Числа (g = 2): железная бочка 40 кг — до 180 Н > 80 Н веса: поднимается, если полюс ближе ~4.2 м (на арене полюс на 3.6 м
## над полом — бочку прямо под ним поднимает за ~1.5 с); молот 6 кг (4.2 кг железа) — 67 Н; железное предплечье 3 кг + кулак
## 2 кг — 48 + 32 Н, у куклы режется до doll_force_max (мышцы плеча ≈ 23 Н у кисти — рука тянется к магниту: проба +0.77 м за 1 с).
class_name MagnetMachine
extends ScrapMachine

const NEAR_MIN := 0.3
const RAMP_S := 0.3
const RELEASE_S := 0.35
const FIELD_DEPTH := 1.6
const FIELD_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))   # ось цилиндра Y → Z

@export var swing_deg := 14.0
@export var swing_period_s := 7.0
@export var pull_radius := 5.5
@export var full_radius := 3.0
@export var near_radius := 1.0
@export var accel := 16.0              # м/с² на кг железа
@export var force_max := 180.0         # Н на тело
@export var doll_force_max := 70.0     # Н на куклу (сумма по частям)
@export var damp := 0.5                # 1/с

var pivot: Node3D
var head: AnimatableBody3D
var pole: Node3D
var sparks: GPUParticles3D
## Последний тик: тело → приложенная сила (Vector3) — для проб; сумма модулей сил.
var last_forces: Dictionary = {}
var last_total_force := 0.0
var _shape: CylinderShape3D          # зона притяжения: круг pull_radius в плоскости XY, толщина FIELD_DEPTH (не цепляет вал куч)
var _exclude: Array[RID] = []
var _power := 0.0


func _machine_ready() -> void:
	pivot = get_node_or_null("Pivot") as Node3D
	head = get_node_or_null("Pivot/Head") as AnimatableBody3D
	pole = get_node_or_null("Pivot/Head/Pole") as Node3D
	sparks = get_node_or_null("Pivot/Head/Sparks") as GPUParticles3D
	_shape = CylinderShape3D.new()
	_shape.radius = pull_radius
	_shape.height = FIELD_DEPTH
	if head != null:
		_exclude = [head.get_rid()]
	_swing()


func pole_global() -> Vector3:
	return pole.global_position if pole != null else global_position


## Угол маятника (градусы) сейчас.
func swing_angle() -> float:
	return swing_deg * sin(TAU * time / maxf(swing_period_s, 0.1))


func _swing() -> void:
	if pivot != null:
		pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(swing_angle()))


func _on_state(s: int, _prev: int) -> void:
	match s:
		State.WARNING:
			play_sfx("beep")
		State.ACTIVE:
			play_sfx("hum", 0.8)
	if sparks != null:
		sparks.emitting = s == State.WARNING or s == State.ACTIVE


func _machine_tick(_delta: float) -> void:
	_swing()
	match state:
		State.ACTIVE:
			_power = minf(state_t / RAMP_S, 1.0)
		State.COOLDOWN:
			_power = maxf(1.0 - state_t / RELEASE_S, 0.0)
		_:
			_power = 0.0
	last_forces.clear()
	last_total_force = 0.0
	if _power <= 0.0 or not is_inside_tree():
		return
	_pull()


func _pull() -> void:
	var p := pole_global()
	var head_v := Vector3.ZERO
	if head != null:
		var st := PhysicsServer3D.body_get_direct_state(head.get_rid())
		if st != null:
			head_v = st.linear_velocity
	var per_doll: Dictionary = {}   # Doll → [[body, force], …]
	var loose: Array = []
	for b in bodies_in(_shape, Transform3D(FIELD_BASIS, p), _exclude):
		var rb := b as RigidBody3D
		var m_iron := iron_mass(rb)
		if m_iron <= 0.0:
			continue
		var c := com_of(rb)
		var d := p - c
		d.z = 0.0
		var r := d.length()
		if r < 1e-3 or r > pull_radius:
			continue
		var fall := 1.0 if r <= full_radius else smoothstep(pull_radius, full_radius, r)
		var near := clampf(r / near_radius, NEAR_MIN, 1.0)
		# PropHeft (29.09): средние пропсы весят больше — gravity_scale 2.5; сила масштабируется так же, чтобы магнит тянул железо
		# «того же веса» как задумано (связка труб / бочка 40 кг поднимается), а не упирался в свой потолок force_max.
		# Куклы (gravity_scale 1) и якоря PropHeft (заморожены, в bodies_in не попадают) не меняются.
		var g_scale := maxf(1.0, rb.gravity_scale)
		var f := d / r * minf(accel * m_iron, force_max) * g_scale * fall * near * _power
		var rel := rb.linear_velocity - head_v
		rel.z = 0.0
		f -= rel * damp * minf(rb.mass, m_iron * 2.0) * fall * _power
		var dl := doll_of(rb)
		if dl != null:
			if not per_doll.has(dl):
				per_doll[dl] = []
			(per_doll[dl] as Array).append([rb, f])
		else:
			loose.append([rb, f])
	for dl in per_doll:
		var sum := 0.0
		for e in per_doll[dl]:
			sum += (e[1] as Vector3).length()
		var k := minf(1.0, doll_force_max / sum) if sum > 0.0 else 1.0
		for e in per_doll[dl]:
			loose.append([e[0], (e[1] as Vector3) * k])
	for e in loose:
		var rb2: RigidBody3D = e[0]
		var f2: Vector3 = e[1]
		if rb2.sleeping:
			rb2.sleeping = false
		rb2.apply_central_force(f2)
		last_forces[rb2] = f2
		last_total_force += f2.length()
