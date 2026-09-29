## Процедурный параллакс: элементы (башни, краны, цепи…) расставляются квадами на СЛУЧАЙНОЙ глубине внутри полос
## (ParallaxScatterBand), перспективная камера даёт непрерывный параллакс — не 4–5 ступенек, как у сплошных слоёв.
## Ширина покрытия считается из диапазона игровой камеры (cam_points, fov, аспект): элементы идут от левого до правого
## края того, что камера может увидеть на дальней глубине полосы. Раскладка детерминирована seed'ом полосы.
## Небо и дальний сплошной фон остаются слоями (parallax_scrap_v2.tscn), сюда — средний и передний планы.
## Подробно — docs/plan-demo/PARALLAX.md.
class_name ParallaxScatter3D
extends Node3D

## Шейдер грузится в rebuild(), а не preload-константой: константа class_name-скрипта держит его до выхода из
## движка («RID … DummyShader leaked at exit» в headless-пробах).
const SHADER_PATH := "res://scenes/arena/parallax_element.gdshader"

@export var bands: Array[ParallaxScatterBand] = []
@export var cam_fov := 45.0
@export var cam_aspect := 16.0 / 9.0
## Крайние точки игровой камеры (x, y, z). По умолчанию — Свалка: зум z 10..24, клэмп центра по x арены ±20 м.
@export var cam_points := PackedVector3Array([
	Vector3(-13, 2.5, 10), Vector3(13, 10, 10), Vector3(-8.5, 2.5, 16), Vector3(8.5, 10, 16),
	Vector3(-5.5, 2.5, 20), Vector3(5.5, 10, 20), Vector3(-2.5, 2.5, 24), Vector3(2.5, 10, 24)])
@export var cover_margin := 2.0

## Что расставлено (для тестов и отладки): band, file, anchor, fill, x, y, z, w, h, flip, haze.
var placements: Array[Dictionary] = []
var _shader: Shader


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for c in get_children():
		if c.has_meta("scatter"):
			remove_child(c)
			c.queue_free()
	placements.clear()
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	for i in bands.size():
		if bands[i] != null:
			_build_band(i, bands[i])


## Мировой отрезок x, который камера может увидеть на глубине z (с запасом cover_margin).
func x_extent(z: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for c in cam_points:
		var hw := tan(deg_to_rad(cam_fov / 2.0)) * (c.z - z) * cam_aspect
		lo = minf(lo, c.x - hw)
		hi = maxf(hi, c.x + hw)
	return Vector2(lo - cover_margin, hi + cover_margin)


func _build_band(bi: int, b: ParallaxScatterBand) -> void:
	var elems := _load_elements(b)
	if elems.is_empty():
		push_warning("ParallaxScatter3D: полоса %d — нет элементов в %s" % [bi, b.dir])
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = b.seed
	var ext := x_extent(b.z_range.x)
	var mats := {}
	var bag: Array[int] = []
	var last := -1
	var x := ext.x - rng.randf_range(0.0, maxf(b.gap_m.y, 0.0))
	while x < ext.y:
		# мешок без повторов подряд: каждый элемент выходит раз за круг
		if bag.is_empty():
			for k in elems.size():
				bag.append(k)
			for k in range(bag.size() - 1, 0, -1):  # Фишер — Йетс своим rng (Array.shuffle — глобальный, недетерминирован)
				var j := rng.randi_range(0, k)
				var tmp := bag[k]
				bag[k] = bag[j]
				bag[j] = tmp
			if bag.size() > 1 and bag[bag.size() - 1] == last:
				bag.reverse()
		var ei: int = bag.pop_back()
		last = ei
		var e: Dictionary = elems[ei]
		var h: float
		if e["m_per_px"] > 0.0:
			h = e["h"] * e["m_per_px"] * rng.randf_range(b.scale_range.x, b.scale_range.y)
		else:
			h = rng.randf_range(b.height_m.x, b.height_m.y)
		var w := h * float(e["w"]) / float(e["h"])
		var z := rng.randf_range(b.z_range.x, b.z_range.y)
		var flip := b.allow_flip and rng.randf() < 0.5
		var cy: float
		if e["anchor"] == "top":
			cy = rng.randf_range(b.top_y.x, b.top_y.y) - h / 2.0
		else:
			cy = rng.randf_range(b.base_y.x, b.base_y.y) + h / 2.0
		var t := inverse_lerp(b.z_range.x, b.z_range.y, z) if b.z_range.x != b.z_range.y else 1.0
		var hz := lerpf(b.haze.x, b.haze.y, t)
		var file: String = e["file"]
		if not mats.has(file):
			var m := ShaderMaterial.new()
			m.shader = _shader
			m.set_shader_parameter("tex", e["tex"])
			m.set_shader_parameter("haze_color", b.haze_color)
			mats[file] = m
		var q := QuadMesh.new()
		q.size = Vector2(w, h)
		var mi := MeshInstance3D.new()
		mi.name = "B%d_%s_%d" % [bi, file.get_basename(), placements.size()]
		mi.mesh = q
		mi.material_override = mats[file]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(x + w / 2.0, cy, z)
		mi.set_meta("scatter", true)
		add_child(mi)
		mi.set_instance_shader_parameter("haze", hz)
		mi.set_instance_shader_parameter("flip", 1.0 if flip else 0.0)
		mi.set_instance_shader_parameter("base_fade", b.base_fade if e["anchor"] != "top" else 0.0)
		placements.append({"band": bi, "file": file, "anchor": e["anchor"], "fill": e["fill"], "x": x + w / 2.0,
				"y": cy, "z": z, "w": w, "h": h, "flip": flip, "haze": hz, "tex_h": e["h"]})
		x += w + rng.randf_range(b.gap_m.x, b.gap_m.y)


func _load_elements(b: ParallaxScatterBand) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var path := b.dir.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return out
	for e in data.get("elements", []):
		if not b.anchors.has(e.get("anchor", "bottom")):
			continue
		var tex := load(b.dir.path_join(e["file"])) as Texture2D
		if tex == null:
			continue
		out.append({"file": e["file"], "w": float(e["w"]), "h": float(e["h"]), "anchor": e.get("anchor", "bottom"),
				"fill": float(e.get("fill", 0.5)), "m_per_px": float(e.get("m_per_px", 0.0)), "tex": tex})
	return out
