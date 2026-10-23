## Испытание (Gauntlet, docs/plan-demo/GAUNTLET.md): состояние одного забега — 10 боёв подряд против бойцов лиги (Tuning.GAUNTLET_LADDER),
## без сцены, чистая логика (её гоняет tests/gauntlet_probe.gd, раздел rules).
## Что переносится между боями (детали не чинятся):
##   lost    — имена оторванных тел и порванных связок («Link_<id>»): следующий бой кукла собирается без них (Doll.missing_parts);
##   deficit — урон по запасу бойца, который не ушёл с оторванными деталями (max_hp − hp в конце боя): на FIGHT! запас = max − deficit,
##             но не ниже Tuning.GAUNTLET_MIN_HP_FRAC;
##   wear    — износ суставов (joint_hp_max − joint_hp): на FIGHT! суставы начинают с ним.
## Карта тела (part_max ❤, parent_of по суставам, part_title — подписи) копится со всех боёв (body_map): у оторванной детали её больше нет.
## Между боями — ровно одна бесплатная починка (repair_options / apply_repair): вернуть одну оторванную ветку целиком или «Подлатать
## корпус» (−Tuning.GAUNTLET_REPAIR_POOL_FRAC запаса от урона, износ суставов снят). Поражение или ничья — конец забега.
## Рекорд — ConfigFile save_path (лучший результат «пройдено N из 10», число забегов, полных проходов).
class_name GauntletRun
extends RefCounted

const SECTION := "gauntlet"
const LINK_PREFIX := "Link_"

## Файл рекорда (пробы ставят свой).
static var save_path := "user://gauntlet.cfg"

var step := 0                         # индекс следующего боя 0..FIGHTS-1
var cleared := 0                      # побед подряд
var over := false
var won_all := false
var lost: PackedStringArray = []
var deficit := 0.0
var wear: Dictionary = {}             # имя тела → износ сустава
var part_max: Dictionary = {}         # имя тела → ❤ детали
var parent_of: Dictionary = {}        # имя тела → имя родителя по суставу
var part_title: Dictionary = {}       # имя тела → подпись для починки
var repair_used := true               # до первого боя чинить нечего
var repaired := ""                    # что починили в последнем антракте ("" — ничего)
var last: Dictionary = {}             # итог последнего боя: won, draw, reason, duration_s, hp, max_hp, lost_now
var history: Array = []               # [{step, won, reason, duration_s}]
var best_before := 0                  # рекорд до этого забега (экран итога: «новый рекорд»)
var hp_scale := 1.0                   # запас бойца на FIGHT! / Σ ❤ деталей (ДРАЙВ ×1.5); не в сейве — ставит бой (GauntletFight)


static func fights() -> int:
	return Tuning.GAUNTLET_FIGHTS


static func rival(i: int) -> Dictionary:
	var l: Array = Tuning.GAUNTLET_LADDER
	return l[clampi(i, 0, l.size() - 1)]


## Ключ арены боя i (по кругу, как Быстрый бой).
static func arena(i: int) -> String:
	var a: Array = Tuning.GAUNTLET_ARENAS
	return String(a[posmod(i, a.size())])


static func arena_title(i: int) -> String:
	return TranslationServer.translate(String((Tuning.GAUNTLET_ARENA[arena(i)] as Dictionary).get("title", arena(i))))


## Чертёж соперника боя i: копия пресета в памяти (переживёт респавн Match).
static func rival_blueprint(i: int) -> BodyBlueprint:
	return CampaignLeague.preset(String(rival(i).get("preset", "")))


static func rival_title(i: int) -> String:
	var bp := rival_blueprint(i)
	return bp.title if bp != null else String(rival(i).get("preset", "?"))


## Параметры бота уровня level: 1..4 — Tuning.RIVAL_LEVELS, 5 — Tuning.GAUNTLET_LEVEL5.
static func level_params(level: int) -> Dictionary:
	if level >= 5:
		return Tuning.GAUNTLET_LEVEL5
	return Tuning.RIVAL_LEVELS.get(clampi(level, 1, 4), Tuning.RIVAL_LEVELS[1])


## Запас соперника боя i: ❤ деталей его чертежа × множитель ступени.
static func rival_max_hp(i: int) -> float:
	var bp := rival_blueprint(i)
	return roundf(float(bp.parts_hp_total() if bp != null else Tuning.MAX_HP) * float(rival(i).get("hp", 1.0)))


