## Проба матча на арене «Свалка» (headless, scenes/playground_scrap.tscn). Бой и все его проверки — tests/match_probe.gd
## (наследование, не копия): две скриптованные куклы дерутся наскоками до KO, диктор, HUD, KO-разлёт, итоги, restart().
## match_probe знает только scene=ruins|workshop|void (константа SCENES, её правит другая сессия), поэтому здесь scene_id =
## "scrap" и, пока ключа "scrap" в SCENES нет, загруженная площадка Свалки подменяет в кэше ресурсов путь SCENES["ruins"]
## (Resource.take_over_path, ссылка держится в _scrap_ps): родитель грузит SCENES.get(scene_id, SCENES["ruins"]) и получает
## Свалку. Отчёт родителя (tests/match_probe_report.json) НЕ пишется — только tests/scrap_match_probe_report.json.
##
## Проверки Свалки (checks[].id, поверх родительских):
##   scrap_arena            — загружена ScrapArena;
##   spawn_surface_N        — под маркером SpawnN (луч сверху вниз) опора — пол/настил, верх в [y−0.15, y+0.02];
##   spawn_pit_clear_N      — SpawnN дальше SPAWN_PIT_MIN_M от края пропасти по x;
##   pit_open               — над пропастью под балкой (y 1.5 → −2.9) лучу не во что упереться: провал открыт;
##   spawn_stand_P1/P2      — на отсчёте (t = STAND_CHECK_S) куклы стоят: нижняя часть у пола, торс на 0.5–2.0 м выше;
##   no_fall_through        — за весь прогон ни одна часть живой куклы вне x пропасти не ниже FALL_THROUGH_Y (пол y=0);
##   spawn23_stand_P3/P4    — после боя куклы пересоздаются на Spawn2 / Spawn3 (Match.respawn_doll с player_index 2/3),
##                            через SPAWN_SETTLE_S стоят там же (нижняя часть у опоры, ЦМ по x в 0.8 м от маркера);
##   pit_ko / pit_ko_kind / pit_ko_time / pit_match_over / pit_winner — кукла, опущенная в провал, получает KO kind "self"
##                            (сигнал body_fell арены → playground → Doll.knock_out), матч кончается, победитель — другая;
##   pit_parts_caught       — через PIT_SETTLE_S части упавшей куклы лежат на дне (y ≥ −9.6), а не падают бесконечно;
##   pit_crate_caught       — большой ящик 80 кг (Props/ShippingCrate) в шахте провала ниже пола летит вбок (SHAFT_SPEED, влево, потом
##                            вправо): через SHAFT_SETTLE_S он лежит на дне шахты (ЦМ в x пропасти, y −9.6…−7.0), а не под полом мимо дна;
##   props_in_bounds        — все пропсы и куски (Props/*, Junk/*, включая обломки Breakable) весь прогон внутри арены:
##                            |x| ≤ HALF_W + 0.5, y ∈ [−9.7, потолок + 0.5]. Дно провала (PitBottom, y −9) — внутри: пропс, столкнутый
##                            в провал, — нормальная физика; вне границ — только то, что провал не поймал (падает бесконечно);
##   info.shipping_crate    — трекер большого ящика: x0, x_min, момент ухода в провал (pit_t), толчки (скачок скорости > 0.4 м/с за
##                            тик: с кем был в контакте). 29.09 в каждом прогоне одинаково: на 1.5 с боя P1 после первой сшибки
##                            отходит полной тягой (RUSH_RETREAT_S), сносит стопку ящиков у x −0.9, усиленный ящик 20 кг летит влево
##                            ~5 м/с и бьёт большой (t 4.52–4.57, −1.4 м/с): тот съезжает к −5.8…−5.9 и нависает над провалом на
##                            0.5–0.7 м; дальше его добивают ящики стопки / куски желоба / куклы (до −6.2) — иногда до провала;
##   info.pit_drop_crate    — где большой ящик в момент, когда жертву опускают в провал;
##   ko_time                — KO основного боя не позже max_s (родитель) — в info время боя и вид KO.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/scrap_match_probe.tscn -- "max_s=120"
## Отчёт tests/scrap_match_probe_report.json, exit 0/1.
extends "res://tests/match_probe.gd"

