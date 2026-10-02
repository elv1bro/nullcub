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
## Говорят только N0 и табло (LORE_NULL.md «Голоса и тон»).
class_name HitJuice
extends Node

signal juice_event(event: String, args: Array)

const TOAST_S := 1.6
const HINT_S := 4.0
const KEY_VARIANT := KEY_0
const KEY_DIGITS := KEY_MINUS
const KEY_STYLE := KEY_EQUAL
const STYLE_TITLES := {"serious": "серьёзный (свет, пыль, волна воздуха)", "cartoon": "мульт (звезда и кольца, как было)"}
const PILE_N := 8
const PILE_GAP_S := 20.0

## Вариант замедления (ключ Tuning.JUICE_TIME_VARIANTS) — общий на все площадки, переживает смену арены.
static var time_variant: String = Tuning.JUICE_TIME_DEFAULT
## Стиль вспышки удара (Tuning.JUICE_IMPACT_STYLES): "serious" — короткий жар, свет и пыль; "cartoon" — прежняя звезда RM и кольца.
static var impact_style: String = Tuning.JUICE_IMPACT_STYLE_DEFAULT
## Цифры-обломки включены (клавиша «−») — общий флаг.
static var digits_on: bool = Tuning.JUICE_DIGITS

var marks_enabled: bool = Tuning.JUICE_MARKS
var digits: DamageDigits
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


static func variant() -> Dictionary:
	return Tuning.JUICE_TIME_VARIANTS.get(time_variant, Tuning.JUICE_TIME_VARIANTS[Tuning.JUICE_TIME_DEFAULT])


## Следующий вариант замедления по кругу (клавиша 0). Возвращает ключ.
static func cycle_time_variant() -> String:
	var order: Array = Tuning.JUICE_TIME_ORDER
	var i := order.find(time_variant)
	time_variant = String(order[(i + 1) % order.size()])
	return time_variant


## Надпись табло для крита (N0_VOICE.md п. 3): «IMPACT 18.4G» — score удара.
static func impact_caption(ctx: Dictionary, fallback: String) -> String:
	if not Tuning.JUICE_IMPACT_CAPTION:
		return fallback
	var sc := float(ctx.get("score", 0.0))
	if sc <= 0.0:
		sc = float(ctx.get("damage", 0.0))
	return "IMPACT %.1fG" % sc if sc > 0.0 else fallback


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
	return "0 — замедление: %s    −  — цифры: %s    =  — удар: %s" % [String(variant().get("title", time_variant)),
		"вкл" if digits_on else "выкл", "серьёзный" if impact_style == "serious" else "мульт"]


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
	_clock += FxClock.real_delta(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_VARIANT:
			cycle_time_variant()
			show_toast("Замедление: %s   (0 — следующее)" % String(variant().get("title", time_variant)))
			get_viewport().set_input_as_handled()
		KEY_STYLE:
			impact_style = "cartoon" if impact_style == "serious" else "serious"
			show_toast("Удар: %s   (= — переключить)" % String(STYLE_TITLES.get(impact_style, impact_style)))
			get_viewport().set_input_as_handled()
		KEY_DIGITS:
			digits_on = not digits_on
			if not digits_on:
				digits.clear()
			show_toast("Цифры урона: %s   (− — переключить)" % ("вкл" if digits_on else "выкл"))
			get_viewport().set_input_as_handled()


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
