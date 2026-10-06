## Проба матча целиком (план 06, headless): настоящая площадка (res://scenes/playground.tscn — Руины, playground_workshop.tscn
## или playground_void.tscn — пустое поле Void)
## с Match и HUD; две скриптованные куклы (external_input) дерутся наскоками, как в combat_gate (разбег → отход → разбег, с тягой
## по вертикали к сопернику; с разбега ≥ 2 м — рывок, как Shift, раз в DASH_COOLDOWN_S), до KO или max_s секунд боя. P2 в начале ставится на 3.8 м правее P1 (в Руинах — на каменный мост).
## Упёрлась на разбеге (BLOCKED_S стоит при полной тяге) — отход и новый разбег, как после сближения. Заклинило (STUCK_S без
## ударов): между куклами препятствие — идут навстречу по пути на сетке проходимости (nav, до NAV_S), иначе или если путь не свёл —
## прыжок UNSTICK_S (врозь / вверх и к сопернику).
## Проверки (checks[].id):
##   announce_countdown/fight — отсчёт «3» и FIGHT! объявлены; hud_panels — панели P1/P2 созданы; hud_timer — таймер HUD обновляется
##   и совпадает с Match.time_left_s(); hits — Match.hit ≥ 1; announce_hit — HEAD/BODY/DOUBLE BLOW! ≥ 1; hud_hp_synced — hp панели
##   HUD == hp куклы после каждого удара; fx — ImpactFx появлялся под Match;
##   ko — KO до max_s; ko_broken — у жертвы суставов 0, частей 14, разлёт ≥ 1.5 м через 1 с; ko_card — карточка KO показана;
##   announce_ko; match_over с winner (живой) или ничья при KO обоих в одном тике (winner null, draw), places 2, medals.Winner == winner;
##   results_visible — панель итогов показана (реальное время);
##   time_scale_restored — Engine.time_scale вернулся к 1; restart — после restart(): фаза COUNTDOWN, итоги скрыты, куклы новые,
##   живые, hp 100, панели HUD сброшены.
##   pit_walls (только Руины) — шахты ям у краёв закрыты стенками под краем земли (Bounds/PitWallL/R): 6 лучей из шахт внутрь
##   арены на y −0.5…−2.5 упираются в стенку на |x| = 14. Без стенок кукла уходила из ямы под плиты земли и жила там до конца
##   боя — соперник сверху её не доставал, KO не было (04.10: 2 прогона из 21 красные, hits = 6 за 120 с).
##   sd=1 — режим Sudden Death: time_limit_s = 3, куклы стоят; проверки sd_phase, sd_hammer (площадка уронила молот на шаге
##   SUDDEN_DEATH_HEAVY_WEAPON_STEP), sd_bridges (RopeBridge.break_apart на шаге SUDDEN_DEATH_BREAK_PLATFORMS_STEP; только Руины),
##   sd_stability (Doll.stability_mult по шагу), sd_no_damage (стоящие куклы без урона), hud_sd_label (надпись SUDDEN DEATH в HUD).
##   HIT_FX (29.09): fx_directors — Match создал HitFxDirector и SfxDirector; hitfx_env_kind — ударов kind environment с уровнем 0;
##   info.hitfx — гистограмма уровней Match.hit_fx, crits[] (t, tier, score, damage), env_slam, fight_s_per_crit.
## Запуск: godot --headless --path . --fixed-fps 60 res://tests/match_probe.tscn -- "scene=ruins,max_s=120" (scene=ruins|workshop|void|scrap)
##   p1=x:y, p2=x:y — исходные точки кукол вместо штатных (воспроизвести ловушку геометрии: p1=-10:2.7,p2=-9.5:0.5 — P1 на левом
##   помосте Руин, P2 под ним).
##   trace=1 — разбор «нет KO»: раз в секунду боя строка TRACE (центр масс, скорость торса, ввод, hp, Заряд обеих кукол) и строка
##   TRACE unstick / TRACE nav на каждое расклинивание; без него при таймауте в отчёте всё равно есть info.timeout.pos, info.unsticks
##   (прыжки), info.navs (обходы по сетке) и info.blocked_retreats (отходы упёршейся куклы).
##   perf=1 (perf-pass, docs/plan-demo/PERF_PASS.md) — детектор рывков: реальные часы между кадрами (в headless --fixed-fps 60 это цена кадра
##   на CPU), узлы, добавленные в кадр (ADDED{класс:имя×N}), события удара рядом; проверки perf_frame_p99_ms / perf_frame_max_ms /
##   perf_nodes_per_frame (limits p99_ms= max_ms= max_nodes=), info.perf; spikes=1 — то же, но только печать рывков > spike_ms (окно).
##   joints=1 — пробный режим «Прочность суставов» (JointBreak, JOINT_BREAK.md): info.joints_broken — что и когда отлетело до KO.
##   parts=1 — пробный режим «Запас из деталей» (PartHp, WORKSHOP_V4.md): info.parts — запас на старте боя (max_hp из ❤ деталей),
##   что и когда отлетело (part_detached: деталь, t, hp до и после, потерянные ❤), остаток.
##   d1=<id> / d2=<id> — вместо обычной куклы P1 / P2 пресет scenes/body/presets/<id>.tscn (калибровка сборок друг против друга;
##   проверки «частей 14» у KO для сборок с другим числом тел не про них).
##   lk=<вид> — связки (KitLink) у сборок d1 / d2: кисть ↔ бедро своей стороны с обеих сторон (rod | bar | spring | rope | piston);
##   info.links — сколько связок порвалось за бой.
##   th=<шарнир> — правая кисть (uid 9, тяга бота) сборок d1 / d2 висит на связке (on_rope | on_bar | on_spring | on_piston), длина по умолчанию.
##   retreat=<с> — отход наскока вместо RUSH_RETREAT_S (retreat=1.0 в Void — клинч голова-о-голову, двойной KO → ничья).
## Отчёт tests/match_probe_report.json (или out=res://…), exit 0/1.
extends Node3D

const SCENES := {"ruins": "res://scenes/playground.tscn", "workshop": "res://scenes/playground_workshop.tscn", "void": "res://scenes/playground_void.tscn",
	"scrap": "res://scenes/playground_scrap.tscn"}
const P2_OFFSET := Vector3(3.8, 0.0, 0.0)
const RUSH_NEAR := 1.3
const RUSH_RETREAT_S := 1.2             # отход полной тягой: разбег 2–3 м до следующего наскока. v7: 1.0 → 1.2 — с мягкими конечностями
                                        # и расслаблением на удар (FEEL_TARGET §9.4) при 1.0 в Void бой кончался клинчем голова-о-голову,
                                        # KO обоих в одном тике (42.5 с) → Match.winner мёртв, match_winner = 0 (3 прогона одинаково);
                                        # 1.2 и 0.9 — KO одного на всех трёх площадках. 29.09: двойной KO — ничья (Match.build_results),
                                        # match_winner её принимает; 1.2 оставлен — проба проверяет обычный KO