const SCRAP_SCENE := "res://scenes/playground_scrap.tscn"
const SCRAP_REPORT := "res://tests/scrap_match_probe_report.json"
const HALF_W := 18.0
const CEIL_Y := 14.0            # потолок арены v3 (Bounds/Ceiling = верх arena_bounds)
const SPAWN_PIT_MIN_M := 3.0
const STAND_CHECK_S := 1.5
const FALL_THROUGH_Y := -0.6
const SPAWN_SETTLE_S := 2.5
const PIT_TIMEOUT_S := 8.0
const PIT_SETTLE_S := 4.0
const SHAFT_Y := -2.0           # стадия 4: низ ящика в шахте провала (верх −0.6 — под плитами пола, низ плит −0.5)
const SHAFT_SPEED := 3.0        # м/с вбок: рывок куклы 40 кг (до 9 м/с) в ящик 80 кг — общая ≈ 3 м/с
const SHAFT_SETTLE_S := 5.0     # падение 7 м при g = 2 ≈ 2.6 с + отскок

var _scrap_ps: PackedScene           # держим ссылку: иначе ресурс освободится и кэш по пути забудет подмену
var arena: Node3D
var scrap_stage := 0                 # 0 бой родителя; 1 спавны 2/3; 2 провал; 3 дно; 4 ящик в провал; 5 конец
var stage_t := 0.0
var stand_checked := false
var min_part_y := INF
var min_part_where := ""
var props_out: Array = []
var pit_victim: Doll = null
var pit_other: Doll = null
var pit_ko_t := -1.0
var pit_ko_kind := ""
var pit_over := false
var pit_winner: Doll = null
var spawn_dolls: Array = []
var spawn23_checked := false
var crate: RigidBody3D = null        # Props/ShippingCrate — трекер: кто и когда его двигал
var crate_x0 := 0.0
var crate_min_x := INF
var crate_prev_v := Vector3.ZERO
var crate_pushes: Array = []
var crate_pit_t := -1.0
var crate_shove_t := -1.0
var crate_shove_i := 0
var crate_shaft_ok := true
var crate_shaft_res: Array = []


func _ready() -> void:
	scene_id = "scrap"
	if not SCENES.has("scrap"):
		_scrap_ps = load(SCRAP_SCENE)
		_scrap_ps.take_over_path(SCENES["ruins"])
	super._ready()
	arena = pg.get("arena")
	report["info"]["scene"] = "scrap"
	match_node.ko.connect(func(_v: Doll, _a: Node, rec: Dictionary) -> void:
		if not report["info"].has("ko_kind"):
			report["info"]["ko_kind"] = str(rec.get("kind", ""))
			report["info"]["fight_time"] = snappedf(match_node.fight_time, 0.01))
	_check("scrap_arena", 1.0 if arena is ScrapArena else 0.0, 1.0, "eq", "playground_scrap loaded (arena %s)" % [arena])
	if not (arena is ScrapArena):
		_scrap_finish()
		return
	crate = arena.get_node_or_null("Props/ShippingCrate") as RigidBody3D
	if crate != null:
		crate_x0 = crate.global_position.x
		crate.contact_monitor = true     # только отчёт о контактах (кто толкал): на симуляцию не влияет
		crate.max_contacts_reported = 8


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not (arena is ScrapArena):
		return
	if t <= delta * 1.5:
		_static_checks()
	_track()
	if not stand_checked and t >= STAND_CHECK_S:
		stand_checked = true
		for d in [p1, p2]:
			_check_standing("spawn_stand_" + String(d.name), d, arena.call("spawn_points")[d.player_index])
	match scrap_stage:
		1:
			_stage_spawns(delta)
		2:
			_stage_pit(delta)
		3:
			stage_t += delta
			if stage_t >= PIT_SETTLE_S:
				var low := INF
				for part in pit_victim.parts.values():
					if is_instance_valid(part):
						low = minf(low, (part as Node3D).global_position.y)
				_check("pit_parts_caught", low, -9.6, "gte", "lowest part of the pit victim %.2f s after KO (PitBottom at −9)" % PIT_SETTLE_S)
				scrap_stage = 4
				stage_t = 0.0
		4:
			_stage_crate_shove(delta)


## Родитель закончил (бой, итоги, restart): вместо записи его отчёта — дополнительные стадии Свалки.
func _finish() -> void:
	if scrap_stage != 0:
		return
	scrap_stage = 1
	stage_t = 0.0
	# куклы на Spawn2 / Spawn3: player_index → точка спавна Match.spawn_point_for. p1/p2 родителя после restart() —
	# освобождённые экземпляры, текущие куклы берутся у Match
	spawn_dolls.clear()
	var olds: Array = match_node.dolls()
	olds.sort_custom(func(a: Doll, b: Doll) -> bool: return a.player_index < b.player_index)
	for i in olds.size():
		var d: Doll = olds[i]
		d.player_index = 2 + i
		spawn_dolls.append(match_node.respawn_doll(d))
	p1 = spawn_dolls[0]
	p2 = spawn_dolls[1]
	for d in spawn_dolls:
		(d as Doll).external_input = true


