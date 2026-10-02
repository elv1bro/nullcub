## Реплики N0 в бою (docs/plan-demo/N0_VOICE.md; автор 02.10.2026: «выдавать комментарии хотя бы субтитрами пока»).
## Таблица «повод → варианты»: ru показывается сейчас, en лежит рядом для перевода (этап 14, п. 5 — tr() и файлы языков).
## Строки из N0_VOICE.md (п. 10–17) приняты автором по направлению; поводы с пометкой «предложение» — новые, ждут автора.
## Правила подачи (N0_VOICE.md, «Правила подачи»): важные поводы (MAJOR) — всегда и перебивают текущую реплику; мелкие —
## только когда N0 молчит, не чаще minor_gap_s и с шансом minor_chance. Подряд один и тот же вариант не повторяется.
class_name N0Lines
extends RefCounted

const LANG := "ru"
const MAJOR: Array[String] = ["fight", "crit", "ko", "ko_player", "sudden_death", "draw", "decision",
	"vote_start", "vote_result", "vote_anomaly"]
const LINES := {
	# отсчёт перед FIGHT! (N0_VOICE п. 10)
	"fight": [
		{"ru": "Мембрана держит, стадион орёт, я вне зоны брызг. Поехали!",
			"en": "Membrane's holding, crowd's screaming, and I'm out of the splash zone. Go!"},
		{"ru": "Гравитация выставлена, конечности парят. Ну, кто-нибудь, ударьте кого-нибудь!",
			"en": "Gravity's set, limbs are floating. Somebody hit something!"},
	],
	# крит IMPACT (п. 11)
	"crit": [
		{"ru": "Это я почувствовал корпусом.", "en": "I felt that one in my casing."},
		{"ru": "Это покажут на большом экране. Дважды.", "en": "That's going on the big screen. Twice."},
	],
	# HEAD BLOW! (п. 12)
	"head": [
		{"ru": "Прямо в лицо! А лицо-то хорошее.", "en": "Right in the face! And it's a nice face."},
	],
	# отлетела деталь (п. 13)
	"part": [
		{"ru": "Это ваше? Кто-то захочет это вернуть.", "en": "Is that yours? Somebody's going to want that back."},
	],
	# KO соперника (п. 14) + вариант — предложение
	"ko": [
		{"ru": "И всё! Детали по всей арене. Уборщики, ваш выход.",
			"en": "And down they go! Parts everywhere. Cleanup crew, you're up."},
		{"ru": "Табло пишет FIGHTER OFFLINE. Я с табло согласен.", "en": "The board says FIGHTER OFFLINE. I agree with the board."},
	],
	# KO игрока — предложение
	"ko_player": [
		{"ru": "Ой. Вставай… то есть собирайся обратно.", "en": "Ouch. Get up… I mean, get yourself back together."},
		{"ru": "Это мы в повторе не покажем. Ладно, покажем.", "en": "We won't show that in the replay. Fine, we will."},
	],
	# комбо 4+ (п. 15)
	"combo": [
		{"ru": "Остановите это… нет, стойте, не надо. Рейтинги!", "en": "Somebody stop this— no, wait, don't. The ratings!"},
	],
	# Sudden Death (п. 16)
	"sudden_death": [
		{"ru": "Время вышло, а все ещё целы. По правилам Лиги кто-то должен лечь.",
			"en": "Time's up and nobody's down. League rules: now somebody has to be."},
	],
	# ничья (п. 17)
	"draw": [
		{"ru": "Ничья! Лига ненавидит ничьи. Сегодня без трофеев.",
			"en": "A draw! The League hates draws. Nobody takes a trophy home tonight."},
	],
	# победа по таймеру без KO — предложение
	"decision": [
		{"ru": "Время! Табло считает урон — без нокаута, зато честно.", "en": "Time! The board counts the damage — no KO, but fair."},
	],
	# голосование зрителей (AudienceVote, этап 15)
	"vote_start": [
		{"ru": "Зрители, ваш ход! Табло принимает голоса.", "en": "Audience, your move! The board is taking votes."},
	],
	"vote_result": [
		{"ru": "Зрители решили: %s. Держитесь за что-нибудь.", "en": "The crowd has spoken: %s. Hold on to something."},
	],
	"vote_anomaly": [
		{"ru": "Эм… это не то, за что голосовали. Технический сбой! Наверное.",
			"en": "Uh… that's not what they voted for. Technical difficulties! Probably."},
	],
	# мелкие поводы — предложение
	"membrane": [
		{"ru": "Мембрана держит! Пока что.", "en": "Membrane's holding! For now."},
		{"ru": "Отскок от мембраны — так и задумано.", "en": "Bounced off the membrane — totally intended."},
	],
	"ouch": [
		{"ru": "Ох. Даже смотреть было больно.", "en": "Oof. That hurt to watch."},
	],
	"far": [
		{"ru": "Соперник в %d метрах. Сам он не прилетит.", "en": "Your opponent is %d metres out. They won't fly over by themselves."},
		{"ru": "Стрелка у края экрана — это туда. Я бы полетел туда.", "en": "See the arrow at the edge? That way. I'd go that way."},
	],
	"quiet": [
		{"ru": "Это бой или медитация? Спрашиваю для трансляции.", "en": "Is this a fight or a meditation? Asking for the broadcast."},
		{"ru": "Зрители скучают. Я тоже.", "en": "The crowd's getting bored. So am I."},
	],
	# сок удара (HIT_FX.md §13, 02.10; поводы шлёт HitJuice.juice_event) — предложение
	# большая цифра-обломок урона упала (≥ JUICE_DIGIT_BIG, не крит)
	"digit_big": [
		{"ru": "%d! Это число теперь лежит на полу. Буквально.", "en": "%d! That number is on the floor now. Literally."},
		{"ru": "Минус %d. Табло записало, пол подобрал.", "en": "Minus %d. The board logged it, the floor caught it."},
	],
	# сильный удар по железной детали
	"metal": [
		{"ru": "Звенит! Значит, железо настоящее.", "en": "It rings! So the metal's real."},
		{"ru": "Искры! Мембрана, не бойся, это не тебе.", "en": "Sparks! Relax, membrane, that wasn't for you."},
	],
	# деталь вся в сколах (сумма следов ≥ JUICE_WORN_POWER)
	"worn": [
		{"ru": "Эта деталь уже вся в сколах. Как трофей — так себе.", "en": "That part's all chipped up. Not much of a trophy anymore."},
		{"ru": "По этой детали теперь можно читать историю боя.", "en": "You can read the whole fight off that part now."},
	],
	# цифр урона на полу много
	"digits_pile": [
		{"ru": "Цифры уже по щиколотку. Уборщики, вы где?", "en": "The numbers are ankle-deep. Cleanup crew, anyone?"},
	],
}

