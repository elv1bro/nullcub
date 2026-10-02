## Главное меню «Гараж + эфир» (docs/plan-demo/MENU_GARAGE.md, кадр стиля автора docs/refs/menu-garage/G01-garage-keyframe.png).
## Слева тёмный гараж бойца (модели assets/models/garage, сцену собирает tools/build_garage_menu.gd), по телевизору идёт
## эфир NULL Fighting; справа меню. Каждый пункт — место в гараже: при смене фокуса камера за move_time переезжает к своей
## точке (CamSpots/<Spot>, Marker3D, meta "fov"), лампы зоны пункта разгораются, остальные притухают, телевизор
## с помехами переключает канал. Enter: ИСТОРИЯ — нырок в экран, БЫСТРЫЙ БОЙ — к воротам лифта, МАСТЕРСКАЯ — к стенду,
## затем смена сцены; ВЫХОД — свет гаснет, телевизор схлопывается. Трофеи и Настройки пока отвечают репликой N0.
## Ввод: ↑↓ / W S / D-pad, Enter / Space / A, Esc / B — к пункту «Выход», цифры 1–5, мышь (наведение и клик).
## Пробы: dry_run (или аргумент `-- menu_dry_run=1`) — Enter не меняет сцену, только сигнал navigated(путь).
## API для проб: enter_menu(), set_focus(i, instant), activate(), tv_mode, state, focus, spot_transform(name), is_moving().
class_name GarageMenu
extends Node3D

signal navigated(target: String)
signal focus_changed(index: int)

const ITEMS := [
	{"id": "story", "title": "ИСТОРИЯ", "l1": "Продолжить · Местная лига, бой 2 из 5", "l2": "Соперник: ГАЙКА · 3–1 · на кону предплечье",
		"spot": "Story", "zone": "tv", "tv": "opponent", "go": "res://scenes/playground_scrap.tscn", "via": "IntoTV",
		"n0": "Следующий бой — Гайка. Дерётся грязно. Ну, как грязно — смазкой."},
	{"id": "quick", "title": "БЫСТРЫЙ БОЙ", "l1": "Выставочный матч · 1–2 игрока", "l2": "Арена: Руины · 90 с → Sudden Death",
		"spot": "Quick", "zone": "gate", "tv": "quick", "go": "res://scenes/playground.tscn", "via": "IntoGate",
		"n0": "Выставочный — это без очков, но с синяками."},
	{"id": "workshop", "title": "МАСТЕРСКАЯ", "l1": "Сборка бойца · детали, шарниры, краска", "l2": "ENERGY ядра — сколько деталей потянет тело",
		"spot": "Workshop", "zone": "bench", "tv": "build", "go": "res://scenes/workshop/workshop_build.tscn", "via": "IntoStand",
		"n0": "Говорят, в боксе 07 кто-то собирает бойца из табуреток."},
	{"id": "trophies", "title": "ТРОФЕИ", "l1": "Детали, взятые у соперников", "l2": "Следующее место на полке пока пустое",
		"spot": "Trophies", "zone": "shelf", "tv": "replay", "go": "", "via": "",
		"n0": "Повтор! Следите за головой Полена. Нет, выше. Ещё выше."},
	{"id": "settings", "title": "НАСТРОЙКИ", "l1": "Звук · экран · управление · эффекты", "l2": "Громкость, эффекты, экран, субтитры N0",
		"spot": "Settings", "zone": "radio", "tv": "testcard", "go": "", "via": "",
		"n0": "Крути ручку, пока не увидишь все шесть клеток. Я подожду. Я всегда жду."},
	{"id": "exit", "title": "ВЫХОД", "l1": "Выключить свет в боксе", "l2": "", "spot": "Settings", "zone": "", "tv": "live",
		"go": "", "via": "", "n0": "Уже? Ну ладно. Свет выключу сам."},
]
const SOON := {"trophies": "Полку я пока протираю. Скоро здесь будет что показать.",
	"settings": "Настройки в разработке. Пока крути громкость на колонках."}
