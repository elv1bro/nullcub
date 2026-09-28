## Builder компонентных сцен мастерской (ART_DIRECTION.md §2 / v3 §5, лист R22): собирает деревья узлов из моделей
## assets/models/workshop/*.glb (tools/blender/workshop_props.py) и сохраняет res://scenes/props/workshop_*.tscn.
## Из них tools/build_arena_workshop.gd собирает арену scenes/arena/workshop.tscn. Скрипты сцен — только поведение
## (workshop_window_wall.gd: видимость задника/листвы; лампу демпфирует workshop.gd).
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_workshop_props_scenes.gd
## Повторный запуск перезаписывает сцены (правки, которые нужно сохранить, вносятся сюда).
##
## Куклы живут в плоскости z=0, поэтому у всего ходибельного коллизия пересекает z=0 (глубина ≥ 0.6 м):
##   workshop_floor_planks   StaticBody3D: бокс 12 × 0.5 × 2 под верхней плоскостью (origin = поверхность пола) + Floor_Tile.glb
##   workshop_bench          StaticBody3D: бокс 2.4 × 0.85 × 0.9 (верх = столешница 0.85) + Workbench.glb; тиски спереди слева
##   workshop_shelf          StaticBody3D: origin — верх полки у стены; доска видима 0.6 м в +Z, коллизия 2.0 × 0.06 × SHELF_COLL_D
##                           тянется от стены (z=0) до z=SHELF_COLL_D: стена стоит на z=WALL_Z<0, а кукла стоит на z=0 — с фронтальной
##                           камеры она читается стоящей на полке
##   workshop_lathe          StaticBody3D: станина 2.2 × 0.95 × 0.8 (верх = направляющие 0.95, по ним ходят) + передняя/задняя бабки,
##                           маховик (цилиндр вдоль X), заготовка (капсула) — препятствия на станине; Lathe.glb
##   workshop_plank_stack    StaticBody3D: бокс 1.6 × 0.5 × 0.6 + Plank_Stack.glb
##   workshop_sawhorse       RigidBody3D 8 кг (XY-плоскость, CCD): бокс 0.9 × 0.6 × 0.5 + Sawhorse.glb — сбиваются
##   workshop_window_wall    Node3D (workshop_window_wall.gd: в _ready снимает тень со стекла Glass — editable instance здесь не
##                           годится, PackedScene.pack() вшивает в .tscn весь меш glb), Foliage.glb за проёмом (пятнистые тени),
##                           Exterior — квад 5.4 × 12.4 на z=−2.7 с задником exterior_backdrop.png (unshaded + эмиссия, без тени, без тумана).
##                           Коллизии нет (стена стоит за плоскостью боя)
##   workshop_tool_board     Node3D + Tool_Board.glb (декор, вешать лицом +Z на стену)
##   workshop_lamp           Node3D, origin = точка подвеса: Anchor Marker3D; Body RigidBody3D 3 кг (сфера r 0.3 у абажура — центр масс
##                           внизу, маятник) + Lamp.glb + Light SpotLight3D вниз (без теней); Joint Generic6DOFJoint3D мир→Body,
##                           угловой Z ±80°. Цепь 3.6 м (LAMP_CHAIN), абажур y ∈ [−3.93, −3.68]
##   workshop_shavings       Node3D + Shavings_Wide.glb (декаль: alpha < порога opaque prepass — тени не даёт)
extends SceneTree

const DIR := "res://scenes/props/"
const GLB := "res://assets/models/workshop/%s.glb"
const BACKDROP := "res://assets/textures/workshop/exterior_backdrop.png"
const WINDOW_WALL_SCRIPT := "res://scenes/props/workshop_window_wall.gd"
const SHELF_COLL_D := 1.6      # глубина коллизии полки от стены (стена z=−1.2 → коллизия до z=+0.4)
const LAMP_CHAIN := 3.6
const SAWHORSE_MASS := 8.0
const LAMP_MASS := 3.0

var _wood: PhysicsMaterial
var _iron: PhysicsMaterial


func _init() -> void:
	_wood = PhysicsMaterial.new()
	_wood.friction = 0.9
	_wood.bounce = 0.05
	_iron = PhysicsMaterial.new()
	_iron.friction = 0.6
	_iron.bounce = 0.15
	_floor()
	_bench()
	_shelf()
	_lathe()
	_plank_stack()
	_sawhorse()
	_window_wall()
	_tool_board()
	_lamp()
	_shavings()
	print("workshop component scenes saved to ", DIR)
	quit(0)


