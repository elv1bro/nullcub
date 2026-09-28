## Builder сцен модульного кита Свалки (биом 1, лист docs/refs/biomes/01-scrap/kit-01.png, K01–K08, K12–K22): собирает
## деревья узлов из моделей assets/models/scrap/kit/*.glb (tools/blender/scrap_kit.py) и сохраняет
## res://scenes/props/scrap/kit_<name>.tscn. Скриптов поведения у модулей нет (статика).
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_scrap_kit_scenes.gd
## Повторный запуск перезаписывает сцены (правки, которые нужно сохранить, вносятся сюда).
##
## Оси Godot: x — вбок, y — вверх, z — к камере; куклы живут в плоскости z = 0, поэтому у всего, по чему ходят,
## коллизия пересекает z = 0: настилы и опоры — на всю глубину кита DECK_D = 2.0 (z ∈ [−1, 1]), рамы / стойки / перила /
## лестница / балка на цепях — THIN_D = 0.6 вокруг z = 0 модуля. Цепи, флаги, крюки — без коллизии.
## Origin и размеры — как в шапке scrap_kit.py (snap: опора на узле сетки x = 2k, платформа с торцом на той же линии
## ставится origin-ом на y = H + 1.0; Lower — H + 0.5, Upper — H + 2.0). Узлы Marker3D Snap_* — точки стыковки.
##
##   kit_platform_s / _m / _l   StaticBody3D: Deck — бокс L × 0.4 × 2.0 под поверхностью (y ∈ [−0.4, 0]); Snap_L/Snap_R
##                              на (±L/2, 0, 0); Mesh = Platform_S/M/L.glb (L = 2 / 4 / 6)
##   kit_platform_end_l / _r    то же, L = 2 (свободный торец слева / справа)
##   kit_platform_gap           DeckL / DeckR — два бокса 1.4 × 0.4 × 2.0 на x = ±1.3 (разрыв 1.2 м без коллизии)
##   kit_platform_lower         Deck — бокс 2 × 0.5 × 2.0 до земли (y ∈ [−0.5, 0]), под низкой платформой не застрять
##   kit_platform_upper         Deck 2 × 0.4 × 2.0 + LegL/LegR — боксы 0.3 × 1.6 × 2.0 по ногам (внутрь рамы не зайти)
##   kit_slope_15 / _30         Ramp — бокс вдоль ската (длина √(16 + rise²), толщина 0.3, глубина 2.0), повёрнут на
##                              atan(rise / 4) вокруг z, верхняя грань — поверхность от (−2, 0) до (2, rise); Snap_L/Snap_R
##   kit_support_s / _m / _l    Column — бокс W × H × 2.0 (W = 1.0 / 1.0 / 1.6, H = 3 / 4 / 6), верх = крышка; Snap_Top (0, H, 0)
##   kit_support_diagonal       Post — бокс 0.44 × 3.0 × 0.6; Brace — повёрнутый бокс по подкосу (от башмака x = −1.9);
##                              Snap_Top (0, 3, 0). Для подкоса справа — scale.x = −1 у экземпляра
##   kit_wall_frame             PostL/PostR 0.5 × 3.0 × 0.6 (x = ±1.75) + Beam 4.0 × 0.36 × 0.6 (верх y = 3.0)
##   kit_banner_frame           PostL/PostR 0.4 × 4.0 × 0.6 (x = ±0.8) + Beam 2.0 × 0.36 × 0.6 (верх y = 4.0)
##   kit_railing                Sill 2.0 × 0.16 × 0.6 + PostL/PostR 0.22 × 1.14 × 0.6 + Rail 1.7 × 0.08 × 0.6 (y ≈ 1.0)
##   kit_chain_hook             Node3D (декор, без коллизии): Anchor Marker3D в origin (точка подвеса) + Mesh
##   kit_hanging_beam           StaticBody3D: Beam 4.0 × 0.34 × 0.6 (верх y = 0), Anchor_L/Anchor_R Marker3D (±1.7, 2.0, 0).
##                              В этой волне статика; маятник на двух цепях (RigidBody3D + 2 × Generic6DOFJoint3D) — волна 2
##   kit_ladder                 RailL/RailR 0.11 × 3.0 × 0.6 (x = ±0.3) + Rung_0…8 0.52 × 0.065 × 0.6 (y = 0.3 … 2.7)
extends SceneTree

const DIR := "res://scenes/props/scrap/"
const GLB := "res://assets/models/scrap/kit/%s.glb"
const DECK_D := 2.0
const THIN_D := 0.6
const DECK_T := 0.4

var _deck: PhysicsMaterial
var _iron: PhysicsMaterial
var _failed := false


