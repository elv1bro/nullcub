## N0 — дрон-ведущий NULL Arena (docs/plan-demo/ART_NULL.md, лист 2; лор — LORE_NULL.md §9–10).
## Только поведение: выражение на экране, ливрея, парение. Сцену собирает tools/build_n0.gd, модель — tools/blender/n0_drone.py.
##
## Экран: материал N0_Screen берёт эмиссию из атласа 5 × 2 (assets/models/n0/n0_face_atlas.png); выражение = uv1_offset ячейки.
## Ливрея: основной и акцентный цвет краски (роли N0_Livery / N0_Accent) — свои копии материалов у каждого дрона.
## В бою не участвует: коллизий нет, это Node3D; в бою его двигает scripts/n0/n0_host.gd (рядом с игроком, реплики-субтитры).
##
## Тело (02.10.2026, автор: «нету анимации у N0, меняется только лицо — может, крыльями махать, двигаться»). Части качаются
## в плоскости экрана: камера смотрит в −Z, поворот вокруг Z виден, вокруг X — почти нет (старое покачивание было почти всё в X).
##   крылья-уши N0_Ear_L/R — взмахи: частота и размах растут со скоростью полёта (set_motion);
##   ножки N0_Legs_L/R — маятник на пружине: отстают на разгоне и раскачиваются после остановки;
##   руки N0_Arm_L/R — направление от плеча и телескоп (_aim): жесты выдвигают их из-за шара корпуса; микрофон N0_Mic едет
##   за правой рукой;
##   talking — микрофон к экрану, левая жестикулирует;
##   жест на выражение (flash_expression → GESTURE_OF): excited — ликует, happy — машет, shocked — вздрагивает, worried / sad — сник,
##   curious / confused — задумался, angry — трясёт кулаками, glitch — дёргается; point_at(pos, secs) — показывает рукой.
## Жест входит за 0.15 с и выходит за 0.3 с (огибающая), поверх покоя.
class_name N0Drone
extends Node3D

const EXPRESSIONS: Array[String] = ["default", "happy", "excited", "shocked", "curious", "worried", "confused", "angry", "sad", "glitch"]
const ATLAS_COLS := 5
const ATLAS_ROWS := 2
## sRGB: (основной, акцент) — те же числа, что LIVERIES в n0_drone.py
const LIVERIES := {
	"default": [Color8(226, 214, 190), Color8(236, 168, 34)],
	"event": [Color8(196, 38, 34), Color8(236, 214, 190)],
	"support": [Color8(38, 104, 178), Color8(226, 214, 190)],
}
## среднее albedo набора paint_marks: цвет краски = цель / это число (как tint в Blender)
const PAINT_ALBEDO := 0.82
## Выражение → жест тела.
const GESTURE_OF := {"excited": "cheer", "happy": "wave", "shocked": "flinch", "worried": "droop", "sad": "droop",
	"curious": "tilt", "confused": "tilt", "angry": "shake", "glitch": "glitch"}
const GESTURES: Array[String] = ["cheer", "wave", "flinch", "droop", "tilt", "shake", "glitch", "point"]
const GESTURE_IN_S := 0.15
const GESTURE_OUT_S := 0.3

@export var expression: String = "default":
	set(v):
		expression = v
		_apply_expression()
@export var livery: String = "default":
	set(v):
		livery = v
		_apply_livery()
## покачивание, уши, ножки, мерцание двигателя
@export var idle := true
@export var bob_height := 0.035
@export var bob_hz := 0.45
## Говорит (N0Speech набирает реплику): корпус подпрыгивает в такт «слогам», крылья вздрагивают, микрофон у экрана,
## левая рука жестикулирует.
var talking := false

