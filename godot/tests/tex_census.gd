## Перепись текстур сцены по зависимостям (docs/plan-demo/PERF_PASS.md §4, §8): сколько памяти держит каждая арена, по группам и форматам.
##   godot --headless --path . -s res://tests/tex_census.gd [-- "scenes=ruins,scrap,null_hall,workshop_build"]
## Байты — размер данных образа (сжатые форматы — как есть, несжатые — с мипмапами ×1.33), без рендера и окна.
extends SceneTree

const SCENES := {
	"ruins": "res://scenes/playground.tscn", "workshop_arena": "res://scenes/playground_workshop.tscn", "scrap": "res://scenes/playground_scrap.tscn",
	"void": "res://scenes/playground_void.tscn", "workshop_build": "res://scenes/workshop/workshop_build.tscn", "null_hall": "res://scenes/playground_null_hall.tscn",
	"pve": "res://scenes/playground_pve.tscn"}
const FORMAT_NAMES := {4: "RGB8", 5: "RGBA8", 17: "DXT1", 18: "DXT3", 19: "DXT5", 20: "RGTC_R", 21: "RGTC_RG", 22: "BPTC_RGBA"}


func _deps(path: String, seen: Dictionary) -> void:
	if seen.has(path):
		return
	seen[path] = true
	for d in ResourceLoader.get_dependencies(path):
		var parts := String(d).split("::")
		var p := parts[2] if parts.size() >= 3 else parts[0]
		if parts.size() >= 3 and p == "":
			p = parts[0]
		if p.begins_with("uid://"):
			var id := ResourceUID.text_to_id(p)
			if ResourceUID.has_id(id):
				p = ResourceUID.get_id_path(id)
		if p != "" and p.begins_with("res://"):
			_deps(p, seen)


func _group(p: String) -> String:
	var seg := p.trim_prefix("res://assets/").split("/")
	if seg.size() >= 3 and seg[0] == "models":
		return "models/" + seg[1] + ("/" + seg[2] if seg[1] == "heroes" else "")
	return "/".join(seg.slice(0, mini(2, seg.size() - 1)))


func _init() -> void:
	var want: PackedStringArray = SCENES.keys()
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "scenes":
				want = p[1].split("+")
	var mb := 1.0 / 1048576.0
	for key in want:
		if not SCENES.has(key):
			continue
		var seen := {}
		_deps(SCENES[key], seen)
		var by_group := {}
		var by_fmt := {}
		var tot := 0
		var n := 0
		var rows: Array = []
		for p in seen.keys():
			var ext := String(p).get_extension().to_lower()
			if ext not in ["png", "jpg", "jpeg", "webp", "exr", "ctex"]:
				continue
			var t := load(p) as Texture2D
			if t == null:
				continue
			var img := t.get_image()
			if img == null:
				continue
			var bytes := img.get_data().size()
			if not img.has_mipmaps():
				bytes = int(bytes * 1.33)
			tot += bytes
			n += 1
			var g := _group(p)
			by_group[g] = int(by_group.get(g, 0)) + bytes
			var f := String(FORMAT_NAMES.get(img.get_format(), str(img.get_format())))
			by_fmt[f] = int(by_fmt.get(f, 0)) + bytes
			rows.append([bytes, p, img.get_width(), img.get_height(), f])
		print("TEXCENSUS %s: %d текстур, %.0f МБ" % [key, n, tot * mb])
		var gk: Array = by_group.keys()
		gk.sort_custom(func(a, b): return int(by_group[a]) > int(by_group[b]))
		var parts: PackedStringArray = []
		for g in gk.slice(0, 7):
			parts.append("%s %.0f" % [g, int(by_group[g]) * mb])
		print("   по группам (МБ): ", ", ".join(parts))
		var fp: PackedStringArray = []
		for f in by_fmt:
			fp.append("%s %.0f" % [f, int(by_fmt[f]) * mb])
		print("   по форматам (МБ): ", ", ".join(fp))
		rows.sort_custom(func(a, b): return a[0] > b[0])
		for r in rows.slice(0, 5):
			print("   %5.1f МБ  %dx%d  %s  %s" % [r[0] * mb, r[2], r[3], r[4], r[1]])
	quit()