func _static_checks() -> void:
	var space := arena.get_world_3d().direct_space_state
	var pts: Array = arena.call("spawn_points")
	var pit: Rect2 = arena.get("pit_rect")
	for i in pts.size():
		var sp: Vector3 = pts[i]
		var q := PhysicsRayQueryParameters3D.create(sp + Vector3(0, 0.6, 0), sp - Vector3(0, 1.5, 0))
		var hit := space.intersect_ray(q)
		var top: float = (hit["position"] as Vector3).y if not hit.is_empty() else -INF
		var who: String = String((hit["collider"] as Node).get_parent().name) + "/" + String((hit["collider"] as Node).name) if not hit.is_empty() else "none"
		_check("spawn_surface_%d" % i, 1.0 if top >= sp.y - 0.15 and top <= sp.y + 0.02 else 0.0, 1.0, "eq",
			"surface under Spawn%d %s: y=%.3f (%s)" % [i, sp, top, who])
		var dist := maxf(pit.position.x - sp.x, sp.x - pit.end.x)
		_check("spawn_pit_clear_%d" % i, dist, SPAWN_PIT_MIN_M, "gte", "Spawn%d x=%.2f distance to pit edge (m)" % [i, sp.x])
	var cx := pit.get_center().x
	var hit_pit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cx, 1.5, 0), Vector3(cx, -2.9, 0)))
	_check("pit_open", 0.0 if hit_pit.is_empty() else 1.0, 0.0, "eq", "ray under the hanging beam into the pit hits %s" % ["nothing" if hit_pit.is_empty() else str(hit_pit["collider"])])


func _check_standing(id: String, d: Doll, sp: Vector3) -> void:
	var low := INF
	for part in d.parts.values():
		low = minf(low, (part as Node3D).global_position.y)
	var torso_y := (d.parts["Torso"] as Node3D).global_position.y
	var com := d.centre_of_mass()
	var ok := low >= sp.y - 0.25 and low <= sp.y + 0.35 and torso_y >= sp.y + 0.5 and torso_y <= sp.y + 2.0 and absf(com.x - sp.x) <= 0.8
	_check(id, 1.0 if ok else 0.0, 1.0, "eq", "spawn %s: lowest part y=%.2f, torso y=%.2f, com x=%.2f" % [sp, low, torso_y, com.x])


## Каждый кадр: нижняя точка живых кукол вне x пропасти и пропсы/куски в границах арены.
func _track() -> void:
	var pit: Rect2 = arena.get("pit_rect")
	for n in get_tree().get_nodes_in_group("dolls"):
		var d := n as Doll
		if d == null or not d.alive:
			continue
		for part in d.parts.values():
			var p := (part as Node3D).global_position
			if p.x > pit.position.x - 0.4 and p.x < pit.end.x + 0.4:
				continue
			if p.y < min_part_y:
				min_part_y = p.y
				min_part_where = "%s/%s at %s t=%.2f" % [d.name, (part as Node).name, p.snapped(Vector3.ONE * 0.01), t]
	for g in ["Props", "Junk"]:
		var holder := arena.get_node_or_null(g)
		if holder == null:
			continue
		for c in holder.get_children():
			if not (c is RigidBody3D):
				continue
			var p := (c as Node3D).global_position
			if absf(p.x) > HALF_W + 0.5 or p.y < -9.7 or p.y > CEIL_Y + 0.5:
				var tag := "%s/%s" % [g, c.name]
				if props_out.size() < 20 and not props_out.any(func(e: Dictionary) -> bool: return e["body"] == tag):
					props_out.append({"body": tag, "pos": var_to_str(p.snapped(Vector3.ONE * 0.01)), "t": snappedf(t, 0.01)})
	_track_crate()