const DASH_FROM_M := 2.0                 # ускорение (Shift за Заряд), если до соперника дальше; legacy=1 — старый рывок с кулдауном DASH_COOLDOWN_S
const BOOST_START_CHARGE := 40.0         # как у ботов EnemyBrain.DASH_START_CHARGE: ниже ускорение не начинают, ниже BOOST_KEEP_CHARGE — отпускают
const BOOST_KEEP_CHARGE := 5.0
const STUCK_S := 6.0                 # без ударов столько секунд — куклы заклинило геометрией (полка, станок): прыжок врозь
const UNSTICK_S := 1.2
# Обход препятствия (nav): заклинило (нет ударов STUCK_S), а между куклами геометрия — помост, мост, плита, куча ящиков. Прыжки
# вслепую тут не сводят: в Руинах помост + верёвочный мост + каменный мост — сплошной настил 15 м, кукла сверху и кукла снизу
# «сближались» через него по 20 с и больше (04.10: бои 91–117 с при лимите 120). Куклы идут навстречу по пути на сетке проходимости.
const NAV_CELL := 0.5                # м: клетка сетки в плоскости боя (z = 0), границы — arena.bounds()
const NAV_CLEAR_R := 0.45            # м: полуширина свободного прохода (торс куклы); клетка занята, если коробка задела препятствие
const NAV_HALF_Z := 0.24             # м: полутолщина слоя кукол (голова r = 0.24)
const NAV_S := 8.0                   # с: дольше по пути не идём — следующая попытка обычным прыжком
const NAV_REPATH_S := 0.25           # с: путь пересчитывается от текущих положений кукол
const NAV_LOOKAHEAD := 6             # клеток: цель — самая дальняя клетка пути впереди, до которой сетка свободна по прямой
const NAV_MEET_M := 2.5              # м: куклы видят друг друга и ближе этого — пришли, дальше обычный наскок
const NAV_HEAVY_KG := 8.0            # динамическое тело от этой массы — препятствие (тележка, козлы, клетка); ящики/бочки и доски моста — всегда
const NAV_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const BLOCKED_SPEED := 0.35          # м/с (как EnemyBrain.STUCK_SPEED): полная тяга к сопернику, а торс стоит
const BLOCKED_S := 0.8               # с: столько стоит на разбеге — упёрся (ящики между куклами, торец плиты): отход и новый разбег
const RUINS_PIT_X := 15.0            # Руины (tools/build_arena_ruins.gd): середина шахты ямы — земля до |x| = GROUND_HALF_W 14, стена на 16
const RUINS_PIT_WALL_X := 14.0
const RUINS_PIT_RAY_Y := [-0.5, -1.5, -2.5]   # между низом плит земли (y 0) и верхом зоны KO (y −3)
const RESULTS_WAIT_REAL_MS := 6000

var scene_id := "ruins"
var out_path := "res://tests/match_probe_report.json"
var hitfx_tiers: Dictionary = {}     # HIT_FX: tier -> число ударов (Match.hit_fx, только бой до restart)
var hitfx_crits: Array = []
var hitfx_env_kind := 0
var joints_left: Dictionary = {}     # joints=1: имя куклы -> {деталь: доля запаса сустава на момент KO}
var joints_broken: Array = []        # joints=1 (JointBreak): отлетевшие детали боя до KO — {doll, part, t, hp}
var parts_lost: Array = []           # parts=1 (PartHp): отлетевшие детали боя до KO — {doll, part, t, hp, max_hp, lost}
var parts_start: Dictionary = {}     # parts=1: имя куклы -> max_hp на FIGHT!
var doll_presets: Dictionary = {}    # d1= / d2=: "P1" / "P2" -> id пресета scenes/body/presets/<id>.tscn
var link_type := ""                  # lk=: вид связок у сборок d1 / d2
var tether_type := ""                # th=: правая кисть сборок d1 / d2 на связке
var env_slams := 0
var max_s := 120.0
var sd_mode := false
var rush_retreat_s := RUSH_RETREAT_S
var legacy_dash := false             # legacy=1: старый рывок без Заряда (dash_until + кулдаун 10 с) — сравнение с экономикой Заряда
var rush_boost: Dictionary = {}      # Doll -> true, пока бот держит ускорение
const SD_TIME_LIMIT_S := 3.0
const SD_SETTLE_S := 2.0             # после шага обрыва мостов ждём столько: доски должны упасть
var plank_y_at_break: Dictionary = {}   # RopeBridge -> Array[float] высоты досок в момент break_apart
var pg: Node3D
var p1: Doll
var p2: Doll
var match_node: Match
var hud: Hud
var t := 0.0
var stage := 0                       # 0 бой, 1 после KO (ждём итоги), 2 после restart, 3 конец
var events: Array = []
var hits := 0
var hit_list: Array = []
var hp_synced := true
var timer_mismatches := 0          # тик перехода FIGHT→SUDDEN_DEATH меняет смысл time_left_s() — допускаем единичные
var timer_updates := 0
var last_timer_text := ""
var ko_fired := false
var ko_t := -1.0
var ko_victim: Doll = null
var ko_card_seen := false
var over_fired := false
var over_winner: Doll = null
var over_results: Dictionary = {}
var results_seen := false
var results_wait_ms := -1
var restart_t := -1.0
var old_ids: Array = []
var min_time_scale := 1.0
var fx_seen := false
var rush_retreat: Dictionary = {}
var last_hit_t := 0.0
var unstick_until := -1.0
var unstick_n := 0                     # номер попытки расклинивания (чередование врозь / через препятствие)
var blocked_since: Dictionary = {}     # Doll -> с какого времени стоит на разбеге
var blocked_n := 0                     # сколько раз упёршаяся кукла уходила на новый разбег
var nav_until := -1.0                  # до этого времени куклы идут по пути навстречу друг другу
var nav_n := 0                         # сколько раз заклинивание лечилось обходом
var nav_tried := false                 # прошлый обход не свёл кукол (вышло время) — следующая попытка прыжком
var nav_met_t := -1.0                  # когда обход свёл кукол: отсюда снова ждём удара STUCK_S
var _nav_free := PackedByteArray()     # 1 — клетка свободна
var _nav_w := 0
var _nav_h := 0
var _nav_org := Vector2.ZERO
var _nav_path: Array[Vector2i] = []    # клетки от P1 к P2
var _nav_repath_at := -1.0
var fight_seen := false               # фаза FIGHT наступала (до неё Match.phase == OVER — начальное значение)
var trace := false                    # trace=1: раз в секунду боя — позиции/скорости/ввод кукол, плюс каждое срабатывание расклинивания
var _trace_next := 0.0
var start_pos: Dictionary = {}        # "p1" / "p2" -> Vector3 из аргументов p1=x:y, p2=x:y
var pit_rays := -1                    # Руины: сколько лучей из шахт ям упёрлось в стенку под краем земли (−1 — ещё не мерили)
var report := {"ok": true, "checks": [], "info": {}}
# --- perf=1 / spikes=1: рывки кадра по реальным часам и узлы, добавленные в кадр ---
var perf := false
var pipes := false           # pipes=1 (окно): компиляции пайплайнов Godot по кадрам (Performance.PIPELINE_COMPILATIONS_*) и события рядом
var _pipe_last: Array = [0, 0, 0, 0, 0]
var _pipe_fight: Array = [0, 0, 0, 0, 0]   # сумма за активный бой
var _pipe_lines: Array = []
var spikes := false
var spikes_all := false      # all=1: рывки логируются и вне активного боя (отсчёт, KO, итоги, рестарт)
var spike_ms := 28.0
var limit_p99_ms := 60.0
var limit_max_ms := 500.0
var limit_nodes := 250
var _last_us := 0
var _frame_ms: Array = []
var _ctx: Array = []   # [{us, text}]
var _spike_lines: Array = []
var _added: Dictionary = {}
var _added_n := 0
var _max_added := 0
var _max_added_top := ""


func _ctx_add(txt: String) -> void:
	_ctx.append({"us": Time.get_ticks_usec(), "text": txt})
	if _ctx.size() > 60:
		_ctx.pop_front()


func _on_node_added(n: Node) -> void:
	_added_n += 1
	var nm := String(n.name)
	var i := nm.length()
	while i > 0 and (nm[i - 1] >= "0" and nm[i - 1] <= "9" or nm[i - 1] == "@"):
		i -= 1
	var key := "%s:%s" % [n.get_class(), nm.substr(0, i)]
	_added[key] = int(_added.get(key, 0)) + 1


func _top_added() -> String:
	var ks: Array = _added.keys()
	ks.sort_custom(func(a: Variant, b: Variant) -> bool: return int(_added[a]) > int(_added[b]))
	var parts: PackedStringArray = []
	for k in ks.slice(0, 6):
		parts.append("%s×%d" % [k, int(_added[k])])
	return ", ".join(parts)


