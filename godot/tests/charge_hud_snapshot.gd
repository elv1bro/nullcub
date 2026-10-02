## Снимок полосы Заряда в HUD (docs/plan-demo/COMBAT_CHARGE.md): четыре панели — полный бак, 55 %, перезаряд 135, выдохся (8, запор).
## Нужно окно (не headless): godot --path . --resolution 1280x720 --always-on-top res://tests/charge_hud_snapshot.tscn -- "out=res://tests/charge_hud.png"
## Пишет PNG и печатает значения полос; exit 0/1 (панели созданы, значения дошли до ChargeBar).
extends Node

const HudScene: PackedScene = preload("res://scenes/ui/hud.tscn")


class FakeDoll extends Node:
	var player_index := 0
	var alive := true
	var charge := 100.0
	var charge_locked := false


class MatchStub extends Node:
	signal phase_changed(phase: int)
	signal time_left(seconds: float)
	signal announce(text: String, color: Color, kind: String)
	signal hp_changed(doll: Node, hp: float, max_hp: float)
	signal combo_changed(doll: Node, n: int)
	signal ko(victim: Node, attacker: Node, record: Dictionary)
	signal match_over(winner: Node, results: Dictionary)
	var fake_dolls: Array = []

	func dolls() -> Array:
		return fake_dolls


func _ready() -> void:
	var out := "res://tests/charge_hud.png"
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "out":
				out = p[1]
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.10, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stub := MatchStub.new()
	add_child(stub)
	var states := [[100.0, false], [55.0, false], [125.0, false], [8.0, true]]
	for i in range(4):
		var d := FakeDoll.new()
		d.player_index = i
		d.charge = states[i][0]
		d.charge_locked = states[i][1]
		stub.add_child(d)
		stub.fake_dolls.append(d)
	var hud := HudScene.instantiate() as Hud
	add_child(hud)
	hud.bind(stub)
	for i in range(40):
		await get_tree().process_frame
	var ok := true
	for i in range(4):
		var panel: PlayerPanel = hud.panels.get(i, null)
		var good: bool = panel != null and absf(panel.charge_bar.charge - float(states[i][0])) < 0.01 and panel.charge_bar.locked == bool(states[i][1])
		print("  panel %d: bar charge %.1f locked %s %s" % [i + 1, panel.charge_bar.charge if panel else -1.0, str(panel.charge_bar.locked) if panel else "?", "ok" if good else "FAIL"])
		ok = ok and good
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	get_tree().quit(0 if ok else 1)
