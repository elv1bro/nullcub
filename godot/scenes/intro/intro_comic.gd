## Заставка-комикс перед игрой (docs/plan-demo/INTRO_COMIC.md): страница из 13 панелей (ComicPanel), в каждой — кадр
## 3D-площадки IntroStage (одна SubViewport на всё: живая только текущая панель, прошлые застыли картинками).
## Камера страницы ведёт взгляд: наезд на панель → панель проявляется чернилами → кадр играет, надписи появляются →
## панель застывает → следующая. После каждой строки — общий план строки, в финале вся страница и логотип.
## Управление: пробел / Enter / клик / A — дальше (досмотреть панель сразу), удерживать или Esc — пропустить всё.
## Аргументы (после --): intro_capture=<папка> — кадры страницы в PNG + отчёт intro_report.json и выход без смены сцены;
## intro_speed=<k> — ускорение времени (для тестов); intro_skip=1 — сразу в игру.
## Узлы собирает tools/build_intro_comic.gd (only=page); здесь поведение.
class_name IntroComic
extends Node2D

const STAGE_SCENE := "res://scenes/intro/intro_stage.tscn"
## «Холодное открытие»: табло поля NULL на чёрном, пока грузится площадка (арена «Свалка» грузится долго).
const COLD_LINES := [
	"NULL FIELD  ::  ARENA CONTROLLER",
	"> FIELD STATUS ................ STABLE",
	"> GRAVITY ..................... 0.20G",
	"> MEMBRANE .................... 98%",
]
const COLD_DONE := "> FIGHTER DETECTED.  GATE 0."
const SFX := "res://assets/audio/intro/%s.wav"
const SEEN_FLAG := "user://intro_seen"
const AMB_DB := -13.0

@export var next_scene := "res://scenes/playground_scrap.tscn"
## true — показывать только до первого полного просмотра (флаг user://intro_seen); аргумент intro=1 — показать всё равно.
@export var play_once := false
@export var page_size := Vector2(3840.0, 2160.0)
## Поля вокруг панели при наезде (доля размера панели).
@export var focus_margin := 0.07
@export var move_s := 0.7
@export var first_move_s := 1.4
@export var row_view_s := 1.3
@export var max_render_px := 1920
@export var hold_to_skip_s := 0.8

@onready var cam: Camera2D = $Camera
@onready var vp: SubViewport = $StageViewport
@onready var page: Node2D = $Page
@onready var title: Node2D = $Title
@onready var fade: ColorRect = $Hud/Fade
@onready var skip_hint: Control = $Hud/Skip
@onready var skip_bar: ProgressBar = $Hud/Skip/Bar
@onready var cold: Label = $Hud/ColdOpen

var stage: IntroStage
var panels: Array[ComicPanel] = []
var speed := 1.0
var capture_dir := ""
var report := {"ok": true, "panels": [], "captures": [], "errors": []}
var _hold := 0.0
var _advance := false
var _skipping := false
var _shake := 0.0
var _shake_t := 0.0
var _cam_base := Vector2.ZERO
var _started_ms := 0
var _pool: Array[AudioStreamPlayer] = []
var _amb: AudioStreamPlayer
var _streams: Dictionary = {}


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"intro_capture":
					capture_dir = p[1]
				"intro_speed":
					speed = maxf(float(p[1]), 0.1)
				"intro_skip":
					if p[1] == "1":
						_go_to_game.call_deferred()
						return
				"intro":
					if p[1] == "1":
						play_once = false
	if play_once and capture_dir == "" and FileAccess.file_exists(SEEN_FLAG):
		_go_to_game.call_deferred()
		return
	for c in page.get_children():
		if c is ComicPanel:
			panels.append(c)
			(c as ComicPanel).set_reveal(0.0)
	title.visible = false
	_setup_audio()
	fade.color.a = 1.0
	skip_hint.modulate.a = 0.0
	ResourceLoader.load_threaded_request(STAGE_SCENE, "", true)   # под-потоки: сотни glb «Свалки» грузятся параллельно
	cold.text = ""
	_frame_rect(Rect2(Vector2.ZERO, page_size), 1.0)
	_run()


