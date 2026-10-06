## HUD «Королевской битвы» (docs/plan-demo/ROYALE.md). Наследник SquadHud стычки: тот же слой canvas (_draw), шрифт скина HUD, плашки,
## прицел у курсора (кольцо магазина, пауза, перезарядка, заряд гаусса, луч до стены), цифры урона, диктор, табличка итогов (Label —
## проба вёрстки). Команд нет — у каждого свой цвет (Tuning.ROYALE_COLORS). Своё:
##   • сверху по центру — табло зоны: «ЗОНА n/N», таймер паузы или сжатия, «ОСТАЛОСЬ N» с черепом; под ним — что сейчас («ДО СЖАТИЯ»,
##     «СЖАТИЕ», «СХЛОПЫВАНИЕ») и урон снаружи; выбыл — «ТЫ ВЫБЫЛ · МЕСТО n · СМОТРИШЬ: Pk»;
##   • куда сожмётся зона — пунктир на месте будущих стен; ты за стеной — красная рамка экрана и «ВНУТРЬ →» с уроном;
##   • справа сверху — лента «кто — чем — кого» (зона — значок часов), цвета бойцов;
##   • над бойцами — имя, HP и броня, бонусы; соперники за кадром — стрелки к трём ближним; без оружия — стрелка к ближнему ящику с
##     оружием за кадром;
##   • слева снизу — карточка бойца (цвет, имя, HP с делениями, броня, бонусы, фраги); справа снизу — карточка оружия (картинка ствола,
##     магазин / запас, состояние) или «БЕЗ ОРУЖИЯ — К ЯЩИКУ»;
##   • конец — «ПОБЕДА!» / «ПОБЕДИЛ Pk» / «НИЧЬЯ», твоё место и таблица мест (место, боец, фраги, урон, оружие).
## bind(match, playground) — подписка на RoyaleMatch.
class_name RoyaleHud
extends SquadHud

const ZONE_COLOUR := Color(0.78, 0.5, 1.0)
const ARROWS_MAX := 3

const SLOW_S := 0.05             # медленный слой (табло, лента, карточки) — 20 раз в секунду

var rm: RoyaleMatch
var playground: Node = null
## Медленный слой: табло зоны, лента, карточки, подсказка — их текст меняется редко, а перерисовка каждого кадра стоила ~3 мс
## (замер 06.10: весь HUD — 4 мс на кадр в окне 1080p). Каждый кадр — только canvas: метки над бойцами, прицел, цифры, рамка «за стеной».
var slow: Control
var _slow_t := 0.0


func _ready() -> void:
	super._ready()
	slow = Control.new()
	slow.name = "Slow"
	slow.set_anchors_preset(Control.PRESET_FULL_RECT)
	slow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slow.draw.connect(_draw_slow)
	root.add_child(slow)
	root.move_child(slow, canvas.get_index() + 1)
	end_table.columns = 5
	var again := end_panel.find_child("Again", true, false) as Label
	if again != null:
		again.text = tr("R — заново · G — день / ночь · Esc — пауза и выход в гараж")
	refresh_hint()


func bind(m: SquadMatch) -> void:
	super.bind(m)
	rm = m as RoyaleMatch
	if rm == null:
		return
	if not rm.eliminated.is_connected(_on_eliminated):
		rm.eliminated.connect(_on_eliminated)
		rm.weapon_taken.connect(_on_weapon_taken)
		rm.zone_stage.connect(_on_zone_stage)


func refresh_hint() -> void:
	var p2b := true
	if playground != null and playground.get("p2_bot") != null:
		p2b = bool(playground.get("p2_bot"))
	hint_text = tr("WASD — лететь · мышь — прицел · ЛКМ — огонь · Q — перезарядка · E — схватить") + "  ·  " + \
		(tr("U — P2 на стрелках") if p2b else tr("P2: стрелки, Num 1 — огонь, Num 2 — перезарядка (U — бот)")) + "  ·  " + \
		tr("K — боты · G — день / ночь · R — заново")
	_clock = 0.0


