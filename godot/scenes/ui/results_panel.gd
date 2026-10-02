## Панель итогов (R20 RESULTS/VICTORY + 09 §19–§20): слева корона и «P1 WINS!» (имя цветом игрока), кнопки-планки
## REMATCH (сигнал rematch → Match.restart()) и MAIN MENU (сигнал main_menu → гараж, hud.gd → Flow.to_menu); справа деревянная рамка:
## места с портретами, таблица статистики (KO, урон нанесён/получен, сильнейший удар, время в воздухе, MAX COMBO,
## COMBO SCORE; лучшее в строке — золотом) и ряд медалей из results.medals {name: Doll}.
## show_results(winner, results): results = {places: Array[Doll], stats: {doll: stats}, medals: {name: doll}, ranks, ko_records};
## stats читаются по ключу-кукле, запасной ключ — player_index. winner == null → «DRAW!» без короны. ranks[i] — место places[i]
## (Match.build_results: двойной KO в одном тике — оба «1ST»); KO на портрете — жертвы ko_records; без ranks/ko_records —
## место по индексу и KO у всех, кроме первого.
## Дерево узлов — scenes/ui/results_panel.tscn; строки таблицы/места/медали строятся по данным при показе.
class_name ResultsPanel
extends Control

signal rematch
signal main_menu

const PortraitScene: PackedScene = preload("res://scenes/ui/portrait.tscn")
## [подпись, ключ stats, формат, меньше = лучше]
const STAT_ROWS := [
	["KO", "kos", "%d", false],
	["DAMAGE DEALT", "damage_dealt", "%.0f", false],
	["DAMAGE TAKEN", "damage_taken", "%.0f", true],
	["HARDEST HIT", "hardest_hit", "%.1f", false],
	["AIR TIME", "air_time", "%.1f s", false],
	["MAX COMBO", "combo_max", "%d", false],
	["COMBO SCORE", "combo_score", "%d", false],
]
const MEDAL_ICONS := {
	"Winner": "👑", "Hardest Hit": "💥", "Frequent Flyer": "✈️", "Showman": "😂", "Wall Inspector": "🧱",
	"Weapon Master": "🔨", "Survivor": "🪳", "Self Destruction": "💀", "Acrobat": "🤸",
}
const PLACE_NAMES := ["1ST", "2ND", "3RD", "4TH"]
const GOLD := Color(1.0, 0.85, 0.4, 1.0)

@onready var winner_name: Label = $Left/WinnerRow/WinnerName
@onready var wins_text: Label = $Left/WinnerRow/WinsText
@onready var crown: TextureRect = $Left/Crown
@onready var rematch_btn: Button = $Left/Rematch
@onready var menu_btn: Button = $Left/MainMenu
@onready var places_row: HBoxContainer = $Frame/Body/Places
@onready var stats_grid: GridContainer = $Frame/Body/Stats
@onready var medals_row: HFlowContainer = $Frame/Body/Medals
@onready var medals_title: Label = $Frame/Body/MedalsTitle
@onready var left: VBoxContainer = $Left
@onready var frame: PanelContainer = $Frame


func _ready() -> void:
	visible = false
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())
	rematch_btn.pressed.connect(func() -> void: rematch.emit())
	menu_btn.pressed.connect(func() -> void: main_menu.emit())


## REMATCH — главная кнопка по скину HUD (scripts/ui/hud_skin.gd; в сцене — старые доски): трансляция — янтарная плашка,
## неон — янтарное стекло, LED — панель с янтарной рамкой.
func _apply_skin() -> void:
	var normal: StyleBox
	var hover: StyleBox
	var ink: Color
	match HudSkin.id():
		"neon":
			normal = HudSkin.glass(HudSkin.NEON_AMBER, 34.0, 10.0)
			hover = HudSkin.glass(Color.WHITE, 34.0, 10.0)
			ink = HudSkin.NEON_AMBER.lerp(Color.WHITE, 0.4)
		"led":
			normal = HudSkin.led_box(34.0, 10.0, HudSkin.LED)
			hover = HudSkin.led_box(34.0, 10.0, Color.WHITE)
			ink = HudSkin.LED
		_:
			normal = Broadcast.plate(Broadcast.AMBER, Broadcast.SKEW, 34.0, 10.0)
			var h := Broadcast.plate(Broadcast.AMBER.lightened(0.15), Broadcast.SKEW, 34.0, 10.0)
			h.edge_color = Color.WHITE
			h.edge_w = 8.0
			hover = h
			ink = Broadcast.INK
	rematch_btn.add_theme_stylebox_override("normal", normal)
	rematch_btn.add_theme_stylebox_override("hover", hover)
	rematch_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	rematch_btn.add_theme_stylebox_override("pressed", normal)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		rematch_btn.add_theme_color_override(c, ink)


static func player_of(doll: Object) -> int:
	if doll == null:
		return -1
	var v: Variant = doll.get("player_index")
	return int(v) if v != null else -1


