## СТАЗИС — пробный режим боя (docs/plan-demo/STASIS.md; автор 05.10: «нужно добавить режим ещё как superhot, чтобы время шло
## только если движется игрок»). SUPERHOT — референс: в интерфейсе и текстах для игрока его имени нет. Клавиша X в бою (HitJuice)
## включает и выключает; выключен — игра как раньше. Состояние общее на все площадки и переживает смену арены (как JointBreak и
## Drive), на диск не пишется. Масштаб времени ставит Match (_stasis_tick → _apply_time_scale), здесь — правила режима:
##   • input_strength(prefix) — сила ввода человека: максимум Input.get_action_strength по ВСЕМ действиям InputMap «prefix_*»
##     (полёт, ускорение, раскрутка, тяги рук, хват, активные блоки и всё, что добавится; клавиша и кнопка мыши — 1, стик — доля
##     наклона после мёртвой зоны действия). Скорость тела не считается: отпустил всё — время стоит, даже если кукла летит;
##   • target(drive) — к чему тянется масштаб: Tuning.STASIS_IDLE_SCALE без ввода, 1 — полный ввод, стик — пропорционально;
##   • step(cur, to, real) — шаг за real реальных секунд: весь путь вверх за STASIS_RAMP_UP_S, вниз — за STASIS_RAMP_DOWN_S.
class_name Stasis
extends RefCounted

## Список действий префикса пересобирается раз в столько кадров: руки и активные блоки заводят свои действия на лету.
const ACTIONS_REFRESH_FRAMES := 120

static var on: bool = Tuning.STASIS_DEFAULT
static var _actions: Dictionary = {}   # prefix → Array[StringName]
static var _actions_frame := -1000000


static func set_on(v: bool) -> void:
	on = v


static func toggle() -> bool:
	on = not on
	return on


static func title() -> String:
	return TranslationServer.translate("СТАЗИС") + ": " + TranslationServer.translate("вкл" if on else "выкл")


## Действия InputMap с префиксом prefix («p1» → p1_left … p1_act3), без ui_*.
static func actions_of(prefix: String) -> Array:
	var f := Engine.get_process_frames()
	if f - _actions_frame >= ACTIONS_REFRESH_FRAMES or f < _actions_frame:
		_actions.clear()
		_actions_frame = f
	if not _actions.has(prefix):
		var out: Array = []
		var head := prefix + "_"
		for a in InputMap.get_actions():
			if String(a).begins_with(head):
				out.append(a)
		_actions[prefix] = out
	return _actions[prefix]


## Сила ввода игрока с префиксом prefix: 0 — ничего не нажато, 1 — клавиша / кнопка / стик до упора.
static func input_strength(prefix: String) -> float:
	if prefix == "":
		return 0.0
	var s := 0.0
	for a in actions_of(prefix):
		s = maxf(s, Input.get_action_strength(a))
		if s >= 1.0:
			break
	return s


## Масштаб «время стоит»: не ниже HITFX_TIME_SCALE_MIN (часть кода делит на масштаб времени).
static func idle_scale() -> float:
	return clampf(Tuning.STASIS_IDLE_SCALE, Tuning.HITFX_TIME_SCALE_MIN, 1.0)


static func target(drive: float) -> float:
	return lerpf(idle_scale(), 1.0, clampf(drive, 0.0, 1.0))


static func step(cur: float, to: float, real: float) -> float:
	var span := maxf(1.0 - idle_scale(), 1e-3)
	if to > cur:
		return minf(to, cur + span * real / maxf(Tuning.STASIS_RAMP_UP_S, 1e-4))
	return maxf(to, cur - span * real / maxf(Tuning.STASIS_RAMP_DOWN_S, 1e-4))