var _t := 0.0
var _screen_mat: StandardMaterial3D
var _livery_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _parts := {}          # имя узла → Node3D
var _rest := {}           # имя узла → исходный Transform3D
var _flash_left := 0.0
var _flash_back := "default"
var _ready_done := false
## Текущий жест ("" — покой) — для проб.
var gesture := ""
var _g_t := 0.0
var _g_dur := 0.0
var _point_at := Vector3.ZERO
var _vel := Vector3.ZERO
var _acc := Vector3.ZERO
var _flap := 0.0
var _leg_a := Vector2.ZERO       # отклонение ножек L / R (рад, вокруг Z)
var _leg_w := Vector2.ZERO
var _arm_dir := {}               # рука → направление в покое (от плеча к середине меша, модель)

@onready var model: Node3D = $Model


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # двигается в _process (не в физическом тике) — своя интерполяция физики дала бы запаздывание / дрожь
	for n in ["N0_Body", "N0_Screen", "N0_Ear_L", "N0_Ear_R", "N0_Legs_L", "N0_Legs_R", "N0_Arm_L", "N0_Arm_R", "N0_Mic"]:
		var node := model.get_node_or_null(n) as Node3D
		if node != null:
			_parts[n] = node
			_rest[n] = node.transform
			if n.begins_with("N0_Arm") and node is MeshInstance3D:
				_arm_dir[n] = (node as MeshInstance3D).get_aabb().get_center().normalized()
	_t = randf() * 10.0
	_make_materials()
	_ready_done = true
	_apply_livery()
	_apply_expression()


## Выражение по имени (EXPRESSIONS); неизвестное — false, экран не меняется.
func set_expression(name: String) -> bool:
	if not EXPRESSIONS.has(name):
		return false
	expression = name
	return true


## Показать выражение на secs секунд, затем вернуть прежнее (реакция на удар, голосование).
func flash_expression(name: String, secs: float) -> void:
	if not EXPRESSIONS.has(name):
		return
	if _flash_left <= 0.0:
		_flash_back = expression
	_flash_left = secs
	expression = name
	if GESTURE_OF.has(name):
		play_gesture(String(GESTURE_OF[name]), secs)


## Жест тела на secs секунд (GESTURES); тот же жест посреди показа — продлевается без нового входа.
func play_gesture(name: String, secs: float) -> void:
	if not GESTURES.has(name) or secs <= 0.0:
		return
	if name == gesture and _g_t < _g_dur:
		_g_t = minf(_g_t, GESTURE_IN_S)
	else:
		_g_t = 0.0
	gesture = name
	_g_dur = secs


## Показать рукой на точку мира: правой (с микрофоном), если точка правее, иначе левой.
func point_at(world_pos: Vector3, secs: float) -> void:
	_point_at = world_pos
	play_gesture("point", secs)


## Скорость и ускорение полёта (м/с, м/с²) от n0_host.gd: крылья машут чаще, ножки отстают, двигатель ярче.
func set_motion(vel: Vector3, acc: Vector3) -> void:
	_vel = vel
	_acc = _acc.lerp(acc, 0.3)


## Огибающая жеста 0..1.
func gesture_weight() -> float:
	if gesture == "" or _g_dur <= 0.0:
		return 0.0
	var a := clampf(_g_t / GESTURE_IN_S, 0.0, 1.0)
	var b := clampf((_g_dur - _g_t) / GESTURE_OUT_S, 0.0, 1.0)
	return smoothstep(0.0, 1.0, a) * smoothstep(0.0, 1.0, b)


func part(name: String) -> Node3D:
	return _parts.get(name) as Node3D


func mesh_nodes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(model, out)
	return out


func screen_uv_offset() -> Vector3:
	return _screen_mat.uv1_offset if _screen_mat != null else Vector3.ZERO


func livery_color() -> Color:
	return _livery_mat.albedo_color if _livery_mat != null else Color.BLACK


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			expression = _flash_back
	if not idle:
		return
	_t += delta
	if gesture != "":
		_g_t += delta
		if _g_t >= _g_dur:
			gesture = ""
	_animate(delta)
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 4.0 + sin(_t * 37.0) * 0.6 + sin(_t * 23.0) * 0.4 + minf(_speed(), 12.0) * 0.25
	if expression == "glitch" and _screen_mat != null:
		_screen_mat.uv1_offset.x = _cell_offset(expression).x + (randf() - 0.5) * 0.012


