## HUD «Стычки 3 на 3» (docs/plan-demo/SQUAD.md; автор 06.10: «всё оформить красиво, весь HUD — не как сейчас, просто линии»).
## Боевой HUD (scenes/ui/hud.gd) рассчитан на 2–4 панели игроков — шесть закрыли бы карту, поэтому здесь свой, как в командных шутерах.
## Почти всё рисует один слой canvas (_draw, обновляется каждый кадр): плашки со скосом и градиентом, кольца, значки (SquadIcons),
## текст — шрифтом скина HUD (HudSkin), ужимается по ширине (языков 10+, строка не вылезает из плашки):
##   • сверху по центру — табло: плашки команд (синие слева, красные справа) со счётом, часы, режим и «до N»; в захвате флага — флаг
##     команды у плашки (дома / унесён — мигает / лежит);
##   • справа сверху — лента выбываний: фишки «кто — чем — кого» цветами команд; доставки флагов;
##   • над каждым бойцом — имя, полоска HP (броня — под ней), значок класса; несущий флаг — флаг над головой; соперник за кадром —
##     стрелка у края экрана с метрами; флаг за кадром — стрелка-флаг;
##   • прицел у курсора (автор 06.10: «показать на нём больше информации; между выстрелами — жёлтый; длина — докуда достанет выстрел»):
##     кольцо — магазин (деления), цвет — готов / пауза между выстрелами (жёлтый, ход паузы) / перезарядка (красный, ход) / пусто /
##     заряд гаусса (голубой, %); луч от дула — до стены или дальности, конец луча — крестик (стена) или кружок; у громилы — готовность
##     полёта и сколько осталось лететь;
##   • слева снизу — карточка бойца: значок класса в кольце опыта с номером уровня, имя и класс, HP с делениями, броня, бонусы с
##     таймерами; справа снизу — карточка оружия: картинка (SquadIcons.picture), магазин / запас, деления магазина, перезарядка,
##     пауза, заряд, полёт громилы; рука оторвана — красная плашка «любой ящик вернёт»;
##   • на отсчёте и пока ждёшь возврата — выбор класса: три карточки с картинкой оружия, классом, описанием, запасом и ветками;
##   • новый уровень — древо класса как в Skyrim (автор 06.10: «древо развития после получения уровня, вверх, и сразу пишешь бонус»):
##     ствол уровней 1–4 снизу вверх, на 5-м — развилка веток (подклассов), их уровни 5–8 выше; новый узел горит и подписан бонусом;
##     ждёт выбор ветки — ветки мигают с клавишами 1…N и таймером;
##   • выбыл — кольцо отсчёта «возврат через N»; конец — табличка победителя со счётом и таблицей бойцов (Label — проба вёрстки).
## Диктор (Announcer) — отсчёт, FIGHT!, KO! игрока, его уровень, ящик, события флагов. bind(match) — подписка на SquadMatch.
class_name SquadHud
extends CanvasLayer

const TOP := 14.0
const FEED_MAX := 6
const FEED_HOLD_S := 6.0
const HINT_S := 10.0
const BAR_W := 74.0
const BAR_H := 8.0
const BAR_LIFT := 0.62           # м над головой
const ARROW_MARGIN := 46.0
const ARMOR_COLOUR := Color(0.55, 0.82, 1.0)
const GOLD := Color(1.0, 0.8, 0.32)
const INK := Color(0.035, 0.04, 0.06)
const DIGIT_S := 0.7              # цифра урона живёт столько реальных секунд и всплывает на DIGIT_RISE px
const DIGIT_RISE := 46.0
const AIM_DASH := 0.35            # м: штрих луча прицела
const TREE_S := 4.5               # древо после нового уровня висит столько (с), ждёт выбор ветки — пока не выбрана
const CARD := Vector2(470.0, 176.0)
const STATE_COLOURS := {"ready": Color(1.0, 1.0, 1.0), "cooldown": Color(1.0, 0.86, 0.25), "reload": Color(1.0, 0.36, 0.3),
	"empty": Color(1.0, 0.25, 0.22), "charging": Color(0.45, 0.92, 1.0), "none": Color(1.0, 0.25, 0.22)}
const CLASS_ICONS := {"brawler": "fist", "sniper": "scope", "raider": "shell"}

var match_node: SquadMatch
var root: Control
var canvas: Control
var announcer: Announcer
var icons: SquadIcons
var end_panel: PanelContainer
var end_title: Label
var end_score: Label
var end_table: GridContainer
var hint_text := ""
var _feed: Array = []            # [{kind, killer, victim, weapon, team, left}]
var _digits: Array = []          # [[мировая точка, текст, осталось с]]
var _tree := {}                  # {pi, level, unlock, left}: древо после нового уровня
var _clock := 0.0
var _pulse := 0.0
var _font: Font
var _pics: Dictionary = {}       # ключ картинки → Texture2D
var _sb: Dictionary = {}         # готовые StyleBoxFlat


func _init() -> void:
	layer = 10


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = HudSkin.theme()
	add_child(root)
	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_all)
	root.add_child(canvas)
	icons = SquadIcons.new()
	icons.name = "Icons"
	icons.picture_ready.connect(func(key: String, tex: Texture2D) -> void: _pics[key] = tex)
	add_child(icons)
	_build_end()
	announcer = Announcer.new()
	announcer.name = "Announcer"
	announcer.set_anchors_preset(Control.PRESET_CENTER)
	announcer.offset_top = -170.0
	announcer.offset_bottom = -170.0
	announcer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := VBoxContainer.new()
	st.name = "Stack"
	st.set_anchors_preset(Control.PRESET_CENTER)
	st.alignment = BoxContainer.ALIGNMENT_CENTER
	st.add_theme_constant_override("separation", -10)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announcer.add_child(st)
	root.add_child(announcer)
	hint_text = tr("WASD — лететь · мышь — прицел · ЛКМ — огонь (гаусс — держи; громила — полёт) · Q — перезарядка · 1–3 — класс · O — настройки")
	_apply_skin()
	HudSkin.events.changed.connect(func(_id: String) -> void: _apply_skin())


func _apply_skin() -> void:
	_font = HudSkin.font("display")
	if _font == null:
		_font = ThemeDB.fallback_font
	for l in root.find_children("*", "Label", true, false):
		if (l as Node).has_meta("px"):
			HudSkin.style_label(l, "display", int(l.get_meta("px")), l.get_meta("colour"))
			(l as Label).add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			(l as Label).add_theme_constant_override("outline_size", 6)
	if end_panel != null:
		end_panel.add_theme_stylebox_override("panel", _box(Color(0.03, 0.035, 0.05, 0.94), GOLD, 4, 10, 32.0))


## StyleBoxFlat: фон, рамка сверху (цвет, толщина), радиус, поля.
func _box(bg: Color, border: Color, top: int, radius: int, pad := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_top = top
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	return sb


func _label(n: String, px: int, c: Color) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_meta("px", px)
	l.set_meta("colour", c)
	return l


func _build_end() -> void:
	end_panel = PanelContainer.new()
	end_panel.name = "End"
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.offset_left = -470.0
	end_panel.offset_right = 470.0
	end_panel.offset_top = -230.0
	end_panel.offset_bottom = 290.0
	end_panel.visible = false
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 10)
	end_panel.add_child(v)
	end_title = _label("Title", 60, Color.WHITE)
	end_score = _label("Score", 50, Color.WHITE)
	end_table = GridContainer.new()
	end_table.name = "Table"
	end_table.columns = 6
	end_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	end_table.add_theme_constant_override("h_separation", 30)
	end_table.add_theme_constant_override("v_separation", 4)
	var again := _label("Again", 22, Color(1, 1, 1, 0.7))
	again.text = tr("R — заново · O — настройки · Esc — пауза и выход в гараж")
	for l in [end_title, end_score, end_table, again]:
		v.add_child(l)
	root.add_child(end_panel)