func _process(delta: float) -> void:
	# удержание = пропустить всё
	var held := Input.is_action_pressed("ui_accept") or Input.is_action_pressed("ui_select") \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_hold = _hold + delta if held else 0.0
	if skip_bar:
		skip_bar.value = clampf(_hold / hold_to_skip_s, 0.0, 1.0) * 100.0
	if (_hold >= hold_to_skip_s or Input.is_action_just_pressed("ui_cancel")) and not _skipping and capture_dir == "":
		_skipping = true
		_skip_all()
	# тряска страницы на ударах
	if _shake > 0.0:
		_shake_t += delta
		var k := _shake * exp(-_shake_t * 9.0)
		cam.offset = Vector2(sin(_shake_t * 83.0), cos(_shake_t * 71.0)) * k
		if k < 0.3:
			_shake = 0.0
			cam.offset = Vector2.ZERO


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept") or (e is InputEventMouseButton and (e as InputEventMouseButton).pressed):
		_advance = true


# ------------------------------------------------------------------------------------------------
# сценарий
# ------------------------------------------------------------------------------------------------
func _run() -> void:
	await _cold_open()
	if _skipping:
		return
	var ps := ResourceLoader.load_threaded_get(STAGE_SCENE) as PackedScene
	report["stage_loaded_s"] = _elapsed()
	# игра грузится в фоне, пока идёт комикс (те же ассеты «Свалки» уже в кэше)
	if next_scene != "" and capture_dir == "":
		ResourceLoader.load_threaded_request(next_scene)
	if ps == null:
		_fail("stage load failed")
		_go_to_game()
		return
	stage = ps.instantiate()
	vp.add_child(stage)
	await get_tree().process_frame
	var tw := create_tween()
	tw.tween_property(cold, "modulate:a", 0.0, 0.4)
	_fade_amb(AMB_DB, 1.5)
	await _tween_fade(0.0, 0.8)
	_tween_skip_hint(1.0)
	for i in panels.size():
		if _skipping:
			return
		await _play(i)
		var last_in_row := i == panels.size() - 1 or panels[i + 1].row != panels[i].row
		if last_in_row and i < panels.size() - 1:
			await _row_view(panels[i].row)
		await _capture("page_p%02d" % (i + 1))
	if _skipping:
		return
	await _finale()


func _play(i: int) -> void:
	var p := panels[i]
	stage.set_shot(p.shot - 1)
	var b := p.bbox()
	var focus := b.grow_individual(b.size.x * focus_margin, b.size.y * focus_margin, b.size.x * focus_margin, b.size.y * focus_margin)
	var z_to := _zoom_for(focus)
	# размер рендера = размер панели на экране в пикселях окна
	var win := Vector2(get_window().size)
	var base := get_viewport_rect().size
	var px := b.size * z_to * (win.x / base.x)
	if px.x > max_render_px:
		px *= max_render_px / px.x
	vp.size = Vector2i(maxi(int(px.x), 64), maxi(int(px.y), 64))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.evaluate(0.0)
	p.set_live(vp.get_texture(), Vector2(vp.size))
	p.update_letters(-1.0, stage)
	var pos_from := cam.position
	var z_from := cam.zoom.x
	var move := (first_move_s if i == 0 else move_s)
	var reveal_at := move * 0.35
	var reveal_s := 0.45
	var dur := stage.shot.duration
	var total := reveal_at + dur + p.hold
	var e := 0.0
	var shot_t := 0.0
	var flashed := false
	var impacted := false
	var snd_prev := -1.0
	_advance = false
	_sfx("whoosh", -9.0, randf_range(0.92, 1.08))
	var rec := {"panel": i + 1, "shot": p.shot, "render": [vp.size.x, vp.size.y], "t0": _elapsed()}
	while e < total:
		var dt := get_process_delta_time() * speed
		e += dt
		if _skipping:
			return
		# камера: наезд, потом медленный «дыхательный» наезд на 3 %
		if e < move:
			var k := _ease_io(e / move)
			cam.position = pos_from.lerp(focus.get_center(), k)
			cam.zoom = Vector2.ONE * lerpf(z_from, z_to, k)
		else:
			var k2 := clampf((e - move) / maxf(total - move, 0.01), 0.0, 1.0)
			cam.position = focus.get_center()
			cam.zoom = Vector2.ONE * z_to * (1.0 + 0.03 * k2)
		p.set_reveal((e - reveal_at) / reveal_s)
		if e >= reveal_at:
			shot_t = e - reveal_at
			if _advance and shot_t < dur:
				# досмотреть панель: прыжок в конец кадра (надписи — все сразу, звуки пропускаются)
				_advance = false
				shot_t = dur
				snd_prev = dur
				e = reveal_at + dur + minf(p.hold, 0.25)
				p.set_reveal(1.0)
			stage.evaluate(minf(shot_t, dur))
			for L in p.update_letters(shot_t, stage):
				if (L as ComicLetter).kind == "caption" and snd_prev < dur:
					_caption_sound(L)
			_panel_sounds(p, snd_prev, shot_t)
			snd_prev = shot_t
			if p.flash_at >= 0.0:
				p.set_flash(clampf(1.0 - (shot_t - p.flash_at) / 0.18, 0.0, 1.0) if shot_t >= p.flash_at else 0.0)
				if shot_t >= p.flash_at and not flashed:
					flashed = true
			if p.impact_at >= 0.0 and shot_t >= p.impact_at and not impacted:
				impacted = true
				_kick(p.impact_strength)
		await get_tree().process_frame
	p.set_reveal(1.0)
	p.set_flash(0.0)
	stage.evaluate(dur)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	p.freeze()
	p.update_letters(dur + p.hold + 10.0, null)
	rec["t1"] = _elapsed()
	report["panels"].append(rec)


