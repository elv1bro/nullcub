## «ВСЕ РЕЖИМЫ» — экран выбора режима в стиле эфира Лиги (docs/plan-demo/MODES_SCREEN.md). Открывается из гаража (главная сцена,
## scenes/menu/garage_menu.tscn, пункт ВСЕ РЕЖИМЫ); Esc здесь — обратно в гараж (Flow.to_menu). В бою Esc — пауза Flow, из мастерской —
## двойной Esc в гараж.
##   Слева — прокручиваемый список карточек (миниатюра, название, строка-тег), сгруппированный по GROUPS; справа — крупный снимок
##   режима (кроссфейд при смене), название, описание, факты (игроки, арена, время), чипы клавиш и кнопка ИГРАТЬ. Сверху — знак,
##   версия сборки (application/config/version), качество графики (Gfx.cycle), «← В гараж»; снизу — подсказка и памятка клавиш (L).
##   Ввод: ↑↓ / W S / крестовина и стик — выбор (список сам прокручивается к карточке), PageUp/PageDown, Home/End; Enter / A, клик по
##   выбранной карточке, двойной клик, кнопка ИГРАТЬ — запуск; колесо мыши — прокрутка; Esc / B — в гараж (или закрыть памятку).
## Снимки режимов — assets/ui/modes/<id>.jpg (генератор tests/modes_shots.tscn); нет снимка — заглушка со знаком N0.
## Новый режим — строка в MODES (поля ниже); старый формат строки [подпись, сцена, пояснение] тоже понимается (группа «ЕЩЁ»).
## Стычка: перед запуском SquadSettings.ask = true (сначала экран настроек). Пробы: dry_run (или `-- modes_dry_run=1`) — запуск только
## сигнал launched(путь), «назад» — сигнал went_back; tests/modes_screen_probe.tscn, tests/menu_probe.tscn.
extends Control

signal launched(path: String)
signal went_back
signal selection_changed(index: int)

const MENU_SCENE := "res://scenes/menu/test_menu.tscn"
const SHOTS_DIR := "res://assets/ui/modes/"
const BADGE := "res://assets/ui/brand/null_gravity_badge_512.png"
const BLUR := preload("res://scenes/menu/modes_blur.gdshader")
const W := 1920.0
const H := 1080.0
const LIST_X := 64.0
const LIST_W := 620.0
const DETAIL_X := 744.0
const TOP := 150.0
const BOTTOM := 1018.0
const PHOTO_H := 600.0          # снимок во всю ширину панели × 600 (≈ 16:9, края кадра чуть срезаны)
const INFO_H := 248.0           # место под снимком: описание, клавиши, ИГРАТЬ (длинный язык — снимок уступает)
const CARD_H := 108.0
const THUMB := Vector2(160, 90)
const XFADE_S := 0.24
const SCROLL_S := 0.18
const SCROLL_PAD := 14.0
const NAVY_TOP := Color(0.07, 0.1, 0.19)
const NAVY_BOTTOM := Color(0.016, 0.024, 0.06)
const KEYCAP := Color(0.86, 0.89, 0.95)

## Группы списка: [id, заголовок]. Порядок — порядок в списке.
const GROUPS := [
	["story", "СЮЖЕТ"],
	["fight", "БОЙ ОДИН НА ОДИН"],
	["crowd", "КОМАНДЫ И ВСЕ ПРОТИВ ВСЕХ"],
	["sport", "СПОРТ"],
	["coop", "ВДВОЁМ И PvE"],
	["build", "МАСТЕРСКАЯ И ТЕЛО"],
	["other", "ЕЩЁ"],
]

