## Сок удара на языке игры (HIT_FX.md §13, 02.10). Ребёнок Match (Match._ensure_fx_directors при Tuning.JUICE_ENABLED, раньше
## директоров эффектов — его обработчик hit_fx идёт первым). На каждый удар (Match.hit_fx: урон > 0, не окружение):
##   • след на ударенной детали — HitMarks (скол + трещины по материалу детали, остаётся до конца жизни детали);
##   • цифра-обломок — DamageDigits (урон объёмной цифрой цвета краски жертвы падает и лежит);
##   • обломки по материалу спавнит не он, а DollCombat → ImpactFx (FxMaterial);
##   • поводы N0 — сигнал juice_event(event, args): digit_big (большая цифра), metal (сильный удар по железу), worn (деталь вся
##     в сколах), digits_pile (цифр на полу много). N0Host слушает и решает, говорить ли (мелкие поводы — N0Lines).
## Замедление — варианты Tuning.JUICE_TIME_VARIANTS: статический time_variant читает Match._juice_time. Клавиши (автор 02.10: без F1–F12,
## на обычных цифрах; 1–9 уже меняют площадку): 0 — следующий вариант замедления, «−» (минус рядом с нулём) — цифры вкл/выкл,
## «=» — стиль вспышки удара: серьёзный (свет, пыль, волна воздуха) / мульт (прежние звезда RM и цветные кольца).
## Физические клавиши — работают в любой раскладке. Тост внизу экрана; на первом FIGHT! сессии — подсказка с клавишами.
## Автор 02.10 (второй круг): L — панель всех доп. клавиш сбоку (KeysPanel, значения живые); колесо мыши / «,» «.» — масштаб камеры
## (DynamicCamera.user_zoom, текущее число в тосте и панели); B — обводка бойцов цветом игрока (DollOutline, по умолчанию вкл —
## тело читается на тёмном фоне купола). Вызов чемпиона лиги в куполе — K (был L, NullHallArena).
## Автор 04.10: C — пробный режим «Прочность суставов» (JointBreak, JOINT_BREAK.md): суставы изнашиваются от ударов, конечности
## отлетают; вид режима — JointBreakFx (искры на повреждённом суставе, вспышка отрыва), создаётся здесь.
## Автор 05.10: X — пробный режим «СТАЗИС» (Stasis, STASIS.md): время идёт, только пока человек жмёт свои действия; метка режима
## на HUD — StasisBadge, создаётся здесь при первом включении (выключенный режим ничего не добавляет в сцену). «Ч» в русской
## раскладке — «часы».
## Говорят только N0 и табло (LORE_NULL.md «Голоса и тон»).
class_name HitJuice
extends Node

signal juice_event(event: String, args: Array)

const TOAST_S := 1.6
const HINT_S := 4.0
const KEY_VARIANT := KEY_0
const KEY_DIGITS := KEY_MINUS
const KEY_STYLE := KEY_EQUAL
const KEY_HELP := KEY_L
const KEY_OUTLINE := KEY_B
const KEY_ZOOM_OUT := KEY_COMMA
const KEY_ZOOM_IN := KEY_PERIOD
const KEY_JOINTS := KEY_C        # пробный режим «Прочность суставов» (JointBreak): «С» в русской раскладке — «суставы»
const KEY_STASIS := KEY_X        # пробный режим «СТАЗИС» (Stasis): «Ч» в русской раскладке — «часы»
const ZOOM_STEP := 1.12          # шаг масштаба (колесо, «,» «.»)
const ZOOM_RANGE := Vector2(0.45, 2.2)   # DynamicCamera.user_zoom: меньше — ближе
const OUTLINE_SCAN_S := 0.15     # обводка ставится по одной кукле за проход — без всплеска узлов в один кадр (perf gate 250/кадр)
const STYLE_TITLES := {"serious": "серьёзный (свет, пыль, волна воздуха)", "cartoon": "мульт (звезда и кольца, как было)"}
const PILE_N := 8
const PILE_GAP_S := 20.0

