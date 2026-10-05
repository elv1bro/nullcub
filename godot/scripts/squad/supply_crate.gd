## Ящик снабжения «Стычки 3 на 3» (docs/plan-demo/SQUAD.md, автор 05.10: «патроны, жизни и броню можно взять в ящиках, которые
## должны появляться»). Его ставит SquadMatch на точку карты (ProvingGround.supply_points). Ящик Руин (Crate.glb) висит в воздухе
## и покачивается (поле NULL), под ним — светящееся кольцо цвета вида, над ним — надпись. Физики нет: пули сквозь него, толкать нечем.
## Берёт живой боец, коснувшийся его любой деталью (ближе Tuning.SQUAD_SUPPLY_PICK_M к центру) — SquadMatch.take_supply решает,
## нужен ли он (полный запас — ящик не тратится). Живёт Tuning.SQUAD_SUPPLY_LIFE_S, последние 3 с мигает.
class_name SupplyCrate
extends Node3D

signal taken(crate: SupplyCrate, doll: Doll)

const MODEL := "res://assets/models/props/Crate.glb"
const BOB_M := 0.12
const BOB_HZ := 0.5
const SPIN_DEG_S := 40.0
const COLOURS := {"ammo": Color(1.0, 0.78, 0.25), "health": Color(0.35, 0.95, 0.45), "armor": Color(0.45, 0.78, 1.0)}
const LABELS := {"ammo": "ПАТРОНЫ", "health": "+ЖИЗНИ", "armor": "БРОНЯ"}

var kind := "ammo"
var life := 0.0
var home := Vector3.ZERO
var _t := 0.0
var _body: Node3D
var _label: Label3D


static func make(kind_: String, at: Vector3) -> SupplyCrate:
	var c := SupplyCrate.new()
	c.kind = kind_ if COLOURS.has(kind_) else "ammo"
	c.home = Vector3(at.x, at.y, 0.0)
	c.life = Tuning.SQUAD_SUPPLY_LIFE_S
	c.name = "Supply_%s" % c.kind
	return c


func _ready() -> void:
	add_to_group("squad_supply")
	global_position = home
	var col: Color = COLOURS[kind]
	_body = Node3D.new()
	add_child(_body)
	if ResourceLoader.exists(MODEL):
		var m := (load(MODEL) as PackedScene).instantiate() as Node3D
		m.scale = Vector3.ONE * 0.75
		m.position = Vector3(0.0, -0.26, 0.0)
		_body.add_child(m)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.5
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # лицом к камере
	add_child(ring)
	_label = Label3D.new()
	_label.text = tr(String(LABELS[kind]))
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56
	_label.pixel_size = 0.006
	_label.outline_size = 14
	_label.modulate = col.lightened(0.3)
	_label.outline_modulate = Color(0.05, 0.04, 0.03)
	_label.position = Vector3(0.0, 0.62, 0.2)
	_label.no_depth_test = true
	add_child(_label)


func _physics_process(delta: float) -> void:
	_t += delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	global_position = home + Vector3(0.0, sin(_t * TAU * BOB_HZ) * BOB_M, 0.0)
	if _body != null:
		_body.rotation_degrees.y += SPIN_DEG_S * delta
	visible = life > 3.0 or fmod(_t, 0.3) < 0.18
	var m := get_tree().get_first_node_in_group(Match.GROUP)
	if m == null or not m.has_method("take_supply"):
		return
	var r2 := Tuning.SQUAD_SUPPLY_PICK_M * Tuning.SQUAD_SUPPLY_PICK_M
	for n in get_tree().get_nodes_in_group("dolls"):
		var d := n as Doll
		if d == null or not d.alive or not d.is_inside_tree():
			continue
		if d.centre_of_mass().distance_squared_to(global_position) > 9.0:
			continue
		for p in d.parts.values():
			if is_instance_valid(p) and (p as Node3D).global_position.distance_squared_to(global_position) <= r2:
				if bool(m.call("take_supply", d, kind)):
					taken.emit(self, d)
					queue_free()
					return
				break
