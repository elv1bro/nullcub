## Площадка: арена + две куклы на клавиатуре (P1 — клён doll.tscn, P2 — орех doll_dark.tscn) + оружие + динамическая камера
## + Match (scripts/core/match.gd: фазы, урон через DollCombat, KO, Sudden Death, итоги) + HUD (scenes/ui/hud.tscn, привязан к Match).
## Дерево (арена, P1/P2 с WeaponPickup, Weapons, Camera, Match, HUD, UI/Hint) живёт в сцене: scenes/playground.tscn — «Руины»,
## scenes/playground_workshop.tscn — «Мастерская», scenes/playground_void.tscn — «Void» (пустое чёрное поле RM, без оружия;
## Weapons там пустой — только молот Sudden Death) (ASSET_PIPELINE.md, правило 2). Здесь только поведение:
##   R — match.restart() (куклы пересоздаются на точках спавна арены), Esc — выход, 1–7 — сменить площадку
##   (Руины / Мастерская / Void / Свалка / Тело / Сборка — последние две из сессии сборки тела, BODY_CRAFT.md);
##   пропасть (сигнал body_fell арены): во время боя — Doll.knock_out() (KO kind "self", Match сам заканчивает матч), иначе —
##   респавн через RESPAWN_DELAY_S через Match.respawn_doll (той же породы дерева);
##   Sudden Death (Match.sudden_death_step): шаг SUDDEN_DEATH_HEAVY_WEAPON_STEP — молот падает в центр арены,
##   SUDDEN_DEATH_BREAK_PLATFORMS_STEP — верёвочные мосты арены (RopeBridge.break_apart) обрываются;
##   камера: snap на отсчёте (после рестарта куклы стоят на новых местах); меши оружия → gi_mode DYNAMIC (SDFGI в окружении).
## Щепки/пыль (ImpactFx) и урон считает DollCombat — ребёнок каждой куклы, его добавляет Match.register.
## P1: WASD, Shift рывок, Space переворот. P2: стрелки, правый Ctrl рывок, Enter переворот.
## F10 — пресет эффектов ударов full → reduced → off (FxPreset, HIT_FX.md §11.2), тост «FX: …» внизу экрана на FX_TOAST_S.
extends Node3D

const SCENES := {
	"ruins": "res://scenes/playground.tscn",
	"workshop": "res://scenes/playground_workshop.tscn",
	"void": "res://scenes/playground_void.tscn",
	"scrap": "res://scenes/playground_scrap.tscn",          # Свалка (биом 01, CONCEPT_V2)
	"body": "res://scenes/playground_body.tscn",            # площадка сборки тела: пресеты F1–F12, [ ] / PgUp PgDn (BODY_CRAFT.md)
	"build": "res://scenes/workshop/workshop_build.tscn",   # мастерская: сборка тела и оружия (BODY_CRAFT.md)
	"pve": "res://scenes/playground_pve.tscn",              # PvE-волны на Свалке (сессия «Определение игры и планы»)
}
## Клавиши площадок: одна таблица на все сцены (площадки, не наследующие этот скрипт, зовут scene_for_key).
const ARENA_KEYS := {KEY_1: "ruins", KEY_2: "workshop", KEY_3: "void", KEY_4: "scrap", KEY_5: "body", KEY_6: "build", KEY_7: "pve"}


## Путь сцены площадки для клавиши 1–7 (physical_keycode) или "" — для площадок со своим скриптом:
##   var path: String = preload("res://scenes/playground.gd").scene_for_key(event.physical_keycode)
##   if path != "" and path != scene_file_path: get_tree().change_scene_to_file(path)
static func scene_for_key(keycode: int) -> String:
	var id: String = ARENA_KEYS.get(keycode, "")
	return SCENES.get(id, "") if id != "" else ""
const DOLLS_GROUP := "dolls"
const RESPAWN_DELAY_S := 1.0
const SD_HAMMER_DROP_M := 1.5      # молот Sudden Death появляется на столько метров ниже потолка арены и падает
const FX_TOAST_S := 1.2            # с реального времени: тост пресета FX (F10) держится, потом гаснет за 0.3 с

## Идентификатор текущей арены (ключ SCENES) — какую сцену НЕ перезагружать по 1–7.
@export var arena_id := "ruins"

var arena: Node3D                  # RuinsArena | WorkshopArena | VoidArena: spawn_points(), bounds(), сигнал body_fell
var hits := 0                      # число ударов с начала (Match.hit) — читают тесты
var sd_hammer: Weapon = null       # молот Sudden Death (один на матч)
var fx_toast: Label = null         # тост F10 (создаётся при первом нажатии, CanvasLayer 20 — поверх HUD)
var _fx_toast_tw: Tween = null

@onready var cam: DynamicCamera = $Camera
@onready var match_node: Match = $Match
@onready var hud: Hud = $HUD
@onready var weapons_root: Node3D = $Weapons


