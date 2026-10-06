## Бомба на кукле (docs/plan-demo/BOMB.md): только вид и звук, без коллизии. Круглая чугунная бомба с жёлтым поясом на груди держателя
## (кукла смотрит в камеру +Z — на спине её бы не было видно), лампа и красный свет мигают на каждый писк BombMatch.beeped, на конце
## фитиля — искра (SparkCone, как у взрывной бочки) и тихое шипение loops/fuse_hiss.ogg (громче к концу, по BombMatch.urgency).
## Писк — синтез (как EnemyLook / ScrapMachine): короткий сигнал ~2 кГц, к концу фитиля чуть выше и громче. Передача — щелчок
## (SfxDirector «clank»). Узел — ребёнок BombMatch; следует за торсом держателя по видимому (интерполированному) положению в _process.
class_name BombCarry
extends Node3D


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # двигается в _process за видимым торсом


const OFFSET := Vector3(0.0, 0.02, 0.24)   # от центра торса: на груди, к камере (торс 0.36 × 0.52 × 0.22 м)
const BODY_R := 0.14
const FUSE_TIP := Vector3(0.05, 0.27, 0.0)
const SPARK_EVERY_S := 0.14
const BEEP_RATE := 22050
const BEEP_S := 0.075
const FUSE_HISS := "res://assets/audio/loops/fuse_hiss.ogg"

var match_node: BombMatch
var holder: Doll = null
## Пробы: сколько писков прозвучало / вспышек показано.
var beeps_played := 0
var _flash := 0.0
var _spark_t := 0.0
var _lamp_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D
var _spark: MeshInstance3D
var _light: OmniLight3D
var _beep: AudioStreamPlayer3D
var _hiss: AudioStreamPlayer3D
static var _beep_wav: AudioStreamWAV


func _ready() -> void:
	_build()
	visible = false


func bind(m: BombMatch) -> void:
	match_node = m
	m.bomb_passed.connect(_on_passed)
	m.bomb_exploded.connect(func(_v: Doll, _p: Vector3) -> void: _detach())
	m.beeped.connect(_on_beep)
	m.round_started.connect(func(_r: int) -> void: _detach())
	m.match_over.connect(func(_w: Doll, _r: Dictionary) -> void: _detach())


func _mat(albedo: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metal
	m.roughness = rough
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	add_child(mi)
	return mi


func _build() -> void:
	var shell := SphereMesh.new()
	shell.radius = BODY_R
	shell.height = BODY_R * 2.0
	_mesh(shell, _mat(Color(0.08, 0.08, 0.09), 0.65, 0.38), Vector3.ZERO)
	var band := CylinderMesh.new()
	band.top_radius = BODY_R * 1.03
	band.bottom_radius = BODY_R * 1.03
	band.height = 0.045
	_mesh(band, _mat(Color(0.95, 0.72, 0.1), 0.2, 0.5), Vector3(0.0, -0.02, 0.0))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.045
	neck.bottom_radius = 0.055
	neck.height = 0.07
	_mesh(neck, _mat(Color(0.25, 0.24, 0.22), 0.8, 0.35), Vector3(0.0, BODY_R + 0.02, 0.0))
	var fuse := CylinderMesh.new()
	fuse.top_radius = 0.011
	fuse.bottom_radius = 0.013
	fuse.height = 0.11
	_mesh(fuse, _mat(Color(0.75, 0.66, 0.48), 0.0, 0.9), Vector3(0.028, BODY_R + 0.09, 0.0), Vector3(0.0, 0.0, -28.0))
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.45, 0.05, 0.03)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.12, 0.05)
	_lamp_mat.emission_energy_multiplier = 0.3
	var lamp := SphereMesh.new()
	lamp.radius = 0.042
	lamp.height = 0.084
	_mesh(lamp, _lamp_mat, Vector3(0.0, 0.035, BODY_R - 0.012))
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.albedo_color = Color(1.0, 0.85, 0.35)
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var spark := SphereMesh.new()
	spark.radius = 0.035
	spark.height = 0.07
	_spark = _mesh(spark, _spark_mat, FUSE_TIP)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.18, 0.08)
	_light.omni_range = 2.4
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.05, 0.35)
	add_child(_light)
	_beep = AudioStreamPlayer3D.new()
	_beep.name = "Beep"
	_beep.stream = beep_stream()
	_beep.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_beep.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_beep.panning_strength = 0.6
	_beep.max_polyphony = 3
	add_child(_beep)
	if ResourceLoader.exists(FUSE_HISS):
		_hiss = AudioStreamPlayer3D.new()
		_hiss.name = "FuseHiss"
		var st := load(FUSE_HISS) as AudioStream
		if st is AudioStreamOggVorbis:
			st = (st as AudioStreamOggVorbis).duplicate()
			(st as AudioStreamOggVorbis).loop = true
		_hiss.stream = st
		_hiss.bus = _beep.bus
		_hiss.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		_hiss.panning_strength = 0.6
		_hiss.volume_db = -26.0
		add_child(_hiss)


