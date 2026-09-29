## Пресет эффектов удара для игрока (docs/plan-demo/HIT_FX.md §11.2): full / reduced / off — одна точка для всех потребителей.
## Значения — Tuning.HITFX_PRESETS[name]: flash (0–1), shake (0–1), impact_frames, crit_cinematic, time_fx.
##   HitFxDirector — FxPreset.apply(director) пишет flash_intensity / shake_intensity / impact_frames / crit_cinematic в его var
##                   (их же читает CritCinematic через _flag); зовут Match._ensure_fx_directors и set_preset (все узлы группы
##                   hit_fx_director);
##   Match         — request_time_scale при time_fx = false отказывает всем тегам, кроме ko* (FxPreset.time_tag_allowed);
##                   старый hit_feel: hit stop — только при time_fx, тряска и zoom × shake();
##   площадка      — F10 (scenes/playground.gd): cycle() и тост «FX: FULL / REDUCED / OFF».
## Состояние статическое: переживает смену арены и рестарт, в headless-пробах по умолчанию full (Tuning.HITFX_PRESET_DEFAULT).
class_name FxPreset
extends RefCounted

const FULL := "full"
const REDUCED := "reduced"
const OFF := "off"
const DIRECTOR_GROUP := "hit_fx_director"

static var current: String = Tuning.HITFX_PRESET_DEFAULT


static func values(name: String = "") -> Dictionary:
	var n := name if name != "" else current
	return Tuning.HITFX_PRESETS.get(n, Tuning.HITFX_PRESETS[Tuning.HITFX_PRESET_DEFAULT]) as Dictionary


static func flash() -> float:
	return clampf(float(values().get("flash", 1.0)), 0.0, 1.0)


static func shake() -> float:
	return clampf(float(values().get("shake", 1.0)), 0.0, 1.0)


static func impact_frames() -> bool:
	return bool(values().get("impact_frames", true))


static func crit_cinematic() -> bool:
	return bool(values().get("crit_cinematic", true))


## Стоп-кадры и замедления эффектов (heavy_stop, крит). false — только KO slow-mo.
static func time_fx() -> bool:
	return bool(values().get("time_fx", true))


## Разрешён ли тег Match.request_time_scale в текущем пресете: при time_fx = false — только ko* (ko_crit_slowmo).
static func time_tag_allowed(tag: String) -> bool:
	return time_fx() or tag.begins_with("ko")


## Выставить пресет (неизвестное имя — не меняет) и применить ко всем директорам в дереве (tree может быть null). Возвращает текущий.
static func set_preset(name: String, tree: SceneTree = null) -> String:
	if Tuning.HITFX_PRESETS.has(name):
		current = name
	apply_all(tree)
	return current


## Следующий пресет по кругу Tuning.HITFX_PRESET_ORDER.
static func cycle(tree: SceneTree = null) -> String:
	var order: Array = Tuning.HITFX_PRESET_ORDER
	var i := order.find(current)
	return set_preset(String(order[(i + 1) % order.size()]), tree)


## Записать значения пресета в var директора (HitFxDirector: flash_intensity, shake_intensity, impact_frames, crit_cinematic).
static func apply(director: Object) -> void:
	if director == null or not is_instance_valid(director):
		return
	director.set("flash_intensity", flash())
	director.set("shake_intensity", shake())
	director.set("impact_frames", impact_frames())
	director.set("crit_cinematic", crit_cinematic())


static func apply_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for d in tree.get_nodes_in_group(DIRECTOR_GROUP):
		apply(d)


## Подпись для тоста: «FX: FULL».
static func label() -> String:
	return "FX: " + current.to_upper()