func bind(m: SquadMatch) -> void:
	match_node = m
	var pairs := [["frag", _on_frag], ["announce", _on_announce], ["match_over", _on_over], ["phase_changed", _on_phase],
		["bullet_landed", _on_bullet], ["melee_landed", _on_bullet], ["leveled", _on_leveled], ["branch_pending", _on_branch_pending],
		["class_changed", _on_class_changed], ["supply_taken", _on_supply], ["flag_event", _on_flag]]
	for p in pairs:
		if m.has_signal(p[0]) and not m.is_connected(p[0], p[1]):
			m.connect(p[0], p[1])


## Имя бойца для ленты и меток: человек — ТЫ, бот — цвет команды и номер в ней.
static func name_of(d: Object) -> String:
	if d == null or not is_instance_valid(d):
		return TranslationServer.translate("ПОЛИГОН")
	var dd := d as Doll
	if not dd.external_input:
		return TranslationServer.translate("ТЫ")
	var n := dd.player_index / 2 + 1
	return (TranslationServer.translate("СИНИЙ %d") if SquadMatch.team_of(dd) == 0 else TranslationServer.translate("КРАСНЫЙ %d")) % n


## Что открыл уровень — для древа: оружие с пояснением, рукопашное оружие, усиление; выбор ветки.
static func unlock_text(unlock: Dictionary) -> String:
	if unlock.has("weapon"):
		var w: Dictionary = Tuning.SQUAD_WEAPONS[String(unlock["weapon"])]
		return "%s — %s" % [TranslationServer.translate(String(w["title"])), TranslationServer.translate(String(w["note"]))]
	if unlock.has("melee"):
		var m: Dictionary = Tuning.SQUAD_MELEE[String(unlock["melee"])]
		return "%s — %s" % [TranslationServer.translate(String(m["title"])), TranslationServer.translate(String(m["note"]))]
	if unlock.has("perk"):
		return TranslationServer.translate(String(Tuning.SQUAD_PERKS[String(unlock["perk"])]["title"]))
	if unlock.has("choose"):
		return TranslationServer.translate("ВЫБЕРИ ПОДКЛАСС")
	return ""


## Короткая подпись узла древа (оружие или усиление).
static func node_text(unlock: Dictionary) -> String:
	if unlock.has("weapon"):
		return TranslationServer.translate(String(Tuning.SQUAD_WEAPONS[String(unlock["weapon"])]["title"]))
	if unlock.has("melee"):
		return TranslationServer.translate(String(Tuning.SQUAD_MELEE[String(unlock["melee"])]["title"]))
	if unlock.has("perk"):
		return TranslationServer.translate(String(Tuning.SQUAD_PERKS[String(unlock["perk"])]["title"]))
	return ""


## Название ветки (подкласса): оружие её 5-го уровня.
static func branch_title(cls: String, branch: String) -> String:
	var br: Dictionary = (Tuning.SQUAD_CLASSES[cls]["branches"] as Dictionary).get(branch, {})
	if br.is_empty():
		return ""
	return node_text((br["levels"] as Array)[0])


## Пояснение ветки: описание её оружия.
static func branch_note(cls: String, branch: String) -> String:
	var br: Dictionary = (Tuning.SQUAD_CLASSES[cls]["branches"] as Dictionary).get(branch, {})
	if br.is_empty():
		return ""
	var u: Dictionary = (br["levels"] as Array)[0]
	if u.has("weapon"):
		return TranslationServer.translate(String(Tuning.SQUAD_WEAPONS[String(u["weapon"])]["note"]))
	if u.has("melee"):
		return TranslationServer.translate(String(Tuning.SQUAD_MELEE[String(u["melee"])]["note"]))
	return ""


# --- сигналы ---

func _on_frag(killer: Doll, victim: Doll, team: int) -> void:
	_feed.append({"kind": "ko", "killer": name_of(killer) if killer != null else "", "victim": name_of(victim),
		"kt": SquadMatch.team_of(killer) if killer != null else -1, "vt": SquadMatch.team_of(victim),
		"weapon": tr(match_node.weapon_name(killer)) if killer != null and match_node != null else "", "left": FEED_HOLD_S})
	while _feed.size() > FEED_MAX:
		_feed.pop_front()
	if killer != null and not killer.external_input:
		announcer.announce(tr("KO!"), GOLD, "ko")


## Попадание: у пуль и ударов игрока — цифра урона над точкой попадания.
func _on_bullet(_victim: Doll, shooter: Doll, damage: float, pos: Vector3) -> void:
	if shooter == null or shooter != _human():
		return
	_digits.append([pos, str(int(round(damage))), DIGIT_S])
	if _digits.size() > 24:
		_digits.pop_front()


## Новый уровень у игрока: древо на TREE_S и строка диктора.
func _on_leveled(pi: int, level: int, unlock: Dictionary) -> void:
	var me := _human()
	if me == null or me.player_index != pi:
		return
	_tree = {"pi": pi, "level": level, "unlock": unlock, "left": TREE_S}
	if not unlock.has("branch") or level == Tuning.SQUAD_BRANCH_LEVEL:
		announcer.announce(tr("УРОВЕНЬ %d") % level, Color(0.6, 1.0, 0.55), "event")


func _on_branch_pending(pi: int, _cls: String) -> void:
	var me := _human()
	if me != null and me.player_index == pi:
		_tree = {"pi": pi, "level": int(match_node.loadout(pi)["level"]), "unlock": {"choose": true}, "left": TREE_S}


func _on_class_changed(pi: int, cls: String, pending: bool) -> void:
	var me := _human()
	if me != null and me.player_index == pi:
		var t := tr(String(Tuning.SQUAD_CLASSES[cls]["title"]))
		announcer.announce(tr("%s — С ВОЗВРАТА") % t if pending else t, Color(0.9, 0.9, 0.95), "event")


func _on_supply(d: Doll, kind: String) -> void:
	if d != null and d == _human():
		var def: Dictionary = Tuning.SQUAD_SUPPLY.get(kind, {})
		announcer.announce(tr(String(def.get("title", ""))), def.get("colour", Color.WHITE), "event")


## Флаги: лента и диктор (что важно игроку — его флаг, флаг соперника, доставка).
func _on_flag(team: int, what: String, d: Doll) -> void:
	var me := _human()
	var mine := me != null and SquadMatch.team_of(me) == team
	var words := {"taken": "ФЛАГ ВЗЯТ", "dropped": "ФЛАГ УПАЛ", "returned": "ФЛАГ ДОМА", "captured": "ФЛАГ ДОСТАВЛЕН"}
	var who_team := SquadMatch.team_of(d) if d != null else team
	_feed.append({"kind": "flag", "killer": name_of(d) if d != null else "", "kt": who_team, "vt": team,
		"victim": tr(words.get(what, "")), "weapon": "", "left": FEED_HOLD_S})
	while _feed.size() > FEED_MAX:
		_feed.pop_front()
	var txt := ""
	match what:
		"taken":
			txt = tr("НАШ ФЛАГ УНЕСЛИ!") if mine else tr("ФЛАГ СОПЕРНИКА ВЗЯТ")
		"captured":
			txt = tr("ФЛАГ ДОСТАВЛЕН!")
		"returned":
			txt = tr("НАШ ФЛАГ ДОМА") if mine else ""
		"dropped":
			txt = tr("ФЛАГ УПАЛ")
	if txt != "":
		announcer.announce(txt, SquadMatch.team_colour(team).lightened(0.35), "event")


func _on_announce(text: String, color: Color, kind: String) -> void:
	if kind in ["countdown", "fight"]:
		announcer.announce(text, color, kind)


func _on_phase(p: int) -> void:
	if p == Match.Phase.COUNTDOWN:
		end_panel.visible = false
		_clock = 0.0
		_feed.clear()
		_digits.clear()
		_tree = {}


