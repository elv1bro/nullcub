## Имена деталей для игрока (мастерская UI/UX v0.3, §12: «внутренние id не должны появляться в обычном UI»).
## PartDef.title — рабочая подпись из пайплайна кита (tools/build_body_kit.gd, build_body_parts.gd): в ней размер и происхождение
## в скобках — «Базовая (предплечье v3)», «Сегмент конечности (хлам)», «Ботинок (кит «Человек»)». Это удобно при сборке ассетов,
## но на карточке каталога и в инспекторе читается как таблица, а не как детали на верстаке. Здесь — короткое имя каждой детали
## (≤ 22 символов, обычно ≤ 18), одно на весь каталог: две детали с одинаковым именем на полке игрок не отличит.
## Как различаем похожие:
##   • конечности кита S / L — «… рука» / «… нога» (размер под руку и под ногу, как «Пружинная рука» в спецификации); у базовой ещё
##     LA / LL — «Базовое предплечье» / «Базовая голень» (риг v3);
##   • старые детали из клёна (wood_*, кукла «Человек (кукла v3)») — «Кленовое плечо», «Кленовая кисть»…;
##   • дубли кита «Человек» (kit_human_*: на полках их нет — CraftEdit.SHELF_HIDDEN_PREFIXES, но на стенде в инспекторе есть) —
##     «… человечка», чтобы не совпасть с «Базовая рука» / «Варежка» / «Ядро-бочка», из мешей которых они собраны;
##   • хлам Свалки (junk_*) — «… из хлама», где без этого имя совпало бы с деталью кита (варежка, ядро, сегмент).
## Новая деталь без записи в NAMES не ломает UI: of() чистит title (скобки и « · …»), а tests/part_names_probe.tscn падает, пока
## имя не добавлено сюда.
## Поиск каталога — search_text(): имя, исходный title (по нему находятся «хлам», «клён», «гидравлика»), вид, материал и теги.
class_name PartNames
extends RefCounted

