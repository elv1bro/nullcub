## Builder сцен физических пропсов Свалки (биом 1 THE SCRAP, лист 02 «Physical Props», №021–040; docs/refs/biomes/01-scrap/
## sheet-02.png, LIST.md): собирает деревья узлов из моделей assets/models/scrap/props/*.glb (tools/blender/scrap_props.py)
## и сохраняет res://scenes/props/scrap/prop_<name>.tscn. Поведение — только в скриптах (разрушаемые — scenes/props/breakable.gd,
## он НЕ меняется: масса/HP/порог задаются свойствами узла в сцене).
## Запуск: godot --headless --path godot --import && godot --headless --path godot -s res://tools/build_scrap_props_scenes.gd
## Повторный запуск перезаписывает сцены (правки, которые нужно сохранить, вносятся сюда). Проверка —
## tests/scrap_props_probe.tscn (падение 180 кадров, удар по разрушаемым).
##
## Координаты Godot: Y вверх, +Z к камере, куклы и пропсы живут в плоскости XY (z = 0). Origin каждой сцены — центр основания
## (y = 0 — пол), как у моделей. Узлы: корень (RigidBody3D / StaticBody3D) → Shape* (CollisionShape3D) + Mesh (инстанс glb).
##   B  RigidBody3D + breakable.gd: kind, hp, min_impact_speed; contact_monitor, max_contacts_reported = MIN_CONTACTS;
##      Mesh = glb с Intact / Damaged / Destroyed/Piece_* (обломки спавнит скрипт).
##   R  RigidBody3D в плоскости XY: axis_lock_linear_z, axis_lock_angular_x/y, continuous_cd, демпфирование 0.2 / 0.5,
##      упрощённая коллизия (боксы, цилиндры, выпуклые оболочки). Тонкие листы (034, 035) — бокс не тоньше 0.08 м (иначе
##      туннелируют): визуальный лист 0.03–0.05 м стоит в середине бокса, лёжа «парит» на ~1–2.5 см.
##      Колёса тележек/корзины/вагонетки/тачки в этой волне — часть корпуса (цилиндры в коллизии, не вращаются); катание
##      (отдельные тела колёс на шарнирах, вагонетка на рельсах — M) — позже.
##   E  как B, скрипт explosive_barrel.gd (Breakable + фитиль и взрыв Explosion), Mesh без Destroyed — обломков нет.
##   S  StaticBody3D с упрощённой коллизией (перевёрнутая тележка, кучи обломков, стопки/штабели для декора).
## Решение по 023/027 (обломки ящика и бочки): варианты A/B — лёгкие R (6 и 5/4 кг): крупные (0.6–1 м), в плоскости боя,
## их весело пинать; «debris» — S: плоские кучи из многих кусков как одно тело выглядели бы склеенным комком, а низкий
## статичный бокс не мешает ходьбе и не даёт кукле провалиться в кучу.
##
## Сцены (масса, кг — MASS ниже; коллизия):
##   prop_wooden_crate           B 10, HP 20, бокс 1.0³                 prop_reinforced_crate   B 20, HP 50, порог 8 м/с, бокс 1.0³
##   prop_wooden_barrel          B 15, HP 30, цилиндр r0.33 × 1.0
##   prop_broken_crate_a/_b      R 6, бокс 1.0 × 0.62 × 1.0             prop_broken_crate_debris S, бокс 1.1 × 0.14 × 0.9
##   prop_large_shipping_crate   R 80, бокс 2.4 × 1.4 × 1.4
##   prop_metal_barrel/_dented   E 12, HP 20, цилиндр r0.3 × 0.91 — взрывные (scenes/props/explosive_barrel.gd, 29.09: было R 40)
##   prop_broken_barrel_a        R 5, лежачий цилиндр r0.38 × 1.0 вдоль Z (катится в плоскости XY)
##   prop_broken_barrel_b        R 4, цилиндр r0.36 × 0.62              prop_broken_barrel_debris S, бокс 1.2 × 0.07 × 0.7
##   prop_scrap_basket/_full     R 15 / 35, бокс 1.0 × 0.8 × 0.7 (+ бокс кучи у full)
##   prop_junk_cart/_loaded      R 30 / 55, бокс кузова + 2 цилиндра колёс вдоль Z (+ бокс хлама у loaded)
##   prop_overturned_junk_cart   S, бокс кузова (крен 8°) + 2 цилиндра колёс
##   prop_rail_scrap_wagon/_full R 90 / 140, выпуклая оболочка кузова-трапеции + бокс рамы с колёсами (+ бокс хлама)
##   prop_broken_wheelbarrow     R 12, бокс корыта + цилиндр колеса + бокс ног + наклонный бокс ручек
##   prop_wooden_pallet          R 12, бокс 1.2 × 0.148 × 1.0
##   prop_metal_plate/_b         R 20 / 18, бокс 1.5 × 0.08 × 1.0       prop_metal_plate_stack  S, бокс 1.6 × 0.24 × 1.1
##   prop_corrugated_sheet/_b    R 12, бокс 2.0 × 0.08 × 1.0            prop_corrugated_sheet_stack S, бокс 2.05 × 0.22 × 1.05
##   prop_wooden_beam            R 35, бокс 3.0 × 0.336 × 0.32          prop_wooden_beam_stack  S, два бокса (ярусы)
##   prop_broken_beam            R 25, бокс 2.5 × 0.42 × 0.44
##   prop_pipe_bundle            R 40, выпуклая оболочка трёх труб
##   prop_rope_coil              R 8, цилиндр r0.45 × 0.3               prop_cable_coil         R 30, цилиндр r0.52 × 0.386
extends SceneTree

