## Чувство управления — варианты «где приложена тяга» и «темп» (запрос автора 02.10: «в JS-игре было больше управление головой,
## а у нас как-то телом по-другому; сделать разные варианты и дать попробовать; общий разгон и скорость тоже настраиваемые»).
##
## В JS-версии (src/lib/moveBody.ts, battleSession) WASD толкает ГОЛОВУ: Body.applyForce(head, …), тело болтается на связях, руки и ноги
## хлещут по инерции. В Godot тяга шла на торс (Tuning.CONTROL_TARGET = "torso"): кукла двигалась «блоком». Здесь — живые варианты
## без правки Tuning: статическое состояние (общее на все площадки, переживает смену арены), Doll читает его каждый физический тик.
##
## Два набора, их можно смешивать и подкручивать ползунками (ControlFeelPanel):
##   • ВАРИАНТ (где и как прикладывается тяга): head_share (доля тяги на голову, 0 — торс, 1 — голова как в JS), upright (держать торс
##     вертикально, PD), lean (наклон корпуса в сторону хода — «нырок» головой вперёд), rotate (режим «руль»: ←→ вращение, ↑↓ тяга).
##   • ТЕМП (числа): thrust (Н/кг), max_speed (м/с), dash_mult (×тяга и потолок при ускорении), damp_mult (инерция: меньше — дольше
##     скользит), turn_boost (подпор при развороте — резче меняешь направление).
## Значения по умолчанию (вариант «ТЕЛО», темп «СЕЙЧАС») равны Tuning — игра и пробы без панели ведут себя как раньше. Сохранение в
## user://control_feel.cfg включается только панелью (enable_persistence): headless-пробы файла не читают.
class_name ControlFeel
extends RefCounted

const FILE := "user://control_feel.cfg"

## Подписи (title / note / подписи ползунков) — русские ключи перевода: показываются через tr() / TranslationServer.translate().
## Что меняют ВАРИАНТЫ и ТЕМПЫ. Всё остальное в словаре values — только то, что есть в KEYS.
const VARIANT_KEYS := ["head_share", "upright", "lean", "rotate"]
const TEMPO_KEYS := ["thrust", "max_speed", "dash_mult", "damp_mult", "turn_boost"]

const VARIANT_ORDER := ["body", "head", "head_up", "dive", "split", "rotate"]
const VARIANTS := {
	"body": {"title": "ТЕЛО", "note": "как было: тяга на центр тела, кукла летит блоком",
		"head_share": 0.0, "upright": 0.0, "lean": 0.0, "rotate": 0.0},
	"head": {"title": "ГОЛОВА", "note": "как в JS: тяга только на голову, тело и руки болтаются следом (на полу без опоры валится)",
		"head_share": 1.0, "upright": 0.0, "lean": 0.0, "rotate": 0.0},
	"head_up": {"title": "ГОЛОВА + СТОЙКА", "note": "голова ведёт, но корпус старается держаться вертикально",
		"head_share": 1.0, "upright": 0.55, "lean": 0.0, "rotate": 0.0},
	"dive": {"title": "ГОЛОВА-ТАРАН", "note": "голова ведёт и корпус ложится в ход — нырок на соперника",
		"head_share": 1.0, "upright": 0.0, "lean": 0.8, "rotate": 0.0},
	"split": {"title": "ГОЛОВА 60 / ТЕЛО 40", "note": "компромисс: голова тянет, торс подпирает — меньше болтанки",
		"head_share": 0.6, "upright": 0.25, "lean": 0.0, "rotate": 0.0},
	"rotate": {"title": "РУЛЬ", "note": "←→ крутят тело, ↑↓ тяга (режим rotate); Space+A/D тут не нужен",
		"head_share": 0.0, "upright": 0.0, "lean": 0.0, "rotate": 1.0},
}

