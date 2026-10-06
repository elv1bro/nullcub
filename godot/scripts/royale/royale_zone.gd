## Зона «Королевской битвы» (docs/plan-demo/ROYALE.md; MODES_PACK.md §2: «зона на виде сбоку — две стены поля, сходящиеся с краёв к
## случайному окну шириной ~12 м»). Узел-ребёнок RoyaleMatch: логика стадий + видимые стены.
##   • setup(left, right, rng) — края карты и случайное последнее окно (центр в ±Tuning.ROYALE_ZONE_CENTER_MAX_X, ширина
##     ROYALE_ZONE_WINDOW_M); цели стадий вложены: стена k-й стадии = lerp(край карты → край последнего окна, f), f — доля пути по
##     ширине (Tuning.ROYALE_ZONE_STAGES: wait → shrink до width), после них — схлопывание ROYALE_ZONE_FINAL (ширина 0 — в центр окна);
##   • start() — с FIGHT!; tick(dt) — ход стадий (матч зовёт в физике); edges() — стены сейчас, edges_at(dt) — через dt с (боты держатся
##     внутри будущих стен), next_edges() — куда идут стены текущей / следующей стадии (HUD рисует их пунктиром);
##   • dps() — урон снаружи: dps стадии, чьё сжатие уже началось (до первого сжатия — 0); inside(x) — ЦМ внутри стен;
##   • вид: по стене с каждой стороны — полупрозрачное поле (квад от стены наружу на всю высоту карты, шейдер FIELD_SHADER: штриховка
##     ползёт, у стены — яркая кромка); рисуется поверх всего (depth_test_disabled), квады стоят в плоскости боя — кромка ровно там,
##     где начинается урон.
## Сигнал stage_changed(stage, shrinking) — стадия номер stage (1…N, N + 1 — схлопывание) начала паузу (shrinking = false) или сжатие.
class_name RoyaleZone
extends Node3D

signal stage_changed(stage: int, shrinking: bool)