func toast(text: String) -> void:
	announcer.announce(text, Color(0.9, 0.9, 0.95), "")


## Имя бойца: человек P1 — ТЫ, остальные — P1…P8.
static func rname(d: Object) -> String:
	if d == null or not is_instance_valid(d) or not (d is Doll):
		return TranslationServer.translate("ЗОНА")
	var dd := d as Doll
	if dd.player_index == 0 and not dd.external_input:
		return TranslationServer.translate("ТЫ")
	return RoyaleMatch.fighter_name(dd)


static func colour(d: Object) -> Color:
	if d == null or not is_instance_valid(d) or not (d is Doll):
		return ZONE_COLOUR
	return RoyaleMatch.colour_for((d as Doll).player_index)


## Кого показывает HUD: живой человек, иначе тот, за кем смотрит камера, иначе «я» матча.
func _view_doll() -> Doll:
	var me := _human()
	if me != null and me.alive:
		return me
	if playground != null and playground.get("spectating") is Doll:
		var s := playground.get("spectating") as Doll
		if is_instance_valid(s):
			return s
	return me


# --- сигналы ---

func _on_eliminated(victim: Doll, killer: Doll, place: int, left: int, cause: String) -> void:
	_feed.append({"kind": cause, "killer": rname(killer) if killer != null else "", "kc": colour(killer) if killer != null else ZONE_COLOUR,
		"victim": rname(victim), "vc": colour(victim), "weapon": tr(rm.weapon_name(killer)) if killer != null else "", "left": FEED_HOLD_S})
	while _feed.size() > FEED_MAX:
		_feed.pop_front()
	var me := _human()
	if victim == me and me != null:
		announcer.announce(tr("ТЫ ВЫБЫЛ · МЕСТО %d") % place, Color(1.0, 0.45, 0.4), "ko")
	elif killer != null and killer == me:
		announcer.announce(tr("KO!"), GOLD, "ko")
	if left > 1 and rm.play_state == "play":
		announcer.announce(tr("ОСТАЛОСЬ %d") % left, Color(0.95, 0.95, 1.0), "event")


func _on_weapon_taken(d: Doll, id: String, _from: String) -> void:
	if d != null and d == _human():
		announcer.announce(tr(String(Tuning.SQUAD_WEAPONS[id]["title"])), Color(1.0, 0.9, 0.55), "event")


func _on_zone_stage(stage: int, shrinking: bool) -> void:
	if not shrinking or rm.play_state != "play":
		return
	var final := rm.zone.is_final() or stage > Tuning.ROYALE_ZONE_STAGES.size()
	announcer.announce(tr("ЗОНА СХЛОПЫВАЕТСЯ!") if final else tr("ЗОНА СЖИМАЕТСЯ!"), ZONE_COLOUR, "event")


