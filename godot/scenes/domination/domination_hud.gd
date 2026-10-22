## HUD «Захвата точек» (docs/plan-demo/DOMINATION.md): всё от HUD стычки (SquadHud — табло команд и таймер, лента, карточка бойца,
## прицел, метки, итоги), плюс:
##   • под табло — три круга A / B / C: заливка — цвет владельца (нейтральная — тёмная), дуга по кругу — прогресс захвата цветом
##     команды, что берёт (у владельца — его запас), спорная — мигает белым; под кругами — кто внутри (точки цветов команд);
##   • игрок в зоне — строка над карточкой: «ТОЧКА A: ЗАХВАТ 45 %» / «СПОРНАЯ» / «НАША»;
##   • зоны за кадром — стрелки у края экрана с буквой и метрами;
##   • события зон — объявление по центру и строка в ленте.
class_name DominationHud
extends SquadHud

const ZONE_R := 24.0
const ZONE_GAP := 66.0
const ZONE_DARK := Color(0.06, 0.07, 0.09, 0.82)


func _ready() -> void:
	super._ready()
	hint_text = tr("WASD — лететь · мышь — прицел · ЛКМ — огонь · Q — перезарядка · 1–3 — класс · стой в зоне — захват · O — настройки")


func bind(m: SquadMatch) -> void:
	super.bind(m)
	if m.has_signal("zone_event") and not m.is_connected("zone_event", _on_zone):
		m.connect("zone_event", _on_zone)


func dm() -> DominationMatch:
	return match_node as DominationMatch


func _my_team() -> int:
	var me := _human()
	return SquadMatch.team_of(me) if me != null else 0


func _on_zone(i: int, what: String, team: int) -> void:
	var m := dm()
	if m == null:
		return
	var zn := m.zone_name(i)
	var mine := team == _my_team()
	var txt := ""
	var feed := ""
	match what:
		"captured":
			txt = (tr("ТОЧКА %s НАША") if mine else tr("СОПЕРНИК ВЗЯЛ ТОЧКУ %s")) % zn
			feed = tr("ВЗЯЛИ ТОЧКУ %s") % zn
		"neutralized":
			txt = (tr("ТОЧКА %s НЕЙТРАЛЬНА") if mine else tr("ТОЧКА %s ПОТЕРЯНА")) % zn
			feed = tr("СБИЛИ ТОЧКУ %s") % zn
	if txt == "":
		return
	_feed.append({"kind": "flag", "killer": tr("СИНИЕ") if team == 0 else tr("КРАСНЫЕ"), "kt": team, "vt": team,
		"victim": feed, "weapon": "", "left": FEED_HOLD_S})
	while _feed.size() > FEED_MAX:
		_feed.pop_front()
	announcer.announce(txt, SquadMatch.team_colour(team).lightened(0.35), "event")


func _draw_scoreboard(vp: Vector2) -> void:
	super._draw_scoreboard(vp)
	var m := dm()
	if m == null or m.zones.size() != m.zone_count():
		return
	var cx := vp.x * 0.5
	var cy := TOP + 78.0 + 36.0 + 14.0 + ZONE_R
	var n := m.zone_count()
	for i in n:
		var c := Vector2(cx + (float(i) - float(n - 1) * 0.5) * ZONE_GAP, cy)
		_zone_badge(c, i, ZONE_R)
	if end_panel.visible:
		return
	_draw_my_zone(vp, cy + ZONE_R + 26.0)


## Круг зоны i на табло: заливка — владелец, дуга — прогресс, буква, под ним — кто внутри.
func _zone_badge(c: Vector2, i: int, r: float) -> void:
	var m := dm()
	var z: Dictionary = m.zones[i]
	var owner := int(z["owner"])
	var prog := clampf(float(z["prog"]), 0.0, 1.0)
	var contested := bool(z["contested"])
	var fill := ZONE_DARK if owner < 0 else SquadMatch.team_colour(owner).darkened(0.1)
	canvas.draw_circle(c, r + 4.0, Color(0, 0, 0, 0.55))
	canvas.draw_circle(c, r, fill)
	canvas.draw_arc(c, r - 1.0, 0.0, TAU, 40, Color(1, 1, 1, 0.16), 4.0, true)
	var pt := owner if owner >= 0 else int(z["prog_team"])
	if prog > 0.0 and pt >= 0:
		var ac := SquadMatch.team_colour(pt).lightened(0.45)
		canvas.draw_arc(c, r - 1.0, -PI * 0.5, -PI * 0.5 + TAU * prog, 40, ac, 5.0, true)
	if contested:
		var a := 0.9 if fmod(_pulse, 0.5) < 0.25 else 0.25
		canvas.draw_arc(c, r + 3.0, 0.0, TAU, 40, Color(1, 1, 1, a), 3.0, true)
	_text(c + Vector2(0.0, 10.0), m.zone_name(i), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 0.0, 4)
	var cnt: Array = z["n"]
	var dots: Array = []
	for t in 2:
		for k in mini(int(cnt[t]), 3):
			dots.append(t)
	var x0 := c.x - float(dots.size() - 1) * 5.0
	for k in dots.size():
		canvas.draw_circle(Vector2(x0 + float(k) * 10.0, c.y + r + 10.0), 4.0, SquadMatch.team_colour(int(dots[k])).lightened(0.35))


