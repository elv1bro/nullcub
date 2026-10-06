## Значки HUD «Стычки 3 на 3» (docs/plan-demo/SQUAD.md; автор 06.10: «всё оформить красиво, не как сейчас — просто линии»):
##   • векторные значки — draw(ci, id, центр, размер, цвет) рисует на любом CanvasItem (сердце, щит, патрон, флаг, глаз, пламя, молния,
##     звезда, крест, череп, часы); без текстур — масштабируются и красятся как угодно;
##   • картинки оружия — picture(id, цвет команды): 3D-модель оружия (ствол — SquadGun.build_model, рукопашное — модель из
##     scenes/weapons/weapon_<id>.tscn) в своём мире SubViewport с ортокамерой и светом, один кадр → ImageTexture (кэш по id и цвету).
##     Готова не сразу (через кадр) — сигнал picture_ready; без окна (headless) картинок нет — HUD рисует вместо них значок.
## Узел ставится в HUD (add_child), рендерит по одной картинке за кадр.
class_name SquadIcons
extends Node

signal picture_ready(key: String, tex: Texture2D)

const PIC := Vector2i(320, 160)
static var _cache: Dictionary = {}

var _queue: Array = []        # [[key, id, colour]]
var _busy := false
var _current := ""             # ключ картинки, которая рисуется сейчас (её не заказывать снова)
var _vp: SubViewport = null
var _stage: Node3D = null
var _cam: Camera3D = null


## Картинка оружия id (огнестрел — Tuning.SQUAD_WEAPONS, рукопашное — Tuning.SQUAD_MELEE) с накладками цвета team; null — ещё нет
## (заказана: придёт picture_ready) или рисовать нечем (без окна).
func picture(id: String, team: Color) -> Texture2D:
	var key := "%s/%s" % [id, team.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	if DisplayServer.get_name() == "headless" or key == _current:
		return null
	for q in _queue:
		if String(q[0]) == key:
			return null
	_queue.append([key, id, team])
	if not _busy:
		_busy = true   # сразу: несколько заказов за кадр иначе запускали несколько рендеров на одной сцене — у всех одна картинка
		_render_next.call_deferred()
	return null


func _ensure_stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.size = PIC
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	key.light_color = Color(1.0, 0.94, 0.85)
	key.light_energy = 1.6
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10.0, 150.0, 0.0)
	rim.light_color = Color(0.6, 0.75, 1.0)
	rim.light_energy = 0.8
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.position = Vector3(0.0, 0.0, 4.0)
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)


func _render_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_ensure_stage()
	var q: Array = _queue.pop_front()
	var key := String(q[0])
	_current = key
	for c in _stage.get_children():
		c.queue_free()
	var model := _model_of(String(q[1]), q[2] as Color)
	if model == null:
		_render_next.call_deferred()
		return
	_stage.add_child(model)
	# рамка — по видимым мешам: ортокамера по центру коробки, по длинной стороне с полями
	var box := _aabb(model)
	var c3 := box.get_center()
	_cam.position = Vector3(c3.x, c3.y, c3.z + 4.0)
	var aspect := float(PIC.x) / float(PIC.y)
	_cam.size = maxf(box.size.y, box.size.x / aspect) * 1.18
	# UPDATE_ONCE подряд срабатывал не всегда (картинка прошлого оружия): рисуем, пока ждём два кадра, потом выключаем
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if img != null and not img.is_empty():
		if OS.get_environment("SQUAD_ICON_DUMP") != "":
			img.save_png(OS.get_environment("SQUAD_ICON_DUMP") + "/" + key.replace("/", "_") + ".png")
		var tex := ImageTexture.create_from_image(img)
		_cache[key] = tex
		picture_ready.emit(key, tex)
	_current = ""
	_render_next.call_deferred()


## Модель оружия для картинки: ствол — из простых форм (SquadGun.build_model), рукопашное — узел Model сцены оружия, лёжа вдоль X.
func _model_of(id: String, team: Color) -> Node3D:
	if Tuning.SQUAD_WEAPONS.has(id):
		var g := SquadGun.build_model(id, team)
		g.rotation_degrees = Vector3(0.0, -18.0, 0.0)
		return g
	var path := Weapon.scene_path(id)
	if not ResourceLoader.exists(path):
		return null
	var w := (load(path) as PackedScene).instantiate()
	var m := w.get_node_or_null("Model") as Node3D
	if m == null:
		w.queue_free()
		return null
	w.remove_child(m)
	w.queue_free()
	var holder := Node3D.new()
	holder.add_child(m)
	# лёжа: длинная сторона — по X (рукоять у моделей оружия — вдоль Y или X), лёгкий поворот — объём
	var b := _aabb(holder)
	var z := 90.0 if b.size.y > b.size.x else 0.0
	holder.rotation_degrees = Vector3(0.0, -20.0, z)
	return holder


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := _xf_to(n, m) * m.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	if first:
		return AABB(Vector3(-0.5, -0.25, -0.1), Vector3(1.0, 0.5, 0.2))
	return n.transform * out