func _on_over(_winner: Doll, results: Dictionary) -> void:
	var wt := int(results.get("winner_team", -1))
	if wt < 0:
		end_title.text = tr("НИЧЬЯ")
		end_title.set_meta("colour", Color.WHITE)
	else:
		end_title.text = tr("ПОБЕДА СИНИХ") if wt == 0 else tr("ПОБЕДА КРАСНЫХ")
		end_title.set_meta("colour", SquadMatch.team_colour(wt).lightened(0.35))
	var sc: Array = results.get("score", [0, 0])
	end_score.text = "%d : %d" % [int(sc[0]), int(sc[1])]
	for c in end_table.get_children():
		end_table.remove_child(c)
		c.queue_free()
	var ctf := String(results.get("mode", "dm")) == "ctf"
	var white := Color(1, 1, 1, 0.7)
	var heads := [tr("БОЕЦ"), tr("КЛАСС"), tr("ФРАГИ"), tr("ВЫБЫЛ"), tr("УРОН"), tr("ФЛАГИ") if ctf else tr("УР.")]
	for h in heads:
		_cell(h, white, end_table.get_child_count() == 0, 20)
	var tally: Dictionary = results.get("tally", {})
	var dolls: Array = match_node.dolls() if match_node != null else []
	dolls.sort_custom(func(a: Doll, b: Doll) -> bool:
		if SquadMatch.team_of(a) != SquadMatch.team_of(b):
			return SquadMatch.team_of(a) < SquadMatch.team_of(b)
		return a.player_index < b.player_index)
	var best := -1
	for d in dolls:
		best = maxi(best, int((tally.get((d as Doll).player_index, {}) as Dictionary).get("kills", 0)))
	for d in dolls:
		var pi := (d as Doll).player_index
		var t: Dictionary = tally.get(pi, {})
		var c := SquadMatch.team_colour(SquadMatch.team_of(d)).lightened(0.4)
		var star := " ★" if int(t.get("kills", 0)) == best and best > 0 else ""
		_cell(name_of(d) + star, c, true, 22)
		var lo := match_node.loadout(pi)
		_cell(tr(String(Tuning.SQUAD_CLASSES[String(lo["class"])]["title"])), Color(1, 1, 1, 0.8), true, 20)
		_cell(str(int(t.get("kills", 0))), Color.WHITE, false, 22)
		_cell(str(int(t.get("deaths", 0))), Color.WHITE, false, 22)
		_cell(str(int(round(float(t.get("damage", 0.0))))), Color.WHITE, false, 22)
		_cell(str(int(t.get("captures", 0))) if ctf else str(int(lo["level"])), Color.WHITE, false, 22)
	_apply_skin()
	end_panel.visible = true
	end_panel.modulate.a = 0.0
	var tw := end_panel.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.6)
	tw.tween_property(end_panel, "modulate:a", 1.0, 0.3)


## Клетка таблицы итогов: имя и класс — влево, числа — по центру колонки.
func _cell(text: String, c: Color, left: bool, px: int) -> void:
	var l := _label("Cell", px, c)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_CENTER
	end_table.add_child(l)


# --- кадр ---

func _human() -> Doll:
	return match_node.me() if match_node != null else null


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	_clock += real
	_pulse += real
	var i := 0
	while i < _feed.size():
		_feed[i]["left"] = float(_feed[i]["left"]) - real
		if float(_feed[i]["left"]) <= 0.0:
			_feed.remove_at(i)
		else:
			i += 1
	var j := 0
	while j < _digits.size():
		_digits[j][2] = float(_digits[j][2]) - real
		if float(_digits[j][2]) <= 0.0:
			_digits.remove_at(j)
		else:
			j += 1
	if not _tree.is_empty():
		var me := _human()
		var waiting := me != null and match_node.branch_left(me.player_index) >= 0.0
		if not waiting:
			_tree["left"] = float(_tree["left"]) - real
		if float(_tree["left"]) <= 0.0 or me == null or int(_tree["pi"]) != me.player_index:   # «я» сменился (снимки) — древо не его
			_tree = {}
	canvas.queue_redraw()


func _draw_all() -> void:
	if match_node == null:
		return
	var cam := get_viewport().get_camera_3d()
	var vp := get_viewport().get_visible_rect().size
	var to_canvas := canvas.get_global_transform_with_canvas().affine_inverse()
	var me := _human()
	if end_panel.visible:
		_draw_scoreboard(vp)
		return   # итоги: метки бойцов просвечивали бы сквозь табличку
	if cam != null:
		_draw_marks(cam, to_canvas, vp, me)
		_draw_flags(cam, to_canvas, vp, me)
	_draw_scoreboard(vp)
	_draw_feed(vp)
	if me == null:
		return
	var picking := match_node.play_state == "countdown" or (match_node.play_state == "play" and not me.alive)
	_draw_me(vp, me)
	_draw_weapon(vp, me)
	if picking:
		_draw_classes(vp, me)
	elif not _tree.is_empty():
		_draw_tree(vp, me)
	if cam != null and me.alive and match_node.play_state == "play":
		_draw_aim(cam, to_canvas, me)
	if not me.alive and match_node.play_state == "play":
		_draw_respawn(vp, me)
	if _clock < HINT_S:
		var a := clampf((HINT_S - _clock) / 1.2, 0.0, 1.0)
		_text(Vector2(vp.x * 0.5, vp.y - 20.0), hint_text, 20, Color(1, 1, 1, 0.75 * a), HORIZONTAL_ALIGNMENT_CENTER, vp.x - 1100.0)
	if cam != null:
		_draw_digits(cam, to_canvas)


# --- текст и плашки ---

## Текст: точка — базовая линия (align по x), шрифт px; не шире max_w (ужимается), с контуром.
func _text(at: Vector2, text: String, px: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, max_w := 0.0, outline := 5) -> float:
	if text == "" or col.a <= 0.01:
		return 0.0
	var size := px
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if max_w > 0.0 and w > max_w:
		size = maxi(int(float(px) * max_w / w), 9)
		w = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	if outline > 0:
		canvas.draw_string_outline(_font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 0.85 * col.a))
	canvas.draw_string(_font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return w


## Текст в несколько строк (по словам) шириной max_w, не больше lines строк (не влезло — шрифт меньше); at — базовая линия первой
## строки (align по x), шаг строк — px × 1.2. Возвращает число строк.
func _text_wrap(at: Vector2, text: String, px: int, col: Color, align: HorizontalAlignment, max_w: float, lines := 2) -> int:
	var size := px
	var out: Array = []
	while true:
		out = _wrap(text, size, max_w)
		if out.size() <= lines or size <= 10:
			break
		size -= 1
	for i in mini(out.size(), lines):
		_text(at + Vector2(0.0, float(i) * float(size) * 1.2), String(out[i]), size, col, align, max_w, 4)
	return mini(out.size(), lines)


func _wrap(text: String, px: int, max_w: float) -> Array:
	var out: Array = []
	var line := ""
	for w in text.split(" ", false):
		var t := w if line == "" else line + " " + w
		if line != "" and _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_w:
			out.append(line)
			line = w
		else:
			line = t
	if line != "":
		out.append(line)
	return out


## Скруглённая плашка: фон, рамка (цвет, толщина) и тень.
func _round(r: Rect2, bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 8, shadow := true) -> void:
	var key := "%s/%s/%d/%d/%s" % [bg.to_html(), border.to_html(), bw, radius, shadow]
	if not _sb.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(bw)
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		if shadow:
			sb.shadow_color = Color(0, 0, 0, 0.35)
			sb.shadow_size = 6
		_sb[key] = sb
	(_sb[key] as StyleBoxFlat).draw(canvas.get_canvas_item(), r)


## Полоса с делениями: фон, заполнение frac цветом col (блик сверху), деления каждые step единиц из full.
func _bar(r: Rect2, frac: float, col: Color, full := 0.0, step := 0.0) -> void:
	_round(r.grow(2.0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0), 0, 4, false)
	var f := clampf(frac, 0.0, 1.0)
	if f > 0.0:
		var fr := Rect2(r.position, Vector2(r.size.x * f, r.size.y))
		canvas.draw_rect(fr, col)
		canvas.draw_rect(Rect2(fr.position, Vector2(fr.size.x, r.size.y * 0.38)), Color(1, 1, 1, 0.22))
	if step > 0.0 and full > step:
		var n := int(full / step)
		for k in range(1, n + 1):
			var x := r.position.x + r.size.x * (float(k) * step / full)
			if x < r.end.x - 1.0:
				canvas.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.55), 2.0)


