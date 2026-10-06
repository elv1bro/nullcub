## Плашки бойцов в начале боя — «нижние трети» эфира Лиги (docs/plan-demo/look/show.md; пункт «ВИД» show_plates, группа «Эфир»).
## На отсчёте (Match.Phase.COUNTDOWN) снизу по краям въезжают плашки P1 (слева) и P2 (справа): блок цвета команды с «P1», имя (как
## на панели HUD: «ИГРОК 1», в кампании — имя и титул), строка сборки (набор / чертёж · дерево · масса · деталей) и янтарная фишка
## счёта (кампания — запись лестницы, иначе — серия этой сессии по коронам HUD). Держатся HOLD_S, уезжают обратно. Стиль — токены
## эфира (ShowTokens: косые плашки, Oswald + Rubik) независимо от скина HUD. Бои один на один (Быстрый бой, арены, кампания, спорт);
## у стычки, бомбы, гонки и PvE — своё вступление, там плашек нет. Выключение пункта прячет слой сразу (снимок «до» на паузе).
class_name LowerThirds
extends CanvasLayer

const ID := &"show_plates"
const LAYER := 12
const BASE := Vector2(1920, 1080)
const MARGIN_X := 56.0
const TOP := 806.0
const TAG_W := 96.0
const NAME_H := 62.0
const SUB_H := 38.0
const NAME_PX := 42
const SUB_PX := 22
const CHIP_PX := 24
const IN_S := 0.32
const HOLD_S := 2.75
const OUT_S := 0.28
const STAGGER_S := 0.12

var match_node: Match
var shown := 0                       # сколько раз плашки выезжали (пробы)
var plates: Array[Control] = []      # [левая, правая] — пока на экране
var _root: Control
var _look: Node
var _tweens: Array[Tween] = []


## Плашки нужны матчу 1 на 1 (Match и SportMatch); у стычки, бомбы, гонки и PvE — своё вступление. По пути скрипта — без загрузки их классов.
const SKIP := ["squad_match.gd", "bomb_match.gd", "race_match.gd", "wave_director.gd", "climb_match.gd"]


static func wants(m: Node) -> bool:
	if not (m is Match):
		return false
	var s := m.get_script() as Script
	while s != null:
		if SKIP.has(s.resource_path.get_file()):
			return false
		s = s.get_base_script()
	return true


## Слой плашек рядом с матчем (повторно — тот же).
static func attach(m: Match) -> LowerThirds:
	var parent := m.get_parent()
	var lt := parent.get_node_or_null("LowerThirds") as LowerThirds
	if lt != null:
		return lt
	lt = LowerThirds.new()
	lt.name = "LowerThirds"
	lt.match_node = m
	parent.add_child(lt)
	return lt


func _init() -> void:
	layer = LAYER


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_look = get_node_or_null("/root/Look")
	if _look != null:
		_look.changed.connect(func(id: StringName, on: bool) -> void:
			if id == ID:
				visible = on)
		visible = bool(_look.call("on", ID))
	if match_node != null:
		match_node.phase_changed.connect(_on_phase)
		if match_node.phase == Match.Phase.COUNTDOWN:
			show_plates()


func _process(delta: float) -> void:
	if _tweens.is_empty():
		return
	var dt := minf(delta / maxf(Engine.time_scale, 0.01), 1.0 / 30.0)   # без масштаба времени, рывок загрузки — не дальше 1/30 с
	for tw in _tweens.duplicate():
		if tw == null or not tw.is_valid() or not tw.custom_step(dt):
			_tweens.erase(tw)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		show_plates()


## Данные плашки бойца i: {name, sub, chip, colour}. Пустой словарь — бойца нет.
func info_for(i: int) -> Dictionary:
	var doll: Doll = null
	if match_node != null:
		for d in match_node.dolls():
			if d is Doll and (d as Doll).player_index == i:
				doll = d
				break
	if doll == null:
		return {}
	var hud := _hud()
	var name := PlayerPanel.default_name(i).to_upper()
	if hud != null and hud.panels.has(i):
		var pn := hud.panels[i] as PlayerPanel
		if pn.name_label != null and pn.name_label.text != "":
			name = pn.name_label.text
	var bits: PackedStringArray = []
	if doll is ModularDoll and (doll as ModularDoll).blueprint != null:
		var bp := (doll as ModularDoll).blueprint
		bits.append(bp.title)
		bits.append(tr("деталей %d") % bp.nodes.size())
	else:
		bits.append(tr("Человек"))
		bits.append(tr("Орех") if doll.scene_file_path.ends_with("doll_dark.tscn") else tr("Клён"))
	if doll.total_mass > 0.0:
		bits.append(tr("%.1f кг") % doll.total_mass)
	var chip := ""
	var info: Variant = match_node.get_parent().get("info") if match_node != null else null
	if info is Dictionary:
		chip = String((info as Dictionary).get("player_record" if i == 0 else "rival_record", ""))
	if chip == "":
		var w: Dictionary = hud.wins if hud != null else {}
		chip = tr("СЕРИЯ %d – %d") % [int(w.get(i, 0)), int(w.get(1 - i, 0))]
	return {"name": name, "sub": " · ".join(bits), "chip": chip, "colour": ShowTokens.team(i)}


