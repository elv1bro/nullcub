## Стена с трещиной (docs/plan-demo/PUZZLE.md, комната 6): Breakable, замороженный намертво (FREEZE_MODE_STATIC) — для кукол это стена,
## ни тягой, ни ударом её не сдвинуть. Ломает только взрыв: Explosion.detonate бьёт Breakable в радиусе на PROP_DAMAGE_MAX × спад —
## брошенная взрывная бочка рвётся о трещину (f ≈ 0.85 → ~50 урона), hp 40 держит взрыв дальше ~1 м. Половина hp — вид «Damaged»
## (трещин больше). Разрушена — куски камня (Destroyed/Piece_*) разлетаются (Breakable._spawn_debris), сама стена исчезает.
## Вид строится в _ready (до Breakable._ready): Mesh/Intact — камень с тёмной светящейся трещиной, Mesh/Damaged — трещин больше,
## Mesh/Destroyed — 3 × 2 куска. Узел ставится серединой низа на пол (origin — низ).
## Трещина «ловит» бочку: Area3D "Crack" чуть больше стены — взрывная бочка влетела в неё брошенной (зачёт ThrownCredit) или быстрее
## CATCH_SPEED — поджиг с CATCH_FUSE_S, взрыв у самой стены. Без этого брошенная бочка, долетев на ~2.9 м/с, давала удар
## 2.9 × 7 ≈ 20 = её hp — на грани: то рвалась, то ложилась у стены целой (проба комнаты 6).
class_name PuzzleCrackWall
extends Breakable

const STONE := "res://assets/textures/pbr/stone/albedo.png"

@export var size := Vector2(0.6, 3.0)

## Разрушена (до сброса комнаты: стену пересоздаёт PuzzleRoom.reset).
var broken := false
const CATCH_SPEED := 1.5
const CATCH_FUSE_S := 0.05


func _init() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	hp = 40.0
	mass = 24.0                 # куски по 4 кг: на плите в нише (порог 30) не дают ток
	min_impact_speed = 1000.0   # удары тел не ломают — только взрыв (take_damage)
	debris_freeze_s = 1000.0    # куски не замерзают: замёрзшие в проходе ниши стали бы новой стеной
	debris_free_s = 6.0


func _ready() -> void:
	add_to_group("puzzle_crack_walls")
	if get_node_or_null("Shape") == null:
		PuzzlePart.box_shape(self, "Shape", Vector3(size.x, size.y, 2.0), Vector3(0, size.y * 0.5, 0))
	if get_node_or_null("Mesh") == null:
		_build_visual()
	mesh_path = ^"Mesh"
	super._ready()
	destroyed.connect(func() -> void: broken = true)
	var crack := Area3D.new()
	crack.name = "Crack"
	crack.monitorable = false
	add_child(crack)
	PuzzlePart.box_shape(crack, "Shape", Vector3(size.x + 0.5, size.y, 2.0), Vector3(0, size.y * 0.5, 0))
	crack.body_entered.connect(_on_crack_body)


## Бочка в трещине: брошенная или быстрая — поджечь, рванёт у стены.
func _on_crack_body(b: Node3D) -> void:
	var barrel := b as ExplosiveBarrel
	if barrel == null or not is_instance_valid(barrel) or broken or barrel._exploded:
		return
	var tc := ThrownCredit.of(barrel)
	var by: Node = tc.attacker() if tc != null else null
	if by != null or barrel.linear_velocity.length() >= CATCH_SPEED:
		barrel.ignite(CATCH_FUSE_S, by)


func _stone() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.6, 0.58)
	if ResourceLoader.exists(STONE):
		m.albedo_texture = load(STONE)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.6
	m.roughness = 0.9
	return m


func _build_visual() -> void:
	var root := Node3D.new()
	root.name = "Mesh"
	add_child(root)
	var stone := _stone()
	var crack := PuzzlePart.glow_material(Color(1.0, 0.45, 0.12), 1.2)
	for state in ["Intact", "Damaged"]:
		var n := Node3D.new()
		n.name = state
		root.add_child(n)
		PuzzlePart.box_mesh(n, "Wall", Vector3(size.x, size.y, 1.9), Vector3(0, size.y * 0.5, 0), stone)
		var zig := [Vector2(0.0, 0.25), Vector2(0.12, 0.38), Vector2(-0.08, 0.5), Vector2(0.1, 0.62), Vector2(-0.04, 0.78)]
		if state == "Damaged":
			zig.append_array([Vector2(0.2, 0.3), Vector2(-0.18, 0.45), Vector2(0.16, 0.7)])
		for i in range(zig.size() - 1):
			var a: Vector2 = zig[i]
			var b: Vector2 = zig[i + 1]
			var pa := Vector2(a.x, a.y * size.y)
			var pb := Vector2(b.x, b.y * size.y)
			var seg := PuzzlePart.box_mesh(n, "Crack%d" % i, Vector3(pa.distance_to(pb) + 0.04, 0.05, 0.02),
				Vector3((pa.x + pb.x) * 0.5, (pa.y + pb.y) * 0.5, 0.96), crack)
			seg.rotation.z = atan2(pb.y - pa.y, pb.x - pa.x)
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var des := Node3D.new()
	des.name = "Destroyed"
	des.visible = false
	root.add_child(des)
	var k := 0
	for row in 3:
		for col in 2:
			var w := size.x * 0.5
			var h := size.y / 3.0
			var mi := MeshInstance3D.new()
			mi.name = "Piece_%d" % k
			var bm := BoxMesh.new()
			bm.size = Vector3(w * 0.95, h * 0.95, 1.6)
			bm.material = stone
			mi.mesh = bm
			mi.position = Vector3(-size.x * 0.25 + col * w, h * (row + 0.5), 0)
			des.add_child(mi)
			k += 1
