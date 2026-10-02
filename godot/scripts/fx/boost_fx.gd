## Эффекты ускорения и раскрутки куклы («лёгкие варианты» из готовых частей, COMBAT_CHARGE.md; выбирает автор). Нода — ребёнок Doll
## (Match.register вешает на каждую куклу), пока Doll.is_dashing() или is_spinning() — показывает выбранный пресет:
##   ribbons — ленты FlightTrail за ЦМ, кистями и стопами в цвет игрока (без дыма — не путать с отлётом после удара);
##   ghosts  — послеобразы AfterimageTrail: призрачные копии позы раз в GHOST_INTERVAL_MS, гаснут за GHOST_FADE_MS;
##   dust    — клубы dust_puff из-под ног, пока земля ближе DUST_GROUND_M (луч вниз от нижней части);
##   lines   — линии скорости ScreenFx вокруг куклы (экран общий: линии у одной куклы, последней, что ускорялась);
##   tint    — рубашка куклы (материалы Shirt*) светится цветом игрока.
## Пресет статический, как FxPreset: F11 на площадке (scenes/playground.gd) — по кругу PRESET_ORDER, тост «Ускорение: …». Уважает пресет
## FX игрока (F10): reduced — без линий и подсветки, off — ещё и без послеобразов. Время — нескалированное (FxClock), hit-stop не замораживает.
class_name BoostFx
extends Node

const GROUP := "boost_fx"
const NODE_NAME := "BoostFx"
const DUST_PUFF: PackedScene = preload("res://scenes/fx/dust_puff.tscn")

const RIBBON_PARTS := ["Hand", "Foot"]
const GHOST_INTERVAL_MS := 70.0
const GHOST_FADE_MS := 230.0
const GHOST_MIN_STEP_M := 0.12
const GHOST_ALPHA := 0.4
const DUST_INTERVAL_MS := 90.0
const DUST_GROUND_M := 0.55
const DUST_MAX := 8
const LINES_REFRESH_MS := 120.0
const LINES_MS := 220.0
const LINES_ALPHA := 0.5
const TINT_ENERGY := 3.0
const TINT_RATE := 9.0                  # 1/с: подсветка плавно набирает и гаснет

const PRESETS := {
	"off": {"label": "нет", "ribbons": false, "ghosts": false, "dust": false, "lines": false, "tint": false},
	"ribbons": {"label": "ленты", "ribbons": true, "ghosts": false, "dust": false, "lines": false, "tint": false},
	"ghosts": {"label": "послеобразы", "ribbons": false, "ghosts": true, "dust": false, "lines": false, "tint": false},
	"ribbons_ghosts": {"label": "ленты + послеобразы", "ribbons": true, "ghosts": true, "dust": false, "lines": false, "tint": false},
	"dust": {"label": "пыль", "ribbons": false, "ghosts": false, "dust": true, "lines": false, "tint": false},
	"lines": {"label": "линии скорости", "ribbons": false, "ghosts": false, "dust": false, "lines": true, "tint": false},
	"ribbons_lines": {"label": "ленты + линии скорости", "ribbons": true, "ghosts": false, "dust": false, "lines": true, "tint": false},
	"tint": {"label": "подсветка", "ribbons": false, "ghosts": false, "dust": false, "lines": false, "tint": true},
	"all": {"label": "всё сразу", "ribbons": true, "ghosts": true, "dust": true, "lines": true, "tint": true},
}
const PRESET_ORDER := ["ribbons_lines", "off", "ribbons", "ghosts", "ribbons_ghosts", "dust", "lines", "tint", "all"]
const PRESET_DEFAULT := "ribbons_lines"

static var preset: String = PRESET_DEFAULT

var doll: Doll
var _trail: FlightTrail
var _ghost: AfterimageTrail
var _on := false
var _next_dust_ms := 0.0
var _next_lines_ms := 0.0
var _clock_ms := 0.0
var _puffs: Array = []
var _tint_k := 0.0
var _tint_mats: Array = []              # [BaseMaterial3D, emission_enabled до подсветки]
var _tint_ready := false
var _exclude: Array = []                # RID частей куклы для луча пыли