const FIELD_COLOUR := Color(0.66, 0.3, 1.0)
const QUAD_OUT_M := 40.0          # квад поля уходит наружу за край карты на столько (камера у края видит поле, а не обрыв)
const QUAD_Y := Vector2(-6.0, 26.0)
const FIELD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.66, 0.3, 1.0, 1.0);
uniform float wall_x = 0.0;
uniform float side = -1.0;
uniform float alpha = 0.2;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float d = max(side * (wp.x - wall_x), 0.0);
	float edge = exp(-d * 2.2);
	float hatch = 0.5 + 0.5 * sin((wp.x * side + wp.y) * 2.4 - TIME * 2.6);
	ALBEDO = mix(tint.rgb, vec3(1.0), edge * 0.55) * (1.0 + edge * 1.2);
	ALPHA = clamp(alpha * (0.7 + 0.3 * hatch) + edge * 0.55, 0.0, 0.95);
}
"""

var map_l := -32.0
var map_r := 32.0
## Центр и ширина последнего окна.
var final_c := 0.0
var window := 12.0
## Стадии: [{wait, shrink, width, dps, l, r}] — l / r — стены в конце сжатия.
var stages: Array = []
## Номер стадии (индекс в stages), чья пауза или сжатие идёт; stages.size() — всё кончилось.
var idx := 0
var shrinking := false
var running := false
## Время с начала текущей паузы / сжатия.
var t := 0.0
var left := -32.0
var right := 32.0
var _from := Vector2(-32.0, 32.0)
var _quads: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _shader: Shader = null


func _ready() -> void:
	for s in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "FieldL" if s < 0.0 else "FieldR"
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		mi.mesh = q
		if _shader == null:
			_shader = Shader.new()
			_shader.code = FIELD_SHADER
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("tint", FIELD_COLOUR)
		m.set_shader_parameter("side", s)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_quads.append(mi)
		_mats.append(m)


## Края карты и случайное последнее окно; цели стадий — заново. Стены — на краях, зона стоит до start().
func setup(map_left: float, map_right: float, rng: RandomNumberGenerator) -> void:
	map_l = map_left
	map_r = map_right
	window = minf(Tuning.ROYALE_ZONE_WINDOW_M, map_r - map_l)
	var lim := minf(Tuning.ROYALE_ZONE_CENTER_MAX_X, (map_r - map_l - window) * 0.5)
	final_c = (map_l + map_r) * 0.5 + rng.randf_range(-lim, lim)
	build_stages()
	idx = 0
	t = 0.0
	shrinking = false
	running = false
	left = map_l
	right = map_r
	_from = Vector2(left, right)


## Цели стадий: ширина ≥ окна — вложенно к окну (f — доля пути по ширине), меньше окна — симметрично к его центру.
func build_stages() -> void:
	stages.clear()
	var list: Array = Tuning.ROYALE_ZONE_STAGES.duplicate()
	if not Tuning.ROYALE_ZONE_FINAL.is_empty():
		list.append(Tuning.ROYALE_ZONE_FINAL)
	var full := map_r - map_l
	var wl := final_c - window * 0.5
	var wr := final_c + window * 0.5
	for st in list:
		var s := (st as Dictionary).duplicate()
		var w := float(s["width"])
		if w >= window:
			var f := clampf((full - w) / maxf(full - window, 0.01), 0.0, 1.0)
			s["l"] = lerpf(map_l, wl, f)
			s["r"] = lerpf(map_r, wr, f)
		else:
			s["l"] = final_c - w * 0.5
			s["r"] = final_c + w * 0.5
		stages.append(s)


func start() -> void:
	running = true
	idx = 0
	t = 0.0
	shrinking = false
	left = map_l
	right = map_r
	stage_changed.emit(1, false)


func stop() -> void:
	running = false


func tick(dt: float) -> void:
	if not running or idx >= stages.size():
		return
	t += dt
	var st: Dictionary = stages[idx]
	if not shrinking:
		if t >= float(st["wait"]):
			shrinking = true
			t -= float(st["wait"])
			_from = Vector2(left, right)
			stage_changed.emit(idx + 1, true)
		else:
			return
	var f := clampf(t / maxf(float(st["shrink"]), 0.01), 0.0, 1.0)
	left = lerpf(_from.x, float(st["l"]), f)
	right = lerpf(_from.y, float(st["r"]), f)
	if f >= 1.0:
		t -= float(st["shrink"])
		shrinking = false
		idx += 1
		if idx < stages.size():
			stage_changed.emit(idx + 1, false)


## Стены сейчас: (левая, правая).
func edges() -> Vector2:
	return Vector2(left, right)


## Стены через dt с (по расписанию стадий): боты держатся внутри них.
func edges_at(dt: float) -> Vector2:
	if not running:
		return Vector2(left, right)
	var i := idx
	var tt := t + dt
	var sh := shrinking
	var from := _from if shrinking else Vector2(left, right)
	var cur := Vector2(left, right)
	while i < stages.size():
		var st: Dictionary = stages[i]
		if not sh:
			if tt < float(st["wait"]):
				return cur
			tt -= float(st["wait"])
			sh = true
			from = cur
		var f := clampf(tt / maxf(float(st["shrink"]), 0.01), 0.0, 1.0)
		cur = Vector2(lerpf(from.x, float(st["l"]), f), lerpf(from.y, float(st["r"]), f))
		if f < 1.0:
			return cur
		tt -= float(st["shrink"])
		sh = false
		i += 1
	return cur


## Куда идут стены: цель сжатия, которое идёт или будет следующим (всё кончилось — стены сейчас).
func next_edges() -> Vector2:
	if idx >= stages.size():
		return Vector2(left, right)
	return Vector2(float(stages[idx]["l"]), float(stages[idx]["r"]))


## Урон снаружи (HP/с): dps стадии, чьё сжатие уже началось; до первого сжатия — 0.
func dps() -> float:
	var started := idx if not shrinking else idx + 1
	if started <= 0:
		return 0.0
	return float(stages[mini(started, stages.size()) - 1]["dps"])


## Стадия для HUD: 1…stages.size() (последняя — схлопывание).
func stage_no() -> int:
	return mini(idx + 1, stages.size())


func stages_n() -> int:
	return stages.size()


## Сколько осталось текущей паузы / сжатия (с); всё кончилось — 0.
func time_left() -> float:
	if idx >= stages.size():
		return 0.0
	var st: Dictionary = stages[idx]
	return maxf((float(st["shrink"]) if shrinking else float(st["wait"])) - t, 0.0)


## Последняя стадия — схлопывание окна в точку.
func is_final() -> bool:
	return not Tuning.ROYALE_ZONE_FINAL.is_empty() and idx == stages.size() - 1


func done() -> bool:
	return idx >= stages.size()


func inside(x: float, margin := 0.0) -> bool:
	return x >= left + margin and x <= right - margin


## Насколько точка снаружи (м; внутри — 0).
func outside_by(x: float) -> float:
	return maxf(maxf(left - x, x - right), 0.0)


func centre() -> float:
	return (left + right) * 0.5


func _process(_delta: float) -> void:
	var show := running or left > map_l + 0.01 or right < map_r - 0.01
	for k in 2:
		var mi := _quads[k]
		mi.visible = show
		if not show:
			continue
		var wall := left if k == 0 else right
		var outer := (map_l - QUAD_OUT_M) if k == 0 else (map_r + QUAD_OUT_M)
		var w := absf(wall - outer)
		var cx := (wall + outer) * 0.5
		var h := QUAD_Y.y - QUAD_Y.x
		mi.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(maxf(w, 0.01), h, 1.0)), Vector3(cx, (QUAD_Y.x + QUAD_Y.y) * 0.5, 0.0))
		_mats[k].set_shader_parameter("wall_x", wall)
