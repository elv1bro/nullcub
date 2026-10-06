## Эфир в куполе Old NULL Hall (docs/plan-demo/look/show.md; LOOK_PASS.md п. 6): толпа, прожекторы ферм и свет финала. Ребёнок арены
## NullHallArena, ставит его LeagueShow (scripts/show/league_show.gd), сцену купола не трогает. Пункты панели «ВИД» (группа «Эфир»):
##   show_crowd_dim   — толпа приглушена на 40 % по яркости и на 25 % по насыщенности (crowd_sprite.gdshader, show_dim);
##   show_crowd_fx    — вспышки фотокамер на сильных ударах и KO (show_flash), «волна» на победе (show_wave), лёгкое покачивание (show_sway);
##   show_spots       — два прожектора ферм (Spot_1 / Spot_2 зала) ведут P1 / P2: плавно за центром масс, узкий конус, вдвое ярче, без
##                      теней (тень Spot_2 выключается — дешевле), видимый луч от фонаря к бойцу (show_beam.gdshader, рисованный);
##   show_final_light — последние FINAL_LAST_S с боя и Sudden Death: общий свет купола (Key, Rim, тёплые лампы, Spot_0 / Spot_3,
##                      ambient и свет тумана окружения, толпа) гаснет до FINAL_KEEP; лучи прожекторов ярче, полосы ламп (эмиссия)
##                      не трогаются.
## Выключение пункта сразу возвращает ровно прежнее (снимки «до / после» на паузе): исходные трансформы, углы, тени и энергии.
## Энергии ламп запоминаются в момент, когда свет начинает гаснуть, и возвращаются, когда он вернулся, — выход бойца (FighterEntrance)
## и пробы соседей, которые сами двигают энергию ламп вне финала, не перебиваются.
class_name HallShow
extends Node

const ID_DIM := &"show_crowd_dim"
const ID_FX := &"show_crowd_fx"
const ID_SPOTS := &"show_spots"
const ID_FINAL := &"show_final_light"

const FOLLOW := ["Spot_1", "Spot_2"]          # прожектор → P1, P2 (Spot_1 над левой половиной, Spot_2 над правой)
const SPOT_ANGLE := 8.0                        # град: узкий «ведущий» конус (в сцене 22)
const SPOT_TAU := 0.22                         # с: плавность слежения
const SPOT_ENERGY := 10.0                      # ведущий прожектор ярче (в сцене 6)…
const SPOT_ATTEN := 0.6                        # …и слабее гаснет с расстоянием (в сцене 1.0): боец — самое светлое в кадре
const BEAM_STRENGTH := 0.1
const BEAM_WIDTH := 0.3                        # радиус луча у бойца — доля пятна света
const BEAM_FINAL_MULT := 1.8
const FINAL_LAST_S := 10.0
const FINAL_KEEP := 0.6                        # доля общего света в финале (−40 %)
const FINAL_BLEND_S := 1.2
const FLASH_DECAY := 1.6                       # в секунду
const FLASH_MIN_DMG := 8.0                     # удар слабее — без вспышек
const WAVE_S := 2.4                            # волна проходит зал слева направо
const WAVE_PASSES := 2
const BEAM_SHADER := preload("res://scripts/show/show_beam.gdshader")

var arena: Node3D
var match_node: Match
var flash := 0.0                               # 0..1 — вспышки камер сейчас
var wave := -1.0                               # 0..WAVE_PASSES — где волна; < 0 — нет
var final_k := 1.0                             # множитель общего света (1 — как было)
var spots_on := false
var _look: Node
var _crowd: ShaderMaterial
var _spots: Array = []                         # [{light, xf, angle, shadow, beam, target, has}]
var _final_lights: Array[Light3D] = []
var _env: Environment
var _dim_base := {}                            # Object → исходная энергия (пока свет финала погашен)


## Поставить эфир купола в арену (повторно — ничего).
static func attach(hall: Node3D) -> HallShow:
	var hs := hall.get_node_or_null("HallShow") as HallShow
	if hs != null:
		return hs
	hs = HallShow.new()
	hs.name = "HallShow"
	hs.arena = hall
	hall.add_child(hs)
	return hs


func _ready() -> void:
	if arena == null:
		arena = get_parent() as Node3D
	_look = get_node_or_null("/root/Look")
	for mmi in arena.find_children("*", "MultiMeshInstance3D", true, false):
		if mmi.is_in_group("null_hall_crowd") and (mmi as MultiMeshInstance3D).material_override is ShaderMaterial:
			_crowd = (mmi as MultiMeshInstance3D).material_override
	var lights := arena.get_node_or_null("Lights")
	if lights != null:
		for l in lights.get_children():
			if not (l is Light3D):
				continue
			if FOLLOW.has(String(l.name)):
				var sl := l as SpotLight3D
				_spots.append({"light": sl, "xf": sl.transform, "angle": sl.spot_angle, "shadow": sl.shadow_enabled,
					"energy": sl.light_energy, "atten": sl.spot_attenuation, "beam": _make_beam(), "target": Vector3.ZERO, "has": false})
			else:
				_final_lights.append(l)
	var we := arena.get_node_or_null("Environment") as WorldEnvironment
	_env = we.environment if we != null else null
	if _look != null:
		_look.changed.connect(_on_look)
	_apply_dim()
	_apply_fx()
	_apply_spots()
	_find_match.call_deferred()