func _speed() -> float:
	return Vector2(_vel.x, _vel.y).length()


## Поза частей на кадр: покой + полёт + разговор, поверх — жест с огибающей.
func _animate(delta: float) -> void:
	var w := TAU * bob_hz
	var sp := minf(_speed(), 10.0)
	var talk := absf(sin(_t * 15.0)) if talking else 0.0
	# покой и полёт
	var bob := sin(_t * w) * bob_height + talk * 0.03
	var body := Vector3(sin(_t * w * 0.5) * 0.04, sin(_t * 0.23 * TAU) * 0.06, sin(_t * w + 0.8) * 0.03)
	_flap += delta * TAU * (1.1 + sp * 0.22)
	var flap_amp := 0.14 + sp * 0.028
	var splay := 0.10 + talk * 0.12
	var ear_x := sin(_t * w - 0.9) * 0.08
	var ear_l_extra := 0.0
	var ear_r_extra := 0.0
	# руки — направление «от плеча» в осях модели (x вправо, y вверх, z к камере); руки короткие и сидят за шаром корпуса,
	# поэтому жесты выводят их вбок, вверх или к экрану — туда, где их видно
	var arm_l := Vector3(-0.3 + sin(_t * w * 0.8 - 0.5) * 0.08, -0.55 + sin(_t * w * 0.6) * 0.08, 0.75)
	var arm_r := Vector3(0.4, -0.3 + sin(_t * w * 0.7) * 0.06, 0.85)
	var reach_l := 0.0      # телескоп: насколько рука выдвинута от плеча (м) — иначе её не видно из-за шара
	var reach_r := 0.0
	if talking:
		arm_r = arm_r.lerp(Vector3(0.15, 0.2, 1.0), 0.9)                 # микрофон к экрану
		arm_l = arm_l.lerp(Vector3(-0.75, 0.05 + sin(_t * 3.1) * 0.35 + talk * 0.15, 0.55), 0.9)
		reach_r = 0.1
		reach_l = 0.07
	# жест
	var e := gesture_weight()
	var gt := _g_t
	if e > 0.0:
		match gesture:
			"cheer":    # ликует: руки вверх в стороны и качает, крылья часто, подпрыгивает
				var pump := sin(gt * 9.0) * 0.25
				arm_l = arm_l.lerp(Vector3(-0.75, 0.65 + pump, 0.2), e)
				arm_r = arm_r.lerp(Vector3(0.75, 0.65 - pump, 0.2), e)
				reach_l = lerpf(reach_l, 0.16, e)
				reach_r = lerpf(reach_r, 0.16, e)
				_flap += delta * TAU * 2.5 * e
				flap_amp = lerpf(flap_amp, 0.5, e)
				splay = lerpf(splay, 0.35, e)
				bob += absf(sin(gt * 9.0)) * 0.06 * e
			"wave":     # машет левой рукой
				var a := 2.35 + sin(gt * 10.0) * 0.45                   # угол в плоскости экрана: вверх-влево ± взмах
				arm_l = arm_l.lerp(Vector3(cos(a), sin(a), 0.25), e)
				reach_l = lerpf(reach_l, 0.17, e)
				body.z += sin(gt * 5.0) * 0.08 * e
				flap_amp = lerpf(flap_amp, 0.3, e)
			"flinch":   # вздрогнул: руки врозь и вниз, крылья прижаты в стороны, дрожь, откинулся назад
				arm_l = arm_l.lerp(Vector3(-0.9, -0.3, 0.35), e)
				arm_r = arm_r.lerp(Vector3(0.9, -0.3, 0.35), e)
				reach_l = lerpf(reach_l, 0.18, e)
				reach_r = lerpf(reach_r, 0.18, e)
				splay = lerpf(splay, 0.95, e)
				flap_amp = lerpf(flap_amp, 0.04, e)
				body.x -= 0.18 * e
				body.z += sin(gt * 47.0) * 0.04 * e
			"droop":    # сник: крылья повисли, руки висят, просел и опустил голову
				splay = lerpf(splay, 1.25, e)
				flap_amp = lerpf(flap_amp, 0.03, e)
				arm_l = arm_l.lerp(Vector3(-0.3, -1.0, 0.2), e)
				arm_r = arm_r.lerp(Vector3(0.3, -1.0, 0.2), e)
				reach_l = lerpf(reach_l, 0.08, e)
				reach_r = lerpf(reach_r, 0.08, e)
				bob -= 0.07 * e
				body.x += 0.16 * e
			"tilt":     # задумался: голова набок, одно крыло вверх, рука под экраном («подбородок»)
				body.z += 0.32 * e
				ear_l_extra = -0.2 * e
				ear_r_extra = 0.55 * e
				arm_l = arm_l.lerp(Vector3(0.35, -0.15, 1.0), e)
				reach_l = lerpf(reach_l, 0.15, e)
			"shake":    # злится: трясёт кулаками перед собой
				var sh := sin(gt * 18.0) * 0.35
				arm_l = arm_l.lerp(Vector3(-0.6, 0.15 + sh, 0.75), e)
				arm_r = arm_r.lerp(Vector3(0.6, 0.15 - sh, 0.75), e)
				reach_l = lerpf(reach_l, 0.13, e)
				reach_r = lerpf(reach_r, 0.13, e)
				body.y += sin(gt * 14.0) * 0.12 * e
			"glitch":   # сбой: рывки раз в 0.09 с
				var k := int(gt / 0.09)
				arm_l += Vector3(_hash(k, 1) - 0.5, _hash(k, 2) - 0.5, 0.0) * 1.6 * e
				arm_r += Vector3(_hash(k, 3) - 0.5, _hash(k, 4) - 0.5, 0.0) * 1.6 * e
				splay += (_hash(k, 5) - 0.5) * 1.2 * e
				body.z += (_hash(k, 6) - 0.5) * 0.4 * e
				reach_l = _hash(k, 7) * 0.15 * e
				reach_r = _hash(k, 8) * 0.15 * e
			"point":    # показывает рукой на точку: правой (с микрофоном), если точка правее, иначе левой
				var lp := model.to_local(_point_at)
				var right := lp.x >= 0.0
				var v := lp - (_rest.get("N0_Arm_R" if right else "N0_Arm_L", Transform3D()) as Transform3D).origin
				if v.length() > 1e-3:
					if right:
						arm_r = arm_r.lerp(v.normalized(), e)
						reach_r = lerpf(reach_r, 0.2, e)
					else:
						arm_l = arm_l.lerp(v.normalized(), e)
						reach_l = lerpf(reach_l, 0.2, e)
					body.z -= signf(v.x) * 0.12 * e
	model.position = Vector3(0.0, bob, 0.0)
	model.rotation = body
	var flap := sin(_flap) * flap_amp
	_swing("N0_Ear_L", Vector3(ear_x, 0.0, splay + flap + ear_l_extra))
	_swing("N0_Ear_R", Vector3(ear_x, 0.0, -(splay + flap + ear_r_extra)))
	# ножки: маятник на пружине; разгон вправо — кончики отстают влево
	var want := clampf(-_acc.x * 0.035, -0.7, 0.7) + sin(_t * w * 0.5) * 0.05
	for i in 2:
		var stiff := 60.0 if i == 0 else 46.0
		_leg_w[i] += ((want - _leg_a[i]) * stiff - _leg_w[i] * 5.0) * delta
		_leg_a[i] += _leg_w[i] * delta
	_swing("N0_Legs_L", Vector3(0.0, 0.0, _leg_a[0] + 0.06))
	_swing("N0_Legs_R", Vector3(0.0, 0.0, _leg_a[1] - 0.06))
	_aim("N0_Arm_L", arm_l, reach_l)
	_aim("N0_Arm_R", arm_r, reach_r)
	# микрофон в правой руке: тот же поворот вокруг плеча
	if _parts.has("N0_Mic") and _parts.has("N0_Arm_R"):
		var arm := _parts["N0_Arm_R"] as Node3D
		var d: Transform3D = arm.transform * (_rest["N0_Arm_R"] as Transform3D).affine_inverse()
		(_parts["N0_Mic"] as Node3D).transform = d * (_rest["N0_Mic"] as Transform3D)