func _pipe_tick(in_fight: bool) -> void:
	var cur: Array = []
	for c in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		cur.append(int(Performance.get_monitor(c)))
	var d: Array = []
	var any := false
	for i in range(5):
		d.append(int(cur[i]) - int(_pipe_last[i]))
		any = any or int(d[i]) > 0
	_pipe_last = cur
	if not any or t < 0.5:
		return
	if in_fight:
		for i in range(5):
			_pipe_fight[i] = int(_pipe_fight[i]) + int(d[i])
	var now := Time.get_ticks_usec()
	var near: PackedStringArray = []
	for c in _ctx:
		if now - int(c["us"]) < 600000:
			near.append("%s(-%dms)" % [c["text"], (now - int(c["us"])) / 1000])
	_pipe_lines.append("PIPE t=%.2f fight=%.2f %s canvas/mesh/surface/draw/spec=%s%s" % [t, match_node.fight_time, "БОЙ" if in_fight else "вне боя", d, (" [" + ", ".join(near) + "]") if not near.is_empty() else ""])


func _process(_d: float) -> void:
	if pipes:
		_pipe_tick(stage == 0 and fight_seen and not ko_fired and match_node.combat_active())
	if not (perf or spikes):
		return
	var now := Time.get_ticks_usec()
	if _last_us == 0:
		_last_us = now
		return
	var ms := float(now - _last_us) / 1000.0
	_last_us = now
	# мерим только активный бой до KO: отсчёт, рестарт кукол и панель итогов — штатные всплески (одноразовые построения)
	var in_fight := stage == 0 and fight_seen and not ko_fired and match_node.combat_active()
	if in_fight and _added_n > _max_added:
		_max_added = _added_n
		_max_added_top = _top_added()
	var top := _top_added() if (ms > spike_ms and not _added.is_empty()) else ""
	_added.clear()
	_added_n = 0
	if not in_fight or t < 1.0:   # прогрев: компиляция пайплайнов, загрузка — отдельная история
		if spikes_all and t >= 1.0 and ms > spike_ms:
			var near2: PackedStringArray = []
			for c in _ctx:
				if now - int(c["us"]) < 400000:
					near2.append("%s(-%dms)" % [c["text"], (now - int(c["us"])) / 1000])
			_spike_lines.append("SPIKE(вне боя) t=%.2f dt=%.1f ms [%s%s]" % [t, ms, ", ".join(near2), (" ADDED{" + top + "}") if top != "" else ""])
		return
	_frame_ms.append(ms)
	if ms > spike_ms:
		var near: PackedStringArray = []
		for c in _ctx:
			if now - int(c["us"]) < 400000:
				near.append("%s(-%dms)" % [c["text"], (now - int(c["us"])) / 1000])
		_spike_lines.append("SPIKE t=%.2f fight=%.2f dt=%.1f ms [%s%s]" % [t, match_node.fight_time, ms, ", ".join(near), (" ADDED{" + top + "}") if top != "" else ""])


func _perf_summary() -> void:
	if pipes:
		print("PIPELINES scene=%s в бою (canvas/mesh/surface/draw/spec) = %s, событий %d" % [scene_id, _pipe_fight, _pipe_lines.size()])
		for l in _pipe_lines:
			print("  ", l)
		report["info"]["pipelines_in_fight"] = _pipe_fight
	if _frame_ms.is_empty():
		return
	var a: Array = _frame_ms.duplicate()
	a.sort()
	var sum := 0.0
	for v in a:
		sum += float(v)
	var over := 0
	for v in a:
		if float(v) > spike_ms:
			over += 1
	var p99: float = a[int(a.size() * 0.99)]
	var mx: float = a[a.size() - 1]
	report["info"]["perf"] = {"frames": a.size(), "avg_ms": snappedf(sum / a.size(), 0.01), "p50_ms": snappedf(a[a.size() / 2], 0.01),
		"p95_ms": snappedf(a[int(a.size() * 0.95)], 0.01), "p99_ms": snappedf(p99, 0.01), "max_ms": snappedf(mx, 0.01), "over_ms": spike_ms, "over_n": over,
		"max_nodes_added_frame": _max_added, "max_nodes_added_top": _max_added_top, "spikes": _spike_lines.slice(0, 12)}
	print("PERF scene=%s frames=%d avg=%.1f p50=%.1f p95=%.1f p99=%.1f max=%.1f over_%dms=%d max_nodes_frame=%d {%s}" % [scene_id, a.size(), sum / a.size(),
		a[a.size() / 2], a[int(a.size() * 0.95)], p99, mx, int(spike_ms), over, _max_added, _max_added_top])
	for l in _spike_lines:
		print("  ", l)
	if perf:
		_check("perf_frame_p99_ms", p99, limit_p99_ms, "lte", "p99 времени кадра (реальные часы)")
		_check("perf_frame_max_ms", mx, limit_max_ms, "lte", "худший кадр")
		_check("perf_nodes_per_frame", float(_max_added), float(limit_nodes), "lte", "узлов, добавленных в один кадр: %s" % _max_added_top)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			match p[0]:
				"scene": scene_id = p[1]
				"max_s": max_s = float(p[1])
				"sd": sd_mode = p[1] != "0"
				"out": out_path = p[1]
				"retreat": rush_retreat_s = float(p[1])
				"legacy": legacy_dash = p[1] != "0"
				"trace": trace = p[1] != "0"
				"p1", "p2":   # p1=x:y / p2=x:y — исходная точка куклы (разбор ловушек геометрии: одна на помосте, другая под ним)
					var xy := p[1].split(":")
					if xy.size() == 2:
						start_pos[p[0]] = Vector3(float(xy[0]), float(xy[1]), 0.0)
				"variant": ControlFeel.set_variant(p[1])   # вариант управления (ControlFeel): боты и игроки ведут куклу так же
				"tempo": ControlFeel.set_tempo(p[1])       # темп: now | brisk | action | ram
				"perf": perf = p[1] != "0"
				"pipes": pipes = p[1] != "0"
				"spikes": spikes = p[1] != "0"
				"all": spikes_all = p[1] != "0"
				"spike_ms": spike_ms = float(p[1])
				"p99_ms": limit_p99_ms = float(p[1])
				"max_ms": limit_max_ms = float(p[1])
				"max_nodes": limit_nodes = int(p[1])
				"joints": JointBreak.set_on(p[1] != "0")   # пробный режим «Прочность суставов»: info.joints_broken — кто что потерял
				"parts": PartHp.set_on(p[1] != "0")        # пробный режим «Запас из деталей»: info.parts
				"d1": doll_presets["P1"] = p[1]
				"d2": doll_presets["P2"] = p[1]
				"lk": link_type = p[1]
				"th": tether_type = p[1]
	pg = load(SCENES.get(scene_id, SCENES["ruins"])).instantiate()
	for pn in doll_presets:   # пресет вместо обычной куклы — до add_child: _ready площадки и Match видят уже сборку
		_swap_doll(pg, String(pn), "res://scenes/body/presets/%s.tscn" % doll_presets[pn])
	add_child(pg)
	p1 = pg.get_node("P1")
	p2 = pg.get_node("P2")
	match_node = pg.get_node("Match")
	hud = pg.get_node("HUD")
	p1.external_input = true
	p2.external_input = true
	if sd_mode:
		match_node.time_limit_s = SD_TIME_LIMIT_S
		match_node.hard_timeout_s = SD_TIME_LIMIT_S + 60.0
		if pg.arena.has_method("rope_bridges"):
			for rb in pg.arena.call("rope_bridges"):
				rb.connect("broken", func() -> void:
					var ys: Array = []
					for pl in rb.call("planks"):
						ys.append((pl as Node3D).global_position.y)
					plank_y_at_break[rb] = ys)
	else:
		p2.position = p1.position + P2_OFFSET
		if start_pos.has("p1"):
			p1.position = start_pos["p1"]
		if start_pos.has("p2"):
			p2.position = start_pos["p2"]
	if perf or spikes:
		get_tree().node_added.connect(_on_node_added)
	match_node.announce.connect(func(text: String, _c: Color, kind: String) -> void:
		_ctx_add("announce:" + kind)
		events.append({"announce": text, "kind": kind, "t": snappedf(t, 0.01)}))
	match_node.phase_changed.connect(func(p: int) -> void:
		_ctx_add("phase:%d" % p)
		if p == Match.Phase.FIGHT:
			fight_seen = true
			last_hit_t = t
			if parts_start.is_empty():
				for pd in [p1, p2]:
					parts_start[String(pd.name)] = (pd as Doll).max_hp
		events.append({"phase": p, "t": snappedf(t, 0.01)}))
	match_node.hit.connect(func(victim: Doll, attacker: Node, damage: float, kind: String, _pos: Vector3) -> void:
		hits += 1
		last_hit_t = t
		if hit_list.size() < 40:
			hit_list.append({"victim": victim.name, "attacker": attacker.name if attacker != null else "", "damage": snappedf(damage, 0.01), "kind": kind, "t": snappedf(t, 0.01)})
		var panel: PlayerPanel = hud.panels.get(victim.player_index, null)
		if panel == null or not is_equal_approx(panel.hp_bar.hp, victim.hp):
			hp_synced = false)
	match_node.ko.connect(func(victim: Doll, _a: Node, _r: Dictionary) -> void:
		_ctx_add("KO")
		ko_fired = true
		ko_t = t
		ko_victim = victim
		ko_card_seen = ko_card_seen or hud.ko_card.visible
		if JointBreak.on and joints_left.is_empty():   # остаток запаса суставов обоих на момент KO, в долях (подбор чисел режима)
			for jd in [p1, p2]:
				var left := {}
				for n in (jd as Doll).joint_hp_max:
					left[n] = snappedf(maxf(float((jd as Doll).joint_hp.get(n, 0.0)), 0.0) / float((jd as Doll).joint_hp_max[n]), 0.01)   # 0 — отлетела
				joints_left[String(jd.name)] = left)
	match_node.match_over.connect(func(winner: Doll, results: Dictionary) -> void:
		_ctx_add("match_over")
		over_fired = true
		over_winner = winner
		over_results = results
		results_wait_ms = Time.get_ticks_msec())
	if match_node.has_signal("hit_fx"):
		match_node.connect("hit_fx", func(ctx: Dictionary) -> void:
			if stage != 0:
				return
			var tier := String(ctx.get("tier", ""))
			_ctx_add("hit:%s/%s" % [tier, String(ctx.get("kind", ""))])
			hitfx_tiers[tier] = int(hitfx_tiers.get(tier, 0)) + 1
			if String(ctx.get("kind", "")) == "environment":
				hitfx_env_kind += 1
			if tier == "crit" or tier == "ko_crit":
				hitfx_crits.append({"t": snappedf(float(ctx.get("fight_time", 0.0)), 0.01), "tier": tier, "score": snappedf(float(ctx.get("score", 0.0)), 0.1),
					"damage": snappedf(float(ctx.get("damage", 0.0)), 0.1), "kind": ctx.get("kind", ""), "part": ctx.get("part", "")}))
	if match_node.has_signal("env_slam"):
		match_node.connect("env_slam", func(_ctx: Dictionary) -> void:
			if stage == 0:
				env_slams += 1)
	for jd in [p1, p2]:
		(jd as Doll).joint_broken.connect(func(part: String, _by: Node, _pos: Vector3) -> void:
			if stage == 0:
				joints_broken.append({"doll": String(jd.name), "part": part, "t": snappedf(match_node.fight_time, 0.01), "hp": snappedf((jd as Doll).hp, 0.1)}))
	for jd in [p1, p2]:
		(jd as Doll).part_detached.connect(func(part: String, _by: Node) -> void:
			if stage == 0 and fight_seen:
				parts_lost.append({"doll": String(jd.name), "part": part, "t": snappedf(match_node.fight_time, 0.01), "hp": snappedf((jd as Doll).hp, 0.1)}))
		(jd as Doll).parts_hp_changed.connect(func(delta: float, _part: String) -> void:
			if stage == 0 and fight_seen and not parts_lost.is_empty() and delta < 0.0:
				var last: Dictionary = parts_lost[parts_lost.size() - 1]
				last["lost"] = -delta
				last["hp_after"] = snappedf((jd as Doll).hp, 0.1)
				last["max_hp"] = (jd as Doll).max_hp)
	report["info"]["scene"] = scene_id
	report["info"]["rush_retreat_s"] = rush_retreat_s
	report["info"]["presets"] = doll_presets


