## Проба вёрстки на всех языках (headless): текст другого языка не должен вылезать или налезать там, где русский помещался.
## Эталон — русский (под него рисовался интерфейс). Для каждого экрана (гараж: титул / пункты / настройки / трофеи, кампания в ТВ,
## мастерская, экран «ВСЕ РЕЖИМЫ» (длинная карточка стычки и памятка клавиш), HUD купола с меткой СТАЗИСА и плашками бойцов эфира, спорт-зал, «Стычка 3 на 3» и её итоги, «Бомба касанием», «Гонка: 10 точек», «Гонка: трасса» и её итоги, «Королевская битва», «Гольф: кукла — мяч», «Головоломки вдвоём» и их итоги, «Подъём: проба стены» вдвоём и её финиш, «Стенка на стенку 5×5» и её итоги, «Заражение», «Охота за головами», «Перетягивание», «Царь горы», хоккей, «Испытание» (старт, бой, антракт, итог забега), экран «РЕЖИМЫ» реестра, панель «ВИД», табло KO-кино и фоторежим) снимаются прямоугольники всех видимых Label / Button / RichTextLabel / LineEdit на русском, потом то же на каждом
## найденном языке (locale/*.json) и на растянутом qps (+35 % длины, Loc.PSEUDO). Новая беда = её не было на русском:
##   • «вылез за экран»  — текст выходит за окно, а на русском не выходил;
##   • «налез на соседа» — два текста пересеклись (≥ 4 % меньшего), а на русском нет;
##   • «вылез из плашки» — текст был внутри ColorRect/Panel, а теперь торчит за край.
## Узлы сопоставляются по пути из индексов детей, а не по имени (auto-имена @Label@N меняются от прогона к прогону).
## Языки из locale/ дают FAIL (exit 1); qps — стресс-тест: беды печатаются, но exit не валят (+35 % заведомо жёстче реальных языков).
## Запуск: godot --headless --path . res://tests/i18n_layout_probe.tscn [-- "langs=en,de,qps"]   (по умолчанию все + qps)
##   Отчёт: tests/i18n_layout_report.json. Сам кадр беды смотреть так: tools/i18n_shots.sh <код> (снимки главных экранов в окне).
extends Node

const MENU := preload("res://scenes/menu/garage_menu.tscn")
const MODES := "res://scenes/menu/test_menu.tscn"
const WORKSHOP := "res://scenes/workshop/workshop_build.tscn"
const HALL := "res://scenes/playground_null_hall.tscn"
const SPORT := "res://scenes/playground_sport.tscn"
const SQUAD := "res://scenes/playground_squad.tscn"
const DOMINATION := "res://scenes/playground_domination.tscn"   # «Захват точек» (DOMINATION.md): табличка итогов с колонкой ТОЧКИ
const BOMB := "res://scenes/playground_bomb.tscn"
const RACE := "res://scenes/playground_race.tscn"
const ROYALE := "res://scenes/playground_royale.tscn"
const GOLF := "res://scenes/playground_golf.tscn"
const PUZZLE := "res://scenes/playground_puzzle.tscn"
const TRACK := "res://scenes/playground_race_track.tscn"
const CLIMB := "res://scenes/playground_climb.tscn"
const CONVOY := "res://scenes/playground_convoy.tscn"
const BRAWL := "res://scenes/playground_brawl.tscn"
const INFECTION := "res://scenes/playground_infection.tscn"
const HEADHUNT := "res://scenes/playground_headhunt.tscn"
const TUG := "res://scenes/playground_tug.tscn"
const DODGEBALL := "res://scenes/playground_dodgeball.tscn"   # «Вышибалы 3 на 3» (DODGEBALL.md): HUD, тосты, табличка итогов
const KING := "res://scenes/playground_king.tscn"
const BOSS := "res://scenes/playground_boss.tscn"   # «Босс» (BOSS.md): полоса Титана, слабое место, итоги
const SCAVENGER := "res://scenes/playground_scavenger.tscn"   # «Собери себя» (SCAVENGER.md): плашки деталей, итоги
const HOCKEY := "res://scenes/playground_sport_hockey.tscn"   # спорт-зал, хоккей (HOCKEY.md): своя подсказка и подпись HUD
const GAUNTLET := "res://scenes/playground_gauntlet.tscn"   # «Испытание» (GAUNTLET.md): старт с лестницей, бой, антракт, итог забега
const MODES_100 := "res://scenes/menu/modes_menu.tscn"   # экран «РЕЖИМЫ» реестра (MODES_100.md)
const VIEW := Rect2(0, 0, 1920, 1080)
const OVERLAP := 0.04
const MARGIN := 2.0
const SETTLE := 40

