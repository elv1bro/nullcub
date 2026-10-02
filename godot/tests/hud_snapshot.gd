## Снимки HUD боя (scenes/ui/hud.tscn по R20) без реального боя: стаб Match (узел с теми же сигналами и dolls())
## проигрывает сценарий FIGHT! → удары → HEAD BLOW! → 3 HIT COMBO! → SUDDEN DEATH → KO → match_over и пишет
##   tests/hud_fight.png         — панели игроков, таймер, комбо ×3, стек диктора (HEAD BLOW! + 3 HIT COMBO!);
##   tests/hud_sudden_death.png  — красная SUDDEN DEATH под таймером, надпись диктора;
##   tests/hud_ko.png            — карточка KO (брызги, KO!, BETTER LUCK NEXT TIME!) при Engine.time_scale 0.25;
##   tests/hud_results.png       — итоги: P1 WINS!, места, статистика, медали, кнопки REMATCH / MAIN MENU;
##   tests/hud_results_draw.png  — после REMATCH двойной KO (оба в одном тике, Match.build_results): match_over(null) — «DRAW!» без
##                                 короны, P1 и P2 оба «1ST» с KO на портретах, корона раунда никому не прибавилась.
## Фон — затемнённый и размытый tests/playground_action.png (если нет — тёмный градиент).
## Печатает JSON и пишет tests/hud_report.json (панели = игроки, таймер, карточка скрыта к итогам, итоги видны,
## REMATCH зовёт restart() стаба). Exit 0/1.
## Запуск: godot --path . --resolution 1280x720 --always-on-top res://tests/hud_snapshot.tscn -- "players=2,out=res://tests/"
##   players=2|3|4, out=<папка>, suffix=<строка к именам файлов>, skin=broadcast|neon|led — скин HUD, hold=1 — не выходить
##   (смотреть глазами).
extends Node

const HudScene: PackedScene = preload("res://scenes/ui/hud.tscn")
const BG_PATH := "res://tests/playground_action.png"
const NO_COLOR := Color(0, 0, 0, 0)


class FakeDoll extends Node:
	var player_index := 0
	var alive := true


class MatchStub extends Node:
	signal phase_changed(phase: int)
	signal time_left(seconds: float)
	signal announce(text: String, color: Color, kind: String)
	signal hp_changed(doll: Node, hp: float, max_hp: float)
	signal combo_changed(doll: Node, n: int)
	signal ko(victim: Node, attacker: Node, record: Dictionary)
	signal match_over(winner: Node, results: Dictionary)
	var fake_dolls: Array = []
	var restarted := 0

	func dolls() -> Array:
		return fake_dolls

	func restart() -> void:
		restarted += 1
		phase_changed.emit(0)

	func hit_feel(_strength: float, _position: Vector3) -> void:
		pass


var cfg := {"players": 2.0, "hold": 0.0}
var out_dir := "res://tests/"
var suffix := ""
var hud: Hud
var stub: MatchStub
var dolls: Array = []
var report := {"ok": true, "checks": [], "shots": []}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		for kv in arg.split(","):
			var p := kv.split("=")
			if p.size() != 2:
				continue
			if p[0] == "out":
				out_dir = p[1]
			elif p[0] == "suffix":
				suffix = p[1]
			elif p[0] == "skin":   # скин HUD (HudSkin: broadcast / neon / led) на время снимка, без записи в настройки
				HudSkin.set_skin(p[1], false)
			elif cfg.has(p[0]):
				cfg[p[0]] = float(p[1])
	_background()
	stub = MatchStub.new()
	stub.name = "MatchStub"
	add_child(stub)
	var n := clampi(int(cfg["players"]), 2, 4)
	for i in range(n):
		var d := FakeDoll.new()
		d.name = "P%d" % (i + 1)
		d.player_index = i
		stub.add_child(d)
		dolls.append(d)
	stub.fake_dolls = dolls
	hud = HudScene.instantiate()
	add_child(hud)
	report["players"] = n
	report["resolution"] = var_to_str(get_viewport().get_visible_rect().size)
	report["window"] = var_to_str(DisplayServer.window_get_size())
	_run()