const LIVE_LINES := ["…и Клёпа улетает в мембрану! Мембрана — один, Клёпа — ноль!", "Гравитация 0.20G — летаем, друзья, летаем!",
	"Зрители голосуют: ПЕРЕВОРОТ ГРАВИТАЦИИ. Держите обед."]
const ACCENT := Color(1.0, 0.55, 0.2)
const SCREEN := Vector2i(768, 576)
const TV_DIR := "res://assets/textures/garage/tv/"

@export var dry_run := false
@export var move_time := 0.75

var state := "title"            # title | menu | settings | trophies | leaving
var focus := 0
var tv_mode := ""
var cam: Camera3D
var spots := {}                 # имя → Transform3D
var spot_fov := {}
var zone_lights := {}           # зона → [Light3D]
var _from := Transform3D()
var _to := Transform3D()
var _fov_from := 50.0
var _fov_to := 50.0
var _t := 1.0
var _dur := 0.75
var _arc := 0.0
var _tw_lights: Tween

var tv_vp: SubViewport
var tv_root: Control
var tv_mat: ShaderMaterial
var _tv_time := 0.0
var _tv_anim := {}

var f_head: Font
var f_body: Font
var f_mono: Font
var ui: Control
var title_box: Control
var menu_box: Control
var item_nodes: Array = []
var sub_who: Label
var sub_text: Label
var sub_panel: PanelContainer
var fade: ColorRect
var press_label: Label
var settings_ui: GarageSettings
var _live_line := 0
var _live_timer := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("menu_dry_run"):
			dry_run = true
	f_head = _font("res://assets/fonts/Oswald.ttf", 650)
	f_body = _font("res://assets/fonts/Rubik.ttf", 450)
	f_mono = _font("res://assets/fonts/JetBrainsMono.ttf", 600)
	cam = get_node("Camera3D") as Camera3D
	for m in get_node("CamSpots").get_children():
		spots[m.name] = (m as Node3D).global_transform
		spot_fov[m.name] = float(m.get_meta("fov", 50.0))
	for l in get_node("Lights").find_children("*", "Light3D", true, false):
		var z := String(l.get_meta("zone", "room"))
		if not zone_lights.has(z):
			zone_lights[z] = []
		zone_lights[z].append(l)
		l.set_meta("base", (l as Light3D).light_energy)
	_setup_tv()
	_build_ui()
	cam.global_transform = spots["Title"]
	cam.fov = spot_fov["Title"]
	_to = cam.global_transform
	_fov_to = cam.fov
	_show_title(true)
	_apply_tv("live")
	_set_zone_mult("", 0.0)
	# вернулись из боя или мастерской (Flow.to_menu): сразу список на том же пункте, из темноты
	var flow := get_node_or_null("/root/Flow")
	if flow != null and bool(flow.returning):
		flow.returning = false
		state = "menu"
		_show_title(false)
		set_focus(int(flow.last_item), true)
		_say("С возвращением в бокс 07! Повтор покажу потом, когда его смонтируют.")
		fade.color.a = 1.0
		create_tween().tween_property(fade, "color:a", 0.0, 0.5)


# ---------------------------------------------------------------- состояние и ввод

func enter_menu() -> void:
	if state != "title":
		return
	state = "menu"
	_show_title(false)
	set_focus(0)


func set_focus(i: int, instant := false) -> void:
	var n := ITEMS.size()
	focus = (i % n + n) % n
	var it: Dictionary = ITEMS[focus]
	_move_to(String(it["spot"]), move_time, 0.06, instant)
	_apply_tv(String(it["tv"]))
	_set_zone_mult(String(it["zone"]), 0.0 if instant else move_time)
	_update_items()
	_say(String(it["n0"]))
	focus_changed.emit(focus)