var report := {"ok": true, "langs": {}}
var langs: Array = []
var _base := {}      # экран → {«индексный путь» → {rect, text}}
var _plate_base := {}


func _ready() -> void:
	var loc := get_node("/root/Loc")
	var want := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("langs="):
			want = a.substr(6)
	langs = want.split(",") if want != "" else []
	if langs.is_empty():
		for c in loc.codes:
			langs.append(c)
		langs.append(loc.PSEUDO)
	langs.erase("ru")
	print("=== I18N LAYOUT PROBE: ru (эталон) → %s ===" % ", ".join(langs))
	WorkshopBuild.prefs_path = "user://_probe_layout_prefs.cfg"
	loc.set_language("ru")
	var base := await _pass()
	for code in langs:
		loc.set_language(code)
		var cur := await _pass()
		var issues := _compare(base, cur)
		var real: bool = code != loc.PSEUDO
		report["langs"][code] = {"issues": issues.size(), "stress_only": not real}
		if issues.is_empty():
			print("  ok   %s" % code)
			continue
		if real:
			report["ok"] = false
		print("  %s %s: %d проблем%s" % ["FAIL" if real else "warn", code, issues.size(), "" if real else " (стресс-тест, не валит)"])
		for i in mini(issues.size(), 14):
			print("       ", issues[i])
		report["langs"][code]["list"] = issues
	loc.set_language("ru")
	var f := FileAccess.open("res://tests/i18n_layout_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
	print("=== %s ===" % ("OK" if report["ok"] else "FAIL"))
	get_tree().quit(0 if report["ok"] else 1)


## Один проход по всем экранам в текущем языке → {экран → {ключ → {rect, text, plates}}}.
func _pass() -> Dictionary:
	var shots := {}
	var menu := MENU.instantiate() as GarageMenu
	menu.dry_run = true
	add_child(menu)
	menu.campaign.save_path = "user://_probe_layout.tres"
	menu.campaign.bp_name = "_probe_layout"
	menu.campaign.load_save = false
	await _wait(SETTLE)
	shots["garage:title"] = _scan(menu)
	menu.enter_menu()
	for i in GarageMenu.ITEMS.size():
		menu.set_focus(i, true)
		await _wait(SETTLE)
		shots["garage:item%d" % i] = _scan(menu)
	menu.set_focus(5, true)
	menu._open_settings()
	await _wait(SETTLE)
	shots["garage:settings"] = _scan(menu)
	menu._close_settings()
	menu._open_trophies()
	await _wait(SETTLE)
	shots["garage:trophies"] = _scan(menu)
	menu._close_trophies()
	# загрузка связи нейрошлема (garage_headset.gd): надпись и строка поверх чёрного визора
	menu.headset.overlay.visible = true
	menu.headset._show_boot("NULL LINK", "нейрошлем · фильтр NULL включён · стенд 1")
	await _wait(SETTLE)
	shots["garage:headset_boot"] = _scan(menu)
	menu.headset.overlay.visible = false
	menu.set_focus(0, true)
	await _wait(10)
	# смена канала ТВ (_apply_tv) достраивает экран твином через 0.08 с реального времени: если кампания откроется раньше,
	# канал «Следующий бой» дорисуется поверх её экранов в одном языке и не дорисуется в другом — ложные «налез» (23.10)
	await get_tree().create_timer(0.3, true, false, true).timeout
	menu.activate()
	var c := menu.campaign
	var guard := 0
	while c.screen != GarageCampaign.Screen.LADDER and guard < 600:
		guard += 1
		await get_tree().process_frame
	await _wait(SETTLE)
	shots["campaign:ladder"] = _scan(menu)
	c.finish_fight(true, {"won": true, "duration_s": 47.0})
	await _wait(SETTLE)
	shots["campaign:win"] = _scan(menu)
	c.finish_fight(false, {"won": false, "duration_s": 12.0})
	await _wait(SETTLE)
	shots["campaign:loss"] = _scan(menu)
	menu.queue_free()
	await _wait(5)
	# экран «ВСЕ РЕЖИМЫ» (docs/plan-demo/MODES_SCREEN.md): выбрана стычка — самое длинное описание и шесть клавиш; потом памятка клавиш
	var modes := (load(MODES) as PackedScene).instantiate()
	modes.set("dry_run", true)
	add_child(modes)
	await _wait(5)
	var mlist: Array = modes.get("list")
	for i in mlist.size():
		if String(mlist[i]["id"]) == "squad":
			modes.call("select", i, true)
	await _wait(SETTLE)
	shots["modes:squad"] = _scan(modes)
	modes.call("set_memo", true)
	await _wait(SETTLE)
	shots["modes:memo"] = _scan(modes.get("memo"))   # памятка — поверх экрана: тексты под ней закрыты, сравниваем только её
	modes.queue_free()
	await _wait(5)
	RacePlayground.best_path = "user://_probe_layout_race.cfg"   # «Гонка» (RACE.md): итоги пишут рекорд P1 — не в рекорды игрока
	TrackPlayground.best_path = "user://_probe_layout_track.cfg"   # «Гонка: трасса» (RACE_TRACK.md) — так же
	GauntletRun.save_path = "user://_probe_layout_gauntlet.cfg"   # «Испытание» (GAUNTLET.md): рекорд забега — не в рекорды игрока
	for p in [WORKSHOP, HALL, SPORT, SQUAD, DOMINATION, BOMB, RACE, TRACK, ROYALE, GOLF, PUZZLE, CLIMB, CONVOY, BRAWL, INFECTION, HEADHUNT, TUG, DODGEBALL, KING, BOSS, SCAVENGER, HOCKEY, GAUNTLET, MODES_100]:
		Stasis.set_on(p == HALL)   # в куполе — с меткой режима СТАЗИС на HUD (StasisBadge, STASIS.md)
		if p == CLIMB:
			ClimbMatch.best_time = -1.0   # лучшее время сессии — static: на каждом языке экран тот же («—»)
		var inst := (load(p) as PackedScene).instantiate()
		if p == GAUNTLET:   # кит «Человек», не автосейв мастерской этой машины: имя сборки на старте и тело в бою — одни и те же
			(inst as GauntletPlayground).use_workshop = false
		add_child(inst)
		await _wait(SETTLE * 2)
		if p == HALL:
			_settle_show(inst)
			await _wait(2)
		shots[p.get_file()] = _scan(inst)
		if p == HALL:   # панель «ВИД» (Look, LOOK_PASS.md): галочки проб картинки, зарегистрированные куполом
			Look._panel.set_open(true)
			await _wait(SETTLE)
			shots["look:panel"] = _scan(Look)
			Look._panel.set_open(false)
			await _look_cam_pass(shots)
		if p == SQUAD:   # «Стычка 3 на 3» (SQUAD.md): ещё табличка итогов с таблицей бойцов
			var sm := inst.get_node("Match") as SquadMatch
			sm.score = [15, 9]
			sm._finish("score")
			await _wait(SETTLE * 3)
			shots["squad:end"] = _scan(inst)
		if p == DOMINATION:   # «Захват точек» (DOMINATION.md): табличка итогов (последняя колонка — ТОЧКИ)
			var dmm := inst.get_node("Match") as DominationMatch
			dmm.score = [100, 64]
			dmm._finish("score")
			await _wait(SETTLE * 3)
			shots["domination:end"] = _scan(inst)
		if p == BOMB:   # «Бомба касанием» (BOMB.md): ещё табличка итогов с таблицей бойцов
			var bm := inst.get_node("Match") as BombMatch
			bm.wins = {0: 3, 1: 1, 3: 2}
			bm._finish("wins")
			await _wait(SETTLE * 3)
			shots["bomb:end"] = _scan(inst)
		if p == BRAWL:   # «Стенка на стенку 5×5» (BRAWL.md): ещё табличка итогов с таблицей бойцов и медалями
			var brm := inst.get_node("Match") as BrawlMatch
			brm.wins = [2, 1]
			brm._finish("wins")
			await _wait(SETTLE * 3)
			shots["brawl:end"] = _scan(inst)
		if p == INFECTION:   # «Заражение» (INFECTION.md): ещё табличка итогов с таблицей бойцов
			var ifm := inst.get_node("Match") as InfectionMatch
			ifm.scores = {0: 2, 1: 1, 3: 2, 5: 1}
			ifm._finish("rounds")
			await _wait(SETTLE * 3)
			shots["infection:end"] = _scan(inst)
		if p == HEADHUNT:   # «Охота за головами» (HEADHUNT.md): ещё табличка итогов с таблицей бойцов и медалями
			var hhm := inst.get_node("Match") as HeadhuntMatch
			hhm.score = [10, 7]
			hhm._finish("score")
			await _wait(SETTLE * 3)
			shots["headhunt:end"] = _scan(inst)
		if p == TUG:   # «Перетягивание каната» (TUG.md): ещё табличка итогов с таблицей бойцов
			var tgm := inst.get_node("Match") as TugMatch
			tgm.score = [3, 1]
			tgm._finish("score")
			await _wait(SETTLE * 3)
			shots["tug:end"] = _scan(inst)
		if p == DODGEBALL:   # «Вышибалы 3 на 3» (DODGEBALL.md): тост ловли под таймером, потом табличка итогов с таблицей бойцов
			var dbh := (inst as DodgeballPlayground).hud
			dbh.toast(tr("ПОЙМАЛ!"))
			dbh.toast(tr("ВЫБИТ %s") % "P3")
			await _wait(SETTLE)
			shots["dodgeball:toast"] = _scan(inst)
			var dbm := inst.get_node("Match") as DodgeballMatch
			dbm.score = [2, 1]
			dbm._finish("score")
			await _wait(SETTLE * 3)
			shots["dodgeball:end"] = _scan(inst)
		if p == KING:   # «Царь горы» (KING.md): ещё табличка итогов с таблицей бойцов
			var kgm := inst.get_node("Match") as KingMatch
			kgm.scores = {0: 60.0, 1: 41.5, 2: 12.0, 3: 33.0, 4: 7.0}
			kgm.winner_index = 0
			kgm._finish("score")
			await _wait(SETTLE * 3)
			shots["king:end"] = _scan(inst)
		if p == BOSS:   # «Босс» (BOSS.md): ещё табличка итогов с таблицей игроков
			var bsm := inst.get_node("Match") as BossMatch
			bsm.tally = {0: {"dmg": 512.0, "weak_hits": 23, "kos_taken": 1, "parts": 4},
				1: {"dmg": 488.5, "weak_hits": 19, "kos_taken": 2, "parts": 3}}
			bsm.boss_phase = 3
			bsm._finish("boss")
			await _wait(SETTLE * 3)
			shots["boss:end"] = _scan(inst)
		if p == SCAVENGER:   # «Собери себя» (SCAVENGER.md): ещё табличка итогов с таблицей бойцов
			var svm := inst.get_node("Match") as ScavMatch
			svm._finish("timeout")
			await _wait(SETTLE * 3)
			shots["scavenger:end"] = _scan(inst)
		if p == GAUNTLET:   # «Испытание» (GAUNTLET.md): бой 1, антракт с оторванным и починкой, итог забега
			var gp := inst as GauntletPlayground
			GauntletRun.erase_record()
			gp.record = GauntletRun.load_record()
			gp.start_run()
			await _wait(SETTLE * 2)
			shots["gauntlet:fight"] = _scan(inst)
			var gd := gp.fight.get_node("P1") as Doll
			gp.run.body_map(gd)
			var lost: Array = []
			for n in gd.part_hp:
				if String(n).begins_with("Upper") and lost.size() < 2:
					lost.append(String(n))
			await get_tree().process_frame
			gp.finish_fight(true, {"duration_s": 47.0, "snapshot": {"lost": lost, "deficit": 30.0, "hp": 70.0, "max_hp": gd.max_hp, "wear": {}}})
			await _wait(SETTLE)
			shots["gauntlet:break"] = _scan(inst)
			gp.give_up_to_result()
			await _wait(SETTLE)
			shots["gauntlet:result"] = _scan(inst)
			GauntletRun.erase_record()
		if p == RACE:   # «Гонка: 10 точек» (RACE.md): ещё табличка итогов с таблицей мест
			var rmm := inst.get_node("Match") as RaceMatch
			rmm.scores = {0: 10, 1: 7, 2: 4, 3: 9}
			rmm.winner_index = 0
			rmm._finish("points")
			await _wait(SETTLE * 3)
			shots["race:end"] = _scan(inst)
		if p == TRACK:   # «Гонка: трасса» (RACE_TRACK.md): ещё табличка итогов (время финиша, доля пути, возвраты)
			var trm := inst.get_node("Match") as TrackMatch
			var times := [72.3, 75.8, -1.0, -1.0]
			for d in trm.dolls():
				var st := trm.state_of(d as Doll)
				var t: float = times[(d as Doll).player_index % times.size()]
				st["finished"] = t > 0.0
				st["finish_t"] = t
				st["prog"] = 300.0 + 20.0 * float((d as Doll).player_index)
				if t > 0.0:
					trm.finish_order.append((d as Doll).player_index)
					st["place"] = trm.finish_order.size()
			trm.winner_index = 0
			trm.first_finish_t = 72.3
			trm._finish("wait")
			await _wait(SETTLE * 3)
			shots["track:end"] = _scan(inst)
		if p == ROYALE:   # «Королевская битва» (ROYALE.md): ещё табличка итогов с местами
			var ro := inst.get_node("Match") as RoyaleMatch
			ro._finish("ko")
			await _wait(SETTLE * 3)
			shots["royale:end"] = _scan(inst)
		if p == GOLF:   # «Гольф: кукла — мяч» (GOLF.md): ещё карточка итогов по лункам
			var gmm := inst.get_node("Match") as GolfMatch
			gmm.players[0]["card"] = [3, 4, 2]
			gmm.players[1]["card"] = [4, 3, 5]
			gmm.hole_i = 2
			gmm._finish("holes")
			await _wait(SETTLE * 3)
			shots["golf:end"] = _scan(inst)
		if p == PUZZLE:   # «Головоломки вдвоём» (PUZZLE.md): P2 вошёл (памятка P2 длиннее) и табличка итогов со временем комнат
			var pz := inst as PuzzlePlayground
			pz.join_p2()
			await _wait(SETTLE)
			shots["puzzle:p2"] = _scan(inst)
			pz.goto_room(pz.rooms.size() - 1)   # «Стрелочник» (PORTAL.md): самая длинная подсказка и строка «Один: …»
			await _wait(SETTLE)
			shots["puzzle:room8"] = _scan(inst)
			pz.room_times =[42.0, 31.5, 77.0, 25.0, 64.0, 58.0, 36.0, 49.5]
			pz.done = true
			pz.demo_finished.emit(297.5)
			await _wait(SETTLE * 2)
			shots["puzzle:end"] = _scan(inst)
		if p == CLIMB:   # «Подъём: проба стены» (CLIMB.md): P2 вошёл (две строки игроков, памятка P2), тост и табличка «ВЕРХ!»
			var cp := inst as ClimbPlayground
			cp.join_p2()
			cp.hud.toast(tr("P%d сорвался: %.1f м вниз") % [2, 12.5])
			await _wait(SETTLE)
			shots["climb:p2"] = _scan(inst)
			cp.match_node.players[0]["falls"] = 3
			cp.match_node.players[0]["max_fall"] = 12.5
			ClimbMatch.best_time = 154.3
			cp.match_node.finished.emit(cp.p1, 161.8)
			await _wait(SETTLE * 2)
			shots["climb:end"] = _scan(inst)
			ClimbMatch.best_time = -1.0
		if p == CONVOY:   # «Перегон: проба машины» (CONVOY.md): P2 вошёл, P1 за рулём (памятки длиннее), предупреждение и табличка финиша
			var cv := inst as ConvoyPlayground
			cv.join_p2()
			cv.teleport(cv.p1, cv.car.door_global() + Vector3(0.0, 0.7, 0.0))
			cv.car.enter(cv.p1)
			cv.hud.refresh_help()
			cv.pit_t = 0.5
			await _wait(SETTLE)
			shots["convoy:drive"] = _scan(inst)
			cv.pit_t = 0.0
			cv.done = true
			cv.finished.emit(83.4, 4, 5)
			await _wait(SETTLE * 2)
			shots["convoy:end"] = _scan(inst)
		inst.queue_free()
		await _wait(5)
		if p == SQUAD:   # экран настроек стычки перед боем (SquadSetup): строки, пояснение, кнопки
			SquadSettings.reset()
			SquadSettings.ask = true
			var su := (load(p) as PackedScene).instantiate()
			add_child(su)
			await _wait(SETTLE * 2)
			shots["squad:setup"] = _scan(su)
			su.queue_free()
			SquadSettings.reset()
			await _wait(5)
		if p == DOMINATION:   # экран настроек в режиме «Захват точек»: своё пояснение режима, цель и время
			SquadSettings.reset()
			SquadSettings.mode = "dom"
			SquadSettings.ask = true
			var sd := (load(p) as PackedScene).instantiate()
			add_child(sd)
			await _wait(SETTLE * 2)
			shots["domination:setup"] = _scan(sd)
			sd.queue_free()
			SquadSettings.reset()
			await _wait(5)
	Stasis.set_on(false)
	for f in ["user://_probe_layout.tres", CraftEdit.save_path("_probe_layout"), "user://_probe_layout_prefs.cfg", RacePlayground.best_path,
			TrackPlayground.best_path, GauntletRun.save_path]:
		var g := ProjectSettings.globalize_path(f)
		if FileAccess.file_exists(g):
			DirAccess.remove_absolute(g)
	return shots


## Камера прохода по картинке (docs/plan-demo/look/cam.md): табло нокаута и плашка повтора KO-кино, фоторежим (подсказка, рамка).
func _look_cam_pass(shots: Dictionary) -> void:
	var ov := KoCamOverlay.new()
	add_child(ov)
	ov.show_ko(tr("KO!"), "P2", Tuning.PLAYER_COLORS[1], TranslationServer.translate("IMPACT %.1fG") % 18.4)
	ov.settle()
	await _wait(SETTLE)
	shots["look:ko_cam"] = _scan(ov)
	ov.show_replay()
	ov.settle()
	await _wait(SETTLE)
	shots["look:ko_replay"] = _scan(ov)
	ov.queue_free()
	var lcam := get_node("/root/LookCam")
	if lcam.call("toggle_photo"):
		await _wait(SETTLE)
		shots["look:photo"] = _scan(lcam.get("photo"))
		lcam.call("toggle_photo")
		await _wait(5)


## Плашки бойцов эфира (LowerThirds, docs/plan-demo/look/show.md) на отсчёте ещё едут — в кадр купола их ставим в конечное положение.
func _settle_show(inst: Node) -> void:
	var lt := inst.get_node_or_null("LowerThirds")
	if lt != null and lt.has_method("pose_full"):
		lt.call("pose_full")


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ------------------------------------------------------------------ снимок экрана

func _scan(root: Node) -> Dictionary:
	var texts := {}
	var plates: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is Control) or not (n as Control).is_visible_in_tree() or _alpha(n) < 0.05:
			continue
		var ctl := n as Control
		var r := ctl.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		if n is ColorRect or n is Panel or n is PanelContainer:
			if r.get_area() < VIEW.get_area() * 0.5:
				plates.append({"key": _key(n), "rect": r})
			continue
		var txt := ""
		if n is Label:
			txt = (n as Label).text
			r = _ink(n as Label, r)
		elif n is Button:
			txt = (n as Button).text
		elif n is RichTextLabel:
			txt = (n as RichTextLabel).get_parsed_text()
		elif n is LineEdit:
			txt = (n as LineEdit).text
		if txt.strip_edges() == "":
			continue
		texts[_key(n)] = {"rect": r, "text": txt.replace("\n", " ").left(48), "node": n}
	for k in texts:
		var tr_ := texts[k]["rect"] as Rect2
		var inside: Array = []
		for p in plates:
			var pr := p["rect"] as Rect2
			if pr.intersects(tr_) and pr.has_point(tr_.get_center()):
				inside.append(p)
		texts[k]["plates"] = inside
		texts[k].erase("node")
	return texts


