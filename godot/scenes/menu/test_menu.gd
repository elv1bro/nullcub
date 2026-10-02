## Тестовое меню сборки (docs/plan-demo/RELEASE_0.0.1.md): все режимы демо в одном месте — кампания, Быстрый бой в куполе,
## мастерская, PvE-волны, площадки арен — и памятка по управлению. Открывается из гаража (главная сцена, scenes/menu/garage_menu.tscn,
## пункт ВСЕ РЕЖИМЫ); Esc здесь — обратно в гараж. В бою Esc — пауза Flow (продолжить / заново / в гараж), из мастерской —
## двойной Esc в гараж.
## Номер сборки — ProjectSettings application/config/version.
extends Control

const MENU_SCENE := "res://scenes/menu/test_menu.tscn"
## [подпись, сцена, пояснение]
const ITEMS := [
	["Кампания «История»", "res://scenes/campaign/campaign.tscn",
		"Местная лига: 4 боя в куполе, выход бойца, голосование зрителей, трофей после победы, мастерская между боями"],
	["Быстрый бой — купол Old NULL Hall", "res://scenes/playground_null_hall.tscn",
		"Двое за одной клавиатурой. Поле NULL, мембрана, голосование зрителей. G — сменить поле"],
	["Мастерская", "res://scenes/workshop/workshop_build.tscn",
		"Сборка тела и оружия, покраска, активные блоки, испытание на манекене (T)"],
	["PvE: волны на Свалке", "res://scenes/playground_pve.tscn",
		"Уборщик и Разборщик, три волны. F2 — кооп"],
	["Арена «Руины»", "res://scenes/playground.tscn", "Бой двоих, оружие, Sudden Death"],
	["Арена «Мастерская»", "res://scenes/playground_workshop.tscn", "Бой двоих среди верстаков"],
	["Арена «Void»", "res://scenes/playground_void.tscn", "Пустое поле, как в Ragdoll Masters"],
	["Арена «Свалка»", "res://scenes/playground_scrap.tscn", "Бой двоих на Свалке, машины и кучи хлама"],
	["Пресеты тела", "res://scenes/playground_body.tscn", "Модульные куклы: F1–F12 — пресеты, [ ] — перебор"],
]
const CONTROLS := """P1 — WASD летать · Shift рывок · Space переворот · мышь: ЛКМ / ПКМ — тяги рук · I / O / P — активные блоки
P2 — стрелки · правый Ctrl рывок · Enter переворот · Num 1 / 2 / 3 — активные блоки
Esc — пауза (в гараж) · R — бой заново · 1–9 — сменить площадку · F10 — эффекты ударов full / reduced / off · F9 — качество графики · Shift+F9 — авто-масштаб
L — панель всех клавиш · = стиль удара · 0 замедление · − цифры урона · B обводка · колесо мыши — масштаб камеры"""


func _ready() -> void:
	var v := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	%Version.text = "тестовая сборка %s" % v
	%Controls.text = CONTROLS
	var list: Node = %Items
	for it in ITEMS:
		var b := Button.new()
		b.text = String(it[0])
		b.tooltip_text = String(it[2])
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_size_override("font_size", 26)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var path := String(it[1])
		b.pressed.connect(func() -> void: get_tree().change_scene_to_file(path))
		b.focus_entered.connect(func() -> void: %Hint.text = String(it[2]))
		b.mouse_entered.connect(func() -> void: %Hint.text = String(it[2]))
		list.add_child(b)
	var gfx := Button.new()   # качество графики (Gfx): low / medium / high / ultra, F9 — то же в любой сцене
	gfx.custom_minimum_size = Vector2(0, 48)
	gfx.add_theme_font_size_override("font_size", 22)
	gfx.alignment = HORIZONTAL_ALIGNMENT_LEFT
	gfx.tooltip_text = "Бюджет пикселей 3D, глубина резкости, свечение, мягкость теней. F9 — то же в любой сцене; Shift+F9 — авто-масштаб (снижает разрешение, если игра не держит 60 fps)"
	var gfx_text := func() -> void:
		gfx.text = "Качество графики: %s   ▸" % Gfx.label().trim_prefix("Графика: ")
	gfx.pressed.connect(func() -> void:
		Gfx.cycle()
		gfx_text.call())
	gfx_text.call()
	list.add_child(gfx)
	var quit := Button.new()
	quit.text = "← В гараж"
	quit.custom_minimum_size = Vector2(0, 48)
	quit.add_theme_font_size_override("font_size", 22)
	quit.pressed.connect(func() -> void: back_to_menu(get_tree()))
	list.add_child(quit)
	(list.get_child(0) as Button).grab_focus()
	%Hint.text = String(ITEMS[0][2])


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