func _exit_tree() -> void:
	# окружение и материал толпы — ресурсы сцены купола (кэш загрузчика): вернуть как было
	_set_final(1.0)
	if _crowd != null:
		for p in ["show_dim", "show_flash", "show_sway"]:
			_crowd.set_shader_parameter(p, 0.0)
		_crowd.set_shader_parameter("show_light", 1.0)
		_crowd.set_shader_parameter("show_wave", -1.0)


func _on_look(id: StringName, _on: bool) -> void:
	match id:
		ID_DIM:
			_apply_dim()
		ID_FX:
			_apply_fx()
		ID_SPOTS:
			_apply_spots()
		ID_FINAL:
			_set_final(_final_target())


func _is(id: StringName) -> bool:
	return _look == null or bool(_look.call("on", id))


func _find_match() -> void:
	var parent := arena.get_parent()
	for m in get_tree().get_nodes_in_group(Match.GROUP):
		if m is Match and (parent == null or parent.is_ancestor_of(m)):
			bind(m as Match)
			return


func bind(m: Match) -> void:
	match_node = m
	if m == null:
		return
	m.hit.connect(func(_v: Doll, _a: Node, dmg: float, _k: String, _p: Vector3) -> void:
		if dmg >= FLASH_MIN_DMG:
			flash = maxf(flash, clampf((dmg - FLASH_MIN_DMG) / 18.0 + 0.3, 0.0, 0.85)))
	m.ko.connect(func(_v: Doll, _a: Node, _r: Dictionary) -> void: flash = 1.0)
	m.match_over.connect(func(w: Doll, _r: Dictionary) -> void:
		flash = 1.0
		if w != null:
			wave = 0.0)
	m.phase_changed.connect(func(p: int) -> void:
		if p == Match.Phase.COUNTDOWN:
			wave = -1.0)
	_apply_spots()


# ---------------------------------------------------------------- толпа

func _apply_dim() -> void:
	if _crowd != null:
		_crowd.set_shader_parameter("show_dim", 1.0 if _is(ID_DIM) else 0.0)


func _apply_fx() -> void:
	if _crowd == null:
		return
	var on := _is(ID_FX)
	_crowd.set_shader_parameter("show_sway", 1.0 if on else 0.0)
	_crowd.set_shader_parameter("show_flash", flash if on else 0.0)
	_crowd.set_shader_parameter("show_wave", fposmod(wave, 1.0) if on and wave >= 0.0 else -1.0)


## Вспышки вручную (пробы, снимки): 0..1.
func flash_now(amount := 1.0) -> void:
	flash = clampf(amount, 0.0, 1.0)
	_apply_fx()


## Волна вручную (пробы, снимки): pos 0..1 — где она сейчас.
func wave_at(pos: float) -> void:
	wave = clampf(pos, 0.0, 0.999)
	_apply_fx()


# ---------------------------------------------------------------- прожекторы

func _make_beam() -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter("strength", BEAM_STRENGTH)
	var mi := MeshInstance3D.new()
	mi.name = "Beam"
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.top_level = true
	mi.visible = false
	add_child(mi)
	return mi


func _apply_spots() -> void:
	spots_on = _is(ID_SPOTS)
	for s in _spots:
		var l := s["light"] as SpotLight3D
		l.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF if spots_on else Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		if spots_on:
			l.spot_angle = SPOT_ANGLE
			l.spot_attenuation = SPOT_ATTEN
			l.shadow_enabled = false
		else:
			l.transform = s["xf"]
			l.spot_angle = float(s["angle"])
			l.shadow_enabled = bool(s["shadow"])
			l.light_energy = float(s["energy"])
			l.spot_attenuation = float(s["atten"])
			(s["beam"] as MeshInstance3D).visible = false
			s["has"] = false
	if spots_on:
		_update_spots(0.0, true)


## Цели прожекторов: P1 и P2 (player_index 0 / 1) — центр масс с интерполяцией физики.
func _targets() -> Array:
	var out := [null, null]
	if match_node == null or not is_instance_valid(match_node):
		return out
	for d in match_node.dolls():
		var dd := d as Doll
		if dd == null or not is_instance_valid(dd) or not dd.is_inside_tree():
			continue
		if dd.player_index >= 0 and dd.player_index < 2 and out[dd.player_index] == null:
			out[dd.player_index] = dd.centre_of_mass(true)
	return out