static func _xf_to(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


# --- векторные значки ---

## Значок id в точке c размером s (сторона квадрата) цветом col на ci.
static func draw(ci: CanvasItem, id: String, c: Vector2, s: float, col: Color) -> void:
	var h := s * 0.5
	match id:
		"heart":
			ci.draw_circle(c + Vector2(-h * 0.45, -h * 0.25), h * 0.5, col)
			ci.draw_circle(c + Vector2(h * 0.45, -h * 0.25), h * 0.5, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.93, -h * 0.05), c + Vector2(h * 0.93, -h * 0.05),
				c + Vector2(0.0, h * 0.9)]), col)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.8, -h * 0.8), c + Vector2(h * 0.8, -h * 0.8),
				c + Vector2(h * 0.75, h * 0.05), c + Vector2(0.0, h * 0.95), c + Vector2(-h * 0.75, h * 0.05)]), col)
		"bullet":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.3, -h * 0.2), Vector2(h * 0.6, h * 1.0)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.3, -h * 0.2), c + Vector2(h * 0.3, -h * 0.2),
				c + Vector2(0.0, -h * 0.9)]), col)
		"flag":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.7, -h * 0.9), Vector2(h * 0.16, h * 1.8)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.55, -h * 0.9), c + Vector2(h * 0.85, -h * 0.55),
				c + Vector2(-h * 0.55, -h * 0.1)]), col)
		"eye":
			var pts := PackedVector2Array()
			for i in 17:
				var a := PI * float(i) / 16.0
				pts.append(c + Vector2(-cos(a) * h * 0.95, -sin(a) * h * 0.55))
			for i in range(1, 16):
				var a := PI * float(i) / 16.0
				pts.append(c + Vector2(cos(a) * h * 0.95, sin(a) * h * 0.55))
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(c, h * 0.32, Color(0.05, 0.05, 0.08, col.a))
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -h * 0.95), c + Vector2(h * 0.55, -h * 0.1),
				c + Vector2(h * 0.6, h * 0.45), c + Vector2(0.0, h * 0.95), c + Vector2(-h * 0.6, h * 0.45), c + Vector2(-h * 0.3, -h * 0.2),
				c + Vector2(-h * 0.05, h * 0.05)]), col)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.25, -h * 0.95), c + Vector2(-h * 0.55, h * 0.1),
				c + Vector2(-h * 0.02, h * 0.1), c + Vector2(-h * 0.25, h * 0.95), c + Vector2(h * 0.55, -h * 0.15),
				c + Vector2(h * 0.02, -h * 0.15)]), col)
		"star":
			var sp := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + TAU * float(i) / 10.0
				var r := h * (0.95 if i % 2 == 0 else 0.42)
				sp.append(c + Vector2(cos(a), sin(a)) * r)
			ci.draw_colored_polygon(sp, col)
		"cross":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.28, -h * 0.85), Vector2(h * 0.56, h * 1.7)), col)
			ci.draw_rect(Rect2(c + Vector2(-h * 0.85, -h * 0.28), Vector2(h * 1.7, h * 0.56)), col)
		"skull":
			ci.draw_circle(c + Vector2(0.0, -h * 0.15), h * 0.72, col)
			ci.draw_rect(Rect2(c + Vector2(-h * 0.42, h * 0.3), Vector2(h * 0.84, h * 0.55)), col)
			var dark := Color(0.04, 0.04, 0.06, col.a)
			ci.draw_circle(c + Vector2(-h * 0.3, -h * 0.15), h * 0.2, dark)
			ci.draw_circle(c + Vector2(h * 0.3, -h * 0.15), h * 0.2, dark)
		"clock":
			ci.draw_arc(c, h * 0.85, 0.0, TAU, 28, col, maxf(h * 0.18, 1.5), true)
			ci.draw_line(c, c + Vector2(0.0, -h * 0.55), col, maxf(h * 0.16, 1.5))
			ci.draw_line(c, c + Vector2(h * 0.4, 0.0), col, maxf(h * 0.16, 1.5))
		"fist":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.7, -h * 0.5), Vector2(h * 1.4, h * 1.1)), col)
			ci.draw_circle(c + Vector2(-h * 0.7, h * 0.05), h * 0.3, col)
		_:
			ci.draw_circle(c, h * 0.6, col)


## Значок вида ящика или бонуса (Tuning.SQUAD_SUPPLY).
static func supply_icon(kind: String) -> String:
	return {"ammo": "bullet", "health": "cross", "armor": "shield", "zoom": "eye", "rage": "flame", "haste": "bolt"}.get(kind, "star")


## Дуга-кольцо прогресса frac (0..1) от верха по часовой: фон и заполнение.
static func ring(ci: CanvasItem, c: Vector2, r: float, w: float, frac: float, col: Color, bg := Color(0, 0, 0, 0.45)) -> void:
	ci.draw_arc(c, r, 0.0, TAU, 48, bg, w, true)
	if frac > 0.001:
		ci.draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), maxi(int(48.0 * frac), 3), col, w, true)


## Скошенная плашка (параллелограмм) с вертикальным градиентом top → bottom; skew — сдвиг верха вправо (px).
static func plate(ci: CanvasItem, r: Rect2, top: Color, bottom: Color, skew := 0.0) -> void:
	var p := PackedVector2Array([r.position + Vector2(skew, 0.0), r.position + Vector2(r.size.x + skew, 0.0),
		r.end, Vector2(r.position.x, r.end.y)])
	ci.draw_polygon(p, PackedColorArray([top, top, bottom, bottom]))