func activate() -> void:
	if state != "menu":
		return
	var it: Dictionary = ITEMS[focus]
	var id := String(it["id"])
	if id == "exit":
		_exit_sequence()
		return
	if id == "settings":
		_open_settings()
		return
	var go := String(it["go"])
	if go == "":
		_say(String(SOON.get(id, "Скоро.")))
		return
	state = "leaving"
	var tw := create_tween()
	tw.tween_property(ui, "modulate:a", 0.0, 0.35)
	_move_to(String(it["via"]), 1.05, 0.0, false, true)
	if id == "quick":
		_set_zone_mult("gate", 0.9, 2.6)
	var t2 := create_tween()
	t2.tween_interval(0.85)
	t2.tween_property(fade, "color:a", 1.0, 0.3)
	t2.tween_callback(_go.bind(go))


func _open_settings() -> void:
	state = "settings"
	menu_box.visible = false
	settings_ui.open()
	_move_to("SettingsClose", 0.6, 0.03)
	_say("Крути ручку. Громче — ярче шкала. Я всегда так делаю, когда никто не смотрит.")


func _close_settings() -> void:
	state = "menu"
	menu_box.visible = true
	set_focus(focus)


## Громкость из настроек: шкала радио светится ярче (сюжет и интерфейс — одна вещь).
func _on_volume(v: float) -> void:
	for l in zone_lights.get("radio", []):
		if (l as Node).name.begins_with("RadioDial"):
			(l as Light3D).light_energy = 0.1 + 0.8 * v


func is_moving() -> bool:
	return _t < 1.0


func spot_transform(name: String) -> Transform3D:
	return spots.get(name, Transform3D())


func _go(target: String) -> void:
	var flow := get_node_or_null("/root/Flow")
	if flow != null:
		flow.last_item = focus
	navigated.emit(target)
	if not dry_run:
		get_tree().change_scene_to_file(target)


func _exit_sequence() -> void:
	state = "leaving"
	_say("")
	var tw := create_tween()
	tw.tween_property(ui, "modulate:a", 0.0, 0.3)
	var order := ["bench", "shelf", "radio", "room", "gate", "tv"]
	var tl := create_tween()
	for z in order:
		for l in zone_lights.get(z, []):
			tl.parallel().tween_property(l, "light_energy", 0.0, 0.18)
		tl.tween_interval(0.12)
	tl.tween_method(func(v: float) -> void: tv_mat.set_shader_parameter("power", v), 1.0, 0.0, 0.45)
	tl.tween_interval(0.4)
	tl.tween_callback(func() -> void:
		navigated.emit("quit")
		if not dry_run:
			get_tree().quit())


func _unhandled_input(e: InputEvent) -> void:
	if state == "leaving":
		return
	if state == "settings":
		if settings_ui.handle_input(e):
			get_viewport().set_input_as_handled()
		return
	if state == "title":
		var pressed: bool = (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventJoypadButton and e.pressed) \
			or (e is InputEventMouseButton and e.pressed)
		if pressed:
			get_viewport().set_input_as_handled()
			enter_menu()
		return
	if e.is_action_pressed("ui_down") or e.is_action_pressed("p1_down"):
		set_focus(focus + 1)
	elif e.is_action_pressed("ui_up") or e.is_action_pressed("p1_up"):
		set_focus(focus - 1)
	elif e.is_action_pressed("ui_accept"):
		activate()
	elif e.is_action_pressed("ui_cancel"):
		set_focus(ITEMS.size() - 1)
	elif e is InputEventKey and e.pressed and not e.echo and e.physical_keycode >= KEY_1 and e.physical_keycode <= KEY_5:
		set_focus(e.physical_keycode - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- камера и свет

func _move_to(spot: String, dur: float, arc: float, instant := false, ease_in := false) -> void:
	if not spots.has(spot):
		return
	_from = cam.global_transform
	_to = spots[spot]
	_fov_from = cam.fov
	_fov_to = spot_fov[spot]
	_dur = max(dur, 0.01)
	_arc = arc
	_t = 1.0 if instant else 0.0
	set_meta("ease_in", ease_in)
	if instant:
		cam.global_transform = _to
		cam.fov = _fov_to


func _process(delta: float) -> void:
	if _t < 1.0:
		_t = min(1.0, _t + delta / _dur)
		var e := _t * _t * (3.0 - 2.0 * _t)
		if bool(get_meta("ease_in", false)):
			e = _t * _t * _t
		var o := _from.origin.lerp(_to.origin, e)
		o.y += sin(PI * _t) * _arc
		var q := _from.basis.get_rotation_quaternion().slerp(_to.basis.get_rotation_quaternion(), e)
		cam.global_transform = Transform3D(Basis(q), o)
		cam.fov = lerpf(_fov_from, _fov_to, e)
	_tv_process(delta)
	if state == "title":
		_live_timer += delta
		if press_label != null:
			press_label.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.004)
		if _live_timer > 6.0:
			_live_timer = 0.0
			_live_line = (_live_line + 1) % LIVE_LINES.size()
			_say(LIVE_LINES[_live_line])