func _update_spots(dt: float, snap := false) -> void:
	var tg := _targets()
	var k := 1.0 if snap else 1.0 - exp(-dt / SPOT_TAU)
	for i in _spots.size():
		var s: Dictionary = _spots[i]
		var l := s["light"] as SpotLight3D
		var beam := s["beam"] as MeshInstance3D
		if tg[i] == null:
			if not bool(s["has"]):
				beam.visible = false
				continue
		else:
			var want := tg[i] as Vector3
			s["target"] = want if (snap or not bool(s["has"])) else (s["target"] as Vector3).lerp(want, k)
			s["has"] = true
		var src: Vector3 = (l.get_parent() as Node3D).global_transform * (s["xf"] as Transform3D).origin
		var dst: Vector3 = s["target"]
		var dir := dst - src
		var len := dir.length()
		if len < 0.5:
			continue
		l.global_transform = Transform3D(Basis.looking_at(dir / len, Vector3.UP), src)
		l.light_energy = SPOT_ENERGY   # каждый кадр: выход бойца гасит лампы зала, а ведущий прожектор остаётся на бойце
		# луч: цилиндр по оси Y (верх — у фонаря), радиус у бойца — чуть уже пятна света
		var y := -dir / len
		var x := y.cross(Vector3.FORWARD)
		if x.length() < 0.01:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var z := x.cross(y).normalized()
		var r := len * tan(deg_to_rad(SPOT_ANGLE)) * BEAM_WIDTH
		beam.global_transform = Transform3D(Basis(x * r, y * len, z * r), src + dir * 0.5)
		beam.visible = true
		var mult := lerpf(BEAM_FINAL_MULT, 1.0, (final_k - FINAL_KEEP) / (1.0 - FINAL_KEEP))
		(beam.material_override as ShaderMaterial).set_shader_parameter("strength", BEAM_STRENGTH * mult)


# ---------------------------------------------------------------- свет финала

func _final_target() -> float:
	if not _is(ID_FINAL) or match_node == null or not is_instance_valid(match_node):
		return 1.0
	var p := match_node.phase
	if p == Match.Phase.SUDDEN_DEATH or (p == Match.Phase.FIGHT and match_node.time_left_s() <= FINAL_LAST_S):
		return FINAL_KEEP
	return 1.0


## Поставить множитель общего света (запоминает энергии при первом погашении, возвращает их при 1).
func _set_final(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if is_equal_approx(k, 1.0):
		for o in _dim_base:
			if is_instance_valid(o):
				if o is Light3D:
					(o as Light3D).light_energy = float(_dim_base[o])
				elif o is Environment:
					var b: Array = _dim_base[o]
					(o as Environment).ambient_light_energy = float(b[0])
					(o as Environment).fog_light_energy = float(b[1])
		_dim_base.clear()
		final_k = 1.0
		if _crowd != null:
			_crowd.set_shader_parameter("show_light", 1.0)
		return
	if _dim_base.is_empty():
		for l in _final_lights:
			if is_instance_valid(l):
				_dim_base[l] = l.light_energy
		if _env != null:
			_dim_base[_env] = [_env.ambient_light_energy, _env.fog_light_energy]
	for o in _dim_base:
		if not is_instance_valid(o):
			continue
		if o is Light3D:
			(o as Light3D).light_energy = float(_dim_base[o]) * k
		elif o is Environment:
			var b: Array = _dim_base[o]
			(o as Environment).ambient_light_energy = float(b[0]) * k
			(o as Environment).fog_light_energy = float(b[1]) * k
	if _crowd != null:
		_crowd.set_shader_parameter("show_light", k)   # толпа без света (unshaded) — гаснет вместе с залом
	final_k = k


## Финал вручную (пробы, снимки): сразу погасить / вернуть.
func force_final(on: bool) -> void:
	_set_final(FINAL_KEEP if on and _is(ID_FINAL) else 1.0)


func _process(delta: float) -> void:
	# время без масштаба: хит-стоп, замедление KO и СТАЗИС не тормозят свет (и детерминированно под --fixed-fps / --write-movie)
	var dt := clampf(delta / maxf(Engine.time_scale, 0.01), 0.0, 0.1)
	if spots_on:
		_update_spots(dt)
	var want := _final_target()
	if not is_equal_approx(want, final_k):
		var step := dt * (1.0 - FINAL_KEEP) / FINAL_BLEND_S
		_set_final(move_toward(final_k, want, step))
	if flash > 0.0:
		flash = maxf(0.0, flash - FLASH_DECAY * dt)
	if wave >= 0.0:
		wave += dt / WAVE_S
		if wave >= float(WAVE_PASSES):
			wave = -1.0
	if _crowd != null and _is(ID_FX):
		_crowd.set_shader_parameter("show_flash", flash)
		_crowd.set_shader_parameter("show_wave", fposmod(wave, 1.0) if wave >= 0.0 else -1.0)
