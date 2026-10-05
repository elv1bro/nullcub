## Метка СТАЗИСА на HUD боя (docs/plan-demo/STASIS.md): плашка табло по скину HUD (HudSkin, как FieldBadge) — имя режима, строка
## «ВРЕМЯ СТОИТ» / «ВРЕМЯ ИДЁТ» и масштаб времени режима цифрами (×0.05). Видна, пока режим включён (Stasis.on), кроме итогов и
## крит-кино (HUD в нём тоже прячется). Создаёт HitJuice (ребёнок Match) на своём слое — метка есть на всех площадках с Match
## (быстрый бой, кампания, PvE, спорт-зал), какой бы HUD там ни стоял. Место — справа снизу: слева снизу плашка поля NULL и ярлык
## Tab, по центру снизу тосты, справа по центру ярлык L. Говорит только табло: без цвета игрока и без частиц.
class_name StasisBadge
extends PanelContainer

const LAYER := 9                  # под HUD (10: карточка KO и итоги — поверх), над субтитрами N0 (6)
const FROZEN_BELOW := 0.5         # масштаб режима ниже — «время стоит»
const MARGIN := Vector2(24.0, 62.0)

## Match, чей масштаб показываем (stasis_scale, phase, crit_playing).
var match_node: Node = null
var title: Label
var state: Label
var rate: Label
## Пробы: что показано сейчас.
var frozen := false
var _skin := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = -MARGIN.x
	offset_right = -MARGIN.x
	offset_top = -MARGIN.y
	offset_bottom = -MARGIN.y
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	title = _label()
	col.add_child(title)
	state = _label()
	col.add_child(state)
	rate = _label()
	rate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(rate)
	title.text = tr("СТАЗИС")
	HudSkin.events.changed.connect(_on_skin)
	_refresh(true)


func _label() -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _on_skin(_id: String) -> void:
	_refresh(true)


func _process(_delta: float) -> void:
	_refresh(false)


func _scale() -> float:
	if match_node != null and is_instance_valid(match_node) and match_node.has_method("stasis_scale"):
		return float(match_node.call("stasis_scale"))
	return 1.0


func _refresh(force: bool) -> void:
	var m: Node = match_node if match_node != null and is_instance_valid(match_node) else null
	var show := Stasis.on and m != null and int(m.get("phase")) != Match.Phase.OVER \
		and not (m.has_method("crit_playing") and bool(m.call("crit_playing")))
	if visible != show:
		visible = show
	if not show:
		return
	var s := _scale()
	var f := s < FROZEN_BELOW
	rate.text = "×%.2f" % s
	if f == frozen and not force and _skin == HudSkin.id():
		return
	frozen = f
	_skin = HudSkin.id()
	state.text = tr("ВРЕМЯ СТОИТ") if f else tr("ВРЕМЯ ИДЁТ")
	add_theme_stylebox_override("panel", HudSkin.panel("field"))
	var muted: Color = Color(HudSkin.text_colour(), 0.65) if _skin != "broadcast" else Broadcast.MUTED
	HudSkin.style_label(title, "plate", 19, HudSkin.accent() if f else muted)
	HudSkin.style_label(state, "digits", 30, HudSkin.text_colour() if f else muted, HudSkin.accent())
	HudSkin.style_label(rate, "digits", 30, HudSkin.accent() if f else muted)