const DIR := "res://scenes/props/scrap/"
const GLB := "res://assets/models/scrap/props/%s.glb"
const BREAKABLE := preload("res://scenes/props/breakable.gd")
const EXPLOSIVE := preload("res://scenes/props/explosive_barrel.gd")

## Массы, кг. Держим здесь, а не в scripts/tuning.gd: его сейчас правит другая сессия — при сведении перенести в Tuning
## (раздел пропсов) и читать оттуда. Ориентиры задачи: ящик 10, бочка 15 (как props/crate, barrel), железная бочка ~40,
## большой ящик ~80, брус 3 м ~35. Гружёные варианты тяжелее пустых на вес хлама.
const MASS := {
	"wooden_crate": 10.0, "reinforced_crate": 20.0, "wooden_barrel": 15.0,
	"broken_crate_a": 6.0, "broken_crate_b": 6.0,
	"large_shipping_crate": 80.0,
	"metal_barrel": 12.0, "metal_barrel_dented": 12.0,   # взрывные: лёгкий класс (PropHeft) — схватить и бросить
	"broken_barrel_a": 5.0, "broken_barrel_b": 4.0,
	"scrap_basket": 15.0, "scrap_basket_full": 35.0,
	"junk_cart": 30.0, "junk_cart_loaded": 55.0,
	"rail_scrap_wagon": 90.0, "rail_scrap_wagon_full": 140.0,
	"broken_wheelbarrow": 12.0,
	"wooden_pallet": 12.0,
	"metal_plate": 20.0, "metal_plate_b": 18.0,
	"corrugated_sheet": 12.0, "corrugated_sheet_b": 12.0,
	"wooden_beam": 35.0,
	"broken_beam": 25.0,
	"pipe_bundle": 40.0,
	"rope_coil": 8.0,
	"cable_coil": 30.0,
}
## Разрушаемые: HP и порог скорости удара (breakable.gd: урон = v × damage_per_speed × mass_factor при v ≥ порога).
## Деревянный ящик/бочка — как props/crate, barrel (20 / 30, 6 м/с); усиленный ящик в 2.5 раза прочнее и не колется
## о лёгкие удары (порог 8 м/с).
const HP := {"wooden_crate": 20.0, "reinforced_crate": 50.0, "wooden_barrel": 30.0, "metal_barrel": 20.0, "metal_barrel_dented": 20.0}
const MIN_IMPACT := {"wooden_crate": 6.0, "reinforced_crate": 8.0, "wooden_barrel": 6.0, "metal_barrel": 6.0, "metal_barrel_dented": 6.0}

var _wood: PhysicsMaterial
var _metal: PhysicsMaterial
var _sheet: PhysicsMaterial
var _rope: PhysicsMaterial
var _saved := 0


