## Якоря поверх 3D (мастерская): берёт WorkshopBuild.overlay_items() каждый кадр и рисует кольца в экранных точках.
##   target  — выбранный якорь: крупное яркое кольцо с заливкой (сюда встанет);
##   ok      — принимает деталь: зелёное пульсирующее кольцо + чёрточка направления роста (−Y якоря);
##   replace — занят, можно заменить: тонкое оранжевое колечко (не спорит с зелёными свободными);
##   bad     — принимает вид, но не влезает (энергия / сборка): красный крестик, без подсветки;
##   idle    — свободный якорь, пока ничего не тащишь: маленькая кремовая точка;
##   control — управляемая деталь («рука мышью»): золотое кольцо и подпись;
##   dim — разъём не принимает тащимую деталь: приглушённая точка (UI v0.2); selected — выбранная деталь: бегущее пунктирное кольцо;
##   com / com_ghost — Physics Overlay: центр массы стенда (перекрестие и отвес до пола) и куда он сместится с тащимой деталью;
##   joint / joint_hover — инструмент шарнира (кит v2): точка связи детали с родителем, кружок цвета типа (JointCard.COLORS) и
##       подпись типа (у обычной оси без подписи); наведённая деталь — крупнее, с пульсом.
extends Control

const JointCard := preload("res://scenes/workshop/ui/joint_card.gd")
const R_TARGET := 22.0
const R_OK := 14.0
const R_IDLE := 5.0

var ctl: Node = null
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if ctl == null or not is_instance_valid(ctl):
		return
	var font := get_theme_default_font()
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	for it in ctl.call("overlay_items"):
		var p: Vector2 = it["pos"]
		var dir: Vector2 = it["dir"]
		match String(it["state"]):
			"target":
				draw_circle(p, R_TARGET + 3.0, Color(0, 0, 0, 0.45))
				draw_circle(p, R_TARGET, Color(0.5, 1.0, 0.45, 0.35 + 0.2 * pulse))
				draw_arc(p, R_TARGET, 0.0, TAU, 40, Color(0.85, 1.0, 0.8), 4.0, true)
				if dir != Vector2.ZERO:
					draw_line(p, p + dir * (R_TARGET + 18.0), Color(0.85, 1.0, 0.8), 4.0, true)
			"ok":
				var r := R_OK + 3.0 * pulse
				draw_arc(p, r + 1.5, 0.0, TAU, 32, Color(0, 0, 0, 0.55), 6.0, true)
				draw_arc(p, r, 0.0, TAU, 32, Color(0.45, 0.95, 0.4), 3.5, true)
				if dir != Vector2.ZERO:
					draw_line(p + dir * r, p + dir * (r + 14.0), Color(0.45, 0.95, 0.4), 3.0, true)
			"replace":
				draw_arc(p, 9.5, 0.0, TAU, 24, Color(0, 0, 0, 0.35), 4.0, true)
				draw_arc(p, 9.0, 0.0, TAU, 24, Color(1.0, 0.62, 0.2, 0.55), 2.0, true)
			"bad":
				var s := 8.0
				draw_line(p + Vector2(-s, -s), p + Vector2(s, s), Color(0, 0, 0, 0.6), 6.0, true)
				draw_line(p + Vector2(-s, s), p + Vector2(s, -s), Color(0, 0, 0, 0.6), 6.0, true)
				draw_line(p + Vector2(-s, -s), p + Vector2(s, s), Color(1.0, 0.32, 0.25), 3.0, true)
				draw_line(p + Vector2(-s, s), p + Vector2(s, -s), Color(1.0, 0.32, 0.25), 3.0, true)
			"idle":
				draw_circle(p, R_IDLE + 2.0, Color(0, 0, 0, 0.4))
				draw_circle(p, R_IDLE, Color(1.0, 0.93, 0.78, 0.75))
			"selected":
				var rs := float(it.get("r", 30.0)) + 2.0 * pulse
				var seg := 24
				for i in seg:
					if i % 2 == 0:
						draw_arc(p, rs, TAU * i / seg + _t * 0.6, TAU * (i + 1) / seg + _t * 0.6, 6, Color(0, 0, 0, 0.5), 6.0, true)
						draw_arc(p, rs, TAU * i / seg + _t * 0.6, TAU * (i + 1) / seg + _t * 0.6, 6, Color(0.6, 0.9, 1.0), 3.0, true)
			"dim":
				draw_circle(p, 4.0, Color(0.55, 0.52, 0.48, 0.35))
			"com":
				var fl: Vector2 = it.get("floor", p)
				_dashed(p, fl, Color(1.0, 0.92, 0.6, 0.55))
				draw_arc(p, 11.0, 0.0, TAU, 28, Color(0, 0, 0, 0.6), 5.0, true)
				draw_arc(p, 11.0, 0.0, TAU, 28, Color(1.0, 0.9, 0.45), 2.5, true)
				draw_line(p + Vector2(-16, 0), p + Vector2(16, 0), Color(1.0, 0.9, 0.45), 2.0, true)
				draw_line(p + Vector2(0, -16), p + Vector2(0, 16), Color(1.0, 0.9, 0.45), 2.0, true)
				draw_circle(fl, 4.0, Color(1.0, 0.9, 0.45, 0.7))
			"com_ghost":
				var fr: Vector2 = it.get("from", p)
				_dashed(fr, p, Color(0.55, 0.9, 1.0, 0.9))
				draw_arc(p, 9.0, 0.0, TAU, 24, Color(0.55, 0.9, 1.0, 0.95), 2.5, true)
				var gl := String(it.get("label", ""))
				if gl != "" and font != null:
					var tg := p + Vector2(-16.0 - font.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, -10.0)   # слева: справа всплывашка разъёма
					draw_string_outline(font, tg, gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.9))
					draw_string(font, tg, gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.93, 1.0))
			"control":
				var rc := 30.0 + 2.0 * pulse
				draw_arc(p, rc + 1.5, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 6.0, true)
				draw_arc(p, rc, 0.0, TAU, 40, Color(1.0, 0.8, 0.25), 3.5, true)
				var label := String(it.get("label", ""))
				if label != "" and font != null:
					var fs := 20
					var tp := p + Vector2(rc + 8.0, 7.0)
					draw_string_outline(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.9))
					draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.85, 0.35))
			"joint", "joint_hover":
				var hov := String(it["state"]) == "joint_hover"
				var col: Color = JointCard.colour(String(it.get("joint", "")))
				var rj := (13.0 + 3.0 * pulse) if hov else 7.0
				draw_circle(p, rj + 2.5, Color(0, 0, 0, 0.55))
				draw_circle(p, rj, col)
				if hov:
					draw_arc(p, rj + 5.0, 0.0, TAU, 32, col.lightened(0.4), 3.0, true)
				var jl := String(it.get("label", ""))
				if jl != "" and font != null:
					var fj := 20 if hov else 17
					var tj := p + Vector2(rj + 6.0, 6.0)
					draw_string_outline(font, tj, jl, HORIZONTAL_ALIGNMENT_LEFT, -1, fj, 6, Color(0, 0, 0, 0.9))
					draw_string(font, tj, jl, HORIZONTAL_ALIGNMENT_LEFT, -1, fj, col.lightened(0.25))


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var dir := (b - a) / len
	var t := 0.0
	while t < len:
		draw_line(a + dir * t, a + dir * minf(t + 7.0, len), col, 2.0, true)
		t += 13.0
