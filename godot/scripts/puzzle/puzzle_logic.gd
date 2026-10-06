## Логика (docs/plan-demo/PUZZLE.md «Механизмы»): узел-коробка на задней стене. Входы inputs (пути к механизмам с is_on()) → режим →
## выход is_on():
##   AND   — ток, когда все входы под током;
##   OR    — когда хоть один;
##   TIMER — как OR, но держит ток ещё hold_s секунд после того, как входы погасли (на коробке — обратный отсчёт).
## Режимы можно ставить цепочкой (AND → TIMER: «две плиты сразу, дверь держится 4 с»). Коробку видно: подпись режима, лампа, у
## таймера — секунды.
class_name PuzzleLogic
extends PuzzlePart

enum Mode { AND, OR, TIMER }

@export var mode: Mode = Mode.AND
@export var inputs: Array[NodePath] = []
@export var hold_s := -1.0

var left_s := 0.0          # TIMER: сколько ещё держит (0 — не держит)
var _lamp_mat: StandardMaterial3D
var _caption: Label3D
var _count: Label3D


func _ready() -> void:
	if hold_s < 0.0:
		hold_s = Tuning.PUZZLE_TIMER_S
	box_mesh(self, "Box", Vector3(1.1, 0.7, 0.2), Vector3.ZERO, flat_material(Color(0.1, 0.11, 0.13), 0.6, 0.45))
	_lamp_mat = glow_material(COLOUR_IDLE, 2.0)
	var lamp := box_mesh(self, "Lamp", Vector3(0.9, 0.08, 0.04), Vector3(0, -0.24, 0.11), _lamp_mat)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_caption = label(self, "Mode", _mode_text(), Vector3(0, 0.08, 0.12), 40, Color(0.85, 0.9, 0.95))
	_count = label(self, "Count", "", Vector3(0, 0.62, 0.12), 44, Color(1.0, 0.85, 0.35))
	reset_state()


func _mode_text() -> String:
	match mode:
		Mode.AND:
			return tr("И")
		Mode.OR:
			return tr("ИЛИ")
	return tr("ТАЙМЕР %d с") % roundi(hold_s)


func reset_state() -> void:
	left_s = 0.0
	super.reset_state()
	_refresh_visual()


## Входы под током: [сколько, всего].
func inputs_on() -> Array:
	var n := 0
	for p in inputs:
		if power_of(p):
			n += 1
	return [n, inputs.size()]


func _physics_process(delta: float) -> void:
	var io := inputs_on()
	var n: int = io[0]
	var total: int = io[1]
	var v := false
	match mode:
		Mode.AND:
			v = total > 0 and n == total
		Mode.OR:
			v = n > 0
		Mode.TIMER:
			if n > 0:
				left_s = hold_s
				v = true
			elif left_s > 0.0:
				left_s = maxf(left_s - delta, 0.0)
				v = left_s > 0.0
				if v and int(ceil(left_s)) != int(ceil(left_s + delta)):
					sfx("tick", -6.0, 1.0)
	_set_on(v)
	_refresh_visual()


func _refresh_visual() -> void:
	if _lamp_mat == null:
		return
	var c := COLOUR_ON if _on else COLOUR_IDLE
	_lamp_mat.albedo_color = c
	_lamp_mat.emission = c
	_count.text = ("%.1f" % left_s) if mode == Mode.TIMER and left_s > 0.0 and inputs_on()[0] == 0 else ""
