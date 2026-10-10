## Тестовое меню сборки (docs/plan-demo/RELEASE_0.0.1.md): все режимы демо в одном месте — кампания, Быстрый бой в куполе,
## мастерская, PvE-волны, площадки арен — и памятка по управлению. Открывается из гаража (главная сцена, scenes/menu/garage_menu.tscn,
## пункт ВСЕ РЕЖИМЫ); Esc здесь — обратно в гараж. В бою Esc — пауза Flow (продолжить / заново / в гараж), из мастерской —
## двойной Esc в гараж.
## Номер сборки — ProjectSettings application/config/version.
extends Control

const MENU_SCENE := "res://scenes/menu/test_menu.tscn"
## [подпись, сцена, пояснение]
const ITEMS := [
	["РЕЖИМЫ: 100+ вариантов", "res://scenes/menu/modes_menu.tscn",
		"Реестр режимов: любая площадка плюс модификаторы — невесомость, один удар, бочки, вампиры, боты. Поиск, теги, случайный, избранное"],
	["Кампания «История»", "res://scenes/campaign/campaign.tscn",
		"Местная лига: 4 боя в куполе, выход бойца, голосование зрителей, трофей после победы, мастерская между боями"],
	["Быстрый бой — купол Old NULL Hall", "res://scenes/playground_null_hall.tscn",
		"Двое за одной клавиатурой. Поле NULL, мембрана, голосование зрителей. G — сменить поле"],
	["Спорт-зал: футбол", "res://scenes/playground_sport.tscn",
		"Мяч в чужие ворота, до 3 голов. За P2 играет бот (U — второй игрок на стрелках). F — баскетбол, волейбол"],
	["Спорт-зал: баскетбол", "res://scenes/playground_sport_basketball.tscn",
		"Мяч в чужое кольцо сверху вниз, до 3 очков. Мяч сам отскакивает от пола — бей его в воздухе"],
	["Спорт-зал: волейбол", "res://scenes/playground_sport_volleyball.tscn",
		"Сетка по центру: урони мяч на чужую половину, до 3 очков"],
	["Мастерская", "res://scenes/workshop/workshop_build.tscn",
		"Сборка тела и оружия, покраска, активные блоки, испытание на манекене (T)"],
	["PvE: волны на Свалке", "res://scenes/playground_pve.tscn",
		"Уборщик и Разборщик, три волны. F2 — кооп"],
	["Стычка 3 на 3: перестрелка и захват флага", "res://scenes/playground_squad.tscn",
		"Две команды по три бойца на Полигоне. Перед боем — настройки: режим (перестрелка или захват флага), день или ночь, до скольких очков, время, боты. Классы 1–3: громила, снайпер, налётчик; на 5 уровне — подкласс"],
	["СТАЗИС: время идёт, только когда ты двигаешься", "res://scenes/playground_stasis.tscn",
		"Волны PvE на Свалке: отпусти клавиши — мир почти замрёт. Метка на HUD справа снизу; X — обычное время, F2 — кооп"],
	["Бомба: передай касанием", "res://scenes/playground_bomb.tscn",
		"Пятеро в куполе, у одного бомба с тайным фитилём: коснись другого — бомба у него. Взрыв выбивает держателя, последний живой берёт партию, матч до 2. WASD + Shift; U — P2 на стрелках, K — уровень ботов"],
	["Гонка: 10 точек — Полигон", "res://scenes/playground_race.tscn",
		"Ты и три бота собираете общие точки: взял — у всех погасла, загорелась новая. Первый до 10 побеждает, бить можно. U — второй игрок на стрелках, K — уровень ботов"],
	["Гонка: 10 точек — Руины", "res://scenes/playground_race_ruins.tscn",
		"Та же гонка в Руинах: тесно, ямы по краям"],
	["Гонка: 10 точек — Свалка", "res://scenes/playground_race_scrap.tscn",
		"Та же гонка на Свалке: пропасть, паровой клапан, магнит и пресс"],
	["Стенка на стенку 5×5", "res://scenes/playground_brawl.tscn",
		"Две команды по пять на Полигоне, только тело: последняя живая команда берёт раунд, матч до 2 побед. Ты в синих (WASD + Shift); U — P2 в красных на стрелках, K — уровень ботов"],
	["Заражение: коснулся — заразил", "res://scenes/playground_infection.tscn",
		"Семеро в куполе, один заражённый (зелёный): коснулся здорового — тот заражён. Заражённые быстрее, но без руки и рывка. Дожил 90 с — очко; заразили всех — очко первому. 3 партии. WASD + Shift; U — P2 на стрелках, K — уровень ботов"],
	["Арена «Руины»", "res://scenes/playground.tscn", "Бой двоих, оружие, Sudden Death"],
	["Арена «Мастерская»", "res://scenes/playground_workshop.tscn", "Бой двоих среди верстаков"],
	["Арена «Void»", "res://scenes/playground_void.tscn", "Пустое чёрное поле: чистая механика без декораций"],
	["Арена «Свалка»", "res://scenes/playground_scrap.tscn", "Бой двоих на Свалке, машины и кучи хлама"],
	["Пресеты тела", "res://scenes/playground_body.tscn", "Модульные куклы: F1–F12 — пресеты, [ ] — перебор"],
]
## Памятка по строкам (каждая строка — свой ключ перевода).
const CONTROLS := [
	"P1 — WASD летать · Shift рывок · Space переворот · мышь: ЛКМ / ПКМ — тяги рук · I / O / P — активные блоки",
	"P2 — стрелки · правый Ctrl рывок · Enter переворот · Num 1 / 2 / 3 — активные блоки",
	"Esc — пауза (в гараж) · R — бой заново · 1–9 — сменить площадку · F10 — эффекты ударов full / reduced / off · F9 — качество графики · Shift+F9 — авто-масштаб",
	"L — панель всех клавиш · = стиль удара · 0 замедление · − цифры урона · B обводка · колесо мыши — масштаб камеры",
]


