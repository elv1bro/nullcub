## Снимки пробного режима «Прочность суставов» в бою (нужно окно): Быстрый бой (купол), клавиша C, панель клавиш L, искры на
## повреждённом суставе, вспышка отрыва → <out>/joints_1_toggle.png, joints_2_sparks.png, joints_3_break.png, joints_4_after.png.
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x900 res://tests/joint_break_snapshot.tscn -- "out=/abs/dir,secs=5"
## Заодно проверка (exit 1): C включает JointBreak и показывает тост, в панели клавиш есть строка режима; сустав с малым запасом
## искрит (JointBreakFx.stats.sparks); урон сверх запаса отрывает предплечье с кистью у бойца игрока, боец жив; повторное C выключает.
## Файл настроек автора не трогает (ControlFeel.no_disk).
extends Node

const PART := "LowerArm_L"

var out := "/tmp"
var secs := 5.0
var scene_path := "res://scenes/playground_null_hall.tscn"
var _t := 0.0
var _mark := 0.0
var _stage := 0
var _fails := 0
var _busy := false
var _doll: Doll
var _juice: HitJuice
var _sparks0 := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2:
				if p[0] == "out": out = p[1]
				elif p[0] == "secs": secs = float(p[1])
				elif p[0] == "scene": scene_path = p[1]
	ControlFeel.no_disk = true
	ControlFeel.reset()
	JointBreak.set_on(false)
	add_child((load(scene_path) as PackedScene).instantiate())


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _player() -> Doll:
	for n in get_tree().get_nodes_in_group("dolls"):
		var d := n as Doll
		if d != null and d.alive and not d.external_input:
			return d
	return null


func _shot(file: String) -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(file))
	print("saved ", out.path_join(file))
	_busy = false


func _process(delta: float) -> void:
	_t += delta
	if _busy:
		return
	match _stage:
		0:
			if _t > secs:
				_stage = 1
				_mark = _t
				_juice = get_tree().root.find_child("HitJuice", true, false) as HitJuice
				_doll = _player()
				_check(_juice != null and _doll != null, "HitJuice и боец игрока на месте")
				if _juice == null or _doll == null:
					get_tree().quit(1)
					return
				_key(KEY_C)
				_key(KEY_L)
		1:
			if _t > _mark + 0.4:
				_stage = 2
				_mark = _t
				_check(JointBreak.on, "C включил режим суставов")
				var toast := _juice._toast
				_check(toast != null and toast.visible and toast.text.contains(tr("Прочность суставов")), "тост режима показан: %s" % (toast.text if toast != null else ""))
				var has_row := false
				for r in _juice.keys_lines():
					has_row = has_row or String(r[0]) == "C"
				_check(has_row and _juice.keys_panel.open, "в панели клавиш (L) есть строка C")
				await _shot("joints_1_toggle.png")
				_key(KEY_L)   # панель клавиш закрыть: дальше в кадре искры и отрыв
				_doll.grace_until = -1.0
				_doll.max_hp = 1000.0
				_doll.hp = 1000.0
				_sparks0 = int(_juice.joint_fx.stats["sparks"])
				_doll.take_damage(float(_doll.joint_hp[PART]) * 0.85, null, PART, _doll.parts[PART].global_position, Vector3.UP, "body")
		2:
			if int(_juice.joint_fx.stats["sparks"]) > _sparks0 or _t > _mark + 3.0:
				_stage = 3
				_mark = _t
				_check(int(_juice.joint_fx.stats["sparks"]) > _sparks0, "сустав с 15 % запаса искрит")
				await get_tree().process_frame
				await get_tree().process_frame
				await _shot("joints_2_sparks.png")
				_doll.take_damage(float(_doll.joint_hp_max[PART]), null, PART, _doll.parts[PART].global_position, Vector3.UP, "body")
		3:
			if not _doll.parts.has(PART) or _t > _mark + 1.0:
				_stage = 4
				_mark = _t
				_check(not _doll.parts.has(PART) and not _doll.parts.has("Hand_L") and _doll.alive, "предплечье с кистью отлетело, боец жив")
				_check(int(_juice.joint_fx.stats["breaks"]) == 1, "вспышка отрыва была")
				await get_tree().process_frame
				await _shot("joints_3_break.png")
		4:
			if _t > _mark + 0.8:
				_stage = 5
				_mark = _t
				await _shot("joints_4_after.png")
				_key(KEY_C)
		5:
			if _t > _mark + 0.3:
				_stage = 6
				_check(not JointBreak.on, "повторное C выключило режим")
				ControlFeel.reset()
				print("fails: ", _fails)
				get_tree().quit(1 if _fails > 0 else 0)
