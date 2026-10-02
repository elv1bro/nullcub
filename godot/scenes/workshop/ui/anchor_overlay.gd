## Слой поверх 3D (мастерская v0.3): берёт WorkshopBuild.overlay_items() каждый кадр и рисует в экранных точках. Цвета — смысловые
## (WsStyle): бледно-голубой — совместимый разъём, зелёный — встанет, янтарный — замена / тяга, красный — нельзя.
##   ok      — совместимый разъём, пока деталь в руке: проступает за FADE_S и ярче ближе к курсору (near 0…1);
##   target  — разъём под деталью: зелёное кольцо с заливкой (встанет); bad — красный крестик (не встанет: энергия / сборка);
##   replace — занят, можно заменить: тонкое янтарное колечко;
##   carry   — кольцо на конце детали в руке (где она прикрутится): голубое, над годным разъёмом — зелёное;
##   flash   — щелчок: расходящееся кольцо у разъёма (деталь встала / открутилась); refuse — красный пульс и причина;
##   control — тяга (только с инструментом Q или у выбранной детали): янтарное / голубое кольцо и подпись;
##   com / com_ghost — центр массы и куда он сместится (кнопка «Физика»); при ней же — слой WsPhysics (нагрузка суставов, опора);
##   joint / joint_hover — инструмент шарнира: кружок цвета типа (JointCard) и подпись; idle / dim / selected — старые состояния.
extends Control

const JointCard := preload("res://scenes/workshop/ui/joint_card.gd")
const R_TARGET := 20.0
const R_OK := 11.0
const R_IDLE := 5.0
const FADE_S := 0.18
const COL_OK := Color(0.72, 0.86, 1.0)
const COL_GO := Color(0.5, 0.9, 0.45)
const COL_BAD := Color(0.95, 0.34, 0.27)
const COL_AMBER := Color(1.0, 0.74, 0.3)

var ctl: Node = null
var _t := 0.0
var _drag_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	var dragging: bool = ctl != null and is_instance_valid(ctl) and not (ctl.get("drag") as Dictionary).is_empty()
	_drag_t = _drag_t + delta if dragging else 0.0
	queue_redraw()


