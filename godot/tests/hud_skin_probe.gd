## Проба скинов HUD (scripts/ui/hud_skin.gd: трансляция / неон / LED, автор 02.10.2026 — сравнить все три в игре). Headless:
##   godot --headless --path godot --fixed-fps 60 res://tests/hud_skin_probe.tscn
## Бой кампании без выхода бойцов; скины переключаются на лету (HudSkin.set_skin(id, false) — без записи в настройки).
## Проверки (exit 1), отчёт — tests/hud_skin_probe_report.json:
##   skin_<id>      после смены: тема Root — HudSkin.theme(), таймер — панель своего скина (трансляция — косая плашка BcStyle,
##                  неон и LED — StyleBoxFlat; у неона — свечение-тень, у LED — нет), имя на панели P1 — шрифт скина «plate»,
##                  надпись диктора — плашка скина, облачко N0 — панель скина, у LED крупный текст KO — материал точек
##   skin_order     порядок H (как cycle(), без записи в настройки): трансляция → неон → LED → трансляция, подписи из LABELS
extends Node

const FIGHT := preload("res://scenes/campaign/campaign_fight.tscn")

var checks: Array = []
var info := {}


func _ready() -> void:
	var start := HudSkin.id()
	var r: Dictionary = CampaignLeague.rival(CampaignLeague.LOCAL, 0)
	var f := FIGHT.instantiate()
	f.call("setup", CampaignLeague.start_blueprint(), CampaignLeague.rival_blueprint(CampaignLeague.LOCAL, r), r,
		CampaignLeague.rival_title(r), {"entrance": false})
	add_child(f)
	(f.get_node("Match") as Match).feel_enabled = false
	for i in 30:
		await get_tree().physics_frame
	var hud := f.get_node("HUD") as Hud
	var speech: N0Speech = f.get_node("N0/Host").get("speech")
	for id in HudSkin.IDS:
		HudSkin.set_skin(id, false)
		await get_tree().process_frame
		hud.announcer.clear()   # одинаковая надпись за DEDUPE_S не дублируется — иначе осталась бы плашка прошлого скина
		hud.announcer.announce("HEAD BLOW!", Color(0, 0, 0, 0), "head")
		speech.say("Проверка скина.")
		await get_tree().process_frame
		var timer_st := hud.timer_panel.get_theme_stylebox("panel")
		var timer_ok := (timer_st is BcStyle) if id == "broadcast" else (timer_st is StyleBoxFlat)
		if id == "neon":
			timer_ok = timer_ok and (timer_st as StyleBoxFlat).shadow_size > 0
		var p1: PlayerPanel = hud.panels[0]
		var name_ok := p1.name_label.get_theme_font("font") == HudSkin.font("plate")
		var plate := hud.announcer.stack.get_child(hud.announcer.stack.get_child_count() - 1) as PanelContainer
		var ann_st := plate.get_theme_stylebox("panel")
		var ann_ok := (ann_st is BcStyle) if id == "broadcast" else (ann_st is StyleBoxEmpty if id == "neon" else ann_st is StyleBoxFlat)
		var bub := speech.bubble.get_theme_stylebox("panel")
		var bub_ok := (bub is BcStyle) if id == "broadcast" else (bub is StyleBoxFlat)
		var ko_mat := hud.ko_card.ko_label.material
		var ko_ok := (ko_mat != null) if id == "led" else (ko_mat == null)
		var theme_ok := hud.root.theme == HudSkin.theme()
		info[id] = {"theme": theme_ok, "timer": timer_ok, "name": name_ok, "announce": ann_ok, "n0": bub_ok, "ko": ko_ok}
		_check("skin_" + id, theme_ok and timer_ok and name_ok and ann_ok and bub_ok and ko_ok, str(info[id]))
	HudSkin.set_skin("broadcast", false)
	var seen: Array = []
	for i in HudSkin.IDS.size():
		HudSkin.set_skin(HudSkin.IDS[(HudSkin.IDS.find(HudSkin.id()) + 1) % HudSkin.IDS.size()], false)   # как cycle(), без записи
		seen.append(HudSkin.label())
	_check("skin_order", seen.size() == 3 and seen[0] == HudSkin.LABELS["neon"] and seen[1] == HudSkin.LABELS["led"]
		and seen[2] == HudSkin.LABELS["broadcast"], str(seen))
	HudSkin.set_skin(start, false)
	f.queue_free()
	await get_tree().physics_frame
	_finish()


func _check(id: String, ok: bool, text: String) -> void:
	checks.append({"id": id, "ok": ok, "info": text})
	print("%s %s — %s" % ["PASS" if ok else "FAIL", id, text])


func _finish() -> void:
	var ok := checks.size() == HudSkin.IDS.size() + 1
	for c in checks:
		ok = ok and bool(c["ok"])
	var fa := FileAccess.open("res://tests/hud_skin_probe_report.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"ok": ok, "checks": checks, "info": info}, "  "))
	fa.close()
	print("hud_skin_probe: %s (%d checks)" % ["OK" if ok else "FAIL", checks.size()])
	get_tree().quit(0 if ok else 1)