## id PartDef (data/body/parts/<id>.tres) → имя для игрока. Порядок — как полки CraftEdit.KIND_ORDER.
const NAMES := {
	# ядра (вкладка «Тело»)
	"kit_core_ball": "Ядро-хаб",
	"kit_core_barrel": "Ядро-бочка",
	"kit_core_boiler": "Ядро-котёл",
	"kit_core_cage": "Ядро-клетка",
	"kit_core_crate": "Ядро-ящик",
	"kit_core_drum": "Ядро-бак",
	"kit_core_toy": "Ядро-игрушка",
	"kit_human_torso": "Ядро человечка",
	"wood_torso": "Кленовое ядро",
	"junk_torso": "Ядро из хлама",
	# головы
	"kit_head_bot": "Голова-экран",
	"kit_head_can": "Голова-банка",
	"kit_head_cow": "Голова-корова",
	"kit_head_crate": "Голова-ящик",
	"kit_head_devil": "Голова-чёртик",
	"kit_head_horned": "Рогатый шлем",
	"kit_head_lantern": "Голова-фонарь",
	"kit_head_round": "Голова-игрушка",
	"kit_head_skull": "Череп с карточкой",
	"kit_human_head": "Голова человечка",
	"wood_head": "Голова-яйцо",
	"metal_head": "Голова-ведро",
	"junk_head_cracked": "Треснувшая голова",
	"junk_head_sad": "Грустная голова",
	"junk_head_scared": "Испуганная голова",
	# конечности кита: _s — под руку, _l — под ногу; у базовой ещё предплечье / голень рига v3
	"kit_limb_basic_s": "Базовая рука",
	"kit_limb_basic_la": "Базовое предплечье",
	"kit_limb_basic_l": "Базовая нога",
	"kit_limb_basic_ll": "Базовая голень",
	"kit_limb_bone_s": "Костяная рука",
	"kit_limb_bone_l": "Костяная нога",
	"kit_limb_curved_s": "Рука-труба",
	"kit_limb_curved_l": "Нога-труба",
	"kit_limb_fantasy_s": "Сказочная рука",
	"kit_limb_fantasy_l": "Сказочная нога",
	"kit_limb_piston_s": "Поршневая рука",
	"kit_limb_piston_l": "Поршневая нога",
	"kit_limb_plate_s": "Бронированная рука",
	"kit_limb_plate_l": "Бронированная нога",
	"kit_limb_robotic_s": "Робо-рука",
	"kit_limb_robotic_l": "Робо-нога",
	"kit_limb_rope_s": "Верёвочная рука",
	"kit_limb_rope_l": "Верёвочная нога",
	"kit_limb_spiked_s": "Шипастая рука",
	"kit_limb_spiked_l": "Шипастая нога",
	"kit_limb_spring_s": "Пружинная рука",
	"kit_limb_spring_l": "Пружинная нога",
	"kit_limb_tentacle_s": "Рука-щупальце",
	"kit_limb_tentacle_l": "Нога-щупальце",
	"kit_limb_thick_s": "Толстая рука",
	"kit_limb_thick_l": "Толстая нога",
	"kit_limb_thin_s": "Тонкая рука",
	"kit_limb_thin_l": "Тонкая нога",
	# конечности кита «Человек», клёна, тяжёлые, железные и хлам
	"kit_human_upper_arm": "Плечо человечка",
	"kit_human_lower_arm": "Предплечье человечка",
	"kit_human_upper_leg": "Бедро человечка",
	"kit_human_lower_leg": "Голень человечка",
	"wood_upper_arm": "Кленовое плечо",
	"wood_lower_arm": "Кленовое предплечье",
	"wood_upper_leg": "Кленовое бедро",
	"wood_lower_leg": "Кленовая голень",
	"wood_big_upper_arm": "Тяжёлое плечо",
	"wood_big_lower_arm": "Тяжёлое предплечье",
	"metal_forearm": "Железное предплечье",
	"junk_upper_limb": "Сегмент из хлама",
	"junk_lower_limb": "Прут из хлама",
	# кисти
	"kit_hand_clamp": "Тиски",
	"kit_hand_claw": "Клешня",
	"kit_hand_fist": "Кулак",
	"kit_hand_mitten": "Варежка",
	"kit_hand_paddle": "Лопасть",
	"kit_human_hand": "Варежка человечка",
	"wood_hand": "Кленовая кисть",
	"wood_big_hand": "Кулак-колотушка",
	"iron_ball_fist": "Шар-кулак",
	"junk_hand": "Варежка из хлама",
	# стопы
	"kit_foot_boot": "Ботинок",
	"kit_foot_flipper": "Ласта",
	"kit_foot_peg": "Колышек",
	"kit_foot_spring": "Пого-пружина",
	"kit_foot_wheel": "Колесо",
	"kit_human_foot": "Ботинок человечка",
	"wood_foot": "Кленовая стопа",
	"junk_foot": "Стопа-клин",
	# суставы и цепь
	"extra_joint": "Добавочный сустав",
	"chain_segment": "Цепь",
	# щиток, броня, декор
	"shield_plate": "Щиток",
	"kit_deco_gauntlet_s": "Наруч",
	"kit_deco_gauntlet_l": "Наголенник",
	"kit_deco_pauldron": "Наплечник",
	"kit_deco_antenna": "Антенна",
	"kit_deco_banner": "Флажок",
	"kit_deco_chimney": "Дымоход",
	"kit_deco_crown": "Корона",
	"kit_deco_horns": "Рога",
	"kit_deco_plume": "Султан",
	"kit_deco_spikes_s": "Шипастый браслет",
	"kit_deco_spikes_l": "Шипастый ошейник",
	"kit_deco_wings": "Жестяные крылья",
	# верстак оружия: рукояти, навершия, моды
	"handle_short": "Короткая рукоять",
	"handle_long": "Длинная рукоять",
	"head_mallet": "Киянка",
	"head_hammer": "Молот",
	"head_mace_ball": "Шар булавы",
	"blade_sword": "Клинок",
	"blade_axe": "Топор",
	"hook": "Крюк",
	"kit_anchor_head": "Якорь",
	"kit_drill_head": "Бур",
	"kit_pick_head": "Кирка",
	"kit_saw_disc": "Дисковая пила",
	"kit_spear_tip": "Наконечник копья",
	"kit_torch_head": "Факел",
	"mod_nails": "Гвозди",
	"mod_iron_plate": "Железная накладка",
	# NULL League (tools/blender/kit_league.py; в title — «(лига)», по нему их и находит поиск)
	"kit_core_league_orb": "Ядро-око",
	"kit_core_league_gyro": "Ядро-гироскоп",
	"kit_core_league_crystal": "Кристальное ядро",
	"kit_core_league_flesh": "Живое ядро",
	"kit_head_league_eye": "Голова-око",
	"kit_head_league_crystal": "Голова-друза",
	"kit_head_league_ring": "Голова-портал",
	"kit_head_league_flesh": "Живая голова",
	"kit_limb_league_float_s": "Парящая рука",
	"kit_limb_league_float_l": "Парящая нога",
	"kit_limb_league_crystal_s": "Кристальная рука",
	"kit_limb_league_crystal_l": "Кристальная нога",
	"kit_limb_league_scythe_s": "Рука-коса",
	"kit_limb_league_scythe_l": "Нога-коса",
	"kit_limb_league_tentacle_s": "Живая рука-щупальце",
	"kit_limb_league_tentacle_l": "Живая нога-щупальце",
	"kit_hand_league_talon": "Золотые когти",
	"kit_hand_league_pincer": "Чёрная клешня",
	"kit_foot_league_hover": "Парящая стопа",
	"kit_foot_league_spike": "Стопа-коготь",
	"kit_blade_league_crystal": "Кристальный клинок",
	"kit_mace_league_orb": "Шар с кристаллами",
	"kit_deco_league_halo": "Гало поля",
	"kit_deco_league_shield_s": "Энергощит руки",
	"kit_deco_league_shield_l": "Энергощит ноги",
	# активные блоки (tools/blender/kit_active.py, docs/plan-demo/ACTIVE_BLOCKS.md)
	"kit_active_booster": "Ускоритель",
	"kit_active_flamer": "Огнемёт",
	"kit_active_gun": "Пулемёт",
	"kit_active_magnet": "Магнит",
	"kit_active_jetpack": "Реактивный ранец",
	"kit_active_league_gravity": "Гравиядро",
	"kit_active_league_shield": "Эмиттер щита",
	"kit_active_league_phase": "Фазовый модуль",
	"kit_active_league_repair": "Ядро самопочинки",
	"kit_active_jet_boots": "Ранец для ног",
	"kit_active_grapple": "Крюк-кошка",
	"kit_active_spring": "Пружина-катапульта",
	"kit_active_smoke": "Дымовая шашка",
	"kit_active_shock": "Разрядник",
	"kit_active_mine": "Минный лоток",
	"kit_active_searchlight": "Прожектор",
	"kit_active_anchor": "Тормоз-якорь",
	# наборы 04.10: про-лига Земли (tools/blender/kit_pro.py) и живые детали Аоэлюн (kit_aoe.py)
	"kit_core_pro_gyro": "Ядро-гиростаб",
	"kit_core_pro_reactor": "Ядро-реактор",
	"kit_head_pro_visor": "Голова-визор",
	"kit_head_pro_pilot": "Шлем пилота",
	"kit_limb_pro_panel_s": "Панельная рука",
	"kit_limb_pro_panel_l": "Панельная нога",
	"kit_hand_pro_claw": "Спортивная клешня",
	"kit_hand_pro_crusher": "Дробилка",
	"kit_blade_pro_energy": "Энергоклинок",
	"kit_hammer_pro_drum": "Молот-барабан",
	"kit_foot_pro_wheel": "Большое колесо",
	"kit_foot_pro_spike": "Стопа-копьё",
	"kit_foot_pro_prop": "Стопа-пропеллер",
	"kit_deco_pro_panel_s": "Щит-панель руки",
	"kit_deco_pro_panel_l": "Щит-панель ноги",
	"kit_core_aoe_heart": "Ядро-сердце",
	"kit_head_aoe_watcher": "Голова-наблюдатель",
	"kit_head_aoe_hunter": "Голова-охотник",
	"kit_limb_aoe_sinew_s": "Рука-жила",
	"kit_limb_aoe_sinew_l": "Нога-жила",
	"kit_limb_aoe_blade_s": "Рука-лезвия",
	"kit_limb_aoe_blade_l": "Нога-лезвия",
	"kit_limb_aoe_whip_s": "Рука-плеть",
	"kit_limb_aoe_whip_l": "Нога-плеть",
	"kit_hand_aoe_claw": "Живой коготь",
	"kit_hand_aoe_hook": "Крюк-захват",
	"kit_foot_aoe_stilt": "Ходуля",
	"kit_foot_aoe_grip": "Присоска",
	"kit_deco_aoe_carapace_s": "Панцирь руки",
	"kit_deco_aoe_carapace_l": "Панцирь ноги",
	"kit_deco_aoe_spines": "Спинные иглы",
	# разветвители 04.10 («невозможные конструкции»): три разъёма под конечности
	"kit_hub_pro_tee": "Тройник",
	"kit_limb_pro_spine_s": "Малая рама-позвонок",
	"kit_limb_pro_spine_l": "Большая рама-позвонок",
	"kit_hub_aoe_node": "Узел-сплетение",
	"kit_limb_aoe_spine_s": "Малый позвонок",
	"kit_limb_aoe_spine_l": "Большой позвонок",
}
## PartDef.material (физика старых деталей: вес, звук, магнит) словами — для поиска у деталей без base_mat.
const MATERIAL_WORDS := {"wood": "дерево", "iron": "железо", "cloth": "ткань"}
## PartDef.hit_profile словами (WORKSHOP_V3.md §4): «колющая» — бонус на тычке, «дробящая» — на размахе.
const PROFILE_WORDS := {"sharp": "колющая", "blunt": "дробящая", "soft": "мягкая"}
## Имя тела в кукле → слово размера: конечность под руку / под ногу (кит S / L, риг v3 — плечо, предплечье / бедро, голень).
const LIMB_WORDS := {"UpperArm": "рука короткая", "LowerArm": "рука короткая", "UpperLeg": "нога длинная", "LowerLeg": "нога длинная"}
## Навершие по имени тела (PartDef.name_prefix): чем оно бьёт.
const WEAPON_HEAD_WORDS := {"Blade": "лезвие", "Hammer": "молот", "Mace": "булава", "Hook": "крюк"}
## Виды верстака оружия (у тела навершие — тоже «оружие»: тело становится частью оружия, CONCEPT_V2 §8).
const WEAPON_KINDS := ["weapon_head", "mod", "handle", "chain"]