func _init() -> void:
	_wood = _pm(0.8, 0.1)
	_metal = _pm(0.55, 0.15)
	_sheet = _pm(0.45, 0.1)
	_rope = _pm(0.95, 0.02)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	# --- B: разрушаемые
	_breakable("wooden_crate", "Wooden_Crate", "crate", [_s(_box(Vector3(1.0, 1.0, 1.0)), Vector3(0, 0.5, 0))])
	_breakable("reinforced_crate", "Reinforced_Crate", "crate", [_s(_box(Vector3(1.0, 1.0, 1.0)), Vector3(0, 0.5, 0))])
	_breakable("wooden_barrel", "Wooden_Barrel", "barrel", [_s(_cyl(0.33, 1.0), Vector3(0, 0.5, 0))])
	# --- 023 / 027: варианты — лёгкие R, кучи — S
	_rigid_prop("broken_crate_a", "Broken_Crate_A", _wood, [_s(_box(Vector3(1.0, 0.62, 1.0)), Vector3(0, 0.31, 0))])
	_rigid_prop("broken_crate_b", "Broken_Crate_B", _wood, [_s(_box(Vector3(1.0, 0.62, 1.0)), Vector3(0, 0.31, 0))])
	_static_prop("broken_crate_debris", "Broken_Crate_Debris", _wood, [_s(_box(Vector3(1.1, 0.14, 0.9)), Vector3(0, 0.07, 0))])
	_rigid_prop("broken_barrel_a", "Broken_Barrel_A", _wood, [_s(_cyl(0.38, 1.0), Vector3(0, 0.384, 0), Vector3(90, 0, 0))])
	_rigid_prop("broken_barrel_b", "Broken_Barrel_B", _wood, [_s(_cyl(0.36, 0.62), Vector3(0, 0.31, 0))])
	_static_prop("broken_barrel_debris", "Broken_Barrel_Debris", _wood, [_s(_box(Vector3(1.2, 0.07, 0.7)), Vector3(0, 0.035, 0))])
	# --- R: ящик, бочки
	_rigid_prop("large_shipping_crate", "Large_Shipping_Crate", _wood, [_s(_box(Vector3(2.4, 1.4, 1.4)), Vector3(0, 0.7, 0))])
	_breakable("metal_barrel", "Metal_Barrel", "barrel", [_s(_cyl(0.3, 0.91), Vector3(0, 0.455, 0))], EXPLOSIVE, _metal)
	_breakable("metal_barrel_dented", "Metal_Barrel_Dented", "barrel", [_s(_cyl(0.3, 0.91), Vector3(0, 0.455, 0))], EXPLOSIVE, _metal)
	# --- 028 корзина (колёсики — часть корпуса)
	var basket := [_s(_box(Vector3(1.0, 0.8, 0.7)), Vector3(0, 0.4, 0))]
	_rigid_prop("scrap_basket", "Scrap_Basket", _metal, basket)
	_rigid_prop("scrap_basket_full", "Scrap_Basket_Full", _metal, basket + [_s(_box(Vector3(0.8, 0.3, 0.5)), Vector3(0, 0.93, 0))])
	# --- 029 тележка: кузов z 0.33..0.92, колёса r 0.312 на осях x = ±0.5 (цилиндры вдоль Z на обе стороны)
	var cart := [_s(_box(Vector3(1.65, 0.59, 1.02)), Vector3(0, 0.625, 0)),
		_s(_cyl(0.312, 1.26), Vector3(-0.5, 0.312, 0), Vector3(90, 0, 0)),
		_s(_cyl(0.312, 1.26), Vector3(0.5, 0.312, 0), Vector3(90, 0, 0))]
	_rigid_prop("junk_cart", "Junk_Cart", _wood, cart)
	_rigid_prop("junk_cart_loaded", "Junk_Cart_Loaded", _wood, cart + [_s(_box(Vector3(1.3, 0.16, 0.7)), Vector3(0, 1.0, 0))])
	# --- 030 перевёрнутая тележка (S): те же детали после переворота (Ry 180° в Blender), крена 8° (правый конец выше)
	# и подъёма +0.095 (нижняя кромка на −0.02) — см. scrap_props.overturned_cart
	_static_prop("overturned_junk_cart", "Overturned_Junk_Cart", _wood, [
		_s(_box(Vector3(1.64, 0.59, 1.02)), Vector3(-0.041, 0.387, 0), Vector3(0, 0, 8)),
		_s(_cyl(0.312, 1.26), Vector3(0.41, 0.766, 0), Vector3(90, 0, 0)),
		_s(_cyl(0.312, 1.26), Vector3(-0.58, 0.627, 0), Vector3(90, 0, 0))])
	# --- 031 вагонетка: кузов-трапеция (низ 1.84 × 0.94 на 0.42, верх 2.28 × 1.18 на 1.155) + рама с колёсами 0..0.42
	var tub := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			tub.append(Vector3(sx * 0.92, 0.42, sz * 0.47))
			tub.append(Vector3(sx * 1.14, 1.155, sz * 0.59))
	var wagon := [_s(_hull(tub), Vector3.ZERO), _s(_box(Vector3(1.9, 0.42, 0.95)), Vector3(0, 0.21, 0))]
	_rigid_prop("rail_scrap_wagon", "Rail_Scrap_Wagon", _metal, wagon)
	_rigid_prop("rail_scrap_wagon_full", "Rail_Scrap_Wagon_Full", _metal, wagon + [_s(_box(Vector3(1.9, 0.26, 0.95)), Vector3(0, 1.28, 0))])
	# --- 032 тачка: корыто, колесо спереди (−X), ноги, ручки
	_rigid_prop("broken_wheelbarrow", "Broken_Wheelbarrow", _metal, [
		_s(_box(Vector3(0.86, 0.34, 0.64)), Vector3(-0.05, 0.47, 0)),
		_s(_cyl(0.2, 0.07), Vector3(-0.55, 0.204, 0), Vector3(90, 0, 0)),
		_s(_box(Vector3(0.12, 0.3, 0.58)), Vector3(0.26, 0.15, 0)),
		_s(_box(Vector3(0.36, 0.06, 0.62)), Vector3(0.58, 0.44, 0), Vector3(0, 0, 27.4))])
	# --- 033 поддон, 034/035 листы (бокс ≥ 0.08 м), стопки — S
	_rigid_prop("wooden_pallet", "Wooden_Pallet", _wood, [_s(_box(Vector3(1.2, 0.148, 1.0)), Vector3(0, 0.074, 0))])
	_rigid_prop("metal_plate", "Metal_Plate", _sheet, [_s(_box(Vector3(1.5, 0.08, 1.0)), Vector3(0, 0.025, 0))])
	_rigid_prop("metal_plate_b", "Metal_Plate_B", _sheet, [_s(_box(Vector3(1.5, 0.08, 1.0)), Vector3(0, 0.025, 0))])
	_static_prop("metal_plate_stack", "Metal_Plate_Stack", _sheet, [_s(_box(Vector3(1.6, 0.24, 1.1)), Vector3(0, 0.12, 0))])
	_rigid_prop("corrugated_sheet", "Corrugated_Sheet", _sheet, [_s(_box(Vector3(2.0, 0.08, 1.0)), Vector3(0, 0.028, 0))])
	_rigid_prop("corrugated_sheet_b", "Corrugated_Sheet_B", _sheet, [_s(_box(Vector3(2.0, 0.08, 1.0)), Vector3(0, 0.028, 0))])
	_static_prop("corrugated_sheet_stack", "Corrugated_Sheet_Stack", _sheet, [_s(_box(Vector3(2.05, 0.22, 1.05)), Vector3(0, 0.11, 0))])
	# --- 036/037 брусья
	_rigid_prop("wooden_beam", "Wooden_Beam", _wood, [_s(_box(Vector3(3.0, 0.336, 0.32)), Vector3(0, 0.168, 0))])
	_static_prop("wooden_beam_stack", "Wooden_Beam_Stack", _wood, [
		_s(_box(Vector3(3.0, 0.312, 1.0)), Vector3(0, 0.156, 0)),
		_s(_box(Vector3(2.85, 0.31, 0.66)), Vector3(0, 0.47, -0.015))])
	_rigid_prop("broken_beam", "Broken_Beam", _wood, [_s(_box(Vector3(2.5, 0.42, 0.44)), Vector3(0, 0.21, 0))])
	# --- 038 трубы: выпуклая оболочка трёх кругов r 0.168 (с бандажами) вдоль X; центры y 0.168 / 0.431, z ∓0.152 / 0
	var pipes := PackedVector3Array()
	for c in [Vector2(0.168, -0.152), Vector2(0.168, 0.152), Vector2(0.431, 0.0)]:
		for k in 16:
			var a := TAU * k / 16.0
			for x in [-1.0, 1.0]:
				pipes.append(Vector3(x, c.x + 0.168 * sin(a), c.y + 0.168 * cos(a)))
	_rigid_prop("pipe_bundle", "Pipe_Bundle", _metal, [_s(_hull(pipes), Vector3.ZERO)])
	# --- 039/040 бухты
	_rigid_prop("rope_coil", "Rope_Coil", _rope, [_s(_cyl(0.45, 0.3), Vector3(0, 0.15, 0))])
	_rigid_prop("cable_coil", "Cable_Coil", _metal, [_s(_cyl(0.52, 0.386), Vector3(0, 0.193, 0))])
	print("scrap props: %d scenes saved to %s" % [_saved, DIR])
	quit(0)