## P1 / P2 площадки (ещё не в дереве) → пресет path: то же имя, место, игрок, префикс ввода, группы и дети без своих тел (WeaponPickup).
func _swap_doll(root: Node, pname: String, path: String) -> void:
	var old := root.get_node_or_null(pname) as Doll
	if old == null or not ResourceLoader.exists(path):
		push_error("match_probe: нет %s или %s" % [pname, path])
		return
	var d := (load(path) as PackedScene).instantiate() as Doll
	if link_type != "" and d.get("blueprint") is BodyBlueprint:   # lk=: связки кисть ↔ бедро своей стороны (kit_human: кисти 3 / 9, бёдра 4 / A)
		var bp := (d.get("blueprint") as BodyBlueprint).duplicate(true) as BodyBlueprint
		var ls: Array[Dictionary] = []
		for pair in [["3", "4"], ["9", "A"]]:
			if not bp.find_node(pair[0]).is_empty() and not bp.find_node(pair[1]).is_empty():
				ls.append({"id": str(ls.size() + 1), "type": link_type, "a": pair[0], "pa": Vector3(0.0, 0.08, 0.0), "b": pair[1],
					"pb": Vector3(0.05, 0.2, 0.0), "len": 0.8, KitLink.CHANNEL_KEY: 1})
		bp.links = ls
		bp.energy_budget = 1000
		d.set("blueprint", bp)
	if tether_type != "" and d.get("blueprint") is BodyBlueprint:   # th=: правая кисть на связке
		var tb := (d.get("blueprint") as BodyBlueprint).duplicate(true) as BodyBlueprint
		var hn := tb.find_node("9")
		if not hn.is_empty():
			hn["joint"] = tether_type
		tb.energy_budget = 1000
		d.set("blueprint", tb)
	d.transform = old.transform
	d.player_index = old.player_index
	d.input_prefix = old.input_prefix
	for g in old.get_groups():
		d.add_to_group(g)
	for c in old.get_children():
		if not (c is RigidBody3D or c is Joint3D) and c.get_script() != null:
			var n: Node = (c.get_script() as Script).new()
			n.name = c.name
			d.add_child(n)
	var idx := old.get_index()
	root.remove_child(old)
	old.free()
	d.name = pname
	root.add_child(d)
	root.move_child(d, idx)


