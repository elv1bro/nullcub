## Сборочный стенд мастерской (UI/UX spec v0.3 §3, §48–51) — узел Stand в scenes/workshop/workshop_build.tscn.
## Настоящий верстачный прибор, а не «палка с блином»: поворотный стол (стальная плита, резиновый диск с кантом, риски шкалы
## через 10°, латунные винты), рейка с пазом на башмаке с косынками, муфта высоты с латунным винтом и Т-ручкой, сверху седло
## со струбциной к спине торса. Всё тёмное и нейтральное (сталь, уголь; латунь только на винтах), чтобы стенд никогда не сливался
## с бойцом: самый контрастный объект кадра — кукла (свет — stand_lights.gd).
##
## Контракт с workshop_build.gd (его не трогаем): там stand_root = $Stand, кукла ставится в Stand.global_position, а
## _update_pole() на каждой пересборке берёт get_node_or_null("Pole") и ставит scale = (1, h, 1), position = (0, h / 2, z), где h —
## высота торса над стендом. Поэтому Pole — рейка с центром в середине (растяжение по Y ей не вредит: паз и кромки тоже тянутся
## только по длине), а всё, что по Y тянуть нельзя (муфта, седло), живёт отдельно и догоняет высоту рейки здесь.
## Поворот стенда (покраска, R) крутит весь узел Stand — стол, рейка и седло едут вместе с куклой, как у настоящей вертушки.
## На испытании кукла оживает на месте стенда, а тел у стенда нет (одни MeshInstance3D) — прибор прячется, чтобы кукла не
## проходила сквозь рейку и диск.
class_name BuildStand
extends Node3D

## Муфта высоты — на этой доле высоты торса (между ног, где рейку видно спереди), но не ниже COLLAR_MIN над полом.
const COLLAR_FRAC := 0.55
const COLLAR_MIN := 0.12

@onready var pole: Node3D = $Pole
@onready var collar: Node3D = $Collar
@onready var saddle: Node3D = $Saddle

var _h := -1.0
var _shown := true


func _ready() -> void:
	_fit(pole.scale.y)


func _process(_delta: float) -> void:
	var h := pole.scale.y
	if not is_equal_approx(h, _h):
		_fit(h)
	var want := not _testing()
	if want != _shown:
		_shown = want
		for c in get_children():
			if c is Node3D:
				(c as Node3D).visible = want


## Муфта и седло — к текущей высоте рейки (h — длина Pole, верх рейки = центр торса).
func _fit(h: float) -> void:
	_h = h
	var z := pole.position.z
	saddle.position = Vector3(0, h, z)
	collar.position = Vector3(0, clampf(h * COLLAR_FRAC, COLLAR_MIN, maxf(COLLAR_MIN, h - 0.1)), z)


## Родитель — WorkshopBuild в режиме испытания (без родителя-мастерской стенд просто стоит).
func _testing() -> bool:
	var ws := get_parent()
	return ws != null and "mode" in ws and int(ws.get("mode")) == WorkshopBuild.Mode.TEST


## Верх рейки в мировых координатах (там седло держит торс) — для камеры, подсказок и проб.
func top_position() -> Vector3:
	return saddle.global_position
