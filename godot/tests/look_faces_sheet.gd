## Лист выражений лиц (look-faces, docs/plan-demo/look/faces.md; ОКОННАЯ проба — только через tools/godot_nofocus.sh): одна голова
## 12 раз в сетке 4 × 3, на каждой своё выражение (FaceExpr.EXPRESSIONS), подписи — id выражения. Аргументы после --:
## head=visor|pilot|round|wood (голова-визор Спринтера, шлем пилота Титана, круглая кита «Человек», деревянный манекен с наклейкой),
## out=<имя файла в tests/look_shots/>. Пишет PNG и выходит (exit 0/1).
##   godot/tools/godot_nofocus.sh --path godot --resolution 1600x1000 res://tests/look_faces_sheet.tscn -- "head=visor"
extends Node3D

const OUT := "res://tests/look_shots/"
const HEADS := {
	"visor": "res://assets/models/body/kit/Kit_Head_ProVisor.glb",
	"pilot": "res://assets/models/body/kit/Kit_Head_ProPilot.glb",
	"round": "res://assets/models/body/kit/Kit_Head_Round.glb",
	"wood": "res://assets/models/heroes/mannequin_v3/light/Head.glb",
	"wood_dark": "res://assets/models/heroes/mannequin_v3/dark/Head.glb",
}
const DX := 0.5
const DY := 0.5

var head := "visor"
var out := ""
## zoom=<i> — крупный план одной головы i (камера 0.55 м); bare=1 — без выражений (исходный вид).
var zoom := -1
var bare := false
## far=<k> — камера в k раз дальше (голова в кадре ~ как в бою: 40–60 px).
var far := 1.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		for part in a.split(","):
			var kv := part.split("=", true, 1)
			if kv.size() < 2:
				continue
			match kv[0]:
				"head": head = kv[1]
				"out": out = kv[1]
				"zoom": zoom = int(kv[1])
				"bare": bare = kv[1] == "1"
				"far": far = float(kv[1])
	if out == "":
		out = "faces_sheet_%s.png" % head
	_stage()
	var gfx := get_node_or_null("/root/Gfx")
	if gfx != null:
		gfx.set("auto_scale", false)
	get_window().scaling_3d_scale = 1.0   # лист — без мыла DynRes / Retina (Gfx не перебивает выставленный пробой)
	var ok := true
	var ps := load(String(HEADS.get(head, HEADS["visor"]))) as PackedScene
	for i in FaceExpr.EXPRESSIONS.size():
		var name: String = FaceExpr.EXPRESSIONS[i]
		var h := ps.instantiate() as Node3D
		h.position = Vector3((i % 4 - 1.5) * DX, (1 - i / 4) * DY - 0.17, 0.0)
		add_child(h)
		if not bare:
			ok = _dress(h, name) and ok
		var l := Label3D.new()
		l.text = "%d %s" % [i, name]
		l.font_size = 40
		l.pixel_size = 0.0016
		l.outline_size = 8
		l.modulate = Color(0.95, 0.9, 0.8)
		l.position = h.position + Vector3(0.0, -0.05, 0.2)
		add_child(l)
	for i in 6:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT + out)
	ok = img.save_png(path) == OK and ok
	print("  sheet %s (%dx%d) %s" % [path, img.get_width(), img.get_height(), "ok" if ok else "FAIL"])
	print("=== %s ===" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


## Выражение на голове h: плашка кита — материал с атласом; манекен — наклейка FaceExpr.build_wood_sticker.
func _dress(h: Node3D, name: String) -> bool:
	var found := false
	var plate: MeshInstance3D
	for mi in _meshes(h):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if FaceExpr.is_kit_face(src):
				m.set_surface_override_material(s, FaceExpr.make_kit_material(src as BaseMaterial3D, name))
				found = true
			elif src != null and src.resource_name.begins_with("Face"):
				plate = m
	if found or plate == null:
		return found
	var egg := plate.get_parent() as MeshInstance3D
	var box := plate.transform * plate.get_aabb()
	var c := Vector2(box.get_center().x, box.position.y + box.size.y * FaceExpr.WOOD_CENTER_Y)
	var mat := FaceExpr.make_wood_material(name)
	for s in plate.mesh.get_surface_count():   # «глазницы» плашки — под дерево, как FaceExpr._cover_plate
		plate.set_surface_override_material(s, FaceExpr.plate_cover(egg.mesh.surface_get_material(0)))
	return FaceExpr.build_wood_sticker(h, egg, c, FaceExpr.WOOD_SIZE, mat) != null


func _meshes(n: Node) -> Array:
	var r: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		r.append(n)
	for c in n.get_children():
		r += _meshes(c)
	return r


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.075, 0.062, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.46)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.94, 0.86)
	key.rotation_degrees = Vector3(-28.0, 24.0, 0.0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.rotation_degrees = Vector3(-10.0, -40.0, 0.0)
	add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.58
	cam.position = Vector3(0.0, 0.0, 3.0)
	add_child(cam)
	cam.make_current()
	cam.size *= far
	if zoom >= 0:
		cam.size = 0.42
		cam.position = Vector3((zoom % 4 - 1.5) * DX, (1 - zoom / 4) * DY, 3.0)