func _zone_mult(z: String, focus_zone: String) -> float:
	if focus_zone == "":
		return 1.0
	if z == "room":
		return 0.8
	if z == "tv":
		return 1.25 if focus_zone == "tv" else 0.85
	return 1.7 if z == focus_zone else 0.4


## Энергии ламп зон к фокусу focus_zone ("" — все как есть); boost — отдельный множитель для фокусной зоны (вход в ворота).
func _set_zone_mult(focus_zone: String, dur: float, boost := 1.0) -> void:
	if _tw_lights != null and _tw_lights.is_valid():
		_tw_lights.kill()
	_tw_lights = create_tween().set_parallel(true)
	for z in zone_lights:
		var m := _zone_mult(z, focus_zone) * (boost if z == focus_zone else 1.0)
		for l in zone_lights[z]:
			var target := float(l.get_meta("base")) * m
			if dur <= 0.0:
				(l as Light3D).light_energy = target
			else:
				_tw_lights.tween_property(l, "light_energy", target, dur)
	if dur <= 0.0:
		_tw_lights.kill()


# ---------------------------------------------------------------- эфир на телевизоре

func _setup_tv() -> void:
	tv_vp = SubViewport.new()
	tv_vp.size = SCREEN
	tv_vp.disable_3d = true
	tv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(tv_vp)
	tv_root = Control.new()
	tv_root.size = Vector2(SCREEN)
	tv_root.clip_contents = true
	tv_vp.add_child(tv_root)
	tv_mat = ShaderMaterial.new()
	tv_mat.shader = preload("res://scenes/menu/crt_screen.gdshader")
	tv_mat.set_shader_parameter("screen_tex", tv_vp.get_texture())
	var tv := get_node_or_null("Props/TV")
	if tv == null:
		return
	for mi in tv.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var cur := m.mesh.surface_get_material(i)
			if cur != null and cur.resource_name.begins_with("Screen"):
				m.set_surface_override_material(i, tv_mat)


func _apply_tv(mode: String) -> void:
	if mode == tv_mode:
		return
	var first := tv_mode == ""
	tv_mode = mode
	if not first:
		tv_mat.set_shader_parameter("noise_amt", 0.9)
		var tw := create_tween()
		tw.tween_interval(0.08)
		tw.tween_callback(_build_tv.bind(mode))
		tw.tween_method(func(v: float) -> void: tv_mat.set_shader_parameter("noise_amt", v), 0.9, 0.0, 0.14)
	else:
		_build_tv(mode)


