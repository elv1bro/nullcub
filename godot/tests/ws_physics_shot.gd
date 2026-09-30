## Кадр Physics Overlay (scenes/workshop/ws_physics.gd): пресеты рядом в мастерской (арена scenes/arena/workshop.tscn — свет и пол как
## у стенда), заморожены в позе стенда, поверх — полноэкранный Control, в его _draw — WsPhysics.draw каждой куклы. Смотреть глазами:
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 --path . --resolution 1920x1080 \
##       res://tests/ws_physics_shot.tscn -- "out=/abs/ws_physics.png" ["presets=kit_human,kit_spinner,flail"] ["labels=0"] ["t=0.35"]
##       ["dist=5.2"] ["x=5.6"] ["focus=1"]
##   x — середина ряда (м, по полу мастерской; 5.6 — место стенда), focus — камера напротив куклы с этим номером (крупный план:
##   "focus=2 dist=3"), cy — высота камеры (м), crop=x,y,w,h — ещё и вырезка кадра ×2 рядом (<out>_crop.png), чтобы разглядеть
##   точки и бирки; tip=<номер> — у этой куклы всё, кроме голеней и стоп, сдвинуто вбок за
##   опору (состояние «опрокинется»: красные опора, засечка и стрелка — у пресетов его нет, в мастерской — кривая сборка);
##   ghost=<номер> — у какой куклы призрак центра масс (по умолчанию 0, -1 — ни у какой).
## По умолчанию: kit_human (с призраком центра масс — как при протяжке детали), kit_spinner (свободные шарниры с булавами) и flail
## (перегруженное запястье — красный пульс, крен влево — стрелка), бирки включены. Код выхода 0 — кадр записан.
extends Node3D

const ARENA := "res://scenes/arena/workshop.tscn"
const PRESET_DIR := "res://scenes/body/presets/"
## Поза стенда — как WorkshopBuild.POSE_GROUPS.
const POSE_GROUPS := ["Neck", "Shoulder", "Elbow", "Hip", "Knee", "Wrist", "Ankle"]
const SPACING := 2.35
const WARM_FRAMES := 12

var out_path := ""
var presets: PackedStringArray = ["kit_human", "kit_spinner", "flail"]
var labels := true
var t_anim := 0.35
var dist := 5.2
var center_x := 5.6
var focus := -1
var cam_y := 1.0
var crop := Rect2i()
var tipped := -1
var ghost := 0
var dolls: Array = []
var cam: Camera3D
var overlay: Control


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"out": out_path = kv[1]
			"presets": presets = kv[1].split(",", false)
			"labels": labels = kv[1] != "0"
			"t": t_anim = float(kv[1])
			"dist": dist = float(kv[1])
			"x": center_x = float(kv[1])
			"focus": focus = int(kv[1])
			"cy": cam_y = float(kv[1])
			"tip": tipped = int(kv[1])
			"ghost": ghost = int(kv[1])
			"crop":
				var c := kv[1].split_floats(",")
				if c.size() == 4:
					crop = Rect2i(int(c[0]), int(c[1]), int(c[2]), int(c[3]))
	var arena := (load(ARENA) as PackedScene).instantiate()
	add_child(arena)
	for n in ["Props", "Right"]:   # бочки / ящики катятся, верстак справа заслоняет крайнюю куклу — кадр про слой, не про комнату
		var c := arena.get_node_or_null(n) as Node3D
		if c != null:
			c.visible = false
			c.process_mode = Node.PROCESS_MODE_DISABLED
	var x0 := center_x - SPACING * (presets.size() - 1) * 0.5
	for i in presets.size():
		dolls.append(_stand(load(PRESET_DIR + presets[i] + ".tscn") as PackedScene, Vector3(x0 + SPACING * i, 0.0, 0.0)))
	if tipped >= 0 and tipped < dolls.size():
		for b in ((dolls[tipped] as Node).get("parts") as Dictionary).values():
			var base := ModularDoll.base_name(String((b as Node).name))
			if base != "Foot" and base != "LowerLeg":
				(b as Node3D).global_position += Vector3(0.8, 0.0, 0.0)
	cam = Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	var cx := x0 + SPACING * focus if focus >= 0 and focus < presets.size() else center_x
	cam.global_position = Vector3(cx, cam_y, dist)
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	for i in WARM_FRAMES:
		await get_tree().process_frame
	overlay.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var code := 0
	if out_path != "":
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(out_path)
		print("ws_physics_shot: %s -> %s" % [out_path, error_string(err)])
		code = 0 if err == OK else 1
		if crop.size.x > 0 and crop.size.y > 0:
			var part := img.get_region(crop)
			part.resize(crop.size.x * 2, crop.size.y * 2, Image.INTERPOLATE_BILINEAR)
			var cp := out_path.get_basename() + "_crop.png"
			print("ws_physics_shot: %s -> %s" % [cp, error_string(part.save_png(cp))])
	for d: Node3D in dolls:
		print("  %-12s %s" % [d.name, WsPhysics.summary(d)])
	get_tree().quit(code)


## Кукла как на стенде мастерской (WorkshopBuild._rebuild_stand): поза стенда, тела заморожены, пути суставов обнулены.
func _stand(ps: PackedScene, at: Vector3) -> Node3D:
	var d := ps.instantiate() as Node3D
	d.set("external_input", true)
	d.set("control_enabled", false)
	d.position = at
	add_child(d)
	if d.has_method("_snap_pose"):
		d.call("_snap_pose", POSE_GROUPS)
	for b in (d.get("parts") as Dictionary).values():
		var rb := b as RigidBody3D
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
	for j in (d.get("joints") as Dictionary).values():
		(j as Generic6DOFJoint3D).node_a = NodePath()
		(j as Generic6DOFJoint3D).node_b = NodePath()
	return d


func _draw_overlay() -> void:
	var font := overlay.get_theme_default_font()
	for i in dolls.size():
		var d: Node3D = dolls[i]
		var opts := {"t": t_anim, "labels": labels, "floor_y": 0.0}
		if i == ghost:
			opts["ghost_com"] = WsPhysics.com(d) + Vector3(0.14, 0.07, 0.0)   # как при протяжке детали на правый бок
		WsPhysics.draw(overlay, cam, d, font, opts)