func _rush(d: Doll, other: Doll) -> void:
	if d == null or other == null or not d.alive or not other.alive:
		return
	var dc := d.centre_of_mass()
	var oc := other.centre_of_mass()
	var dx := oc.x - dc.x
	var dy := oc.y - dc.y
	var sgn := signf(dx) if absf(dx) > 0.05 else 1.0
	var vy := clampf(dy / 1.5, -1.0, 1.0) if absf(dy) > 0.8 else 0.0
	# заклинило (нет ударов STUCK_S): обе куклы прыгают врозь и вверх, потом вниз — ломает упор в полку/станок
	# v2 (HIT_FX §11.6): чётная попытка — врозь, нечётная — вверх и через препятствие к сопернику (станок Мастерской
	# между куклами: врозь-вниз их не разводит, обе снова упираются в станок с двух сторон)
	# v3 (04.10): если по сетке проходимости между куклами препятствие и есть путь в обход — идут по пути (nav); не свело за NAV_S
	# или препятствия нет (клинч, пролёты мимо) — прыжок, как раньше
	if t - maxf(last_hit_t, nav_met_t) > STUCK_S and t > unstick_until + STUCK_S and t >= nav_until:
		var us := Time.get_ticks_usec()
		if not nav_tried and _nav_begin():
			nav_until = t + NAV_S
			nav_n += 1
			nav_tried = true
			if trace:
				print("TRACE nav n=%d t=%.2f since_hit=%.1f path=%d grid=%.1f ms %s" % [nav_n, t, t - last_hit_t, _nav_path.size(), (Time.get_ticks_usec() - us) / 1000.0, _trace_pos()])
		else:
			nav_tried = false
			unstick_until = t + UNSTICK_S
			unstick_n += 1
			if trace:
				print("TRACE unstick n=%d t=%.2f since_hit=%.1f %s %s" % [unstick_n, t, t - last_hit_t, _trace_pos(), _trace_between()])
	if t < nav_until and _nav_update():
		d.input_vec = _nav_input(d)
		return
	if t < unstick_until:
		var first_half := t < unstick_until - UNSTICK_S * 0.5
		if unstick_n % 2 == 0:
			d.input_vec = Vector2(sgn * 0.35, 1.0) if first_half else Vector2(sgn, 0.3)
		else:
			d.input_vec = Vector2(-sgn, 1.0 if first_half else -1.0)
		return
	var until := float(rush_retreat.get(d, -1.0))
	if t < until:
		blocked_since.erase(d)
		d.input_vec = Vector2(-sgn, 0.0)
	elif absf(dx) < RUSH_NEAR and absf(dy) < 1.2:
		blocked_since.erase(d)
		rush_retreat[d] = t + rush_retreat_s
		d.input_vec = Vector2(-sgn, 0.0)
	elif _blocked(d):
		# упёрся на разбеге (в Руинах — ящики под помостом между куклами: обе давят с двух сторон и стоят до расклинивания):
		# тот же отход, что после сближения, — следующий наскок с разбега и на Заряде выбивает ящики
		rush_retreat[d] = t + rush_retreat_s
		blocked_n += 1
		d.input_vec = Vector2(-sgn, 0.0)
	else:
		# с отбросом RM (FEEL_TARGET §9: 1–2 H/с вместо 4) куклы после удара остаются рядом и толкаются по 0.1–3 HP:
		# отход полной тягой RUSH_RETREAT_S и рывок (как Shift, DASH_COOLDOWN_S) с разбега ≥ DASH_FROM_M — удары 8–20 HP
		if legacy_dash:
			if absf(dx) > DASH_FROM_M and d._time >= d.dash_ready_at and not d.is_stunned():
				d.dash_until = d._time + Tuning.DASH_DURATION_S
				d.dash_ready_at = d._time + Tuning.DASH_COOLDOWN_S
		else:
			# Заряд (COMBAT_CHARGE.md): как игрок, держащий Shift на разбеге; начинает с BOOST_START_CHARGE, отпускает у BOOST_KEEP_CHARGE
			var holding := bool(rush_boost.get(d, false))
			if absf(dx) > DASH_FROM_M and not d.is_stunned() and (d.charge >= BOOST_START_CHARGE or (holding and d.charge > BOOST_KEEP_CHARGE)):
				rush_boost[d] = true
				d.request_dash()
			else:
				rush_boost[d] = false
		d.input_vec = Vector2(sgn, vy)


## Кукла на разбеге (полная тяга к сопернику) стоит BLOCKED_S подряд — упёрлась.
func _blocked(d: Doll) -> bool:
	var torso := d.parts.get("Torso") as RigidBody3D
	if torso == null or d.is_stunned() or torso.linear_velocity.length() >= BLOCKED_SPEED:
		blocked_since.erase(d)
		return false
	if not blocked_since.has(d):
		blocked_since[d] = t
		return false
	if t - float(blocked_since[d]) < BLOCKED_S:
		return false
	blocked_since.erase(d)
	return true


## Препятствие для обхода: статика, зона смерти арены, ящики/бочки, доски верёвочного моста, тяжёлые динамические тела.
## Части кукол, оружие, обломки и мелочь — нет.
func _nav_obstacle(c: Object) -> bool:
	if c is Area3D:
		return (c as Node).name == "DeathZone"
	if c is StaticBody3D or c is AnimatableBody3D:
		return true
	var rb := c as RigidBody3D
	if rb == null or rb is Weapon or rb.get_parent() is Doll:
		return false
	if rb is Breakable or rb.mass >= NAV_HEAVY_KG:
		return true
	var n := rb.get_parent()
	while n != null and n != pg:
		if n is RopeBridge:
			return true
		n = n.get_parent()
	return false


func _doll_rids() -> Array[RID]:
	var out: Array[RID] = []
	for d in [p1, p2]:
		for part in (d as Doll).parts.values():
			if is_instance_valid(part):
				out.append((part as RigidBody3D).get_rid())
	return out


## Сетка проходимости на момент заклинивания (ящики к этому времени сдвинуты) и первый путь. false — обход не нужен или невозможен.
func _nav_begin() -> bool:
	if pg.arena == null or not pg.arena.has_method("bounds"):
		return false
	var b: AABB = pg.arena.call("bounds")
	_nav_org = Vector2(b.position.x, b.position.y)
	_nav_w = int(ceil(b.size.x / NAV_CELL))
	_nav_h = int(ceil(b.size.y / NAV_CELL))
	_nav_free.resize(_nav_w * _nav_h)
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	# коробка, а не шар: по глубине — только слой кукол (|z| ≤ NAV_HALF_Z); кладка за плоскостью боя (z ≤ −0.3) куклам не мешает
	var box := BoxShape3D.new()
	box.size = Vector3(NAV_CLEAR_R * 2.0, NAV_CLEAR_R * 2.0, NAV_HALF_Z * 2.0)
	q.shape = box
	q.collide_with_areas = true
	q.exclude = _doll_rids()
	for iy in _nav_h:
		for ix in _nav_w:
			var c := _nav_pos(Vector2i(ix, iy))
			q.transform = Transform3D(Basis.IDENTITY, Vector3(c.x, c.y, 0.0))
			var free := 1
			for hit in space.intersect_shape(q, 32):
				if _nav_obstacle(hit["collider"]):
					free = 0
					break
			_nav_free[iy * _nav_w + ix] = free
	_nav_repath_at = t + NAV_REPATH_S
	return _nav_repath() and not _nav_grid_los(_nav_path[0], _nav_path[_nav_path.size() - 1])


func _nav_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - _nav_org.x) / NAV_CELL)), 0, _nav_w - 1), clampi(int(floor((p.y - _nav_org.y) / NAV_CELL)), 0, _nav_h - 1))


func _nav_pos(c: Vector2i) -> Vector2:
	return _nav_org + (Vector2(c) + Vector2(0.5, 0.5)) * NAV_CELL


