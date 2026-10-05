## Спорт-зал (docs/plan-demo/SPORT.md): закрытая коробка в плоскости боя z = 0 — пол y = 0, потолок y = SPORT_FIELD_H, стены
## x = ±SPORT_FIELD_HALF_W — из кита Old NULL Hall (как тренировочный зал), со снарядами трёх видов спорта:
##   Fixtures/football   — ворота у обеих стен (рама, сетка; коллайдер — крыша ворот с уклоном к полю: мяч сверху скатывается);
##   Fixtures/basketball — щиты с кольцами на стенах (коллайдеры: щит и передняя дужка кольца);
##   Fixtures/volleyball — сетка по центру (коллайдер сетки + невидимая стенка для кукол над ней: мяч её не замечает).
## apply_sport(id) оставляет в мире один набор (остальные невидимы и вне физики). Сцену sport_hall.tscn собирает
## tools/build_sport_hall.gd; числа поля и снарядов — Tuning.SPORT_* / Tuning.SPORTS.
## API арен: spawn_points(), bounds(), breakables(), сигнал body_fell (пропасти нет — не испускается). Своё: ball_spawn(serve_team),
## ball_passthrough() — тела, сквозь которые мяч проходит; set_score(a, b) и подписи табло на задней стене (Board/*).
class_name SportHallArena
extends Node3D

@warning_ignore("unused_signal")
signal body_fell(body: Node3D)

## Границы для камеры: поле со стенами и запасом сверху под фермы света — 16:9, камера с fit_bounds видит зал целиком.
@export var arena_bounds := AABB(Vector3(-12.0, -1.5, -1.0), Vector3(24.0, 13.5, 2.0))
@export var sport := "football"

var score := [0, 0]


func _ready() -> void:
	apply_sport(sport)
	set_score(0, 0)


func apply_sport(id: String) -> void:
	if not Tuning.SPORTS.has(id):
		return
	sport = id
	var fx := get_node_or_null("Fixtures")
	if fx != null:
		for f in fx.get_children():
			var on := String(f.name) == id
			(f as Node3D).visible = on
			f.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	var sub := get_node_or_null("Board/Sub") as Label3D
	if sub != null:
		sub.text = "%s · %s" % [tr(String(Tuning.SPORTS[id]["title"])), tr("ДО %d") % Tuning.SPORT_GOALS_TO_WIN]


## Точки ввода кукол: P1 слева, P2 справа, P3 / P4 — глубже к своим воротам.
func spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var holder := get_node_or_null("Spawns")
	if holder:
		for m in holder.get_children():
			if m is Node3D:
				out.append((m as Node3D).global_position)
	return out


func bounds() -> AABB:
	return arena_bounds


func breakables() -> Array:
	return []


## Точка ввода мяча. Волейбол — над половиной команды serve_team (ей принимать), остальные — по центру.
func ball_spawn(serve_team: int = 0) -> Vector3:
	var r: Dictionary = Tuning.SPORTS[sport]
	var x := 0.0
	if r.has("serve_x"):
		x = float(r["serve_x"]) * (-1.0 if serve_team == 0 else 1.0)
	return Vector3(x, float(r.get("ball_y", 3.0)), 0.0)


## Тела, с которыми мяч не сталкивается (стенка для кукол над волейбольной сеткой).
func ball_passthrough() -> Array:
	var out: Array = []
	for n in find_children("DollBarrier*", "StaticBody3D", true, false):
		out.append(n)
	return out


func set_score(a: int, b: int) -> void:
	score = [a, b]
	var l := get_node_or_null("Board/ScoreL") as Label3D
	var r := get_node_or_null("Board/ScoreR") as Label3D
	if l != null:
		l.text = str(a)
	if r != null:
		r.text = str(b)