## Вешает BoostFx на куклу (один раз). Возвращает ноду.
static func attach(d: Doll) -> BoostFx:
	if d == null:
		return null
	var old := d.get_node_or_null(NODE_NAME)
	if old is BoostFx:
		return old
	var n := BoostFx.new()
	n.name = NODE_NAME
	n.doll = d
	d.add_child(n)
	return n


static func values(name: String = "") -> Dictionary:
	return PRESETS.get(name if name != "" else preset, PRESETS[PRESET_DEFAULT]) as Dictionary


static func label() -> String:
	return "Ускорение: " + String(values().get("label", ""))


## Следующий пресет по кругу PRESET_ORDER (все BoostFx в дереве подхватывают сразу). Возвращает имя.
static func cycle(tree: SceneTree = null) -> String:
	var i := PRESET_ORDER.find(preset)
	return set_preset(String(PRESET_ORDER[(i + 1) % PRESET_ORDER.size()]), tree)


static func set_preset(name: String, tree: SceneTree = null) -> String:
	if PRESETS.has(name):
		preset = name
	if tree != null:
		for n in tree.get_nodes_in_group(GROUP):
			(n as BoostFx).refresh()
	return preset


func _ready() -> void:
	add_to_group(GROUP)
	FxClock.ensure(self)


func _exit_tree() -> void:
	_end()
	_restore_tint()


## Какие эффекты включены с учётом пресета FX игрока (F10): reduced — без линий и подсветки, off — ещё и без послеобразов.
func _flag(name: String) -> bool:
	if not bool(values().get(name, false)):
		return false
	match FxPreset.current:
		FxPreset.REDUCED:
			return name != "lines" and name != "tint"
		FxPreset.OFF:
			return name != "lines" and name != "tint" and name != "ghosts"
	return true


## Пресет сменили на лету: идущие эффекты пересобираются.
func refresh() -> void:
	if _on:
		_end()
		_begin()


func _process(delta: float) -> void:
	var real_ms := FxClock.real_delta(delta) * 1000.0
	_clock_ms += real_ms
	var want := doll != null and is_instance_valid(doll) and doll.alive and (doll.is_dashing() or doll.is_spinning())
	if want and not _on:
		_begin()
	elif not want and _on:
		_end()
	if _on:
		if _flag("dust"):
			_tick_dust()
		if _flag("lines"):
			_tick_lines()
	_tick_tint(delta, want and _flag("tint"))


func _colour() -> Color:
	var c: Color = Tuning.PLAYER_COLORS[clampi(doll.player_index, 0, Tuning.PLAYER_COLORS.size() - 1)]
	return c


func _begin() -> void:
	_on = true
	var base := _colour()
	if _flag("ribbons"):
		_trail = FlightTrail.new()
		_trail.name = "BoostTrail"
		add_child(_trail)
		_trail.setup(doll, RIBBON_PARTS, true, 1.0e9, base.lerp(Color.WHITE, 0.45), 0.0, null)
	if _flag("ghosts"):
		_ghost = AfterimageTrail.new()
		_ghost.name = "BoostGhosts"
		add_child(_ghost)
		var gc := base.lerp(Color.WHITE, 0.3)
		gc.a = GHOST_ALPHA
		_ghost.endless = true
		_ghost.setup(doll, AfterimageTrail.MAX_SNAPSHOTS, GHOST_INTERVAL_MS, GHOST_FADE_MS, 1.0e9, gc, GHOST_MIN_STEP_M)


func _end() -> void:
	_on = false
	if _trail != null and is_instance_valid(_trail):
		_trail.finish()
	_trail = null
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.finish()
	_ghost = null


# --- пыль ---

