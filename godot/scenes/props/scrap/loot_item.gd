## Лут Свалки — материал крафта (гвозди, пластина, звено цепи, рукоять), выпадает из разбитых ящиков и бочек (scrap.gd:
## Breakable.destroyed → ScrapArena.spawn_loot). Сцены scenes/props/scrap/loot_<id>.tscn (tools/build_scrap_machines_scenes.gd):
## RigidBody3D в плоскости XY (как пропсы: z и вращение x/y заперты — лицо модели всегда к камере) → Shape + Model.
##
## Подбор: через ARM_S после появления (видно, что выпало) — касание любой частью живой куклы (body_entered, а если касание
## началось раньше ARM_S — текущие контакты get_colliding_bodies) или захват клавишей E
## (ArmAssist.grab вешает на предмет ThrownCredit с held = true — его и ловим, arm_assist.gd не трогаем). Итог — RunInventory.shared()
## .add(material_id, amount, кукла), всплывашка «+1 гвозди» (Label3D поднимается и гаснет за POPUP_S), предмет исчезает.
## Подпись над предметом — Label3D, но не ребёнок тела (подсветка ArmAssist красит всех GeometryInstance3D-детей): свой узел у
## родителя, едет за предметом в _process.
## Железные материалы (RunInventory.is_iron) — meta material = "iron": тянет магнит.
class_name LootItem
extends RigidBody3D

signal picked(by: Node, material_id: String)

const ARM_S := 0.5
const POPUP_S := 1.1
const POPUP_RISE_M := 1.1
const LABEL_Y := 0.42
const SCENE := "res://scenes/props/scrap/loot_%s.tscn"

@export var material_id := "nails"
@export var amount := 1
@export var show_label := true

var taken := false
var age := 0.0
var _label: Label3D


## Инстанс лута id в parent в точке pos со скоростью vel (null — нет сцены).
static func spawn(id: String, parent: Node, pos: Vector3, vel := Vector3.ZERO) -> LootItem:
	var ps := load(SCENE % id) as PackedScene if ResourceLoader.exists(SCENE % id) else null
	if ps == null or parent == null:
		return null
	var it := ps.instantiate() as LootItem
	if it == null:
		return null
	parent.add_child(it)
	it.global_position = Vector3(pos.x, pos.y, 0.0)
	it.linear_velocity = vel
	it.angular_velocity = Vector3(0.0, 0.0, randf_range(-3.0, 3.0))
	return it


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = maxi(max_contacts_reported, 4)
	body_entered.connect(_on_body_entered)
	set_meta(ScrapMachine.META_MATERIAL, "iron" if RunInventory.is_iron(material_id) else "wood")
	add_to_group("loot")
	if show_label:
		_label = _make_label(RunInventory.title(material_id), 34, Color(1.0, 0.93, 0.78, 0.92))
		_label.no_depth_test = false   # подпись прячется за тем, что ближе к камере (прилипший к магниту лут)
		get_parent().add_child.call_deferred(_label)


func _exit_tree() -> void:
	if _label != null and is_instance_valid(_label):
		_label.queue_free()


func _process(_delta: float) -> void:
	if _label != null and is_instance_valid(_label) and _label.is_inside_tree():
		_label.global_position = global_position + Vector3(0.0, LABEL_Y, 0.25)


func _physics_process(delta: float) -> void:
	age += delta
	if taken or age < ARM_S:
		return
	var tc := ThrownCredit.of(self)
	if tc != null and tc.held and tc.thrower is Doll and (tc.thrower as Doll).alive:
		pick(tc.thrower)
		return
	# касание, начавшееся до ARM_S (лут упал прямо на куклу): body_entered уже был — смотрим текущие контакты
	for b in get_colliding_bodies():
		var d := (b as Node).get_parent() as Doll
		if d != null and d.alive:
			pick(d)
			return


func _on_body_entered(b: Node) -> void:
	if taken or age < ARM_S:
		return
	var d := b.get_parent() as Doll
	if d != null and d.alive:
		pick.call_deferred(d)


## Подобрать (кукла by или null). Повторно — ничего.
func pick(by: Node) -> void:
	if taken or not is_inside_tree():
		return
	taken = true
	RunInventory.shared().add(material_id, amount, by)
	_popup("+%d %s" % [amount, RunInventory.title(material_id)])
	picked.emit(by, material_id)
	visible = false
	freeze = true
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	queue_free()


func _popup(text: String) -> void:
	var p := get_parent()
	if p == null:
		return
	var l := _make_label(text, 48, Color(1.0, 0.86, 0.35))
	l.outline_size = 14
	p.add_child(l)
	l.global_position = global_position + Vector3(0.0, 0.5, 0.4)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + POPUP_RISE_M, POPUP_S).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, POPUP_S).set_delay(POPUP_S * 0.4)
	tw.tween_property(l, "outline_modulate:a", 0.0, POPUP_S).set_delay(POPUP_S * 0.4)
	tw.chain().tween_callback(l.queue_free)


static func _make_label(text: String, size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.name = "LootLabel"
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_modulate = Color(0.08, 0.04, 0.02, 0.9)
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.shaded = false
	l.double_sided = true
	l.render_priority = 5
	l.outline_render_priority = 4
	return l