var minor_gap_s := 8.0
var minor_chance := 0.5
var rng := RandomNumberGenerator.new()
## Журнал для проб: [{event, text, t, major}].
var said: Array = []
var _last_minor := -INF
var _last_idx := {}


static func is_major(event: String) -> bool:
	return MAJOR.has(event)


## Текст реплики на повод или "" — промолчать. t — реальные секунды, speaking — N0 ещё говорит прошлую реплику.
## args — подстановка в строку с %d / %s.
func pick(event: String, t: float, speaking: bool, args: Array = []) -> String:
	if not LINES.has(event):
		return ""
	var major := is_major(event)
	if not major:
		if speaking or t - _last_minor < minor_gap_s or rng.randf() >= minor_chance:
			return ""
		_last_minor = t
	var vs: Array = LINES[event]
	var i := rng.randi_range(0, vs.size() - 1)
	if vs.size() > 1 and int(_last_idx.get(event, -1)) == i:
		i = (i + 1) % vs.size()
	_last_idx[event] = i
	var v: Dictionary = vs[i]
	var text := String(v.get(LANG, v["en"]))
	if text.contains("%"):
		text = text % args if not args.is_empty() else text.replace("%d", "?").replace("%s", "?")
	said.append({"event": event, "text": text, "t": t, "major": major})
	return text