func _init() -> void:
	_deck = PhysicsMaterial.new()
	_deck.friction = 0.9
	_deck.bounce = 0.05
	_iron = PhysicsMaterial.new()
	_iron.friction = 0.7
	_iron.bounce = 0.1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_platform("Platform_S", 2.0, "scrapkitps01")
	_platform("Platform_M", 4.0, "scrapkitpm01")
	_platform("Platform_L", 6.0, "scrapkitpl01")
	_platform("Platform_End_L", 2.0, "scrapkitpel1")
	_platform("Platform_End_R", 2.0, "scrapkitper1")
	_gap()
	_lower()
	_upper()
	_slope("Slope_15", 1.0, "scrapkits151")
	_slope("Slope_30", 2.0, "scrapkits301")
	_support("Support_S", 3.0, 1.0, "scrapkitss01")
	_support("Support_M", 4.0, 1.0, "scrapkitsm01")
	_support("Support_L", 6.0, 1.6, "scrapkitsl01")
	_diagonal()
	_frame("Wall_Frame", 4.0, 3.0, 0.5, 1.75, "scrapkitwf01")
	_frame("Banner_Frame", 2.0, 4.0, 0.4, 0.8, "scrapkitbf01")
	_railing()
	_chain_hook()
	_hanging_beam()
	_ladder()
	print("scrap kit scenes saved to ", DIR)
	quit(1 if _failed else 0)


# ---------------------------------------------------------------- helpers
func _glb(name: String) -> Node3D:
	var ps: PackedScene = load(GLB % name)
	if ps == null:
		push_error("missing " + (GLB % name) + " — run Blender tools/blender/scrap_kit.py and godot --import")
		_failed = true
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.name = "Mesh"
	return n


func _file(module: String) -> String:
	return "kit_" + module.to_lower()


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
		_failed = true
		root.free()
		return
	var path := DIR + file + ".tscn"
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
		_failed = true
		root.free()
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


func _box(parent: Node, name: String, size: Vector3, pos: Vector3, rot_z_deg := 0.0) -> CollisionShape3D:
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.name = name
	cs.shape = b
	cs.position = pos
	cs.rotation_degrees = Vector3(0, 0, rot_z_deg)
	parent.add_child(cs)
	return cs


