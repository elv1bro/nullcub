## Арена «Мастерская» (референс docs/refs/R22-a-hero-workshop-fight.jpg, ART_DIRECTION.md v3 §5) — только поведение.
## Сцена workshop.tscn собрана builder-ом tools/build_arena_workshop.gd ИЗ КОМПОНЕНТНЫХ СЦЕН scenes/props/workshop_*.tscn
## (+ barrel/crate): пол из плиток, верстаки, штабели, полки, станок, козлы, лампы на цепях, стены с окнами, щиты с
## инструментом, стружка, потолочные балки, свет, туман, пыль. Закрытое помещение: ям и DeathZone нет — сигнал body_fell
## оставлен для паритета API с RuinsArena и никогда не испускается.
## Здесь: точки спавна (Spawns/Spawn*), границы для камеры и боя, доступ к компонентам, демпфирование качания ламп,
## а также gi_mode DYNAMIC для мешей под RigidBody3D (лампы, козлы, бочки, ящики): иначе SDFGI из workshop_env.tres
## перевокселизирует каскад при каждом их движении (качающаяся лампа → ~90 мс на кадр).
class_name WorkshopArena
extends Node3D

@warning_ignore("unused_signal")
signal body_fell(body: Node3D)

## Границы: невидимые стены x=±13, пол y=0, потолок y=10 — для камеры (у DynamicCamera floor_inset здесь должен быть 0:
## ниже пола смотреть нечего) и боя.
@export var arena_bounds := AABB(Vector3(-13.0, 0.0, -1.0), Vector3(26.0, 10.0, 2.0))
## Демпфирование маятника лампы (Lamps/*/Body): без него цепь качается минутами.
@export var lamp_angular_damp := 0.35
@export var lamp_linear_damp := 0.12


## Mobile / Compatibility (perf-pass): нет SSIL и объёмного тумана — тёплую подсветку стен (отражённый свет) даёт ambient, а лучи из окон —
## плоские аддитивные квады вдоль солнца (light_shaft.gdshader). В Forward+ ничего не меняется.
const LIGHT_SHAFT := preload("res://scenes/arena/light_shaft.gdshader")
@export var cheap_ambient_energy := 1.0
@export var cheap_ambient_color := Color(0.46, 0.36, 0.30)
## Центры верхних окон (x, y) и сила луча из каждого.
@export var shaft_windows: Array[Vector3] = [Vector3(-8.0, 7.2, 1.0), Vector3(0.0, 7.2, 0.3)]
@export var shaft_length := 13.0
@export var shaft_width := 6.0
@export var shaft_z := -0.9


func _ready() -> void:
	if RenderingServer.get_current_rendering_method() in ["mobile", "gl_compatibility"]:
		_cheap_look()
	for lamp in lamps():
		var body := lamp.get_node_or_null("Body") as RigidBody3D
		if body != null:
			body.angular_damp = lamp_angular_damp
			body.linear_damp = lamp_linear_damp
	for g in ["Lamps", "Props"]:
		var holder := get_node_or_null(g)
		if holder != null:
			_gi_dynamic_under_rigid(holder, false)


func _cheap_look() -> void:
	var we := get_node_or_null("Environment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = cheap_ambient_color
		we.environment.ambient_light_energy = cheap_ambient_energy
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		return
	var dir := Vector2(-sun.global_basis.z.x, -sun.global_basis.z.y)   # куда идёт свет на экране (XY)
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	var holder := Node3D.new()
	holder.name = "LightShafts"
	add_child(holder)
	for w in shaft_windows:
		var q := QuadMesh.new()
		q.size = Vector2(shaft_length, shaft_width)
		var mat := ShaderMaterial.new()
		mat.shader = LIGHT_SHAFT
		mat.set_shader_parameter("intensity", 0.22 * w.z)
		mat.set_shader_parameter("edge", 0.5)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "Shaft"
		holder.add_child(mi)
		var origin := Vector2(w.x, w.y) + dir * shaft_length * 0.5
		mi.position = Vector3(origin.x, origin.y, shaft_z)
		mi.rotation.z = dir.angle()


func _gi_dynamic_under_rigid(n: Node, under_rigid: bool) -> void:
	var rigid := under_rigid or n is RigidBody3D
	if rigid and n is GeometryInstance3D:
		(n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for c in n.get_children():
		_gi_dynamic_under_rigid(c, rigid)


## Четыре точки спавна (мировые координаты) из маркеров Spawns/Spawn0..3.
func spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Spawns")
	if holder:
		for m in holder.get_children():
			if m is Node3D:
				out.append((m as Node3D).global_position)
	return out


func bounds() -> AABB:
	return arena_bounds


## Разрушаемые пропсы (Props/*, Breakable) — живые, не обломки.
func breakables() -> Array:
	var out: Array = []
	var holder := get_node_or_null("Props")
	if holder:
		for c in holder.get_children():
			if c is Breakable:
				out.append(c)
	return out


## Подвесные лампы (Lamps/*): у каждой Body (RigidBody3D), Light (SpotLight3D) и Joint.
func lamps() -> Array:
	var out: Array = []
	var holder := get_node_or_null("Lamps")
	if holder:
		for c in holder.get_children():
			if c is Node3D:
				out.append(c)
	return out


## Козлы (Props/Sawhorse*, RigidBody3D 8 кг) — сбиваются ударом.
func sawhorses() -> Array:
	var out: Array = []
	var holder := get_node_or_null("Props")
	if holder:
		for c in holder.get_children():
			if c is RigidBody3D and String(c.name).begins_with("Sawhorse"):
				out.append(c)
	return out


## Ходибельные площадки (Left/Centre/Right: верстаки, штабели, полки, станок) — StaticBody3D.
func platforms() -> Array:
	var out: Array = []
	for g in ["Left", "Centre", "Right"]:
		var holder := get_node_or_null(g)
		if holder:
			for c in holder.get_children():
				if c is StaticBody3D:
					out.append(c)
	return out


func window_walls() -> Array:
	return find_children("*", "WorkshopWindowWall", true, false)