func _nav_is_free(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < _nav_w and c.y < _nav_h and _nav_free[c.y * _nav_w + c.x] == 1


## Ближайшая свободная клетка: кукла лежит на плите или прижата к стене — её собственная клетка в зазоре прохода.
func _nav_snap(c: Vector2i) -> Vector2i:
	if _nav_is_free(c):
		return c
	for r in range(1, 5):
		var best := Vector2i(-1, -1)
		var best_d := 1 << 30
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				if maxi(absi(ox), absi(oy)) != r:
					continue
				var n := c + Vector2i(ox, oy)
				if _nav_is_free(n) and ox * ox + oy * oy < best_d:
					best_d = ox * ox + oy * oy
					best = n
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Поиск в ширину по 8 соседям (по диагонали — только если обе соседние по сторонам свободны: углы не срезаем).
func _nav_repath() -> bool:
	_nav_path.clear()
	var a := _nav_snap(_nav_cell(p1.centre_of_mass()))
	var b := _nav_snap(_nav_cell(p2.centre_of_mass()))
	if a.x < 0 or b.x < 0:
		return false
	var prev := PackedInt32Array()
	prev.resize(_nav_w * _nav_h)
	prev.fill(-1)
	var start := a.y * _nav_w + a.x
	var goal := b.y * _nav_w + b.x
	var queue := PackedInt32Array([start])
	prev[start] = start
	var head := 0
	while head < queue.size() and prev[goal] == -1:
		var cur := queue[head]
		head += 1
		var cc := Vector2i(cur % _nav_w, cur / _nav_w)
		for dir in NAV_DIRS:
			var n := cc + dir
			if not _nav_is_free(n) or prev[n.y * _nav_w + n.x] != -1:
				continue
			if dir.x != 0 and dir.y != 0 and not (_nav_is_free(cc + Vector2i(dir.x, 0)) and _nav_is_free(cc + Vector2i(0, dir.y))):
				continue
			prev[n.y * _nav_w + n.x] = cur
			queue.append(n.y * _nav_w + n.x)
	if prev[goal] == -1:
		return false
	var i := goal
	while i != start:
		_nav_path.append(Vector2i(i % _nav_w, i / _nav_w))
		i = prev[i]
	_nav_path.append(a)
	_nav_path.reverse()
	return true


## Раз в NAV_REPATH_S: путь от новых положений; куклы сошлись (ближе NAV_MEET_M и сетка между ними свободна) — обход окончен.
## false — обхода больше нет (сошлись или пути нет), _rush идёт дальше обычной логикой.
func _nav_update() -> bool:
	if t < _nav_repath_at:
		return true
	_nav_repath_at = t + NAV_REPATH_S
	var has_path := _nav_repath()
	var met := has_path and p1.centre_of_mass().distance_to(p2.centre_of_mass()) < NAV_MEET_M and _nav_grid_los(_nav_path[0], _nav_path[_nav_path.size() - 1])
	if met or not has_path:
		nav_until = t
		if met:
			nav_met_t = t
			nav_tried = false
		if trace:
			print("TRACE nav end t=%.2f %s %s" % [t, "met" if met else "no path", _trace_pos()])
		return false
	return true


func _nav_grid_los(a: Vector2i, b: Vector2i) -> bool:
	var steps := maxi(absi(b.x - a.x), absi(b.y - a.y)) * 2
	for k in range(1, steps + 1):
		var p := Vector2(a).lerp(Vector2(b), float(k) / float(steps))
		if not _nav_is_free(Vector2i(roundi(p.x), roundi(p.y))):
			return false
	return true


## Полная тяга к самой дальней клетке пути впереди (≤ NAV_LOOKAHEAD), до которой сетка свободна по прямой. P1 идёт с начала пути, P2 — с конца.
func _nav_input(d: Doll) -> Vector2:
	var n := _nav_path.size()
	if n == 0:
		return Vector2.ZERO
	var idx := 0 if d == p1 else n - 1
	var step := 1 if d == p1 else -1
	var target := idx
	for k in range(1, NAV_LOOKAHEAD + 1):
		var j := idx + step * k
		if j < 0 or j >= n or not _nav_grid_los(_nav_path[idx], _nav_path[j]):
			break
		target = j
	var c := d.centre_of_mass()
	var v := _nav_pos(_nav_path[target]) - Vector2(c.x, c.y)
	return v.normalized() if v.length() > 0.05 else Vector2.ZERO


## Руины: из середины каждой шахты ямы луч внутрь арены под плитами земли; стенка шахты — StaticBody3D на |x| = RUINS_PIT_WALL_X.
## Меряется один раз в начале боя: куклы ещё на мосту, в шахтах пусто.
func _probe_pit_walls() -> void:
	var space := get_world_3d().direct_space_state
	pit_rays = 0
	for side in [-1.0, 1.0]:
		for y in RUINS_PIT_RAY_Y:
			var q := PhysicsRayQueryParameters3D.create(Vector3(side * RUINS_PIT_X, y, 0.0), Vector3(side * (RUINS_PIT_WALL_X - 2.0), y, 0.0))
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and hit["collider"] is StaticBody3D and absf(absf((hit["position"] as Vector3).x) - RUINS_PIT_WALL_X) < 0.05:
				pit_rays += 1


## trace: что лежит между куклами (коробка от ЦМ до ЦМ, ±1 м по высоте) — имена тел, кроме частей кукол.
func _trace_between() -> String:
	var a := p1.centre_of_mass()
	var b := p2.centre_of_mass()
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(absf(b.x - a.x) + 0.4, absf(b.y - a.y) + 2.0, 0.6)
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, (a + b) * 0.5)
	q.exclude = _doll_rids()
	var names: PackedStringArray = []
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 32):
		var n := hit["collider"] as Node3D
		names.append("%s@(%.1f,%.1f)" % [n.name, n.global_position.x, n.global_position.y])
	return "between=[%s]" % ", ".join(names)


func _trace_pos() -> String:
	var out: PackedStringArray = []
	for d in [p1, p2]:
		var c: Vector3 = d.centre_of_mass()
		var torso: RigidBody3D = d.parts.get("Torso", null)
		var v: Vector3 = torso.linear_velocity if torso != null and is_instance_valid(torso) else Vector3.ZERO
		out.append("%s com=(%.2f,%.2f,%.2f) v=(%.1f,%.1f) in=(%.2f,%.2f) hp=%.0f ch=%.0f" % [d.name, c.x, c.y, c.z, v.x, v.y, d.input_vec.x, d.input_vec.y, d.hp, d.charge])
	return " | ".join(out)


func _check(id: String, value: float, limit: float, cmp: String, detail: String) -> void:
	var ok := false
	match cmp:
		"lt": ok = value < limit
		"gt": ok = value > limit
		"lte": ok = value <= limit
		"gte": ok = value >= limit
		"eq": ok = is_equal_approx(value, limit)
	report["checks"].append({"id": id, "value": snappedf(value, 0.001), "limit": limit, "cmp": cmp, "ok": ok, "detail": detail})
	if not ok:
		report["ok"] = false
		print("  FAIL %s: %s %s %s (%s)" % [id, snappedf(value, 0.001), cmp, limit, detail])
	else:
		print("  ok   %s: %s %s %s" % [id, snappedf(value, 0.001), cmp, limit])


func _has_announce(kind: String) -> bool:
	for e in events:
		if e.has("announce") and e["kind"] == kind:
			return true
	return false


func _has_hit_announce() -> bool:
	return _has_announce("head") or _has_announce("body") or _has_announce("double")


func _joint_nodes(d: Doll) -> int:
	var n := 0
	for c in d.get_children():
		if c is Generic6DOFJoint3D:
			n += 1
	return n


func _part_spread(d: Doll) -> float:
	var mx := 0.0
	var list: Array = d.parts.values()
	for i in range(list.size()):
		for j in range(i + 1, list.size()):
			if is_instance_valid(list[i]) and is_instance_valid(list[j]):
				mx = maxf(mx, (list[i] as RigidBody3D).global_position.distance_to((list[j] as RigidBody3D).global_position))
	return mx


func _physics_process(delta: float) -> void:
	t += delta
	min_time_scale = minf(min_time_scale, Engine.time_scale)
	if not fx_seen:
		for c in match_node.get_children():
			if c.name.begins_with("ImpactFx"):
				fx_seen = true
				break
	# таймер HUD: текст меняется и совпадает с Match
	if match_node.combat_active():
		var txt := hud.timer_label.text
		if txt != last_timer_text:
			timer_updates += 1
			last_timer_text = txt
		if txt != Hud.format_time(match_node.time_left_s()):
			timer_mismatches += 1
	if sd_mode:
		_sd_tick()
		return
	match stage:
		0:
			if match_node.combat_active():
				if scene_id == "ruins" and pit_rays < 0:
					_probe_pit_walls()
				_rush(p1, p2)
				_rush(p2, p1)
				if trace and t >= _trace_next:
					_trace_next = t + 1.0
					print("TRACE t=%.1f fight=%.1f hits=%d %s" % [t, match_node.fight_time, hits, _trace_pos()])
			else:
				p1.input_vec = Vector2.ZERO
				p2.input_vec = Vector2.ZERO
			if ko_fired and t >= ko_t + 1.0:
				_checks_ko()
				stage = 1
			elif fight_seen and (match_node.fight_time >= max_s or (match_node.phase == Match.Phase.OVER and not ko_fired)):
				var c1 := p1.centre_of_mass()
				var c2 := p2.centre_of_mass()
				report["info"]["timeout"] = {"fight_time": match_node.fight_time, "hp": [p1.hp, p2.hp], "hits": hits,
					"pos": [[snappedf(c1.x, 0.01), snappedf(c1.y, 0.01)], [snappedf(c2.x, 0.01), snappedf(c2.y, 0.01)]], "last_hit_ago_s": snappedf(t - last_hit_t, 0.1)}
				_checks_ko()
				stage = 1
		1:
			if hud.results.visible:
				results_seen = true
			var waited_ms := Time.get_ticks_msec() - results_wait_ms if results_wait_ms >= 0 else 0
			if over_fired and (results_seen or waited_ms >= RESULTS_WAIT_REAL_MS) or not over_fired and t >= ko_t + 4.0:
				_checks_over()
				old_ids = [p1.get_instance_id(), p2.get_instance_id()]
				match_node.restart()
				restart_t = t
				stage = 2
		2:
			if t >= restart_t + 0.5:
				_checks_restart()
				stage = 3
				_finish()


