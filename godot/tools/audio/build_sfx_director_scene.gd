## Собирает scenes/audio/sfx_director.tscn (docs/plan-demo/AUDIO.md §4.2): узел SfxDirector (scripts/audio/sfx_director.gd),
## VOICES голосов AudioStreamPlayer (Voice00…) и слои — AudioStreamRandomizer из папок assets/audio/sfx/<слой>/*.ogg и
## assets/audio/ui/<слой>/*.ogg (питч ±6 %, громкость ±1.5 dB, без повторов подряд). Звуки добавляются файлом в папку слоя:
##   python3 godot/tools/audio/build_audio.py   (ассеты) → godot --headless --path godot --import
##   godot --headless --path godot -s res://tools/audio/build_sfx_director_scene.gd
extends SceneTree

const OUT := "res://scenes/audio/sfx_director.tscn"
const DirectorScript := preload("res://scripts/audio/sfx_director.gd")


func _init() -> void:
	var root := Node.new()
	root.name = "SfxDirector"
	root.set_script(DirectorScript)
	var layers: Dictionary[String, AudioStreamRandomizer] = {}
	var total := 0
	for layer in SfxDirector.LAYER_ORDER:
		var rs := SfxDirector.make_layer(layer)
		if rs.streams_count == 0:
			push_error("sfx: слой %s пуст (%s)" % [layer, SfxDirector.layer_dir(layer)])
			continue
		layers[layer] = rs
		total += rs.streams_count
		print("  %-12s %d" % [layer, rs.streams_count])
	root.set("layers", layers)
	for i in range(SfxDirector.VOICES):
		var p := AudioStreamPlayer.new()
		p.name = "Voice%02d" % i
		root.add_child(p)
		p.owner = root
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
		err = ResourceSaver.save(ps, OUT)
	print("sfx_director: %d слоёв, %d звуков, %d голосов → %s (%s)" % [layers.size(), total, SfxDirector.VOICES, OUT, error_string(err)])
	root.free()
	quit(0 if err == OK and layers.size() == SfxDirector.LAYER_ORDER.size() else 1)