## Картинка оружия id (готова — текстура, нет — значок класса или патрон) в прямоугольнике r.
func _weapon_pic(r: Rect2, id: String, team: int, fallback: String) -> void:
	var c := SquadMatch.team_colour(team)
	var key := "%s/%s" % [id, c.to_html(false)]
	var tex: Texture2D = _pics.get(key, null)
	if tex == null:
		tex = icons.picture(id, c)
		if tex != null:
			_pics[key] = tex
	if tex != null:
		var ts := tex.get_size()
		var k := minf(r.size.x / ts.x, r.size.y / ts.y)
		var sz := ts * k
		canvas.draw_texture_rect(tex, Rect2(r.get_center() - sz * 0.5, sz), false)
	else:
		_icon(fallback, r.get_center(), minf(r.size.x, r.size.y) * 0.7, Color(1, 1, 1, 0.85))


## Значок: векторный (SquadIcons) плюс свои для классов — прицел, патрон дроби.
func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	match id:
		"scope":
			canvas.draw_arc(c, s * 0.38, 0.0, TAU, 32, col, maxf(s * 0.09, 1.5), true)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				canvas.draw_line(c + d * s * 0.18, c + d * s * 0.5, col, maxf(s * 0.08, 1.5))
		"shell":
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.38), Vector2(s * 0.4, s * 0.56)), col)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.24, s * 0.18), Vector2(s * 0.48, s * 0.2)), col.darkened(0.35))
		_:
			SquadIcons.draw(canvas, id, c, s, col)


# --- табло ---

func _draw_scoreboard(vp: Vector2) -> void:
	var cx := vp.x * 0.5
	var pw := 250.0
	var ph := 78.0
	var tw := 190.0
	var y := TOP
	for t in 2:
		var tc := SquadMatch.team_colour(t)
		var x0 := cx - tw * 0.5 - 8.0 - pw if t == 0 else cx + tw * 0.5 + 8.0
		var r := Rect2(x0, y, pw, ph)
		SquadIcons.plate(canvas, r.grow(3.0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55), 14.0 if t == 0 else -14.0)
		SquadIcons.plate(canvas, r, tc.lightened(0.18), tc.darkened(0.35), 14.0 if t == 0 else -14.0)
		var sc := str(int(match_node.score[t]))
		var name_t := tr("СИНИЕ") if t == 0 else tr("КРАСНЫЕ")
		if t == 0:
			_text(Vector2(x0 + 26.0, y + 28.0), name_t, 22, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_LEFT, pw * 0.5)
			_text(Vector2(x0 + pw - 20.0, y + ph - 12.0), sc, 66, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		else:
			_text(Vector2(x0 + pw - 26.0, y + 28.0), name_t, 22, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_RIGHT, pw * 0.5)
			_text(Vector2(x0 + 20.0, y + ph - 12.0), sc, 66, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		if match_node.is_ctf():
			_flag_status(t, Vector2(x0 + (40.0 if t == 0 else pw - 40.0), y + ph - 26.0))
	var tr_ := Rect2(cx - tw * 0.5, y + 4.0, tw, ph - 8.0)
	_round(tr_, INK.lerp(Color(0.08, 0.09, 0.12), 0.5), Color(1, 1, 1, 0.18), 2, 6)
	var s := int(ceil(maxf(match_node.time_left_s(), 0.0)))
	var low := match_node.play_state == "play" and s <= 30
	_text(Vector2(cx, y + ph * 0.5 + 16.0), "%d:%02d" % [s / 60, s % 60], 46, Color(1.0, 0.45, 0.35) if low else Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER)
	var mode_t := tr("ЗАХВАТ ФЛАГА") if match_node.is_ctf() else tr("ПЕРЕСТРЕЛКА")
	var cap := tr("%s · ДО %d") % [mode_t, match_node.score_to_win]
	var cw := _font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 36.0
	_round(Rect2(cx - cw * 0.5, y + ph + 6.0, cw, 30.0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), 0, 15, false)
	_text(Vector2(cx, y + ph + 28.0), cap, 20, Color(1, 1, 1, 0.88), HORIZONTAL_ALIGNMENT_CENTER, 560.0)


## Флаг команды t на табло: дома — белый, унесён — мигает цветом команды с «!», лежит — пульсирует.
func _flag_status(t: int, at: Vector2) -> void:
	var f := match_node.flag_of(t)
	if f == null:
		return
	var col := Color.WHITE
	match f.state:
		"carried":
			col = Color(1.0, 0.95, 0.4) if fmod(_pulse, 0.5) < 0.25 else SquadMatch.team_colour(t).lightened(0.5)
		"dropped":
			col = Color(1, 1, 1, 0.45 + 0.4 * absf(sin(_pulse * 5.0)))
	canvas.draw_circle(at, 17.0, Color(0, 0, 0, 0.45))
	_icon("flag", at, 26.0, col)
	if f.state == "carried":
		_text(at + Vector2(16.0, -6.0), "!", 22, Color(1.0, 0.95, 0.4))


# --- лента ---

func _draw_feed(vp: Vector2) -> void:
	var y := 22.0
	for e in _feed:
		var a := clampf(float(e["left"]) / 0.6, 0.0, 1.0)
		var kc := SquadMatch.team_colour(int(e["kt"])).lightened(0.4) if int(e["kt"]) >= 0 else Color(0.85, 0.85, 0.85)
		var vc := SquadMatch.team_colour(int(e["vt"])).lightened(0.4)
		var k := String(e["killer"])
		var w := String(e["weapon"])
		var v := String(e["victim"])
		var px := 22
		var kw := _font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x if k != "" else 0.0
		var ww := _font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x if w != "" else 0.0
		var vw := _font.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var icon_w := 26.0
		var total := kw + vw + icon_w + (ww + 12.0 if w != "" else 0.0) + 40.0
		var r := Rect2(vp.x - 24.0 - total, y, total, 36.0)
		_round(r, Color(0.03, 0.035, 0.05, 0.72 * a), Color(kc.r, kc.g, kc.b, 0.9 * a), 0, 6, false)
		canvas.draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), Color(kc.r, kc.g, kc.b, a))
		var x := r.position.x + 14.0
		var base := y + 26.0
		if k != "":
			_text(Vector2(x, base), k, px, Color(kc.r, kc.g, kc.b, a), HORIZONTAL_ALIGNMENT_LEFT, 0.0, 4)
			x += kw + 8.0
		_icon("flag" if String(e["kind"]) == "flag" else "skull", Vector2(x + 10.0, y + 18.0), 20.0, Color(1, 1, 1, 0.85 * a))
		x += icon_w
		if w != "":
			_text(Vector2(x, base - 1.0), w, 17, Color(0.82, 0.82, 0.86, a), HORIZONTAL_ALIGNMENT_LEFT, 0.0, 3)
			x += ww + 12.0
		_text(Vector2(x, base), v, px, Color(vc.r, vc.g, vc.b, a), HORIZONTAL_ALIGNMENT_LEFT, 0.0, 4)
		y += 42.0


# --- карточка бойца ---