func _draw() -> void:
	if ctl == null or not is_instance_valid(ctl):
		return
	var font := get_theme_default_font()
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	var fade := clampf(_drag_t / FADE_S, 0.0, 1.0)
	_draw_physics(font)
	for it in ctl.call("overlay_items"):
		var p: Vector2 = it["pos"]
		var dir: Vector2 = it["dir"]
		match String(it["state"]):
			"target":
				draw_circle(p, R_TARGET + 3.0, Color(0, 0, 0, 0.4))
				draw_circle(p, R_TARGET, Color(COL_GO, 0.28 + 0.14 * pulse))
				draw_arc(p, R_TARGET, 0.0, TAU, 40, COL_GO.lightened(0.35), 3.0, true)
			"ok":
				# читается и на голубых / стальных деталях: тёмная подложка кольца, лёгкая заливка, дальние не тусклее 0.55
				var near := float(it.get("near", 0.5))
				var a := fade * (0.55 + 0.45 * near)
				var r := R_OK + 2.0 * near + 1.5 * pulse * near
				draw_circle(p, r, Color(COL_OK, 0.18 * a))
				draw_arc(p, r + 1.2, 0.0, TAU, 28, Color(0, 0, 0, 0.8 * a), 4.5, true)
				draw_arc(p, r, 0.0, TAU, 28, Color(COL_OK, a), 2.2, true)
				draw_circle(p, 2.5, Color(COL_OK, a))
				if dir != Vector2.ZERO and near > 0.4:
					draw_line(p + dir * r, p + dir * (r + 10.0), Color(COL_OK, a), 2.0, true)
			"replace":
				var ar := fade * 0.8
				draw_arc(p, 9.0, 0.0, TAU, 24, Color(0, 0, 0, 0.35 * ar), 4.0, true)
				draw_arc(p, 8.5, 0.0, TAU, 24, Color(COL_AMBER, 0.7 * ar), 2.0, true)
			"bad":
				var s := 7.0
				var ab := fade
				for q in [[Vector2(-s, -s), Vector2(s, s)], [Vector2(-s, s), Vector2(s, -s)]]:
					draw_line(p + q[0], p + q[1], Color(0, 0, 0, 0.55 * ab), 5.0, true)
					draw_line(p + q[0], p + q[1], Color(COL_BAD, ab), 2.5, true)
			"carry":
				var good := bool(it.get("ok", false))
				var cc := COL_GO if good else COL_OK
				draw_arc(p, 9.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 4.5, true)
				draw_arc(p, 8.0, 0.0, TAU, 24, cc, 2.0, true)
				draw_circle(p, 2.0, cc)
			"flash":
				var age := float(it.get("age", 0.0))
				var rf := 10.0 + 34.0 * age
				draw_arc(p, rf, 0.0, TAU, 36, Color(1.0, 0.95, 0.75, 0.9 * (1.0 - age)), 3.0 * (1.0 - age) + 1.0, true)
				draw_circle(p, 6.0 * (1.0 - age), Color(1.0, 0.92, 0.6, 0.8 * (1.0 - age)))
			"refuse":
				var ag := float(it.get("age", 0.0))
				var rr := 14.0 + 10.0 * sin(ag * PI * 3.0) * (1.0 - ag)
				draw_arc(p, rr, 0.0, TAU, 32, Color(COL_BAD, 0.9 * (1.0 - ag * 0.7)), 3.0, true)
				var why := String(it.get("label", ""))
				if why != "" and font != null:
					var fs := 18
					var w := font.get_string_size(why, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					var tp := p + Vector2(-w * 0.5, -rr - 12.0)
					var col := Color(1.0, 0.72, 0.66, 1.0 - ag * ag)
					draw_string_outline(font, tp, why, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85 * col.a))
					draw_string(font, tp, why, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			"joint_sel":
				draw_arc(p, 7.5, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 4.0, true)
				draw_arc(p, 7.0, 0.0, TAU, 24, COL_AMBER, 2.0, true)
				draw_circle(p, 2.0, COL_AMBER)
			"idle":
				draw_circle(p, R_IDLE + 2.0, Color(0, 0, 0, 0.4))
				draw_circle(p, R_IDLE, Color(1.0, 0.93, 0.78, 0.75))
			"dim":
				draw_circle(p, 4.0, Color(0.55, 0.52, 0.48, 0.35))
			"selected":
				draw_arc(p, float(it.get("r", 30.0)), 0.0, TAU, 40, Color(COL_OK, 0.5), 1.5, true)
			"com":
				if bool(ctl.get("show_com")):
					continue   # «Физика» включена — центр масс и его сдвиг рисует WsPhysics
				var fl: Vector2 = it.get("floor", p)
				_dashed(p, fl, Color(1.0, 0.92, 0.6, 0.45))
				draw_circle(p, 7.0, Color(0, 0, 0, 0.5))
				draw_circle(p, 4.5, Color(1.0, 0.86, 0.45, 0.8 + 0.2 * pulse))
				draw_arc(p, 10.0 + 2.0 * pulse, 0.0, TAU, 28, Color(1.0, 0.86, 0.45, 0.45), 1.5, true)
				draw_circle(fl, 3.0, Color(1.0, 0.9, 0.45, 0.6))
			"com_ghost":
				if bool(ctl.get("show_com")):
					continue
				var fr: Vector2 = it.get("from", p)
				_dashed(fr, p, Color(COL_OK, 0.85))
				draw_arc(p, 7.0, 0.0, TAU, 24, Color(COL_OK, 0.95), 2.0, true)
				var gl := String(it.get("label", ""))
				if gl != "" and font != null:
					var tg := p + Vector2(-14.0 - font.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, -10.0)
					draw_string_outline(font, tg, gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color(0, 0, 0, 0.9))
					draw_string(font, tg, gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_OK)
			"channel":   # активный блок: плашка клавиши канала (цвет канала — ActiveRig.COL_CH; без канала — серая)
				var ch := int(it.get("channel", 0))
				var col: Color = ActiveRig.COL_CH[ch - 1] if ch >= 1 and ch <= 3 else Color(0.6, 0.6, 0.6)
				var lb := String(it.get("label", ""))
				var w := 30.0 if font == null else maxf(30.0, font.get_string_size(lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 14.0)
				var rect := Rect2(p + Vector2(-w * 0.5, -58.0), Vector2(w, 26.0))   # выше центра: справа от детали — подпись тяги ЛКМ / ПКМ
				draw_rect(rect.grow(2.0), Color(0, 0, 0, 0.75), true)
				draw_rect(rect, col, false, 2.5)
				if font != null:
					var tpos := rect.position + Vector2((w - font.get_string_size(lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x) * 0.5, 20.0)
					draw_string(font, tpos, lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
			"control":
				var rc := 26.0 + 2.0 * pulse
				var label := String(it.get("label", ""))
				var cc2 := Color(0.35, 0.8, 1.0) if bool(it.get("rmb", false)) else COL_AMBER
				draw_arc(p, rc + 1.5, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 5.0, true)
				draw_arc(p, rc, 0.0, TAU, 40, cc2, 2.5, true)
				if label != "" and font != null:
					var fs2 := 18
					var tp2 := p + Vector2(rc + 8.0, 6.0)
					draw_string_outline(font, tp2, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 6, Color(0, 0, 0, 0.9))
					draw_string(font, tp2, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, cc2)
			"joint", "joint_hover":
				var hov := String(it["state"]) == "joint_hover"
				var col2: Color = JointCard.colour(String(it.get("joint", "")))
				var rj := (12.0 + 3.0 * pulse) if hov else 7.0
				draw_circle(p, rj + 2.5, Color(0, 0, 0, 0.55))
				draw_circle(p, rj, col2)
				if hov:
					draw_arc(p, rj + 5.0, 0.0, TAU, 32, col2.lightened(0.4), 2.5, true)
				var jl := String(it.get("label", ""))
				if jl != "" and font != null:
					var fj := 19 if hov else 16
					var tj := p + Vector2(rj + 6.0, 6.0)
					draw_string_outline(font, tj, jl, HORIZONTAL_ALIGNMENT_LEFT, -1, fj, 6, Color(0, 0, 0, 0.9))
					draw_string(font, tj, jl, HORIZONTAL_ALIGNMENT_LEFT, -1, fj, col2.lightened(0.25))


## «Физика» включена: нагрузка суставов (зелёный → жёлтый → красный), распределение массы, опора и куда заваливается —
## рисует WsPhysics (если модуль есть). Выключена — модель чистая.
func _draw_physics(font: Font) -> void:
	if not bool(ctl.get("show_com")) or int(ctl.get("mode")) != 0 or int(ctl.get("view")) != 0:
		return
	var stand: Variant = ctl.get("stand")
	var cam := get_viewport().get_camera_3d()
	if stand == null or not is_instance_valid(stand) or cam == null:
		return
	var paint: Variant = ctl.get("paint")
	if paint != null and bool(paint.get("tab_open")):
		return
	var opts := {"t": _t, "labels": true, "floor_y": (ctl.get("stand_root") as Node3D).global_position.y}
	var g: Variant = ctl.call("drag_com")
	if g is Vector3:
		opts["ghost_com"] = g
	WsPhysics.draw(self, cam, stand as Node, font, opts)


func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
	var len := a.distance_to(b)
	if len < 1.0:
		return
	var dir := (b - a) / len
	var t := 0.0
	while t < len:
		draw_line(a + dir * t, a + dir * minf(t + 7.0, len), col, 2.0, true)
		t += 13.0
