## Цена света в кадре (PERF_AUDIT №8): сколько мс кадра стоит каждая группа источников сцены. ОКНО (кадр по реальным часам, vsync выключен: на Metal GPU-таймер отдаёт 0).
## Запуск: godot/tools/godot_nofocus.sh --path godot --resolution 1920x1080 res://tests/light_cost_probe.tscn -- "scene=res://scenes/playground_scrap.tscn,frames=150"
## Грузит сцену, греет 90 кадров, меряет средний кадр (реальные часы) с полным светом и затем с выключенной группой: все Directional без теней,
## все Spot, все Omni, все источники сразу (ambient и фон остаются). Печатает «LIGHTCOST группа: N шт, кадр X мс, цена Y мс» и список источников.
## Выход — только отчёт, exit 0.
extends Node

var scene_path := "res://scenes/playground_scrap.tscn"
var frames := 150
var warm := 90
const REPEATS := 4
var root_scene: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2:
				match p[0]:
					"scene": scene_path = p[1]
					"frames": frames = int(p[1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root_scene = (load(scene_path) as PackedScene).instantiate()
	add_child(root_scene)
	await _measure_all()
	get_tree().quit(0)


func _lights() -> Array:
	var out: Array = []
	for n in root_scene.find_children("*", "Light3D", true, false):
		if str(root_scene.get_path_to(n)).begins_with("Match") or str(root_scene.get_path_to(n)).contains("ImpactFx"):
			continue   # короткоживущие вспышки ударов не трогаем
		out.append(n)
	return out


func _kind(l: Light3D) -> String:
	if l is DirectionalLight3D:
		return "shadow_dir" if l.shadow_enabled else "dir"
	if l is SpotLight3D:
		return "shadow_spot" if l.shadow_enabled else "spot"
	return "shadow_omni" if l.shadow_enabled else "omni"


## Средний кадр по реальным часам (GPU-таймер на Metal отдаёт 0): vsync выключен, кадр упирается в GPU.
func _frame_ms() -> float:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in range(warm):
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for i in range(frames):
		await get_tree().process_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)


func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


## Группа выключается и включается по очереди (REPEATS раз), цена = медиана «со светом» − медиана «без группы»: шум одиночного замера ±1,5 мс.
func _cost(group: Array) -> Array:
	var on: Array = []
	var off: Array = []
	for r in range(REPEATS):
		for l in group:
			l.visible = true
		on.append(await _frame_ms())
		for l in group:
			l.visible = false
		off.append(await _frame_ms())
	for l in group:
		l.visible = true
	return [_median(on), _median(off)]


func _measure_all() -> void:
	var lights := _lights()
	var kinds := {}
	for l in lights:
		var k := _kind(l)
		kinds[k] = int(kinds.get(k, 0)) + 1
		print("LIGHT %s %s energy=%.2f range=%s" % [k, root_scene.get_path_to(l), l.light_energy, str(l.get("omni_range") if l is OmniLight3D else (l.get("spot_range") if l is SpotLight3D else "-"))])
	warm = 90
	await _frame_ms()
	warm = 30
	print("LIGHTCOST %s: %d источников %s, окно %s, повторов %d" % [scene_path.get_file(), lights.size(), kinds, get_viewport().get_visible_rect().size, REPEATS])
	var groups := {}
	for k in kinds.keys():
		var g: Array = []
		for l in lights:
			if _kind(l) == k and l.visible:
				g.append(l)
		groups[k] = g
	var every: Array = []
	for l in lights:
		if l.visible:
			every.append(l)
	groups["ВСЕ"] = every
	for k in groups.keys():
		var g: Array = groups[k]
		if g.is_empty():
			continue
		var r := await _cost(g)
		print("LIGHTCOST %s: %-12s %2d шт — со светом %.2f мс, без %.2f мс, цена %.2f мс" % [scene_path.get_file(), k, g.size(), r[0], r[1], float(r[0]) - float(r[1])])