func _draw_me(vp: Vector2, me: Doll) -> void:
	var pi := me.player_index
	var t := SquadMatch.team_of(me)
	var tc := SquadMatch.team_colour(t)
	var lo := match_node.loadout(pi)
	var cls := String(lo["class"])
	var r := Rect2(24.0, vp.y - CARD.y - 22.0, CARD.x, CARD.y)
	_round(r, Color(0.03, 0.035, 0.05, 0.82), tc.lightened(0.2), 0, 12)
	canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), tc.lightened(0.2))
	# значок класса в кольце опыта, номер уровня
	var cc := r.position + Vector2(76.0, 92.0)
	canvas.draw_circle(cc, 54.0, Color(0.07, 0.08, 0.11))
	SquadIcons.ring(canvas, cc, 60.0, 7.0, match_node.xp_progress(pi), Color(0.55, 1.0, 0.5), Color(1, 1, 1, 0.08))
	_icon(String(CLASS_ICONS.get(cls, "star")), cc + Vector2(0.0, -6.0), 54.0, tc.lightened(0.45))
	var lv := int(lo["level"])
	canvas.draw_circle(cc + Vector2(0.0, 48.0), 18.0, GOLD)
	_text(cc + Vector2(0.0, 56.0), str(lv), 24, INK, HORIZONTAL_ALIGNMENT_CENTER, 0.0, 0)
	# имя и класс
	var x0 := r.position.x + 152.0
	var wcol := r.end.x - x0 - 18.0
	var br := String(lo["branch"])
	var cls_t := tr(String(Tuning.SQUAD_CLASSES[cls]["title"]))
	if br != "":
		cls_t += " · " + branch_title(cls, br)
	_text(Vector2(x0, r.position.y + 38.0), "%s · %s" % [name_of(me), cls_t], 25, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, wcol)
	# HP
	var hp := me.hp if me.alive else 0.0
	var hpr := Rect2(x0 + 30.0, r.position.y + 54.0, wcol - 90.0, 24.0)
	_icon("heart", Vector2(x0 + 11.0, hpr.position.y + 12.0), 22.0, Color(1.0, 0.4, 0.4))
	_bar(hpr, hp / maxf(me.max_hp, 1.0), tc.lightened(0.25) if hp > me.max_hp * 0.3 else Color(1.0, 0.35, 0.3), me.max_hp, 25.0)
	_text(Vector2(hpr.end.x + 10.0, hpr.end.y - 3.0), str(int(ceil(hp))), 26, Color.WHITE)
	# броня
	var ar := match_node.armor_of(me) if me.alive else 0.0
	var arr := Rect2(x0 + 30.0, r.position.y + 90.0, wcol - 90.0, 12.0)
	_icon("shield", Vector2(x0 + 11.0, arr.position.y + 6.0), 18.0, ARMOR_COLOUR)
	_bar(arr, ar / Tuning.SQUAD_ARMOR_MAX, ARMOR_COLOUR, Tuning.SQUAD_ARMOR_MAX, 25.0)
	_text(Vector2(arr.end.x + 10.0, arr.end.y + 2.0), str(int(round(ar))), 20, ARMOR_COLOUR)
	# бонусы — значки с таймерами; ждёт выбор ветки — напоминание
	var bx := x0
	var by := r.position.y + 140.0
	for k in Tuning.SQUAD_BOOSTS:
		var left := match_node.boost_left(me, k)
		if left <= 0.0:
			continue
		var def: Dictionary = Tuning.SQUAD_SUPPLY[k]
		var col: Color = def["colour"]
		var c := Vector2(bx + 18.0, by)
		canvas.draw_circle(c, 18.0, Color(0, 0, 0, 0.55))
		SquadIcons.ring(canvas, c, 18.0, 3.0, left / float(def["seconds"]), col, Color(0, 0, 0, 0))
		_icon(SquadIcons.supply_icon(k), c, 20.0, col)
		_text(c + Vector2(24.0, 7.0), "%d" % int(ceil(left)), 18, col)
		bx += 78.0
	var wait := match_node.branch_left(pi)
	if wait >= 0.0 and bx == x0:
		_text(Vector2(x0, by + 7.0), tr("ВЫБЕРИ ПОДКЛАСС: 1–%d") % (Tuning.SQUAD_CLASSES[cls]["branch_order"] as Array).size(), 20,
			GOLD.lerp(Color.WHITE, absf(sin(_pulse * 4.0)) * 0.5), HORIZONTAL_ALIGNMENT_LEFT, wcol)


# --- карточка оружия ---

func _draw_weapon(vp: Vector2, me: Doll) -> void:
	var t := SquadMatch.team_of(me)
	var tc := SquadMatch.team_colour(t)
	var r := Rect2(vp.x - 24.0 - CARD.x, vp.y - CARD.y - 22.0, CARD.x, CARD.y)
	_round(r, Color(0.03, 0.035, 0.05, 0.82), tc.lightened(0.2), 0, 12)
	canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), tc.lightened(0.2))
	var g := SquadMatch.gun_of(me)
	var ml := SquadMatch.melee_of(me)
	var pic := Rect2(r.position + Vector2(14.0, 16.0), Vector2(210.0, 110.0))
	var x1 := r.position.x + 238.0
	var w1 := r.end.x - x1 - 16.0
	var armless := me.alive and not match_node.has_weapon_arm(me)
	if g != null and g.weapon != "":
		_weapon_pic(pic, g.weapon, t, "bullet")
		_text(Vector2(pic.get_center().x, r.end.y - 18.0), tr(String(Tuning.SQUAD_WEAPONS[g.weapon]["title"])), 24, Color(1.0, 0.92, 0.7),
			HORIZONTAL_ALIGNMENT_CENTER, pic.size.x)
		var st := g.state()
		var sc: Color = STATE_COLOURS.get(st, Color.WHITE)
		var mw := _text(Vector2(x1, r.position.y + 72.0), str(g.mag), 64, sc if st != "ready" else Color.WHITE)
		_text(Vector2(x1 + mw + 10.0, r.position.y + 72.0), "/ %d" % g.reserve, 28, Color(1, 1, 1, 0.7))
		# деления магазина
		var n := mini(g.mag_max, 32)
		var pw := minf((w1 - 4.0) / float(maxi(n, 1)), 22.0)
		for k in n:
			var on := k < int(float(g.mag) * float(n) / float(maxi(g.mag_max, 1)) + 0.001)
			canvas.draw_rect(Rect2(x1 + float(k) * pw, r.position.y + 88.0, pw - 3.0, 12.0), sc if on else Color(1, 1, 1, 0.12))
		var line := ""
		var frac := -1.0
		match st:
			"reload":
				line = tr("ПЕРЕЗАРЯДКА")
				frac = maxf(g.reload_progress(), 0.0)
			"empty":
				line = tr("ПАТРОНОВ НЕТ — РУКОПАШНАЯ")
			"charging":
				line = tr("ЗАРЯД %d %%") % int(round(g.charge * 100.0))
				frac = g.charge
			"cooldown":
				line = tr("ПАУЗА")
				frac = g.cooldown_frac()
			_:
				line = tr("ГОТОВ") if not g.charges() else tr("ДЕРЖИ ЛКМ — ЗАРЯД")
		_text(Vector2(x1, r.position.y + 134.0), line, 20, sc, HORIZONTAL_ALIGNMENT_LEFT, w1)
		if frac >= 0.0:
			_bar(Rect2(x1, r.position.y + 144.0, w1, 8.0), frac, sc)
	elif ml != null and ml.weapon_id != "":
		_weapon_pic(pic, ml.weapon_id, t, "fist")
		var md: Dictionary = Tuning.SQUAD_MELEE[ml.weapon_id]
		_text(Vector2(pic.get_center().x, r.end.y - 18.0), tr(String(md["title"])), 24, Color(1.0, 0.92, 0.7), HORIZONTAL_ALIGNMENT_CENTER,
			pic.size.x)
		var ready := ml.can_dash()
		var col := Color(1.0, 0.62, 0.25) if ml.dashing else (Color(0.5, 1.0, 0.55) if ready else Color(1, 1, 1, 0.55))
		_text(Vector2(x1, r.position.y + 58.0), tr("ПОЛЁТ"), 40, col, HORIZONTAL_ALIGNMENT_LEFT, w1)
		var line2 := tr("ЛЕТИТ · %.1f с") % maxf(Tuning.SQUAD_DASH_S - ml.dash_t, 0.0) if ml.dashing else (tr("ГОТОВ — ЖМИ ЛКМ") if ready else tr("ПАУЗА"))
		_text(Vector2(x1, r.position.y + 92.0), line2, 20, col, HORIZONTAL_ALIGNMENT_LEFT, w1)
		_bar(Rect2(x1, r.position.y + 104.0, w1, 10.0), ml.ready_frac(), col)
		_text(Vector2(x1, r.position.y + 140.0), tr(String(md["note"])), 17, Color(1, 1, 1, 0.65), HORIZONTAL_ALIGNMENT_LEFT, w1)
	if armless:
		var ab := Rect2(r.position.x, r.position.y - 46.0, r.size.x, 38.0)
		_round(ab, Color(0.55, 0.06, 0.05, 0.85 + 0.15 * sin(_pulse * 6.0)), Color(0, 0, 0, 0), 0, 8)
		_text(Vector2(ab.get_center().x, ab.position.y + 27.0), tr("РУКА ОТОРВАНА · ЛЮБОЙ ЯЩИК ВЕРНЁТ"), 22, Color.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER, ab.size.x - 20.0)


