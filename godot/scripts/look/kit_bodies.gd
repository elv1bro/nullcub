## Бойцы кита вместо голого деревянного манекена (проход по картинке, look-faces, пункт 4; docs/plan-demo/look/faces.md).
## Два пункта «ВИД» в группе «Лица», оба ВЫКЛЮЧЕНЫ по умолчанию — тело меняет игру:
##   faces_kit_human — манекен → кит «Человек» (scenes/body/presets/kit_human.tscn: формы, массы, суставы байт в байт как у doll.tscn,
##       BODY_KIT.md §3.2; голова Kit_Head_Round с плашкой лица — на ней видны выражения). Отличия: вид (бочка, ремни цвета игрока), нет
##       различия «клён / орех» у P1 и P2 — только цвет игрока; материал удара для искр и звука — по деталям кита;
##   faces_kit_sets — манекен → бойцы-наборы: P1 Спринтер (51.5 кг), P2 Титан (60 кг), KIT_SETS.md. Другая масса, тяга фиксирована
##       (fixed_thrust: тяжёлый разгоняется медленнее), другие формы, оружие на руках — это другой баланс.
## Работает только там, где кукла — манекен (doll.tscn / doll_dark.tscn) и бой ведёт обычный Match (купол, быстрый бой из гаража,
## Свалка, мастерская, площадка тела): спорт, бомба, PvE, стычка, гонка, кампания — не трогаются (свои правила тел и HP).
## Общий рубильник Shift+Э подмену не трогает (checked): «до / после» — это один кадр, а подмена пересоздаёт кукол.
## Подмена = Match.respawn_doll с подменённым scene_file_path (как playground_body.set_preset): кукла пересоздаётся на точке спавна,
## HP полное. Исходная сцена — meta META_ORIG новой куклы: выключение пункта возвращает манекен. KO и R пересоздают ту же сцену.
## Зовёт FaceExpr (узел куклы): on_doll_ready — при появлении куклы, on_look — по сигналу Look.changed.
class_name KitBodies
extends RefCounted

const LOOK_HUMAN := &"faces_kit_human"
const LOOK_SETS := &"faces_kit_sets"
const MANNEQUIN: Array[String] = ["res://scenes/doll/doll.tscn", "res://scenes/doll/doll_dark.tscn"]
const HUMAN := "res://scenes/body/presets/kit_human.tscn"
## По player_index % 2.
const SETS: Array[String] = ["res://scenes/body/presets/pro_sprinter.tscn", "res://scenes/body/presets/pro_titan.tscn"]
const MATCH_SCRIPT := "res://scripts/core/match.gd"
const META_ORIG := "kit_bodies_orig"
const RETRY_S := 0.1
const RETRIES := 30


static func register() -> void:
	var l := FaceExpr._look()
	if l == null:
		return
	l.call("add", LOOK_HUMAN, TranslationServer.translate("Манекены → кит «Человек» (та же физика)"), TranslationServer.translate("Лица"), false)
	l.call("add", LOOK_SETS, TranslationServer.translate("Манекены → бойцы-наборы: Спринтер и Титан (другая масса)"),
			TranslationServer.translate("Лица"), false)


## Сцена, которой кукла должна быть сейчас: исходная (манекен) или подмена по пунктам. Не манекен — как есть.
static func target_scene(d: Doll) -> String:
	var orig := String(d.get_meta(META_ORIG, d.scene_file_path))
	if not MANNEQUIN.has(orig):
		return d.scene_file_path
	if checked(LOOK_SETS):
		return SETS[absi(d.player_index) % SETS.size()]
	if checked(LOOK_HUMAN):
		return HUMAN
	return orig


## Галочка пункта БЕЗ общего рубильника «до / после»: Shift+Э сравнивает один и тот же кадр, а смена тела пересоздаёт кукол на
## точках спавна — поэтому подмену тел включает и выключает только её галочка.
static func checked(id: StringName) -> bool:
	var l := FaceExpr._look()
	return l != null and bool(l.call("checked", id))


static func on_doll_ready(fe: FaceExpr) -> void:
	register()
	if fe.doll != null and target_scene(fe.doll) != fe.doll.scene_file_path:
		_try_swap(fe.doll, RETRIES)


static func on_look(fe: FaceExpr, id: StringName, _on: bool) -> void:
	if id != LOOK_HUMAN and id != LOOK_SETS:
		return
	if fe.doll != null and target_scene(fe.doll) != fe.doll.scene_file_path:
		var iid := fe.doll.get_instance_id()
		(func() -> void: _try_swap_id(iid, RETRIES)).call_deferred()


## Обычный Match куклы (не подкласс: у режимов свои правила тел), в котором она уже зарегистрирована; иначе null.
static func match_of(d: Doll) -> Node:
	if d == null or not is_instance_valid(d) or not d.is_inside_tree():
		return null
	for m in d.get_tree().get_nodes_in_group("match"):
		var s := m.get_script() as Script
		if s != null and s.resource_path == MATCH_SCRIPT and (m.call("dolls") as Array).has(d):
			return m
	return null


## Отложенные вызовы держат id, а не куклу: к их сроку кукла могла уже смениться (respawn) и уйти.
static func _try_swap_id(id: int, left: int) -> void:
	var d := instance_from_id(id) as Doll
	if d != null:
		_try_swap(d, left)


static func _try_swap(d: Doll, left: int) -> void:
	if d == null or not is_instance_valid(d) or d.is_queued_for_deletion():
		return
	var target := target_scene(d)
	if target == d.scene_file_path:
		return
	var m := match_of(d)
	if m == null:
		if left > 0 and d.is_inside_tree():
			var id := d.get_instance_id()
			d.get_tree().create_timer(RETRY_S).timeout.connect(func() -> void: _try_swap_id(id, left - 1))
		return
	if int(m.get("phase")) == Match.Phase.OVER:
		# итоги матча держат куклу (ResultsPanel через лямбду HUD) — пересоздать её сейчас значит оборвать их; ждём новый матч
		var iid := d.get_instance_id()
		d.get_tree().create_timer(1.0).timeout.connect(func() -> void: _try_swap_id(iid, left))
		return
	var orig := String(d.get_meta(META_ORIG, d.scene_file_path))
	d.scene_file_path = target
	var nd: Doll = m.call("respawn_doll", d)
	if nd != null and target != orig:
		nd.set_meta(META_ORIG, orig)
