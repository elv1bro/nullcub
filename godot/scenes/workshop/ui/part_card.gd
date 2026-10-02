## Карточка детали в библиотеке мастерской (UI v0.3, две колонки): крупная картинка детали (PartIcons; под курсором — живое
## вращающееся превью), имя для игрока (PartNames — без id и хвостов «(v3)»), ⚡ и кг. Наведение — карточка чуть приподнимается;
## клик — выбрать (справа паспорт детали), потянул — деталь «в руке» (WorkshopBuild.begin_drag: под курсором настоящая 3D-деталь);
## ☆ в углу — в избранное (фильтр «Избранное»). Не влезает по энергии — ⚡ красная, карточка тусклее (тащить можно — на замену).
## Подсказка (tooltip) — две короткие строки: вид и материал, чем деталь особенная.
extends PanelContainer

signal grabbed(part_id: String, pos: Vector2)
signal picked(part_id: String)
signal favorite_toggled(part_id: String, on: bool)
signal hovered(part_id: String, on: bool)

const ICON := 148
const W := 184.0
const H := 232.0
const DRAG_PX := WorkshopBuild.DRAG_MOVE_PX   # тот же порог, что у протяжки: «клик» и «потянул» не спорят
const LIFT := 1.035
## Чем бьёт форма детали (PartDef.hit_mult ≠ 1) — слово для подсказки по префиксу id; нет в таблице — «форма».
const HIT_WORDS := {
	"kit_limb_spiked": "шипы", "kit_head_horned": "рога", "kit_head_devil": "рожки", "kit_head_cow": "рога", "kit_hand_claw": "клешня",
	"kit_hand_clamp": "тиски", "kit_hand_fist": "кулак", "kit_foot_peg": "острый колышек", "kit_limb_rope": "мягкая верёвка",
	"kit_limb_tentacle": "мягкое щупальце",
}

var part_id := ""
var def: PartDef
var _icon: TextureRect
var _kind: Label
var _energy: Label
var _energy_icon: WsIcon
var _star: Button
var _static_tex: Texture2D
var _fits := true
var _fav := false
var _selected := false
var _hover := false
var _press := Vector2(-1, -1)
var _tw: Tween


func setup(d: PartDef, on_body := false, fav := false) -> void:
	def = d
	part_id = d.id
	_fav = fav
	custom_minimum_size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_restyle()
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(0, ICON)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_box)
	_kind = Label.new()
	_kind.text = String(CraftEdit.KIND_TITLES.get(d.kind, d.kind)).capitalize()
	WsStyle.label(_kind, WsStyle.SIZE_XS, true)
	_kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_kind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(_kind)
	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.add_child(_icon)
	_star = Button.new()
	_star.flat = true
	_star.focus_mode = Control.FOCUS_NONE
	_star.custom_minimum_size = Vector2(30, 30)
	_star.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_star.offset_left = -30
	_star.offset_bottom = 30
	_star.tooltip_text = "В избранное"
	_star.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_star.pressed.connect(func() -> void:
		_fav = not _fav
		_sync_star()
		favorite_toggled.emit(part_id, _fav))
	icon_box.add_child(_star)
	WsIcon.add_to_button(_star, "star", 18.0, WsStyle.TEXT_FAINT)
	var title := Label.new()
	title.text = PartNames.of(d)
	WsStyle.label(title, WsStyle.SIZE_S)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(0, 44)
	title.max_lines_visible = 2
	title.add_theme_constant_override("line_spacing", -3)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	v.add_child(row)
	_energy_icon = WsIcon.make("energy", 16.0, WsStyle.AMBER)
	row.add_child(_energy_icon)
	_energy = Label.new()
	_energy.text = str(d.energy)
	WsStyle.label(_energy, WsStyle.SIZE_S)
	_energy.add_theme_color_override("font_color", WsStyle.AMBER if d.energy > 0 else WsStyle.TEXT_DIM)
	_energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_energy)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(10, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	row.add_child(WsIcon.make("mass", 16.0, WsStyle.TEXT_DIM))
	var mass := Label.new()
	mass.text = "%.1f кг" % d.mass
	WsStyle.label(mass, WsStyle.SIZE_S, true)
	mass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mass)
	tooltip_text = _tooltip(d, on_body)
	_sync_star()
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func set_icon(tex: Texture2D) -> void:
	if _icon != null and tex != null:
		_static_tex = tex
		if _icon.texture == null or not (_icon.texture is ViewportTexture):
			_icon.texture = tex
		_kind.visible = false


## Живое превью под курсором (вращается — PartIcons.live_start); null — снова статичная картинка.
func set_live(tex: Texture2D) -> void:
	if _icon == null:
		return
	_icon.texture = tex if tex != null else _static_tex
	_kind.visible = _icon.texture == null


