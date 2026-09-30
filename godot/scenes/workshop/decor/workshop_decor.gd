## Декор мастерской «про историю» (UI/UX spec v0.3 §3, §50) — узел Decor в scenes/workshop/workshop_build.tscn: прототип руки на цепи,
## чертёж на стене, образцы материалов с бумажными бирками на полочке, ящик с запасными головами и ногами, шестерни у стены.
## Всё — по краям кадра сборки и у задней стены (z ≈ −0.8…−1.15), вдали от силуэта куклы и от плоскости боя испытания (z = 0).
## Только меши из существующих glb кита и примитивы: тел и коллизий нет, поэтому манекен, ящик и бочка испытания сквозь декор
## не цепляются. Детали кита покрыты «пылью» (material_overlay): прототипы на складе — тусклее и серее живой куклы на стенде,
## фон остаётся низкоконтрастным даже там, где на него падает свет ламп.
class_name WorkshopDecor
extends Node3D

## Пыль поверх деталей кита и железа из glb (выключить — родные цвета). Свои примитивы (ящик, полочка, чертёж) и так приглушены.
@export var dust := true
@export var dust_color := Color(0.3, 0.27, 0.23, 0.55)
@export var dusty: Array[NodePath] = [^"HangingArm", ^"PartsCrate/SpareHead", ^"PartsCrate/SpareLeg", ^"PartsCrate/SpareBot",
	^"Gears"]

var _dust_mat: StandardMaterial3D


func _ready() -> void:
	_strip_physics(self)
	if dust:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.albedo_color = dust_color
		_dust_mat.roughness = 1.0
		_dust_mat.metallic_specular = 0.1
		for path in dusty:
			var n := get_node_or_null(path)
			if n != null:
				for g in n.find_children("*", "GeometryInstance3D", true, false):
					(g as GeometryInstance3D).material_overlay = _dust_mat


## Декор — только картинка: если в импортированном glb окажется тело (коллизия из имени «-col» и т. п.), выключаем его, чтобы
## куклы испытания и брошенные предметы не спотыкались о фон.
func _strip_physics(n: Node) -> void:
	for c in n.get_children():
		if c is CollisionObject3D:
			var co := c as CollisionObject3D
			co.collision_layer = 0
			co.collision_mask = 0
			co.process_mode = Node.PROCESS_MODE_DISABLED
			if co is RigidBody3D:
				(co as RigidBody3D).freeze = true
		_strip_physics(c)


## Сколько в декоре тел с непустыми слоями (для проб: должно быть 0).
func live_bodies() -> int:
	var out := 0
	for c in find_children("*", "CollisionObject3D", true, false):
		var co := c as CollisionObject3D
		if co.collision_layer != 0 or co.collision_mask != 0:
			out += 1
	return out
