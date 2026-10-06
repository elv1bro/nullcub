## Связки (docs/plan-demo/WORKSHOP_V4.md «Связки»; автор 06.10: «чтобы можно было концы деталей соединить» → «все виды, можно перебить,
## и поршень»). Связка замыкает контур между двумя деталями, которые уже стоят на бойце: сборка перестаёт быть только деревом.
## Чертёж — BodyBlueprint.links: {id, type, a, pa, b, pb, len, channel?}; a / b — uid узлов со своим телом, pa / pb — точка в кадре
## тела (снята мастерской на стенде в позе покоя), len — длина в позе покоя (энергия считается по ней без сборки куклы).
## В бою (ModularDoll._build_links, после спавна в позе) связка — свои тела и суставы, которые Doll не считает суставами мышц:
##   • rod «Стержень» — одно тело, приварено к обеим деталям: держит расстояние и угол (рамы, треугольники);
##   • bar «Тяга» — одно тело на шарнирах: держит расстояние, концы вращаются (рычаги, ножницы, параллелограмм);
##   • spring «Пружина» — телескоп из двух половин с пружиной по оси: тянет к своей длине и пружинит;
##   • rope «Трос» — цепочка звеньев на шарнирах: не даёт разойтись дальше длины, сходиться может;
##   • piston «Поршень» — телескоп, который по клавише канала (I / O / P, как активные блоки) выдвигается и толкает детали врозь.
## Связку можно перебить: урон в её тела копит износ (Doll._wear_link), набралось — связка рвётся, контур раскрывается.
class_name KitLink
extends RefCounted

const ORDER := ["rod", "bar", "spring", "rope", "piston"]
## energy_m — энергии за метр (не меньше ENERGY_MIN), mass_m — кг на метр, r — радиус (м) вида и формы столкновения.
const TYPES := {
	"rod": {"title": "Стержень", "hint": "жёстко держит расстояние и угол: рамы и треугольники", "energy_m": 6.0, "mass_m": 1.2, "r": 0.022},
	"bar": {"title": "Тяга", "hint": "держит расстояние, концы вращаются: рычаги, ножницы, параллелограмм", "energy_m": 5.0, "mass_m": 1.0,
		"r": 0.02},
	"spring": {"title": "Пружина", "hint": "тянет к своей длине и пружинит: амортизаторы, катапульта", "energy_m": 5.0, "mass_m": 1.0,
		"r": 0.026, "k": 700.0, "c": 25.0, "stroke": 0.4},
	"rope": {"title": "Трос", "hint": "не даёт разойтись дальше длины, сходиться может: связать руки, праща", "energy_m": 3.0,
		"mass_m": 0.5, "r": 0.014, "seg": 0.12},
	"piston": {"title": "Поршень", "hint": "по клавише канала выдвигается и толкает: удар рукой, прыжок ногой", "energy_m": 8.0,
		"mass_m": 1.4, "r": 0.03, "extend": 0.6, "speed": 3.0, "force": 1800.0, "cost": 16.0},
}
const ENERGY_MIN := 2
const MIN_LEN := 0.1
const MAX_LEN := 2.2
const MAX_LINKS := 10
## Ключ канала у поршня (как у активных блоков, ActiveBlocks.NODE_KEY): 1…3.
const CHANNEL_KEY := "channel"
## Цвета видов: плашки мастерской и подсветка.
const COLORS := {"rod": Color(0.78, 0.8, 0.86), "bar": Color(1.0, 0.82, 0.45), "spring": Color(0.55, 0.95, 0.45),
	"rope": Color(0.82, 0.62, 0.42), "piston": Color(1.0, 0.45, 0.32)}


static func is_type(t: String) -> bool:
	return TYPES.has(t)


static func info(t: String) -> Dictionary:
	return TYPES.get(t, TYPES["rod"])


static func title_of(t: String) -> String:
	return String(TranslationServer.translate(String(info(t)["title"])))


static func hint_of(t: String) -> String:
	return String(TranslationServer.translate(String(info(t)["hint"])))


## Цена связки вида t длиной len_m (м).
static func energy_of(t: String, len_m: float) -> int:
	return maxi(ENERGY_MIN, int(ceil(float(info(t)["energy_m"]) * maxf(len_m, 0.0) - 0.001)))


## Масса связки (кг): на ❤ (PartHp) и на разгон — она тоже деталь.
static func mass_of(t: String, len_m: float) -> float:
	return maxf(float(info(t)["mass_m"]) * maxf(len_m, 0.0), 0.15)


static func colour(t: String) -> Color:
	return COLORS.get(t, Color.WHITE)


static func uses_channel(t: String) -> bool:
	return t == "piston"
