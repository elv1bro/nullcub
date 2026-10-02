## Лоадер игры — экран «подключение» поверх всего (autoload «Loading»), в стиле эфира телевизора гаража (docs/plan-demo/MENU_GARAGE.md,
## «Лоадер»). Все долгие загрузки идут под ним: смена сцены (change_scene — фоновая загрузка с полосой прогресса), постановка
## мастерской, купола боя, тренировочного зала. Идея в трёх вызовах:
##   Loading.begin("ЗАГОЛОВОК", "подпись")  — показать сразу (кадр успевает нарисоваться до тяжёлой работы: await Loading.present());
##   Loading.set_progress(0..1)              — полоса едет плавно;
##   Loading.finish()                        — спрятать (не раньше MIN_SHOW_S, чтобы не мигало).
## Удержание: hold("ключ", …) / release("ключ") — экран не уходит, пока есть хоть одно удержание (гараж держит его, пока в фоне
## ставится мастерская). change_scene(path) — фоновая загрузка (ResourceLoader.load_threaded_*: полоса живая, пока грузится),
## смена сцены и спрятать после первых кадров новой сцены. load_async(path) — то же без смены сцены, возвращает PackedScene.
## Главная сцена проекта — scenes/boot.tscn: лоадер встаёт первым, гараж грузится под ним.
## Пробы (dry_run гаража) удержаний не берут и лоадер не показывают.
extends Node

const MIN_SHOW_S := 0.45
const FADE_S := 0.28
const LAYER := 100
const OVERLAY := preload("res://scenes/menu/tv_overlay.gdshader")
const TIPS := [
	"Shift — ускорение. Держи: тратит Заряд, а удары его копят.",
	"Space + A/D — раскрутка: тело закручивается, а удар получается тяжёлым.",
	"ПКМ в мастерской — открутить деталь; ЛКМ — взять и поставить.",
	"Чем дальше деталь от ядра, тем дороже она по энергии.",
	"Победа в лиге — случайная деталь соперника на полку мастерской.",
	"За воротами мастерской есть зал: манекен, груша и экраны с замером удара.",
	"Груша считает силу удара, экран у входа — твою скорость.",
	"N0 вне зоны брызг. N0 всегда вне зоны брызг.",
]

var showing := false
var progress := 0.0                     # показанный прогресс (догоняет цель)
var _target := 0.0
var _holds := {}                        # ключ → true
var _t_shown := 0.0
var _hiding := false
var _layer: CanvasLayer
var _root: Control
var _title: Label
var _sub: Label
var _tip: Label
var _fill: Panel
var _pct: Label
var _dots: Label
var _ticker: Label
var _tw: Tween
var _time := 0.0
var _tip_i := 0
var _tip_tick := 0
var _f_head: Font
var _f_body: Font
var _f_mono: Font
var _mat: ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_f_head = Flow.make_font("res://assets/fonts/Oswald.ttf", 650)
	_f_body = Flow.make_font("res://assets/fonts/Rubik.ttf", 450)
	_f_mono = Flow.make_font("res://assets/fonts/JetBrainsMono.ttf", 600)
	_build()
	_layer.visible = false


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "LoadingLayer"
	_layer.layer = LAYER
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # пока лоадер на экране, клики не проходят в игру
	_layer.add_child(_root)
	var g := Gradient.new()
	g.set_color(0, Color(0.1, 0.03, 0.06))
	g.set_color(1, Color(0.3, 0.07, 0.12))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 1)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var wm := _label("NULL", Vector2(1920 - 780, 150), 520, Color(1, 1, 1, 0.04), _f_head)
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# красная плашка и строка заголовка
	_rect(Vector2(160, 330), Vector2(250, 66), Color(0.8, 0.1, 0.1))
	_dots = _label("● ЭФИР", Vector2(180, 332), 44, Color.WHITE, _f_head)
	_rect(Vector2(410, 330), Vector2(1350, 66), Color(0.05, 0.05, 0.07, 0.9))
	_title = _label("ЗАГРУЗКА", Vector2(436, 334), 44, Color.WHITE, _f_head)
	_sub = _label("", Vector2(164, 420), 30, Color(1.0, 0.9, 0.55), _f_mono)
	# полоса прогресса: рамка + заливка
	var frame := Panel.new()
	frame.position = Vector2(160, 520)
	frame.size = Vector2(1600, 54)
	var fs := BcStyle.new()
	fs.bg = Color(0.04, 0.04, 0.06, 0.92)
	fs.skew = 0.0
	fs.edge_color = Color(0.8, 0.1, 0.1)
	fs.edge_w = 8.0
	frame.add_theme_stylebox_override("panel", fs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)
	_fill = Panel.new()
	_fill.position = Vector2(176, 530)
	_fill.size = Vector2(0, 34)
	var ps := BcStyle.new()
	ps.bg = Color(0.95, 0.75, 0.2)
	ps.skew = 0.5
	ps.shadow_alpha = 0.0
	_fill.add_theme_stylebox_override("panel", ps)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fill)
	_pct = _label("0 %", Vector2(1640, 586), 28, Color(0.75, 0.85, 1.0), _f_mono)
	_tip = _label("", Vector2(164, 640), 30, Color(0.92, 0.92, 0.95), _f_body)
	_tip.size = Vector2(1500, 90)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# бегущая строка внизу
	_rect(Vector2(0, 1008), Vector2(1920, 72), Color(0.95, 0.75, 0.2))
	var clip := Control.new()
	clip.position = Vector2(0, 1008)
	clip.size = Vector2(1920, 72)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(clip)
	var one := "NULL FIGHTING · БОКС 07 · НЕ ВЫКЛЮЧАЙТЕ ТЕЛЕВИЗОР · СИГНАЛ ПОДХОДИТ      ●      "
	_ticker = Label.new()
	_ticker.text = one + one + one + one
	_ticker.add_theme_font_override("font", _f_head)
	_ticker.add_theme_font_size_override("font_size", 40)
	_ticker.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
	_ticker.position = Vector2(0, 8)
	clip.add_child(_ticker)
	# кинескоп поверх
	var ov := ColorRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = OVERLAY
	_mat.set_shader_parameter("strength", 0.9)
	ov.material = _mat
	_root.add_child(ov)