## Вариант замедления (ключ Tuning.JUICE_TIME_VARIANTS) — общий на все площадки, переживает смену арены.
static var time_variant: String = Tuning.JUICE_TIME_DEFAULT
## Стиль вспышки удара (Tuning.JUICE_IMPACT_STYLES): "serious" — короткий жар, свет и пыль; "cartoon" — прежняя звезда RM и кольца.
static var impact_style: String = Tuning.JUICE_IMPACT_STYLE_DEFAULT
## Цифры-обломки включены (клавиша «−») — общий флаг.
static var digits_on: bool = Tuning.JUICE_DIGITS
## Обводка бойцов (клавиша B) и открыта ли панель клавиш (L) — общие, переживают смену арены.
static var outline_on: bool = Tuning.JUICE_OUTLINE_DEFAULT
static var help_open := false

var marks_enabled: bool = Tuning.JUICE_MARKS
var digits: DamageDigits
var keys_panel: KeysPanel
var joint_fx: JointBreakFx
var stasis_badge: StasisBadge
## Пробы: события и счётчики.
var events: Array = []
var stats := {"marks": 0, "digits": 0}

var _match: Node = null
var _worn: Dictionary = {}       # instance_id тела -> true (повод worn уже был)
var _pile_t := -INF
var _clock := 0.0
var _toast: Label = null
static var _hinted := false     # подсказка клавиш показана в этой сессии
var _toast_tw: Tween = null
var _outline_t := 0.0
var _outline_shown := true       # текущее видимое состояние обводок (скрыты на время крупного плана)


static func variant() -> Dictionary:
	if Drive.on and time_variant != "off":   # ДРАЙВ: свой микростоп почти на каждый удар (Tuning.DRIVE_TIME); «выкл» клавиши 0 главнее
		return Tuning.DRIVE_TIME
	return Tuning.JUICE_TIME_VARIANTS.get(time_variant, Tuning.JUICE_TIME_VARIANTS[Tuning.JUICE_TIME_DEFAULT])


## Следующий вариант замедления по кругу (клавиша 0). Возвращает ключ.
static func cycle_time_variant() -> String:
	var order: Array = Tuning.JUICE_TIME_ORDER
	var i := order.find(time_variant)
	time_variant = String(order[(i + 1) % order.size()])
	return time_variant


## Название выбранного варианта замедления для экрана (в Tuning лежит русский ключ).
static func variant_title() -> String:
	return TranslationServer.translate(String(variant().get("title", time_variant)))


static func style_title() -> String:
	return TranslationServer.translate(String(STYLE_TITLES.get(impact_style, impact_style)))


## Надпись табло для крита (N0_VOICE.md п. 3): «IMPACT 18.4G» — score удара.
static func impact_caption(ctx: Dictionary, fallback: String) -> String:
	if not Tuning.JUICE_IMPACT_CAPTION:
		return TranslationServer.translate(fallback)
	var sc := float(ctx.get("score", 0.0))
	if sc <= 0.0:
		sc = float(ctx.get("damage", 0.0))
	return TranslationServer.translate("IMPACT %.1fG") % sc if sc > 0.0 else TranslationServer.translate(fallback)


## Цвет краски куклы — цвет цифры-обломка: цвет игрока (обмотки и мазки), у врагов PvE — ржавая ткань EnemyLook.
static func paint_colour(doll: Node) -> Color:
	if doll == null or not is_instance_valid(doll):
		return Color(0.9, 0.9, 0.9)
	if doll.get_node_or_null("EnemyLook") != null:
		return EnemyLook.CLOTH_COLOR.lightened(0.3)
	var pi: Variant = doll.get("player_index")
	var i := int(pi) if pi != null else 0
	return Tuning.PLAYER_COLORS[clampi(i, 0, Tuning.PLAYER_COLORS.size() - 1)]


