## Перф-проба площадки (res://scenes/playground.tscn как есть, куклы стоят): vsync off, FPS по секундам,
## средний TIME_PROCESS после 1 с, число объектов/примитивов/draw calls. Нужна для подбора настроек рендера.
## Запуск: godot --path . --resolution 1920x1080 --position 100,100 res://tests/perf_probe.tscn -- "secs=8,ssao=0,scene=workshop"
## scene=ruins|workshop|void — площадка (playground.tscn / playground_workshop.tscn / playground_void.tscn); арена — pg.arena
## (у всех трёх есть Environment и Sun). min_fps=N — exit 1, если средний FPS после 1 с ниже N (по умолчанию 0 — без проверки);
## итог печатается строкой «PERF scene=… avg_fps=… min_sec_fps=…».
## Переключатели одной строкой (−1 = не трогать): secs, scale (scaling_3d_scale), fsr (0 bilinear/1 FSR1/2 FSR2),
## msaa (0..3), ssaa (0/1 FXAA), ssao/glow/omni/shadow (0/1: SSAO, glow, OmniLight3D факелов, тени солнца),
## soft (качество мягких теней 0..5), atlas (размер атласа теней), splits (0..2: 1/2/4 сплита),
## ssaoq (качество SSAO 0..4), bicubic (апскейл glow 0/1), orange (дальность факелов, м),
## sdfgi/ssil/fog/vfog/dof (0/1: SDFGI, SSIL, depth fog, объёмный туман, DOF camera_attributes — окружение v3 ruins_env.tres).
## HIT_FX (29.09): hitfx=1 — нагрузка эффектами (HIT_FX.md §5.5): после 2 с heavy каждую секунду и crit каждые 3 с (настоящий
## Match.on_hit с тестовым переключателем Match.hit_tiers.force_next; жертвы чередуются, hp возвращается к 100 — без KO). Время и FPS в
## этом режиме и всегда — по реальным часам (Time.get_ticks_usec), не по delta: slow-mo крита иначе завышал бы FPS. min_sec_fps_hitfx=N —
## exit 1, если худшее секундное окно ниже N. Пишет load average; при load > числа ядер — WARN (чужая нагрузка), не провал.
## Покраска (BODY_PAINT.md §8, 30.09): paint=1 — сразу после сборки кукол каждая ModularDoll площадки красится целиком публичным API
## (как «full» замера §8): на каждой красимой детали ensure_paint → fill + раскраска PaintLayer.KINDS по кругу (seed 1000 + k),
## stickers=N наклеек на деталь (по умолчанию 3: первая — фикстура tests/fixtures/paint/sticker_fixture.png через KitImages,
## остальные — «stencil:star»), фото фикстуры на плашку лица головы. Обычные куклы doll.tscn (Doll, не ModularDoll) не красятся —
## на ruins/workshop/void обе такие (painted=0/2). Строка «PAINT {…}» и поле «paint=1 painted=N/M» в PERF — только при paint=1:
## без него вывод прежний байт в байт.
## Godot запускать нативно (arm64 → Metal): x86_64-обёртки (например /usr/local/bin/timeout) тянут Rosetta → MoltenVK.
extends Node3D
var t := 0.0
var frames := 0
var sec_frames := 0
var sec_t := 0.0
var secs := 6.0
var pg: Node3D
var scene_id := "ruins"
const SCENES := {"ruins": "res://scenes/playground.tscn", "workshop": "res://scenes/playground_workshop.tscn", "void": "res://scenes/playground_void.tscn", "null_hall": "res://scenes/playground_null_hall.tscn"}
var rows: Array = []
var tp_sum := 0.0
var tp_n := 0
var gpu_sum := 0.0
var cpu_sum := 0.0
var min_fps := 0.0
var fps_frames := 0
var fps_time := 0.0
var min_sec_fps := INF
var hitfx := false
const WARMUP_FRAMES := 30
var warm := 0
var hit_n := 0
var next_hit_s := 2.0
var min_sec_fps_req := 0.0
var _last_us := 0
var match_node: Match
var hits_done := {"heavy": 0, "crit": 0}
const PAINT_FIXTURE := "res://tests/fixtures/paint/sticker_fixture.png"
var paint := false
var paint_stickers := 3
var paint_info := {}
func _ready() -> void:
	var scale := 1.0
	var msaa := -1
	var ssaa := -1
	var ssao := -1
	var glow := -1
	var omni := -1
	var shadow := -1
	var soft := -1
	var atlas := -1
	var splits := -1
	var ssaoq := -1
	var bicubic := -1
	var orange := -1.0
	var fsr := -1
	var sdfgi := -1
	var ssil := -1
	var fog := -1
	var vfog := -1
	var dof := -1
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2: continue
			match p[0]:
				"secs": secs = float(p[1])
				"scale": scale = float(p[1])
				"msaa": msaa = int(p[1])
				"ssaa": ssaa = int(p[1])
				"ssao": ssao = int(p[1])
				"glow": glow = int(p[1])
				"omni": omni = int(p[1])
				"shadow": shadow = int(p[1])
				"soft": soft = int(p[1])
				"atlas": atlas = int(p[1])
				"splits": splits = int(p[1])
				"ssaoq": ssaoq = int(p[1])
				"bicubic": bicubic = int(p[1])
				"orange": orange = float(p[1])
				"fsr": fsr = int(p[1])
				"sdfgi": sdfgi = int(p[1])
				"ssil": ssil = int(p[1])
				"fog": fog = int(p[1])
				"vfog": vfog = int(p[1])
				"dof": dof = int(p[1])
				"scene": scene_id = p[1]
				"min_fps": min_fps = float(p[1])
				"hitfx": hitfx = p[1] != "0"
				"min_sec_fps_hitfx": min_sec_fps_req = float(p[1])
				"paint": paint = p[1] != "0"
				"stickers": paint_stickers = int(p[1])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	get_viewport().scaling_3d_scale = scale
	if msaa >= 0: get_viewport().msaa_3d = msaa
	if ssaa >= 0: get_viewport().screen_space_aa = ssaa
	pg = load(SCENES.get(scene_id, SCENES["ruins"])).instantiate()
	match_node = pg.get_node_or_null("Match") as Match
	if hitfx and match_node != null:
		match_node.countdown_s = 0.0
	add_child(pg)
	_last_us = Time.get_ticks_usec()
	pg.get_node("P1").external_input = true
	pg.get_node("P2").external_input = true
	if paint:   # куклы уже собраны (add_child); время покраски уходит в кадры прогрева
		paint_info = paint_dolls(pg, paint_stickers)
		print("PAINT ", JSON.stringify(paint_info))
	var arena: Node = pg.get("arena")
	var we: WorldEnvironment = arena.get_node("Environment")
	var env: Environment = we.environment.duplicate()
	we.environment = env
	if ssao >= 0: env.ssao_enabled = ssao == 1
	if sdfgi >= 0: env.sdfgi_enabled = sdfgi == 1
	if ssil >= 0: env.ssil_enabled = ssil == 1
	if fog >= 0: env.fog_enabled = fog == 1
	if vfog >= 0: env.volumetric_fog_enabled = vfog == 1
	if dof >= 0:
		var ca := we.camera_attributes as CameraAttributesPractical
		if ca != null: ca.dof_blur_far_enabled = dof == 1
	if glow >= 0: env.glow_enabled = glow == 1
	if omni >= 0:
		for l in pg.find_children("*", "OmniLight3D", true, false):
			l.visible = omni == 1
	if shadow >= 0: arena.get_node("Sun").shadow_enabled = shadow == 1
	if soft >= 0: RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	if atlas >= 0: RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	if splits >= 0: arena.get_node("Sun").directional_shadow_mode = splits
	if ssaoq >= 0: RenderingServer.environment_set_ssao_quality(ssaoq, true, 0.5, 2, 50.0, 300.0)
	if bicubic >= 0: RenderingServer.environment_glow_set_use_bicubic_upscale(bicubic == 1)
	if orange > 0.0:
		for l in pg.find_children("*", "OmniLight3D", true, false):
			l.omni_range = orange
	if fsr >= 0: get_viewport().scaling_3d_mode = fsr
	print("window=", DisplayServer.window_get_size(), " visible=", get_viewport().get_visible_rect().size, " texture=", get_viewport().get_texture().get_size(), " screen_scale=", DisplayServer.screen_get_scale(), " max_scale=", DisplayServer.screen_get_max_scale(), " msaa=", get_viewport().msaa_3d, " ssaa=", get_viewport().screen_space_aa, " driver=", RenderingServer.get_current_rendering_driver_name(), " method=", RenderingServer.get_current_rendering_method())
