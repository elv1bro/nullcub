## Проба загрузки арены «Свалка» (scenes/arena/scrap.tscn): время load() и instantiate() в холодном процессе, число разных
## текстур в материалах арены и откуда они. Проверки (exit 1 при провале): у мешей из assets/models/scrap/** нет «своих»
## текстур, извлечённых из glb (все подменены общими из assets/models/scrap/shared_tex/ пост-импортом
## tools/import/scrap_shared_textures.gd), и все общие текстуры VRAM-сжатые. Время только печатается (зависит от машины):
## 29.09, M2 headless — 7.3–9.0 с и ~500 текстур lossless без библиотеки, ~0.1 с и 68 текстур с ней (docs/plan-demo/ASSET_PIPELINE.md).
## Запуск: godot --headless --path . -s res://tests/scrap_load_probe.gd [-- scene=res://…tscn]
extends SceneTree

const SCENE := "res://scenes/arena/scrap.tscn"
const SCRAP := "res://assets/models/scrap/"
const LIB := "res://assets/models/scrap/shared_tex/"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := SCENE
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("scene="):
			scene = arg.trim_prefix("scene=")
	var t0 := Time.get_ticks_usec()
	var ps: PackedScene = load(scene)
	var t1 := Time.get_ticks_usec()
	var inst := ps.instantiate()
	var t2 := Time.get_ticks_usec()
	var tex := {}
	_collect(inst, tex)
	var own: Array[String] = []
	var lossless: Array[String] = []
	var shared := 0
	for p: String in tex:
		if p.begins_with(LIB):
			shared += 1
			if not (tex[p] as Texture2D).get_image().is_compressed():
				lossless.append(p)
		elif p.begins_with(SCRAP):
			own.append(p)
	var report := {
		"scene": scene, "load_ms": roundi((t1 - t0) / 1000.0), "instantiate_ms": roundi((t2 - t1) / 1000.0),
		"textures": tex.size(), "shared": shared, "own_scrap": own.size(), "shared_not_vram": lossless.size(),
		"ok": own.is_empty() and lossless.is_empty(),
	}
	print("=== SCRAP LOAD PROBE ===")
	print(JSON.stringify(report, " "))
	for p in own.slice(0, 10):
		print("own: ", p)
	for p in lossless.slice(0, 10):
		print("not vram: ", p)
	print("=== OK ===" if report.ok else "=== FAIL ===")
	inst.free()
	quit(0 if report.ok else 1)


func _collect(n: Node, out: Dictionary) -> void:
	var mesh = n.get("mesh")
	var mats: Array = []
	if mesh is Mesh:
		for s in mesh.get_surface_count():
			mats.append(mesh.surface_get_material(s))
	if n is GeometryInstance3D:
		mats.append(n.material_override)
	if n is MeshInstance3D:
		for s in n.get_surface_override_material_count():
			mats.append(n.get_surface_override_material(s))
	for m in mats:
		if m is BaseMaterial3D:
			for i in BaseMaterial3D.TEXTURE_MAX:
				var t: Texture2D = m.get_texture(i)
				if t and not t.resource_path.is_empty():
					out[t.resource_path] = t
	for c in n.get_children():
		_collect(c, out)