## Повернуть руку вокруг плеча так, чтобы её направление в покое (_arm_dir) смотрело вдоль dir (оси модели), и выдвинуть
## на reach метров вдоль dir (телескоп).
func _aim(n: String, dir: Vector3, reach: float = 0.0) -> void:
	if not _parts.has(n) or not _arm_dir.has(n) or dir.length() < 1e-4:
		return
	var rest: Transform3D = _rest[n]
	var d := dir.normalized()
	var q := Quaternion(_arm_dir[n] as Vector3, d)
	(_parts[n] as Node3D).transform = Transform3D(Basis(q) * rest.basis, rest.origin + d * maxf(reach, 0.0))


## Куда сейчас смотрит рука (оси модели) — для проб.
func arm_direction(n: String) -> Vector3:
	if not _parts.has(n) or not _arm_dir.has(n):
		return Vector3.ZERO
	var rest: Transform3D = _rest[n]
	return ((_parts[n] as Node3D).transform.basis * rest.basis.inverse()) * (_arm_dir[n] as Vector3)


static func _hash(k: int, salt: int) -> float:
	return fposmod(sin(float(k * 31 + salt * 17) * 12.9898) * 43758.5453, 1.0)


func _swing(n: String, euler: Vector3) -> void:
	if not _parts.has(n):
		return
	var rest: Transform3D = _rest[n]
	(_parts[n] as Node3D).transform = Transform3D(rest.basis * Basis.from_euler(euler), rest.origin)