func _ready() -> void:
	var v := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	%Version.text = tr("тестовая сборка %s") % v
	%Controls.text = "\n".join(Array(CONTROLS).map(func(l: String) -> String: return tr(l)))
	var list: Node = %Items
	for it in ITEMS:
		var b := Button.new()
		b.text = tr(String(it[0]))
		b.tooltip_text = tr(String(it[2]))
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 26)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var path := String(it[1])
		b.pressed.connect(func() -> void:
			if path.contains("playground_squad"):
				SquadSettings.ask = true   # стычка: сначала экран настроек
			Loading.change_scene(path, "ПОДКЛЮЧЕНИЕ", path.get_file().get_basename()))
		b.focus_entered.connect(func() -> void: %Hint.text = tr(String(it[2])))
		b.mouse_entered.connect(func() -> void: %Hint.text = tr(String(it[2])))
		list.add_child(b)
	var gfx := Button.new()   # качество графики (Gfx): low / medium / high / ultra, F9 — то же в любой сцене
	gfx.custom_minimum_size = Vector2(0, 48)
	gfx.add_theme_font_size_override("font_size", 22)
	gfx.alignment = HORIZONTAL_ALIGNMENT_LEFT
	gfx.tooltip_text = tr("Бюджет пикселей 3D, глубина резкости, свечение, мягкость теней. F9 — то же в любой сцене; Shift+F9 — авто-масштаб (снижает разрешение, если игра не держит 60 fps)")
	var gfx_text := func() -> void:
		gfx.text = tr("Качество графики: %s   ▸") % Gfx.label().trim_prefix(tr("Графика: "))
	gfx.pressed.connect(func() -> void:
		Gfx.cycle()
		gfx_text.call())
	gfx_text.call()
	list.add_child(gfx)
	var quit := Button.new()
	quit.text = tr("← В гараж")
	quit.custom_minimum_size = Vector2(0, 48)
	quit.add_theme_font_size_override("font_size", 22)
	quit.pressed.connect(func() -> void: back_to_menu(get_tree()))
	list.add_child(quit)
	(list.get_child(0) as Button).grab_focus()
	%Hint.text = tr(String(ITEMS[0][2]))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		back_to_menu(get_tree())


## В главное меню — гараж (Flow.to_menu: на пункт, с которого ушли); без автозагрузки Flow — выход, как раньше.
static func back_to_menu(tree: SceneTree) -> void:
	var flow := tree.root.get_node_or_null("Flow")
	if flow != null:
		flow.to_menu()
	else:
		tree.quit()
