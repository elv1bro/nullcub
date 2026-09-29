## Кадр заставки-комикса: данные одной панели в 3D-мире IntroStage. Узел собирает tools/build_intro_comic.gd, правится
## в редакторе: камеры CamA → CamB (Camera3D, в редакторе можно включить Preview), метки HeroA/HeroB и EnemyA/EnemyB
## (где стоит кукла в начале и в конце кадра), Props (предметы только этого кадра), Lights (свет только этого кадра).
## Таймлайн — строки «время:что» (секунды от начала кадра):
##   hero_keys / enemy_keys   "0:lying", "1.6:sit_up"            — позы ComicPoses, между ключами плавное смешивание
##   hero_params / enemy_params "0:eye=0,core=0.3,flicker=1"       — числа марионетки (eye, squint, core, flicker), линейно
##   events                   "0.9:drop:Barrel", "1.2:shake:0.25:0.4", "0.4:hero_hide:LowerArm_R", "1.1:shatter:enemy:1,0.4"
## Полный список событий — в IntroStage._apply_events().
class_name ComicShot
extends Node3D

@export var duration := 3.0
## Кривая наезда камеры CamA → CamB (как у ease(): < 0 — плавно на обоих концах, 1 — линейно).
@export var cam_ease := -1.6
@export var hero_ease := -1.8
## Окно движения по меткам HeroA → HeroB / EnemyA → EnemyB, секунды (x ≥ y — весь кадр).
@export var hero_move := Vector2.ZERO
@export var enemy_move := Vector2.ZERO
@export var enemy_ease := -1.8
@export var hero_visible := true
@export var enemy_visible := false
@export var hero_keys: PackedStringArray = PackedStringArray()
@export var hero_params: PackedStringArray = PackedStringArray()
@export var enemy_keys: PackedStringArray = PackedStringArray()
@export var enemy_params: PackedStringArray = PackedStringArray()
@export var events: PackedStringArray = PackedStringArray()
@export_group("Камера")
## Глубина резкости: дальняя граница (м от камеры, 0 — выключено) и ширина перехода.
@export var dof_far := 0.0
@export var dof_far_transition := 4.0
@export var dof_near := 0.0
@export var dof_near_transition := 0.6
@export_range(0.0, 1.0, 0.01) var dof_amount := 0.12
@export var exposure := 1.0
## Множитель ключевого прожектора арены (CameraKey едет за камерой; энергия и так падает на крупных планах).
@export var key_mult := 1.0
## Прятать передний слой параллакса (силуэты хлама у камеры) — для крупных планов.
@export var hide_fore_layer := false
## Узлы арены (пути от Scrap), которые мешают кадру и прячутся на время кадра.
@export var hide_nodes: PackedStringArray = PackedStringArray()
@export_group("")


## Разбор строк «t:value» → [[t, value], ...] по возрастанию t.
static func parse_keys(keys: PackedStringArray) -> Array:
	var out: Array = []
	for s in keys:
		var i := s.find(":")
		if i < 0:
			continue
		out.append([float(s.substr(0, i)), s.substr(i + 1)])
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


## Параметры «eye=1,core=0.5» → {"eye": 1.0, "core": 0.5}.
static func parse_params(s: String) -> Dictionary:
	var d := {}
	for kv in s.split(","):
		var p := kv.split("=")
		if p.size() == 2:
			d[p[0].strip_edges()] = float(p[1])
	return d