## Удар как DollCombat._deliver (take_damage → apply_knockback → ImpactFx → Match.on_hit), из физики.
func _physics_process(_d: float) -> void:
	if not hitfx or match_node == null or t < next_hit_s:
		return
	next_hit_s += 1.0
	hit_n += 1
	var crit := hit_n % 3 == 0
	var v := pg.get_node("P2" if hit_n % 2 == 0 else "P1") as Doll
	var a := pg.get_node("P1" if hit_n % 2 == 0 else "P2") as Doll
	if not v.alive or not v.can_take_damage():
		return
	v.hp = 100.0
	var part := v.parts["Head" if crit else "Torso"] as RigidBody3D
	var dir := Vector3(signf(v.centre_of_mass().x - a.centre_of_mass().x), 0.35, 0.0).normalized()
	var pos := part.global_position - dir * 0.12
	match_node.hit_tiers.force_next = "crit" if crit else "heavy"
	v.hit_meta = {"dir": dir, "striker_name": "Hand_R"}
	var dmg := 24.0 if crit else 12.0
	v.take_damage(dmg, a, part.name, pos, -dir, "head" if crit else "body")
	v.apply_knockback(Damage.knockback_dir(dir) * 3.0 * v.total_mass, v.torso(), 0.3, dir)
	ImpactFx.spawn_impact(match_node, pos, -dir, 4.0 + dmg * 0.4, "head" if crit else "body")
	match_node.on_hit(v, a, dmg, "head" if crit else "body", pos, 1, false, "", 7.0)
	hits_done["crit" if crit else "heavy"] += 1