## Игрок в зоне — строка под кругами: захват с процентом, спорная или «наша».
func _draw_my_zone(vp: Vector2, y: float) -> void:
	var me := _human()
	var m := dm()
	if me == null or not me.alive or m.play_state != "play":
		return
	var t := SquadMatch.team_of(me)
	for i in m.zone_count():
		if not m.dolls_in(i, t).has(me):
			continue
		var z: Dictionary = m.zones[i]
		var zn := m.zone_name(i)
		var txt := ""
		var col := Color.WHITE
		if bool(z["contested"]):
			txt = tr("ТОЧКА %s: СПОРНАЯ") % zn
			col = Color(1.0, 0.9, 0.45)
		elif int(z["owner"]) == t and float(z["prog"]) >= 1.0:
			txt = tr("ТОЧКА %s: НАША") % zn
			col = SquadMatch.team_colour(t).lightened(0.45)
		else:
			var p := float(z["prog"])
			if int(z["owner"]) == 1 - t:
				p = 1.0 - p
				txt = tr("ТОЧКА %s: СБИВАЕМ %d %%") % [zn, int(round(p * 100.0))]
			else:
				txt = tr("ТОЧКА %s: ЗАХВАТ %d %%") % [zn, int(round(p * 100.0)) if int(z["prog_team"]) == t else 0]
			col = SquadMatch.team_colour(t).lightened(0.45)
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 36.0
		_round(Rect2(vp.x * 0.5 - w * 0.5, y, w, 32.0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0), 0, 16, false)
		_text(Vector2(vp.x * 0.5, y + 24.0), txt, 22, col, HORIZONTAL_ALIGNMENT_CENTER, 520.0)
		return


## Зоны за кадром — стрелки у края экрана с буквой зоны и расстоянием (цвет — владелец).
func _draw_flags(cam: Camera3D, to_canvas: Transform2D, vp: Vector2, me: Doll) -> void:
	super._draw_flags(cam, to_canvas, vp, me)
	var m := dm()
	if m == null or me == null or m.zones.size() != m.zone_count():
		return
	for i in m.zone_count():
		var p := m.zone_centre(i)
		if cam.is_position_behind(p):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(p)
		if sp.x > 0.0 and sp.y > 0.0 and sp.x < vp.x and sp.y < vp.y:
			continue
		_zone_arrow(sp, vp, i, me.centre_of_mass().distance_to(p))


func _zone_arrow(sp: Vector2, vp: Vector2, i: int, metres: float) -> void:
	var m := dm()
	var centre := vp * 0.5
	var dir := sp - centre
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var half := centre - Vector2(ARROW_MARGIN + 10.0, ARROW_MARGIN + 40.0)
	var k := minf(half.x / maxf(absf(dir.x), 1e-4), half.y / maxf(absf(dir.y), 1e-4))
	var p := centre + dir * k
	var owner := m.zone_owner(i)
	var c := DominationZone.colour_of(owner)
	var side := Vector2(-dir.y, dir.x)
	var tip := p + dir * 26.0
	var pts := PackedVector2Array([tip + dir * 12.0, tip - dir * 6.0 + side * 10.0, tip - dir * 6.0 - side * 10.0])
	canvas.draw_colored_polygon(pts, c)
	canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 2.0)
	canvas.draw_circle(p, 20.0, Color(0, 0, 0, 0.6))
	canvas.draw_arc(p, 18.0, 0.0, TAU, 32, c, 3.0, true)
	if bool(m.zones[i]["contested"]) and fmod(_pulse, 0.5) < 0.25:
		canvas.draw_arc(p, 22.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)
	_text(p + Vector2(0.0, 8.0), m.zone_name(i), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 0.0, 4)
	_text(p - dir * 34.0 + Vector2(0.0, 6.0), tr("%d м") % int(round(metres)), 18, c, HORIZONTAL_ALIGNMENT_CENTER)
