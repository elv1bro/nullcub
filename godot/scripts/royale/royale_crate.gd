## Ящик «Королевской битвы» (docs/plan-demo/ROYALE.md; автор 06.10: «оружие из ящиков разное + бонусы типа жизни и броню находить»).
## Наследник SupplyCrate стычки (группа squad_supply, покачивание в поле NULL, подбор касанием любой деталью ближе
## Tuning.SQUAD_SUPPLY_PICK_M): ящики стычки (патроны, жизни, броня, бонусы) — как есть, но живут весь бой (ставит RoyaleMatch на старте
## и редко — внутри зоны); ящик с оружием (weapon_id) — свой вид: модель ствола (SquadGun.build_model) крупно, медленно крутится над
## кольцом цвета ранга, над ним — название оружия. Касание решает RoyaleMatch.take_crate (без оружия — берёшь, ранг выше — меняешь,
## то же — как патроны). mag / reserve — патроны внутри (−1 — полный магазин и запас: ящик со старта).
class_name RoyaleCrate
extends SupplyCrate

## Модель ствола в ящике — длиной около WEAPON_LEN_M (короткий пистолет крупнее, длинный гаусс — мельче), масштаб в WEAPON_SCALE.
const WEAPON_LEN_M := 0.9
const WEAPON_SCALE := Vector2(1.4, 3.4)
const WEAPON_COLOUR := Color(1.0, 0.9, 0.55)
const LIFE_FOREVER := 1.0e9

var weapon_id := ""
var mag := -1
var reserve := -1


## Ящик стычки вида kind (ammo | health | armor | zoom | rage | haste) на весь бой.
static func make_kind(kind_: String, at: Vector3) -> RoyaleCrate:
	var c := RoyaleCrate.new()
	c.kind = kind_ if Tuning.SQUAD_SUPPLY.has(kind_) else "ammo"
	c.home = Vector3(at.x, at.y, 0.0)
	c.life = LIFE_FOREVER
	c.name = "Supply_%s" % c.kind
	return c


## Ящик с оружием id; патроны внутри — m / r (−1 — полные).
static func make_weapon(id: String, at: Vector3, m := -1, r := -1) -> RoyaleCrate:
	var c := RoyaleCrate.new()
	c.kind = "weapon"
	c.weapon_id = id if Tuning.SQUAD_WEAPONS.has(id) else Tuning.SQUAD_START_WEAPON
	c.mag = m
	c.reserve = r
	c.home = Vector3(at.x, at.y, 0.0)
	c.life = LIFE_FOREVER
	c.name = "Weapon_%s" % c.weapon_id
	return c


func is_weapon() -> bool:
	return weapon_id != ""


## Цвет ящика: оружие — по рангу (Tuning.ROYALE_WEAPONS.tier: от белого к золотому), остальное — цвет вида стычки.
func colour() -> Color:
	if is_weapon():
		var tier := int((Tuning.ROYALE_WEAPONS.get(weapon_id, {}) as Dictionary).get("tier", 1))
		return Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.72, 0.2), clampf(float(tier - 1) / 4.0, 0.0, 1.0))
	return Tuning.SQUAD_SUPPLY[kind]["colour"]


func _ready() -> void:
	if not is_weapon():
		super._ready()
		return
	add_to_group(SquadMatch.SUPPLY_GROUP)
	global_position = home
	var col := colour()
	_body = Node3D.new()
	add_child(_body)
	var m := SquadGun.build_model(weapon_id, col)
	var l := float((Tuning.SQUAD_WEAPONS[weapon_id] as Dictionary).get("len", 0.3))
	var k := clampf(WEAPON_LEN_M / maxf(l, 0.05), WEAPON_SCALE.x, WEAPON_SCALE.y)
	m.scale = Vector3.ONE * k
	m.position = Vector3(-l * 0.4 * k, 0.0, 0.0)   # рукоять у начала координат модели — по центру ящика середина ствола
	_body.add_child(m)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.5
	tm.outer_radius = 0.58
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.5
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(ring)
	_label = Label3D.new()
	_label.text = tr(String(Tuning.SQUAD_WEAPONS[weapon_id]["title"]))
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56
	_label.pixel_size = 0.006
	_label.outline_size = 14
	_label.modulate = col.lightened(0.2)
	_label.outline_modulate = Color(0.05, 0.04, 0.03)
	_label.position = Vector3(0.0, 0.7, 0.2)
	_label.no_depth_test = true
	add_child(_label)


## Как у SupplyCrate (покачивание, касание любой деталью живого бойца), но решает RoyaleMatch.take_crate — ящик знает своё оружие и
## патроны. Живёт весь бой.
func _physics_process(delta: float) -> void:
	_t += delta
	global_position = home + Vector3(0.0, sin(_t * TAU * BOB_HZ) * BOB_M, 0.0)
	if _body != null:
		_body.rotation_degrees.y += SPIN_DEG_S * (0.6 if is_weapon() else 1.0) * delta
	var m := get_tree().get_first_node_in_group(Match.GROUP)
	if m == null or not m.has_method("take_crate"):
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
				if bool(m.call("take_crate", d, self)):
					taken.emit(self, d)
					queue_free()
					return
				break
