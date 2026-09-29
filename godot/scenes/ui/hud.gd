## HUD боя (R20 IN-GAME HUD, план 06 «HUD», 09 итоги). CanvasLayer поверх площадки; дерево — scenes/ui/hud.tscn:
##   Root/Players   — панели игроков (scenes/ui/player_panel.tscn), P1/P2 по верхним углам, P3/P4 под ними;
##   Root/TimerBox  — таймер mm:ss по центру сверху в тёмной панели, под ним красная «SUDDEN DEATH» (пульсирует);
##   Root/Announcer — диктор (announcer.gd): FIGHT!, HEAD BLOW!, N HIT COMBO!, KO!, SUDDEN DEATH;
##   Root/KoCard    — карточка KO (ko_card.tscn), 1.2 с; пока она видна, стек диктора пуст и новые надписи не
##                    показываются (карточка сама пишет KO!; раньше KO!/BODY BLOW! просвечивали под брызгами «призраками»);
##   Root/Results   — панель итогов (results_panel.tscn): места, статистика, медали, REMATCH → Match.restart().
## bind(match): подписка на сигналы Match (phase_changed, time_left, announce, hp_changed, combo_changed, ko,
## match_over) по имени — типы не требуются, стаб с теми же сигналами (tests/hud_snapshot.gd) тоже подходит.
## Панели ключуются по player_index, а не по узлу куклы: после restart()/респавна куклы могут быть новыми инстансами.
## Короны раундов — победы в этой сессии (match_over инкрементирует), слоты round_slots (0..3).
## Все размеры — в единицах базового вьюпорта 1920×1080 (project.godot: stretch canvas_items), на 1280×720 масштабируются.
class_name Hud
extends CanvasLayer

signal rematch_requested

enum Phase { COUNTDOWN, FIGHT, SUDDEN_DEATH, OVER }

const PlayerPanelScene: PackedScene = preload("res://scenes/ui/player_panel.tscn")
const PANEL_SIZE := Vector2(500, 136)
const PANEL_MARGIN := Vector2(24, 18)
const PANEL_ROW_GAP := 10.0
const SIGNALS := ["phase_changed", "time_left", "announce", "hp_changed", "combo_changed", "ko", "match_over"]
const RESULTS_MIN_DELAY_S := 0.3

## Слоты корон побед в раундах (0..3).
@export var round_slots := 2
## Непрозрачность чернильных брызг карточки KO; < 0 — как в ko_card.tscn. Void (чёрный фон, куклы в центре кадра RM)
## ставит 0: чёрные брызги на чёрном не видны, а поверх кукол вырезали тёмные «дыры» в разлёте частей.
@export var ko_splatter_alpha := -1.0

var match_node: Node
var panels: Dictionary = {}     # player_index -> PlayerPanel
var wins: Dictionary = {}       # player_index -> int
var phase: int = Phase.COUNTDOWN
var _pulse := 0.0
var _last_ms := 0
var _results_timer: SceneTreeTimer
var _cinematic_hidden: Array = []   # [[CanvasItem, was_visible]] — HIT_FX §3.1 set_cinematic

@onready var root: Control = $Root
@onready var players_root: Control = $Root/Players
@onready var timer_label: Label = $Root/TimerBox/TimerPanel/TimerLabel
@onready var sudden_death_label: Label = $Root/TimerBox/SuddenDeath
@onready var announcer: Announcer = $Root/Announcer
@onready var ko_card: KoCard = $Root/KoCard
@onready var results: ResultsPanel = $Root/Results


func _ready() -> void:
	add_to_group("hud")   # HIT_FX §4.1: CritCinematic находит HUD по группе
	sudden_death_label.visible = false
	if ko_splatter_alpha >= 0.0:
		ko_card.set_splatter_alpha(ko_splatter_alpha)
	results.rematch.connect(_on_rematch)
	results.visibility_changed.connect(_on_results_visibility)
	_last_ms = Time.get_ticks_msec()


## Пока открыты итоги, боевой HUD (панели, таймер) спрятан — экран итогов чистый, как на R20.
func _on_results_visibility() -> void:
	players_root.visible = not results.visible
	$Root/TimerBox.visible = not results.visible


## Подписка на Match (или любой узел с теми же сигналами и dolls()). Повторный bind переподписывает.
func bind(match_node_: Node) -> void:
	unbind()
	match_node = match_node_
	if match_node == null:
		return
	for s in SIGNALS:
		if match_node.has_signal(s):
			match_node.connect(s, Callable(self, "_on_" + s))
	if match_node.has_method("dolls"):
		for d in match_node.dolls():
			_ensure_panel(d)
	_layout_panels()


func unbind() -> void:
	if match_node != null and is_instance_valid(match_node):
		for s in SIGNALS:
			var cb := Callable(self, "_on_" + s)
			if match_node.has_signal(s) and match_node.is_connected(s, cb):
				match_node.disconnect(s, cb)
	match_node = null


static func player_of(doll: Object) -> int:
	if doll == null:
		return -1
	var v: Variant = doll.get("player_index")
	return int(v) if v != null else -1


func panel_for(index: int) -> PlayerPanel:
	if index < 0:
		return null
	if panels.has(index):
		return panels[index]
	var p: PlayerPanel = PlayerPanelScene.instantiate()
	p.slots = round_slots
	p.player_index = index
	players_root.add_child(p)
	p.set_player(index)
	p.set_wins(int(wins.get(index, 0)))
	panels[index] = p
	_layout_panels()
	return p


func _ensure_panel(doll: Object) -> PlayerPanel:
	return panel_for(player_of(doll))