## «Сила» ступени без тела: тяга × запас × бот (быстрее реакция — сильнее). Строго растёт по лестнице (проба ladder).
static func power(i: int) -> float:
	var r := rival(i)
	var p := level_params(int(r.get("level", 1)))
	return float(r.get("thrust", 1.0)) * float(r.get("hp", 1.0)) * (0.5 / maxf(float(p.get("reaction_s", 0.3)), 0.05))


# ------------------------------------------------------------------ бой

## Карта тела куклы игрока на FIGHT!: ❤ деталей, родители по суставам, подписи. Копится (оторванных потом нет в кукле).
func body_map(d: Doll) -> void:
	for n in d.part_hp:
		part_max[String(n)] = float(d.part_hp[n])
	for j in d.joints.values():
		var jj := j as Generic6DOFJoint3D
		if not is_instance_valid(jj):
			continue
		var a := jj.get_node_or_null(jj.node_a)
		var b := jj.get_node_or_null(jj.node_b)
		if a != null and b != null:
			parent_of[String(b.name)] = String(a.name)
	if is_instance_valid(d) and d is ModularDoll:
		var md := d as ModularDoll
		var counts := {}
		var titles := {}
		for uid in md.uid_body:
			var body := String(md.uid_body[uid])
			if titles.has(body) or md.blueprint == null:
				continue
			var nd := md.blueprint.find_node(String(uid))
			var def := BodyBlueprint.part_def(String(nd.get("part", "")))
			if def == null or md.blueprint.is_fixed(String(uid)):
				continue
			titles[body] = def.title
			counts[def.title] = int(counts.get(def.title, 0)) + 1
		for body in titles:
			var t := String(titles[body])
			if int(counts[t]) > 1:
				if body.ends_with("_L"):
					t += TranslationServer.translate(" (слева)")
				elif body.ends_with("_R"):
					t += TranslationServer.translate(" (справа)")
				else:
					t += " · " + body.get_slice("_", body.get_slice_count("_") - 1)
			part_title[body] = t


## Состояние куклы игрока после боя: что оторвано, урон по запасу, износ суставов.
static func snapshot(d: Doll) -> Dictionary:
	var w := {}
	for n in d.joint_hp:
		var m := float(d.joint_hp_max.get(n, 0.0))
		var left := float(d.joint_hp[n])
		if d.parts.has(n) and m - left > 0.01:
			w[String(n)] = m - left
	return {"lost": d.lost_part_names(), "deficit": maxf(d.max_hp - d.hp, 0.0) if d.alive else d.max_hp, "wear": w,
		"hp": d.hp, "max_hp": d.max_hp}


## Запас бойца на FIGHT! при полном max_hp (❤ оставшихся деталей).
func start_hp(max_hp: float) -> float:
	return clampf(maxf(max_hp - deficit, max_hp * Tuning.GAUNTLET_MIN_HP_FRAC), 1.0, maxf(max_hp, 1.0))


## Итог боя: победа — следующая ступень и одна починка; поражение / ничья — конец забега, рекорд на диск.
func record_result(won: bool, info: Dictionary, snap: Dictionary) -> void:
	if over:
		return
	var draw := bool(info.get("draw", false))
	won = won and not draw
	var before := lost.duplicate()
	if won:
		lost = PackedStringArray(snap.get("lost", lost))
		deficit = float(snap.get("deficit", deficit))
		wear = (snap.get("wear", {}) as Dictionary).duplicate()
	var now: PackedStringArray = []
	for n in PackedStringArray(snap.get("lost", [])):
		if not before.has(n):
			now.append(n)
	last = {"won": won, "draw": draw, "reason": String(info.get("reason", "")), "duration_s": float(info.get("duration_s", 0.0)),
		"hp": float(snap.get("hp", 0.0)), "max_hp": float(snap.get("max_hp", 0.0)), "lost_now": now, "step": step}
	history.append({"step": step, "won": won, "reason": last["reason"], "duration_s": last["duration_s"]})
	repaired = ""
	if won:
		cleared += 1
		step += 1
		if step >= fights():
			over = true
			won_all = true
		else:
			repair_used = false
	else:
		over = true
	if over:
		repair_used = true
		save_record()


# ------------------------------------------------------------------ починка