func _make_materials() -> void:
	for mi in mesh_nodes():
		for i in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if m == null:
				continue
			match m.resource_name:
				"N0_Screen":
					if _screen_mat == null:
						_screen_mat = m.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, _screen_mat)
				"N0_Livery":
					if _livery_mat == null:
						_livery_mat = m.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, _livery_mat)
				"N0_Accent":
					if _accent_mat == null:
						_accent_mat = m.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, _accent_mat)
				"N0_Glow":
					if _glow_mat == null:
						_glow_mat = m.duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, _glow_mat)


func _apply_expression() -> void:
	if not _ready_done or _screen_mat == null:
		return
	if not EXPRESSIONS.has(expression):
		push_warning("N0: нет выражения «%s»" % expression)
		return
	_screen_mat.uv1_scale = Vector3(1.0 / ATLAS_COLS, 1.0 / ATLAS_ROWS, 1.0)
	_screen_mat.uv1_offset = _cell_offset(expression)


func _cell_offset(name: String) -> Vector3:
	var i := EXPRESSIONS.find(name)
	return Vector3(float(i % ATLAS_COLS) / ATLAS_COLS, float(i / ATLAS_COLS) / ATLAS_ROWS, 0.0)


func _apply_livery() -> void:
	if not _ready_done or not LIVERIES.has(livery):
		return
	var pair: Array = LIVERIES[livery]
	if _livery_mat != null:
		_livery_mat.albedo_color = _paint(pair[0])
	if _accent_mat != null:
		_accent_mat.albedo_color = _paint(pair[1])


static func _paint(c: Color) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r / PAINT_ALBEDO, l.g / PAINT_ALBEDO, l.b / PAINT_ALBEDO).linear_to_srgb()


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