# --- выбор класса ---

func _draw_classes(vp: Vector2, me: Doll) -> void:
	var pi := me.player_index
	var lo := match_node.loadout(pi)
	var t := SquadMatch.team_of(me)
	var tc := SquadMatch.team_colour(t)
	var n := Tuning.SQUAD_CLASS_ORDER.size()
	var cw := 330.0
	var ch := 336.0
	var gap := 22.0
	var total := cw * n + gap * (n - 1)
	var x0 := vp.x * 0.5 - total * 0.5
	var y0 := vp.y - CARD.y - 40.0 - ch
	var pending := String(lo["next_class"]) != String(lo["class"])
	var title := tr("ВЫБЕРИ КЛАСС · ЖМИ 1–%d") % n + ("  ·  " + tr("сменится при возврате") if pending else "")
	_text(Vector2(vp.x * 0.5, y0 - 16.0), title, 28, GOLD, HORIZONTAL_ALIGNMENT_CENTER, total)
	for k in n:
		var id := String(Tuning.SQUAD_CLASS_ORDER[k])
		var c: Dictionary = Tuning.SQUAD_CLASSES[id]
		var r := Rect2(x0 + float(k) * (cw + gap), y0, cw, ch)
		var on := id == String(lo["next_class"])
		_round(r, Color(0.04, 0.045, 0.065, 0.9 if on else 0.78), tc.lightened(0.3) if on else Color(1, 1, 1, 0.12), 3 if on else 1, 12)
		if on:
			_round(r.grow(6.0), Color(0, 0, 0, 0), Color(tc.r, tc.g, tc.b, 0.35 + 0.25 * absf(sin(_pulse * 3.0))), 3, 16, false)
		canvas.draw_circle(r.position + Vector2(28.0, 28.0), 18.0, GOLD if on else Color(1, 1, 1, 0.2))
		_text(r.position + Vector2(28.0, 37.0), str(k + 1), 24, INK if on else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 0.0, 0)
		_weapon_pic(Rect2(r.position + Vector2(40.0, 30.0), Vector2(cw - 80.0, 120.0)), String(c["icon"]), t,
			String(CLASS_ICONS.get(id, "star")))
		_text(Vector2(r.get_center().x, r.position.y + 186.0), tr(String(c["title"])), 34, Color.WHITE if on else Color(1, 1, 1, 0.85),
			HORIZONTAL_ALIGNMENT_CENTER, cw - 24.0)
		_text_wrap(Vector2(r.get_center().x, r.position.y + 214.0), tr(String(c["note"])), 18, Color(1, 1, 1, 0.72), HORIZONTAL_ALIGNMENT_CENTER,
			cw - 28.0, 2)
		var hp_s := tr("HP %d") % int(c["hp"])
		if float(c["armor"]) > 0.0:
			hp_s += " · " + tr("БРОНЯ %d") % int(c["armor"])
		if float(c.get("zoom", 1.0)) > 1.0:
			hp_s += " · " + tr("ОБЗОР ×%.1f") % float(c["zoom"])
		_text(Vector2(r.get_center().x, r.position.y + 262.0), hp_s, 19, ARMOR_COLOUR, HORIZONTAL_ALIGNMENT_CENTER, cw - 24.0)
		var names: Array = []
		for b in c["branch_order"]:
			names.append(branch_title(id, String(b)))
		_text(Vector2(r.get_center().x, r.position.y + 292.0), tr("5 УР.: %s") % " / ".join(names), 18, GOLD, HORIZONTAL_ALIGNMENT_CENTER,
			cw - 24.0)
		var start_w := String((c["levels"] as Array)[0].get("weapon", (c["levels"] as Array)[0].get("melee", "")))
		var sw: String = node_text((c["levels"] as Array)[0])
		if start_w != "":
			_text(Vector2(r.get_center().x, r.position.y + 318.0), tr("старт: %s") % sw, 16, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER,
				cw - 24.0)


# --- древо ---