## Цена у ближайшего свободного подходящего разъёма (WorkshopBuild.cheapest_cost; дальше от ядра — дороже); -1 — некуда.
func set_cost(cost: int) -> void:
	if _energy != null:
		_energy.text = str(cost) if cost >= 0 else "—"


## Влезает ли по энергии (хотя бы на свободный якорь): нет — энергия красная, карточка тусклее (но тащить можно — на замену).
func set_fits(fits: bool) -> void:
	if fits == _fits:
		return
	_fits = fits
	modulate = Color(1, 1, 1, 1) if fits else Color(0.78, 0.7, 0.68, 0.88)
	_energy.add_theme_color_override("font_color", (WsStyle.AMBER if def.energy > 0 else WsStyle.TEXT_DIM) if fits else WsStyle.RED)
	_energy_icon.color = WsStyle.AMBER if fits else WsStyle.RED
	_restyle()


func set_selected(on: bool) -> void:
	if on == _selected:
		return
	_selected = on
	_restyle()


func set_favorite(on: bool) -> void:
	_fav = on
	_sync_star()


func is_favorite() -> bool:
	return _fav


func _restyle() -> void:
	var st := "selected" if _selected else ("hover" if _hover else ("normal" if _fits else "dim"))
	add_theme_stylebox_override("panel", WsStyle.card(st))


func _sync_star() -> void:
	if _star == null:
		return
	WsIcon.add_to_button(_star, "star_filled" if _fav else "star", 18.0, WsStyle.AMBER if _fav else WsStyle.TEXT_FAINT)
	_star.tooltip_text = "Убрать из избранного" if _fav else "В избранное"
	_star.modulate.a = 1.0 if (_fav or _hover) else 0.0


## Наведение: карточка чуть крупнее и поверх соседей (контейнер держит позицию — поднимаем масштабом), звёздочка видна.
func _set_hover(on: bool) -> void:
	_hover = on
	_restyle()
	_sync_star()
	z_index = 1 if on else 0
	if _tw != null:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector2.ONE * (LIFT if on else 1.0), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hovered.emit(part_id, on)
	if not on:
		_press = Vector2(-1, -1)


## ЛКМ: без сдвига — выбор; потянул дальше DRAG_PX — деталь в руку (протяжку дальше ведёт WorkshopBuild._input).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_press = get_viewport().get_mouse_position()
			get_viewport().gui_release_focus()   # поле поиска отдаёт клавиши: D / Del / T снова мастерской
		elif _press.x >= 0.0:
			_press = Vector2(-1, -1)
			picked.emit(part_id)
		accept_event()
	elif event is InputEventMouseMotion and _press.x >= 0.0:
		var mp := get_viewport().get_mouse_position()
		if mp.distance_to(_press) > DRAG_PX:
			var start := _press
			_press = Vector2(-1, -1)
			grabbed.emit(part_id, start)
			accept_event()


## Слово формы для подсказки: «шипы», «клешня»… (HIT_WORDS по префиксу id детали), иначе «форма».
static func hit_word(id: String) -> String:
	for k in HIT_WORDS:
		if id.begins_with(String(k)):
			return String(HIT_WORDS[k])
	return "форма"


## 1.3 → «1.3», 1.15 → «1.15», 0.85 → «0.85» (без хвостовых нулей).
static func _mult_str(v: float) -> String:
	var s := "%.2f" % v
	return s.trim_suffix("0").trim_suffix(".") if s.ends_with("0") else s


## Короткая подсказка (v0.3 §48): вид · материал; чем особенная (удар формы, намертво, урон в оружии).
static func _tooltip(d: PartDef, on_body := false) -> String:
	var mat := CraftEdit.mat_title(d.base_mat) if d.base_mat != "" else String({"wood": "дерево", "iron": "железо", "cloth": "ткань"}.get(d.material, ""))
	var lines: PackedStringArray = ["%s%s" % [String(CraftEdit.KIND_TITLES.get(d.kind, d.kind)).capitalize(), " · " + mat.to_lower() if mat != "" else ""]]
	if d.weapon_mult > 1.0:
		lines.append(("в оружии урон ×%s" if on_body else "урон ×%s") % _mult_str(d.weapon_mult))
	elif not is_equal_approx(d.hit_mult, 1.0) and not BodyBlueprint.is_fixed_part(d):
		lines.append("%s: удар ×%s" % [hit_word(d.id), _mult_str(d.hit_mult)])
	elif PartDef.FIXED_KINDS.has(d.kind) and not is_equal_approx(d.body_mult, 1.0):
		lines.append("удар хозяином ×%s" % _mult_str(d.body_mult))
	elif BodyBlueprint.is_fixed_part(d):
		lines.append("крепится намертво")
	return "\n".join(lines)