func _tick_dust() -> void:
	if _clock_ms < _next_dust_ms or doll.parts.is_empty():
		return
	_next_dust_ms = _clock_ms + DUST_INTERVAL_MS
	var low: RigidBody3D = null
	for b in doll.parts.values():
		var rb := b as RigidBody3D
		if rb != null and is_instance_valid(rb) and (low == null or rb.global_position.y < low.global_position.y):
			low = rb
	if low == null or not doll.is_inside_tree():
		return
	if _exclude.is_empty():
		for b in doll.parts.values():
			_exclude.append((b as RigidBody3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(low.global_position, low.global_position + Vector3.DOWN * DUST_GROUND_M)
	q.exclude = _exclude
	var hit := doll.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var v := FlightTrail.com_velocity(doll)
	var k := clampf(v.length() / 9.0, 0.35, 1.2)
	_puff(hit["position"] as Vector3, hit["normal"] as Vector3, k)


func _puff(pos: Vector3, normal: Vector3, k: float) -> void:
	while _puffs.size() >= DUST_MAX:
		var old: Variant = _puffs.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var p := DUST_PUFF.instantiate() as GPUParticles3D
	if p == null:
		return
	doll.get_parent().add_child(p)
	var n := normal.normalized() if normal.length_squared() > 1e-6 else Vector3.UP
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	p.global_transform = Transform3D(Basis.looking_at(-n, up), pos + n * 0.05)
	var pm := p.process_material as ParticleProcessMaterial
	if pm != null:
		pm = pm.duplicate() as ParticleProcessMaterial
		pm.initial_velocity_min *= k * 0.8
		pm.initial_velocity_max *= k * 0.8
		pm.scale_min *= 1.7
		pm.scale_max *= 1.7
		p.process_material = pm
	p.amount_ratio = clampf(0.6 * k, 0.3, 0.8)
	_puffs.append(p)
	var wr: WeakRef = weakref(p)
	p.finished.connect(func() -> void: _free_ref(wr))
	get_tree().create_timer(1.6).timeout.connect(func() -> void: _free_ref(wr))
	p.restart()


func _free_ref(wr: WeakRef) -> void:
	var n: Variant = wr.get_ref()
	if n != null and is_instance_valid(n):
		_puffs.erase(n)
		(n as Node).queue_free()


# --- линии скорости ---

func _tick_lines() -> void:
	if doll.external_input:
		return   # линии скорости — только когда куклой управляет игрок (боты и тесты без них)
	if _clock_ms < _next_lines_ms:
		return
	_next_lines_ms = _clock_ms + LINES_REFRESH_MS
	var dir := get_tree().get_first_node_in_group(FxPreset.DIRECTOR_GROUP)
	if dir == null:
		return
	var sfx: Variant = dir.get("screen_fx")
	var fi: Variant = dir.get("flash_intensity")
	if sfx == null or (fi != null and float(fi) <= 0.001):
		return
	(sfx as ScreenFx).speed_lines(doll, LINES_MS, LINES_ALPHA * clampf(float(fi) if fi != null else 1.0, 0.0, 1.0))


# --- подсветка рубашки ---

func _collect_tint() -> void:
	_tint_ready = true
	for m in doll.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_surface_override_material(s) as BaseMaterial3D
			if mat != null and mat.resource_name.begins_with(Doll.SHIRT_MATERIAL):
				_tint_mats.append([mat, mat.emission_enabled])


func _tick_tint(delta: float, on: bool) -> void:
	var target := 1.0 if on else 0.0
	if is_equal_approx(_tint_k, target) and target == 0.0:
		return
	if not _tint_ready:
		_collect_tint()
	_tint_k = move_toward(_tint_k, target, TINT_RATE * delta)
	var col := _colour().lerp(Color.WHITE, 0.25)
	for e in _tint_mats:
		if not is_instance_valid(e[0]):
			continue
		var mat := e[0] as BaseMaterial3D
		mat.emission_enabled = _tint_k > 0.01
		mat.emission = col
		mat.emission_energy_multiplier = _tint_k * TINT_ENERGY
	if _tint_k <= 0.0:
		_restore_tint()


func _restore_tint() -> void:
	for e in _tint_mats:
		var m: Variant = e[0]
		if m != null and is_instance_valid(m):
			(m as BaseMaterial3D).emission_enabled = bool(e[1])
	_tint_k = 0.0