# ---------------------------------------------------------------- helpers
func _pm(friction: float, bounce: float) -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = friction
	m.bounce = bounce
	return m


## Описание формы коллизии: форма, позиция, поворот (градусы, Эйлер XYZ).
func _s(shape: Shape3D, pos: Vector3, rot_deg := Vector3.ZERO) -> Dictionary:
	return {"shape": shape, "pos": pos, "rot": rot_deg}


func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	return c


func _hull(points: PackedVector3Array) -> ConvexPolygonShape3D:
	var h := ConvexPolygonShape3D.new()
	h.points = points
	return h


func _glb(name: String) -> Node3D:
	var ps: PackedScene = load(GLB % name)
	if ps == null:
		push_error("missing " + (GLB % name) + " — run Blender tools/blender/scrap_props.py and godot --import")
		quit(1)
		return Node3D.new()
	var n: Node3D = ps.instantiate()
	n.name = "Mesh"
	return n


func _shapes(body: Node, specs: Array) -> void:
	for i in specs.size():
		var sp: Dictionary = specs[i]
		var cs := CollisionShape3D.new()
		cs.name = "Shape" if specs.size() == 1 else "Shape_%d" % i
		cs.shape = sp["shape"]
		cs.position = sp["pos"]
		cs.rotation_degrees = sp["rot"]
		body.add_child(cs)


