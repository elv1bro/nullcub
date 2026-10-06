## Проба автозагрузки «Look» (LOOK_PASS.md, headless): регистрация пунктов, галочки, общий рубильник «до / после», сигналы, панель,
## программная смена не пишет user://look.cfg. Запуск: godot --headless --path . res://tests/look_probe.tscn   Exit 0/1.
extends Node

var ok := true
var _sig: Array = []


func _check(id: String, cond: bool, detail: String) -> void:
	if not cond:
		ok = false
	print("  %s %s: %s" % ["ok  " if cond else "FAIL", id, detail])


func _ready() -> void:
	print("=== LOOK PROBE ===")
	var look := get_node_or_null("/root/Look")
	_check("autoload", look != null, "Look в автозагрузке")
	if look == null:
		_finish()
		return
	var cfg := ProjectSettings.globalize_path(look.SAVE_PATH)
	var had_cfg := FileAccess.file_exists(cfg)
	var before := FileAccess.get_file_as_string(cfg) if had_cfg else ""
	var master0: bool = look.master
	look.set_master(true)
	look.changed.connect(func(id: StringName, v: bool) -> void: _sig.append([id, v]))
	var a: bool = look.add(&"_probe_a", "проба А", "Проба")
	var b: bool = look.add(&"_probe_b", "проба Б", "Проба", false)
	_check("default_on", a and look.on(&"_probe_a"), "новый пункт включён по умолчанию")
	_check("default_off", not b and not look.on(&"_probe_b"), "default_on=false держится")
	_check("unknown", look.on(&"_probe_nope"), "незарегистрированный пункт = рубильник (вкл)")
	look.set_on(&"_probe_a", false)
	_check("set_off", not look.on(&"_probe_a") and _sig.back() == [&"_probe_a", false], "галочка снята, сигнал ушёл")
	look.set_on(&"_probe_a", true)
	_sig.clear()
	look.set_master(false)
	_check("master_off", not look.on(&"_probe_a") and not look.on(&"_probe_nope"), "рубильник выкл → все on() = false")
	_check("master_signal", _sig.size() == 1 and _sig[0] == [&"_probe_a", false], "сигнал только по включённым пунктам: %s" % str(_sig))
	_check("checked_kept", look.checked(&"_probe_a"), "галочка под выключенным рубильником сохранилась")
	look.set_master(true)
	_check("master_on", look.on(&"_probe_a") and not look.on(&"_probe_b"), "рубильник вкл → снова по галочкам")
	var panel: LookPanel = look._panel
	panel.set_open(true)
	await get_tree().process_frame
	_check("panel_rows", panel._checks.has(&"_probe_a") and panel._checks.has(&"_probe_b"), "в панели строки обоих пунктов")
	_check("panel_state", (panel._checks[&"_probe_a"] as CheckBox).button_pressed and not (panel._checks[&"_probe_b"] as CheckBox).button_pressed, "галочки панели = состояние")
	panel.set_open(false)
	var after := FileAccess.get_file_as_string(cfg) if FileAccess.file_exists(cfg) else ""
	_check("no_write", after == before, "программная смена не писала %s" % look.SAVE_PATH)
	look.set_master(master0)
	_finish()


func _finish() -> void:
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