func _hud() -> Hud:
	var scene := match_node.get_parent() if match_node != null else null
	if scene == null:
		return null
	for h in get_tree().get_nodes_in_group("hud"):
		if h is Hud and scene.is_ancestor_of(h):
			return h
	return null


## Выпустить плашки (отсчёт боя). Старые — убрать сразу.
func show_plates() -> void:
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	for p in plates:
		if is_instance_valid(p):
			p.queue_free()
	plates.clear()
	for i in 2:
		var inf := info_for(i)
		if inf.is_empty():
			continue
		var p := _build(inf, i == 1)
		plates.append(p)
		_animate(p, i == 1, STAGGER_S * i)
	if not plates.is_empty():
		shown += 1


func _panel(parent: Control, style: StyleBox, pos: Vector2, size: Vector2) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style)
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _label(parent: Control, text: String, font: Font, px: int, colour: Color, pos: Vector2, size: Vector2,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = pos
	l.size = size
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _plate_style(bg: Color, mirror: bool, underline := Color(0, 0, 0, 0), skew := ShowTokens.SKEW) -> BcStyle:
	var s := BcStyle.new()
	s.bg = bg
	s.skew = skew
	s.mirror = mirror
	if underline.a > 0.0:
		s.underline_color = underline
		s.underline_h = 5.0
	return s


## Плашка: Root (вся, едет при уходе) → Tag (блок цвета), MaskName (раскрывается по ширине) → Name, MaskSub → Sub, Chip.
func _build(inf: Dictionary, right: bool) -> Control:
	var f_name := ShowTokens.title(700)
	var f_sub := ShowTokens.text(500)
	var f_chip := ShowTokens.title(600)
	var name_w := clampf(f_name.get_string_size(String(inf["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_PX).x + 64.0, 300.0, 640.0)
	var sub_w := clampf(f_sub.get_string_size(String(inf["sub"]), HORIZONTAL_ALIGNMENT_LEFT, -1, SUB_PX).x + 56.0, 220.0, 620.0)
	var chip_w := f_chip.get_string_size(String(inf["chip"]), HORIZONTAL_ALIGNMENT_LEFT, -1, CHIP_PX).x + 44.0
	var total := TAG_W + maxf(name_w + chip_w - 12.0, sub_w) + 20.0
	var root := Control.new()
	root.name = "PlateR" if right else "PlateL"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(total, NAME_H + SUB_H)
	root.position = Vector2(BASE.x - MARGIN_X - total if right else MARGIN_X, TOP)
	_root.add_child(root)
	# позиции внутри: слева направо для P1, зеркально для P2
	var x_of := func(x: float, w: float) -> float: return total - x - w if right else x
	var colour: Color = inf["colour"]
	var tag := _panel(root, _plate_style(colour, right), Vector2(x_of.call(0.0, TAG_W), 0.0), Vector2(TAG_W, NAME_H + SUB_H))
	tag.name = "Tag"
	_label(tag, "P%d" % (2 if right else 1), ShowTokens.title(700), 46, ShowTokens.TEXT, Vector2.ZERO, tag.size, HORIZONTAL_ALIGNMENT_CENTER)
	var mask_name := Control.new()
	mask_name.name = "MaskName"
	mask_name.clip_contents = true
	mask_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask_name.position = Vector2(x_of.call(TAG_W - 8.0, name_w + chip_w), 0.0)
	mask_name.size = Vector2(name_w + chip_w, NAME_H)
	root.add_child(mask_name)
	var name_x := chip_w - 12.0 if right else 0.0
	var np := _panel(mask_name, _plate_style(ShowTokens.PLATE, right, ShowTokens.AMBER), Vector2(name_x, 0.0), Vector2(name_w, NAME_H))
	np.name = "NamePlate"
	var nl := _label(np, String(inf["name"]), f_name, NAME_PX, ShowTokens.TEXT, Vector2(28.0, -2.0), Vector2(name_w - 52.0, NAME_H),
		HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT)
	nl.name = "Name"
	var chip := _panel(mask_name, _plate_style(ShowTokens.AMBER, right), Vector2(0.0 if right else name_w - 12.0, 8.0),
		Vector2(chip_w, NAME_H - 16.0))
	chip.name = "Chip"
	_label(chip, String(inf["chip"]), f_chip, CHIP_PX, ShowTokens.INK, Vector2(0.0, -1.0), chip.size, HORIZONTAL_ALIGNMENT_CENTER)
	var mask_sub := Control.new()
	mask_sub.name = "MaskSub"
	mask_sub.clip_contents = true
	mask_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask_sub.position = Vector2(x_of.call(TAG_W - 20.0, sub_w), NAME_H)
	mask_sub.size = Vector2(sub_w, SUB_H)
	root.add_child(mask_sub)
	var sp := _panel(mask_sub, _plate_style(ShowTokens.PLATE_LIGHT, right), Vector2.ZERO, Vector2(sub_w, SUB_H))
	sp.name = "SubPlate"
	var sl := _label(sp, String(inf["sub"]), f_sub, SUB_PX, Color(0.86, 0.9, 0.97), Vector2(26.0, 0.0), Vector2(sub_w - 48.0, SUB_H),
		HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT)
	sl.name = "Sub"
	root.set_meta("full", {"name": mask_name.size, "sub": mask_sub.size, "name_pos": mask_name.position, "sub_pos": mask_sub.position,
		"tag_pos": tag.position})
	return root


## Въезд: блок цвета из-за края, имя и строка сборки раскрываются, фишка счёта — щелчком; HOLD_S; уход за край.
func _animate(root: Control, right: bool, delay: float) -> void:
	var full: Dictionary = root.get_meta("full")
	var tag := root.get_node("Tag") as Control
	var mn := root.get_node("MaskName") as Control
	var ms := root.get_node("MaskSub") as Control
	var chip := mn.get_node("Chip") as Control
	var sign := 1.0 if right else -1.0
	var tag_pos: Vector2 = full["tag_pos"]
	tag.position = tag_pos + Vector2(sign * (TAG_W + MARGIN_X + 40.0), 0.0)
	# маска раскрывается от блока: у правой плашки — справа налево (сдвиг позиции вместе с шириной)
	var name_full: Vector2 = full["name"]
	var sub_full: Vector2 = full["sub"]
	var name_pos: Vector2 = full["name_pos"]
	var sub_pos: Vector2 = full["sub_pos"]
	mn.size = Vector2(0.0, name_full.y)
	ms.size = Vector2(0.0, sub_full.y)
	if right:
		mn.position = name_pos + Vector2(name_full.x, 0.0)
		ms.position = sub_pos + Vector2(sub_full.x, 0.0)
	chip.scale = Vector2(0.0, 0.0)
	chip.pivot_offset = chip.size * 0.5
	root.modulate.a = 1.0
	var tw := root.create_tween()
	tw.pause()   # шагает _process с ограниченным шагом: первый кадр после загрузки сцены длится секунды — анимация не должна проскочить
	_tweens.append(tw)
	tw.tween_interval(delay)
	tw.tween_property(tag, "position", tag_pos, IN_S * 0.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mn, "size:x", name_full.x, IN_S).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if right:
		tw.parallel().tween_property(mn, "position:x", name_pos.x, IN_S).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ms, "size:x", sub_full.x, IN_S).set_delay(0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if right:
		tw.parallel().tween_property(ms, "position:x", sub_pos.x, IN_S).set_delay(0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(chip, "scale", Vector2.ONE, 0.2).set_delay(0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD_S - IN_S)
	tw.tween_property(root, "position:x", root.position.x + sign * (root.size.x + MARGIN_X + 60.0), OUT_S) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(root, "modulate:a", 0.0, OUT_S)
	tw.tween_callback(func() -> void:
		plates.erase(root)
		root.queue_free())


## Плашки сразу в конечном положении и без ухода (пробы вёрстки на всех языках, снимки): анимация останавливается.
func pose_full() -> void:
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	for root in plates:
		if not is_instance_valid(root):
			continue
		var full: Dictionary = root.get_meta("full")
		var mn := root.get_node("MaskName") as Control
		var ms := root.get_node("MaskSub") as Control
		(root.get_node("Tag") as Control).position = full["tag_pos"]
		mn.position = full["name_pos"]
		mn.size = full["name"]
		ms.position = full["sub_pos"]
		ms.size = full["sub"]
		(mn.get_node("Chip") as Control).scale = Vector2.ONE
		root.modulate.a = 1.0