## Древо класса (как в Skyrim): ствол 1–4 снизу вверх, на SQUAD_BRANCH_LEVEL — развилка, ветки — выше. Горят открытые узлы, новый
## пульсирует и подписан бонусом; ждёт выбор — ветки с клавишами и таймером.
func _draw_tree(vp: Vector2, me: Doll) -> void:
	var pi := me.player_index
	var lo := match_node.loadout(pi)
	var cls := String(lo["class"])
	var c: Dictionary = Tuning.SQUAD_CLASSES[cls]
	var level := int(lo["level"])
	var branch := String(lo["branch"])
	var order: Array = c["branch_order"]
	var trunk: Array = c["levels"]
	var wait := match_node.branch_left(pi)
	var a := clampf(float(_tree.get("left", 1.0)) / 0.5, 0.0, 1.0) if wait < 0.0 else 1.0
	var pw := 500.0
	var ph := 640.0 if wait >= 0.0 else 625.0
	var r := Rect2(24.0, 150.0, pw, ph)   # слева: справа — лента, стрелки к соперникам за кадром и подсказка «L — клавиши»
	var bg := Color(0.02, 0.03, 0.06, 0.88 * a)
	SquadIcons.plate(canvas, r, Color(0.05, 0.06, 0.12, 0.9 * a), bg)
	_round(r, Color(0, 0, 0, 0), Color(GOLD.r, GOLD.g, GOLD.b, 0.5 * a), 2, 10, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 40:   # звёзды фона
		var sp := r.position + Vector2(rng.randf() * pw, rng.randf() * ph)
		canvas.draw_circle(sp, rng.randf_range(0.6, 1.8), Color(1, 1, 1, rng.randf_range(0.15, 0.5) * a))
	_text(Vector2(r.get_center().x, r.position.y + 40.0), tr("УРОВЕНЬ %d · %s") % [level, tr(String(c["title"]))], 30,
		Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, pw - 30.0)
	# узлы: ствол — по центру снизу вверх; ветки — веером выше
	var cx := r.get_center().x
	var y_base := r.position.y + 520.0
	var step := 52.0
	var pts := {}   # "t1".."t4", "<branch>5".."<branch>8" → Vector2
	for i in trunk.size():
		pts["t%d" % (i + 1)] = Vector2(cx, y_base - step * float(i))
	var top := y_base - step * float(trunk.size() - 1)
	var span := pw - 230.0
	for bi in order.size():
		var bx := cx + (float(bi) - float(order.size() - 1) * 0.5) * (span / maxf(float(order.size() - 1), 1.0) if order.size() > 1 else 0.0)
		var bl: Array = (c["branches"][order[bi]] as Dictionary)["levels"]
		for li in bl.size():
			pts["%s%d" % [order[bi], li + 5]] = Vector2(bx, top - 64.0 - step * float(li))
	var lit := GOLD
	var dim := Color(1, 1, 1, 0.18 * a)
	# линии
	for i in range(1, trunk.size()):
		canvas.draw_line(pts["t%d" % i], pts["t%d" % (i + 1)], Color(lit.r, lit.g, lit.b, a) if level > i else dim, 3.0, true)
	for b in order:
		var on_b := String(b) == branch
		canvas.draw_line(pts["t%d" % trunk.size()], pts["%s5" % b], Color(lit.r, lit.g, lit.b, a) if on_b and level >= 5 else dim, 3.0, true)
		for lv in range(5, 8):
			canvas.draw_line(pts["%s%d" % [b, lv]], pts["%s%d" % [b, lv + 1]], Color(lit.r, lit.g, lit.b, a) if on_b and level > lv else dim, 3.0, true)
	# узлы
	var new_lv := int(_tree.get("level", level))
	var new_key := ""
	if new_lv <= trunk.size():
		new_key = "t%d" % new_lv
	elif branch != "":
		new_key = "%s%d" % [branch, new_lv]
	for key in pts:
		var p: Vector2 = pts[key]
		var k := String(key)
		var lv := int(k.right(1))
		var on := level >= lv and (k.begins_with("t") or k.begins_with(branch) and branch != "")
		var is_new := k == new_key
		var rad := 15.0 if is_new else 11.0
		if is_new:
			var pr := rad + 6.0 + 4.0 * absf(sin(_pulse * 5.0))
			canvas.draw_circle(p, pr + 6.0, Color(lit.r, lit.g, lit.b, 0.18 * a))
			canvas.draw_arc(p, pr, 0.0, TAU, 32, Color(lit.r, lit.g, lit.b, 0.9 * a), 2.0, true)
		canvas.draw_circle(p, rad, Color(lit.r, lit.g, lit.b, a) if on else Color(0.12, 0.13, 0.18, a))
		canvas.draw_arc(p, rad, 0.0, TAU, 24, Color(1, 1, 1, (0.85 if on else 0.3) * a), 2.0, true)
	# подписи ствола (справа) и названия веток (над веткой)
	for i in trunk.size():
		var p: Vector2 = pts["t%d" % (i + 1)]
		var on := level >= i + 1
		_text(p + Vector2(24.0, 7.0), node_text(trunk[i]), 17, Color(1, 1, 1, (0.85 if on else 0.4) * a), HORIZONTAL_ALIGNMENT_LEFT,
			pw * 0.5 - 40.0)
		_text(p + Vector2(-24.0, 7.0), str(i + 1), 17, Color(1, 1, 1, 0.35 * a), HORIZONTAL_ALIGNMENT_RIGHT)
	var col_w := minf(span / maxf(float(order.size() - 1), 1.0), 200.0)
	for bi in order.size():
		var b := String(order[bi])
		var p8: Vector2 = pts["%s8" % b]
		var chosen := b == branch
		var tcol := Color(lit.r, lit.g, lit.b, a) if chosen else Color(1, 1, 1, (0.9 if wait >= 0.0 else 0.45) * a)
		if wait >= 0.0:
			tcol = tcol.lerp(GOLD, absf(sin(_pulse * 3.0 + bi)) * 0.6)
			canvas.draw_circle(p8 + Vector2(0.0, -48.0), 15.0, GOLD)
			_text(p8 + Vector2(0.0, -40.0), str(bi + 1), 22, INK, HORIZONTAL_ALIGNMENT_CENTER, 0.0, 0)
		_text(p8 + Vector2(0.0, -20.0), branch_title(cls, b), 22, tcol, HORIZONTAL_ALIGNMENT_CENTER, col_w)
	# что теперь; ждёт выбор — ветки с пояснениями и таймер
	var by := y_base + 44.0
	if wait >= 0.0:
		for bi in order.size():
			var b := String(order[bi])
			_text(Vector2(r.position.x + 24.0, by), "%d — %s: %s" % [bi + 1, branch_title(cls, b), branch_note(cls, b)], 19,
				Color(1, 1, 1, 0.9 * a), HORIZONTAL_ALIGNMENT_LEFT, pw - 48.0)
			by += 26.0
		_text(Vector2(cx, by + 8.0), tr("ВЫБЕРИ ПОДКЛАСС: 1–%d · сам через %d с") % [order.size(), int(ceil(wait))], 22,
			GOLD.lerp(Color.WHITE, absf(sin(_pulse * 3.0)) * 0.4), HORIZONTAL_ALIGNMENT_CENTER, pw - 30.0)
	else:
		var u: Dictionary = _tree.get("unlock", {})
		if unlock_text(u) != "":
			_text_wrap(Vector2(cx, by), tr("ТЕПЕРЬ: %s") % unlock_text(u), 22, Color(0.75, 1.0, 0.7, a), HORIZONTAL_ALIGNMENT_CENTER, pw - 40.0, 2)


# --- над бойцами ---

func _draw_marks(cam: Camera3D, to_canvas: Transform2D, vp: Vector2, me: Doll) -> void:
	var my_team := SquadMatch.team_of(me) if me != null else 0
	for n in match_node.dolls():
		var d := n as Doll
		if not is_instance_valid(d) or not d.is_inside_tree() or not d.alive:
			continue
		var head: Node3D = d.parts.get("Head", d.torso()) as Node3D
		if head == null:
			continue
		var top := head.global_position + Vector3(0.0, BAR_LIFT, 0.0)
		if cam.is_position_behind(top):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(top)
		var t := SquadMatch.team_of(d)
		var c := SquadMatch.team_colour(t).lightened(0.3)
		var inside := sp.x > 0.0 and sp.y > 0.0 and sp.x < vp.x and sp.y < vp.y
		if not inside:
			if t != my_team and me != null:
				_arrow(sp, vp, c, me.centre_of_mass().distance_to(d.centre_of_mass()), "")
			continue
		var r := Rect2(sp - Vector2(BAR_W * 0.5, BAR_H * 0.5), Vector2(BAR_W, BAR_H))
		_round(r.grow(2.0), Color(0.02, 0.02, 0.03, 0.85), Color(0, 0, 0, 0), 0, 4, false)
		var f := clampf(d.hp / maxf(d.max_hp, 1.0), 0.0, 1.0)
		if f > 0.0:
			_round(Rect2(r.position, Vector2(BAR_W * f, BAR_H)), c, Color(0, 0, 0, 0), 0, 3, false)
		var ar := match_node.armor_of(d)
		if ar > 0.0:
			var a_r := Rect2(r.position + Vector2(0.0, BAR_H + 3.0), Vector2(BAR_W * clampf(ar / Tuning.SQUAD_ARMOR_MAX, 0.0, 1.0), 3.0))
			canvas.draw_rect(a_r.grow(1.0), Color(0.02, 0.02, 0.03, 0.85))
			canvas.draw_rect(a_r, ARMOR_COLOUR)
		var cls := String(match_node.loadout(d.player_index)["class"])
		_icon(String(CLASS_ICONS.get(cls, "star")), r.position + Vector2(-12.0, BAR_H * 0.5), 16.0, c)
		var txt := name_of(d)
		var fs := 18 if d != me else 20
		_text(sp + Vector2(0.0, -10.0), txt, fs, Color.WHITE if d == me else c, HORIZONTAL_ALIGNMENT_CENTER)
		var bx := sp.x - 20.0
		for k in Tuning.SQUAD_BOOSTS:
			if match_node.boost_left(d, k) > 0.0:
				_icon(SquadIcons.supply_icon(k), Vector2(bx, sp.y - 40.0), 16.0, Tuning.SQUAD_SUPPLY[k]["colour"])
				bx += 20.0
		if match_node.carried_flag(d) != null:
			var fc := SquadMatch.team_colour(1 - t).lightened(0.3)
			_icon("flag", sp + Vector2(0.0, -58.0), 34.0, fc.lerp(Color.WHITE, absf(sin(_pulse * 5.0)) * 0.4))


## Флаги за кадром — стрелки-флаги у края экрана (захват флага).
func _draw_flags(cam: Camera3D, to_canvas: Transform2D, vp: Vector2, me: Doll) -> void:
	if not match_node.is_ctf() or me == null:
		return
	for t in 2:
		var f := match_node.flag_of(t)
		if f == null or f.state == "carried":
			continue
		var p := f.global_position + Vector3(0.0, 0.8, 0.0)
		if cam.is_position_behind(p):
			continue
		var sp: Vector2 = to_canvas * cam.unproject_position(p)
		if sp.x > 0.0 and sp.y > 0.0 and sp.x < vp.x and sp.y < vp.y:
			continue
		_arrow(sp, vp, SquadMatch.team_colour(t).lightened(0.35), me.centre_of_mass().distance_to(f.global_position), "flag")


func _arrow(sp: Vector2, vp: Vector2, c: Color, metres: float, icon: String) -> void:
	var centre := vp * 0.5
	var dir := (sp - centre)
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var half := centre - Vector2(ARROW_MARGIN, ARROW_MARGIN + 30.0)
	var k := minf(half.x / maxf(absf(dir.x), 1e-4), half.y / maxf(absf(dir.y), 1e-4))
	var p := centre + dir * k
	if p.x > vp.x - 160.0 and absf(p.y - centre.y) < 36.0:
		p.y += 48.0 * (1.0 if p.y >= centre.y else -1.0)   # справа посередине — подсказка «L — клавиши» (HitJuice): стрелка мимо неё
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([p + dir * 18.0, p - dir * 10.0 + side * 12.0, p - dir * 10.0 - side * 12.0])
	canvas.draw_colored_polygon(pts, c)
	canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 2.0)
	if icon != "":
		canvas.draw_circle(p - dir * 34.0, 16.0, Color(0, 0, 0, 0.55))
		_icon(icon, p - dir * 34.0, 22.0, c)
	_text(p - dir * (60.0 if icon != "" else 34.0) + Vector2(0.0, 6.0), tr("%d м") % int(round(metres)), 18, c, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_digits(cam: Camera3D, to_canvas: Transform2D) -> void:
	for e in _digits:
		var wp := e[0] as Vector3
		if cam.is_position_behind(wp):
			continue
		var k2 := clampf(float(e[2]) / DIGIT_S, 0.0, 1.0)
		var dp: Vector2 = to_canvas * cam.unproject_position(wp) + Vector2(0.0, -DIGIT_RISE * (1.0 - k2))
		_text(dp, String(e[1]), 28, Color(1.0, 0.95, 0.6, k2), HORIZONTAL_ALIGNMENT_CENTER)


# --- прицел ---

## Прицел игрока: луч от дула до места, куда долетит выстрел (стена — крестик, дальность — кружок), и кольцо у курсора — магазин,
## состояние (готов / пауза — жёлтый / перезарядка / пусто / заряд), число патронов. Громила — готовность и ход полёта.
func _draw_aim(cam: Camera3D, to_canvas: Transform2D, me: Doll) -> void:
	var mouse := canvas.get_local_mouse_position()
	var g := SquadMatch.gun_of(me)
	var ml := SquadMatch.melee_of(me)
	if me.external_input:   # «я» — бот (снимки, пробы): прицел — у конца луча, а не у мыши
		var ae := g.aim_end() if g != null and g.weapon != "" else []
		if not ae.is_empty() and not cam.is_position_behind(ae[0]):
			mouse = to_canvas * cam.unproject_position(ae[0] as Vector3)
	if g != null and g.weapon != "":
		var st := g.state()
		var col: Color = STATE_COLOURS.get(st, Color.WHITE)
		var ray := g.aim_ray()
		var end := g.aim_end()
		if not ray.is_empty() and not end.is_empty():
			var o := ray[0] as Vector3
			var e := end[0] as Vector3
			var dir := ray[1] as Vector3
			var reach := o.distance_to(e)
			var n := int(reach / (AIM_DASH * 2.0))
			for k in n:
				var a3 := o + dir * (float(k) * AIM_DASH * 2.0)
				var b3 := a3 + dir * AIM_DASH
				if cam.is_position_behind(a3) or cam.is_position_behind(b3):
					continue
				var fade := 1.0 - 0.6 * float(k) / float(maxi(n, 1))
				canvas.draw_line(to_canvas * cam.unproject_position(a3), to_canvas * cam.unproject_position(b3),
					Color(col.r, col.g, col.b, 0.55 * fade), 2.0, true)
			if not cam.is_position_behind(e):
				var ep: Vector2 = to_canvas * cam.unproject_position(e)
				if bool(end[1]):
					canvas.draw_line(ep + Vector2(-7, -7), ep + Vector2(7, 7), col, 3.0, true)
					canvas.draw_line(ep + Vector2(-7, 7), ep + Vector2(7, -7), col, 3.0, true)
				else:
					canvas.draw_arc(ep, 6.0, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.7), 2.0, true)
		_reticle(mouse, g, st, col)
	elif ml != null and ml.weapon_id != "":
		var col2 := Color(1.0, 0.62, 0.25) if ml.dashing else (Color(0.5, 1.0, 0.55) if ml.can_dash() else Color(1, 1, 1, 0.6))
		canvas.draw_circle(mouse, 26.0, Color(0, 0, 0, 0.25))
		SquadIcons.ring(canvas, mouse, 22.0, 5.0, ml.ready_frac(), col2, Color(1, 1, 1, 0.12))
		_icon("fist", mouse, 18.0, col2)
		if ml.dashing and not cam.is_position_behind(me.centre_of_mass()):
			var cp: Vector2 = to_canvas * cam.unproject_position(me.centre_of_mass())
			canvas.draw_dashed_line(cp, mouse, Color(col2.r, col2.g, col2.b, 0.6), 2.0, 10.0, true)