static func colour_of(doll: Object) -> Color:
	var i := player_of(doll)
	if i < 0:
		return Color(0.8, 0.8, 0.8)
	return Tuning.PLAYER_COLORS[clampi(i, 0, Tuning.PLAYER_COLORS.size() - 1)]


static func label_of(doll: Object) -> String:
	var i := player_of(doll)
	return "P%d" % (i + 1) if i >= 0 else "?"


func _stats_of(stats: Dictionary, doll: Object) -> Dictionary:
	if stats.has(doll):
		return stats[doll]
	var i := player_of(doll)
	if stats.has(i):
		return stats[i]
	return {}


func _fmt(fmt: String, v: Variant) -> String:
	if v == null:
		return "—"
	if fmt.contains("d"):
		return fmt % int(v)
	return fmt % float(v)


func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


func show_results(winner: Object, results: Dictionary) -> void:
	var places: Array = results.get("places", [])
	var stats: Dictionary = results.get("stats", {})
	var medals: Dictionary = results.get("medals", {})
	var ranks: Array = results.get("ranks", [])
	var has_ko := results.has("ko_records")
	var knocked: Array = []
	for r in results.get("ko_records", []):
		knocked.append((r as Dictionary).get("victim"))
	if winner != null:
		winner_name.text = label_of(winner)
		winner_name.add_theme_color_override("font_color", colour_of(winner).lightened(0.25))
		wins_text.text = "WINS!"
		crown.visible = true
	else:
		winner_name.text = "DRAW!"
		winner_name.add_theme_color_override("font_color", Color(0.95, 0.93, 0.9))
		wins_text.text = ""
		crown.visible = false
	# места
	_clear(places_row)
	for i in range(places.size()):
		var d: Object = places[i]
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 2)
		var p: Portrait = PortraitScene.instantiate()
		p.custom_minimum_size = Vector2(72, 72)
		col.add_child(p)
		p.set_player(player_of(d))
		p.set_ko(knocked.has(d) if has_ko else (i > 0 and d != winner))
		var rank := int(ranks[i]) if i < ranks.size() else i
		var place := Label.new()
		place.theme_type_variation = &"DisplayLabel"
		place.add_theme_font_size_override("font_size", 22)
		place.text = PLACE_NAMES[mini(rank, PLACE_NAMES.size() - 1)]
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if rank == 0:
			place.add_theme_color_override("font_color", GOLD)
		col.add_child(place)
		places_row.add_child(col)
	# таблица: подпись + столбец на игрока (в порядке мест)
	_clear(stats_grid)
	stats_grid.columns = 1 + places.size()
	var header := Label.new()
	header.theme_type_variation = &"SmallCaps"
	header.text = ""
	stats_grid.add_child(header)
	for d in places:
		var h := Label.new()
		h.theme_type_variation = &"DisplayLabel"
		h.add_theme_font_size_override("font_size", 24)
		h.text = label_of(d)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_theme_color_override("font_color", colour_of(d).lightened(0.35))
		h.custom_minimum_size = Vector2(150, 0)
		stats_grid.add_child(h)
	for row in STAT_ROWS:
		var key: String = row[1]
		var lower_better: bool = row[3]
		var best: float = INF if lower_better else -INF
		var vals: Array = []
		for d in places:
			var s := _stats_of(stats, d)
			var v: Variant = s.get(key, null)
			vals.append(v)
			if v != null:
				best = minf(best, float(v)) if lower_better else maxf(best, float(v))
		var l := Label.new()
		l.theme_type_variation = &"StatLabel"
		l.text = row[0]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_grid.add_child(l)
		for v in vals:
			var c := Label.new()
			c.theme_type_variation = &"StatValue"
			c.text = _fmt(row[2], v)
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			c.custom_minimum_size = Vector2(150, 0)
			if v != null and places.size() > 1 and is_equal_approx(float(v), best) and float(v) != 0.0:
				c.add_theme_color_override("font_color", GOLD)
			stats_grid.add_child(c)
	# медали
	_clear(medals_row)
	medals_title.visible = not medals.is_empty()
	for medal_name in medals.keys():
		var d: Object = medals[medal_name]
		var chip := PanelContainer.new()
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var t := Label.new()
		t.theme_type_variation = &"StatLabel"
		t.text = "%s %s" % [MEDAL_ICONS.get(medal_name, "🏅"), String(medal_name).to_upper()]
		h.add_child(t)
		var who := Label.new()
		who.theme_type_variation = &"StatValue"
		who.text = label_of(d)
		who.add_theme_color_override("font_color", colour_of(d).lightened(0.35))
		h.add_child(who)
		chip.add_child(h)
		medals_row.add_child(chip)
	visible = true
	modulate = Color(1, 1, 1, 0)
	left.scale = Vector2(0.9, 0.9)
	left.pivot_offset = left.size * 0.5
	var tw := create_tween().set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.25)
	tw.tween_property(left, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rematch_btn.grab_focus()


func hide_panel() -> void:
	visible = false
