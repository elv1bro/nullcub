## Доводка прицела пулемёта на руке (docs/plan-demo/SQUAD.md, «Прицел»). ArmAssist тянет к цели кисть (точку хвата), а пулемёт
## стреляет вдоль оси детали, на которой стоит (предплечье; ActiveBlocks: +Y блока). У разных тел ось уходит от линии «плечо → кисть»
## на свой угол (локоть согнут, накладка стоит на боку детали): замер aim пробы 05.10 — «Человек» 9–14° мимо при руке, вытянутой к
## цели. Поправка — прямая, без накопления: каждый тик мерится угол delta от линии «плечо → кисть» до оси пулемёта (сглажен SMOOTH,
## |delta| ≤ OFF_MAX), и цель руке ставится по направлению «плечо → цель», повёрнутому на −delta. Интегратор по ошибке оси пробовал —
## рука отвечает за 0.13–0.28 с, и он раскачивался (до 160° мимо на «вверх»).
## Один объект на ствол (бот — свои, P1 — у площадки); новая кукла после возрождения — reset().
class_name GunAim
extends RefCounted

const SMOOTH := 0.25            # доля нового замера за тик
const OFF_MAX := 0.6            # рад (~34°)
const FAR_M := 3.0              # цель ближе к плечу — выносится на столько (у самого плеча направление прыгает)

## Сглаженный угол «линия руки → ось пулемёта» (рад, со знаком; + — ось повёрнута против часовой).
var delta := 0.0
var _has := false


func reset() -> void:
	delta = 0.0
	_has = false


## Точка для ArmAssist.set_target_override, чтобы ось ствола gun (SquadMatch.guns_of) легла на want; без ствола или руки — want.
func point_for(arm: ArmAssist, gun: Dictionary, want: Vector3) -> Vector3:
	if arm == null or not is_instance_valid(arm):
		return want
	var root := arm.root_point()
	var m := SquadMatch.muzzle_of(gun) if not gun.is_empty() else []
	if not m.is_empty():
		var ax := m[1] as Vector3
		var arm3 := arm.grip_global() - root
		var a2 := Vector2(arm3.x, arm3.y)
		if a2.length_squared() > 1e-4:
			var md := clampf(a2.normalized().angle_to(Vector2(ax.x, ax.y)), -OFF_MAX, OFF_MAX)
			delta = md if not _has else lerp_angle(delta, md, SMOOTH)
			_has = true
	var v := want - root
	v.z = 0.0
	var dist := maxf(v.length(), FAR_M)
	var dir := Vector2(v.x, v.y).normalized() if v.length_squared() > 1e-6 else Vector2.RIGHT
	dir = dir.rotated(-delta)
	return Vector3(root.x + dir.x * dist, root.y + dir.y * dist, 0.0)


## Угол (рад, без знака) между осью ствола и направлением «дуло → want»; PI — ствола нет.
static func error_to(gun: Dictionary, want: Vector3) -> float:
	var m := SquadMatch.muzzle_of(gun)
	if m.is_empty():
		return PI
	var to := want - (m[0] as Vector3)
	to.z = 0.0
	if to.length_squared() < 1e-4:
		return 0.0
	return (m[1] as Vector3).angle_to(to.normalized())
