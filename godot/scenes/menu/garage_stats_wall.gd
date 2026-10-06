## Стена экранов в правом углу гаража (06.10, автор: «должно быть место с разными экранами — много, чтобы там показатели куклы
## показывали, как стенд общий крутой»). Ферма Props/ScreenRack (модель Garage_ScreenRack) и мониторы на ней (Garage_Monitor_*,
## у каждого meta "panel" — что показывает); раскладку ставит tools/build_garage_menu.gd.
##
## Все экраны рисуются в ОДИН SubViewport-атлас (2D, свой холст), каждый монитор берёт свой прямоугольник атласа (stats_screen.gdshader,
## uv_rect) — одна текстура и одна перерисовка на всю стену. Перерисовка — SNAP_HZ раз в секунду (живые графики), пока комната видна.
## Числа — те же, что в правой панели мастерской: WorkshopBuild.body_stats() у спящей мастерской гаража (её кукла и висит на стенде);
## мастерской ещё нет — из автосейва игрока (CraftEdit.AUTOSAVE), иначе пресет human. Плюс разбивка по видам деталей и шарнирам из
## чертежа, кампания (CampaignState) и рекорды тренировочного зала (если он уже был).
class_name GarageStatsWall
extends Node

const SNAP_HZ := 12.0
const ATLAS_W := 2048
const PAD := 6
## Пиксели на метр экрана: прямоугольник атласа — по размеру экрана монитора (Garage_Monitor_*), чтобы буквы не тянулись.
const PX_PER_M := 1000.0
const SCREEN_M := {"Wide": Vector2(1.04, 0.44), "Flat": Vector2(0.6, 0.36), "Small": Vector2(0.34, 0.24), "CRT": Vector2(0.35, 0.27)}
const CYAN := Color(0.4, 0.9, 1.0)
const AMBER := Color(1.0, 0.62, 0.22)
const RED := Color(1.0, 0.3, 0.25)
const GREEN := Color(0.45, 1.0, 0.55)
const DIM := Color(0.55, 0.62, 0.68)
const BG := Color(0.018, 0.03, 0.045)
## Вид детали → подпись строки (ключи перевода) — порядок строк на экране «Детали» / «Масса».
const KIND_ROWS := [["core", "Ядро"], ["head", "Голова"], ["limb", "Конечности"], ["hand", "Кисти"], ["foot", "Стопы"],
	["armor", "Броня"], ["deco", "Декор"]]

var garage: Node3D
var vp: SubViewport
var root: Control
var panels := {}                 # имя → Control (_PanelView)
var screens := {}                # имя → MeshInstance3D монитора
var mats := {}                   # имя → ShaderMaterial
var data := {}                   # последняя сводка (пробы читают)
var portraits: DollPortrait
var _portrait_key := ""
var _t := 0.0
var _noise := 0.0


class _PanelView extends Control:
	var kind := ""
	var wall: GarageStatsWall
	var t := 0.0

	func _draw() -> void:
		wall.draw_panel(self, kind, size, t)


func _init(g: Node3D = null) -> void:
	garage = g


func _ready() -> void:
	var rack := garage.get_node_or_null("Props/ScreenRack")
	if rack == null:
		return
	for c in rack.get_children():
		if c.has_meta("panel"):
			screens[String(c.get_meta("panel"))] = c
	portraits = DollPortrait.new()
	portraits.name = "Portraits"
	add_child(portraits)
	portraits.portrait_ready.connect(func(key: String, _tex: Texture2D) -> void:
		if key == _portrait_key and panels.has("main"):
			(panels["main"] as Control).queue_redraw())
	_build_atlas()
	refresh()


