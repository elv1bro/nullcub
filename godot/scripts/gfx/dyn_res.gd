## Динамическое разрешение 3D (docs/plan-demo/PERF_PASS.md §7): множитель поверх масштаба Gfx, который снижается, когда игра не держит
## частоту кадров, и осторожно возвращается, когда запас появился. Чистая логика без движка — проверяется на синтетических потоках кадров
## (tests/gfx_probe). На GPU Metal время GPU не читается, поэтому судим по реальной длине кадров: окна по 1 с, «медленный» кадр —
## дольше target_ms × SLOW_FACTOR.
##   снижение: два плохих окна подряд (больше половины кадров медленные) → mult × DOWN, не ниже floor_mult;
##   возврат:  GOOD_WINDOWS хороших окон подряд (почти нет медленных) → mult × UP; если после возврата сразу стало плохо — возврат
##             отменяется и новые блокируются на BLOCK_S (иначе 47 ↔ 59 fps качелями).
## Единичные рывки (загрузка, KO, итоги) окно не портят: нужна устойчивая медлительность, а не пик.
class_name DynRes
extends RefCounted

const WINDOW_S := 1.0
const SLOW_FACTOR := 1.25
const BAD_FRAC := 0.5
const GOOD_FRAC := 0.05
const BAD_WINDOWS := 2
const GOOD_WINDOWS := 10
const DOWN := 0.9
const UP := 1.05
const BLOCK_S := 60.0
const REVERT_WITHIN_S := 4.0

var mult := 1.0
var floor_mult := 0.6
var target_ms := 1000.0 / 60.0

var _t := 0.0
var _n := 0
var _slow := 0
var _bad := 0
var _good := 0
var _block_until := -1.0
var _raised_at := -100.0
var _now := 0.0


## Кадр длиной ms реальных миллисекунд. active = false (загрузка сцены, замедление времени, окно свёрнуто) — окно не копится.
## Возвращает true, если mult изменился.
func feed(ms: float, active: bool) -> bool:
	_now += ms / 1000.0
	if not active:
		_t = 0.0
		_n = 0
		_slow = 0
		return false
	_t += ms / 1000.0
	_n += 1
	if ms > target_ms * SLOW_FACTOR:
		_slow += 1
	if _t < WINDOW_S:
		return false
	var frac := float(_slow) / maxf(_n, 1)
	_t = 0.0
	_n = 0
	_slow = 0
	return _close_window(frac)


func _close_window(frac: float) -> bool:
	if frac >= BAD_FRAC:
		_bad += 1
		_good = 0
		if _bad >= BAD_WINDOWS:
			_bad = 0
			if _now - _raised_at <= REVERT_WITHIN_S:   # только что подняли — и снова плохо: назад и надолго не пытаться
				_block_until = _now + BLOCK_S
			var before := mult
			mult = maxf(floor_mult, mult * DOWN)
			return not is_equal_approx(mult, before)
	elif frac <= GOOD_FRAC:
		_bad = 0
		_good += 1
		if _good >= GOOD_WINDOWS and mult < 1.0 and _now >= _block_until:
			_good = 0
			_raised_at = _now
			mult = minf(1.0, mult * UP)
			return true
	else:
		_bad = 0
		_good = 0
	return false


func reset() -> void:
	mult = 1.0
	_t = 0.0
	_n = 0
	_slow = 0
	_bad = 0
	_good = 0
	_block_until = -1.0
	_raised_at = -100.0