## P1 слева сверху, P2 справа сверху, P3 под P1, P4 под P2 (якоря по углам, размеры в единицах 1080p).
func _layout_panels() -> void:
	for i in panels.keys():
		var p: PlayerPanel = panels[i]
		var idx := int(i)
		var right := idx % 2 == 1
		@warning_ignore("integer_division")
		var row := idx / 2
		p.set_side(right)
		p.anchor_left = 1.0 if right else 0.0
		p.anchor_right = p.anchor_left
		p.anchor_top = 0.0
		p.anchor_bottom = 0.0
		var top := PANEL_MARGIN.y + float(row) * (PANEL_SIZE.y + PANEL_ROW_GAP)
		p.offset_top = top
		p.offset_bottom = top + PANEL_SIZE.y
		if right:
			p.offset_left = -PANEL_MARGIN.x - PANEL_SIZE.x
			p.offset_right = -PANEL_MARGIN.x
		else:
			p.offset_left = PANEL_MARGIN.x
			p.offset_right = PANEL_MARGIN.x + PANEL_SIZE.x


func set_round_wins(index: int, n: int) -> void:
	wins[index] = n
	var p := panel_for(index)
	if p != null:
		p.set_wins(n)


## Фото игрока на портрет (этап 10); null — обратно инициалы.
func set_photo(index: int, tex: Texture2D) -> void:
	var p := panel_for(index)
	if p != null:
		p.portrait.set_photo(tex)


static func format_time(seconds: float) -> String:
	var s := int(ceil(maxf(seconds, 0.0)))
	@warning_ignore("integer_division")
	return "%02d:%02d" % [s / 60, s % 60]


# --- сигналы Match ---

func _on_phase_changed(p: int) -> void:
	phase = p
	sudden_death_label.visible = p == Phase.SUDDEN_DEATH
	timer_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if p == Phase.SUDDEN_DEATH else Color(0.96, 0.94, 0.9))
	if p == Phase.COUNTDOWN:
		results.hide_panel()
		ko_card.visible = false
		ko_card.cancel_defer()
		set_cinematic(false)
		announcer.clear()
		for i in panels.keys():
			(panels[i] as PlayerPanel).reset()
		if match_node != null and match_node.has_method("dolls"):
			for d in match_node.dolls():
				_ensure_panel(d)


func _on_time_left(seconds: float) -> void:
	timer_label.text = format_time(seconds)


func _on_announce(text: String, color: Color, kind: String) -> void:
	if ko_card.visible:
		return
	announcer.announce(text, color, kind)


func _on_hp_changed(doll: Object, hp: float, max_hp: float) -> void:
	var p := _ensure_panel(doll)
	if p != null:
		p.set_hp(hp, max_hp)


func _on_combo_changed(doll: Object, n: int) -> void:
	var p := _ensure_panel(doll)
	if p != null:
		p.set_combo(n)


func _on_ko(victim: Object, _attacker: Variant, _record: Dictionary) -> void:
	var idx := player_of(victim)
	var p := panel_for(idx)
	if p != null:
		p.set_ko(true)
	var colour: Color = Tuning.PLAYER_COLORS[clampi(idx, 0, Tuning.PLAYER_COLORS.size() - 1)] if idx >= 0 else Color.WHITE
	announcer.clear()   # KO! Match объявил до сигнала ko — карточка пишет его сама
	ko_card.show_card("P%d" % (idx + 1) if idx >= 0 else "", colour)


func _on_match_over(winner: Object, match_results: Dictionary) -> void:
	phase = Phase.OVER
	var w := player_of(winner)
	if w >= 0:
		wins[w] = int(wins.get(w, 0)) + 1
		var p := panel_for(w)
		if p != null:
			p.set_wins(int(wins[w]))
	# итоги — после карточки KO (реальное время, hit-stop/slow-mo не учитываются)
	var delay := maxf(ko_card.remaining_s() + 0.15, RESULTS_MIN_DELAY_S)
	_results_timer = get_tree().create_timer(delay, true, false, true)
	_results_timer.timeout.connect(func() -> void:
		if phase == Phase.OVER:
			results.show_results(winner, match_results))


## HIT_FX §3.1: на время кинематографа крита прячет панели игроков, таймер и диктор; при выходе
## возвращает видимость и чистит диктор (BODY BLOW! удара-крита не всплывает после ката).
func set_cinematic(on: bool) -> void:
	if on:
		if not _cinematic_hidden.is_empty():
			return
		for n: CanvasItem in [players_root, $Root/TimerBox as CanvasItem, announcer]:
			_cinematic_hidden.append([n, n.visible])
			n.visible = false
	else:
		if _cinematic_hidden.is_empty():
			return
		for e: Array in _cinematic_hidden:
			if is_instance_valid(e[0]):
				(e[0] as CanvasItem).visible = bool(e[1]) and not (results.visible and e[0] != announcer)
		_cinematic_hidden.clear()
		announcer.clear()


func is_cinematic() -> bool:
	return not _cinematic_hidden.is_empty()


## HIT_FX §3.3: карточка KO (уже показанная в KO) откладывается на real_s — показ после ката назад.
func defer_ko_card(real_s: float) -> void:
	ko_card.defer(real_s)


func _on_rematch() -> void:
	results.hide_panel()
	rematch_requested.emit()
	if match_node != null and match_node.has_method("restart"):
		match_node.restart()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	if sudden_death_label.visible:
		_pulse += dt * 5.0
		sudden_death_label.modulate = Color(1, 1, 1, 0.7 + 0.3 * sin(_pulse))
		sudden_death_label.scale = Vector2.ONE * (1.0 + 0.04 * sin(_pulse))
		sudden_death_label.pivot_offset = sudden_death_label.size * 0.5