# ---------------------------------------------------------------- helpers
func _glb(name: String) -> Node3D:
	var ps: PackedScene = load(GLB % name)
	if ps == null:
		push_error("missing " + (GLB % name) + " — run Blender workshop_props.py and godot --import")
		quit(1)
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.name = "Mesh"
	return n


func _set_owner(n: Node, root: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		_set_owner(c, root)


func _save(root: Node, file: String, uid: String) -> void:
	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %s: %d" % [file, err])
		quit(1)
		return
	var path := DIR + file + ".tscn"
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
		quit(1)
		return
	var id := ResourceUID.text_to_id("uid://" + uid)
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)
	ResourceSaver.set_uid(path, id)
	print("saved ", path, " (", _count(root), " nodes)")
	root.free()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _shape(parent: Node, name: String, shape: Shape3D, pos := Vector3.ZERO, rot_deg := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = name
	cs.shape = shape
	cs.position = pos
	cs.rotation_degrees = rot_deg
	parent.add_child(cs)
	return cs


func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _static(name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.physics_material_override = _wood
	return b


func _rigid(name: String, mass: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = name
	b.mass = mass
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	b.linear_damp = 0.2
	b.angular_damp = 0.5
	b.physics_material_override = _wood
	return b


# ---------------------------------------------------------------- scenes
func _floor() -> void:
	var root := _static("WorkshopFloor")
	_shape(root, "Shape", _box(Vector3(12.0, 0.5, 2.0)), Vector3(0, -0.25, 0))
	root.add_child(_glb("Floor_Tile"))
	_save(root, "workshop_floor_planks", "wsfloor00001")


func _bench() -> void:
	var root := _static("WorkshopBench")
	_shape(root, "Shape", _box(Vector3(2.4, 0.85, 0.9)), Vector3(0, 0.425, 0))
	root.add_child(_glb("Workbench"))
	_save(root, "workshop_bench", "wsbench00001")


func _shelf() -> void:
	var root := _static("WorkshopShelf")
	_shape(root, "Shape", _box(Vector3(2.0, 0.06, SHELF_COLL_D)), Vector3(0, -0.03, SHELF_COLL_D * 0.5))
	root.add_child(_glb("Shelf"))
	_save(root, "workshop_shelf", "wsshelf00001")


func _lathe() -> void:
	var root := _static("WorkshopLathe")
	_shape(root, "Bed", _box(Vector3(2.2, 0.95, 0.8)), Vector3(0, 0.475, 0))
	_shape(root, "Headstock", _box(Vector3(0.32, 0.42, 0.38)), Vector3(-0.75, 1.16, 0))
	_shape(root, "Tailstock", _box(Vector3(0.24, 0.36, 0.32)), Vector3(0.62, 1.13, 0))
	var wheel := CylinderShape3D.new()
	wheel.radius = 0.475
	wheel.height = 0.06
	_shape(root, "Wheel", wheel, Vector3(-1.05, 1.2, 0), Vector3(0, 0, 90))
	var work := CapsuleShape3D.new()
	work.radius = 0.075
	work.height = 0.98
	_shape(root, "Workpiece", work, Vector3(-0.06, 1.2, 0), Vector3(0, 0, 90))
	root.add_child(_glb("Lathe"))
	_save(root, "workshop_lathe", "wslathe00001")


func _plank_stack() -> void:
	var root := _static("WorkshopPlankStack")
	_shape(root, "Shape", _box(Vector3(1.6, 0.5, 0.6)), Vector3(0, 0.25, 0))
	root.add_child(_glb("Plank_Stack"))
	_save(root, "workshop_plank_stack", "wsstack00001")


func _sawhorse() -> void:
	var root := _rigid("Sawhorse", SAWHORSE_MASS)
	_shape(root, "Shape", _box(Vector3(0.9, 0.6, 0.5)), Vector3(0, 0.3, 0))
	root.add_child(_glb("Sawhorse"))
	_save(root, "workshop_sawhorse", "wssawhorse01")


func _window_wall() -> void:
	var root := Node3D.new()
	root.name = "WorkshopWindowWall"
	root.set_script(load(WINDOW_WALL_SCRIPT))
	var mesh := _glb("Wall_Window_4m")
	root.add_child(mesh)
	if mesh.find_child("Glass", true, false) == null:
		push_warning("Wall_Window_4m.glb: узел Glass не найден — workshop_window_wall.gd не сможет снять с него тень")
	# листва за проёмом (Foliage_Soft: тёмные силуэты, почти без эмиссии) — заглядывает в проём с боков, даёт пятнистые лучи
	var fol_ps: PackedScene = load(GLB % "Foliage_Soft")
	if fol_ps == null:
		fol_ps = load(GLB % "Foliage")
	if fol_ps != null:
		var fol := Node3D.new()
		fol.name = "Foliage"
		root.add_child(fol)
		for k in 2:
			var leaf: Node3D = fol_ps.instantiate()
			leaf.name = "Leaf%d" % k
			# плоскости 2.8 м скрещены под 25°/−65°: с поворотом ±20° их размах по z ≈ ±1.0 м — позади стены (толщина 0.29)
			leaf.position = Vector3(-1.5, 0.3, -1.6) if k == 0 else Vector3(1.6, 1.5, -1.75)
			leaf.rotation_degrees = Vector3(0, 20.0 if k == 0 else -20.0, 0)
			fol.add_child(leaf)
	# задник: квад 5.4 × 12.4 за стеной, покрывает оба ряда (y −0.2..12.2 при установке нижнего ряда на y=0)
	var ext := MeshInstance3D.new()
	ext.name = "Exterior"
	var quad := QuadMesh.new()
	quad.size = Vector2(5.4, 12.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.disable_fog = true
	mat.texture_repeat = false
	var tex: Texture2D = load(BACKDROP)
	if tex == null:
		push_warning("нет задника %s — python3 tools/blender/workshop_props.py --backdrop" % BACKDROP)
	else:
		mat.albedo_texture = tex
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_texture = tex
		mat.emission_energy_multiplier = 1.35
	quad.material = mat
	ext.mesh = quad
	ext.position = Vector3(0, 6.0, -2.7)
	ext.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ext.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(ext)
	_save(root, "workshop_window_wall", "wswinwall001")


func _tool_board() -> void:
	var root := Node3D.new()
	root.name = "WorkshopToolBoard"
	root.add_child(_glb("Tool_Board"))
	_save(root, "workshop_tool_board", "wstoolbrd001")


func _lamp() -> void:
	var root := Node3D.new()
	root.name = "WorkshopLamp"
	var anchor := Marker3D.new()
	anchor.name = "Anchor"
	root.add_child(anchor)
	var body := _rigid("Body", LAMP_MASS)
	body.physics_material_override = _iron
	body.linear_damp = 0.12
	body.angular_damp = 0.35
	body.continuous_cd = false
	root.add_child(body)
	var shade_y := -LAMP_CHAIN - 0.08 - 0.13
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	_shape(body, "Shape", sph, Vector3(0, shade_y, 0))
	var mesh := _glb("Lamp")
	body.add_child(mesh)
	var light := SpotLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, shade_y - 0.04, 0)
	light.rotation_degrees = Vector3(-90.0, 0, 0)   # −Z спота → вниз
	light.light_color = Color(1.0, 0.80, 0.54)
	light.light_energy = 7.0
	light.light_indirect_energy = 0.6
	light.light_volumetric_fog_energy = 1.5
	light.light_specular = 0.3
	light.spot_range = 9.0
	light.spot_angle = 55.0
	light.spot_angle_attenuation = 0.9
	light.spot_attenuation = 1.1
	light.shadow_enabled = false
	body.add_child(light)
	var j := Generic6DOFJoint3D.new()
	j.name = "Joint"
	j.position = Vector3.ZERO
	root.add_child(j)
	j.node_b = j.get_path_to(body)
	j.exclude_nodes_from_collision = true
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
	for ax in ["x", "y"]:
		j.set("angular_limit_%s/enabled" % ax, true)
		j.set("angular_limit_%s/upper_angle" % ax, 0.0)
		j.set("angular_limit_%s/lower_angle" % ax, 0.0)
	j.set("angular_limit_z/enabled", true)
	j.set("angular_limit_z/lower_angle", deg_to_rad(-80.0))
	j.set("angular_limit_z/upper_angle", deg_to_rad(80.0))
	_save(root, "workshop_lamp", "wslamp000001")


func _shavings() -> void:
	var root := Node3D.new()
	root.name = "WorkshopShavings"
	root.add_child(_glb("Shavings_Wide"))
	_save(root, "workshop_shavings", "wsshaving001")
