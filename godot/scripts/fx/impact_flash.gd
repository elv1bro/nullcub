## Вспышка-блик удара (INSPIRATION_GAMES.md, Ragdoll Masters): мягкий диск + два скрещённых луча из квадов лицом к камере.
## Создаётся ImpactFx._spawn_flash: материал общий на тип удара (ImpactFx.flash_material), размер по силе удара.
## Живёт по времени сцены, но шаг ограничен MAX_STEP_S: длинный кадр (компиляция шейдера на первом ударе, save_png в тестах)
## не съедает всю вспышку за раз. Хлопок POP_S (0.35 → 1.0), затухание LIFE_S через GeometryInstance3D.transparency
## (материал не трогаем — он общий), затем queue_free. Hit-stop (Engine.time_scale) вспышку держит, как и щепки.
## collapse(real_ms) (HIT_FX.md §11.3, heavy/ko): с этого момента вспышка живёт по реальному времени — сжимается до COLLAPSE_SCALE
## и гаснет за real_ms, затем queue_free: звезда хлопает на кадре удара и не закрывает торсы в hit-stop (+100 мс).
class_name ImpactFlash
extends Node3D


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # двигается в _process (не в физическом тике) — своя интерполяция физики дала бы запаздывание / дрожь

const POP_S := 0.05
const LIFE_S := 0.18
const MAX_STEP_S := 1.0 / 30.0
const START_SCALE := 0.35

const COLLAPSE_SCALE := 0.25
const COLLAPSE_POP := 0.3          # доля collapse на доигрывание хлопка до полного размера

var _t := 0.0
var _life := LIFE_S               # затухание (стиль «серьёзный» — короче, HIT_FX.md §13)
var _quads: Array[MeshInstance3D] = []
var _alpha := 1.0                 # множитель яркости (пресет FX: FxPreset.flash())
var _collapse_ms := -1.0
var _collapse_t := 0.0
var _collapse_from := 1.0
var _collapse_a := 0.0
var _collapse_pop := COLLAPSE_POP


## Сжать и погасить за real_ms реального времени (повторный вызов не удлиняет). pop = false — без доигрывания хлопка
## (вторичные контакты того же сшиба: сразу сжимаются от текущего размера).
func collapse(real_ms: float, pop: bool = true) -> void:
	if _collapse_ms > 0.0 and _collapse_ms - _collapse_t <= real_ms:
		return
	_collapse_ms = maxf(real_ms, 1.0)
	_collapse_pop = COLLAPSE_POP if pop else 0.0
	_collapse_t = 0.0
	_collapse_from = maxf(scale.x, START_SCALE)
	_collapse_a = _quads[0].transparency if not _quads.is_empty() else 0.0


func collapsing() -> bool:
	return _collapse_ms > 0.0


## rays = false — только мягкий диск без лучей (горячее пятно стиля «серьёзный», HIT_FX.md §13); life_s — затухание.
func setup(mat: Material, size: float, alpha: float = 1.0, rays: bool = true, life_s: float = LIFE_S) -> void:
	_alpha = clampf(alpha, 0.0, 1.0)
	_life = maxf(life_s, 0.01)
	var specs: Array = [[Vector2(size, size), 0.0]]
	if rays:
		specs.append([Vector2(size * 2.2, size * 0.16), deg_to_rad(randf_range(-14.0, 14.0))])
		specs.append([Vector2(size * 0.16, size * 2.2), deg_to_rad(randf_range(-14.0, 14.0))])
	for spec in specs:
		var q := QuadMesh.new()
		q.size = spec[0]
		q.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.z = spec[1]
		mi.transparency = 1.0 - _alpha
		add_child(mi)
		_quads.append(mi)
	scale = Vector3.ONE * START_SCALE


func _process(delta: float) -> void:
	if _collapse_ms > 0.0:
		_collapse_t += minf(FxClock.real_delta(delta), MAX_STEP_S) * 1000.0
		var u := clampf(_collapse_t / _collapse_ms, 0.0, 1.0)
		if u < _collapse_pop:
			# доиграть хлопок в реальном времени: звезда полного размера на кадре удара
			var p := u / _collapse_pop
			scale = Vector3.ONE * lerpf(_collapse_from, 1.0, 1.0 - (1.0 - p) * (1.0 - p))
			for mi in _quads:
				mi.transparency = lerpf(_collapse_a, 1.0 - _alpha, p)
		else:
			var e := (u - _collapse_pop) / (1.0 - _collapse_pop)
			e = 1.0 - (1.0 - e) * (1.0 - e)
			var from := 1.0 if _collapse_pop > 0.0 else _collapse_from
			scale = Vector3.ONE * lerpf(from, from * COLLAPSE_SCALE, e)
			for mi in _quads:
				mi.transparency = lerpf(1.0 - _alpha, 1.0, e)
		if u >= 1.0:
			queue_free()
		return
	_t += minf(delta, MAX_STEP_S)
	var pop := clampf(_t / POP_S, 0.0, 1.0)
	var s := lerpf(START_SCALE, 1.0, 1.0 - pow(1.0 - pop, 3.0))
	scale = Vector3.ONE * s
	var fade := clampf((_t - POP_S) / _life, 0.0, 1.0)
	for mi in _quads:
		mi.transparency = 1.0 - _alpha * (1.0 - fade * fade)
	if _t >= POP_S + _life:
		queue_free()