func _row_view(row: int) -> void:
	var r := Rect2()
	var first := true
	for p in panels:
		if p.row == row:
			r = p.bbox() if first else r.merge(p.bbox())
			first = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sfx("whoosh_big", -12.0)
	await _move_to(r.grow(40.0), row_view_s * 0.55)
	await _wait(row_view_s * 0.45)


## Печатает табло поля, пока площадка грузится: строки по буквам, потом точки и мигающий курсор до конца загрузки.
func _cold_open() -> void:
	var shown := ""
	_amb.volume_db = -34.0
	_amb.play()
	_fade_amb(-22.0, 2.5)
	for ln in COLD_LINES:
		var typing := _sfx("type", -14.0, 1.5)
		for ch in ln:
			shown += ch
			cold.text = shown + "_"
			await _wait(0.022)
			if _skipping:
				return
		shown += "\n"
		if typing:
			typing.stop()
		await _wait(0.28)
	var dots := 0
	var e := 0.0
	while ResourceLoader.load_threaded_get_status(STAGE_SCENE) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		e += get_process_delta_time()
		dots = int(e / 0.45) % 4
		cold.text = shown.trim_suffix("\n") + " " + ".".repeat(dots) + ("_" if fmod(e, 0.9) < 0.5 else " ")
		if _skipping:
			return
		await get_tree().process_frame
	cold.text = shown + COLD_DONE
	_sfx("beep", -12.0)
	await _wait(0.6)