## Режимы. id — имя снимка (assets/ui/modes/<id>.jpg) и ключ для проб; group — id из GROUPS; scene — что грузим;
## title — название; tag — строка под названием в карточке; desc — описание 2–4 предложения (анонс эфира, факты из docs/plan-demo/<РЕЖИМ>.md);
## players / arena / time — факты под описанием (пустая строка — не показывать); keys — чипы клавиш [клавиша, что делает].
## Все строки — ключи перевода (tr в месте использования, английский — locale/en.json).
const MODES := [
	{"id": "campaign", "group": "story", "scene": "res://scenes/campaign/campaign.tscn",
		"title": "Кампания «История»", "tag": "1 игрок · против лиги",
		"desc": "Местная лига ждёт новичка. Четыре соперника — четыре боя в куполе Old NULL Hall: выход под свет ферм, зрители голосуют за поле, а победителю достаётся деталь соперника на полку. Между боями — мастерская: подкрути тело под следующего.",
		"players": "1 игрок", "arena": "купол Old NULL Hall", "time": "4 боя",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["Space + A/D", "раскрутка"], ["ЛКМ / ПКМ", "тяги рук"]]},
	{"id": "quick", "group": "fight", "scene": "res://scenes/playground_null_hall.tscn",
		"title": "Быстрый бой", "tag": "2 игрока на одной клавиатуре",
		"desc": "Выставочный матч: очков не дают, синяки — сколько угодно. Двое за одной клавиатурой в куполе Old NULL Hall: поле NULL держит в воздухе, мембрана отбрасывает обратно в драку, а зрители голосуют, что сделать с гравитацией дальше.",
		"players": "2 игрока", "arena": "купол Old NULL Hall", "time": "1:30 + Sudden Death",
		"keys": [["WASD", "P1 — полёт"], ["Стрелки", "P2 — полёт"], ["G", "сменить поле"], ["R", "заново"]]},
	{"id": "ruins", "group": "fight", "scene": "res://scenes/playground.tscn",
		"title": "Арена «Руины»", "tag": "2 игрока · оружие на полу",
		"desc": "Тесные руины с ямами по краям, а на полу — молот, булава, топор и меч: кто первым подобрал, тот и диктует. Полторы минуты без нокаута — и табло объявит Sudden Death: отброс растёт, в центр падает молот, верёвочные мосты рвутся.",
		"players": "2 игрока", "arena": "Руины", "time": "1:30 + Sudden Death",
		"keys": [["WASD / стрелки", "P1 / P2"], ["Shift / правый Ctrl", "ускорение"], ["1–9", "другая арена"], ["R", "заново"]]},
	{"id": "workshop_arena", "group": "fight", "scene": "res://scenes/playground_workshop.tscn",
		"title": "Арена «Мастерская»", "tag": "2 игрока · верстаки и сковорода",
		"desc": "Драка прямо среди верстаков: станки, ящики и всё твёрдое стоит на своих местах. Под рукой молот, булава, топор, меч и сковорода — последняя бьёт обиднее всех.",
		"players": "2 игрока", "arena": "Мастерская", "time": "1:30 + Sudden Death",
		"keys": [["WASD / стрелки", "P1 / P2"], ["Shift / правый Ctrl", "ускорение"], ["1–9", "другая арена"], ["R", "заново"]]},
	{"id": "void", "group": "fight", "scene": "res://scenes/playground_void.tscn",
		"title": "Арена «Void»", "tag": "2 игрока · чистая механика",
		"desc": "Чёрное поле и больше ничего: ни оружия, ни декораций, ни оправданий. Только две куклы и физика — здесь сразу видно, кто умеет летать, а кто просто машет руками.",
		"players": "2 игрока", "arena": "Void", "time": "1:30 + Sudden Death",
		"keys": [["WASD / стрелки", "P1 / P2"], ["Shift / правый Ctrl", "ускорение"], ["Space + A/D", "раскрутка"], ["R", "заново"]]},
	{"id": "scrap", "group": "fight", "scene": "res://scenes/playground_scrap.tscn",
		"title": "Арена «Свалка»", "tag": "2 игрока · машины и пропасть",
		"desc": "Свалка: кучи хлама, пропасть, паровой клапан, магнит и пресс. Машины работают на того, кто первым подтолкнёт к ним соперника. Оружие тоже валяется под ногами — это же свалка.",
		"players": "2 игрока", "arena": "Свалка", "time": "1:30 + Sudden Death",
		"keys": [["WASD / стрелки", "P1 / P2"], ["Shift / правый Ctrl", "ускорение"], ["1–9", "другая арена"], ["R", "заново"]]},
	{"id": "gauntlet", "group": "fight", "scene": "res://scenes/playground_gauntlet.tscn",
		"title": "Испытание", "tag": "1 игрок · 10 боёв подряд",
		"desc": "Десять бойцов лиги подряд, каждый следующий сильнее. Оторванное не отрастает, синяки копятся — между боями одна бесплатная починка. Проиграл — забег окончен.",
		"players": "1 игрок", "arena": "купол, Руины, Свалка, Void, Мастерская", "time": "до 10 боёв",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["ЛКМ / ПКМ", "тяги рук"], ["Esc", "пауза"]]},
	{"id": "squad", "group": "crowd", "scene": "res://scenes/playground_squad.tscn",
		"title": "Стычка 3 на 3", "tag": "3 на 3 · с ботами",
		"desc": "Две тройки на Полигоне: перестрелка на очки или захват флага, днём или ночью — всё решаешь перед боем. Громила лезет в ближний бой, снайпер держит дистанцию, налётчик врывается и уходит. Опыт копится прямо в бою, а на пятом уровне открывается подкласс.",
		"players": "3 на 3", "arena": "Полигон", "time": "5–30 минут",
		"keys": [["WASD", "полёт"], ["Мышь", "прицел"], ["ЛКМ", "стрелять"], ["Q", "перезарядка"], ["1–3", "класс"], ["O", "настройки"]]},
	{"id": "domination", "group": "crowd", "scene": "res://scenes/playground_domination.tscn",
		"title": "Захват точек", "tag": "3 на 3 · три зоны",
		"desc": "Три зоны на Полигоне — A, B и C. Стой в зоне, пока там нет соперника, и она станет вашей. Каждая своя зона даёт очко в секунду: кто первым набрал 100, тот и победил.",
		"players": "3 на 3", "arena": "Полигон", "time": "до 6 минут",
		"keys": [["WASD", "полёт"], ["ЛКМ", "стрелять"], ["Q", "перезарядка"], ["1–3", "класс"], ["O", "настройки"]]},
	{"id": "royale", "group": "crowd", "scene": "res://scenes/playground_royale.tscn",
		"title": "Королевская битва", "tag": "8 бойцов · каждый сам за себя",
		"desc": "Восемь бойцов на Полигоне, возрождений нет. Стартуешь с пустыми руками: стволы, патроны, жизни и броня — в ящиках по карте. Зона сжимается двумя стенами, снаружи жжёт. Последний, кто остался на ногах, забирает всё.",
		"players": "1–2 игрока + боты", "arena": "Полигон", "time": "",
		"keys": [["WASD", "полёт"], ["ЛКМ", "стрелять"], ["Q", "перезарядка"], ["U", "второй игрок"], ["K", "уровень ботов"], ["G", "день / ночь"]]},
	{"id": "brawl", "group": "crowd", "scene": "res://scenes/playground_brawl.tscn",
		"title": "Стенка на стенку 5×5", "tag": "5 на 5 · только тело",
		"desc": "Пятеро синих против пятерых красных на Полигоне — без оружия, классов и ящиков, одно тело. Выбывший ждёт следующего раунда, последняя живая команда берёт раунд. Через две минуты — Sudden Death, матч до двух побед.",
		"players": "1–2 игрока + боты", "arena": "Полигон", "time": "до 2 побед",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "headhunt", "group": "crowd", "scene": "res://scenes/playground_headhunt.tscn",
		"title": "Охота за головами 3 на 3", "tag": "3 на 3 · до 7 очков",
		"desc": "Две тройки на Полигоне. Выбитый соперник оставляет голову: коснись её — и она уже у тебя на спине, унести можно три. Довези до своей корзины — очко за каждую. До семи очков или шести минут.",
		"players": "1–2 игрока + боты", "arena": "Полигон", "time": "до 6 минут",
		"keys": [["WASD", "полёт"], ["ЛКМ", "рука"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "bomb", "group": "crowd", "scene": "res://scenes/playground_bomb.tscn",
		"title": "Бомба: передай касанием", "tag": "5 бойцов · урона нет",
		"desc": "У одного из пятерых на груди тикает бомба, и сколько ей осталось, не знает никто. Коснись соперника любой деталью — теперь она его. Писк всё чаще, держатель летит быстрее, удары только толкают. Последний уцелевший берёт партию, матч — до двух побед.",
		"players": "1–2 игрока + боты", "arena": "купол Old NULL Hall", "time": "до 2 побед",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "infection", "group": "crowd", "scene": "res://scenes/playground_infection.tscn",
		"title": "Заражение", "tag": "7 бойцов · коснулся — заразил",
		"desc": "Семеро в куполе, и один уже зелёный: коснулся здорового — тот заражён. Заражённые летают медленнее здоровых, но их всё больше; они без руки и рывка, а урона нет вовсе — удары только толкают. Продержался 35 секунд — очко, заразил всех — очко первому. Три партии.",
		"players": "1–2 игрока + боты", "arena": "купол Old NULL Hall", "time": "3 партии по 35 с",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "king", "group": "crowd", "scene": "res://scenes/playground_king.tscn",
		"title": "Царь горы", "tag": "5 бойцов · все против всех",
		"desc": "Светящийся круг в куполе каждые 15 секунд переезжает. Ты в нём один — очко в секунду, вдвоём — никому. Удары здесь отбрасывают вдвое дальше. Продержись один десять секунд подряд — станешь ЦАРЁМ, очки ×2. До двадцати очков или пяти минут.",
		"players": "1–2 игрока + боты", "arena": "купол Old NULL Hall", "time": "до 5 минут",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "scavenger", "group": "crowd", "scene": "res://scenes/playground_scavenger.tscn",
		"title": "Собери себя", "tag": "5 бойцов · руки и ноги на земле",
		"desc": "Пятеро на Свалке, у всех только торс и голова. Руки и ноги светятся по карте: коснись — прикрутится, запаса больше. Выбил соперника — его детали твои. Последний на ногах побеждает.",
		"players": "1–2 игрока + боты", "arena": "Свалка", "time": "до 5 минут",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "race_proving", "group": "crowd", "scene": "res://scenes/playground_race.tscn",
		"title": "Гонка — Полигон", "tag": "4 гонщика · до 10 точек",
		"desc": "Точки общие на всех: взял одну — у остальных она гаснет, а где-то загорается новая. Ты и три бота на широком Полигоне, первый до десяти побеждает. Бить соперников можно — иногда это быстрее, чем лететь.",
		"players": "1–2 игрока + боты", "arena": "Полигон", "time": "до 5 минут",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "race_ruins", "group": "crowd", "scene": "res://scenes/playground_race_ruins.tscn",
		"title": "Гонка — Руины", "tag": "4 гонщика · до 10 точек",
		"desc": "Та же гонка до десяти точек, только в Руинах: тесно, по краям ямы, и соперник всегда где-то рядом. Сбил его с курса — точка твоя.",
		"players": "1–2 игрока + боты", "arena": "Руины", "time": "до 5 минут",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "race_scrap", "group": "crowd", "scene": "res://scenes/playground_race_scrap.tscn",
		"title": "Гонка — Свалка", "tag": "4 гонщика · до 10 точек",
		"desc": "Гонка до десяти точек на Свалке: пропасть, паровой клапан, магнит и пресс. Короткий путь здесь обычно самый опасный.",
		"players": "1–2 игрока + боты", "arena": "Свалка", "time": "до 5 минут",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "race_track", "group": "crowd", "scene": "res://scenes/playground_race_track.tscn",
		"title": "Гонка: трасса", "tag": "4 гонщика · старт → финиш",
		"desc": "Длинная трасса, шесть участков — один злее другого: прессы и магниты, узкие трубы, поля гравитации, тяжёлая зона, яма с рвущимися мостами. На развилках — длинный лёгкий путь или короткий трудный.",
		"players": "1–2 игрока + боты", "arena": "Трасса", "time": "2–3 минуты",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["Q", "к точке"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "football", "group": "sport", "scene": "res://scenes/playground_sport.tscn",
		"title": "Футбол", "tag": "1–2 игрока · до 3 голов",
		"desc": "Мяч — в чужие ворота, до трёх голов. Отдельной кнопки удара нет: бьёшь всем телом, и чем быстрее влетел, тем дальше улетит мяч. Драться не запрещено, а оторванные детали до конца матча никто не чинит.",
		"players": "1–2 игрока", "arena": "Спорт-зал", "time": "3 минуты",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["F", "вид спорта"]]},
	{"id": "basketball", "group": "sport", "scene": "res://scenes/playground_sport_basketball.tscn",
		"title": "Баскетбол", "tag": "1–2 игрока · до 3 очков",
		"desc": "Мяч должен пройти чужое кольцо сверху вниз — до трёх очков. Он сам подскакивает от пола, так что с земли его не поднять: лови и бей в воздухе.",
		"players": "1–2 игрока", "arena": "Спорт-зал", "time": "3 минуты",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["F", "вид спорта"]]},
	{"id": "volleyball", "group": "sport", "scene": "res://scenes/playground_sport_volleyball.tscn",
		"title": "Волейбол", "tag": "1–2 игрока · до 3 очков",
		"desc": "Сетка посередине, каждый заперт на своей половине. Урони мяч на чужую сторону три раза — и матч твой. Подаёт тот, кто пропустил.",
		"players": "1–2 игрока", "arena": "Спорт-зал", "time": "3 минуты",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["F", "вид спорта"]]},
	{"id": "hockey", "group": "sport", "scene": "res://scenes/playground_sport_hockey.tscn",
		"title": "Хоккей", "tag": "1–2 игрока · до 3 голов",
		"desc": "Пол спорт-зала стал льдом, вместо мяча — шайба, у каждой куклы в руке клюшка. Ворота низкие, шайба не прыгает, только скользит. До трёх голов или четырёх минут, при ничьей — золотой гол.",
		"players": "1–2 игрока", "arena": "Спорт-зал", "time": "4 минуты",
		"keys": [["Мышь", "клюшка"], ["Space", "раскрутка"], ["U", "второй игрок"], ["K", "уровень бота"], ["F", "вид спорта"]]},
	{"id": "tug", "group": "sport", "scene": "res://scenes/playground_tug.tscn",
		"title": "Перетягивание каната 2 на 2", "tag": "2 на 2 · до 3 очков",
		"desc": "Канат лежит на полу спорт-зала. Схвати звено на своей половине и тяни к своей стене: метка секунду за чертой соперника — очко. Бить можно, и порой это лучший способ отцепить чужую руку. До трёх очков или четырёх минут.",
		"players": "1–2 игрока + боты", "arena": "Спорт-зал", "time": "до 4 минут",
		"keys": [["ЛКМ", "рука к канату"], ["E", "схватить"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "dodgeball", "group": "sport", "scene": "res://scenes/playground_dodgeball.tscn",
		"title": "Вышибалы 3 на 3", "tag": "3 на 3 · до 2 побед",
		"desc": "Черта делит зал пополам, на полу четыре мяча. Брось мяч в чужого: попал до касания пола — он выбит. Поймал чужой бросок — выбит бросивший, а твой вернулся. Пустая половина — раунд проигран.",
		"players": "1–2 игрока + боты", "arena": "Спорт-зал", "time": "до 5 минут",
		"keys": [["WASD", "полёт"], ["ЛКМ", "рука и бросок"], ["E", "схватить мяч"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "golf", "group": "sport", "scene": "res://scenes/playground_golf.tscn",
		"title": "Гольф: кукла — мяч", "tag": "1–2 игрока · 3 лунки",
		"desc": "Здесь мяч — это ты. Прицелься мышью, зажми ЛКМ, отпусти — и обмякшая кукла летит кувырком через купол к чаше. В полёте разрешён один рывок на Shift. Три лунки, меньше ударов — лучше.",
		"players": "1–2 игрока", "arena": "купол Old NULL Hall", "time": "3 лунки",
		"keys": [["Мышь", "прицел"], ["ЛКМ", "сила и удар"], ["Shift", "рывок в полёте"], ["U", "второй игрок"]]},
	{"id": "puzzle", "group": "coop", "scene": "res://scenes/playground_puzzle.tscn",
		"title": "Головоломки вдвоём", "tag": "1–2 игрока · 8 комнат",
		"desc": "Восемь комнат: плиты, рычаг, двери, лифт, гравитация вбок, ящик на двоих и порталы. Вдвоём веселее, но один тоже пройдёт. Застрял — R вернёт комнату к началу.",
		"players": "1–2 игрока", "arena": "", "time": "8 комнат",
		"keys": [["WASD", "полёт"], ["ЛКМ", "рука"], ["E", "взять / положить"], ["Стрелки", "P2"], ["R", "комната заново"]]},
	{"id": "climb", "group": "coop", "scene": "res://scenes/playground_climb.tscn",
		"title": "Подъём: проба стены", "tag": "1–2 игрока · стена 30 м",
		"desc": "Тридцать метров скалы, а тяга не бесконечная: полёт тратит запас, отдышаться можно только на уступе или на обеих руках. Хватайся за камень и подтягивайся — гладкие синие плиты не держат.",
		"players": "1–2 игрока", "arena": "скальная шахта", "time": "до вершины",
		"keys": [["WASD", "полёт"], ["ЛКМ / ПКМ", "левая / правая рука"], ["U", "второй игрок"], ["G", "тяжесть"]]},
	{"id": "convoy", "group": "coop", "scene": "res://scenes/playground_convoy.tscn",
		"title": "Перегон: проба машины", "tag": "1–2 игрока · машина и груз",
		"desc": "Сто метров плохой дороги и машина с открытым кузовом, полным ящиков. Один за рулём, второй толкает в гору и ловит то, что вылетело на кочках, а перед провалом нужна доска.",
		"players": "1–2 игрока", "arena": "грунтовка", "time": "~100 м",
		"keys": [["F", "сесть / выйти"], ["A / D", "газ / назад"], ["Space", "ручник"], ["U", "второй игрок"]]},
	{"id": "pve", "group": "coop", "scene": "res://scenes/playground_pve.tscn",
		"title": "PvE: волны на Свалке", "tag": "1–2 игрока · 3 волны",
		"desc": "Сервисные роботы арены со сбитой программой сыплются из мусорного желоба вместе с хламом. Уборщик машет метлой, Разборщик откручивает детали — держи свои при себе. Три волны, один или вдвоём.",
		"players": "1–2 игрока", "arena": "Свалка", "time": "3 волны",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["ЛКМ / ПКМ", "тяги рук"], ["F2", "кооп"]]},
	{"id": "stasis", "group": "coop", "scene": "res://scenes/playground_stasis.tscn",
		"title": "СТАЗИС", "tag": "время идёт, когда ты движешься",
		"desc": "Время идёт, только когда ты двигаешься. Отпусти клавиши — и бой почти замрёт: удар, летящий в тебя, повиснет в воздухе. Те же волны PvE на Свалке, но теперь есть время подумать.",
		"players": "1–2 игрока", "arena": "Свалка", "time": "3 волны",
		"keys": [["WASD", "движение = время"], ["X", "обычное время"], ["F2", "кооп"]]},
	{"id": "boss", "group": "coop", "scene": "res://scenes/playground_boss.tscn",
		"title": "Босс: Титан", "tag": "1–2 игрока · против чемпиона лиги",
		"desc": "Титан, чемпион континента: вдвое выше и втрое тяжелее. Бей в светящуюся деталь — урон ×2, детали отлетают по одной. Три фазы: наскоки, рывки, ярость с волной. Оторви голову или обнули запас.",
		"players": "1–2 игрока + бот", "arena": "купол Old NULL Hall", "time": "до 6 минут",
		"keys": [["WASD", "полёт"], ["Shift", "ускорение"], ["U", "второй игрок"], ["K", "уровень ботов"]]},
	{"id": "workshop", "group": "build", "scene": "res://scenes/workshop/workshop_build.tscn",
		"title": "Мастерская", "tag": "сборка · покраска · испытание",
		"desc": "Верстак, стенд и ящик деталей. Собери бойца из ядра, конечностей и оружия, покрась, поставь активные блоки — энергия ядра подскажет, сколько тело потянет. Готов — жми T и проверь его на манекене.",
		"players": "1 игрок", "arena": "Мастерская", "time": "",
		"keys": [["ЛКМ", "взять / поставить"], ["ПКМ", "открутить"], ["T", "испытание"], ["Esc ×2", "в гараж"]]},
	{"id": "body", "group": "build", "scene": "res://scenes/playground_body.tscn",
		"title": "Пресеты тела", "tag": "2 игрока · готовые тела",
		"desc": "Паук, длиннорукий, безногий, кистень, рогатый, король, колёса — готовые модульные тела против обычной куклы на арене «Мастерская». Листай пресеты и смотри, как форма тела меняет драку.",
		"players": "2 игрока", "arena": "Мастерская", "time": "1:30 + Sudden Death",
		"keys": [["F1–F12", "пресет"], ["[ ]", "листать"], ["WASD / стрелки", "P1 / P2"], ["R", "заново"]]},
	{"id": "registry", "group": "other", "scene": "res://scenes/menu/modes_menu.tscn",
		"title": "РЕЖИМЫ: 100+ вариантов", "tag": "реестр · площадка + модификаторы",
		"desc": "Любая площадка плюс модификаторы: невесомость, один удар, бочки, вампиры, боты — больше сотни сочетаний. Поиск и теги слева, случайный режим и избранное.",
		"players": "", "arena": "", "time": "",
		"keys": [["Enter", "играть"], ["F", "в избранное"], ["R", "случайный"], ["Esc", "назад"]]},
]
## Памятка по строкам (каждая строка — свой ключ перевода); открывается кнопкой ПАМЯТКА КЛАВИШ или L.
const CONTROLS := [
	"P1 — WASD летать · Shift рывок · Space переворот · мышь: ЛКМ / ПКМ — тяги рук · I / O / P — активные блоки",
	"P2 — стрелки · правый Ctrl рывок · Enter переворот · Num 1 / 2 / 3 — активные блоки",
	"Esc — пауза (в гараж) · R — бой заново · 1–9 — сменить площадку · F10 — эффекты ударов full / reduced / off · F9 — качество графики · Shift+F9 — авто-масштаб",
	"L — панель всех клавиш · = стиль удара · 0 замедление · − цифры урона · B обводка · колесо мыши — масштаб камеры",
]

## Выбор переживает уход в режим и возврат через гараж (до выхода из игры).
static var last_id := ""

## Пробы: запуск и «назад» — только сигналы, без смены сцены.
@export var dry_run := false

var list: Array = []            # режимы в порядке показа (modes())
var sel := -1
var cards: Array = []           # {panel, title, tag, thumb, header (у первой в группе — заголовок группы)}
var scroll: ScrollContainer
var list_box: VBoxContainer
var memo: PanelContainer
var play_btn: Button
var gfx_btn: Button
var back_btn: Button
var memo_btn: Button
var version_label: Label
var detail_group: Label
var detail_title: Label
var detail_tag: Label
var detail_desc: Label
var facts_box: HFlowContainer
var keys_box: HFlowContainer
var photo_back: TextureRect
var photo_front: TextureRect
var photo_stub: Control
var backdrop: TextureRect
var _fade_nodes: Array = []
var _tw_photo: Tween
var _tw_scroll: Tween
var _tw_text: Tween
var _shots := {}                # id → Texture2D или null
var _stick := 0
var _sb := {}                   # стили карточек
var _launching := false
## Дуэльные карточки → экран «ВЫБОР БОЙЦА», выбранный боец уходит через эту карточку реестра.
const DUEL_MODES := {"quick": "duel_classic", "ruins": "ruins_classic", "workshop_arena": "workshop_classic", "void": "void_classic",
	"scrap": "scrap_classic"}
@export var pick_fighter := true
var pick: FighterSelect = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "modes_dry_run=1":
			dry_run = true
	list = modes()
	_build()
	var start := 0
	for i in list.size():
		if String(list[i]["id"]) == last_id:
			start = i
	select(start, true)


# ------------------------------------------------------------------ данные

## Режимы в порядке показа: по группам GROUPS, внутри группы — как в MODES. Старый формат строки [подпись, сцена, пояснение] —
## в группу «ЕЩЁ»; неизвестная группа — тоже туда.
static func modes() -> Array:
	var norm: Array = []
	for e in MODES:
		norm.append(norm_entry(e))
	var known := {}
	for g in GROUPS:
		known[String(g[0])] = true
	var out: Array = []
	for g in GROUPS:
		for m in norm:
			var gid := String(m["group"]) if known.has(String(m["group"])) else "other"
			if gid == String(g[0]):
				out.append(m)
	return out


static func norm_entry(e: Variant) -> Dictionary:
	var m := {"id": "", "group": "other", "scene": "", "title": "", "tag": "", "desc": "", "players": "", "arena": "", "time": "", "keys": []}
	if e is Array:
		var a := e as Array
		m["title"] = String(a[0])
		m["scene"] = String(a[1])
		m["desc"] = String(a[2]) if a.size() > 2 else ""
		m["id"] = String(a[1]).get_file().get_basename()
		return m
	for k in (e as Dictionary):
		m[k] = (e as Dictionary)[k]
	if String(m["id"]) == "":
		m["id"] = String(m["scene"]).get_file().get_basename()
	return m


static func group_title(gid: String) -> String:
	for g in GROUPS:
		if String(g[0]) == gid:
			return String(g[1])
	return String(GROUPS[GROUPS.size() - 1][1])


static func shot_path(id: String) -> String:
	return SHOTS_DIR + id + ".jpg"


## Снимок режима (кэш) или null — тогда заглушка со знаком N0.
func shot(id: String) -> Texture2D:
	if not _shots.has(id):
		var p := shot_path(id)
		_shots[id] = load(p) as Texture2D if ResourceLoader.exists(p) else null
	return _shots[id]


func mode(i := -1) -> Dictionary:
	return list[sel if i < 0 else i]


# ------------------------------------------------------------------ выбор, запуск, назад

func select(i: int, instant := false) -> void:
	if list.is_empty():
		return
	i = clampi(i, 0, list.size() - 1)
	var changed := i != sel
	sel = i
	last_id = String(list[i]["id"])
	_style_cards()
	if changed or instant:
		_show_detail(instant)
	scroll_to(i, instant)
	if changed:
		selection_changed.emit(i)


func launch(i := -1) -> void:
	if _launching:
		return   # уже грузим: второй клик / Enter под лоадером не запускает сцену дважды
	if i >= 0 and i != sel:
		select(i, true)
	var path := String(mode()["scene"])
	last_id = String(mode()["id"])
	if path.contains("playground_squad"):
		SquadSettings.ask = true   # стычка: сначала экран настроек
		if SquadSettings.mode == "dom":
			SquadSettings.mode = "dm"   # захват точек — своя карточка и сцена
	elif path.contains("playground_domination"):
		SquadSettings.mode = "dom"
		SquadSettings.ask = true
	var duel := String(DUEL_MODES.get(last_id, ""))
	if duel != "" and pick_fighter:
		_open_pick(path, duel)
		return
	_start(path, null, "")


## Запуск: bp == null — сцена режима как есть; иначе карточка реестра duel с бойцом экрана выбора (ModeRun.launch → ModePlayer.swap_p1).
func _start(path: String, bp: BodyBlueprint, duel: String) -> void:
	launched.emit(path)
	if dry_run:
		return
	_launching = true
	if bp != null and duel != "":
		ModeRun.launch(ModeCatalog.by_id(duel), {"player_blueprint": bp})
	else:
		Loading.change_scene(path, "ПОДКЛЮЧЕНИЕ", String(mode()["title"]))


# ---------------------------------------------------------------- «ВЫБОР БОЙЦА» перед дуэлью (docs/plan-demo/FIGHTER_SELECT.md)

func _open_pick(path: String, duel: String) -> void:
	pick = FighterSelect.open_over(self, {"title": tr(String(mode()["title"])), "dry_run": dry_run})
	pick.chosen.connect(func(bp: BodyBlueprint) -> void:
		_close_pick()
		_start(path, bp, duel))
	pick.cancelled.connect(_close_pick)
	pick.workshop_requested.connect(func(bp: BodyBlueprint) -> void:
		_close_pick()
		if not dry_run:
			FighterPick.open_workshop(get_tree(), bp))


func _close_pick() -> void:
	if pick != null:
		pick.close()
	pick = null


func back() -> void:
	went_back.emit()
	if not dry_run:
		back_to_menu(get_tree())


## В главное меню — гараж (Flow.to_menu: на пункт, с которого ушли); без автозагрузки Flow — выход, как раньше.
static func back_to_menu(tree: SceneTree) -> void:
	var flow := tree.root.get_node_or_null("Flow")
	if flow != null:
		flow.to_menu()
	else:
		tree.quit()


func set_memo(on: bool) -> void:
	memo.visible = on
	memo_btn.text = tr("ПАМЯТКА КЛАВИШ") + ("  ▾" if on else "  ▴")


func _unhandled_input(e: InputEvent) -> void:
	if Loading.showing and not dry_run:
		return
	if pick != null:   # экран выбора бойца ловит ввод сам
		return
	if e is InputEventJoypadMotion:
		_on_stick(e as InputEventJoypadMotion)
		return
	var k := e as InputEventKey
	if e.is_action_pressed("ui_cancel") or (k != null and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE):
		if memo.visible:
			set_memo(false)
		else:
			back()
	elif e.is_action_pressed("ui_down", true) or e.is_action_pressed("p1_down", true):
		select(sel + 1)
	elif e.is_action_pressed("ui_up", true) or e.is_action_pressed("p1_up", true):
		select(sel - 1)
	elif e.is_action_pressed("ui_page_down", true):
		select(sel + 4)
	elif e.is_action_pressed("ui_page_up", true):
		select(sel - 4)
	elif e.is_action_pressed("ui_end"):
		select(list.size() - 1)
	elif e.is_action_pressed("ui_home"):
		select(0)
	elif e.is_action_pressed("ui_accept"):
		launch()
	elif k != null and k.pressed and not k.echo and k.physical_keycode == KEY_L:
		set_memo(not memo.visible)
	else:
		return
	get_viewport().set_input_as_handled()


## Стик геймпада: шаг на каждое отклонение (без повторов на каждом событии оси).
func _on_stick(e: InputEventJoypadMotion) -> void:
	if e.axis != JOY_AXIS_LEFT_Y:
		return
	var d := 0 if absf(e.axis_value) < 0.5 else int(signf(e.axis_value))
	if d != 0 and d != _stick:
		select(sel + d)
		get_viewport().set_input_as_handled()
	if absf(e.axis_value) < 0.3 or d != 0:
		_stick = d


# ------------------------------------------------------------------ прокрутка

## Прокрутить список так, чтобы карточка (и заголовок её группы, если она первая в группе) была видна целиком.
func scroll_to(i: int, instant := false) -> void:
	if i < 0 or i >= cards.size():
		return
	var c: Dictionary = cards[i]
	var card := c["panel"] as Control
	if list_box.size.y <= 0.0 or card.size.y <= 0.0:
		await get_tree().process_frame
		if not is_instance_valid(card):
			return
	var top := card.position.y
	var head := c.get("header") as Control
	if head != null:
		top = head.position.y
	var bottom := card.position.y + card.size.y
	var view_h := scroll.size.y
	var cur := float(scroll.scroll_vertical)
	var target := cur
	if top - SCROLL_PAD < cur:
		target = top - SCROLL_PAD
	elif bottom + SCROLL_PAD > cur + view_h:
		target = bottom + SCROLL_PAD - view_h
	target = clampf(target, 0.0, maxf(0.0, list_box.size.y - view_h))
	if _tw_scroll != null and _tw_scroll.is_valid():
		_tw_scroll.kill()
	if instant or absf(target - cur) < 1.0:
		scroll.scroll_vertical = int(round(target))
		return
	_tw_scroll = create_tween()
	_tw_scroll.tween_method(func(v: float) -> void: scroll.scroll_vertical = int(round(v)), cur, target, SCROLL_S) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Карточка i целиком в видимой области списка (пробы).
func card_visible(i: int) -> bool:
	var card := (cards[i] as Dictionary)["panel"] as Control
	var top := card.position.y - float(scroll.scroll_vertical)
	return top >= -1.0 and top + card.size.y <= scroll.size.y + 1.0


# ------------------------------------------------------------------ панель режима

func _show_detail(instant: bool) -> void:
	var m := mode()
	detail_group.text = tr(group_title(String(m["group"])))
	detail_title.text = tr(String(m["title"]))
	detail_tag.text = tr(String(m["tag"]))
	detail_tag.visible = String(m["tag"]) != ""
	detail_desc.text = tr(String(m["desc"]))
	for ch in facts_box.get_children():
		facts_box.remove_child(ch)
		ch.queue_free()
	for f in [["ИГРОКИ", "players"], ["АРЕНА", "arena"], ["ВРЕМЯ", "time"]]:
		if String(m.get(f[1], "")) != "":
			facts_box.add_child(_fact_chip(tr(String(f[0])), tr(String(m[f[1]]))))
	facts_box.visible = facts_box.get_child_count() > 0
	for ch in keys_box.get_children():
		keys_box.remove_child(ch)
		ch.queue_free()
	for kv in m.get("keys", []):
		keys_box.add_child(_key_chip(tr(String(kv[0])), tr(String(kv[1]))))
	keys_box.get_parent().visible = keys_box.get_child_count() > 0
	# снимок: новый поверх старого, кроссфейд и лёгкий «наезд»
	var tex := shot(String(m["id"]))
	photo_stub.visible = tex == null
	if _tw_photo != null and _tw_photo.is_valid():
		_tw_photo.kill()
	if instant:
		photo_back.texture = tex
		photo_front.texture = null
		photo_front.modulate.a = 0.0
		backdrop.texture = tex
		backdrop.modulate.a = 1.0 if tex != null else 0.0
	else:
		photo_front.texture = tex
		photo_front.modulate.a = 0.0
		photo_front.pivot_offset = photo_front.size * 0.5
		photo_front.scale = Vector2.ONE * 1.04
		_tw_photo = create_tween().set_parallel(true)
		_tw_photo.tween_property(photo_front, "modulate:a", 1.0, XFADE_S)
		_tw_photo.tween_property(photo_front, "scale", Vector2.ONE, XFADE_S * 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw_photo.tween_property(backdrop, "modulate:a", 0.0, XFADE_S * 0.5)
		_tw_photo.chain().tween_callback(func() -> void:
			photo_back.texture = tex
			photo_front.modulate.a = 0.0
			photo_front.scale = Vector2.ONE
			backdrop.texture = tex)
		_tw_photo.chain().tween_property(backdrop, "modulate:a", 1.0 if tex != null else 0.0, XFADE_S)
	if _tw_text != null and _tw_text.is_valid():
		_tw_text.kill()
	for n in _fade_nodes:
		(n as CanvasItem).modulate.a = 1.0 if instant else 0.35
	if not instant:
		_tw_text = create_tween().set_parallel(true)
		for n in _fade_nodes:
			_tw_text.tween_property(n, "modulate:a", 1.0, XFADE_S * 0.8)


func _style_cards() -> void:
	for i in cards.size():
		var c: Dictionary = cards[i]
		var on := i == sel
		(c["panel"] as PanelContainer).add_theme_stylebox_override("panel", _sb["on"] if on else (_sb["hover"] if c.get("hover", false) else _sb["off"]))
		(c["title"] as Label).add_theme_color_override("font_color", ShowTokens.TEXT if on else Color(ShowTokens.TEXT, 0.82))
		(c["frame"] as Panel).add_theme_stylebox_override("panel", _sb["thumb_on"] if on else _sb["thumb_off"])
		(c["arrow"] as Label).visible = on


func _on_card_input(e: InputEvent, i: int) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	(cards[i]["panel"] as Control).accept_event()
	if i == sel or mb.double_click:
		launch(i)
	else:
		select(i)


# ------------------------------------------------------------------ сборка экрана

func _build() -> void:
	_make_styles()
	var bg := Control.new()
	bg.name = "Bg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(func() -> void: _draw_bg(bg))
	add_child(bg)
	# размытый снимок выбранного режима — фон справа, тихо
	backdrop = TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = BLUR
	backdrop.material = bm
	backdrop.self_modulate = Color(1, 1, 1, 0.2)
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(backdrop)
	var shade := TextureRect.new()   # слева фон темнее — под списком
	shade.name = "Shade"
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.texture = _gradient([Color(NAVY_BOTTOM, 0.96), Color(NAVY_BOTTOM, 0.75), Color(NAVY_BOTTOM, 0.35)], [0.0, 0.42, 1.0], Vector2(1, 0))
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_build_header()
	_build_list()
	_build_detail()
	_build_footer()


func _build_header() -> void:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.position = Vector2(LIST_X, 16)
	row.size = Vector2(W - LIST_X * 2.0, 110)
	row.add_theme_constant_override("separation", 22)
	add_child(row)
	var badge := TextureRect.new()
	badge.texture = load(BADGE)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.custom_minimum_size = Vector2(100, 100)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", -10)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(titles)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 10)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_child(brand)
	# название не переводится (BRAND.md): NULL — белым, GRAVITY — янтарём
	brand.add_child(_label("NULL", ShowTokens.title(700), 27, ShowTokens.TEXT))
	brand.add_child(_label("GRAVITY", ShowTokens.title(700), 27, ShowTokens.AMBER))
	var live := _label(tr("● ЭФИР ЛИГИ"), ShowTokens.title(600), 20, ShowTokens.NULL_BLUE)
	live.size_flags_vertical = Control.SIZE_SHRINK_END
	brand.add_child(live)
	titles.add_child(_label(tr("ВСЕ РЕЖИМЫ"), ShowTokens.title(700), 56, ShowTokens.TEXT))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	var v := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	version_label = _label(tr("тестовая сборка %s") % v, ShowTokens.text(500), 20, ShowTokens.MUTED)
	version_label.name = "Version"
	version_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(version_label)
	gfx_btn = _plate_button("", 22)
	gfx_btn.name = "Gfx"
	gfx_btn.tooltip_text = tr("Бюджет пикселей 3D, глубина резкости, свечение, мягкость теней. F9 — то же в любой сцене; Shift+F9 — авто-масштаб (снижает разрешение, если игра не держит 60 fps)")
	gfx_btn.pressed.connect(func() -> void:
		Gfx.cycle()
		_gfx_text())
	row.add_child(gfx_btn)
	_gfx_text()
	back_btn = _plate_button(tr("← В гараж"), 22)
	back_btn.name = "Back"
	back_btn.pressed.connect(back)
	row.add_child(back_btn)
	# полоса эфира под шапкой: цвета Лиги
	var bar := Control.new()
	bar.name = "LeagueBar"
	bar.position = Vector2(LIST_X, 134)
	bar.size = Vector2(W - LIST_X * 2.0, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func() -> void:
		var w := bar.size.x
		bar.draw_rect(Rect2(0, 0, w * 0.62, 3), Color(ShowTokens.AMBER, 0.9))
		bar.draw_rect(Rect2(w * 0.62 + 8, 0, w * 0.12, 3), Color(ShowTokens.TEAM_RED, 0.9))
		bar.draw_rect(Rect2(w * 0.74 + 16, 0, w * 0.1, 3), Color(ShowTokens.TEAM_BLUE, 0.95))
		bar.draw_rect(Rect2(w * 0.84 + 24, 0, w * 0.16 - 24, 3), Color(ShowTokens.NULL_BLUE, 0.8)))
	add_child(bar)


func _gfx_text() -> void:
	gfx_btn.text = tr("ГРАФИКА: %s  ▸") % String(Gfx.preset).to_upper()
	gfx_btn.tooltip_text = Gfx.label()


func _build_list() -> void:
	scroll = ScrollContainer.new()
	scroll.name = "List"
	scroll.position = Vector2(LIST_X - 8, TOP)
	scroll.size = Vector2(LIST_W + 30, BOTTOM - TOP)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	var vs := scroll.get_v_scroll_bar()
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(1, 1, 1, 0.04)
	sb_bg.set_corner_radius_all(3)
	sb_bg.content_margin_left = 3
	sb_bg.content_margin_right = 3
	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = Color(ShowTokens.AMBER, 0.55)
	sb_grab.set_corner_radius_all(3)
	var sb_grab_hi := sb_grab.duplicate() as StyleBoxFlat
	sb_grab_hi.bg_color = ShowTokens.AMBER
	vs.add_theme_stylebox_override("scroll", sb_bg)
	vs.add_theme_stylebox_override("grabber", sb_grab)
	vs.add_theme_stylebox_override("grabber_highlight", sb_grab_hi)
	vs.add_theme_stylebox_override("grabber_pressed", sb_grab_hi)
	vs.custom_minimum_size = Vector2(8, 0)
	add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(pad)
	list_box = VBoxContainer.new()
	list_box.name = "Items"
	list_box.add_theme_constant_override("separation", 8)
	list_box.mouse_filter = Control.MOUSE_FILTER_PASS
	pad.add_child(list_box)
	var last_group := ""
	for i in list.size():
		var m: Dictionary = list[i]
		var head: Control = null
		if String(m["group"]) != last_group:
			last_group = String(m["group"])
			head = _group_header(tr(group_title(last_group)), list_box.get_child_count() == 0)
			list_box.add_child(head)
		var c := _card(m, i)
		c["header"] = head
		list_box.add_child(c["panel"])
		cards.append(c)
	# края списка мягко уходят в фон (карточка не обрезается «ножом»)
	for edge in [[TOP, 22.0, Vector2(0, 1)], [BOTTOM - 30.0, 30.0, Vector2(0, -1)]]:
		var f := TextureRect.new()
		f.position = Vector2(LIST_X - 8, float(edge[0]))
		f.size = Vector2(LIST_W + 10, float(edge[1]))
		var up := (edge[2] as Vector2).y < 0.0
		f.texture = _gradient([Color(NAVY_BOTTOM, 0.0 if up else 0.95), Color(NAVY_BOTTOM, 0.95 if up else 0.0)], [0.0, 1.0], Vector2(0, 1))
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(f)


func _group_header(text: String, first: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not first:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 12)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(gap)
	var l := _label(text, ShowTokens.title(600), 21, ShowTokens.AMBER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	var line := ColorRect.new()
	line.color = Color(ShowTokens.AMBER, 0.22)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	return box


func _card(m: Dictionary, i: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.name = "Card_%s" % String(m["id"])
	panel.custom_minimum_size = Vector2(0, CARD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS   # колесо мыши уходит в ScrollContainer
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.add_theme_stylebox_override("panel", _sb["off"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var frame := Panel.new()       # миниатюра в рамке (у выбранной — янтарная)
	frame.custom_minimum_size = THUMB
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	var tex := shot(String(m["id"]))
	if tex != null:
		var th := TextureRect.new()
		th.texture = tex
		th.set_anchors_preset(Control.PRESET_FULL_RECT)
		th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		th.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		th.mouse_filter = Control.MOUSE_FILTER_IGNORE
		th.show_behind_parent = true
		frame.add_child(th)
	else:
		frame.add_child(_stub(0.62))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var title := _label(tr(String(m["title"])), ShowTokens.title(600), 27, ShowTokens.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(title)
	var tag := _label(tr(String(m["tag"])), ShowTokens.text(450), 18, ShowTokens.MUTED)
	tag.clip_text = true
	tag.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tag.visible = String(m["tag"]) != ""
	col.add_child(tag)
	var arrow := _label("▸", ShowTokens.title(700), 30, ShowTokens.AMBER)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	var c := {"panel": panel, "title": title, "tag": tag, "frame": frame, "arrow": arrow, "hover": false}
	panel.gui_input.connect(func(e: InputEvent) -> void: _on_card_input(e, i))
	panel.mouse_entered.connect(func() -> void:
		c["hover"] = true
		_style_cards())
	panel.mouse_exited.connect(func() -> void:
		c["hover"] = false
		_style_cards())
	return c


func _build_detail() -> void:
	var col := VBoxContainer.new()
	col.name = "Detail"
	col.position = Vector2(DETAIL_X, TOP)
	col.size = Vector2(W - LIST_X - DETAIL_X, BOTTOM - TOP)
	col.add_theme_constant_override("separation", 20)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	# снимок во всю ширину панели × PHOTO_H; если текст под ним длиннее INFO_H (длинный язык), снимок уменьшается, а не текст вылезает
	var arc := AspectRatioContainer.new()
	arc.name = "PhotoSlot"
	arc.ratio = col.size.x / PHOTO_H
	arc.stretch_mode = AspectRatioContainer.STRETCH_FIT
	arc.alignment_horizontal = AspectRatioContainer.ALIGNMENT_BEGIN
	arc.alignment_vertical = AspectRatioContainer.ALIGNMENT_BEGIN
	arc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(arc)
	var frame := Panel.new()
	frame.name = "Photo"
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = NAVY_BOTTOM
	fsb.shadow_color = Color(0, 0, 0, 0.45)
	fsb.shadow_size = 18
	fsb.shadow_offset = Vector2(0, 8)
	frame.add_theme_stylebox_override("panel", fsb)
	arc.add_child(frame)
	photo_stub = _stub(0.42)
	frame.add_child(photo_stub)
	for n in ["Back", "Front"]:
		var t := TextureRect.new()
		t.name = n
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(t)
		if n == "Back":
			photo_back = t
		else:
			photo_front = t
	# верх и низ снимка темнее — под плашки фактов и под название
	var fade := TextureRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.texture = _gradient([Color(NAVY_BOTTOM, 0.55), Color(NAVY_BOTTOM, 0.0), Color(NAVY_BOTTOM, 0.0), Color(NAVY_BOTTOM, 0.93)],
		[0.0, 0.2, 0.45, 1.0], Vector2(0, 1))
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fade)
	var edge := Panel.new()          # тонкая рамка поверх снимка
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var esb := StyleBoxFlat.new()
	esb.draw_center = false
	esb.border_color = Color(1, 1, 1, 0.1)
	esb.set_border_width_all(2)
	edge.add_theme_stylebox_override("panel", esb)
	frame.add_child(edge)
	var amber := ColorRect.new()     # янтарная полоса эфира по низу снимка
	amber.color = ShowTokens.AMBER
	amber.anchor_top = 1.0
	amber.anchor_bottom = 1.0
	amber.anchor_right = 0.38
	amber.offset_top = -5
	amber.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(amber)
	# факты — плашки эфира в левом верхнем углу снимка
	facts_box = HFlowContainer.new()
	facts_box.name = "Facts"
	facts_box.anchor_right = 0.94
	facts_box.offset_left = 26
	facts_box.offset_top = 24
	facts_box.add_theme_constant_override("h_separation", 10)
	facts_box.add_theme_constant_override("v_separation", 8)
	facts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(facts_box)
	# название поверх снимка, «нижняя треть»: группа на янтарной плашке, название, тег
	var dt := VBoxContainer.new()
	dt.name = "TitleBlock"
	dt.anchor_top = 1.0
	dt.anchor_bottom = 1.0
	dt.anchor_right = 0.88
	dt.offset_left = 38
	dt.offset_bottom = -30
	dt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dt.add_theme_constant_override("separation", 4)
	dt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(dt)
	var gp := PanelContainer.new()
	gp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	gp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = ShowTokens.AMBER
	gsb.skew = Vector2(ShowTokens.SKEW * 0.5, 0)
	gsb.content_margin_left = 14
	gsb.content_margin_right = 16
	gsb.content_margin_top = 1
	gsb.content_margin_bottom = 1
	gp.add_theme_stylebox_override("panel", gsb)
	dt.add_child(gp)
	detail_group = _label("", ShowTokens.title(600), 21, ShowTokens.INK)
	gp.add_child(detail_group)
	detail_title = _label("", ShowTokens.title(700), 66, ShowTokens.TEXT)
	detail_title.name = "Title"
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	detail_title.add_theme_constant_override("shadow_offset_y", 4)
	detail_title.add_theme_constant_override("shadow_outline_size", 6)
	detail_title.add_theme_constant_override("line_spacing", -10)
	dt.add_child(detail_title)
	detail_tag = _label("", ShowTokens.text(500), 24, Color(ShowTokens.TEXT, 0.9))
	detail_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	detail_tag.add_theme_constant_override("shadow_offset_y", 2)
	dt.add_child(detail_tag)
	# под снимком: слева описание, справа клавиши и ИГРАТЬ
	var row := HBoxContainer.new()
	row.name = "Info"
	row.custom_minimum_size = Vector2(0, INFO_H)
	row.add_theme_constant_override("separation", 36)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	detail_desc = _label("", ShowTokens.text(400), 23, Color(ShowTokens.TEXT, 0.92))
	detail_desc.name = "Desc"
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_desc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	detail_desc.add_theme_constant_override("line_spacing", 4)
	row.add_child(detail_desc)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
	right.add_theme_constant_override("separation", 14)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	var keys := VBoxContainer.new()
	keys.name = "Keys"
	keys.add_theme_constant_override("separation", 8)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(keys)
	keys.add_child(_label(tr("УПРАВЛЕНИЕ"), ShowTokens.title(600), 18, ShowTokens.MUTED))
	keys_box = HFlowContainer.new()
	keys_box.add_theme_constant_override("h_separation", 16)
	keys_box.add_theme_constant_override("v_separation", 8)
	keys_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.add_child(keys_box)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(push)
	play_btn = Button.new()
	play_btn.name = "Play"
	play_btn.text = tr("ИГРАТЬ  ▸")
	play_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	play_btn.focus_mode = Control.FOCUS_NONE
	play_btn.custom_minimum_size = Vector2(520, 80)
	play_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	play_btn.add_theme_font_override("font", ShowTokens.title(700))
	play_btn.add_theme_font_size_override("font_size", 42)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		play_btn.add_theme_color_override(k, ShowTokens.INK)
	for st in [["normal", ShowTokens.AMBER], ["hover", ShowTokens.AMBER.lightened(0.18)], ["pressed", ShowTokens.AMBER.darkened(0.15)],
			["focus", ShowTokens.AMBER]]:
		var s := StyleBoxFlat.new()
		s.bg_color = st[1]
		s.skew = Vector2(ShowTokens.SKEW * 0.5, 0)
		s.shadow_color = Color(ShowTokens.AMBER, 0.3)
		s.shadow_size = 14
		s.content_margin_left = 24
		s.content_margin_right = 24
		play_btn.add_theme_stylebox_override(String(st[0]), s)
	play_btn.pressed.connect(func() -> void: launch())
	right.add_child(play_btn)
	_fade_nodes = [dt, facts_box, row]


func _build_footer() -> void:
	var row := HBoxContainer.new()
	row.name = "Footer"
	row.position = Vector2(LIST_X, BOTTOM + 12)
	row.size = Vector2(W - LIST_X * 2.0, 44)
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	var hint := _label(tr("↑↓ · W S — выбор     ENTER — играть     ESC — в гараж     L — памятка клавиш"), ShowTokens.title(500), 19,
		ShowTokens.MUTED)
	hint.name = "Hint"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)
	memo_btn = _plate_button("", 19)
	memo_btn.name = "MemoBtn"
	memo_btn.pressed.connect(func() -> void: set_memo(not memo.visible))
	row.add_child(memo_btn)
	memo = PanelContainer.new()
	memo.name = "Memo"
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(ShowTokens.PLATE, 0.97)
	msb.border_color = ShowTokens.AMBER
	msb.border_width_top = 4
	msb.shadow_color = Color(0, 0, 0, 0.5)
	msb.shadow_size = 24
	msb.set_content_margin_all(22)
	msb.content_margin_left = 30
	memo.add_theme_stylebox_override("panel", msb)
	memo.anchor_left = 0.0
	memo.anchor_right = 1.0
	memo.anchor_top = 1.0
	memo.anchor_bottom = 1.0
	memo.offset_left = LIST_X
	memo.offset_right = -LIST_X
	memo.offset_bottom = -(H - BOTTOM) - 4
	memo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(memo)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	memo.add_child(mv)
	mv.add_child(_label(tr("ПАМЯТКА КЛАВИШ"), ShowTokens.title(600), 22, ShowTokens.AMBER))
	var lines := _label("\n".join(Array(CONTROLS).map(func(l: String) -> String: return tr(l))), ShowTokens.text(450), 20,
		Color(ShowTokens.TEXT, 0.9))
	lines.name = "Controls"
	lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_theme_constant_override("line_spacing", 4)
	mv.add_child(lines)
	set_memo(false)


# ------------------------------------------------------------------ детали оформления

func _make_styles() -> void:
	var off := StyleBoxFlat.new()
	off.bg_color = Color(1, 1, 1, 0.035)
	off.set_content_margin_all(9)
	off.content_margin_left = 10
	off.content_margin_right = 14
	off.border_width_left = 6
	off.border_color = Color(1, 1, 1, 0.0)
	var hover := off.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.075)
	hover.border_color = Color(ShowTokens.AMBER, 0.35)
	var on := off.duplicate() as StyleBoxFlat
	on.bg_color = Color(ShowTokens.PLATE_LIGHT, 0.96)
	on.border_color = ShowTokens.AMBER
	on.shadow_color = Color(0, 0, 0, 0.35)
	on.shadow_size = 10
	on.shadow_offset = Vector2(0, 4)
	var t_off := StyleBoxFlat.new()
	t_off.draw_center = false
	t_off.border_color = Color(1, 1, 1, 0.08)
	t_off.set_border_width_all(1)
	var t_on := t_off.duplicate() as StyleBoxFlat
	t_on.border_color = ShowTokens.AMBER
	t_on.set_border_width_all(3)
	_sb = {"off": off, "hover": hover, "on": on, "thumb_off": t_off, "thumb_on": t_on}


func _label(text: String, font: Font, px: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # текст уже переведён tr()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _plate_button(text: String, px: int) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", ShowTokens.title(600))
	b.add_theme_font_size_override("font_size", px)
	b.add_theme_color_override("font_color", ShowTokens.TEXT)
	b.add_theme_color_override("font_hover_color", ShowTokens.INK)
	b.add_theme_color_override("font_pressed_color", ShowTokens.INK)
	for st in [["normal", Color(ShowTokens.PLATE_LIGHT, 0.9), Color(1, 1, 1, 0.14)], ["hover", ShowTokens.AMBER, ShowTokens.AMBER],
			["pressed", ShowTokens.AMBER.darkened(0.15), ShowTokens.AMBER], ["focus", Color(ShowTokens.PLATE_LIGHT, 0.9), Color(1, 1, 1, 0.14)]]:
		var s := StyleBoxFlat.new()
		s.bg_color = st[1]
		s.border_color = st[2]
		s.set_border_width_all(1)
		s.skew = Vector2(ShowTokens.SKEW * 0.5, 0)
		s.content_margin_left = 20
		s.content_margin_right = 20
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		b.add_theme_stylebox_override(String(st[0]), s)
	return b


func _fact_chip(caption: String, value: String) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = Color(ShowTokens.PLATE, 0.86)
	s.border_color = ShowTokens.NULL_BLUE
	s.border_width_left = 4
	s.skew = Vector2(ShowTokens.SKEW * 0.5, 0)
	s.content_margin_left = 12
	s.content_margin_right = 14
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var c := _label(caption, ShowTokens.title(600), 16, ShowTokens.NULL_BLUE)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(c)
	row.add_child(_label(value, ShowTokens.text(500), 20, ShowTokens.TEXT))
	return p


func _key_chip(key: String, action: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s := StyleBoxFlat.new()
	s.bg_color = KEYCAP
	s.border_color = KEYCAP.darkened(0.35)
	s.border_width_bottom = 3
	s.set_corner_radius_all(4)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", s)
	cap.add_child(_label(key, ShowTokens.title(600), 18, ShowTokens.INK))
	row.add_child(cap)
	var a := _label(action, ShowTokens.text(450), 19, Color(ShowTokens.TEXT, 0.9))
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(a)
	return row


## Заглушка вместо снимка: тёмно-синий градиент, косые штрихи и знак N0 по центру.
func _stub(badge_k: float) -> Control:
	var c := Control.new()
	c.name = "Stub"
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void: _draw_bg(c))
	var b := TextureRect.new()
	b.texture = load(BADGE)
	b.anchor_left = 0.5 - badge_k * 0.5 * 9.0 / 16.0
	b.anchor_right = 0.5 + badge_k * 0.5 * 9.0 / 16.0
	b.anchor_top = 0.5 - badge_k * 0.5
	b.anchor_bottom = 0.5 + badge_k * 0.5
	b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	b.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	b.modulate = Color(1, 1, 1, 0.55)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(b)
	return c


## Фон эфира: градиент тёмно-синего сверху вниз и тонкие косые штрихи (как шторка заставки Лиги).
func _draw_bg(c: Control) -> void:
	var s := c.size
	c.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([NAVY_TOP, NAVY_TOP, NAVY_BOTTOM, NAVY_BOTTOM]))
	var slant := s.y * 0.28
	var step := 46.0 * maxf(s.y / H, 0.25)
	var x := -slant
	while x < s.x:
		c.draw_line(Vector2(x + slant, 0), Vector2(x, s.y), Color(1, 1, 1, 0.022), 1.0)
		x += step


func _gradient(colors: Array, offsets: Array, to: Vector2) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill_to = to
	return t