## Итоги: победитель, твоё место, таблица мест.
func _on_over(winner: Doll, results: Dictionary) -> void:
	var me := _human()
	if winner == null:
		end_title.text = tr("НИЧЬЯ")
		end_title.set_meta("colour", Color.WHITE)
	elif me != null and winner == me:
		end_title.text = tr("ПОБЕДА!")
		end_title.set_meta("colour", GOLD)
	else:
		end_title.text = tr("ПОБЕДИЛ %s") % rname(winner)
		end_title.set_meta("colour", colour(winner).lightened(0.35))
	var pl: Dictionary = results.get("royale_places", {})
	var n := rm.dolls().size() if rm != null else 0
	end_score.text = tr("ТВОЁ МЕСТО: %d ИЗ %d") % [int(pl.get(me.player_index, n)), n] if me != null else tr("БОЙ БОТОВ")
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var white := Color(1, 1, 1, 0.7)
	for h in [tr("МЕСТО"), tr("БОЕЦ"), tr("ФРАГИ"), tr("УРОН"), tr("ОРУЖИЕ")]:
		_cell(h, white, end_table.get_child_count() == 1, 20)
	var tally: Dictionary = results.get("tally", {})
	var dolls: Array = rm.dolls() if rm != null else []
	dolls.sort_custom(func(a: Doll, b: Doll) -> bool:
		var pa := int(pl.get(a.player_index, 99))
		var pb := int(pl.get(b.player_index, 99))
		return pa < pb if pa != pb else a.player_index < b.player_index)
	var weapons: Dictionary = results.get("weapons", {})
	for d in dolls:
		var pi := (d as Doll).player_index
		var t: Dictionary = tally.get(pi, {})
		var c := colour(d).lightened(0.4)
		var place := int(pl.get(pi, 0))
		_cell(str(place) if place > 0 else "—", GOLD if place == 1 else Color.WHITE, false, 24)
		_cell(rname(d) + (" ★" if place == 1 else ""), c, true, 22)
		_cell(str(int(t.get("kills", 0))), Color.WHITE, false, 22)
		_cell(str(int(round(float(t.get("damage", 0.0))))), Color.WHITE, false, 22)
		var w := String(weapons.get(pi, ""))
		_cell(tr(String(Tuning.SQUAD_WEAPONS[w]["title"])) if w != "" else "—", Color(1, 1, 1, 0.8), true, 20)
	_apply_skin()
	end_panel.visible = true
	end_panel.modulate.a = 0.0
	var tw := end_panel.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.6)
	tw.tween_property(end_panel, "modulate:a", 1.0, 0.3)


# --- кадр ---

func _process(delta: float) -> void:
	super._process(delta)
	_slow_t += delta / maxf(Engine.time_scale, 0.02)
	if _slow_t >= SLOW_S and slow != null:
		_slow_t = 0.0
		slow.queue_redraw()


## Быстрый слой (каждый кадр): будущие стены, метки над бойцами, рамка «за стеной», прицел, цифры урона.
func _draw_all() -> void:
	if rm == null or end_panel.visible:
		return   # итоги: метки бойцов просвечивали бы сквозь табличку
	var cam := get_viewport().get_camera_3d()
	var vp := get_viewport().get_visible_rect().size
	var to_canvas := canvas.get_global_transform_with_canvas().affine_inverse()
	var me := _human()
	var view := _view_doll()
	if cam != null:
		_draw_next_zone(cam, to_canvas, vp)
		_draw_marks_r(cam, to_canvas, vp, view)
	if me != null and me.alive and rm.play_state == "play":
		_draw_outside(vp, me)
		if cam != null:
			var g := SquadMatch.gun_of(me)
			if g != null and g.weapon != "":
				_draw_aim(cam, to_canvas, me)
			elif not me.external_input:
				var mp := canvas.get_local_mouse_position()
				canvas.draw_circle(mp, 24.0, Color(0, 0, 0, 0.22))
				canvas.draw_arc(mp, 20.0, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 3.0, true)
				_icon("fist", mp, 16.0, Color(1, 1, 1, 0.8))
	if cam != null:
		_draw_digits(cam, to_canvas)


## Медленный слой (SLOW_S): табло зоны, лента, карточки бойца и оружия, подсказка. Помощники рисуют на canvas — на время слоя это slow.
func _draw_slow() -> void:
	if rm == null or end_panel.visible:
		return
	var keep := canvas
	canvas = slow
	var vp := get_viewport().get_visible_rect().size
	var view := _view_doll()
	_draw_zone_board(vp, _human())
	_draw_feed_r(vp)
	if view != null:
		_draw_card(vp, view)
		_draw_weapon_r(vp, view)
	if _clock < HINT_S:
		var a := clampf((HINT_S - _clock) / 1.2, 0.0, 1.0)
		_text(Vector2(vp.x * 0.5, vp.y - 20.0), hint_text, 20, Color(1, 1, 1, 0.75 * a), HORIZONTAL_ALIGNMENT_CENTER, vp.x - 1100.0)
	canvas = keep


