## Проба ударных эффектов без физики: три вспышки (body / head / weapon, strength 4 / 8 / 16) + щепки перед камерой,
## кадры tests/fx_probe_a.png (0.04 с) и tests/fx_probe_b.png (0.12 с). Запуск:
##   godot --path . --resolution 1280x720 --always-on-top res://tests/fx_probe.tscn
extends Node3D

const SHOTS := [[0.04, "fx_probe_a.png"], [0.12, "fx_probe_b.png"]]
const SPAWNS := [Vector3(-1.2, 1.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(1.2, 1.0, 0.0)]
var _t := 0.0
var _i := 0
var _spawned := false


func _ready() -> void:
	HitJuice.impact_style = "cartoon"   # проба снимает звёзды-вспышки стиля «мульт»; «серьёзный» — juice_probe / impact_look_snapshot (§13)


func _process(delta: float) -> void:
	if not _spawned:
		_spawned = true
		ImpactFx.spawn_impact(self, Vector3(-1.2, 1.0, 0.0), Vector3(0, 0, 1), 4.0, "body")
		ImpactFx.spawn_impact(self, Vector3(0.0, 1.0, 0.0), Vector3(0, 0, 1), 8.0, "head")
		ImpactFx.spawn_impact(self, Vector3(1.2, 1.0, 0.0), Vector3(0, 0, 1), 16.0, "weapon")
		return
	_t += delta
	if _i < SHOTS.size() and _t >= float(SHOTS[_i][0]):
		var name: String = SHOTS[_i][1]
		_i += 1
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://tests/" + name)
		var flashes := find_children("Flash", "Node3D", true, false)
		var ok := flashes.size() == 3
		var pos_ok := true
		for f in flashes:
			var near := false
			for sp in SPAWNS:
				if (f as Node3D).global_position.distance_to(sp + Vector3(0.0, 0.0, 0.18)) < 0.01:
					near = true
			pos_ok = pos_ok and near
		ok = ok and pos_ok
		print("shot %s t=%.3f flashes=%d positions=%s %s" % [name, _t, flashes.size(), "ok" if pos_ok else "WRONG", "OK" if ok else "FAIL (ожидалось 3 вспышки в точках удара)"])
		if _i >= SHOTS.size():
			get_tree().quit(0 if ok else 1)