## Имя детали для игрока (NAMES — русские ключи перевода, на выходе переводятся): NAMES, иначе title без скобок и хвоста « · …» (новая деталь до записи в NAMES), иначе id (title пуст).
static func of(d: PartDef) -> String:
	if d == null:
		return ""
	if NAMES.has(d.id):
		return String(TranslationServer.translate(String(NAMES[d.id])))
	var clean := clean_title(d.title)
	return clean if clean != "" else d.id


## То же по id; детали нет в data/body/parts — сам id (чертёж со ссылкой на удалённую деталь: validate() всё равно откажет).
static func of_id(part_id: String) -> String:
	if NAMES.has(part_id):
		return String(TranslationServer.translate(String(NAMES[part_id])))
	var d := BodyBlueprint.part_def(part_id) if part_id != "" else null
	return of(d) if d != null else part_id


## «Базовая (предплечье v3)» → «Базовая», «Сегмент · хлам» → «Сегмент»: служебные хвосты подписи пайплайна.
static func clean_title(title: String) -> String:
	var s := title
	var open := s.find("(")
	while open >= 0:
		var close := s.find(")", open)
		s = s.substr(0, open) + (s.substr(close + 1) if close >= 0 else "")
		open = s.find("(")
	var dot := s.find("·")
	if dot >= 0:
		s = s.substr(0, dot)
	while s.contains("  "):
		s = s.replace("  ", " ")
	return s.strip_edges()