## Размеры прямоугольников атласа по экранам и упаковка полками (ширина ATLAS_W).
func _build_atlas() -> void:
	var items: Array = []
	for name in screens:
		var m := screens[name] as Node3D
		var model := String(m.get_meta("model", "Flat"))
		var sz: Vector2 = SCREEN_M.get(model, SCREEN_M["Flat"]) * PX_PER_M
		items.append({"name": name, "size": Vector2i(roundi(sz.x), roundi(sz.y)), "crt": model == "CRT"})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["size"] as Vector2i).y > (b["size"] as Vector2i).y)
	var x := 0
	var y := 0
	var shelf_h := 0
	for it in items:
		var s: Vector2i = it["size"]
		if x + s.x > ATLAS_W:
			x = 0
			y += shelf_h + PAD
			shelf_h = 0
		it["pos"] = Vector2i(x, y)
		x += s.x + PAD
		shelf_h = maxi(shelf_h, s.y)
	var h := y + shelf_h
	vp = SubViewport.new()
	vp.name = "StatsAtlas"
	vp.size = Vector2i(ATLAS_W, h)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	root = Control.new()
	root.size = Vector2(ATLAS_W, h)
	vp.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = root.size
	root.add_child(bg)
	for it in items:
		var p := _PanelView.new()
		p.kind = String(it["name"])
		p.wall = self
		p.position = Vector2(it["pos"])
		p.size = Vector2(it["size"])
		p.clip_contents = true
		root.add_child(p)
		panels[p.kind] = p
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scenes/menu/stats_screen.gdshader")
		mat.set_shader_parameter("atlas", vp.get_texture())
		mat.set_shader_parameter("uv_rect", Vector4(float(it["pos"].x) / ATLAS_W, float(it["pos"].y) / h,
			float(it["size"].x) / ATLAS_W, float(it["size"].y) / h))
		mat.set_shader_parameter("crt", 1.0 if bool(it["crt"]) else 0.0)
		mat.set_shader_parameter("seed", float(mats.size()) * 1.7)
		mats[p.kind] = mat
		_bind(screens[p.kind] as Node, mat)


## Поверхности экрана монитора (материал роли Screen) — на материал стены.
func _bind(node: Node, mat: ShaderMaterial) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var cur := m.get_surface_override_material(i)
			if cur == null:
				cur = m.mesh.surface_get_material(i)
			if cur != null and cur.resource_name.begins_with("Screen"):
				m.set_surface_override_material(i, mat)


func screens_bound() -> int:
	var n := 0
	for name in screens:
		for mi in (screens[name] as Node).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for i in m.mesh.get_surface_count():
				if m.get_surface_override_material(i) == mats.get(name):
					n += 1
	return n


# ---------------------------------------------------------------- данные

## Пересчитать сводку (после мастерской, кампании, загрузки) и помехи на экранах на смене.
func refresh() -> void:
	data = collect()
	_noise = 0.6
	if portraits != null and data.has("bp"):
		_portrait_key = "wall_%s" % String(data["sig"])
		portraits.request(_portrait_key, data["bp"] as BodyBlueprint)
	for p in panels.values():
		(p as Control).queue_redraw()
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _blueprint() -> BodyBlueprint:
	var gw := garage.get("workshop") as GarageWorkshop
	if gw != null and gw.ws != null and gw.ws.blueprint is BodyBlueprint:
		return gw.ws.blueprint as BodyBlueprint
	var bp := CraftEdit.load_saved(CraftEdit.save_path(CraftEdit.AUTOSAVE))
	if bp == null or not CraftEdit.structural_errors(bp).is_empty():
		bp = CraftEdit.load_body_preset("human")
	return bp