func _background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var tex: Texture2D = load(BG_PATH) as Texture2D if ResourceLoader.exists(BG_PATH) else null
	if tex == null:
		var cr := ColorRect.new()
		cr.color = Color(0.09, 0.075, 0.06)
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(cr)
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float radius = 3.0;
uniform float dark = 0.42;
void fragment() {
	vec4 acc = vec4(0.0);
	float n = 0.0;
	for (int i = -3; i <= 3; i++) {
		for (int j = -3; j <= 3; j++) {
			acc += texture(TEXTURE, UV + vec2(float(i), float(j)) * TEXTURE_PIXEL_SIZE * radius);
			n += 1.0;
		}
	}
	COLOR = vec4((acc / n).rgb * dark, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	tr.material = mat
	layer.add_child(tr)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _check(id: String, ok: bool, value: Variant = null) -> void:
	report["checks"].append({"id": id, "ok": ok, "value": value})
	if not ok:
		report["ok"] = false


func _capture(base: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join(base.replace(".png", suffix + ".png"))
	var err := img.save_png(path)
	report["shots"].append(path)
	print("saved ", path, " (", err, ")")
	_check("shot_" + base, err == OK, path)
	# save_png блокирует кадр (≈1 с на 1080p): пропускаем «длинный» кадр, чтобы он не съел таймеры и твины сцены
	await get_tree().process_frame
	await get_tree().process_frame


func _results(winner: FakeDoll) -> Dictionary:
	var places: Array = dolls.duplicate()
	places.erase(winner)
	places.insert(0, winner)
	if places.size() == 4:
		places = [dolls[0], dolls[2], dolls[1], dolls[3]]
	var stats: Dictionary = {}
	var seed_vals := [
		{"kos": 1, "damage_dealt": 100.0, "damage_taken": 9.0, "hardest_hit": 34.5, "air_time": 6.2, "wall_collisions": 3, "weapon_hits": 2, "rotations": 4, "max_speed": 14.2, "flight_distance": 9.1, "combo_max": 3, "combo_score": 412},
		{"kos": 0, "damage_dealt": 9.0, "damage_taken": 100.0, "hardest_hit": 9.0, "air_time": 11.8, "wall_collisions": 7, "weapon_hits": 0, "rotations": 9, "max_speed": 19.7, "flight_distance": 14.3, "combo_max": 1, "combo_score": 9},
		{"kos": 0, "damage_dealt": 46.0, "damage_taken": 30.0, "hardest_hit": 21.0, "air_time": 4.1, "wall_collisions": 2, "weapon_hits": 3, "rotations": 1, "max_speed": 11.0, "flight_distance": 5.0, "combo_max": 2, "combo_score": 120},
		{"kos": 0, "damage_dealt": 12.0, "damage_taken": 55.0, "hardest_hit": 12.0, "air_time": 7.9, "wall_collisions": 5, "weapon_hits": 1, "rotations": 6, "max_speed": 16.3, "flight_distance": 8.8, "combo_max": 1, "combo_score": 12},
	]
	for i in range(dolls.size()):
		stats[dolls[i]] = seed_vals[i]
	var medals: Dictionary = {"Winner": winner, "Hardest Hit": winner, "Frequent Flyer": dolls[1], "Wall Inspector": dolls[1], "Weapon Master": dolls[mini(2, dolls.size() - 1)], "Acrobat": dolls[1]}
	return {"places": places, "stats": stats, "medals": medals}


## Ничья двойным KO как у Match.build_results: P1 и P2 выбыли в одном тике последними (ranks 0, 0), остальные — раньше; медали Winner нет.
func _draw_results() -> Dictionary:
	var r := _results(dolls[0])
	var places: Array = dolls.duplicate()
	var ranks: Array = [0, 0]
	var ko_records: Array = []
	for i in range(2, places.size()):
		ranks.append(i)
	for d in places:
		ko_records.append({"victim": d, "kind": "head"})
	var medals: Dictionary = r["medals"]
	medals.erase("Winner")
	return {"places": places, "ranks": ranks, "ko_records": ko_records, "stats": r["stats"], "medals": medals, "winner": null, "draw": true, "reason": "ko"}


func _run() -> void:
	var p1: FakeDoll = dolls[0]
	var p2: FakeDoll = dolls[1]
	await _wait(0.25)
	hud.bind(stub)
	stub.phase_changed.emit(0)
	stub.time_left.emit(90.0)
	for d in dolls:
		stub.hp_changed.emit(d, 100.0, 100.0)
	await _wait(0.2)
	_check("panels_created", hud.panels.size() == dolls.size(), hud.panels.size())
	stub.announce.emit("FIGHT!", NO_COLOR, "fight")
	stub.phase_changed.emit(1)
	await _wait(0.5)
	stub.hp_changed.emit(p2, 88.0, 100.0)
	stub.combo_changed.emit(p1, 1)
	stub.announce.emit("BODY BLOW!", NO_COLOR, "body")
	stub.time_left.emit(78.0)
	await _wait(0.45)
	stub.hp_changed.emit(p1, 91.0, 100.0)
	if dolls.size() > 2:
		stub.hp_changed.emit(dolls[2], 70.0, 100.0)
	if dolls.size() > 3:
		stub.hp_changed.emit(dolls[3], 45.0, 100.0)
		stub.combo_changed.emit(dolls[2], 2)
	await _wait(0.4)
	stub.hp_changed.emit(p2, 74.0, 100.0)
	stub.combo_changed.emit(p1, 2)
	stub.announce.emit("HEAD BLOW!", NO_COLOR, "head")
	stub.time_left.emit(71.0)
	await _wait(0.25)
	stub.hp_changed.emit(p2, 55.0, 100.0)
	stub.combo_changed.emit(p1, 3)
	stub.announce.emit("3 HIT COMBO!", NO_COLOR, "combo")
	await _wait(0.22)
	_check("announcer_stack_le_2", hud.announcer.stack.get_child_count() <= 2, hud.announcer.stack.get_child_count())
	_check("timer_text", hud.timer_label.text == "01:11", hud.timer_label.text)
	await _capture("hud_fight.png")
	await _wait(0.5)
	stub.phase_changed.emit(2)
	stub.announce.emit("SUDDEN DEATH", NO_COLOR, "sudden_death")
	stub.time_left.emit(84.0)
	stub.combo_changed.emit(p1, 0)
	await _wait(0.3)
	_check("sudden_death_visible", hud.sudden_death_label.visible)
	await _capture("hud_sudden_death.png")
	await _wait(0.5)
	# KO-замедление как в этапе 09: карточка, диктор и полосы HP идут по реальному времени, а не по time_scale
	Engine.time_scale = 0.25
	stub.hp_changed.emit(p2, 0.0, 100.0)
	stub.announce.emit("KO!", NO_COLOR, "ko")
	stub.ko.emit(p2, p1, {"time": 96.0, "damage": 34.5, "weapon": "hammer"})
	stub.phase_changed.emit(3)
	await _wait(0.45)
	_check("ko_card_visible", hud.ko_card.visible)
	_check("ko_card_remaining_realtime", hud.ko_card.remaining_s() > 0.5 and hud.ko_card.remaining_s() < 0.85, hud.ko_card.remaining_s())
	await _capture("hud_ko.png")
	await _wait(0.7)
	Engine.time_scale = 1.0
	stub.match_over.emit(p1, _results(p1))
	await _wait(1.3)
	_check("ko_card_hidden_at_results", not hud.ko_card.visible)
	_check("results_visible", hud.results.visible)
	_check("winner_crown", int(hud.wins.get(0, 0)) == 1, hud.wins)
	await _capture("hud_results.png")
	# REMATCH → restart() стаба → фаза COUNTDOWN → итоги скрыты, панели сброшены
	hud.results.rematch_btn.pressed.emit()
	await _wait(0.1)
	_check("rematch_calls_restart", stub.restarted == 1, stub.restarted)
	_check("results_hidden_after_rematch", not hud.results.visible)
	var p2_panel: PlayerPanel = hud.panels[1]
	_check("panel_reset_after_rematch", p2_panel.hp_bar.hp == 100.0 and not p2_panel.portrait.knocked_out, p2_panel.hp_bar.hp)
	# двойной KO в одном тике → ничья: match_over(null) — короны раунда никому, «DRAW!» без короны, оба «1ST» с KO
	stub.phase_changed.emit(1)
	await _wait(0.3)
	for d in dolls:
		stub.hp_changed.emit(d, 0.0, 100.0)
	stub.announce.emit("KO!", NO_COLOR, "ko")
	stub.ko.emit(p1, p2, {"time": 42.5, "damage": 6.0, "weapon": ""})
	stub.ko.emit(p2, p1, {"time": 42.5, "damage": 6.0, "weapon": ""})
	stub.phase_changed.emit(3)
	stub.match_over.emit(null, _draw_results())
	await _wait(1.6)
	_check("draw_no_crown", int(hud.wins.get(0, 0)) == 1 and int(hud.wins.get(1, 0)) == 0, hud.wins)
	_check("draw_results_visible", hud.results.visible)
	_check("draw_label", hud.results.winner_name.text == "DRAW!" and not hud.results.crown.visible, hud.results.winner_name.text)
	var firsts := 0
	var ko_marks := 0
	for col in hud.results.places_row.get_children():
		for c in col.get_children():
			if c is Label and (c as Label).text == "1ST":
				firsts += 1
			if c is Portrait and (c as Portrait).knocked_out:
				ko_marks += 1
	_check("draw_places_shared", firsts == 2, firsts)
	_check("draw_ko_marks", ko_marks == dolls.size(), ko_marks)
	await _capture("hud_results_draw.png")
	var json := JSON.stringify(report, "  ")
	print(json)
	var f := FileAccess.open(out_dir.path_join("hud_report.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(json)
		f.close()
	if cfg["hold"] > 0.5:
		return
	get_tree().quit(0 if report["ok"] else 1)
