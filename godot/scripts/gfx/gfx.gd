## Графика: масштаб 3D под реальный экран и пресеты качества (docs/plan-demo/PERF_PASS.md, PERF_AUDIT.md §1 / §5). Автозагрузка «Gfx».
##
## 1) Масштаб 3D. Godot на macOS берёт max_scale = 2 для ВСЕХ окон, пока подключён Retina: на внешнем 1×-мониторе окно в «пикселях Godot» вдвое
##    больше по каждой оси, чем есть физических пикселей экрана (развёрнутое окно = 5120×2880 при 2560×1440 на мониторе — 14.7 Мп вместо
##    3.7 Мп, на Руинах 10 fps). Поэтому 3D рисуется в масштабе scale = screen_scale / max_scale (физические пиксели), а сверх того — не
##    больше бюджета пикселей пресета (FSR 1 дотягивает до окна). Меню, HUD и текст рисуются в полном разрешении окна — не размыты.
## 2) Пресеты low / medium / high / ultra (F9 в любой сцене, кнопка в тестовом меню): бюджет пикселей 3D, DOF, glow, FXAA, мягкость теней.
##    Лишнее для рендерера (SSAO / SSIL в Forward+) пресеты не трогают. Выбор хранится в user://gfx.cfg.
## Пересчёт — на смену размера окна, экрана и пресета (не каждый кадр); проба, выставляющая scaling_3d_scale сама, не перебивается.
extends Node

signal changed

const ORDER := ["low", "medium", "high", "ultra"]
const DEFAULT_PRESET := "high"
## budget_px — потолок пикселей 3D (0 — без потолка), dof / glow — разрешены ли эти эффекты, fxaa, shadow_q — SoftShadowFilterQuality
## (0 выкл … 5 ультра) направленного и точечного света. «high» = то, что было в проекте до пресетов.
const PRESETS := {
	"low": {"budget_px": 1_000_000, "dof": false, "glow": false, "fxaa": false, "shadow_q": 1},
	"medium": {"budget_px": 2_100_000, "dof": true, "glow": true, "fxaa": true, "shadow_q": 2},
	"high": {"budget_px": 3_700_000, "dof": true, "glow": true, "fxaa": true, "shadow_q": 2},
	"ultra": {"budget_px": 0, "dof": true, "glow": true, "fxaa": true, "shadow_q": 3},
}
const SCALE_MIN := 0.4
const SETTINGS_PATH := "user://gfx.cfg"
const SCREEN_POLL_S := 0.25
const TOAST_S := 1.8
const META_DOF := "gfx_dof0"
const META_GLOW := "gfx_glow0"

var preset := DEFAULT_PRESET
var render_scale := 1.0            # то, что выставлено на корневом вьюпорте (scaling_3d_scale)
var render_size := Vector2i.ZERO   # размер 3D-картинки в пикселях

var _headless := false
var _screen := -1
var _win_size := Vector2i.ZERO
var _poll_t := 0.0
var _toast: Label
var _toast_t := 0.0


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	preset = _load_preset()
	_make_toast()
	get_tree().node_added.connect(_on_node_added)
	var win := get_window()
	win.size_changed.connect(_refresh_scale)
	if win.has_signal("dpi_changed"):
		win.connect("dpi_changed", _refresh_scale)
	_apply_all()


func _process(delta: float) -> void:
	if _toast != null and _toast.visible:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	_poll_t += delta
	if _poll_t >= SCREEN_POLL_S:   # окно переехало на другой экран (другой масштаб) — размер окна при этом может не поменяться
		_poll_t = 0.0
		if not _headless and get_window().current_screen != _screen:
			_refresh_scale()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_F9:
		return
	var cs := get_tree().current_scene
	if cs != null and cs.scene_file_path.ends_with("playground_body.tscn"):
		return   # там F1–F13 — пресеты тела
	cycle()


static func values(name: String = "") -> Dictionary:
	var n := name if name != "" else DEFAULT_PRESET
	return PRESETS.get(n, PRESETS[DEFAULT_PRESET]) as Dictionary


## Выставить пресет (неизвестное имя — не меняет), применить и запомнить.
func set_preset(name: String, save := true) -> String:
	if PRESETS.has(name):
		preset = name
	_apply_all()
	if save:
		_save_preset()
	changed.emit()
	return preset


func cycle() -> String:
	var i := ORDER.find(preset)
	set_preset(String(ORDER[(i + 1) % ORDER.size()]))
	show_toast(label())
	return preset


func label() -> String:
	var info := "%s · %d×%d" % [preset.to_upper(), render_size.x, render_size.y] if render_size != Vector2i.ZERO else preset.to_upper()
	return tr("Графика: ") + info


