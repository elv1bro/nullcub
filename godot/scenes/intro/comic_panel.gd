## Панель страницы комикса: многоугольник в координатах страницы (3840 × 2160), в нём — кадр ComicShot площадки IntroStage.
## Пока панель «живая», в ней текстура SubViewport площадки; по окончании кадра freeze() копирует картинку, и панель
## остаётся на странице неподвижной. Надписи и эффекты — дети узла Letters (ComicLetter), время у них — время кадра.
## Узлы собирает tools/build_intro_comic.gd (раскладка страницы); форму панели можно править в редакторе (polygon).
class_name ComicPanel
extends Node2D

const PANEL_SHADER := "res://scenes/intro/shaders/comic_panel.gdshader"

## Контур панели на странице (по часовой стрелке от левого верхнего угла).
@export var polygon := PackedVector2Array()
## Номер кадра ComicShot в IntroStage (с 1).
@export var shot := 1
## Сколько секунд панель ещё держится после конца кадра (читатель дочитывает надписи).
@export var hold := 0.4
## Строка страницы (0, 1, 2) — после последней панели строки камера показывает строку целиком.
@export var row := 0
## Вспышка панели белым (время кадра, −1 — нет) и удар по странице (тряска камеры страницы).
@export var flash_at := -1.0
@export var impact_at := -1.0
@export var impact_strength := 18.0
## Звуки кадра: "время:имя[:дБ]" (assets/audio/intro/<имя>.wav), время — время кадра, громкость по умолчанию −4 дБ.
@export var sounds: PackedStringArray = PackedStringArray()
@export var frame_width := 7.0
@export var frame_color := Color(0.03, 0.025, 0.02)

var art: Polygon2D
var frame: Line2D
var letters: Node2D
var clip: Node2D
var _mat: ShaderMaterial
var _live := false
var _tex_size := Vector2.ONE


func _ready() -> void:
	art = get_node_or_null("Art") as Polygon2D
	if art == null:
		art = Polygon2D.new()
		art.name = "Art"
		add_child(art)
		move_child(art, 0)
	art.polygon = polygon
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat = ShaderMaterial.new()
	_mat.shader = load(PANEL_SHADER)
	_mat.set_shader_parameter("art_px", bbox().size)
	_mat.set_shader_parameter("seed", float(shot) * 1.37)
	_mat.set_shader_parameter("reveal", 0.0)
	art.material = _mat
	# эффекты, которые не должны вылезать за край панели (линии скорости, фокус), — дети Art/Clip
	art.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	clip = art.get_node_or_null("Clip") as Node2D
	if clip == null:
		clip = Node2D.new()
		clip.name = "Clip"
		art.add_child(clip)
	frame = get_node_or_null("Frame") as Line2D
	if frame == null:
		frame = Line2D.new()
		frame.name = "Frame"
		add_child(frame)
	frame.points = polygon
	frame.closed = true
	frame.width = frame_width
	frame.default_color = frame_color
	frame.joint_mode = Line2D.LINE_JOINT_SHARP
	frame.modulate.a = 0.0
	letters = get_node_or_null("Letters") as Node2D
	if letters == null:
		letters = Node2D.new()
		letters.name = "Letters"
		add_child(letters)
	visible = true


func bbox() -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var r := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		r = r.expand(p)
	return r


func centre() -> Vector2:
	return bbox().get_center()


## Показать живую текстуру площадки (размер текстуры = размер SubViewport).
func set_live(tex: Texture2D, tex_size: Vector2) -> void:
	_live = true
	_tex_size = tex_size
	art.texture = tex
	_update_uv()


## Застыть: копия картинки с mip-уровнями (на общем плане страницы панель уменьшена).
func freeze() -> void:
	if not _live or art.texture == null:
		return
	var img := art.texture.get_image()
	if img:
		img.generate_mipmaps()
		art.texture = ImageTexture.create_from_image(img)
	_live = false


func is_live() -> bool:
	return _live


func set_reveal(v: float) -> void:
	_mat.set_shader_parameter("reveal", clampf(v, 0.0, 1.0))
	frame.modulate.a = clampf(v * 3.0, 0.0, 1.0)


func set_flash(v: float) -> void:
	_mat.set_shader_parameter("flash", clampf(v, 0.0, 1.0))


## Доля панели (0..1 по bbox) → точка страницы.
func to_page(frac: Vector2) -> Vector2:
	var b := bbox()
	return b.position + frac * b.size


## Время кадра t → надписям (появление, слежение за якорем в 3D пока панель живая). Возвращает надписи,
## появившиеся в этот кадр (для звука табличек).
func update_letters(t: float, stage: IntroStage) -> Array:
	var appeared: Array = []
	for c in clip.get_children() + letters.get_children():
		if c is ComicLetter:
			if (c as ComicLetter).update(t, self, stage if _live else null):
				appeared.append(c)
	return appeared


func _update_uv() -> void:
	var b := bbox()
	var uv := PackedVector2Array()
	for p in polygon:
		uv.append((p - b.position) / b.size * _tex_size)
	art.uv = uv