## Запас на старт боя в единицах боя (как max_hp куклы на FIGHT!): Σ ❤ оставшихся деталей × hp_scale. Экран антракта
## пишет его, а не голую Σ ❤: иначе при ДРАЙВЕ «осталось 130 из 150» в бою и «запас 80 из 100» строкой ниже (VISUAL_PASS_2310).
func fight_pool() -> float:
	return pool_max() * hp_scale


## Запас бойца из оставшихся деталей (как Match._parts_hp без ДРАЙВА).
func pool_max() -> float:
	var t := 0.0
	for n in part_max:
		if not lost.has(String(n)):
			t += float(part_max[n])
	return t


## Корни оторванного: оторванное, чей родитель на месте (у связки родителя нет — сама корень).
func lost_roots() -> PackedStringArray:
	var out: PackedStringArray = []
	for n in lost:
		var p := String(parent_of.get(n, ""))
		if n.begins_with(LINK_PREFIX) or p == "" or not lost.has(p):
			out.append(n)
	return out


## Ветка root среди оторванного: root и всё, что висело на нём.
func branch_of(root: String) -> PackedStringArray:
	var out: PackedStringArray = [root]
	for n in lost:
		if n == root:
			continue
		var p := String(parent_of.get(n, ""))
		var guard := 0
		while p != "" and p != root and guard < 64:
			p = String(parent_of.get(p, ""))
			guard += 1
		if p == root:
			out.append(n)
	return out


func branch_hp(root: String) -> float:
	var t := 0.0
	for n in branch_of(root):
		t += float(part_max.get(n, 0.0))
	return t


func title_of(n: String) -> String:
	if n.begins_with(LINK_PREFIX):
		return TranslationServer.translate("Связка")
	return String(part_title.get(n, n.get_slice("_", 0)))


## Варианты починки: [{kind: "branch", part, title, hp, parts} … (до GAUNTLET_REPAIR_OPTIONS, крупные ❤ сначала), {kind: "patch", hp}].
## «Подлатать корпус» есть всегда (даже если урона нет — тогда +0).
func repair_options() -> Array:
	var out: Array = []
	for r in lost_roots():
		out.append({"kind": "branch", "part": r, "title": title_of(r), "hp": branch_hp(r), "parts": branch_of(r).size()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["hp"]) > float(b["hp"]) or (is_equal_approx(float(a["hp"]), float(b["hp"])) and String(a["part"]) < String(b["part"])))
	out = out.slice(0, Tuning.GAUNTLET_REPAIR_OPTIONS)
	out.append({"kind": "patch", "part": "", "title": TranslationServer.translate("Подлатать корпус"),
		"hp": minf(deficit, pool_max() * Tuning.GAUNTLET_REPAIR_POOL_FRAC), "wear": wear.size()})
	return out


## Починка i из repair_options(). Ровно одна за антракт: вторая (и в конце забега) — false.
func apply_repair(i: int) -> bool:
	if repair_used or over:
		return false
	var opts := repair_options()
	if i < 0 or i >= opts.size():
		return false
	var o: Dictionary = opts[i]
	if String(o["kind"]) == "branch":
		for n in branch_of(String(o["part"])):
			var k := lost.find(n)
			if k >= 0:
				lost.remove_at(k)
			wear.erase(n)
	else:
		deficit = maxf(deficit - pool_max() * Tuning.GAUNTLET_REPAIR_POOL_FRAC, 0.0)
		wear.clear()
	repaired = String(o["title"])
	repair_used = true
	return true


# ------------------------------------------------------------------ рекорд

## Рекорд с диска: {best (пройдено боёв), runs, wins (полных проходов)}.
static func load_record() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(save_path) != OK:
		return {"best": 0, "runs": 0, "wins": 0}
	return {"best": int(cf.get_value(SECTION, "best", 0)), "runs": int(cf.get_value(SECTION, "runs", 0)),
		"wins": int(cf.get_value(SECTION, "wins", 0))}


func save_record() -> bool:
	var r := load_record()
	best_before = int(r["best"])
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "best", maxi(int(r["best"]), cleared))
	cf.set_value(SECTION, "runs", int(r["runs"]) + 1)
	cf.set_value(SECTION, "wins", int(r["wins"]) + (1 if won_all else 0))
	return cf.save(save_path) == OK


static func erase_record() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
