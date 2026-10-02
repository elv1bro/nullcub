## Взрывная бочка (железные бочки Свалки prop_metal_barrel / _dented, 29.09). Breakable: HP, урон от ударов, лут при разрушении —
## как у деревянной; разрушение = взрыв (Explosion.detonate), обломков нет.
##
## Фитиль. Бочка получила урон, но не лопнула (≤ 50 % HP — состояние DAMAGED), или её задел соседний взрыв — поджиг:
## через FUSE_S (цепная реакция — короче) взрыв. Пока горит — мигает красным всё чаще, из горловины бьют искры, шипит.
## Горящую бочку можно схватить и бросить (лёгкий класс, PropHeft.LIGHT) — брошенная на скорости ≥ Breakable.THROWN_MIN_SPEED
## взрывается от удара сразу.
## Кому засчитать: бросивший (ThrownCredit) → последний ударивший (часть куклы / оружие в руке) → кто поджёг.
class_name ExplosiveBarrel
extends Breakable

const FUSE_HISS := "res://assets/audio/loops/fuse_hiss.ogg"
const FUSE_S := 2.2
const BLINK_HZ_FROM := 2.5
const BLINK_HZ_TO := 12.0
const SPARK_EVERY_S := 0.09
const TOP_Y := 0.95            # м: горловина (бочка 0.91 м)

var lit := false
var fuse_left := 0.0
var _blame: Node = null
var _blink_mat: StandardMaterial3D
var _spark_t := 0.0
var _blink_on := false
var _exploded := false


func _ready() -> void:
	super._ready()
	state_changed.connect(_on_state)
	hit.connect(_on_hit)
	_blink_mat = StandardMaterial3D.new()
	_blink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blink_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_blink_mat.albedo_color = Color(1.0, 0.15, 0.05, 0.55)


## Поджечь: взрыв через delay (если уже горит — фитиль только укорачивается).
func ignite(delay: float = FUSE_S, by: Node = null) -> void:
	if _exploded or state == State.DESTROYED:
		return
	if by != null and _blame == null:
		_blame = by
	if lit:
		fuse_left = minf(fuse_left, delay)
		return
	lit = true
	fuse_left = delay
	var sfx := get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector if is_inside_tree() else null
	if sfx != null:
		sfx.play_layer("clank", -2.0, 1.2, SfxDirector.BUS_SFX, sfx.pan_for(global_position))
	_start_fuse_hiss()


## Шипение фитиля (петля loops/fuse_hiss.ogg на AudioStreamPlayer3D, шина SFX) — громче к взрыву; гаснет с бочкой.
func _start_fuse_hiss() -> void:
	if get_node_or_null("FuseHiss") != null or not ResourceLoader.exists(FUSE_HISS):
		return
	var p := AudioStreamPlayer3D.new()
	p.name = "FuseHiss"
	var st := load(FUSE_HISS) as AudioStream
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	p.stream = st
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.panning_strength = 0.7
	p.volume_db = -14.0
	add_child(p)
	p.play()


func _on_state(s: int) -> void:
	if s == State.DAMAGED:
		ignite(FUSE_S)


func _on_hit(_speed: float, _dmg: float, by: Node) -> void:
	var d := _doll_of(by)
	if d != null:
		_blame = d


static func _doll_of(n: Node) -> Doll:
	if n == null or not is_instance_valid(n):
		return null
	if n is Doll:
		return n
	if n.get_parent() is Doll:
		return n.get_parent()
	if n is Weapon:
		var h: Variant = n.get("holder")
		if h is Node and (h as Node).get_parent() is Doll:
			return (h as Node).get_parent()
	return null


func blame() -> Node:
	var tc := ThrownCredit.of(self)
	if tc != null and tc.attacker() != null:
		return tc.attacker()
	return _blame if _blame != null and is_instance_valid(_blame) else null


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not lit or _exploded:
		return
	fuse_left -= delta
	var k := 1.0 - clampf(fuse_left / FUSE_S, 0.0, 1.0)
	var hiss := get_node_or_null("FuseHiss") as AudioStreamPlayer3D
	if hiss != null:
		hiss.volume_db = lerpf(-14.0, -4.0, k)
		hiss.pitch_scale = lerpf(0.9, 1.3, k)
	var hz := lerpf(BLINK_HZ_FROM, BLINK_HZ_TO, k * k)
	var on := fmod(_time * hz, 1.0) < 0.5
	if on != _blink_on:
		_blink_on = on
		_set_blink(on)
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = SPARK_EVERY_S
		var sc := SparkCone.new()
		sc.name = "FuseSpark"
		get_parent().add_child(sc)
		var up := global_transform.basis.y
		sc.setup(global_position + up * TOP_Y, up.rotated(Vector3.BACK, randf_range(-0.5, 0.5)), Color(1.0, 0.7, 0.2), 0.6)
	if fuse_left <= 0.0:
		take_damage(hp + 1.0)


func _set_blink(on: bool) -> void:
	var m := _mesh_root()
	if m == null:
		return
	for gi in m.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).material_overlay = _blink_mat if on else null


## Разрушение = взрыв (обломков из GLB у железной бочки нет — Breakable._spawn_debris ничего не спавнит).
func _destroy() -> void:
	if _exploded:
		return
	_exploded = true
	var p := global_position + global_transform.basis.y * 0.45
	var parent := get_parent()
	var by := blame()
	super._destroy()
	Explosion.detonate(parent, p, by, self)