const TEMPO_ORDER := ["now", "brisk", "action", "ram"]
const TEMPOS := {
	"now": {"title": "СЕЙЧАС", "note": "текущие числа Tuning (откалиброваны под бой)",
		"thrust": 12.0, "max_speed": 9.0, "dash_mult": 1.8, "damp_mult": 1.0, "turn_boost": 0.0},
	"brisk": {"title": "БОДРЫЙ", "note": "чуть резвее: быстрее разгон и потолок",
		"thrust": 15.0, "max_speed": 10.0, "dash_mult": 1.8, "damp_mult": 0.95, "turn_boost": 0.5},
	"action": {"title": "ЭКШЕН", "note": "ближе к веб-игре: разгон рывком, скользит, резкие развороты",
		"thrust": 20.0, "max_speed": 12.0, "dash_mult": 1.8, "damp_mult": 0.85, "turn_boost": 1.0},
	"ram": {"title": "ТАРАН", "note": "максимум: летишь как снаряд, очень резкие развороты",
		"thrust": 26.0, "max_speed": 15.0, "dash_mult": 2.0, "damp_mult": 0.75, "turn_boost": 1.5},
}

## Ползунки панели: [ключ, подпись, мин, макс, шаг, формат]
const SLIDERS := [
	["thrust", "Разгон (Н/кг)", 4.0, 40.0, 0.5, "%.1f"],
	["max_speed", "Скорость, потолок (м/с)", 4.0, 22.0, 0.5, "%.1f"],
	["dash_mult", "Ускорение Shift (×)", 1.0, 3.0, 0.1, "%.1f"],
	["damp_mult", "Инерция: торможение (×)", 0.2, 2.0, 0.05, "%.2f"],
	["turn_boost", "Резкость разворота", 0.0, 3.0, 0.1, "%.1f"],
	["head_share", "Тяга на голову (0 тело … 1 голова)", 0.0, 1.0, 0.05, "%.2f"],
	["upright", "Корпус вертикально", 0.0, 1.0, 0.05, "%.2f"],
	["lean", "Нырок: наклон в ход", 0.0, 1.0, 0.05, "%.2f"],
]

## Параметры PD торса (на кг thrust_mass): K — Н·м/рад, D — Н·м·с/рад при upright/lean = 1.
const UPRIGHT_K := 8.0
const UPRIGHT_D := 2.0
const LEAN_MAX_RAD := 1.15            # угол нырка при lean = 1 (≈ 66°): торс почти ложится, голова вперёд
const LEAN_GAIN_MIN := 0.6            # жёсткость PD при нырке, даже если upright = 0
const TURN_BOOST_MIN_SPEED := 1.0     # м/с: ниже подпора разворота нет (стоим — тяга обычная)

static var variant := "body"          # ключ VARIANTS или "custom" (ползунки разошлись с набором)
static var tempo := "now"             # ключ TEMPOS или "custom"
static var values: Dictionary = {}
## Растёт при любом изменении: Doll сверяет и пересчитывает дамп частей, панель обновляет подписи.
static var rev := 0
static var persist := false
## Пробы с окном (панель Tab создаётся в каждом бою): true — enable_persistence ничего не читает и не пишет user://control_feel.cfg,
## иначе проба затирала бы сохранённые настройки автора (у проектов в worktree тот же app_userdata).
static var no_disk := false
static var panel_open := false


static func _ensure() -> void:
	if values.is_empty():
		_apply_set(VARIANTS["body"], VARIANT_KEYS)
		_apply_set(TEMPOS["now"], TEMPO_KEYS)


static func _apply_set(src: Dictionary, keys: Array) -> void:
	for k in keys:
		values[k] = float(src[k])


# --- чтение (Doll, каждый физический тик) ---

static func get_value(key: String) -> float:
	_ensure()
	return float(values[key])


static func thrust() -> float:
	return get_value("thrust")


static func max_speed() -> float:
	return get_value("max_speed")


static func dash_mult() -> float:
	return get_value("dash_mult")


static func damp_mult() -> float:
	return get_value("damp_mult")


static func turn_boost() -> float:
	return get_value("turn_boost")


static func head_share() -> float:
	return get_value("head_share")


static func upright() -> float:
	return get_value("upright")


static func lean() -> float:
	return get_value("lean")


static func is_rotate() -> bool:
	return get_value("rotate") > 0.5


# --- изменение ---

static func set_variant(id: String) -> void:
	if not VARIANTS.has(id):
		return
	_ensure()
	_apply_set(VARIANTS[id], VARIANT_KEYS)
	variant = id
	_changed()


static func set_tempo(id: String) -> void:
	if not TEMPOS.has(id):
		return
	_ensure()
	_apply_set(TEMPOS[id], TEMPO_KEYS)
	tempo = id
	_changed()


