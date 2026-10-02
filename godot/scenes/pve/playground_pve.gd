## Площадка PvE «волны на Свалке» (scenes/playground_pve.tscn; CONCEPT_V2 §29 проба 2, LORE.md «Враги»): арена Свалки + P1 (клён,
## WeaponPickup, ArmAssist — рука мышью) + оружие рядом + WaveDirector (scripts/pve/wave_director.gd: волны из мусорного желоба,
## урон через ядро Match) + PveHud + камера DynamicCamera с группой pve_focus (PveFocus: игроки и ближайшие враги).
## P2 (орех, стрелки) — кооп: в сцене есть, по умолчанию убирается; F2 — включить/выключить и начать заново.
## Эффекты удара (HitFxDirector, SfxDirector, крит) создаёт сам Match — WaveDirector его наследник; F10 — пресет FX по кругу
## (FxPreset: full / reduced / off, как на PvP-площадке), подпись — дикторской надписью HUD.
## Здесь только поведение: R — заново (WaveDirector.restart), F2 — кооп, F10 — FX, Esc — выход; пропасть (ScrapArena.body_fell) — KO куклы,
## чья часть упала (игрока или врага; оторванные детали и оружие падают дальше, их хозяин не страдает).
class_name PvePlayground
extends Node3D

## Кооп между перезагрузками сцены (F2).
static var coop := false

@onready var director: WaveDirector = $WaveDirector
@onready var hud: PveHud = $HUD
@onready var cam: DynamicCamera = $Camera

var arena: Node3D


func _ready() -> void:
	for c in get_children():
		if c is Node3D and c.has_method("spawn_points"):
			arena = c
			break
	if arena != null and arena.has_signal("body_fell"):
		arena.connect("body_fell", _on_body_fell)
	var p2 := get_node_or_null("P2")
	if p2 != null and not coop:
		remove_child(p2)
		p2.free()
	hud.bind(director)
	director.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			cam.snap())
	_set_gi_dynamic(get_node_or_null("Weapons"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				director.restart()
			KEY_F2:
				coop = not coop
				get_tree().reload_current_scene()
			KEY_F10:
				FxPreset.cycle(get_tree())
				hud.announcer.announce(FxPreset.label(), Color(0.9, 0.9, 0.95), "")
			KEY_M:
				hud.announcer.announce(get_node("/root/GameAudio").toggle_music(), Color(0.9, 0.9, 0.95), "")
			KEY_N:
				hud.announcer.announce(get_node("/root/GameAudio").toggle_crowd(), Color(0.9, 0.9, 0.95), "")
			KEY_ESCAPE:
				preload("res://scenes/menu/test_menu.gd").back_to_menu(get_tree())   # тестовое меню сборки (или выход)
			_:
				# 1–7 — площадки хаба (таблица ARENA_KEYS в scenes/playground.gd: одна строка там — клавиша работает везде)
				var path: String = preload("res://scenes/playground.gd").scene_for_key(event.physical_keycode)
				if path != "" and path != scene_file_path:
					get_tree().change_scene_to_file(path)


func _on_body_fell(body: Node3D) -> void:
	var d := body.get_parent() as Doll
	if d == null or not d.alive or not d.parts.values().has(body):
		return   # оружие, пропсы, оторванные детали и части уже разбитой куклы
	d.knock_out()   # KO kind "self": враг засчитывается WaveDirector как «в пропасти», игрок — выбыл


func _set_gi_dynamic(n: Node) -> void:
	if n == null:
		return
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for c in n.get_children():
		_set_gi_dynamic(c)