## Большой ящик у края пропасти: минимум x, момент ухода в провал и толчки (скачок скорости > 0.4 м/с за тик — с кем в контакте).
func _track_crate() -> void:
	if crate == null or not is_instance_valid(crate):
		return
	var p := crate.global_position
	crate_min_x = minf(crate_min_x, p.x)
	if crate_pit_t < 0.0 and p.y < -0.6 and scrap_stage < 4:   # ушёл в провал сам (стадия 4 кладёт его туда нарочно)
		crate_pit_t = t
	var v := crate.linear_velocity
	if (v - crate_prev_v).length() > 0.4 and crate_pushes.size() < 16:
		var by: Array = []
		for b in crate.get_colliding_bodies():
			var d := ScrapMachine.doll_of(b)
			var tag := "%s/%s" % [d.name, b.name] if d != null else String(b.name)
			if d != null and b is RigidBody3D:
				tag += " v%s" % [(b as RigidBody3D).linear_velocity.snapped(Vector3.ONE * 0.1)]
			by.append(tag)
		crate_pushes.append({"t": snappedf(t, 0.01), "stage": scrap_stage, "x": snappedf(p.x, 0.01), "v": var_to_str(v.snapped(Vector3.ONE * 0.01)), "by": by})
	crate_prev_v = v


func _stage_spawns(delta: float) -> void:
	stage_t += delta
	if stage_t < SPAWN_SETTLE_S:
		for d in spawn_dolls:
			if is_instance_valid(d):
				(d as Doll).input_vec = Vector2.ZERO
		return
	if not spawn23_checked:
		spawn23_checked = true
		var pts: Array = arena.call("spawn_points")
		for d in spawn_dolls:
			var dd := d as Doll
			_check_standing("spawn23_stand_P%d" % (dd.player_index + 1), dd, pts[dd.player_index])
	# провал — только в фазе боя (на отсчёте площадка после KO пересоздаёт куклу, матч не кончается)
	if not match_node.combat_active():
		if stage_t > SPAWN_SETTLE_S + 10.0:
			_check("pit_fight_phase", 0.0, 1.0, "eq", "FIGHT did not start after restart (phase %d)" % match_node.phase)
			_scrap_finish()
		return
	# провал: P3 (бывшая P1) опускается ногами в пропасть под балку и тянется вниз; P4 стоит
	pit_victim = spawn_dolls[0]
	pit_other = spawn_dolls[1]
	var pit: Rect2 = arena.get("pit_rect")
	var low := INF
	for part in pit_victim.parts.values():
		low = minf(low, (part as Node3D).global_position.y)
	var com := pit_victim.centre_of_mass()
	pit_victim.global_position += Vector3(pit.get_center().x - com.x, -1.2 - low, 0.0)
	for part in pit_victim.parts.values():
		(part as RigidBody3D).linear_velocity = Vector3.ZERO
		(part as RigidBody3D).angular_velocity = Vector3.ZERO
	match_node.ko.connect(func(v: Doll, _a: Node, rec: Dictionary) -> void:
		if v == pit_victim and pit_ko_t < 0.0:
			pit_ko_t = stage_t
			pit_ko_kind = str(rec.get("kind", "")))
	match_node.match_over.connect(func(w: Doll, _r: Dictionary) -> void:
		pit_over = true
		pit_winner = w)
	report["info"]["pit_phase"] = match_node.phase
	if crate != null and is_instance_valid(crate):
		report["info"]["pit_drop_crate"] = var_to_str(crate.global_position.snapped(Vector3.ONE * 0.01))   # ящик мог нависнуть над провалом
	scrap_stage = 2
	stage_t = 0.0


func _stage_pit(delta: float) -> void:
	stage_t += delta
	if is_instance_valid(pit_victim) and pit_victim.alive:
		pit_victim.input_vec = Vector2(0.0, -1.0)
	if is_instance_valid(pit_other):
		pit_other.input_vec = Vector2.ZERO
	if (pit_ko_t >= 0.0 and stage_t >= pit_ko_t + 0.5) or stage_t >= PIT_TIMEOUT_S:
		_check("pit_ko", 1.0 if pit_ko_t >= 0.0 else 0.0, 1.0, "eq", "doll lowered into the pit got KO")
		_check("pit_ko_kind", 1.0 if pit_ko_kind == "self" else 0.0, 1.0, "eq", "KO kind '%s' == 'self'" % pit_ko_kind)
		_check("pit_ko_time", pit_ko_t if pit_ko_t >= 0.0 else PIT_TIMEOUT_S, 4.0, "lte", "seconds from drop to KO")
		_check("pit_match_over", 1.0 if pit_over else 0.0, 1.0, "eq", "match_over after the pit KO (phase %d at drop)" % int(report["info"].get("pit_phase", -1)))
		_check("pit_winner", 1.0 if pit_winner == pit_other else 0.0, 1.0, "eq", "winner is the doll that stayed up")
		scrap_stage = 3
		stage_t = 0.0