func _marker(parent: Node, name: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = name
	m.position = pos
	parent.add_child(m)


func _static(name: String, mat: PhysicsMaterial) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.physics_material_override = mat
	return b


func _node_name(module: String) -> String:
	return "Kit" + module.replace("_", "")


## Бокс по отрезку a → b в плоскости XY: толщина t (поперёк отрезка), глубина d по z.
func _bar(parent: Node, name: String, a: Vector2, b: Vector2, t: float, d: float) -> void:
	var v := b - a
	var mid := (a + b) * 0.5
	_box(parent, name, Vector3(v.length(), t, d), Vector3(mid.x, mid.y, 0), rad_to_deg(atan2(v.y, v.x)))


# ---------------------------------------------------------------- scenes
func _platform(module: String, length: float, uid: String) -> void:
	var root := _static(_node_name(module), _deck)
	_box(root, "Deck", Vector3(length, DECK_T, DECK_D), Vector3(0, -DECK_T * 0.5, 0))
	_marker(root, "Snap_L", Vector3(-length * 0.5, 0, 0))
	_marker(root, "Snap_R", Vector3(length * 0.5, 0, 0))
	root.add_child(_glb(module))
	_save(root, _file(module), uid)


func _gap() -> void:
	var root := _static(_node_name("Platform_Gap"), _deck)
	_box(root, "DeckL", Vector3(1.4, DECK_T, DECK_D), Vector3(-1.3, -DECK_T * 0.5, 0))
	_box(root, "DeckR", Vector3(1.4, DECK_T, DECK_D), Vector3(1.3, -DECK_T * 0.5, 0))
	_marker(root, "Snap_L", Vector3(-2.0, 0, 0))
	_marker(root, "Snap_R", Vector3(2.0, 0, 0))
	root.add_child(_glb("Platform_Gap"))
	_save(root, _file("Platform_Gap"), "scrapkitpg01")


func _lower() -> void:
	var root := _static(_node_name("Platform_Lower"), _deck)
	_box(root, "Deck", Vector3(2.0, 0.5, DECK_D), Vector3(0, -0.25, 0))
	_marker(root, "Snap_L", Vector3(-1.0, 0, 0))
	_marker(root, "Snap_R", Vector3(1.0, 0, 0))
	root.add_child(_glb("Platform_Lower"))
	_save(root, _file("Platform_Lower"), "scrapkitplw1")


func _upper() -> void:
	var root := _static(_node_name("Platform_Upper"), _deck)
	_box(root, "Deck", Vector3(2.0, DECK_T, DECK_D), Vector3(0, -DECK_T * 0.5, 0))
	_box(root, "LegL", Vector3(0.3, 1.6, DECK_D), Vector3(-0.78, -1.2, 0))
	_box(root, "LegR", Vector3(0.3, 1.6, DECK_D), Vector3(0.78, -1.2, 0))
	_marker(root, "Snap_L", Vector3(-1.0, 0, 0))
	_marker(root, "Snap_R", Vector3(1.0, 0, 0))
	root.add_child(_glb("Platform_Upper"))
	_save(root, _file("Platform_Upper"), "scrapkitpup1")


func _slope(module: String, rise: float, uid: String) -> void:
	var run := 4.0
	var th := atan2(rise, run)
	var t := 0.3
	var root := _static(_node_name(module), _deck)
	# верхняя грань бокса лежит на поверхности ската: центр смещён от середины поверхности по нормали вниз на t/2
	var n := Vector2(-sin(th), cos(th))
	var c := Vector2(0.0, rise * 0.5) - n * (t * 0.5)
	_box(root, "Ramp", Vector3(sqrt(run * run + rise * rise), t, DECK_D), Vector3(c.x, c.y, 0), rad_to_deg(th))
	_marker(root, "Snap_L", Vector3(-run * 0.5, 0, 0))
	_marker(root, "Snap_R", Vector3(run * 0.5, rise, 0))
	root.add_child(_glb(module))
	_save(root, _file(module), uid)


func _support(module: String, h: float, w: float, uid: String) -> void:
	var root := _static(_node_name(module), _iron)
	_box(root, "Column", Vector3(w, h, DECK_D), Vector3(0, h * 0.5, 0))
	_marker(root, "Snap_Top", Vector3(0, h, 0))
	root.add_child(_glb(module))
	_save(root, _file(module), uid)


func _diagonal() -> void:
	var root := _static(_node_name("Support_Diagonal"), _iron)
	_box(root, "Post", Vector3(0.44, 3.0, THIN_D), Vector3(0, 1.5, 0))
	# подкос: башмак (−1.9, 0.16) → стойка (−0.2, 2.28), сечение 0.2 (как швеллер в scrap_kit.support_diagonal)
	_bar(root, "Brace", Vector2(-1.9, 0.16), Vector2(-0.2, 2.28), 0.2, THIN_D)
	_marker(root, "Snap_Top", Vector3(0, 3.0, 0))
	root.add_child(_glb("Support_Diagonal"))
	_save(root, _file("Support_Diagonal"), "scrapkitsd01")


func _frame(module: String, w: float, h: float, post_w: float, post_x: float, uid: String) -> void:
	var root := _static(_node_name(module), _iron)
	_box(root, "PostL", Vector3(post_w, h, THIN_D), Vector3(-post_x, h * 0.5, 0))
	_box(root, "PostR", Vector3(post_w, h, THIN_D), Vector3(post_x, h * 0.5, 0))
	_box(root, "Beam", Vector3(w, 0.36, THIN_D), Vector3(0, h - 0.18, 0))
	root.add_child(_glb(module))
	_save(root, _file(module), uid)


func _railing() -> void:
	var root := _static(_node_name("Railing"), _iron)
	_box(root, "Sill", Vector3(2.0, 0.16, THIN_D), Vector3(0, 0.08, 0))
	_box(root, "PostL", Vector3(0.22, 1.14, THIN_D), Vector3(-0.85, 0.57, 0))
	_box(root, "PostR", Vector3(0.22, 1.14, THIN_D), Vector3(0.85, 0.57, 0))
	_box(root, "Rail", Vector3(1.7, 0.08, THIN_D), Vector3(0, 1.01, 0))
	root.add_child(_glb("Railing"))
	_save(root, _file("Railing"), "scrapkitrl01")


func _chain_hook() -> void:
	var root := Node3D.new()
	root.name = _node_name("Chain_Hook")
	_marker(root, "Anchor", Vector3.ZERO)
	root.add_child(_glb("Chain_Hook"))
	_save(root, _file("Chain_Hook"), "scrapkitch01")


func _hanging_beam() -> void:
	var root := _static(_node_name("Hanging_Beam"), _iron)
	_box(root, "Beam", Vector3(4.0, 0.34, THIN_D), Vector3(0, -0.17, 0))
	_marker(root, "Anchor_L", Vector3(-1.7, 2.0, 0))
	_marker(root, "Anchor_R", Vector3(1.7, 2.0, 0))
	root.add_child(_glb("Hanging_Beam"))
	_save(root, _file("Hanging_Beam"), "scrapkithb01")


func _ladder() -> void:
	var root := _static(_node_name("Ladder"), _deck)
	_box(root, "RailL", Vector3(0.11, 3.0, THIN_D), Vector3(-0.3, 1.5, 0))
	_box(root, "RailR", Vector3(0.11, 3.0, THIN_D), Vector3(0.3, 1.5, 0))
	for i in 9:
		_box(root, "Rung_%d" % i, Vector3(0.52, 0.065, THIN_D), Vector3(0, 0.3 + 0.3 * i, 0))
	root.add_child(_glb("Ladder"))
	_save(root, _file("Ladder"), "scrapkitld01")
