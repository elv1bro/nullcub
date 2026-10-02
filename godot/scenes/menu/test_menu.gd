## Тестовое меню сборки (docs/plan-demo/RELEASE_0.0.1.md): все режимы демо в одном месте — кампания, Быстрый бой в куполе,
## мастерская, PvE-волны, площадки арен — и памятка по управлению. Главная сцена проекта, пока нет настоящего меню (этап 11).
## Из площадок Esc возвращает сюда (playground.gd, playground_pve.gd); из мастерской — двойной Esc закрывает игру.
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
Esc — назад в это меню · R — бой заново · 1–9 — сменить площадку · F10 — эффекты ударов full / reduced / off
0 — вариант замедления удара · − (минус) — цифры урона вкл/выкл · = — стиль удара серьёзный / мульт"""


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
	var quit := Button.new()
	quit.text = "Выход"
	quit.custom_minimum_size = Vector2(0, 48)
	quit.add_theme_font_size_override("font_size", 22)
	quit.pressed.connect(func() -> void: get_tree().quit())
	list.add_child(quit)
	(list.get_child(0) as Button).grab_focus()
	%Hint.text = String(ITEMS[0][2])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()


## Площадки: Esc — сюда, если меню есть в проекте; иначе выход (как раньше).
static func back_to_menu(tree: SceneTree) -> void:
	if ResourceLoader.exists(MENU_SCENE):
		tree.change_scene_to_file(MENU_SCENE)
	else:
		tree.quit()