## Сводка для экранов: как правая панель мастерской + разбивки. Ключи — для проб (tests/garage_menu_probe.gd).
func collect() -> Dictionary:
	var bp := _blueprint()
	var d := {}
	if bp == null:
		return d
	var gw := garage.get("workshop") as GarageWorkshop
	if gw != null and gw.ws != null and gw.ws.blueprint == bp:
		d = gw.ws.body_stats().duplicate()
		d.erase("errors")
		d.erase("warnings")
	else:
		var wm := bp.weapon_mass() if bp.weapon != null else 0.0
		d = {"title": bp.title, "energy": bp.energy_used(), "budget": bp.energy_cap(), "mass": bp.total_mass(), "hp": bp.parts_hp_total(),
			"links": bp.links.size(), "weapon_mass": wm, "parts": bp.nodes.size(), "accel": bp.thrust_n() / maxf(bp.total_mass() + wm, 0.1),
			"weapon": (bp.weapon as WeaponBlueprint).title.trim_suffix(" *") if bp.weapon != null else ""}
	d["bp"] = bp
	d["sig"] = String(",".join(CraftEdit.signature(bp))).md5_text().substr(0, 10)
	d["thrust"] = bp.thrust_n()
	var kinds := {}
	var kind_mass := {}
	var joints := {}
	for n in bp.nodes:
		var def := CraftEdit.part(String(n.get("part", "")))
		var k := def.kind if def != null else "?"
		kinds[k] = int(kinds.get(k, 0)) + 1
		kind_mass[k] = float(kind_mass.get(k, 0.0)) + bp.node_mass(String(n.get("uid", "")))
		if String(n.get("parent", "")) != "":
			var jt := bp.joint_type_of(String(n.get("uid", "")))
			joints[jt] = int(joints.get(jt, 0)) + 1
	d["kinds"] = kinds
	d["kind_mass"] = kind_mass
	d["joints"] = joints
	var st: CampaignState = garage.call("_campaign_state") if garage.has_method("_campaign_state") else null
	d["campaign"] = {} if st == null else {"wins": st.wins, "losses": st.losses, "trophies": st.trophies.size(), "step": st.step,
		"of": st.ladder().size(), "done": st.finished()}
	var hall: TrainingHall = gw.hall if gw != null else null
	if hall != null and hall.bag != null:
		d["hall"] = {"best_n": hall.bag.best_force_n, "hits": hall.bag.hits,
			"vmax": float((hall.screens["speed"] as Object).get("_data").get("vmax", 0.0)) if hall.screens.has("speed") else 0.0}
	var com := -1.0
	if gw != null and gw.ws != null and gw.ws.stand != null and gw.ws.stand.has_method("centre_of_mass"):
		com = (gw.ws.stand.call("centre_of_mass") as Vector3).y - gw.ws.stand_root.global_position.y
	d["com_h"] = com
	return d


func _process(delta: float) -> void:
	if vp == null:
		return
	_t += delta
	_noise = maxf(0.0, _noise - delta * 2.5)
	for m in mats.values():
		(m as ShaderMaterial).set_shader_parameter("noise_amt", _noise)
	var cam := garage.get("cam") as Camera3D
	var room := garage.get_node_or_null("Props") as Node3D
	if cam == null or not cam.is_current() or (room != null and not room.visible):
		return
	if _t >= 1.0 / SNAP_HZ:
		for p in panels.values():
			(p as _PanelView).t += _t
			if (p as _PanelView).kind in ["pulse", "link", "main", "energy"]:
				(p as Control).queue_redraw()
		_t = 0.0
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE


# ---------------------------------------------------------------- рисование экранов

func _font(kind: String) -> Font:
	return garage.get("f_head" if kind == "head" else ("f_mono" if kind == "mono" else "f_body")) as Font