## Кольцо прицела у курсора: деления магазина (до 24, больше — сплошная дуга), ход паузы / перезарядки / заряда, число патронов.
func _reticle(c: Vector2, g: SquadGun, st: String, col: Color) -> void:
	var r := 24.0
	canvas.draw_circle(c, r + 6.0, Color(0, 0, 0, 0.22))
	var n := g.mag_max
	if n <= 24:
		var seg := TAU / float(n)
		for k in n:
			var a0 := -PI * 0.5 + seg * float(k) + 0.06
			var a1 := -PI * 0.5 + seg * float(k + 1) - 0.06
			var on := k < g.mag
			canvas.draw_arc(c, r, a0, a1, 6, Color(col.r, col.g, col.b, 0.95) if on else Color(1, 1, 1, 0.15), 4.0, true)
	else:
		SquadIcons.ring(canvas, c, r, 4.0, float(g.mag) / float(maxi(g.mag_max, 1)), col, Color(1, 1, 1, 0.15))
	match st:
		"cooldown":
			SquadIcons.ring(canvas, c, r - 7.0, 3.0, g.cooldown_frac(), col, Color(0, 0, 0, 0))
		"reload":
			SquadIcons.ring(canvas, c, r - 7.0, 4.0, maxf(g.reload_progress(), 0.0), col, Color(1, 1, 1, 0.1))
		"charging":
			SquadIcons.ring(canvas, c, r - 7.0, 6.0, g.charge, col, Color(1, 1, 1, 0.1))
			_text(c + Vector2(0.0, r + 44.0), "%d %%" % int(round(g.charge * 100.0)), 20, col, HORIZONTAL_ALIGNMENT_CENTER)
	canvas.draw_circle(c, 2.5, col)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		canvas.draw_line(c + d * 6.0, c + d * 12.0, Color(col.r, col.g, col.b, 0.8), 2.0)
	var label := str(g.mag)
	if st == "reload":
		label = tr("ПЕРЕЗАРЯДКА")
	elif st == "empty":
		label = tr("ПУСТО")
	_text(c + Vector2(0.0, r + 24.0), label, 20, col, HORIZONTAL_ALIGNMENT_CENTER)


# --- возврат ---

func _draw_respawn(vp: Vector2, me: Doll) -> void:
	var left := match_node.respawn_left(me)
	if left < 0.0:
		return
	var c := Vector2(vp.x * 0.5, vp.y * 0.28)
	canvas.draw_circle(c, 62.0, Color(0, 0, 0, 0.55))
	SquadIcons.ring(canvas, c, 56.0, 8.0, 1.0 - left / maxf(match_node.respawn_s, 0.1), GOLD, Color(1, 1, 1, 0.1))
	_text(c + Vector2(0.0, 20.0), str(int(ceil(left))), 60, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_text(c + Vector2(0.0, 100.0), tr("ВОЗВРАТ НА БАЗУ"), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 600.0)