## Писк: синус ~1.95 кГц с третьей гармоникой, атака 3 мс, спад — «электронный» сигнал таймера.
static func beep_stream() -> AudioStreamWAV:
	if _beep_wav != null:
		return _beep_wav
	var n := int(BEEP_S * BEEP_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / BEEP_RATE
		var env := minf(t / 0.003, 1.0) * exp(-t * 26.0)
		var v := (sin(TAU * 1950.0 * t) + 0.28 * sin(TAU * 5850.0 * t)) * 0.55 * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	_beep_wav = AudioStreamWAV.new()
	_beep_wav.format = AudioStreamWAV.FORMAT_16_BITS
	_beep_wav.mix_rate = BEEP_RATE
	_beep_wav.stereo = false
	_beep_wav.data = data
	return _beep_wav


func _on_passed(from: Doll, to: Doll) -> void:
	holder = to
	visible = to != null
	_flash = Tuning.BOMB_BEEP_FLASH_S
	if _hiss != null and is_inside_tree() and not _hiss.playing:
		_hiss.play()
	if from != null and is_inside_tree():
		var sfx := get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
		if sfx != null and to != null:
			sfx.play_layer("clank", -6.0, 1.55, SfxDirector.BUS_SFX, sfx.pan_for(to.centre_of_mass()))
	_follow()


func _detach() -> void:
	holder = null
	visible = false
	if _hiss != null:
		_hiss.stop()
	if _light != null:
		_light.light_energy = 0.0


func _on_beep(urgency: float) -> void:
	beeps_played += 1
	_flash = Tuning.BOMB_BEEP_FLASH_S
	if _beep != null and is_inside_tree():
		_beep.volume_db = lerpf(-12.0, -4.0, urgency)
		_beep.pitch_scale = lerpf(1.0, 1.18, urgency)
		_beep.play()


func _follow() -> void:
	if holder == null or not is_instance_valid(holder) or not holder.alive or not holder.parts.has("Torso"):
		return
	var t := holder.torso()
	global_transform = t.get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, OFFSET)


func _process(delta: float) -> void:
	if holder == null or not is_instance_valid(holder) or not holder.alive:
		if visible:
			_detach()
		return
	var real := delta / maxf(Engine.time_scale, 0.02)
	_follow()
	_flash = maxf(_flash - real, 0.0)
	var on := _flash > 0.0
	var u := match_node.urgency() if match_node != null else 0.0
	_lamp_mat.emission_energy_multiplier = 7.0 if on else 0.3 + 0.5 * u
	_light.light_energy = 2.6 if on else 0.0
	_spark.scale = Vector3.ONE * randf_range(0.6, 1.25)
	_spark_mat.albedo_color.a = randf_range(0.6, 1.0)
	if _hiss != null:
		_hiss.volume_db = lerpf(-26.0, -14.0, u)
		_hiss.pitch_scale = lerpf(0.9, 1.25, u)
	_spark_t -= real
	if _spark_t <= 0.0 and get_parent() != null:
		_spark_t = SPARK_EVERY_S
		var sc := SparkCone.new()
		sc.name = "FuseSpark"
		get_parent().add_child(sc)
		var up := global_transform.basis.y
		sc.setup(to_global(FUSE_TIP), up.rotated(Vector3.BACK, randf_range(-0.6, 0.6)), Color(1.0, 0.72, 0.25), 0.35, 0.8)
