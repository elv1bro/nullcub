## Индикатор поля NULL в HUD (лист камеры автора, HUD варианта 4: «слева снизу значок-стрелка направления гравитации и 0.35G»;
## вид по скину HUD — scripts/ui/hud_skin.gd): панель, стрелка направления, сила в G и строка
## мембраны («MEMBRANE 98%», при смене поля — «FIELD: SHIFTING»), как на табло зала. Данные — арена из группы "arena" с методом
## gravity_text() (NullHallArena); на аренах без поля плашка скрыта. Узел Root/Field в scenes/ui/hud.tscn.
class_name FieldBadge
extends PanelContainer

const POLL_S := 0.2

var arrow: Label
var value: Label
var membrane: Label
var _arena: Node
var _had := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	arrow = _label()
	row.add_child(arrow)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	value = _label()
	col.add_child(value)
	membrane = _label()
	col.add_child(membrane)
	visible = false
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())
	_refresh()


func _label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _apply_skin() -> void:
	add_theme_stylebox_override("panel", HudSkin.panel("field"))
	var field_c: Color = Broadcast.FIELD
	if HudSkin.id() == "led":
		field_c = HudSkin.LED
	HudSkin.style_label(arrow, "digits", 40, field_c)
	HudSkin.style_label(value, "digits", 32, HudSkin.text_colour(), field_c)
	HudSkin.style_label(membrane, "plate", 19, Color(HudSkin.text_colour(), 0.65) if HudSkin.id() != "broadcast" else Broadcast.MUTED)


func _process(delta: float) -> void:
	_t += delta
	if _t >= POLL_S:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if _arena == null or not is_instance_valid(_arena):
		_arena = null
		for a in get_tree().get_nodes_in_group("arena"):
			if a.has_method("gravity_text"):
				_arena = a
				break
	var has := _arena != null
	if has != _had:   # видимость — только при смене арены: HUD прячет плашку на кинематограф крита (Hud.set_cinematic)
		_had = has
		visible = has
	if not has:
		return
	var g := String(_arena.call("gravity_text"))
	var parts := g.split(" ", false, 1)
	arrow.text = parts[0] if parts.size() == 2 else "·"
	value.text = parts[1] if parts.size() == 2 else g
	var field: Variant = _arena.get("field")
	var shifting := field is Object and (field as Object).has_method("is_shifting") and bool((field as Object).call("is_shifting"))
	membrane.text = tr("FIELD: SHIFTING") if shifting else tr("MEMBRANE %d%%") % int(_arena.get("membrane_pct"))