## Стадия 4: провал ловит то, что в него упало. Большой ящик 80 кг ставится стоя в шахту провала ниже пола (центр пропасти,
## низ на SHAFT_Y: верх ящика −0.6 — под плитами пола) и летит вбок на SHAFT_SPEED — сначала влево, потом вправо. Через
## SHAFT_SETTLE_S ЦМ ящика должен лежать на дне шахты (x пропасти, y −9.6…−7.0: Bounds/PitBottom верх −9, стенки PitWallL/R).
## До 29.09 стенок не было: под полом провал открыт вбок, и ящик, столкнутый в бою в провал со скоростью вбок, пролетал под
## полом мимо края PitBottom (x −11…−5) и падал бесконечно (x −12.7, y −9.7 → props_in_bounds FAIL, ~1 прогон из 3–6: ящик
## уходит в провал не в каждом бою, см. info.shipping_crate). Пропс в провале — нормальная физика, дно его и ловит. Толчок с края
## по полу так не проверить: быстрый (3.5 м/с) ловится торцом пола за провалом, медленный (1 м/с) заклинивает ящик верхним углом
## под балкой PitBeam (низ y 1.66) — сам вылет вбок под полом зависит от боя; здесь он задан прямо.
func _stage_crate_shove(delta: float) -> void:
	stage_t += delta
	if crate == null or not is_instance_valid(crate):
		_check("pit_crate_caught", 0.0, 1.0, "eq", "Props/ShippingCrate missing")
		scrap_stage = 5
		_scrap_finish()
		return
	var pit: Rect2 = arena.get("pit_rect")
	if crate_shove_t < 0.0:
		crate_shove_t = stage_t
		var dir := -1.0 if crate_shove_i == 0 else 1.0
		# стоя (поза сброшена, не только позиция) и без вращения — как телепорт бочки в scrap_machines_probe
		var anchor := PropHeft.anchor_of(crate)   # 29.09: большой ящик на якоре (PropHeft) — перенос скриптом его будит
		if anchor != null:
			anchor.wake()
		crate.global_transform = Transform3D(Basis.IDENTITY, Vector3(pit.get_center().x, SHAFT_Y, 0.0))
		crate.angular_velocity = Vector3.ZERO
		crate.linear_velocity = Vector3(dir * SHAFT_SPEED, 0.0, 0.0)
		return
	if stage_t < crate_shove_t + SHAFT_SETTLE_S:
		return
	var c := ScrapMachine.com_of(crate)
	var ok := c.x > pit.position.x and c.x < pit.end.x and c.y >= -9.6 and c.y <= -7.0
	crate_shaft_res.append("%s: COM %s" % ["left" if crate_shove_i == 0 else "right", c.snapped(Vector3.ONE * 0.01)])
	crate_shaft_ok = crate_shaft_ok and ok
	crate_shove_i += 1
	crate_shove_t = -1.0
	if crate_shove_i < 2:
		return
	_check("pit_crate_caught", 1.0 if crate_shaft_ok else 0.0, 1.0, "eq",
		"ShippingCrate thrown sideways at %.1f m/s inside the pit shaft below the floor, %.0f s later %s (shaft x %.1f…%.1f, PitBottom top y −9)" %
		[SHAFT_SPEED, SHAFT_SETTLE_S, crate_shaft_res, pit.position.x, pit.end.x])
	scrap_stage = 5
	_scrap_finish()


func _scrap_finish() -> void:
	if crate != null:
		report["info"]["shipping_crate"] = {"x0": snappedf(crate_x0, 0.01), "x_min": snappedf(crate_min_x, 0.01),
			"pos_end": var_to_str(crate.global_position.snapped(Vector3.ONE * 0.01)) if is_instance_valid(crate) else "freed",
			"pit_t": snappedf(crate_pit_t, 0.01), "pushes": crate_pushes}
	_check("no_fall_through", min_part_y, FALL_THROUGH_Y, "gte", "lowest alive doll part outside the pit x-range: %s" % min_part_where)
	_check("props_in_bounds", float(props_out.size()), 0.0, "eq", "props/junk outside arena bounds: %s" % [props_out])
	var ko_ok := false
	for c in report["checks"]:
		if c["id"] == "ko":
			ko_ok = c["ok"]
	report["info"]["godot"] = Engine.get_version_info()["string"]
	var js := JSON.stringify(report, "  ")
	print("=== SCRAP MATCH PROBE ===")
	print(js)
	var f := FileAccess.open(SCRAP_REPORT, FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("SCRAP fight_time=%.1f ko=%s ko_kind=%s hits=%d" % [float(report["info"].get("fight_time", -1.0)), ko_ok, report["info"].get("ko_kind", ""), hits])
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