func _process(_delta: float) -> void:
	var now_us := Time.get_ticks_usec()
	var delta := float(now_us - _last_us) / 1e6
	_last_us = now_us
	if warm < WARMUP_FRAMES:   # первые кадры — загрузка и компиляция пайплайнов (под чужой нагрузкой до 10+ с), не рендер
		warm += 1
		return
	t += delta
	frames += 1
	sec_frames += 1
	sec_t += delta
	if t > 1.0:
		fps_frames += 1
		fps_time += delta
		tp_sum += Performance.get_monitor(Performance.TIME_PROCESS); tp_n += 1
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
	if sec_t >= 1.0:
		rows.append("t=%.0f fps=%.1f" % [t, sec_frames / sec_t])
		if t > 1.5:
			min_sec_fps = minf(min_sec_fps, sec_frames / sec_t)
		sec_frames = 0; sec_t = 0.0
	if t >= secs:
		print(" | ".join(rows), " | avg TIME_PROCESS after 1s: %.2f ms" % (tp_sum / max(tp_n, 1) * 1000.0), " gpu=%.2f ms cpu=%.2f ms" % [gpu_sum / max(tp_n, 1), cpu_sum / max(tp_n, 1)], " | objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " draw=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var avg_fps := fps_frames / maxf(fps_time, 0.001)
		var ok := avg_fps >= min_fps
		var la: Array = []
		OS.execute("/usr/sbin/sysctl", ["-n", "vm.loadavg"], la)
		var load_s := (String(la[0]) if la.size() > 0 else "").strip_edges().replace("{ ", "").replace(" }", "")
		var load1 := float(load_s.split(" ")[0]) if load_s != "" else 0.0
		var busy := load1 > float(OS.get_processor_count())
		if hitfx:
			var fx_ok := min_sec_fps >= min_sec_fps_req
			if not fx_ok and busy:
				print("WARN hitfx: min_sec_fps %.1f < %.1f under foreign load %.1f > %d cores — not a failure" % [min_sec_fps, min_sec_fps_req, load1, OS.get_processor_count()])
			elif not fx_ok:
				ok = false
			if busy and avg_fps < min_fps:
				print("WARN hitfx: avg_fps %.1f < %.1f under foreign load — not a failure" % [avg_fps, min_fps])
				ok = true
		var paint_s: String = " paint=1 painted=%d/%d" % [int(paint_info.get("painted", 0)), int(paint_info.get("dolls", 0))] if paint else ""
		print("PERF scene=%s%s hitfx=%s hits=%s avg_fps=%.1f min_sec_fps=%.1f min_fps=%.1f load=[%s] cores=%d %s" % [scene_id, paint_s, str(hitfx), str(hits_done), avg_fps, min_sec_fps, min_fps, load_s, OS.get_processor_count(), "OK" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)


## paint=1: все ModularDoll под root — краска на каждой красимой детали (fill + раскраска), n_stickers наклеек на деталь, фото на
## плашку лица. Только публичный API (ModularDoll.ensure_paint / add_sticker, BodyPaint.set_face, KitImages); детерминировано.
## {dolls, painted, layers, stickers, sticker_misses, faces, ms, skipped: [имена кукол Doll без чертежа — не красятся]}.
static func paint_dolls(root: Node, n_stickers: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var fixture := KitImages.import_file(ProjectSettings.globalize_path(PAINT_FIXTURE))
	var face_tex := KitImages.texture(fixture)
	var info := {"dolls": 0, "painted": 0, "layers": 0, "stickers": 0, "sticker_misses": 0, "faces": 0, "ms": 0.0, "skipped": [],
		"fixture": fixture}
	var k := 0
	for n in root.find_children("*", "", true, false):
		if not n is Doll:
			continue
		info["dolls"] += 1
		var d := n as ModularDoll
		if d == null or d.blueprint == null:
			(info["skipped"] as Array).append(String(n.name))
			continue
		info["painted"] += 1
		for node in d.blueprint.nodes:
			var uid := String(node.get("uid", ""))
			var mroot := BodyPaint.mesh_root_of(d, uid)
			if mroot == null:
				continue
			if face_tex != null and BodyPaint.set_face(mroot, face_tex):
				info["faces"] += 1
			if not _paintable(mroot):
				continue
			var h := d.ensure_paint(uid)
			if h.is_empty():
				continue
			var layer: PaintLayer = h["layer"]
			layer.fill(Color.from_hsv(fmod(0.13 * k, 1.0), 0.6, 0.85))
			layer.pattern(PaintLayer.KINDS[k % PaintLayer.KINDS.size()], [], 1000 + k)
			layer.update_texture(h["tex"])
			info["layers"] += 1
			for j in n_stickers:
				var xf: Variant = _sticker_xf(mroot, (j + 1.0) / (n_stickers + 1.0))
				if xf == null:
					info["sticker_misses"] += 1
					continue
				var st := {"img": fixture if j == 0 else "stencil:star", "xf": xf,
					"size": Vector2(0.09, 0.06) if j == 0 else Vector2(0.07, 0.07),
					"color": Color.WHITE if j == 0 else Color.from_hsv(fmod(0.29 * (k + j), 1.0), 0.8, 1.0)}
				if d.add_sticker(uid, st) != null:
					info["stickers"] += 1
			k += 1
	info["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	return info


## Есть поверхность, которую красит attach_layer (не Shirt* / Face*).
static func _paintable(mroot: Node3D) -> bool:
	for mi in BodyPaint.meshes(mroot):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			if not BodyPaint.is_protected(BodyPaint.surface_material(m, s)):
				return true
	return false


## Кадр наклейки в кадре корня меша: луч −Z (к кукле спереди) в точку доли u вдоль длинной оси (X / Y) лицевой грани габарита;
## Y кадра — нормаль наружу, −Z — верх картинки (+Y корня). null — луч не попал в меш.
static func _sticker_xf(mroot: Node3D, u: float) -> Variant:
	var box := BodyPaint.mesh_aabb(mroot)
	var p := box.get_center()
	if box.size.y >= box.size.x:
		p.y = box.position.y + box.size.y * u
	else:
		p.x = box.position.x + box.size.x * u
	var from := Vector3(p.x, p.y, box.end.z + 0.05)
	var best_d := INF
	var best: Array = []
	var inv_root := mroot.global_transform.affine_inverse()
	for mi in BodyPaint.meshes(mroot):
		var m := mi as MeshInstance3D
		var tm := m.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var rel := inv_root * m.global_transform   # кадр меша → кадр корня
		var inv := rel.affine_inverse()
		var hit := tm.intersect_ray(inv * from, (inv.basis * Vector3.FORWARD).normalized())
		if hit.is_empty():
			continue
		var hp: Vector3 = rel * (hit["position"] as Vector3)
		if from.z - hp.z < best_d:
			best_d = from.z - hp.z
			var nrm := (rel.basis.inverse().transposed() * (hit["normal"] as Vector3)).normalized()
			best = [hp, nrm if nrm.z >= 0.0 else -nrm]
	if best.is_empty():
		return null
	var y: Vector3 = best[1]
	var up := Vector3.UP - y * Vector3.UP.dot(y)
	if up.length() < 1e-3:
		up = Vector3.BACK - y * Vector3.BACK.dot(y)
	var z := -up.normalized()
	return Transform3D(Basis(y.cross(z).normalized(), y, z), best[0])