## Прямоугольник самого текста: у Label с заданным размером без переноса строка может торчать за рамку узла (clip_text выключен).
func _ink(l: Label, r: Rect2) -> Rect2:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF or l.text.contains("\n") or l.clip_text:
		return r
	var need := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
	if need <= r.size.x + 0.5:
		return r
	var extra := need - r.size.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return Rect2(r.position.x - extra * 0.5, r.position.y, need, r.size.y)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return Rect2(r.position.x - extra, r.position.y, need, r.size.y)
	return Rect2(r.position.x, r.position.y, need, r.size.y)


func _alpha(n: Node) -> float:
	var a := 1.0
	var cur: Node = n
	while cur != null:
		if cur is CanvasItem:
			a *= (cur as CanvasItem).modulate.a * (cur as CanvasItem).self_modulate.a
		cur = cur.get_parent()
	return a


## Путь из индексов детей: стабилен между прогонами, в отличие от авто-имён @Label@75.
func _key(n: Node) -> String:
	var parts: PackedStringArray = []
	var cur: Node = n
	while cur != null and cur != self:
		parts.append(str(cur.get_index()))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)


# ------------------------------------------------------------------ сравнение с эталоном

func _compare(base: Dictionary, cur: Dictionary) -> Array:
	var issues: Array = []
	for screen in cur:
		if not base.has(screen):
			continue
		var b: Dictionary = base[screen]
		var c: Dictionary = cur[screen]
		var keys: Array = c.keys().filter(func(k: String) -> bool: return b.has(k))
		for k in keys:
			var rb := b[k]["rect"] as Rect2
			var rc := c[k]["rect"] as Rect2
			if not _outside(rb) and _outside(rc):
				issues.append("%s: вылез за экран «%s» (%s)" % [screen, c[k]["text"], _fmt(rc)])
			# вылез из плашки: на эталоне текст внутри плашки целиком, теперь торчит за её край
			for p in b[k]["plates"]:
				var pr := p["rect"] as Rect2
				var pcur: Variant = null
				for q in c[k]["plates"]:
					if q["key"] == p["key"]:
						pcur = q["rect"]
				if pcur != null and pr.grow(MARGIN).encloses(rb) and not (pcur as Rect2).grow(MARGIN).encloses(rc):
					issues.append("%s: вылез из плашки «%s» (текст %s, плашка %s)" % [screen, c[k]["text"], _fmt(rc), _fmt(pcur)])
					break
		# пересечения пар
		var ks: Array = keys
		for i in ks.size():
			for j in range(i + 1, ks.size()):
				var a := c[ks[i]]["rect"] as Rect2
				var d := c[ks[j]]["rect"] as Rect2
				if _overlap(a, d) < OVERLAP:
					continue
				if _overlap(b[ks[i]]["rect"], b[ks[j]]["rect"]) >= OVERLAP:
					continue   # на русском уже налезали друг на друга — не новая беда
				# виноват текст, ставший ШИРЕ русского; высота рамки зависит от размера шрифта и от письменности, а не от длины фразы
				if a.size.x <= (b[ks[i]]["rect"] as Rect2).size.x + MARGIN and d.size.x <= (b[ks[j]]["rect"] as Rect2).size.x + MARGIN:
					continue
				issues.append("%s: «%s» (%s) налез на «%s» (%s); на русском %s и %s" % [screen, c[ks[i]]["text"], _fmt(a), c[ks[j]]["text"], _fmt(d),
					_fmt(b[ks[i]]["rect"]), _fmt(b[ks[j]]["rect"])])
	return issues


func _outside(r: Rect2) -> bool:
	return r.position.x < -MARGIN or r.position.y < -MARGIN or r.end.x > VIEW.end.x + MARGIN or r.end.y > VIEW.end.y + MARGIN


func _overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	var m := minf(a.get_area(), b.get_area())
	return 0.0 if m <= 0.0 or i.get_area() <= 0.0 else i.get_area() / m


func _fmt(r: Rect2) -> String:
	return "x %d–%d, y %d–%d" % [r.position.x, r.end.x, r.position.y, r.end.y]