func _label(s: String, pos: Vector2, px: int, c: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = s
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func _rect(pos: Vector2, size: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


# ---------------------------------------------------------------- показ

## Показать лоадер. Прогресс — с нуля. После вызова подожди present(), если дальше идёт тяжёлая работа в главном потоке.
func begin(title := "ЗАГРУЗКА", sub := "") -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_hiding = false
	progress = 0.0 if not showing else progress
	_target = 0.0 if not showing else _target
	if not showing:
		showing = true
		_t_shown = Time.get_ticks_msec() / 1000.0
		_tip_i = randi() % TIPS.size()
		_layer.visible = true
		_root.modulate.a = 1.0
	_title.text = title
	_sub.text = sub
	_tip.text = "СОВЕТ · " + String(TIPS[_tip_i])
	_apply_progress()
	set_process(true)


## Подписать / сменить подпись, не трогая прогресс.
func describe(title: String, sub := "") -> void:
	if _title != null:
		_title.text = title
		_sub.text = sub


func set_progress(p: float) -> void:
	_target = clampf(p, 0.0, 1.0)


## Два кадра: лоадер точно нарисован, дальше можно блокировать главный поток.
func present() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func hold(key: String, title := "", sub := "") -> void:
	_holds[key] = true
	if not showing or title != "":
		begin(title if title != "" else "ЗАГРУЗКА", sub)


func release(key: String) -> void:
	_holds.erase(key)
	_try_finish()


## Спрятать (если нет удержаний): полоса доезжает до конца, не раньше MIN_SHOW_S от показа.
func finish() -> void:
	_target = 1.0
	_try_finish()


func _try_finish() -> void:
	if not showing or _hiding or not _holds.is_empty():
		return
	_hiding = true
	_finish_async()


func _finish_async() -> void:
	_target = 1.0
	var t0 := Time.get_ticks_msec() / 1000.0
	while (progress < 0.995 or Time.get_ticks_msec() / 1000.0 - _t_shown < MIN_SHOW_S) and showing and _holds.is_empty():
		await get_tree().process_frame
		if Time.get_ticks_msec() / 1000.0 - t0 > 3.0:
			break
	if not _holds.is_empty() or not showing:
		_hiding = false
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_root, "modulate:a", 0.0, FADE_S)
	_tw.tween_callback(func() -> void:
		showing = false
		_hiding = false
		_layer.visible = false
		set_process(false))


func _process(delta: float) -> void:
	_time += delta
	progress = lerpf(progress, _target, 1.0 - exp(-delta * 9.0))
	if _target - progress < 0.004:
		progress = _target
	_apply_progress()
	_dots.modulate.a = 0.6 + 0.4 * sin(_time * 5.0)
	_ticker.position.x = -fposmod(_time * 150.0, maxf(_ticker.get_minimum_size().x * 0.25, 200.0))
	var tip_now := int(_time / 4.0)
	if tip_now != _tip_tick:
		_tip_tick = tip_now
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = "СОВЕТ · " + String(TIPS[_tip_i])


func _apply_progress() -> void:
	if _fill == null:
		return
	_fill.size.x = maxf(1600.0 - 32.0, 1.0) * progress
	_pct.text = "%d %%" % int(round(progress * 100.0))


# ---------------------------------------------------------------- загрузки

## Фоновая загрузка ресурса под лоадером (полоса живая, главный поток свободен). null — не удалось.
func load_async(path: String, title := "ЗАГРУЗКА", sub := "") -> Resource:
	begin(title, sub)
	if ResourceLoader.load_threaded_request(path, "", true) != OK:
		return load(path)
	var prog := []
	while true:
		var st := ResourceLoader.load_threaded_get_status(path, prog)
		if not prog.is_empty():
			set_progress(float(prog[0]) * 0.9)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			push_error("Loading: не загрузилось %s" % path)
			return null
		await get_tree().process_frame
	set_progress(0.95)
	return ResourceLoader.load_threaded_get(path)


## Сменить сцену под лоадером; лоадер уходит после первых кадров новой сцены (если она не взяла hold()).
func change_scene(path: String, title := "ЗАГРУЗКА", sub := "") -> void:
	var ps := await load_async(path, title, sub) as PackedScene
	if ps == null:
		finish()
		return
	await present()
	get_tree().paused = false
	get_tree().change_scene_to_packed(ps)
	for i in 4:
		await get_tree().process_frame
	finish()