# --- табло зоны ---

func _draw_zone_board(vp: Vector2, me: Doll) -> void:
	var z := rm.zone
	var cx := vp.x * 0.5
	var w := 600.0
	var h := 78.0
	var y := TOP
	var r := Rect2(cx - w * 0.5, y, w, h)
	SquadIcons.plate(canvas, r.grow(3.0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55), 0.0)
	SquadIcons.plate(canvas, r, Color(0.09, 0.07, 0.14, 0.92), Color(0.03, 0.03, 0.05, 0.92), 0.0)
	canvas.draw_rect(Rect2(r.position, Vector2(w, 4.0)), ZONE_COLOUR)
	# стадия
	var st := z.stage_no() if z.stages_n() > 0 else 1
	_text(Vector2(r.position.x + 22.0, y + 30.0), tr("ЗОНА"), 20, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_LEFT, 150.0)
	_text(Vector2(r.position.x + 22.0, y + h - 12.0), "%d/%d" % [st, maxi(z.stages_n(), 1)], 40, ZONE_COLOUR.lightened(0.3))
	# таймер
	var left := z.time_left() if z.running else float((Tuning.ROYALE_ZONE_STAGES[0] as Dictionary)["wait"])
	var s := int(ceil(left))
	var hot := z.shrinking
	_text(Vector2(cx, y + h * 0.5 + 16.0), "%d:%02d" % [s / 60, s % 60], 46, Color(1.0, 0.55, 0.95) if hot else Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER)
	# осталось
	var n := rm.alive_count()
	_icon("skull", Vector2(r.end.x - 120.0, y + h * 0.5), 30.0, Color(1, 1, 1, 0.85))
	_text(Vector2(r.end.x - 22.0, y + h - 12.0), str(n), 52, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(r.end.x - 22.0, y + 26.0), tr("ОСТАЛОСЬ"), 18, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
	# что сейчас
	var cap := ""
	if z.done():
		cap = tr("ЗОНА СХЛОПНУЛАСЬ · СНАРУЖИ −%d HP/с") % int(z.dps())
	elif z.shrinking:
		cap = (tr("СХЛОПЫВАНИЕ") if z.is_final() else tr("СЖАТИЕ")) + " · " + tr("СНАРУЖИ −%d HP/с") % int(z.dps())
	elif z.dps() > 0.0:
		cap = tr("ДО СЖАТИЯ") + " · " + tr("СНАРУЖИ −%d HP/с") % int(z.dps())
	else:
		cap = tr("ДО СЖАТИЯ") + " · " + tr("СОБЕРИ ОРУЖИЕ В ЯЩИКАХ")
	if me != null and not me.alive and rm.play_state == "play":
		var v := _view_doll()
		cap = tr("ТЫ ВЫБЫЛ · МЕСТО %d") % rm.place_of(me)
		if v != null and v != me:
			cap += " · " + tr("СМОТРИШЬ: %s") % rname(v)
	var cw := _font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 36.0
	cw = minf(cw, 760.0)
	_round(Rect2(cx - cw * 0.5, y + h + 6.0, cw, 30.0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 0, 15, false)
	_text(Vector2(cx, y + h + 28.0), cap, 20, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 730.0)


## Будущие стены зоны — пунктир на всю высоту карты (пока стены туда не пришли).
func _draw_next_zone(cam: Camera3D, to_canvas: Transform2D, vp: Vector2) -> void:
	var z := rm.zone
	if not z.running or z.done():
		return
	var e := z.edges()
	var nx := z.next_edges()
	var b := rm._map_bounds()
	for k in 2:
		var x := nx.x if k == 0 else nx.y
		var cur := e.x if k == 0 else e.y
		if absf(x - cur) < 0.05:
			continue
		var a3 := Vector3(x, b.position.y, 0.0)
		var b3 := Vector3(x, b.end.y, 0.0)
		if cam.is_position_behind(a3) or cam.is_position_behind(b3):
			continue
		var p0: Vector2 = to_canvas * cam.unproject_position(a3)
		var p1: Vector2 = to_canvas * cam.unproject_position(b3)
		if p0.x < -10.0 or p0.x > vp.x + 10.0:
			continue
		var a := 0.45 + 0.25 * absf(sin(_pulse * 3.0)) if z.shrinking else 0.4
		canvas.draw_dashed_line(p0, p1, Color(1, 1, 1, a), 3.0, 18.0, true)


## Ты за стеной зоны: красная рамка экрана, «ВНУТРЬ» со стрелкой и урон.
func _draw_outside(vp: Vector2, me: Doll) -> void:
	var z := rm.zone
	var x := me.centre_of_mass().x
	if z.inside(x):
		return
	var k := 0.55 + 0.35 * absf(sin(_pulse * 5.0))
	var col := Color(1.0, 0.2, 0.35, k)
	for rr in [Rect2(0, 0, vp.x, 10.0), Rect2(0, vp.y - 10.0, vp.x, 10.0), Rect2(0, 0, 10.0, vp.y), Rect2(vp.x - 10.0, 0, 10.0, vp.y)]:
		canvas.draw_rect(rr, col)
	var dir := 1.0 if x < z.left else -1.0
	var txt := tr("ТЫ ЗА СТЕНОЙ ЗОНЫ · −%d HP/с") % int(z.dps()) + "  " + (tr("ВНУТРЬ →") if dir > 0.0 else tr("← ВНУТРЬ"))
	var y := vp.y * 0.24
	var tw := minf(_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x + 40.0, 900.0)
	_round(Rect2(vp.x * 0.5 - tw * 0.5, y - 34.0, tw, 46.0), Color(0.35, 0.03, 0.08, 0.8), Color(0, 0, 0, 0), 0, 10)
	_text(Vector2(vp.x * 0.5, y), txt, 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 860.0)


# --- лента ---

func _draw_feed_r(vp: Vector2) -> void:
	var y := 22.0
	for e in _feed:
		var a := clampf(float(e["left"]) / 0.6, 0.0, 1.0)
		var kc: Color = (e["kc"] as Color).lightened(0.35)
		var vc: Color = (e["vc"] as Color).lightened(0.35)
		var k := String(e["killer"])
		var w := String(e["weapon"])
		var v := String(e["victim"])
		var px := 22
		var kw := _font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if k != "" else 0.0
		var ww := _font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x if w != "" else 0.0
		var vw := _font.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var icon_w := 26.0
		var total := kw + vw + icon_w + (ww + 12.0 if w != "" else 0.0) + 40.0
		var r := Rect2(vp.x - 24.0 - total, y, total, 36.0)
		_round(r, Color(0.03, 0.035, 0.05, 0.72 * a), Color(0, 0, 0, 0), 0, 6, false)
		canvas.draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), Color(kc.r, kc.g, kc.b, a))
		var x := r.position.x + 14.0
		var base := y + 26.0
		if k != "":
			_text(Vector2(x, base), k, px, Color(kc.r, kc.g, kc.b, a), HORIZONTAL_ALIGNMENT_LEFT, 0.0, 4)
			x += kw + 8.0
		_icon("clock" if String(e["kind"]) == "zone" else "skull", Vector2(x + 10.0, y + 18.0), 20.0, Color(1, 1, 1, 0.85 * a))
		x += icon_w
		if w != "":
			_text(Vector2(x, base - 1.0), w, 17, Color(0.82, 0.82, 0.86, a), HORIZONTAL_ALIGNMENT_LEFT, 0.0, 3)
			x += ww + 12.0
		_text(Vector2(x, base), v, px, Color(vc.r, vc.g, vc.b, a), HORIZONTAL_ALIGNMENT_LEFT, 0.0, 4)
		y += 42.0


