## Бот «Гольфа: кукла — мяч» (docs/plan-demo/GOLF.md). Узел-ребёнок куклы (как мозги других режимов: U снимает его с P2 и
## возвращает, Match.respawn_doll переносит). Сам ничего не жмёт — GolfMatch спрашивает:
##   • think_s() — сколько думать, прежде чем ударить (Tuning.GOLF_BOT_THINK_S);
##   • plan(m, d) — удар {dir, power, target, arc}: цель — подсказка лунки (GolfCourse.bot_hint: у банкового удара — в мембрану, у
##     машин — в паровой столб, у гравитации вбок — дальше чаши), иначе чаша. Прицел — баллистика с дампом по гравитации в точке
##     удара (GolfShot.solve, закрытая формула — без симуляции), сверху разброс угла и силы уровня (Tuning.GOLF_BOT_LEVELS);
##   • nudge_dir(course, d, target) — поправка в полёте (уровни 2–3): кукла уже падает, а по той же формуле пролетит мимо цели удара дальше
##     1.5 м (и ближе 7 м) — рывок к цели; иначе Vector2.ZERO.
class_name GolfBrain
extends Node

static var default_level := 2

var level := 2
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	level = default_level
	rng.randomize()


func settings() -> Dictionary:
	return Tuning.GOLF_BOT_LEVELS.get(level, Tuning.GOLF_BOT_LEVELS[2])


func think_s() -> float:
	return rng.randf_range(Tuning.GOLF_BOT_THINK_S.x, Tuning.GOLF_BOT_THINK_S.y)


func plan(course: GolfCourse, d: Doll) -> Dictionary:
	var com := d.centre_of_mass()
	var p0 := Vector2(com.x, com.y)
	var hint := course.bot_hint(p0)
	var to: Vector2 = hint["to"]
	var arc := String(hint.get("arc", "min"))
	var g := course.gravity_at(p0)
	var s := GolfShot.solve(p0, to, g, Tuning.GOLF_DAMP, Tuning.GOLF_SPEED_MIN, Tuning.GOLF_SPEED_MAX, arc, float(hint.get("deg", -999.0)))
	var st := settings()
	var dir: Vector2 = s["dir"]
	dir = dir.rotated(deg_to_rad(rng.randf_range(-1.0, 1.0) * float(st["spread_deg"])))
	var base := float(hint["power"]) if hint.has("power") else GolfShot.power_for(float(s["speed"]))
	if hint.has("power") and hint.has("deg"):
		dir = Vector2.from_angle(deg_to_rad(float(hint["deg"]))).rotated(deg_to_rad(rng.randf_range(-1.0, 1.0) * float(st["spread_deg"])))
	var power := base + rng.randf_range(-1.0, 1.0) * float(st["power"])
	return {"dir": dir, "power": clampf(power, 0.0, 1.0), "target": to, "arc": arc, "solved": bool(s["ok"])}


func nudge_dir(course: GolfCourse, d: Doll, target: Vector2) -> Vector2:
	if not bool(settings().get("nudge", false)) or course.cup == null:
		return Vector2.ZERO
	var com := d.centre_of_mass()
	var p := Vector2(com.x, com.y)
	var v3 := d.com_velocity()
	var v := Vector2(v3.x, v3.y)
	var g := course.gravity_at(p)
	if v.dot(g) <= 0.0 or v.length() < 1.0:
		return Vector2.ZERO   # ещё летит вверх (против гравитации) или почти стоит
	var aim := target
	if p.distance_to(aim) > 9.0:
		return Vector2.ZERO
	# где окажется на высоте чаши (по формуле, без стен)
	var land := p
	for i in 60:
		var t := float(i + 1) * 0.05
		land = GolfShot.point_at(p, v, g, Tuning.GOLF_DAMP, t)
		if land.y <= aim.y:
			break
	var miss := land.x - aim.x
	if absf(miss) < 1.5 or absf(miss) > 7.0:
		return Vector2.ZERO
	return (aim - p).normalized()