func _rigid(key: String, glb: String, phys: PhysicsMaterial) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.name = glb
	b.mass = MASS[key]
	b.axis_lock_linear_z = true
	b.axis_lock_angular_x = true
	b.axis_lock_angular_y = true
	b.continuous_cd = true
	b.linear_damp = 0.2
	b.angular_damp = 0.5
	b.physics_material_override = phys
	return b


func _breakable(key: String, glb: String, kind: String, specs: Array, script: Script = BREAKABLE, phys: PhysicsMaterial = null) -> void:
	var b := _rigid(key, glb, phys if phys != null else _wood)
	b.set_script(script)
	b.set("kind", kind)
	b.set("hp", HP[key])
	b.set("min_impact_speed", MIN_IMPACT[key])
	b.contact_monitor = true
	b.max_contacts_reported = BREAKABLE.MIN_CONTACTS
	_shapes(b, specs)
	b.add_child(_glb(glb))
	_save(b, key)


func _rigid_prop(key: String, glb: String, phys: PhysicsMaterial, specs: Array) -> void:
	var b := _rigid(key, glb, phys)
	_shapes(b, specs)
	b.add_child(_glb(glb))
	_save(b, key)


func _static_prop(key: String, glb: String, phys: PhysicsMaterial, specs: Array) -> void:
	var b := StaticBody3D.new()
	b.name = glb
	b.physics_material_override = phys
	_shapes(b, specs)
	b.add_child(_glb(glb))
	_save(b, key)


func _set_owner(n: Node, root: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		_set_owner(c, root)


## Стабильный uid сцены (12 символов a–z/0–9, как у остальных builder-ов; длиннее ResourceSaver.set_uid не принимает):
## "sc" + порядковый номер сохранения (порядок вызовов в _init фиксирован) + первые буквы ключа.
func _uid_text(key: String) -> String:
	var out := ""
	for ch in key.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return "uid://sc%02d%s" % [_saved + 1, (out + "xxxxxxxx").substr(0, 8)]


func _save(root: Node, key: String) -> void:
	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed %s: %d" % [key, err])
		quit(1)
		return
	var path := DIR + "prop_" + key + ".tscn"
	err = ResourceSaver.save(ps, path)
	if err != OK:
		push_error("save failed %s: %d" % [path, err])
		quit(1)
		return
	var id := ResourceUID.text_to_id(_uid_text(key))
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)
	ResourceSaver.set_uid(path, id)
	_saved += 1
	print("saved ", path)
	root.free()