## Ползунок: меняет одно число; если набор перестал совпадать с пресетом — подпись «СВОЙ».
static func set_value(key: String, v: float) -> void:
	_ensure()
	if not values.has(key) or is_equal_approx(float(values[key]), v):
		return
	values[key] = v
	if key in VARIANT_KEYS:
		variant = _match_preset(VARIANTS, VARIANT_KEYS)
	if key in TEMPO_KEYS:
		tempo = _match_preset(TEMPOS, TEMPO_KEYS)
	_changed()


static func _match_preset(table: Dictionary, keys: Array) -> String:
	for id in table:
		var ok := true
		for k in keys:
			if not is_equal_approx(float(values[k]), float(table[id][k])):
				ok = false
				break
		if ok:
			return String(id)
	return "custom"


static func cycle_variant(dir: int = 1) -> String:
	var i: int = VARIANT_ORDER.find(variant)
	i = (i + dir + VARIANT_ORDER.size()) % VARIANT_ORDER.size() if i >= 0 else (0 if dir > 0 else VARIANT_ORDER.size() - 1)
	set_variant(String(VARIANT_ORDER[i]))
	return variant


static func cycle_tempo(dir: int = 1) -> String:
	var i: int = TEMPO_ORDER.find(tempo)
	i = (i + dir + TEMPO_ORDER.size()) % TEMPO_ORDER.size() if i >= 0 else (0 if dir > 0 else TEMPO_ORDER.size() - 1)
	set_tempo(String(TEMPO_ORDER[i]))
	return tempo


## Всё как в Tuning: вариант ТЕЛО + темп СЕЙЧАС, ДРАЙВ выключен.
static func reset() -> void:
	Drive.on = false
	values = {}
	variant = "body"
	tempo = "now"
	_ensure()
	_changed()


static func variant_title() -> String:
	return TranslationServer.translate(String(VARIANTS[variant]["title"]) if VARIANTS.has(variant) else "СВОЙ")


static func tempo_title() -> String:
	return TranslationServer.translate(String(TEMPOS[tempo]["title"]) if TEMPOS.has(tempo) else "СВОЙ")


static func variant_note() -> String:
	return TranslationServer.translate(String(VARIANTS[variant]["note"]) if VARIANTS.has(variant) else "набор ползунков, не совпадающий ни с одним вариантом")


static func tempo_note() -> String:
	return TranslationServer.translate(String(TEMPOS[tempo]["note"]) if TEMPOS.has(tempo) else "числа подкручены вручную")


## Коротко для тоста и панели клавиш: «ГОЛОВА · ЭКШЕН» (+ « · ДРАЙВ», если включён).
static func label() -> String:
	var s := "%s · %s" % [variant_title(), tempo_title()]
	return s + " · " + TranslationServer.translate("ДРАЙВ") if Drive.on else s


static func _changed() -> void:
	rev += 1
	if persist:
		save()


## Поднять rev (и сохранить): чужие переключатели того же файла — ДРАЙВ (Drive) — меняют дамп и гравитацию кукол.
static func bump() -> void:
	_changed()


# --- сохранение (только если включила панель) ---

static func enable_persistence() -> void:
	if persist or no_disk:
		return
	persist = true
	load_saved()


static func save() -> void:
	_ensure()
	var cf := ConfigFile.new()
	cf.set_value("control_feel", "variant", variant)
	cf.set_value("control_feel", "tempo", tempo)
	cf.set_value("drive", "on", Drive.on)
	for k in values:
		cf.set_value("values", String(k), float(values[k]))
	cf.save(FILE)


static func load_saved() -> void:
	_ensure()
	var cf := ConfigFile.new()
	if cf.load(FILE) != OK:
		return
	for k in values.keys():
		if cf.has_section_key("values", String(k)):
			values[k] = float(cf.get_value("values", String(k), values[k]))
	variant = String(cf.get_value("control_feel", "variant", variant))
	tempo = String(cf.get_value("control_feel", "tempo", tempo))
	if variant != "custom" and not VARIANTS.has(variant):
		variant = _match_preset(VARIANTS, VARIANT_KEYS)
	if tempo != "custom" and not TEMPOS.has(tempo):
		tempo = _match_preset(TEMPOS, TEMPO_KEYS)
	Drive.on = bool(cf.get_value("drive", "on", Drive.on))
	rev += 1
