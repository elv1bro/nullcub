## Камера прохода по картинке (docs/plan-demo/look/cam.md, LOOK_PASS.md п. 5 и 7). Автозагрузка «LookCam».
##   KO-камера и мини-повтор — к каждому Match обычного боя (скрипт ровно scripts/core/match.gd: Быстрый бой в куполе, арены 1–4,
##   кампания) ребёнком добавляется KoCam (scripts/look/ko_cam.gd). Наследники Match (PvE-волны, спорт-зал, стычка, бомба, гонка) —
##   без неё: там нокаутов за бой десятки. В headless и в тестовых сценах (res://tests/…) KoCam не ставится, пока проба сама не
##   включит `force` — гейты и чужие пробы видят бой как раньше.
##   Фоторежим — клавиша / (physical KEY_SLASH; в русской раскладке это «.») в любой 3D-сцене: PhotoMode (scripts/look/photo_mode.gd).
## Пункты панели «ВИД» (Э), группа «Камера»: cam_ko — стоп-кадр и облёт на нокауте, cam_replay — повтор перед карточкой KO,
## cam_photo — фоторежим. Выключенный пункт — ровно прежнее поведение (нет KoCam-действий, клавиша / ничего не делает).
extends Node

const KEY_PHOTO := PhotoMode.KEY_PHOTO
const ID_KO := &"cam_ko"
const ID_REPLAY := &"cam_replay"
const ID_PHOTO := &"cam_photo"
const MATCH_SCRIPT := "res://scripts/core/match.gd"

## Пробы: ставить KoCam и в headless, и в сценах res://tests/.
var force := false
var photo: PhotoMode = null


var _registered := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)


## Пункты «ВИД» регистрируются, когда в дереве появился бой (Match) или нажата клавиша фоторежима, — не при старте: панель «ВИД»
## в сценах без камеры боя их не показывает, и look_probe видит только свои пункты.
func register_items() -> void:
	var look := get_node_or_null("/root/Look")
	if look == null or _registered:
		return
	_registered = true
	look.add(ID_KO, tr("KO-камера: стоп-кадр и облёт"), tr("Камера"))
	look.add(ID_REPLAY, tr("Повтор нокаута перед карточкой KO"), tr("Камера"))
	look.add(ID_PHOTO, tr("Фоторежим — клавиша /"), tr("Камера"))


## Пункт «ВИД» включён (нет автозагрузки Look — включён).
func look_on(id: StringName) -> bool:
	var look := get_node_or_null("/root/Look")
	return look == null or bool(look.call("on", id))


func _on_node_added(n: Node) -> void:
	if n is Match:
		register_items()
		attach.call_deferred(n)


## Только обычный бой: скрипт Match ровно match.gd (не наследник).
static func plain_match(m: Node) -> bool:
	if m == null or not is_instance_valid(m):
		return false
	var s := m.get_script() as Script
	return s != null and s.resource_path == MATCH_SCRIPT


## Где KoCam работает: обычный бой, не headless и не тестовая сцена (или проба включила force).
func allowed_for(m: Node) -> bool:
	if not plain_match(m):
		return false
	if force:
		return true
	if DisplayServer.get_name() == "headless":
		return false
	var cs := get_tree().current_scene
	return cs == null or not cs.scene_file_path.begins_with("res://tests/")


## Поставить KoCam ребёнком Match (повторный вызов ничего не делает). Возвращает узел или null.
func attach(m: Node) -> KoCam:
	if m == null or not is_instance_valid(m) or not m.is_inside_tree():
		return null
	var have := m.get_node_or_null("KoCam") as KoCam
	if have != null:
		return have
	if not allowed_for(m):
		return null
	var k := KoCam.new()
	k.name = "KoCam"
	m.add_child(k)
	return k


# --- фоторежим ---

func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.physical_keycode != KEY_PHOTO:
		return
	if photo != null and is_instance_valid(photo) and photo.active:
		return   # выход по той же клавише ловит сам PhotoMode
	if get_tree().get_first_node_in_group(PhotoMode.KEY_TAKEN_GROUP) != null:
		return   # «/» в этом режиме — рука P2 (PhotoMode.KEY_TAKEN_GROUP)
	register_items()
	if not look_on(ID_PHOTO):
		return
	if toggle_photo():
		get_viewport().set_input_as_handled()


## Войти в фоторежим или выйти из него. false — войти нельзя (нет 3D-камеры, открыта пауза, лоадер).
func toggle_photo() -> bool:
	if photo != null and is_instance_valid(photo) and photo.active:
		photo.leave()
		return true
	if photo == null or not is_instance_valid(photo):
		photo = PhotoMode.new()
		photo.name = "PhotoMode"
		add_child(photo)
	return photo.enter()


func photo_active() -> bool:
	return photo != null and is_instance_valid(photo) and photo.active