func _build_tv(mode: String) -> void:
	for c in tv_root.get_children():
		tv_root.remove_child(c)
		c.queue_free()
	_tv_anim = {}
	match mode:
		"live":
			var a := _tv_img(TV_DIR + "tv_live_a.png")
			var b := _tv_img(TV_DIR + "tv_live_b.png")
			b.modulate.a = 0.0
			_tv_anim["slides"] = [a, b]
			_tv_anim["pics"] = ["tv_live_a.png", "tv_live_d.png", "tv_live_c.png", "tv_live_b.png"]
			_tv_anim["pic"] = 0
			_tv_bar("● LIVE", "NULL FIGHTING · МЕСТНАЯ ЛИГА")
			_tv_score("КЛЁПА", "2 : 1", "ТУМБА", "NULL FIELD 0.20G ↓")
			_tv_ticker("ОТКРЫТ НАБОР НОВИЧКОВ · БОКСЫ 01–12 · ГРАВИТАЦИЮ ВЫБИРАЮТ ЗРИТЕЛИ · ")
			_tv_n0()
		"opponent":
			_tv_grad(Color(0.12, 0.04, 0.07), Color(0.42, 0.1, 0.12))
			_tv_pic(TV_DIR + "tv_opponent.png", Rect2(40, 92, 300, 394))
			_tv_bar("● LIVE", "СЛЕДУЮЩИЙ БОЙ")
			_tv_text("ГАЙКА", Vector2(360, 140), 104, Color(1.0, 0.85, 0.4), f_head)
			_tv_text("3 – 1   ·   МЕСТНАЯ ЛИГА", Vector2(366, 268), 30, Color(1, 1, 1), f_body)
			_tv_text("НА КОНУ:", Vector2(366, 332), 26, Color(0.82, 0.82, 0.82), f_mono)
			_tv_text("ПРЕДПЛЕЧЬЕ", Vector2(366, 362), 46, Color(0.6, 1.0, 0.95), f_head)
			_tv_text("VS  БОКС 07", Vector2(366, 436), 36, Color(1, 1, 1), f_head)
			_tv_ticker("СЕГОДНЯ В 21:00 · ГАЙКА ПРОТИВ НОВИЧКА ИЗ БОКСА 07 · СТАВКИ НА ДЕТАЛЬ ПРИНЯТЫ · ")
		"quick":
			_tv_img(TV_DIR + "tv_live_c.png")
			_tv_bar("ВЫСТАВОЧНЫЙ", "АРЕНА: РУИНЫ   ◀ ▶")
			_tv_score("P1", "VS", "P2", "1–2 ИГРОКА · БОТЫ")
		"build":
			_tv_grad(Color(0.04, 0.1, 0.2), Color(0.1, 0.24, 0.4))
			_tv_grid()
			_tv_pic(TV_DIR + "tv_build.png", Rect2(40, 92, 300, 394))
			_tv_bar("КАРТОЧКА БОЙЦА", "БОКС 07")
			_tv_text("ГРОМИЛА", Vector2(360, 140), 90, Color(1, 1, 1), f_head)
			_tv_text("МАССА      57 КГ\nДЕТАЛЕЙ    14\nENERGY     91 / 100", Vector2(366, 268), 30, Color(0.75, 0.9, 1.0), f_mono)
		"replay":
			_tv_img(TV_DIR + "tv_replay.png")
			_tv_bar("▶ ПОВТОР", "ТЫ vs ПОЛЕНО · KO 0:47")
			_tv_text("ТРОФЕЙ: ГОЛОВА-ЯЩИК", Vector2(30, 500), 34, Color(1.0, 0.85, 0.4), f_head, true)
		"testcard":
			var cols := [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0), Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
			for i in cols.size():
				_tv_rect(Vector2(i * SCREEN.x / 7.0, 0), Vector2(SCREEN.x / 7.0 + 1, SCREEN.y), cols[i])
			_tv_rect(Vector2(0, 380), Vector2(SCREEN.x, 120), Color(0.05, 0.05, 0.05))
			for i in 6:
				_tv_rect(Vector2(84 + i * 100, 400), Vector2(100, 80), Color(i / 5.0, i / 5.0, i / 5.0))
			_tv_text("НАСТРОЙКА ПРИЁМНИКА", Vector2(140, 150), 56, Color(1, 1, 1), f_head, true)
			_tv_text("ЯРКОСТЬ: ВИДНЫ ВСЕ 6 КЛЕТОК?", Vector2(120, 520), 28, Color(1, 1, 1), f_mono)