func _ready() -> void:
	_match = get_parent()
	digits = DamageDigits.new()
	digits.name = "DamageDigits"
	add_child(digits)
	keys_panel = KeysPanel.new()
	keys_panel.lines_fn = keys_lines
	add_child(keys_panel)
	keys_panel.set_open(help_open)
	joint_fx = JointBreakFx.new()
	joint_fx.name = "JointBreakFx"
	add_child(joint_fx)
	if DisplayServer.get_name() != "headless":   # панель управления (ControlFeel): в headless-пробах не нужна и не читает user://
		var cfp := ControlFeelPanel.new()
		cfp.toast_fn = show_toast
		add_child(cfp)
	if _match != null:
		if _match.has_signal("hit_fx"):
			_match.connect("hit_fx", _on_hit_fx)
		if _match.has_signal("phase_changed"):
			_match.connect("phase_changed", _on_phase_changed)
	call_deferred("_prewarm")


func _prewarm() -> void:
	var mats: Array = [DamageDigits.material_for(Color.WHITE, false), DamageDigits.material_for(Color.WHITE, true)]
	var mm := ShaderMaterial.new()
	mm.shader = HitMarks.SHADER
	mats.append(mm)
	FxPrewarm.spatial(self, mats)


func _on_phase_changed(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		digits.clear()
		_worn.clear()
	elif p == Match.Phase.FIGHT and not _hinted:
		_hinted = true
		show_toast(hint_text(), HINT_S)


## Подсказка клавиш сока удара (первый FIGHT! сессии).
static func hint_text() -> String:
	return TranslationServer.translate("L — все клавиши    =  — удар: %s    0 — замедление: %s    −  — цифры: %s") % [
		TranslationServer.translate("серьёзный") if impact_style == "serious" else TranslationServer.translate("мульт"), variant_title(), TranslationServer.translate("вкл") if digits_on else TranslationServer.translate("выкл")]


func _on_hit_fx(ctx: Dictionary) -> void:
	var victim := ctx.get("victim") as Doll
	if victim == null or not is_instance_valid(victim):
		return
	var damage := float(ctx.get("damage", 0.0))
	var tier := String(ctx.get("tier", "light"))
	var pos: Vector3 = ctx.get("position", victim.centre_of_mass())
	var part := String(ctx.get("part", ""))
	var body: Node3D = null
	if victim.parts.has(part):
		body = victim.parts[part] as Node3D
	var mat := String(ctx.get("mat", FxMaterial.id_of(victim, body)))
	var cls := FxMaterial.cls(mat)
	# след на детали
	if marks_enabled and body != null and damage >= Tuning.JUICE_MARK_MIN_DAMAGE:
		var w := HitMarks.add(body, pos, damage, cls)
		stats["marks"] = int(stats["marks"]) + 1
		var id := body.get_instance_id()
		if w >= Tuning.JUICE_WORN_POWER and not _worn.has(id) and victim.alive:
			_worn[id] = true
			_event("worn", [Doll.part_base_name(part)])
	# цифра-обломок
	if digits_on and damage >= Tuning.JUICE_DIGIT_MIN_DAMAGE:
		var dir: Vector3 = ctx.get("dir", Vector3.RIGHT)
		var big := damage >= Tuning.JUICE_DIGIT_BIG
		digits.spawn(damage, pos, signf(dir.x) if dir.x != 0.0 else 1.0, paint_colour(victim), big)
		stats["digits"] = int(stats["digits"]) + 1
		if big and (tier == HitTier.LIGHT or tier == HitTier.HEAVY):
			_event("digit_big", [roundi(damage)])
		if digits.resting_count() >= PILE_N and _clock - _pile_t > PILE_GAP_S:
			_pile_t = _clock
			_event("digits_pile", [])
	if tier == HitTier.HEAVY and FxMaterial.is_metal(cls):
		_event("metal", [])


func _event(ev: String, args: Array) -> void:
	events.append({"event": ev, "args": args, "t": _clock})
	juice_event.emit(ev, args)


func _process(delta: float) -> void:
	var real := FxClock.real_delta(delta)
	_clock += real
	if Stasis.on and stasis_badge == null:
		_ensure_stasis_badge()
	_outline_t += real
	if _outline_t >= OUTLINE_SCAN_S:
		_outline_t = 0.0
		_tick_outlines()


## Обводка: новые куклы группы dolls получают её по одной за проход; видимость = outline_on и камера не захвачена эффектом.
func _tick_outlines() -> void:
	if not is_inside_tree():
		return
	var captured := _match != null and _match.has_method("camera_owner") and String(_match.call("camera_owner")) != ""
	var show := outline_on and not captured
	var dolls := get_tree().get_nodes_in_group("dolls")
	if show:
		for d in dolls:
			if d is Doll and not (d as Node).has_meta(DollOutline.META) and (d as Node).is_inside_tree():
				DollOutline.ensure(d, paint_colour(d))
				break
	for d in dolls:
		if (d as Node).has_meta(DollOutline.META):
			var on: bool = (d as Node).get_meta("outline_shown", true)
			if on != show:
				DollOutline.set_visible(d, show)
				(d as Node).set_meta("outline_shown", show)
	_outline_shown = show


## Масштаб камеры для людей: 1 / user_zoom (больше — ближе).
static func zoom_level() -> float:
	return 1.0 / maxf(DynamicCamera.user_zoom, 0.01)


static func set_zoom_level(level: float) -> void:
	DynamicCamera.user_zoom = clampf(1.0 / maxf(level, 0.01), ZOOM_RANGE.x, ZOOM_RANGE.y)


## Строки панели клавиш (KeysPanel): [клавиша, что делает, текущее значение]; пустая клавиша — заголовок.
func keys_lines() -> Array:
	var on := func(b: bool) -> String: return tr("вкл") if b else tr("выкл")
	var rows: Array = [
		["", tr("Бой"), ""],
		["WASD", tr("лететь"), ""],
		["Shift", tr("ускорение (держать, Заряд)"), ""],
		["Space + A/D", tr("раскрутка (держать)"), ""],
		["Tab", tr("панель управления"), ControlFeel.label()],
		["V  /  T", tr("вариант / темп управления"), ""],
		["J", tr("ДРАЙВ: импульс живёт"), tr("вкл") if Drive.on else tr("выкл")],
		["C", tr("прочность суставов: конечности отлетают"), on.call(JointBreak.on)],
		["X", tr("СТАЗИС: время идёт, только пока двигаешься"), on.call(Stasis.on)],
		[tr("ЛКМ / ПКМ"), tr("тяги рук"), ""],
		["I  O  P", tr("активные блоки"), ""],
		["R", tr("бой заново"), ""],
		["1–9", tr("сменить площадку"), ""],
		["Esc", tr("пауза"), ""],
		["H", tr("интерфейс боя"), HudSkin.label()],
		["", tr("Эффекты удара"), ""],
		["=", tr("стиль удара"), tr("серьёзный") if impact_style == "serious" else tr("мульт")],
		["0", tr("замедление"), variant_title()],
		["−", tr("цифры урона"), on.call(digits_on)],
		["B", tr("обводка бойцов"), on.call(outline_on)],
		[tr("колесо  ,  ."), tr("масштаб камеры"), "%.2f×" % zoom_level()],
		["F10", tr("яркость эффектов"), FxPreset.title()],
	]
	var gfx := get_node_or_null("/root/Gfx") if is_inside_tree() else null
	if gfx != null and gfx.has_method("label"):
		rows.append(["F9", tr("качество графики"), String(gfx.call("label"))])
	var arena := get_tree().get_first_node_in_group("arena") if is_inside_tree() else null
	if arena != null and arena.has_method("call_champion"):
		rows.append(["", tr("Купол"), ""])
		rows.append(["K", tr("вызвать чемпиона лиги"), ""])
		rows.append(["G", tr("поле NULL"), ""])
	rows.append(["L", tr("скрыть эту панель"), ""])
	return rows


func _zoom(step: float) -> void:
	set_zoom_level(zoom_level() * step)
	show_toast(tr("Масштаб камеры: %.2f×   (колесо мыши или «,» «.»)") % zoom_level())
	if keys_panel != null:
		keys_panel.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := (event as InputEventMouseButton).button_index
		if mb == MOUSE_BUTTON_WHEEL_UP or mb == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(ZOOM_STEP if mb == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_HELP:
			help_open = not help_open
			keys_panel.set_open(help_open)
			get_viewport().set_input_as_handled()
		KEY_OUTLINE:
			outline_on = not outline_on
			_tick_outlines()
			show_toast(tr("Обводка бойцов: %s   (B — переключить)") % (tr("вкл") if outline_on else tr("выкл")))
			get_viewport().set_input_as_handled()
		KEY_ZOOM_IN:
			_zoom(ZOOM_STEP)
			get_viewport().set_input_as_handled()
		KEY_ZOOM_OUT:
			_zoom(1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		KEY_VARIANT:
			cycle_time_variant()
			show_toast(tr("Замедление: %s   (0 — следующее)") % variant_title())
			keys_panel.refresh()
			get_viewport().set_input_as_handled()
		KEY_STYLE:
			impact_style = "cartoon" if impact_style == "serious" else "serious"
			show_toast(tr("Удар: %s   (= — переключить)") % style_title())
			keys_panel.refresh()
			get_viewport().set_input_as_handled()
		KEY_JOINTS:
			JointBreak.toggle()
			show_toast(tr("Прочность суставов: %s   (C — переключить)") % (tr("вкл — конечности отлетают, дальние суставы слабее") if JointBreak.on else tr("выкл")), 2.4)
			keys_panel.refresh()
			get_viewport().set_input_as_handled()
		KEY_STASIS:
			Stasis.toggle()
			if Stasis.on:
				_ensure_stasis_badge()
			show_toast(tr("СТАЗИС: %s   (X — переключить)") % (tr("вкл — время идёт, только пока ты двигаешься") if Stasis.on else tr("выкл")), 2.4)
			keys_panel.refresh()
			get_viewport().set_input_as_handled()
		KEY_DIGITS:
			digits_on = not digits_on
			if not digits_on:
				digits.clear()
			show_toast(tr("Цифры урона: %s   (− — переключить)") % (tr("вкл") if digits_on else tr("выкл")))
			get_viewport().set_input_as_handled()


## Метка СТАЗИСА на HUD (StasisBadge) — на своём слое; видимость решает сама (Stasis.on, фаза, крит-кино).
func _ensure_stasis_badge() -> void:
	if stasis_badge != null and is_instance_valid(stasis_badge):
		return
	var layer := CanvasLayer.new()
	layer.name = "StasisLayer"
	layer.layer = StasisBadge.LAYER
	add_child(layer)
	stasis_badge = StasisBadge.new()
	stasis_badge.name = "StasisBadge"
	stasis_badge.match_node = _match
	layer.add_child(stasis_badge)


## Тост внизу экрана (как F10 площадки), поверх HUD; живёт в реальном времени.
func show_toast(text: String, secs: float = TOAST_S) -> void:
	if _toast == null or not is_instance_valid(_toast):
		var layer := CanvasLayer.new()
		layer.name = "JuiceToast"
		layer.layer = 20
		add_child(layer)
		_toast = Label.new()
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_toast.offset_left = -560.0
		_toast.offset_right = 560.0
		_toast.offset_top = -170.0
		_toast.offset_bottom = -130.0
		_toast.add_theme_font_size_override("font_size", 26)
		_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_toast.add_theme_constant_override("outline_size", 6)
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_toast)
	_toast.text = text
	_toast.modulate = Color(1, 1, 1, 1)
	_toast.visible = true
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = _toast.create_tween().set_ignore_time_scale(true)
	_toast_tw.tween_interval(secs)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.3)
	_toast_tw.tween_callback(func() -> void: _toast.visible = false)