func _finale() -> void:
	_tween_skip_hint(0.0)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_sfx("whoosh_big", -9.0, 0.85)
	await _move_to(Rect2(Vector2.ZERO, page_size), 1.3)
	await _wait(0.5)
	await _capture("page_full")
	# логотип: удар по странице
	title.visible = true
	title.modulate.a = 1.0
	title.scale = Vector2.ONE * 2.6
	var tw := create_tween()
	tw.tween_property(title, "scale", Vector2.ONE * 0.92, 0.16 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(title, "scale", Vector2.ONE, 0.12 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sfx("sting", -3.0)
	await _wait(0.16)
	_kick(38.0)
	_flash_screen()
	if title.has_method("play"):
		title.call("play")
	await _wait(1.0)
	await _capture("page_title")
	await _wait(1.0)
	_fade_amb(-40.0, 1.2)
	await _wait(0.6)
	if capture_dir == "":
		var f := FileAccess.open(SEEN_FLAG, FileAccess.WRITE)
		if f:
			f.store_string(Time.get_datetime_string_from_system())
	_go_to_game()


# ------------------------------------------------------------------------------------------------
# вспомогательное
# ------------------------------------------------------------------------------------------------
func _zoom_for(r: Rect2) -> float:
	var s := get_viewport_rect().size
	return minf(s.x / r.size.x, s.y / r.size.y)


func _frame_rect(r: Rect2, _k: float) -> void:
	cam.position = r.get_center()
	cam.zoom = Vector2.ONE * _zoom_for(r)


func _move_to(r: Rect2, secs: float) -> void:
	var p0 := cam.position
	var z0 := cam.zoom.x
	var z1 := _zoom_for(r)
	var e := 0.0
	while e < secs:
		e += get_process_delta_time() * speed
		var k := _ease_io(clampf(e / secs, 0.0, 1.0))
		cam.position = p0.lerp(r.get_center(), k)
		cam.zoom = Vector2.ONE * lerpf(z0, z1, k)
		if _skipping:
			return
		await get_tree().process_frame


func _wait(secs: float) -> void:
	var e := 0.0
	while e < secs:
		e += get_process_delta_time() * speed
		if _skipping:
			return
		await get_tree().process_frame


func _ease_io(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


func _kick(strength: float) -> void:
	_shake = strength
	_shake_t = 0.0


func _flash_screen() -> void:
	var f: ColorRect = $Hud/Flash
	f.color.a = 0.85
	var tw := create_tween()
	tw.tween_property(f, "color:a", 0.0, 0.35 / speed)


func _tween_fade(a: float, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, secs / speed)
	await tw.finished


func _tween_skip_hint(a: float) -> void:
	var tw := create_tween()
	tw.tween_property(skip_hint, "modulate:a", a, 0.6)


func _skip_all() -> void:
	_fade_amb(-40.0, 0.35)
	await _tween_fade(1.0, 0.35)
	_go_to_game()


func _go_to_game() -> void:
	if capture_dir != "":
		_write_report()
		get_tree().quit(0 if report["ok"] else 1)
		return
	await _tween_fade(1.0, 0.5)
	var ps: PackedScene = null
	if ResourceLoader.load_threaded_get_status(next_scene) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ps = ResourceLoader.load_threaded_get(next_scene) as PackedScene
	if ps == null:
		ps = load(next_scene) as PackedScene
	print("IntroComic → ", next_scene, " (%.1f s)" % _elapsed())
	get_tree().change_scene_to_packed(ps)


# ------------------------------------------------------------------------------------------------
# звук (assets/audio/intro/, генератор tools/gen_intro_audio.py)
# ------------------------------------------------------------------------------------------------
func _setup_audio() -> void:
	var holder := Node.new()
	holder.name = "Audio"
	add_child(holder)
	for i in 10:
		var pl := AudioStreamPlayer.new()
		holder.add_child(pl)
		_pool.append(pl)
	_amb = AudioStreamPlayer.new()
	holder.add_child(_amb)
	_amb.stream = _stream("amb_scrap")   # петля задана в импорте (edit/loop_mode=2)


func _stream(n: String) -> AudioStream:
	if not _streams.has(n):
		var path := SFX % n
		_streams[n] = load(path) if ResourceLoader.exists(path) else null
	return _streams[n]


## Играет звук из пула; возвращает плеер (чтобы остановить печать), null — нет файла.
func _sfx(n: String, db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var s := _stream(n)
	if s == null or _pool.is_empty():
		return null
	var pl: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			pl = p
			break
	if pl == null:
		pl = _pool[0]
	pl.stream = s
	pl.volume_db = db
	pl.pitch_scale = pitch * speed if speed <= 1.0 else pitch
	pl.play()
	return pl


func _fade_amb(db: float, secs: float) -> void:
	if _amb == null:
		return
	var tw := create_tween()
	tw.tween_property(_amb, "volume_db", db, secs)


func _panel_sounds(p: ComicPanel, t_prev: float, t_now: float) -> void:
	for s in p.sounds:
		var i := s.find(":")
		if i < 0:
			continue
		var at := float(s.substr(0, i))
		if t_prev < at and at <= t_now:
			var parts := s.substr(i + 1).split(":")
			_sfx(parts[0], float(parts[1]) if parts.size() > 1 else -4.0)


## Табличка Башни: сигнал и печать по буквам, пока строка печатается.
func _caption_sound(L: ComicLetter) -> void:
	_sfx("beep", -14.0)
	var pl := _sfx("type", -17.0, L.cps / 28.0)
	if pl:
		var secs := float(L.text.length()) / L.cps
		get_tree().create_timer(secs / speed).timeout.connect(func() -> void:
			if is_instance_valid(pl):
				pl.stop())


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _started_ms) / 1000.0


func _fail(msg: String) -> void:
	report["ok"] = false
	report["errors"].append(msg)
	push_warning("IntroComic: " + msg)


func _capture(n: String) -> void:
	if capture_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var path := capture_dir.path_join(n + ".png")
	img.save_png(path)
	report["captures"].append(path)


func _write_report() -> void:
	# проверки: каждая панель застыла непустой картинкой, длительность в разумных пределах
	for i in panels.size():
		var p := panels[i]
		var tex := p.art.texture
		if tex == null or p.is_live():
			_fail("panel %d not frozen" % (i + 1))
			continue
		var img := tex.get_image()
		var sum := 0.0
		var n := 0
		for y in range(0, img.get_height(), 16):
			for x in range(0, img.get_width(), 16):
				var c := img.get_pixel(x, y)
				sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				n += 1
		var mean := sum / maxf(n, 1)
		if i < report["panels"].size():
			report["panels"][i]["mean"] = mean
		if mean < 0.04:
			_fail("panel %d is black (mean %.3f)" % [i + 1, mean])
	report["total_s"] = _elapsed()
	report["speed"] = speed
	var f := FileAccess.open(capture_dir.path_join("intro_report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("intro report: ok=%s total=%.1fs panels=%d" % [report["ok"], report["total_s"], report["panels"].size()])