## Sudden Death: ждём шаг SUDDEN_DEATH_BREAK_PLATFORMS_STEP (+0.5 с), проверяем молот/мосты/стабильность/HUD, выходим.
func _sd_tick() -> void:
	p1.input_vec = Vector2.ZERO
	p2.input_vec = Vector2.ZERO
	var target_step: int = Tuning.SUDDEN_DEATH_BREAK_PLATFORMS_STEP
	var done_t := SD_TIME_LIMIT_S + Tuning.SUDDEN_DEATH_STEP_S * float(target_step) + SD_SETTLE_S
	if stage == 0 and fight_seen and (match_node.fight_time >= done_t or match_node.phase == Match.Phase.OVER):
		stage = 3
		_check("sd_phase", 1.0 if match_node.phase == Match.Phase.SUDDEN_DEATH else 0.0, 1.0, "eq", "phase SUDDEN_DEATH (phase=%d)" % match_node.phase)
		_check("sd_step", float(match_node.sd_step), float(target_step), "eq", "sd_step reached %d" % target_step)
		_check("sd_announce", 1.0 if _has_announce("sudden_death") else 0.0, 1.0, "eq", "SUDDEN DEATH announced")
		_check("hud_sd_label", 1.0 if hud.sudden_death_label.visible else 0.0, 1.0, "eq", "HUD SUDDEN DEATH label visible")
		var hammer: Variant = pg.get("sd_hammer")
		_check("sd_hammer", 1.0 if hammer is Weapon and is_instance_valid(hammer) and (hammer as Weapon).weapon_id == "hammer" else 0.0, 1.0, "eq", "playground dropped the Sudden Death hammer")
		if hammer is Weapon and is_instance_valid(hammer):
			var b: AABB = pg.arena.call("bounds")
			var hp_: Vector3 = (hammer as Node3D).global_position
			_check("sd_hammer_in_arena", 1.0 if b.grow(0.5).has_point(hp_) else 0.0, 1.0, "eq", "hammer inside arena bounds (%s)" % hp_)
			_check("sd_hammer_landed", 1.0 if (hammer as RigidBody3D).linear_velocity.length() < 1.0 else 0.0, 1.0, "eq", "hammer came to rest (v=%.2f)" % (hammer as RigidBody3D).linear_velocity.length())
		if pg.arena.has_method("rope_bridges"):
			var bridges: Array = pg.arena.call("rope_bridges")
			var broken := 0
			for rb in bridges:
				if rb.get("is_broken") == true:
					broken += 1
			_check("sd_bridges", float(broken), float(bridges.size()), "eq", "all rope bridges broken (%d of %d)" % [broken, bridges.size()])
			var fallen := 0
			var planks_n := 0
			for rb in bridges:
				var ys: Array = plank_y_at_break.get(rb, [])
				var planks: Array = rb.call("planks")
				for i in range(planks.size()):
					planks_n += 1
					var y0 := float(ys[i]) if i < ys.size() else INF
					if (planks[i] as Node3D).global_position.y < y0 - 0.5:
						fallen += 1
			_check("sd_planks_fell", float(fallen), float(planks_n) * 0.5, "gte", "at least half the planks dropped >= 0.5 m within %.0f s of the break (%d of %d)" % [SD_SETTLE_S, fallen, planks_n])
		_check("sd_stability", p1.stability_mult, Damage.sd_stability_mult(target_step), "eq", "Doll.stability_mult at step %d" % target_step)
		_check("sd_knockback", match_node.knockback_mult(), Damage.sd_knockback_mult(target_step), "eq", "Match.knockback_mult at step %d" % target_step)
		_check("sd_no_damage", float(hits), 0.0, "eq", "idle dolls took no hits during SD")
		_check("sd_alive", 1.0 if p1.alive and p2.alive else 0.0, 1.0, "eq", "both alive")
		report["info"]["sd"] = {"fight_time": match_node.fight_time, "sd_step": match_node.sd_step, "events": events.slice(0, 20), "hp": [p1.hp, p2.hp]}
		_finish()