## Что сейчас: для проб и отчётов.
func info() -> Dictionary:
	var win := get_window()
	return {"preset": preset, "render_scale": render_scale, "render_size": render_size, "window_px": win.size,
		"screen_scale": DisplayServer.screen_get_scale(win.current_screen), "max_scale": DisplayServer.screen_get_max_scale()}


# --- масштаб 3D ---

## Доля пикселей Godot, которые реально есть на экране окна (≤ 1): screen_scale / max_scale.
func display_factor() -> float:
	if _headless:
		return 1.0
	var win := get_window()
	return clampf(DisplayServer.screen_get_scale(win.current_screen) / maxf(DisplayServer.screen_get_max_scale(), 1.0), 0.1, 1.0)


## Масштаб 3D для окна в win_px пикселей Godot: физические пиксели, но не больше бюджета пикселей пресета.
static func scale_for(win_px: Vector2, factor: float, budget_px: int) -> float:
	var s := factor
	var phys := win_px.x * win_px.y * factor * factor
	if budget_px > 0 and phys > float(budget_px):
		s = factor * sqrt(float(budget_px) / phys)
	return clampf(s, SCALE_MIN, 1.0)


func _refresh_scale() -> void:
	if _headless:
		return
	var win := get_window()
	_screen = win.current_screen
	_win_size = win.size
	var f := display_factor()
	var s := scale_for(Vector2(win.size), f, int(values(preset)["budget_px"]))
	render_scale = s
	win.scaling_3d_scale = s
	# FSR 1 — когда рендер меньше физических пикселей (дотягивает резкость); равный им масштаб ОС сама сводит билинейно
	win.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if s < f - 0.01 else Viewport.SCALING_3D_MODE_BILINEAR
	render_size = Vector2i(int(win.size.x * s), int(win.size.y * s))


# --- пресет: эффекты и тени ---

func _apply_all() -> void:
	var v := values(preset)
	_refresh_scale()
	var win := get_window()
	win.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(v["fxaa"]) else Viewport.SCREEN_SPACE_AA_DISABLED
	if not _headless:
		RenderingServer.directional_soft_shadow_filter_set_quality(int(v["shadow_q"]))
		RenderingServer.positional_soft_shadow_filter_set_quality(int(v["shadow_q"]))
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_tune_world_env(n as WorldEnvironment)
	for n in get_tree().root.find_children("*", "Camera3D", true, false):
		_tune_camera(n as Camera3D)


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment:
		_tune_world_env.call_deferred(n)   # environment / camera_attributes ставятся уже после add_child
	elif n is Camera3D:
		_tune_camera.call_deferred(n)


func _tune_world_env(we: WorldEnvironment) -> void:
	if we == null or not is_instance_valid(we):
		return
	var v := values(preset)
	var env := we.environment
	if env != null:
		_drop_unsupported(env)
		if not env.has_meta(META_GLOW):
			env.set_meta(META_GLOW, env.glow_enabled)   # как задумала арена: пресет только выключает, включённым не навязывает
		env.glow_enabled = bool(env.get_meta(META_GLOW)) and bool(v["glow"])
	_tune_dof(we.camera_attributes, bool(v["dof"]))


## Эффекты, которых нет у рендерера (SSIL / SDFGI / объёмный туман — только Forward+, SSAO — Forward+ и Compatibility): выключаем в памяти,
## иначе Godot пишет предупреждение на каждую загрузку арены. Файлы окружений не трогаются.
func _drop_unsupported(env: Environment) -> void:
	var method := RenderingServer.get_current_rendering_method()
	if method == "forward_plus":
		return
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false
	if method == "mobile":
		env.ssao_enabled = false


func _tune_camera(cam: Camera3D) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	_tune_dof(cam.attributes, bool(values(preset)["dof"]))


func _tune_dof(attr: CameraAttributes, allowed: bool) -> void:
	var p := attr as CameraAttributesPractical
	if p == null:
		return
	if not p.has_meta(META_DOF):
		p.set_meta(META_DOF, [p.dof_blur_far_enabled, p.dof_blur_near_enabled])
	var orig: Array = p.get_meta(META_DOF)
	p.dof_blur_far_enabled = bool(orig[0]) and allowed
	p.dof_blur_near_enabled = bool(orig[1]) and allowed


# --- сохранение и тост ---

func _load_preset() -> String:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return DEFAULT_PRESET
	var p := String(cf.get_value("gfx", "preset", DEFAULT_PRESET))
	return p if PRESETS.has(p) else DEFAULT_PRESET


func _save_preset() -> void:
	if _headless:
		return
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("gfx", "preset", preset)
	cf.save(SETTINGS_PATH)


func _make_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_toast = Label.new()
	_toast.visible = false
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position.y -= 120.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_toast)


func show_toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = TOAST_S
