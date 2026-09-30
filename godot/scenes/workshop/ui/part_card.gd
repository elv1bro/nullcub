## Карточка детали на полке мастерской: иконка (PartIcons, рендер в рантайме), название, энергия и масса. Нажал ЛКМ — сигнал
## grabbed (WorkshopBuild.begin_drag: протяжка или «деталь в руке» по клику). Не влезает в бюджет — энергия красная, карточка тусклее.
## Подсказка (tooltip) — вид, масса, крепление, множитель удара; у деталей кита v2 — материал по умолчанию и его физика. Множитель
## удара — тот, что правда в бою (BODY_KIT.md §5.4): у детали со своим телом — таблица по имени × материал по умолчанию × форма
## (PartDef.hit_mult: «шипы: удар ×1.3»), у декора / брони — бонус телу-хозяину; weapon_mult навершия / мода на полке тела (on_body) —
## только в оружии, на теле — масса и форма.
extends PanelContainer

signal grabbed(part_id: String, pos: Vector2)

const ICON := 80   # компактный экран (WORKSHOP_V3.md §6): три карточки в колонке 400 px
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
var _style := StyleBoxFlat.new()
var _style_hover := StyleBoxFlat.new()
var _fits := true


func setup(d: PartDef, on_body := false) -> void:
	def = d
	part_id = d.id
	custom_minimum_size = Vector2(108, 152)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	for s in [_style, _style_hover]:
		s.bg_color = Color(0.11, 0.09, 0.075, 0.95)
		s.set_border_width_all(2)
		s.set_corner_radius_all(8)
		s.content_margin_left = 6
		s.content_margin_right = 6
		s.content_margin_top = 6
		s.content_margin_bottom = 6
	_style.border_color = Color(0.36, 0.26, 0.16)
	_style_hover.border_color = Color(0.95, 0.75, 0.4)
	_style_hover.bg_color = Color(0.17, 0.13, 0.1, 0.97)
	add_theme_stylebox_override("panel", _style)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var icon_box := Control.new()
	icon_box.custom_minimum_size = Vector2(ICON, ICON)
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_box)
	_kind = Label.new()
	_kind.text = String(CraftEdit.KIND_TITLES.get(d.kind, d.kind))
	_kind.add_theme_font_size_override("font_size", 16)
	_kind.add_theme_color_override("font_color", Color(0.75, 0.68, 0.58))
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
	var title := Label.new()
	title.text = _short_title(d.title)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(96, 40)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.84))
	title.add_theme_constant_override("line_spacing", -4)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_energy = Label.new()
	_energy.text = "⚡%d" % d.energy
	_energy.add_theme_font_size_override("font_size", 18)
	_energy.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35) if d.energy > 0 else Color(0.7, 0.66, 0.6))
	_energy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_energy)
	var mass := Label.new()
	mass.text = "%.1f кг" % d.mass
	mass.add_theme_font_size_override("font_size", 16)
	mass.add_theme_color_override("font_color", Color(0.8, 0.76, 0.7))
	mass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mass)
	tooltip_text = _tooltip(d, on_body)
	mouse_entered.connect(func() -> void: add_theme_stylebox_override("panel", _style_hover))
	mouse_exited.connect(func() -> void: add_theme_stylebox_override("panel", _style))


func set_icon(tex: Texture2D) -> void:
	if _icon != null and tex != null:
		_icon.texture = tex
		_kind.visible = false


## Влезает ли по энергии (хотя бы на свободный якорь): нет — энергия красная, карточка тусклее (но тащить можно — на замену).
func set_fits(fits: bool) -> void:
	if fits == _fits:
		return
	_fits = fits
	modulate = Color(1, 1, 1, 1) if fits else Color(0.72, 0.62, 0.6, 0.85)
	_energy.add_theme_color_override("font_color", (Color(1.0, 0.86, 0.35) if def.energy > 0 else Color(0.7, 0.66, 0.6)) if fits else Color(1.0, 0.35, 0.28))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		grabbed.emit(part_id, get_viewport().get_mouse_position())
		accept_event()


static func _short_title(t: String) -> String:
	return t.replace(" (клён)", "").replace(" (хлам)", " · хлам").replace(" (кит «Человек»)", " · кит")


## Слово формы для подсказки: «шипы», «клешня»… (HIT_WORDS по префиксу id детали), иначе «форма».
static func hit_word(part_id: String) -> String:
	for k in HIT_WORDS:
		if part_id.begins_with(String(k)):
			return String(HIT_WORDS[k])
	return "форма"


## 1.3 → «1.3», 1.15 → «1.15», 0.85 → «0.85» (без хвостовых нулей).
static func _mult_str(v: float) -> String:
	var s := "%.2f" % v
	return s.trim_suffix("0").trim_suffix(".") if s.ends_with("0") else s


static func _tooltip(d: PartDef, on_body := false) -> String:
	var lines: PackedStringArray = [d.title]
	lines.append("%s · %.1f кг · энергия %d" % [String(CraftEdit.KIND_TITLES.get(d.kind, d.kind)).capitalize(), d.mass, d.energy])
	var fixed := BodyBlueprint.is_fixed_part(d)
	lines.append("прикручивается намертво" if fixed else "свой сустав — болтается")
	# кит v2 (BODY_KIT.md §4): материал по умолчанию и его физика; кисть «Материал» меняет его (масса — новая плотность / прежняя)
	var md := MaterialDef.get_def(d.base_mat) if d.base_mat != "" else null
	if md != null:
		lines.append("материал: %s — %s" % [CraftEdit.mat_title(d.base_mat), CraftEdit.mat_line(d.base_mat)])
	elif d.base_mat == "" and d.kind != "handle" and d.kind != "weapon_head" and d.kind != "mod":
		lines.append("не красится (старая деталь)")
	if d.weapon_mult > 1.0:
		if on_body:
			lines.append("на теле: только масса и форма (урон оружия ×%.2f — в оружии)" % d.weapon_mult)
		else:
			lines.append("урон оружия ×%.2f" % d.weapon_mult)
	if fixed:
		# декор / броня: бонус к удару телом-хозяином (шипы) — он в бою работает (meta body_mult хозяина)
		if PartDef.FIXED_KINDS.has(d.kind) and not is_equal_approx(d.body_mult, 1.0):
			lines.append("удар хозяином ×%.2f" % d.body_mult)
	else:
		# своё тело: удар = таблица по имени тела × материал узла × форма (hit_mult; PartDef.body_mult в бою не читается)
		if not is_equal_approx(d.hit_mult, 1.0):
			lines.append("%s: удар ×%s" % [hit_word(d.id), _mult_str(d.hit_mult)])
		var bm := Damage.body_mult_of(d.name_prefix) * (md.body_mult if md != null else 1.0) * d.hit_mult
		if bm >= 1.5:
			lines.append("бьёт сильно (×%.1f%s)" % [bm, (", " + md.title.to_lower()) if md != null and not is_equal_approx(md.body_mult, 1.0) else ""])
	var anchors := BodyBlueprint.part_anchors(d)
	if not anchors.is_empty():
		lines.append("якорей: %d" % anchors.size())
	return "\n".join(lines)