func _tv_process(delta: float) -> void:
	_tv_time += delta
	if _tv_anim.has("ticker"):
		var t: Label = _tv_anim["ticker"]
		t.position.x -= delta * 70.0
		if t.position.x < -t.size.x * 0.5:
			t.position.x += t.size.x * 0.5
	if _tv_anim.has("dot"):
		(_tv_anim["dot"] as Label).modulate.a = 0.4 + 0.6 * float(fmod(_tv_time, 1.0) < 0.6)
	if _tv_anim.has("slides"):
		var s: Array = _tv_anim["slides"]
		for sl in s:
			(sl as TextureRect).scale = Vector2.ONE * (1.0 + 0.04 * fmod(_tv_time, 5.0) / 5.0)
		var phase := fmod(_tv_time, 5.0)
		if phase > 4.4:
			(s[1] as TextureRect).modulate.a = (phase - 4.4) / 0.6
		elif (s[1] as TextureRect).modulate.a > 0.5:
			# новый кадр стал основным, следующий ждёт за ним
			var k: int = (int(_tv_anim["pic"]) + 1) % (_tv_anim["pics"] as Array).size()
			_tv_anim["pic"] = k
			(s[0] as TextureRect).texture = (s[1] as TextureRect).texture
			(s[1] as TextureRect).modulate.a = 0.0
			(s[1] as TextureRect).texture = load(TV_DIR + String(_tv_anim["pics"][(k + 1) % (_tv_anim["pics"] as Array).size()]))


func _tv_img(path: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.size = Vector2(SCREEN)
	t.pivot_offset = Vector2(SCREEN) * 0.5
	tv_root.add_child(t)
	return t


func _tv_pic(path: String, r: Rect2) -> void:
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = r.position
	t.size = r.size
	tv_root.add_child(t)


func _tv_grad(a: Color, b: Color) -> void:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 1)
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.size = Vector2(SCREEN)
	tv_root.add_child(t)


func _tv_grid() -> void:
	for i in 13:
		_tv_rect(Vector2(i * 64, 0), Vector2(1, SCREEN.y), Color(1, 1, 1, 0.07))
	for i in 10:
		_tv_rect(Vector2(0, i * 64), Vector2(SCREEN.x, 1), Color(1, 1, 1, 0.07))


func _tv_rect(pos: Vector2, size: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.position = pos
	r.size = size
	tv_root.add_child(r)
	return r


func _tv_text(s: String, pos: Vector2, px: int, c: Color, font: Font, outline := false) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	if outline:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 10)
	tv_root.add_child(l)
	return l


func _tv_bar(tag: String, title: String) -> void:
	_tv_rect(Vector2(24, 22), Vector2(190, 48), Color(0.8, 0.1, 0.1))
	var d := _tv_text(tag, Vector2(36, 24), 32, Color(1, 1, 1), f_head)
	if tag.begins_with("●"):
		_tv_anim["dot"] = d
	_tv_rect(Vector2(214, 22), Vector2(SCREEN.x - 238, 48), Color(0.05, 0.05, 0.07, 0.85))
	_tv_text(title, Vector2(230, 26), 30, Color(1, 1, 1), f_head)


func _tv_score(a: String, mid: String, b: String, extra: String) -> void:
	var y := SCREEN.y - 146.0
	_tv_rect(Vector2(24, y), Vector2(SCREEN.x - 48, 58), Color(0.05, 0.05, 0.07, 0.88))
	_tv_rect(Vector2(24, y), Vector2(8, 58), Color(0.18, 0.6, 0.58))
	_tv_rect(Vector2(SCREEN.x - 32, y), Vector2(8, 58), Color(0.85, 0.35, 0.15))
	_tv_text(a, Vector2(48, y + 6), 38, Color(1, 1, 1), f_head)
	_tv_text(mid, Vector2(SCREEN.x * 0.5 - 46, y + 4), 42, Color(1.0, 0.85, 0.4), f_head)
	_tv_text(b, Vector2(SCREEN.x - 210, y + 6), 38, Color(1, 1, 1), f_head)
	_tv_text(extra, Vector2(SCREEN.x * 0.5 - 110, y + 62), 22, Color(0.75, 0.85, 1.0), f_mono)


