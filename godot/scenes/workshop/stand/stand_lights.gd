## Свет сборки (UI/UX spec v0.3 §48–51) — узел BuildLights в scenes/workshop/workshop_build.tscn. Самый контрастный объект кадра —
## кукла на стенде, фон — спокойный:
##   • Stand/Key — тёплый ключевой спот «лампы» спереди-сверху-слева, крутой угол: луч за куклой уходит в пол, а не в стену;
##   • Stand/Fill — холодная омни-подсветка справа на металл (короткий range: до задней стены не достаёт);
##   • Stand/Rim — контровой спот сзади-сверху на плечи и голову (силуэт), range обрезан до пола перед стендом;
##   • Bench/Key — лампа над верстаком для вида ОРУЖИЕ.
## Фон приглушаем светом, а не удалением декора: в сборке гасим солнце арены (оно же засвечивает пол перед стендом), её холодный
## Fill (единственный прямой свет на лицевую сторону задней стены), ambient и лампы на цепях (их конусы — пятна на стене и полу
## вокруг стенда); на испытании всё возвращаем, как в бою, а свои лампы гасим — комната испытаний освещена ровно, кукла не бегает
## из пятна света в тень. Переход плавный (fade_tau).
## Окружение арены копируем (Environment.duplicate): под-ресурс workshop.tscn общий для всех её инстансов в кэше, правка
## ambient «протекла» бы в бой на той же арене.
## Камере сборки (DOF дали в CameraAttributesPractical, только Forward+; в Compatibility игнорируется) каждый кадр ставим
## начало размытия чуть за фокусом (кукла / верстак) — стена и полки мягче, кукла резкая при любом зуме.
class_name StandLights
extends Node3D

@export var arena_path := NodePath("../Workshop")
@export var stand_path := NodePath("../Stand")
@export var bench_path := NodePath("../BenchSpot")
@export var camera_path := NodePath("../BuildCamera")
## Доля света арены в сборке: солнце, холодный Fill, ambient, лампы на цепях (1 — как в бою).
@export_range(0.0, 1.0) var sun_build := 0.45
@export_range(0.0, 1.0) var fill_build := 0.25
@export_range(0.0, 1.0) var ambient_build := 0.55
@export_range(0.0, 1.0) var lamps_build := 0.5
## Постоянная времени перехода сборка ↔ испытание, с.
@export var fade_tau := 0.2
## Размытие дали начинается на столько метров дальше фокуса.
@export var dof_margin := 0.9

@onready var stand_rig: Node3D = $Stand
@onready var bench_rig: Node3D = $Bench

var _sun: Light3D
var _fill: Light3D
var _env: Environment
var _sun_e := 0.0
var _fill_e := 0.0
var _amb_e := 0.0
var _own: Dictionary = {}     # Light3D -> энергия в сборке (из сцены)
var _lamps: Dictionary = {}   # Light3D ламп арены -> энергия как в бою
var _k := -1.0                # 1 — свет сборки, 0 — свет испытания (как в бою)


func _ready() -> void:
	var arena := get_node_or_null(arena_path)
	if arena != null:
		_sun = arena.get_node_or_null("Sun") as Light3D
		_fill = arena.get_node_or_null("Fill") as Light3D
		var holder := arena.get_node_or_null("Lamps")
		if holder != null:
			for l in holder.find_children("*", "Light3D", true, false):
				_lamps[l] = (l as Light3D).light_energy
		var we := arena.get_node_or_null("Environment") as WorldEnvironment
		if we != null and we.environment != null:
			we.environment = we.environment.duplicate() as Environment
			_env = we.environment
	if _sun != null:
		_sun_e = _sun.light_energy
	if _fill != null:
		_fill_e = _fill.light_energy
	if _env != null:
		_amb_e = _env.ambient_light_energy
	for rig in [stand_rig, bench_rig]:
		for c in (rig as Node).get_children():
			if c is Light3D:
				_own[c] = (c as Light3D).light_energy
	var cam := get_node_or_null(camera_path) as Camera3D
	if cam != null and cam.attributes != null:
		cam.attributes = cam.attributes.duplicate() as CameraAttributes   # свой экземпляр: фокус правим каждый кадр
	_follow()
	_apply(_target())


func _process(delta: float) -> void:
	_follow()
	var t := _target()
	if not is_equal_approx(_k, t):
		var k := lerpf(_k, t, 1.0 - exp(-delta / maxf(fade_tau, 0.001)))
		_apply(t if absf(k - t) < 0.01 else k)
	_focus()


## 1 — сборка, 0 — испытание (родитель WorkshopBuild; без него — всегда сборка).
func _target() -> float:
	var ws := get_parent()
	if ws != null and "mode" in ws and int(ws.get("mode")) == WorkshopBuild.Mode.TEST:
		return 0.0
	return 1.0


## Лампы стенда едут за стендом (без поворота: поворот стенда крутит куклу, а не свет), лампа верстака — за BenchSpot.
func _follow() -> void:
	var st := get_node_or_null(stand_path) as Node3D
	if st != null:
		stand_rig.global_position = st.global_position
	var bn := get_node_or_null(bench_path) as Node3D
	if bn != null:
		bench_rig.global_position = bn.global_position


func _apply(k: float) -> void:
	_k = k
	if _sun != null:
		_sun.light_energy = _sun_e * lerpf(1.0, sun_build, k)
	if _fill != null:
		_fill.light_energy = _fill_e * lerpf(1.0, fill_build, k)
	if _env != null:
		_env.ambient_light_energy = _amb_e * lerpf(1.0, ambient_build, k)
	for l in _lamps:
		if is_instance_valid(l):
			(l as Light3D).light_energy = float(_lamps[l]) * lerpf(1.0, lamps_build, k)
	for l in _own:
		var light := l as Light3D
		light.light_energy = float(_own[l]) * k
		light.visible = k > 0.001


## DOF дали камеры сборки: резкость до фокуса + dof_margin (фокус — кукла на стенде или верстак в виде ОРУЖИЕ).
func _focus() -> void:
	var cam := get_node_or_null(camera_path) as Camera3D
	if cam == null or not (cam.attributes is CameraAttributesPractical):
		return
	var ws := get_parent()
	var weapon := ws != null and "view" in ws and int(ws.get("view")) == WorkshopBuild.View.WEAPON
	var target := bench_rig.global_position if weapon else stand_rig.global_position + Vector3(0, 0.9, 0)
	(cam.attributes as CameraAttributesPractical).dof_blur_far_distance = cam.global_position.distance_to(target) + dof_margin
