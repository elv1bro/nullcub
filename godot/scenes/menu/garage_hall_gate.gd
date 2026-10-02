## Двустворчатые ворота в тренировочный зал на левой стене гаража (scenes/arena/training_hall.tscn; docs/plan-demo/MENU_GARAGE.md,
## «Тренировочный зал»): модуль Fighter_Gate кита Old NULL Hall (рама Gate_Frame и створки Gate_Door_L / Gate_Door_R с петлями),
## собирает их garage_menu.tscn (tools/build_garage_menu.gd). open() — створки распахиваются в зал (как ворота бойцов в куполе,
## FighterEntrance), close() — закрываются. Сигналы opened / closed — когда створки дошли. Пока открыты — коллайдер-заглушка
## проёма (Stage/Bounds/WallL встроенной мастерской) отключает GarageWorkshop.
class_name GarageHallGate
extends Node3D

signal opened
signal closed

const OPEN_DEG := 105.0
const OPEN_S := 1.1
const CLOSE_S := 0.9

var is_open := false
var _doors := {}                 # узел → [угол закрытой, знак открывания]
var _tw: Tween


func _ready() -> void:
	for pair in [["Gate_Door_L", 1.0], ["Gate_Door_R", -1.0]]:
		var d := find_child(String(pair[0]), true, false) as Node3D
		if d != null:
			_doors[d] = [d.rotation.y, float(pair[1])]


func open(secs := OPEN_S) -> void:
	_swing(true, secs)


func close(secs := CLOSE_S) -> void:
	_swing(false, secs)


func _swing(want_open: bool, secs: float) -> void:
	if want_open == is_open and _tw == null:
		return
	is_open = want_open
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween().set_parallel(true).set_ignore_time_scale(true)
	for d in _doors:
		var closed_y := float(_doors[d][0])
		var to := closed_y + (deg_to_rad(OPEN_DEG) * float(_doors[d][1]) if want_open else 0.0)
		_tw.tween_property(d, "rotation:y", to, maxf(secs, 0.01)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tw.chain().tween_callback(func() -> void:
		if is_open:
			opened.emit()
		else:
			closed.emit())