func _tv_ticker(s: String) -> void:
	_tv_rect(Vector2(0, SCREEN.y - 48), Vector2(SCREEN.x, 48), Color(0.95, 0.75, 0.2))
	var l := _tv_text(s + s + s, Vector2(0, SCREEN.y - 44), 27, Color(0.08, 0.06, 0.04), f_head)
	_tv_anim["ticker"] = l


## Заглушка N0 в углу эфира — дизайна N0 ещё нет (MENU_GARAGE.md §9).
func _tv_n0() -> void:
	var p := Vector2(SCREEN.x - 150, 96)
	for spec in [[p, Vector2(120, 120), Color(0.9, 0.85, 0.72), Color(0.3, 0.25, 0.2), 60, 5],
			[p + Vector2(34, 34), Vector2(52, 52), Color(0.1, 0.15, 0.25), Color(0.4, 0.9, 1.0), 26, 6]]:
		var pn := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = spec[2]
		sb.border_color = spec[3]
		sb.set_corner_radius_all(spec[4])
		sb.set_border_width_all(spec[5])
		pn.add_theme_stylebox_override("panel", sb)
		pn.position = spec[0]
		pn.size = spec[1]
		tv_root.add_child(pn)
	_tv_text("N0", p + Vector2(40, 124), 30, Color(1, 1, 1), f_mono, true)


# ---------------------------------------------------------------- меню справа

func _font(path: String, weight: int) -> Font:
	var base: Font = load(path)
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