func _ready() -> void:
	arena = _find_arena()
	if arena != null and arena.has_signal("body_fell"):
		arena.connect("body_fell", _on_body_fell)
	hud.bind(match_node)
	match_node.phase_changed.connect(_on_phase_changed)
	match_node.sudden_death_step.connect(_on_sudden_death_step)
	match_node.hit.connect(func(_v: Doll, _a: Node, _d: float, _k: String, _p: Vector3) -> void: hits += 1)
	_set_gi_dynamic(weapons_root)


## Арена — первый ребёнок с spawn_points() (Ruins / Workshop / Void).
func _find_arena() -> Node3D:
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			return c
	return null


func dolls() -> Array:
	var out: Array = []
	for c in get_children():
		if c is Doll and c.is_in_group(DOLLS_GROUP):
			out.append(c)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				match_node.restart()
			KEY_ESCAPE:
				get_tree().quit()
			KEY_1:
				switch_arena("ruins")
			KEY_2:
				switch_arena("workshop")
			KEY_3:
				switch_arena("void")
			KEY_4:
				switch_arena("scrap")
			KEY_5:
				switch_arena("body")
			KEY_6:
				switch_arena("build")
			KEY_7:
				switch_arena("pve")
			KEY_F10:
				cycle_fx_preset()


## F10: следующий пресет FX (применяется ко всем HitFxDirector сразу) и тост. Возвращает имя пресета.
func cycle_fx_preset() -> String:
	var preset := FxPreset.cycle(get_tree())
	_show_fx_toast(FxPreset.label())
	return preset


func _show_fx_toast(text: String) -> void:
	if fx_toast == null or not is_instance_valid(fx_toast):
		var layer := CanvasLayer.new()
		layer.name = "FxToast"
		layer.layer = 20
		add_child(layer)
		fx_toast = Label.new()
		fx_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fx_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fx_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		fx_toast.offset_left = -160.0
		fx_toast.offset_right = 160.0
		fx_toast.offset_top = -120.0
		fx_toast.offset_bottom = -80.0
		fx_toast.add_theme_font_size_override("font_size", 26)
		fx_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		fx_toast.add_theme_constant_override("outline_size", 6)
		fx_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(fx_toast)
	fx_toast.text = text
	fx_toast.modulate = Color(1, 1, 1, 1)
	fx_toast.visible = true
	if _fx_toast_tw != null and _fx_toast_tw.is_valid():
		_fx_toast_tw.kill()
	_fx_toast_tw = fx_toast.create_tween().set_ignore_time_scale(true)
	_fx_toast_tw.tween_interval(FX_TOAST_S)
	_fx_toast_tw.tween_property(fx_toast, "modulate:a", 0.0, 0.3)
	_fx_toast_tw.tween_callback(func() -> void: fx_toast.visible = false)


## Смена арены: загрузка другой площадки целиком (Match._exit_tree возвращает Engine.time_scale = 1).
func switch_arena(id: String) -> void:
	if id == arena_id or not SCENES.has(id):
		return
	get_tree().change_scene_to_file(SCENES[id])


func respawn_all() -> void:
	match_node.restart()


## Заменяет куклу новым инстансом её сцены на её точке спавна (делегирует Match.respawn_doll). Возвращает новую.
func respawn(old: Doll) -> Doll:
	return match_node.respawn_doll(old)


func _on_phase_changed(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		cam.snap()
		if is_instance_valid(sd_hammer):
			sd_hammer.queue_free()
		sd_hammer = null


func _on_body_fell(body: Node3D) -> void:
	var d := body.get_parent() as Doll
	if d == null or not d.is_in_group(DOLLS_GROUP) or not d.alive:
		return   # оружие и части уже разбитой куклы падают дальше
	d.knock_out()   # KO kind "self"; во время боя Match учитывает его как обычное KO и сам завершает матч
	if match_node.combat_active():
		return
	get_tree().create_timer(RESPAWN_DELAY_S).timeout.connect(func() -> void:
		if is_instance_valid(d) and d.is_inside_tree():
			match_node.respawn_doll(d))


## Sudden Death (CONCEPT.md §12, В8): n = 1 — молот в центре арены, n = 3 — мосты рвутся.
func _on_sudden_death_step(n: int) -> void:
	if n == Tuning.SUDDEN_DEATH_HEAVY_WEAPON_STEP and sd_hammer == null:
		var b: AABB = arena.call("bounds") if arena != null and arena.has_method("bounds") else cam.bounds()
		var pos := Vector3(b.get_center().x, b.end.y - SD_HAMMER_DROP_M, 0.0)
		sd_hammer = Weapon.spawn("hammer", weapons_root, pos, 0.0)
		if sd_hammer != null:
			_set_gi_dynamic(sd_hammer)
	elif n == Tuning.SUDDEN_DEATH_BREAK_PLATFORMS_STEP and arena != null and arena.has_method("rope_bridges"):
		for rb in arena.call("rope_bridges"):
			if rb.has_method("break_apart"):
				rb.call("break_apart")


func _set_gi_dynamic(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for c in n.get_children():
		_set_gi_dynamic(c)