func _text(c: Control, s: String, pos: Vector2, px: int, col: Color, kind := "body", w := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	c.draw_string(_font(kind), pos, s, align, w, px, col)


func _header(c: Control, title: String, sz: Vector2, accent: Color, tag := "") -> void:
	c.draw_rect(Rect2(Vector2.ZERO, sz), BG)
	c.draw_rect(Rect2(0, 0, sz.x, 44), Color(0.04, 0.07, 0.1))
	c.draw_rect(Rect2(0, 0, 8, 44), accent)
	_text(c, title, Vector2(20, 34), 30, Color(0.92, 0.95, 0.98), "head")
	if tag != "":
		_text(c, tag, Vector2(sz.x - 16, 31), 18, accent, "mono", 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
	for i in int(sz.x / 64.0) + 1:     # сетка фона
		c.draw_line(Vector2(i * 64, 44), Vector2(i * 64, sz.y), Color(1, 1, 1, 0.025))
	for j in int(sz.y / 64.0) + 1:
		c.draw_line(Vector2(0, 44 + j * 64), Vector2(sz.x, 44 + j * 64), Color(1, 1, 1, 0.025))


func _bar(c: Control, r: Rect2, frac: float, col: Color, segs := 0) -> void:
	c.draw_rect(r, Color(1, 1, 1, 0.07))
	if segs <= 0:
		c.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
		return
	var w := r.size.x / segs
	for i in segs:
		var on := (i + 0.5) / segs <= frac
		c.draw_rect(Rect2(r.position + Vector2(i * w + 1, 0), Vector2(w - 2, r.size.y)), col if on else Color(1, 1, 1, 0.06))


func draw_panel(c: Control, kind: String, sz: Vector2, t: float) -> void:
	var d := data
	if d.is_empty():
		c.draw_rect(Rect2(Vector2.ZERO, sz), BG)
		_text(c, tr("НЕТ СИГНАЛА"), Vector2(20, sz.y * 0.5), 34, DIM, "head")
		return
	match kind:
		"main":
			_draw_main(c, sz, t)
		"energy":
			var used := int(d["energy"])
			var cap := maxi(int(d["budget"]), 1)
			var over := used > cap
			_header(c, tr("ЭНЕРГИЯ"), sz, RED if over else CYAN, "ENERGY")
			_text(c, "%d" % used, Vector2(22, 150), 92, RED if over else Color(1, 1, 1), "head")
			_text(c, "/ %d" % cap, Vector2(22 + 30.0 * str(used).length() + 40, 150), 40, DIM, "head")
			_bar(c, Rect2(22, 182, sz.x - 44, 34), float(used) / cap, RED if over else CYAN, 20)
			var free := cap - used
			_text(c, tr("свободно %d") % free if not over else tr("перебор %d — в бой не пустят") % -free, Vector2(22, 256), 24,
				RED if over else DIM, "body")
		"parts":
			_header(c, tr("ДЕТАЛИ"), sz, AMBER, "%d" % int(d["parts"]))
			_kind_rows(c, sz, d["kinds"] as Dictionary, false)
		"mass":
			var total := float(d["mass"]) + float(d.get("weapon_mass", 0.0))
			_header(c, tr("МАССА"), sz, AMBER, tr("%.1f кг") % total)
			_kind_rows(c, sz, d["kind_mass"] as Dictionary, true)
		"joints":
			_header(c, tr("ШАРНИРЫ"), sz, CYAN, tr("связки %d") % int(d["links"]))
			var js: Dictionary = d["joints"]
			var y := 82.0
			var mx := 1
			for k in js:
				mx = maxi(mx, int(js[k]))
			for jt in KitJoint.ORDER:
				if not js.has(jt):
					continue
				_text(c, KitJoint.title_of(jt), Vector2(22, y), 22, Color(0.9, 0.92, 0.95), "body")
				_bar(c, Rect2(210, y - 16, sz.x - 290, 16), float(js[jt]) / mx, CYAN)
				_text(c, str(int(js[jt])), Vector2(sz.x - 22, y), 22, CYAN, "mono", 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
				y += 34.0
				if y > sz.y - 10:
					break
		"hp":
			_header(c, tr("ЗАПАС"), sz, RED, "❤")
			_text(c, "%d" % int(d["hp"]), Vector2(20, 150), 84, Color(1, 0.86, 0.84), "head")
			_text(c, tr("режим: вкл") if PartHp.on else tr("режим: выкл (клавиша «;»)"), Vector2(20, 200), 20, DIM, "body")
			_text(c, tr("сумма ❤ деталей"), Vector2(20, 232), 20, DIM, "body")
		"pulse":
			_header(c, tr("NULL-СВЯЗЬ"), sz, CYAN, "Hz")
			var pts := PackedVector2Array()
			for i in 64:
				var x := 16.0 + (sz.x - 32.0) * i / 63.0
				var ph := i * 0.35 - t * 6.0
				var spike := exp(-pow(fmod(i + t * 18.0, 32.0) - 16.0, 2.0) * 0.08) * 46.0
				pts.append(Vector2(x, sz.y * 0.6 - sin(ph) * 14.0 - spike))
			c.draw_polyline(pts, CYAN, 3.0, true)
			_text(c, tr("фильтр NULL: вкл"), Vector2(18, sz.y - 18), 19, DIM, "mono")
		"link":
			var gh = garage.get("headset")
			var worn: bool = gh != null and bool(gh.get("worn"))
			_header(c, tr("ШЛЕМ"), sz, GREEN if worn else AMBER, "LINK")
			var blink := fmod(t, 1.0) < 0.6
			c.draw_circle(Vector2(44, 120), 16.0, (GREEN if worn else AMBER) * (1.0 if blink else 0.45))
			_text(c, tr("ПОДКЛЮЧЁН") if worn else tr("НА ПОДСТАВКЕ"), Vector2(76, 132), 34, Color(1, 1, 1), "head")
			_text(c, tr("кукла: стенд 1"), Vector2(20, 196), 20, DIM, "body")
			_text(c, tr("наденешь — откроется мастерская"), Vector2(20, 228), 18, DIM, "body")
		"weapon":
			_header(c, tr("ОРУЖИЕ"), sz, AMBER)
			var w := String(d.get("weapon", ""))
			_text(c, w.to_upper() if w != "" else tr("БЕЗ ОРУЖИЯ"), Vector2(20, 130), 40 if w.length() < 14 else 28, Color(1, 1, 1), "head", sz.x - 40)
			if float(d.get("weapon_mass", 0.0)) > 0.0:
				_text(c, tr("%.1f кг") % float(d["weapon_mass"]), Vector2(20, 186), 24, DIM, "mono")
		"thrust":
			_header(c, tr("РАЗГОН"), sz, GREEN)
			_text(c, "×%.2f" % float(d["accel"]), Vector2(20, 140), 72, Color(1, 1, 1), "head")
			_text(c, tr("тяга %d Н") % roundi(float(d["thrust"])), Vector2(20, 196), 22, DIM, "mono")
			if float(d.get("com_h", -1.0)) > 0.0:
				_text(c, tr("центр масс %.2f м") % float(d["com_h"]), Vector2(20, 230), 20, DIM, "mono")
		"league":
			var cp: Dictionary = d["campaign"]
			_header(c, tr("ЛИГА"), sz, AMBER)
			if cp.is_empty():
				_text(c, tr("кампания не начата"), Vector2(20, 130), 26, DIM, "body")
			else:
				_text(c, "%d – %d" % [int(cp["wins"]), int(cp["losses"])], Vector2(20, 150), 76, Color(1, 1, 1), "head")
				_text(c, tr("трофеев: %d") % int(cp["trophies"]), Vector2(20, 210), 24, AMBER, "body")
				_text(c, tr("пройдена") if bool(cp["done"]) else tr("бой %d из %d") % [int(cp["step"]) + 1, int(cp["of"])],
					Vector2(20, 246), 22, DIM, "body")
		"hall":
			var hl: Dictionary = d.get("hall", {})
			_header(c, tr("ЗАЛ"), sz, CYAN)
			if hl.is_empty():
				_text(c, tr("испытаний ещё не было"), Vector2(20, 130), 24, DIM, "body", sz.x - 40)
			else:
				_text(c, tr("удар %.1f кН") % (float(hl["best_n"]) / 1000.0), Vector2(20, 120), 36, Color(1, 1, 1), "head")
				_text(c, tr("скорость %.1f м/с") % float(hl["vmax"]), Vector2(20, 176), 28, CYAN, "head")
				_text(c, tr("ударов по груше: %d") % int(hl["hits"]), Vector2(20, 222), 20, DIM, "body")
		_:
			_header(c, kind.to_upper(), sz, DIM)


func _kind_rows(c: Control, sz: Vector2, vals: Dictionary, is_mass: bool) -> void:
	var mx := 0.001
	for k in vals:
		mx = maxf(mx, float(vals[k]))
	var y := 80.0
	for row in KIND_ROWS:
		var k := String(row[0])
		var v := float(vals.get(k, 0.0))
		if v <= 0.0:
			continue
		_text(c, tr(String(row[1])), Vector2(22, y), 22, Color(0.9, 0.92, 0.95), "body")
		_bar(c, Rect2(200, y - 16, sz.x - 290, 16), v / mx, AMBER)
		_text(c, ("%.1f" % v) if is_mass else str(int(v)), Vector2(sz.x - 22, y), 22, AMBER, "mono", 0.0, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 32.0
		if y > sz.y - 8:
			break


func _draw_main(c: Control, sz: Vector2, t: float) -> void:
	var d := data
	_header(c, tr("БОЕЦ · СТЕНД 1"), sz, AMBER, "BAY 07")
	# портрет сборки (рендер DollPortrait) или силуэт-заглушка
	var pr := Rect2(18, 56, sz.y * 0.62, sz.y - 70)
	c.draw_rect(pr, Color(0.03, 0.06, 0.09))
	var tex: Texture2D = portraits.request(_portrait_key, d["bp"] as BodyBlueprint) if portraits != null and _portrait_key != "" else null
	if tex != null:
		c.draw_texture_rect(tex, pr, false)
	else:
		var cx := pr.get_center().x
		var top := pr.position.y + 30
		c.draw_circle(Vector2(cx, top + 26), 24, Color(0.3, 0.6, 0.7, 0.6))
		c.draw_rect(Rect2(cx - 32, top + 56, 64, 110), Color(0.3, 0.6, 0.7, 0.5))
		c.draw_rect(Rect2(cx - 30, top + 170, 22, 120), Color(0.3, 0.6, 0.7, 0.5))
		c.draw_rect(Rect2(cx + 8, top + 170, 22, 120), Color(0.3, 0.6, 0.7, 0.5))
	var sy := pr.position.y + fmod(t * 60.0, pr.size.y)        # строка сканера
	c.draw_line(Vector2(pr.position.x, sy), Vector2(pr.end.x, sy), Color(0.4, 0.9, 1.0, 0.5), 2.0)
	c.draw_rect(pr, Color(0.4, 0.9, 1.0, 0.4), false, 2.0)
	var x0 := pr.end.x + 30
	var name := String(d.get("title", "")).trim_suffix(" *").to_upper()
	_text(c, name if name != "" else tr("БЕЗ ИМЕНИ"), Vector2(x0, 116), 58 if name.length() <= 14 else 40, Color(1, 0.86, 0.5), "head", sz.x - x0 - 20)
	var cells := [[tr("МАССА"), tr("%.1f кг") % (float(d["mass"]) + float(d.get("weapon_mass", 0.0)))], [tr("ДЕТАЛИ"), str(int(d["parts"]))],
		[tr("ЭНЕРГИЯ"), "%d / %d" % [int(d["energy"]), int(d["budget"])]], [tr("РАЗГОН"), "×%.2f" % float(d["accel"])]]
	var cw := (sz.x - x0 - 20) / 2.0
	for i in cells.size():
		var cx2 := x0 + (i % 2) * cw
		var cy := 170.0 + (i / 2) * 104.0
		c.draw_rect(Rect2(cx2, cy, cw - 14, 92), Color(1, 1, 1, 0.04))
		_text(c, String(cells[i][0]), Vector2(cx2 + 14, cy + 30), 20, DIM, "mono")
		_text(c, String(cells[i][1]), Vector2(cx2 + 14, cy + 78), 42, Color(1, 1, 1), "head")