func _label(parent: Control, s: String, pos: Vector2, px: int, c: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _rect(parent: Control, pos: Vector2, size: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _build_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 10
	add_child(cl)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(ui)
	var g := Gradient.new()
	g.set_color(0, Color(0.01, 0.01, 0.02, 0.0))
	g.add_point(0.35, Color(0.01, 0.01, 0.02, 0.72))
	g.set_color(g.get_point_count() - 1, Color(0.01, 0.01, 0.02, 0.92))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.position = Vector2(1920 * 0.53, 0)
	shade.size = Vector2(1920 * 0.47, 1080)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var x0 := 1920 * 0.655
	_label(ui, "NULL FIGHTING  ·  BAY 07", Vector2(x0, 80), 18, Color(1.0, 0.7, 0.35, 0.9), f_mono)
	_label(ui, "RAGDOLL", Vector2(x0 - 4, 104), 82, Color(1, 1, 1), f_head)
	_label(ui, "MASTER", Vector2(x0 - 4, 184), 82, ACCENT, f_head)
	title_box = Control.new()
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(title_box)
	_label(title_box, "build · fly · smash", Vector2(x0, 290), 28, Color(0.86, 0.86, 0.86), f_body)
	_rect(title_box, Vector2(x0, 400), Vector2(470, 2), Color(1, 1, 1, 0.15))
	press_label = _label(title_box, "НАЖМИ ЛЮБУЮ КНОПКУ", Vector2(x0, 424), 42, Color(1, 1, 1), f_head)
	_label(title_box, "клавиатура · геймпад · мышь", Vector2(x0, 480), 21, Color(0.7, 0.7, 0.7), f_body)
	_label(title_box, "МЕСТНАЯ ЛИГА  ·  NULL FIELD 0.20G  ·  demo", Vector2(x0, 1080 - 76), 16, Color(0.6, 0.6, 0.65), f_mono)
	menu_box = Control.new()
	menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu_box)
	_rect(menu_box, Vector2(x0, 292), Vector2(500, 2), Color(1, 1, 1, 0.14))
	for i in ITEMS.size():
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = ITEMS[i]["title"]
		b.add_theme_font_override("font", f_head)
		b.mouse_entered.connect(func() -> void:
			if state == "menu" and focus != i:
				set_focus(i))
		b.pressed.connect(func() -> void:
			if state == "menu":
				if focus != i:
					set_focus(i)
				activate())
		menu_box.add_child(b)
		var d1 := _label(menu_box, ITEMS[i]["l1"], Vector2.ZERO, 22, Color(0.95, 0.88, 0.78), f_body)
		var d2 := _label(menu_box, ITEMS[i]["l2"], Vector2.ZERO, 19, Color(0.68, 0.68, 0.7), f_body)
		var bg := _rect(menu_box, Vector2.ZERO, Vector2(560, 150), Color(1.0, 0.55, 0.2, 0.13))
		var bar := _rect(menu_box, Vector2.ZERO, Vector2(6, 150), ACCENT)
		var en := _label(menu_box, "ENTER ▸", Vector2.ZERO, 20, ACCENT, f_mono)
		menu_box.move_child(bg, 1)
		menu_box.move_child(bar, 2)
		item_nodes.append({"btn": b, "d1": d1, "d2": d2, "bg": bg, "bar": bar, "en": en})
	settings_ui = GarageSettings.new()
	ui.add_child(settings_ui)
	settings_ui.setup(f_head, f_body, f_mono)
	settings_ui.closed.connect(_close_settings)
	settings_ui.volume_changed.connect(_on_volume)
	_rect(menu_box, Vector2(x0, 1080 - 90), Vector2(500, 1), Color(1, 1, 1, 0.12))
	_label(menu_box, "↑↓  ВЫБОР     ENTER  ВОЙТИ     ESC  ВЫХОД", Vector2(x0, 1080 - 76), 17, Color(0.65, 0.65, 0.7), f_mono)
	# субтитр эфира
	sub_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.set_content_margin_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.set_corner_radius_all(4)
	sub_panel.add_theme_stylebox_override("panel", sb)
	sub_panel.position = Vector2(56, 1080 - 118)
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(sub_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	sub_panel.add_child(hb)
	sub_who = Label.new()
	sub_who.text = "N0"
	sub_who.add_theme_font_override("font", f_mono)
	sub_who.add_theme_font_size_override("font_size", 24)
	sub_who.add_theme_color_override("font_color", ACCENT)
	hb.add_child(sub_who)
	sub_text = Label.new()
	sub_text.add_theme_font_override("font", f_body)
	sub_text.add_theme_font_size_override("font_size", 25)
	sub_text.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	hb.add_child(sub_text)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fade)
	_say(LIVE_LINES[0])


func _show_title(on: bool) -> void:
	title_box.visible = on
	menu_box.visible = not on


func _update_items() -> void:
	var x0 := 1920 * 0.655
	var y := 318.0
	for i in item_nodes.size():
		var n: Dictionary = item_nodes[i]
		var b: Button = n["btn"]
		var on := i == focus
		var is_exit := i == ITEMS.size() - 1
		if is_exit:
			y = 1080 - 150.0
		b.add_theme_font_size_override("font_size", 56 if on else (26 if is_exit else 36))
		var col := Color(1, 1, 1) if on else (Color(0.62, 0.62, 0.62, 0.85) if is_exit else Color(0.82, 0.8, 0.76, 0.82))
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(k, col if k == "font_color" else Color(1, 1, 1))
		b.position = Vector2(x0 - 6, y - 6)
		b.size = Vector2(540, 72 if on else 50)
		var h := 160.0 if (on and not is_exit) else (66.0 if on else 0.0)
		(n["bg"] as ColorRect).visible = on
		(n["bar"] as ColorRect).visible = on
		(n["bg"] as ColorRect).position = Vector2(x0 - 26, y - 10)
		(n["bg"] as ColorRect).size = Vector2(580, h)
		(n["bar"] as ColorRect).position = Vector2(x0 - 26, y - 10)
		(n["bar"] as ColorRect).size = Vector2(6, h)
		(n["en"] as Label).visible = on
		(n["en"] as Label).position = Vector2(x0 + 440, y + 20)
		for k in ["d1", "d2"]:
			(n[k] as Label).visible = on and not is_exit
		(n["d1"] as Label).position = Vector2(x0 + 2, y + 70)
		(n["d2"] as Label).position = Vector2(x0 + 2, y + 104)
		y += 172.0 if on else 62.0


func _say(s: String) -> void:
	var flow := get_node_or_null("/root/Flow")
	if flow != null and not bool(flow.get_setting("subtitles")):
		s = ""
	sub_panel.visible = s != ""
	sub_text.text = s
	sub_panel.reset_size()