## Строка поиска каталога (нижний регистр, слова через пробел): имя, исходный title, вид, материал и теги — рука / нога по размеру,
## колющая / дробящая по форме, шипы, оружие. По ней фильтр находит «Пружинная нога» и по «пружина», и по «нога», и по «железо».
## Слова берутся и на языке игрока (в английском — «spring leg», «iron», «junk»), и русские исходники: игрок с английским
## интерфейсом, набравший «хлам», тоже найдёт деталь.
static func search_text(d: PartDef) -> String:
	if d == null:
		return ""
	var words: PackedStringArray = [of(d), d.title]
	if NAMES.has(d.id):
		_add_word(words, String(NAMES[d.id]))
	_add_word(words, String(CraftEdit.KIND_TITLES.get(d.kind, "")))
	var md := MaterialDef.get_def(d.base_mat) if d.base_mat != "" else null
	if md != null:
		words.append(md.title)
		if d.material == "iron":
			_add_word(words, String(MATERIAL_WORDS["iron"]))   # ржавчина, крашеный лист — всё равно железо (магнит Свалки)
	else:
		_add_word(words, String(MATERIAL_WORDS.get(d.material, "")))
	match d.kind:
		"core":
			_add_word(words, "тело торс")
		"limb":
			_add_word(words, String(LIMB_WORDS.get(d.name_prefix, "")))
		"hand":
			_add_word(words, "рука")
		"foot":
			_add_word(words, "нога")
		"joint", "chain":
			_add_word(words, "шарнир")
		"weapon_head":
			_add_word(words, String(WEAPON_HEAD_WORDS.get(d.name_prefix, "")))
	if WEAPON_KINDS.has(d.kind):
		_add_word(words, "оружие")
	_add_word(words, String(PROFILE_WORDS.get(d.hit_profile, "")))
	if d.id.contains("spike") or d.id.contains("nails"):
		_add_word(words, "шипы")
	if d.id.begins_with("junk_"):
		_add_word(words, "хлам")
	var out: PackedStringArray = []
	for w in words:
		var s := w.strip_edges().to_lower()
		if s != "" and not out.has(s):
			out.append(s)
	return " ".join(out)


## Слово поиска: перевод на язык игрока и русский исходник (если они разные).
static func _add_word(words: PackedStringArray, ru: String) -> void:
	if ru == "":
		return
	words.append(String(TranslationServer.translate(ru)))
	words.append(ru)
