## Фон арены (docs/plan-demo/AUDIO.md §4.7): петли на шине Ambience, редкие далёкие звуки (лязг, скрип) в случайной точке арены,
## реверберация SFX (GameAudio.set_room) и материал пола (SoundMaterial.ground). Ребёнок Match (Match._ensure_fx_directors).
## Арена — по классу узла сцены (ScrapArena / RuinsArena / WorkshopArena / VoidArena), иначе пресет "default".
## Музыка: на входе в бой GameAudio.play_context("fight"), на выходе — "" (затухание; следующая арена продолжит тот же трек).
class_name ArenaAmbience
extends Node

const GROUP := "arena_ambience"
const DIR := "res://assets/audio/amb/"
## loops: [[файл, дБ]], room: пресет GameAudio.ROOMS, ground: SoundMaterial.ground, shots: [[слой, мин_с, макс_с, дБ]].
const PRESETS := {
	"scrap": {"loops": [["scrap_wind", -1.0], ["scrap_industrial", -5.0]], "room": "dome", "ground": "dirt",
		"shots": [["amb_clank", 5.0, 13.0, -9.0], ["amb_creak", 8.0, 18.0, -11.0]]},
	"ruins": {"loops": [["ruins_wind", -1.0]], "room": "hall", "ground": "stone", "shots": [["amb_creak", 11.0, 24.0, -13.0]]},
	"workshop": {"loops": [["workshop_room", 0.0]], "room": "room", "ground": "wood", "shots": [["amb_creak", 10.0, 22.0, -15.0]]},
	"void": {"loops": [["void_drone", 0.0]], "room": "void", "ground": "stone", "shots": []},
	"default": {"loops": [["ruins_wind", -4.0]], "room": "hall", "ground": "stone", "shots": []},
}
const BUS := "Ambience"

var arena := ""
var music := true                       # бой ведёт музыку (пробы выключают)
var shots_played: Array = []            # [{ms, layer}]

var _loops: Array[AudioStreamPlayer] = []
var _shot_player: AudioStreamPlayer3D
var _shot_rs: Dictionary = {}
var _next_shot: Dictionary = {}         # слой -> мс
var _rng := RandomNumberGenerator.new()
var _bounds := AABB(Vector3(-10, 0, 0), Vector3(20, 8, 0.1))


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	SfxDirector.ensure_buses()
	call_deferred("_start")


func _exit_tree() -> void:
	var ga := get_node_or_null("/root/GameAudio")
	if ga != null and music:
		ga.play_context("")


static func detect(root: Node) -> Array:
	if root == null:
		return ["default", null]
	for n in root.find_children("*", "Node3D", true, false):
		if n is ScrapArena:
			return ["scrap", n]
		if n is RuinsArena:
			return ["ruins", n]
		if n is WorkshopArena:
			return ["workshop", n]
		if n is VoidArena:
			return ["void", n]
	return ["default", null]


func _start() -> void:
	var root := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	var found := detect(root)
	var node: Variant = found[1]
	if node != null and (node as Node).has_method("bounds"):
		var b: Variant = (node as Node).call("bounds")
		if b is AABB:
			_bounds = b
	start_preset(String(found[0]))


## Включает пресет арены (петли, разовые, реверберация, пол; музыка боя — если music). Прежние петли снимаются (звуковая доска).
func start_preset(name_: String) -> void:
	for pl in _loops:
		pl.queue_free()
	_loops.clear()
	if _shot_player != null:
		_shot_player.queue_free()
		_shot_player = null
	_shot_rs.clear()
	_next_shot.clear()
	arena = name_ if PRESETS.has(name_) else "default"
	var p: Dictionary = PRESETS[arena]
	SoundMaterial.ground = String(p["ground"])
	var ga := get_node_or_null("/root/GameAudio")
	if ga != null:
		ga.set_room(String(p["room"]))
		if music:
			ga.play_context("fight")
	for l in p["loops"]:
		var pl := AudioStreamPlayer.new()
		pl.name = "Amb_" + String(l[0])
		pl.bus = BUS
		var s := load(DIR + String(l[0]) + ".ogg") as AudioStream
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		pl.stream = s
		pl.volume_db = float(l[1])
		add_child(pl)
		_loops.append(pl)
		if s != null:
			pl.play(_rng.randf_range(0.0, maxf(s.get_length() - 1.0, 0.0)))
	_shot_player = AudioStreamPlayer3D.new()
	_shot_player.name = "AmbShot"
	_shot_player.bus = BUS
	_shot_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_shot_player.panning_strength = 0.8
	add_child(_shot_player)
	var now := Time.get_ticks_msec()
	for sh in p["shots"]:
		var layer := String(sh[0])
		_shot_rs[layer] = CrowdDirector._make_layer_at(DIR + layer)
		_next_shot[layer] = now + _rng.randf_range(float(sh[1]), float(sh[2])) * 1000.0


func _process(_dt: float) -> void:
	if arena == "" or _shot_player == null:
		return
	var now := Time.get_ticks_msec()
	for sh in PRESETS[arena]["shots"]:
		var layer := String(sh[0])
		if now < float(_next_shot.get(layer, 1.0e18)):
			continue
		_next_shot[layer] = now + _rng.randf_range(float(sh[1]), float(sh[2])) * 1000.0
		var rs: AudioStreamRandomizer = _shot_rs.get(layer, null)
		if rs == null or rs.streams_count == 0 or _shot_player.playing:
			continue
		var x := _rng.randf_range(_bounds.position.x, _bounds.end.x)
		var y := _rng.randf_range(_bounds.position.y + _bounds.size.y * 0.4, _bounds.end.y)
		_shot_player.global_position = Vector3(x, y, -6.0)
		_shot_player.stream = rs
		_shot_player.volume_db = float(sh[3])
		_shot_player.pitch_scale = _rng.randf_range(0.85, 1.1)
		_shot_player.play()
		shots_played.append({"ms": now, "layer": layer})


func loops_playing() -> int:
	var n := 0
	for p in _loops:
		if p.playing:
			n += 1
	return n