# --- над бойцами ---

func _draw_marks_r(cam: Camera3D, to_canvas: Transform2D, vp: Vector2, view: Doll) -> void:
	var off: Array = []   # [дистанция, экранная точка, цвет]
	for n in rm.dolls():
		var d := n as Doll
		if not is_instance_valid(d) or not d.is_inside_tree() or not d.alive:
			continue
		var head: Node3D = d.parts.get("Head", d.torso()) as Node3D
		if head == null:
			continue
		var top := head.global_position + Vector3(0.0, BAR_LIFT, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(top)
		var c := colour(d).lightened(0.3)
		var inside := sp.x > 0.0 and sp.y > 0.0 and sp.x < vp.x and sp.y < vp.y
		if not inside:
			if view != null and d != view and view.alive:
				off.append([view.centre_of_mass().distance_to(d.centre_of_mass()), sp, c])
			continue
		var r := Rect2(sp - Vector2(BAR_W * 0.5, BAR_H * 0.5), Vector2(BAR_W, BAR_H))
		_round(r.grow(2.0), Color(0.02, 0.02, 0.03, 0.85), Color(0, 0, 0, 0), 0, 4, false)
		var f := clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)
		if f > 0.0:
			_round(Rect2(r.position, Vector2(BAR_W * f, BAR_H)), c, Color(0, 0, 0, 0), 0, 3, false)
		var ar := rm.armor_of(d)
		if ar > 0.0:
			var a_r := Rect2(r.position + Vector2(0.0, BAR_H + 3.0), Vector2(BAR_W * clampf(ar / Tuning.SQUAD_ARMOR_MAX, 0.0, 1.0), 3.0))
			canvas.draw_rect(a_r.grow(1.0), Color(0.02, 0.02, 0.03, 0.85))
			canvas.draw_rect(a_r, ARMOR_COLOUR)
		_text(sp + Vector2(0.0, -10.0), rname(d), 20 if d == view else 18, Color.WHITE if d == view else c, HORIZONTAL_ALIGNMENT_CENTER)
		var bx := sp.x - 20.0
		for k in Tuning.SQUAD_BOOSTS:
			if rm.boost_left(d, k) > 0.0:
				_icon(SquadIcons.supply_icon(k), Vector2(bx, sp.y - 40.0), 16.0, Tuning.SQUAD_SUPPLY[k]["colour"])
				bx += 20.0
	off.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in mini(off.size(), ARROWS_MAX):
		_arrow(off[i][1], vp, off[i][2], float(off[i][0]), "")
	# без оружия — стрелка к ближнему ящику с оружием за кадром
	if view == null or not view.alive:
		return
	var g := SquadMatch.gun_of(view)
	if g != null and g.weapon != "":
		return
	var best: RoyaleCrate = null
	var bd := INF
	for c in get_tree().get_nodes_in_group(SquadMatch.SUPPLY_GROUP):
		var rc := c as RoyaleCrate
		if rc == null or not rc.is_weapon() or rc.is_queued_for_deletion():
			continue
		var dd := view.centre_of_mass().distance_to(rc.global_position)
		if dd < bd:
			bd = dd
			best = rc
	if best == null or cam.is_position_behind(best.global_position):
		return
	var cp: Vector2 = to_canvas * cam.unproject_position(best.global_position)
	if cp.x > 0.0 and cp.y > 0.0 and cp.x < vp.x and cp.y < vp.y:
		return
	_arrow(cp, vp, best.colour(), bd, "bullet")