func _checks_ko() -> void:
	if scene_id == "ruins":
		_check("pit_walls", float(pit_rays), float(RUINS_PIT_RAY_Y.size() * 2), "eq", "pit shafts are walled off under the ground edge (rays stopped at |x| = %.0f)" % RUINS_PIT_WALL_X)
	_check("announce_countdown", 1.0 if _has_announce("countdown") else 0.0, 1.0, "eq", "countdown announced")
	_check("announce_fight", 1.0 if _has_announce("fight") else 0.0, 1.0, "eq", "FIGHT! announced")
	_check("hud_panels", float(hud.panels.size()), 2.0, "eq", "HUD has 2 player panels")
	_check("hud_timer_updates", float(timer_updates), 2.0, "gte", "HUD timer text changed at least twice")
	_check("hud_timer_synced", float(timer_mismatches), 2.0, "lte", "HUD timer text == Match.time_left_s() (mismatching ticks)")
	_check("hits", float(hits), 1.0, "gte", "Match.hit fired at least once")
	_check("announce_hit", 1.0 if _has_hit_announce() else 0.0, 1.0, "eq", "HEAD/BODY/DOUBLE BLOW! announced")
	_check("hud_hp_synced", 1.0 if hp_synced else 0.0, 1.0, "eq", "HUD panel hp == doll hp after every hit")
	_check("fx", 1.0 if fx_seen else 0.0, 1.0, "eq", "ImpactFx spawned under Match")
	_check("ko", 1.0 if ko_fired else 0.0, 1.0, "eq", "KO within %.0f s of fight (fight_time %.1f)" % [max_s, match_node.fight_time])
	if ko_fired and is_instance_valid(ko_victim):
		# детали, отлетевшие до KO (joints=1, JointBreak): их тел нет в parts, а суставы внутри оторванного куска остаются (рука — рукой)
		var lost_bodies := 0
		var lost_joints := 0
		for rec in ko_victim._detached.values():
			lost_bodies += (rec["sub"] as Array).size()
			lost_joints += 1 + (rec["sub_joints"] as Array).size()
		_check("ko_joints", float(ko_victim.joints.size()) + float(_joint_nodes(ko_victim)), float(lost_joints), "lte", "victim joints freed (detached limbs keep theirs)")
		var valid := 0
		var lob: Variant = ko_victim.get("link_of_body")   # тела связок (lk= / th=) — не детали куклы, их в 14 не считаем
		for pn in ko_victim.parts:
			var p: Variant = ko_victim.parts[pn]
			if is_instance_valid(p) and (p as Node).is_inside_tree() and not (lob is Dictionary and (lob as Dictionary).has(pn)):
				valid += 1
		_check("ko_parts", float(valid), 14.0 - float(lost_bodies), "eq", "14 parts (minus limbs lost before KO, links not counted) still in the tree after KO")
		_check("ko_spread", _part_spread(ko_victim), 1.5, "gte", "parts spread (m) 1 s after KO")
		_check("ko_card", 1.0 if ko_card_seen else 0.0, 1.0, "eq", "HUD KO card shown on ko signal")
		_check("announce_ko", 1.0 if _has_announce("ko") else 0.0, 1.0, "eq", "KO! announced")
		report["info"]["ko"] = {"t": ko_t, "fight_time": match_node.fight_time, "victim": ko_victim.name, "record": _record_summary(ko_victim.last_ko_record)}
	if Tuning.HITFX_ENABLED:
		var dirs := int(match_node.get_node_or_null("HitFxDirector") != null) + int(match_node.get_node_or_null("SfxDirector") != null)
		_check("fx_directors", float(dirs), 2.0, "eq", "Match created HitFxDirector + SfxDirector (_ensure_fx_directors)")
		_check("hitfx_env_kind", float(hitfx_env_kind), 0.0, "eq", "hit_fx with kind environment (env damage stays 0)")
	var n_crit := int(hitfx_tiers.get("crit", 0)) + int(hitfx_tiers.get("ko_crit", 0))
	report["info"]["hitfx"] = {"tiers": hitfx_tiers, "crits": hitfx_crits, "env_slam": env_slams, "fight_time": snappedf(match_node.fight_time, 0.01),
		"fight_s_per_crit": snappedf(match_node.fight_time / float(n_crit), 0.1) if n_crit > 0 else -1.0}
	report["info"]["hits"] = hits
	if JointBreak.on:
		report["info"]["joints_broken"] = joints_broken
		report["info"]["joints_left"] = joints_left
	if PartHp.on:
		report["info"]["parts"] = {"start": parts_start, "lost": parts_lost, "end": {"P1": [snappedf(p1.hp, 0.1), p1.max_hp], "P2": [snappedf(p2.hp, 0.1), p2.max_hp]}}
	if link_type != "":
		report["info"]["links"] = {"type": link_type, "broken": [int(p1.stats.get("links_broken", 0)), int(p2.stats.get("links_broken", 0))]}
	report["info"]["hit_list"] = hit_list
	report["info"]["hp"] = {"p1": p1.hp, "p2": p2.hp}
	report["info"]["stats_p1"] = p1.stats.duplicate()
	report["info"]["stats_p2"] = p2.stats.duplicate()
	var ch := {}
	for pair in [["p1", p1], ["p2", p2]]:
		var st: Dictionary = (pair[1] as Doll).stats
		var inc := float(st["charge_from_hits"]) + float(st["charge_from_regen"])
		ch[pair[0]] = {"from_hits": snappedf(float(st["charge_from_hits"]), 0.1), "from_regen": snappedf(float(st["charge_from_regen"]), 0.1),
			"hit_share": snappedf(float(st["charge_from_hits"]) / inc, 0.01) if inc > 0.0 else 0.0, "spent": snappedf(float(st["charge_spent"]), 0.1),
			"boost_s": snappedf(float(st["boost_s"]), 0.01), "spin_s": snappedf(float(st["spin_s"]), 0.01), "empty": int(st["charge_empty"]),
			"charge_end": snappedf((pair[1] as Doll).charge, 0.1)}
	report["info"]["charge"] = ch
	report["info"]["legacy_dash"] = legacy_dash
	report["info"]["unsticks"] = unstick_n
	report["info"]["navs"] = nav_n
	report["info"]["blocked_retreats"] = blocked_n


func _checks_over() -> void:
	_check("match_over", 1.0 if over_fired else 0.0, 1.0, "eq", "match_over emitted")
	# одновременный KO (оба в одном тике физики) — ничья без победителя; мёртвый победителем не бывает
	var draw_ko := over_winner == null and bool(over_results.get("draw", false)) and not p1.alive and not p2.alive
	_check("match_winner", 1.0 if over_winner != null and over_winner.alive or draw_ko else 0.0, 1.0, "eq",
		"winner is an alive doll, or a draw when both were knocked out in the same tick")
	var places: Array = over_results.get("places", [])
	_check("match_places", float(places.size()), 2.0, "eq", "results.places has 2 dolls")
	var medals: Dictionary = over_results.get("medals", {})
	_check("match_medal_winner", 1.0 if medals.get("Winner", null) == over_winner else 0.0, 1.0, "eq", "medals.Winner == winner")
	_check("results_visible", 1.0 if results_seen else 0.0, 1.0, "eq", "HUD results panel shown after match_over (real time)")
	_check("hud_phase_over", float(hud.phase), float(Hud.Phase.OVER), "eq", "HUD phase OVER")
	_check("time_scale_restored", Engine.time_scale, 1.0, "eq", "Engine.time_scale back to 1")
	_check("time_scale_used", min_time_scale, 1.0, "lt", "hit stop / slow-mo lowered time_scale")
	var medal_names: Array = []
	for k in medals.keys():
		medal_names.append("%s:P%d" % [k, (medals[k] as Doll).player_index + 1])
	report["info"]["match"] = {"reason": over_results.get("reason", ""), "duration": over_results.get("duration_s", -1.0), "medals": medal_names,
		"winner": over_winner.name if over_winner != null else "", "draw": over_results.get("draw", false), "ranks": over_results.get("ranks", []),
		"ko_frames": over_results.get("ko_records", []).map(func(r: Dictionary) -> int: return int(r.get("physics_frame", -1))),
		"events": events.slice(0, 40), "min_time_scale": min_time_scale}


func _checks_restart() -> void:
	var ds := match_node.dolls()
	_check("restart_dolls", float(ds.size()), 2.0, "eq", "after restart(): Match.dolls() has 2")
	var fresh := 0
	var alive := 0
	var full_hp := 0
	for d in ds:
		var dd := d as Doll
		if not old_ids.has(dd.get_instance_id()):
			fresh += 1
		if dd.alive and not dd.is_broken():
			alive += 1
		if is_equal_approx(dd.hp, dd.max_hp) and (is_equal_approx(dd.max_hp, Tuning.MAX_HP) or dd.has_meta("parts_hp")):   # parts=1: запас из деталей
			full_hp += 1
	_check("restart_fresh", float(fresh), 2.0, "eq", "both dolls are new instances")
	_check("restart_alive", float(alive), 2.0, "eq", "both alive and unbroken")
	_check("restart_hp", float(full_hp), 2.0, "eq", "both at MAX_HP (parts=1 — at Σ ❤ of their parts)")
	_check("restart_phase", 1.0 if match_node.phase == Match.Phase.COUNTDOWN else 0.0, 1.0, "eq", "phase COUNTDOWN after restart (phase=%d)" % match_node.phase)
	_check("restart_results_hidden", 0.0 if hud.results.visible else 1.0, 1.0, "eq", "HUD results hidden after restart")
	_check("restart_ko_card_hidden", 0.0 if hud.ko_card.visible else 1.0, 1.0, "eq", "HUD KO card hidden after restart")
	var panels_reset := 0
	for i in hud.panels.keys():
		var p: PlayerPanel = hud.panels[i]
		var want := Tuning.MAX_HP
		for d in ds:   # parts=1: запас новой куклы этого игрока — Σ ❤ её деталей
			if (d as Doll).player_index == i and (d as Doll).has_meta("parts_hp"):
				want = (d as Doll).max_hp
		if is_equal_approx(p.hp_bar.hp, want) and not p.portrait.knocked_out:
			panels_reset += 1
	_check("restart_panels", float(panels_reset), 2.0, "eq", "HUD panels reset (hp max, KO cleared)")
	_check("restart_group", float(get_tree().get_nodes_in_group("dolls").size()), 2.0, "eq", "group dolls has exactly 2")


func _record_summary(r: Dictionary) -> Dictionary:
	var out := {}
	for k in ["kind", "damage", "speed", "weapon_id", "part", "time", "combo_mult", "double_blow"]:
		if r.has(k):
			out[k] = r[k]
	var att: Object = r.get("attacker", null)
	out["attacker"] = att.name if att != null and is_instance_valid(att) else ""
	return out


func _finish() -> void:
	_perf_summary()
	report["info"]["godot"] = Engine.get_version_info()["string"]
	var js := JSON.stringify(report, "  ")
	print("=== MATCH PROBE ===")
	print(js)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(js)
		f.close()
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)
