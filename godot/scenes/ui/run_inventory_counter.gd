## Маленький счётчик материалов забега (RunInventory.shared()) в правом нижнем углу: «гвозди 2 · пластина 1 · …», только
## ненулевые, в порядке RunInventory.ORDER; пусто — скрыт. На каждое изменение строка вспыхивает (FLASH_S). Узел — CanvasLayer
## с ребёнком Label "Text" (его стиль задаёт сцена: у арены «Свалка» — tools/build_arena_scrap.gd, узел LootCounter).
class_name RunInventoryCounter
extends CanvasLayer

const FLASH_S := 0.6
const BASE_COLOR := Color(1.0, 0.93, 0.8, 0.85)
const FLASH_COLOR := Color(1.0, 0.8, 0.3, 1.0)

var _text: Label
var _flash := 0.0


func _ready() -> void:
	_text = get_node_or_null("Text") as Label
	var inv := RunInventory.shared()
	if not inv.changed.is_connected(_on_changed):
		inv.changed.connect(_on_changed)
	_refresh()


func _exit_tree() -> void:
	var inv := RunInventory.shared()
	if inv.changed.is_connected(_on_changed):
		inv.changed.disconnect(_on_changed)


func _process(delta: float) -> void:
	if _flash <= 0.0 or _text == null:
		return
	_flash = maxf(_flash - delta, 0.0)
	_text.add_theme_color_override("font_color", BASE_COLOR.lerp(FLASH_COLOR, _flash / FLASH_S))


func _on_changed(_id: String, _total: int, delta: int, _by: Node) -> void:
	_refresh()
	if delta > 0:
		_flash = FLASH_S


## Текст счётчика сейчас (для проб).
func text() -> String:
	return _text.text if _text != null else ""


func _refresh() -> void:
	if _text == null:
		return
	var inv := RunInventory.shared()
	var parts: PackedStringArray = []
	for id in RunInventory.ORDER:
		var n := inv.count(id)
		if n > 0:
			parts.append("%s %d" % [RunInventory.title(id), n])
	_text.text = tr("материалы: %s") % " · ".join(parts) if not parts.is_empty() else ""
	_text.visible = not parts.is_empty()