# --- карточки ---

func _draw_card(vp: Vector2, me: Doll) -> void:
	var tc := colour(me)
	var r := Rect2(24.0, vp.y - CARD.y - 22.0, CARD.x, CARD.y)
	_round(r, Color(0.03, 0.035, 0.05, 0.82), tc.lightened(0.2), 0, 12)
	canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), tc.lightened(0.2))
	var cc := r.position + Vector2(76.0, 92.0)
	canvas.draw_circle(cc, 54.0, Color(0.07, 0.08, 0.11))
	canvas.draw_arc(cc, 60.0, 0.0, TAU, 48, tc, 6.0, true)
	var kills := int((rm.tally.get(me.player_index, {}) as Dictionary).get("kills", 0))
	_icon("skull", cc + Vector2(0.0, -10.0), 40.0, tc.lightened(0.45))
	_text(cc + Vector2(0.0, 40.0), str(kills), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	var x0 := r.position.x + 152.0
	var wcol := r.end.x - x0 - 18.0
	var who := rname(me)
	if who != RoyaleMatch.fighter_name(me):
		who += " · " + RoyaleMatch.fighter_name(me)
	var pl := rm.place_of(me)
	if pl > 0:
		who += " · " + tr("МЕСТО %d") % pl
	_text(Vector2(x0, r.position.y + 38.0), who, 25, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, wcol)
	var hp := me.hp if me.alive else 0.0
	var hpr := Rect2(x0 + 30.0, r.position.y + 54.0, wcol - 90.0, 24.0)
	_icon("heart", Vector2(x0 + 11.0, hpr.position.y + 12.0), 22.0, Color(1.0, 0.4, 0.4))
	_bar(hpr, hp / maxf(me.max_hp, 1.0), tc.lightened(0.25) if hp > me.max_hp * 0.3 else Color(1.0, 0.35, 0.3), me.max_hp, 25.0)
	_text(Vector2(hpr.end.x + 10.0, hpr.end.y - 3.0), str(int(ceil(hp))), 26, Color.WHITE)
	var ar := rm.armor_of(me) if me.alive else 0.0
	var arr := Rect2(x0 + 30.0, r.position.y + 90.0, wcol - 90.0, 12.0)
	_icon("shield", Vector2(x0 + 11.0, arr.position.y + 6.0), 18.0, ARMOR_COLOUR)
	_bar(arr, ar / Tuning.SQUAD_ARMOR_MAX, ARMOR_COLOUR, Tuning.SQUAD_ARMOR_MAX, 25.0)
	_text(Vector2(arr.end.x + 10.0, arr.end.y + 2.0), str(int(round(ar))), 20, ARMOR_COLOUR)
	var bx := x0
	var by := r.position.y + 140.0
	for k in Tuning.SQUAD_BOOSTS:
		var left := rm.boost_left(me, k)
		if left <= 0.0:
			continue
		var def: Dictionary = Tuning.SQUAD_SUPPLY[k]
		var col: Color = def["colour"]
		var c := Vector2(bx + 18.0, by)
		canvas.draw_circle(c, 18.0, Color(0, 0, 0, 0.55))
		SquadIcons.ring(canvas, c, 18.0, 3.0, left / float(def["seconds"]), col, Color(0, 0, 0, 0))
		_icon(SquadIcons.supply_icon(k), c, 20.0, col)
		_text(c + Vector2(24.0, 7.0), "%d" % int(ceil(left)), 18, col)
		bx += 78.0


func _weapon_pic_c(r: Rect2, id: String, c: Color, fallback: String) -> void:
	var key := "%s/%s" % [id, c.to_html(false)]
	var tex: Texture2D = _pics.get(key, null)
	if tex == null:
		tex = icons.picture(id, c)
		if tex != null:
			_pics[key] = tex
	if tex != null:
		var ts := tex.get_size()
		var k := minf(r.size.x / ts.x, r.size.y / ts.y)
		var sz := ts * k
		canvas.draw_texture_rect(tex, Rect2(r.get_center() - sz * 0.5, sz), false)
	else:
		_icon(fallback, r.get_center(), minf(r.size.x, r.size.y) * 0.7, Color(1, 1, 1, 0.85))


func _draw_weapon_r(vp: Vector2, me: Doll) -> void:
	var tc := colour(me)
	var r := Rect2(vp.x - 24.0 - CARD.x, vp.y - CARD.y - 22.0, CARD.x, CARD.y)
	_round(r, Color(0.03, 0.035, 0.05, 0.82), tc.lightened(0.2), 0, 12)
	canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), tc.lightened(0.2))
	var g := SquadMatch.gun_of(me)
	var pic := Rect2(r.position + Vector2(14.0, 16.0), Vector2(210.0, 110.0))
	var x1 := r.position.x + 238.0
	var w1 := r.end.x - x1 - 16.0
	if g == null or g.weapon == "":
		_icon("fist", pic.get_center(), 70.0, Color(1, 1, 1, 0.5))
		_text(Vector2(pic.get_center().x, r.end.y - 18.0), tr("РУКИ"), 24, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER, pic.size.x)
		_text(Vector2(x1, r.position.y + 62.0), tr("БЕЗ ОРУЖИЯ"), 34, Color(1.0, 0.85, 0.5), HORIZONTAL_ALIGNMENT_LEFT, w1)
		_text_wrap(Vector2(x1, r.position.y + 100.0), tr("Лети к ящику со стволом. Пока нет — бей рукой и телом"), 19,
			Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, w1, 3)
		return
	var armless := me.alive and not rm.has_weapon_arm(me)
	_weapon_pic_c(pic, g.weapon, tc, "bullet")
	_text(Vector2(pic.get_center().x, r.end.y - 18.0), tr(String(Tuning.SQUAD_WEAPONS[g.weapon]["title"])), 24, Color(1.0, 0.92, 0.7),
		HORIZONTAL_ALIGNMENT_CENTER, pic.size.x)
	var st := g.state()
	var sc: Color = STATE_COLOURS.get(st, Color.WHITE)
	var mw := _text(Vector2(x1, r.position.y + 72.0), str(g.mag), 64, sc if st != "ready" else Color.WHITE)
	_text(Vector2(x1 + mw + 10.0, r.position.y + 72.0), "/ %d" % g.reserve, 28, Color(1, 1, 1, 0.7))
	var n := mini(g.mag_max, 32)
	var pw := minf((w1 - 4.0) / float(maxi(n, 1)), 22.0)
	for k in n:
		var on := k < int(float(g.mag) * float(n) / float(maxi(g.mag_max, 1)) + 0.001)
		canvas.draw_rect(Rect2(x1 + float(k) * pw, r.position.y + 88.0, pw - 3.0, 12.0), sc if on else Color(1, 1, 1, 0.12))
	var line := ""
	var frac := -1.0
	match st:
		"reload":
			line = tr("ПЕРЕЗАРЯДКА")
			frac = maxf(g.reload_progress(), 0.0)
		"empty":
			line = tr("ПАТРОНОВ НЕТ — РУКОПАШНАЯ")
		"charging":
			line = tr("ЗАРЯД %d %%") % int(round(g.charge * 100.0))
			frac = g.charge
		"cooldown":
			line = tr("ПАУЗА")
			frac = g.cooldown_frac()
		_:
			line = tr("ГОТОВ") if not g.charges() else tr("ДЕРЖИ ЛКМ — ЗАРЯД")
	_text(Vector2(x1, r.position.y + 134.0), line, 20, sc, HORIZONTAL_ALIGNMENT_LEFT, w1)
	if frac >= 0.0:
		_bar(Rect2(x1, r.position.y + 144.0, w1, 8.0), frac, sc)
	if armless:
		var ab := Rect2(r.position.x, r.position.y - 46.0, r.size.x, 38.0)
		_round(ab, Color(0.55, 0.06, 0.05, 0.85 + 0.15 * sin(_pulse * 6.0)), Color(0, 0, 0, 0), 0, 8)
		_text(Vector2(ab.get_center().x, ab.position.y + 27.0), tr("ОБЕ РУКИ ОТОРВАНЫ · ЯЩИК ВЕРНЁТ"), 22, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, ab.size.x - 20.0)
