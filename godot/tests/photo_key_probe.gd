## Проба клавиши «/» (headless, --fixed-fps 60): фоторежим LookCam против руки P2 с клавиатуры. «/» — вход в фоторежим (PhotoMode)
## и в то же время хват P2 в головоломках и Перегоне (PuzzleKeyArm, вход P2 в игру) и в перетягивании (P2 человек — хват каната).
## Режим, где «/» занята, ставит себя в группу PhotoMode.KEY_TAKEN_GROUP — фоторежим уступает клавишу.
##   A  обычный бой (Void): «/» — фоторежим и пауза, ещё раз «/» — выход;
##   B  головоломки: «/» — P2 вошёл в игру, фоторежима нет; ещё «/» — рука P2 сработала (PuzzleKeyArm.last_action), фоторежима нет;
##   C  Перегон: то же, что B;
##   D  перетягивание, P2 человек: «/» — фоторежима нет, пауза не встала; P2 бот: «/» — фоторежим (клавиша свободна), «/» — выход.
## Нажатия — Input.parse_input_event (как с клавиатуры: состояние действий Input + _input / _unhandled_input вьюпорта).
## Ловит SCRIPT ERROR (Logger). Запуск: godot --headless --path godot --fixed-fps 60 res://tests/photo_key_probe.tscn   Exit 0/1.
extends Node

const VOID := "res://scenes/playground_void.tscn"
const PUZZLE := "res://scenes/playground_puzzle.tscn"
const CONVOY := "res://scenes/playground_convoy.tscn"
const TUG := "res://scenes/playground_tug.tscn"


class ScriptErrors extends Logger:
	var count := 0
	var first := ""
	var _mx := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mx.lock()
		count += 1
		if first == "":
			first = "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mx.unlock()


var ok := true
var errs := ScriptErrors.new()
var look: Node
var lc: Node
var pg: Node
var _saved := {}


func check(id: String, cond: bool, detail: Variant = "") -> void:
	if not cond:
		ok = false
	print("  %s %s: %s" % ["ok  " if cond else "FAIL", id, str(detail)])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.add_logger(errs)
	print("=== PHOTO KEY PROBE ===")
	look = get_node_or_null("/root/Look")
	lc = get_node_or_null("/root/LookCam")
	check("autoloads", look != null and lc != null, "Look и LookCam в автозагрузке")
	if look == null or lc == null:
		_finish()
		return
	lc.call("register_items")
	_saved = {"master": look.master, "photo": look.checked(&"cam_photo")}
	look.set_master(true)
	look.set_on(&"cam_photo", true)
	await _case_a()
	await _case_puzzle("B", PUZZLE)
	await _case_puzzle("C", CONVOY)
	await _case_d()
	_finish()


# --- помощники ---

func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	await get_tree().process_frame


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## Нажать и отпустить: держим 2 физических тика (действие «just pressed» видно в _physics_process).
func _tap(code: Key) -> void:
	_key(code, true)
	await _ticks(2)
	_key(code, false)
	await _ticks(1)


func _photo() -> bool:
	return bool(lc.call("photo_active"))


## Выйти из фоторежима, если открыт (чтобы следующий случай начинался чисто).
func _photo_off() -> void:
	if _photo():
		lc.call("toggle_photo")
		await _ticks(1)
	get_tree().paused = false


func _load(path: String, setup := Callable()) -> void:
	await _unload()
	pg = (load(path) as PackedScene).instantiate()
	if setup.is_valid():
		setup.call(pg)
	add_child(pg)
	await _ticks(30)


func _unload() -> void:
	await _photo_off()
	if pg != null and is_instance_valid(pg):
		remove_child(pg)
		pg.queue_free()
		pg = null
		await get_tree().physics_frame


func _key_arm() -> PuzzleKeyArm:
	if pg == null:
		return null
	var found := pg.find_children(PuzzleKeyArm.NODE_NAME, "", true, false)
	return found[0] as PuzzleKeyArm if found.size() > 0 else null


# --- случаи ---

func _case_a() -> void:
	print("-- A: обычный бой — «/» открывает фоторежим")
	await _load(VOID)
	await _tap(KEY_SLASH)
	check("A_photo_on", _photo() and get_tree().paused, "фоторежим %s, пауза %s" % [_photo(), get_tree().paused])
	await _tap(KEY_SLASH)
	check("A_photo_off", not _photo() and not get_tree().paused, "вторая «/» — выход")


func _case_puzzle(tag: String, path: String) -> void:
	print("-- %s: %s — «/» у руки P2" % [tag, path.get_file()])
	await _load(path, func(n: Node) -> void:
		n.set("p2_on_start", false)
		n.set("auto_join", true))
	check(tag + "_key_taken", get_tree().get_first_node_in_group(PhotoMode.KEY_TAKEN_GROUP) != null, "режим занял клавишу «/»")
	await _tap(KEY_SLASH)
	var p2: Variant = pg.get("p2")
	check(tag + "_join", p2 is Doll and is_instance_valid(p2), "«/» — P2 вошёл в игру")
	check(tag + "_join_no_photo", not _photo() and not get_tree().paused, "фоторежим %s, пауза %s" % [_photo(), get_tree().paused])
	await _ticks(90)
	var key := _key_arm()
	check(tag + "_key_arm", key != null, "PuzzleKeyArm у P2")
	if key == null:
		return
	key.last_action = ""
	await _tap(KEY_SLASH)
	check(tag + "_grab_no_photo", not _photo() and not get_tree().paused, "фоторежим %s, пауза %s" % [_photo(), get_tree().paused])
	check(tag + "_grab_pressed", key.last_action != "", "рука P2 сработала: «%s»" % key.last_action)


func _case_d() -> void:
	print("-- D: перетягивание — «/» хват P2-человека")
	await _load(TUG, func(n: Node) -> void:
		n.set("p1_bot", true)
		n.set("p2_human", true))
	check("D_key_taken", get_tree().get_first_node_in_group(PhotoMode.KEY_TAKEN_GROUP) != null, "P2 человек — клавиша «/» занята")
	await _tap(KEY_SLASH)
	check("D_human_no_photo", not _photo() and not get_tree().paused, "фоторежим %s, пауза %s" % [_photo(), get_tree().paused])
	pg.call("set_p2_human", false)
	check("D_bot_key_free", get_tree().get_first_node_in_group(PhotoMode.KEY_TAKEN_GROUP) == null, "P2 бот — клавиша свободна")
	await _tap(KEY_SLASH)
	check("D_bot_photo", _photo() and get_tree().paused, "фоторежим %s, пауза %s" % [_photo(), get_tree().paused])
	await _tap(KEY_SLASH)
	check("D_bot_photo_off", not _photo() and not get_tree().paused, "вторая «/» — выход")


func _finish() -> void:
	await _unload()
	if look != null and not _saved.is_empty():
		look.set_on(&"cam_photo", bool(_saved["photo"]))
		look.set_master(bool(_saved["master"]))
	get_tree().paused = false
	check("no_script_errors", errs.count == 0, "SCRIPT ERROR: %d %s" % [errs.count, errs.first])
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
