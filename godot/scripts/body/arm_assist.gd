## Рука мышью и захват (docs/plan-demo/BODY_CRAFT.md §5, решения автора п. 2–4). Узел-ребёнок Doll, как WeaponPickup:
##   doll.add_child(ArmAssist.new())  (или ArmAssist.attach_to(doll)).
##
## Какая деталь. control_part — имя тела куклы; пусто (по умолчанию) = авто: у ModularDoll — первая деталь blueprint.control
## (имя тела — явное name узла чертежа, иначе <PartDef.name_prefix>_<uid>), у обычной Doll — "Hand_R". Кукла проверяется через
## get("blueprint") — без жёсткой зависимости от класса ModularDoll. Цепь «деталь → торс» — по doll.joints (node_a — родитель,
## node_b — ребёнок): корневой сустав (плечо) — центр круга досягаемости, досягаемость = сумма звеньев плечо → локоть → запястье →
## точка хвата (у doll.tscn 0.30 + 0.27 + 0.12 = 0.69 м). Точка хвата — маркер "Grip" детали, у кисти — как WeaponPickup
## (0, −0.03, 0), иначе центр тела.
##
## Ввод. Действия InputMap создаются при первом _ready, если их нет (project.godot не трогаем; занятые клавиши — input_setup.gd,
## playground.gd: WASD, Shift, Space, стрелки, Ctrl, Enter, R, Esc, 1–3):
##   p1: ЛКМ зажата — цель = курсор (луч камеры × плоскость z = 0); E — захват / отпустить;
##   pN: геймпад N−1 (p1 — геймпад 0): правый стик — цель = плечо + стик × досягаемость; RB — захват / отпустить.
##   Мышь по умолчанию только у p1 (use_mouse −1). Настройки узла Match.respawn_doll не переносит (script.new()), поэтому всё
##   определяется по doll.input_prefix. Кукла с external_input (боты, пробы) устройства не читает: set_target_override() /
##   clear_target_override() / press_grab().
##
## Сила «мягкой помощи» (пока цель активна) — пружина-демпфер к цели ASSIST_K 800 Н/м, ASSIST_C 40 Н·с/м по скорости хвата
## относительно плеча, неявная (обратный Эйлер на массе голой детали m, у кисти 0.5 кг; явная схема на лёгкой кисти с грузом дрожала
## через тик): e = цель − хват, v' = (v + dt·k·e/m) / (1 + dt·c/m + dt²·k/m), F = m·(v' − v)/dt, |F| ≤ ASSIST_F_MAX 80 Н пустой рукой,
## с грузом 80 + ASSIST_LOAD_ACCEL·m_предмета, но ≤ ASSIST_F_MAX_LOADED 120 Н. +F к детали в точке хвата, −F в центр торса (в плечо —
## та же сумма, но торс качается втрое сильнее): сумма сил помощи ноль — рукой нельзя грести и летать (ЦМ не сдвинуть, только
## опереться о пол или предмет; проба zero_sum: 5 с маха в невесомости — ЦМ сдвинулся на 6 мм, без −F в торс — на 0.77 м).
## Цель клэмпится кругом досягаемости × REACH_FRAC (0.97). Кисть приходит к цели за 0.13–0.28 с с ошибкой 4–21 мм (проба reach).
## Отпустил — силы нет, деталь снова болтается на мышцах (k и tmax мышц не трогаем: плечо 16 Н·м ≈ 23 Н у кисти, рука с оружием ≈ 32 Н).
## Поза руки на время помощи следует за целью (Doll.set_pose плеча и локтя по IK двух звеньев, прежние углы возвращаются при
## отпускании): иначе мышцы тянут к Т-позе против силы (ошибка до 0.14 м), а прямую руку сила в кисти к плечу вообще не согнёт —
## момент в локте идёт в переразгибание (упор лимита), кисть застревает на круге досягаемости. Мышцы ведут позу, сила — точку.
## В стане помощь × (1 − Tuning.STUN_CONTROL_LOSS), как тяга.
##
## Захват (клавиша-переключатель). Нажал — управляемая деталь хватает ближайший RigidBody3D в GRAB_RADIUS от точки хвата
## (расстояние до ближайшей точки AABB коллизий предмета): пропсы, куски хлама, части разбитых кукол и части живых чужих кукол
## (GRAB_DOLLS; держит так же слабо — соперник вырывается тягой). Не хватаются: свои части, замороженные тела, оружие (Weapon —
## дело WeaponPickup). Нажал ещё раз — отпустил; бросок = отпустить на замахе (предмет уходит со своей скоростью).
## «Сустав» захвата — пружина с ограниченной силой между точкой хвата детали и точкой предмета (ближайшая к кисти точка при захвате),
## пара сил +F предмету / −F детали: F = clamp(k·Δx + c·Δv, HOLD_F_MAX), k = μ·HOLD_OMEGA², c = 2·HOLD_ZETA·μ·HOLD_OMEGA,
## μ = m_детали·m_предмета / (m_детали + m_предмета) — частота одна для любого веса; пружина неявная (обратный Эйлер на μ), устойчива
## и на кисти 0.5 кг, и на гайке 0.1 кг. Жёсткий Generic6DOFJoint3D (как у оружия) не годится: у Jolt в Godot нет предела силы сустава, а тяга куклы
## 12 Н/кг × 40 кг = 480 Н подняла бы и ящик 80 кг. Шарнир свободный — предмет висит и раскачивается вокруг точки хвата.
## Классы веса (g = 2, HOLD_F_MAX 150 Н; проба classes, бросок с разбегом):
##   лёгкие ≤ 15 кг (вес ≤ 30 Н) — летят: болт 0.3 кг 4.6 м/с, голова 2.6 кг 8.4 м/с, ящик 10 кг 3.0 м/с (первое касание 2.3 м),
##     бочка 15 кг 3.9 м/с; одной рукой без разбега ящик почти не летит (0.3–1.2 м/с);
##   средние 15–40 кг (≤ 80 Н) — тащатся, почти не поднимаются: железная бочка 40 кг поднята на 0.09 м, на разбеге срывается;
##   тяжёлые ≥ 80 кг (160 Н > хвата) — не поднять: ящик 80 кг с тягой вверх не поднимается, срыв через 0.5–0.7 с.
## Растяжение > HOLD_SLIP_M (0.45 м) дольше HOLD_SLIP_S (0.2 с) или > 2·HOLD_SLIP_M сразу — предмет срывается (reason "slip").
## Держимый предмет не сталкивается со своими частями (исключения, как у оружия), исключения снимаются через RELEASE_EXCEPT_S после
## отпускания, когда предмет отошёл от куклы. Кукла в стане (сильный удар ≥ Tuning.STUN_DAMAGE_THRESHOLD) и после KO
## (Doll.break_apart зовёт drop_all) отпускает.
##
## Оружие в управляемой кисти (WeaponPickup): рука мышью водит кисть вместе с оружием (удар мышью), а клавиша захвата бросает оружие
## (WeaponPickup.drop — зачёт брошенного оружия уже есть: Weapon.attacker, 3 с); после броска подбор оружия выключен REPICK_BLOCK_S,
## иначе упавшее рядом оружие вернулось бы в кисть через 0.35 с. Пока кисть держит пропс, авто-подбор оружия выключен (WeaponPickup
## не прикрутит молот к кисти с ящиком); у WeaponPickup флаг один на обе кисти — вторая тоже не подбирает, пока пропс в руке.
##
## Брошенный предмет бьёт: ThrownCredit (scripts/body/thrown_credit.gd) — ребёнок предмета, WINDOW_S = 2 с после отпускания урон
## засчитывается бросившему (kind weapon) через Doll.take_damage по Damage.compute(масса, скорость).
##
## Своя оторванная деталь (Doll.detach_part — PvE: Разборщик; хук сессии куклы). Оторвали управляемую деталь или её цепь —
## _on_part_detached отпускает предмет и перестаёт управлять (мышь не таскает оторванную кисть). Вернуть деталь:
##   • касанием — любая часть куклы ближе REATTACH_TOUCH_M к своей оторванной детали (Doll.detached_parts(), meta detached_from ==
##     эта кукла), прошло REATTACH_GRACE_S после отрыва и деталь не в чужой руке (реестр хватов holder_of: у вора её сначала надо
##     выбить ударом — он роняет) → Doll.reattach_part. Касание, а не только клавиша: вернуть можно и без руки-мыши (её тоже могли
##     оторвать), с клавиатуры и геймпада, как лут Свалки; подлетел к своей кисти — «щёлк», она на месте;
##   • клавишей захвата (E / RB) — своя деталь в GRAB_RADIUS от хвата прикручивается сразу (раньше броска оружия).
## Вернулась управляемая деталь (сигнал Doll.part_reattached) — цепь и IK собираются заново (_rebind), управление возобновляется.
## Чужую деталь (meta detached_from — другая кукла) не прикручиваем: её можно только схватить, как пропс.
##
## Вес и бросок (29.09, «предметы тянутся, а не держатся»; классы — scenes/props/prop_heft.gd):
##   лёгкие (PropHeft.LIGHT, ≤ WELD_MAX_KG, не части живых кукол) — пружина подтягивает точку хвата к кисти (≤ WELD_SNAP_MAX_S), дальше
##     предмет приваривается жёстким Generic6DOFJoint3D, как оружие, и рука с ним жёстче (Tuning.WEAPON_ARM_MUSCLES): не висит, не
##     болтается, не отстаёт;
##   средние — пружина, как раньше, плюс удержание поворота (момент к углу при захвате, реакция в торс): не крутятся на шарнире;
##   тяжёлые на якоре (замороженные) не хватаются — подсказка «слишком тяжело», last_grab_action "too_heavy".
##   Бросок — клавиша захвата, пока рука активна (ЛКМ / стик): предмет уходит к цели руки (курсору) со скоростью √(2·THROW_ENERGY/m)
##   (THROW_SPEED_MIN…MAX) поверх скорости торса, торс получает отдачу THROW_RECOIL; рука не активна — просто отпустить. Оружие в
##   кисти бросается так же.
##
## Подсказки: кольцо цвета игрока в точке цели, пока рука активна (ЛКМ / стик); подсветка (material_overlay, пульсирует) предмета,
## который будет схвачен по нажатию, и подпись над ним (у живого игрока): «E — взять», класс веса, «ЛКМ+E — бросок» с предметом в руке. Две руки на одном предмете делят общий реестр подсветки (_hl_registry): исходный overlay возвращается
## при любом порядке ухода рук.
##
## Тяги (WORKSHOP_V3.md §3, 30.09): у ModularDoll управляемых деталей может быть несколько — blueprint.control (≤ BodyBlueprint.MAX_PULLS),
## каждая — своя тяга на ЛКМ или ПКМ (blueprint.control_rmb). Главная рука (этот узел, control[0]) в _setup сама вешает на куклу по
## узлу ArmAssist-сестре на каждую следующую деталь (primary = false, control_part = имя тела): у сестры та же мягкая помощь, IK и
## реакция в торс (сумма сил каждой тяги — ноль, 10 тяг куклу не поднимут), но без захвата, броска, возврата деталей и подсказок
## предмета — это остаётся у главной. ЛКМ тянет все ЛКМ-тяги к курсору, ПКМ — все ПКМ-тяги; геймпад: правый стик — ЛКМ-тяги,
## стик с зажатым LB — ПКМ-тяги.
class_name ArmAssist
extends Node

signal grabbed(body: RigidBody3D)
signal released(body: RigidBody3D, reason: String)

# --- рука: мягкая помощь ---
## Н/м. Схема неявная (обратный Эйлер на массе голой детали, кисть 0.5 кг) — устойчива при любых k, но на 60 Гц «съедает» часть
## жёсткости: k_eff = k / (1 + dt·c/m + dt²·k/m) = 800 / 2.8 ≈ 290 Н/м у цели. Эффективная масса кисти на цепи ≈ 1 кг (инерция руки у
## плеча 0.57 кг·м² / 0.69² ≈ 1.2 кг): ω ≈ 17 рад/с. Ошибка ≥ 0.3 м — уже F_max: дальше разгон с постоянной силой.
const ASSIST_K := 800.0
## Н·с/м по скорости хвата относительно плеча: ζ ≈ 0.7 при k_eff и 1 кг — без перелёта, но и без «ваты».
const ASSIST_C := 40.0
## Н. Больше мышц руки у кисти (плечо 16–22 Н·м / 0.69 м ≈ 23–32 Н) + вес руки 8 Н — вместе с позой по IK кисть доходит до цели
## с ошибкой 4–21 мм; поднимает ящик 10 кг (20 Н) и бочку 15 кг (30 Н). Равно весу всей куклы (40 кг × 2): без реакции в торс рука подняла бы куклу.
const ASSIST_F_MAX := 80.0
## Н на кг предмета в руке: рука с грузом сильнее (упирается всем телом, реакция уходит в торс), иначе пустая рука 80 Н разгоняла бы
## кисть с ящиком 10 кг до ~1 м/с (проба throw_far): 80 + 10 × m, но не больше ASSIST_F_MAX_LOADED.
const ASSIST_LOAD_ACCEL := 10.0
## Н: рука не должна перетягивать хват — иначе на махе кисть уходит от предмета быстрее, чем пружина хвата (HOLD_F_MAX) его разгоняет,
## и бочка 15 кг срывается с руки (проба classes). 0.8 × HOLD_F_MAX: вместе с мышцами плеча по IK (~25 Н) меньше хвата.
const ASSIST_F_MAX_LOADED := 120.0
## Цель держится внутри круга досягаемости: у самой границы рука тянется в струну и суставы спорят с силой.
const REACH_FRAC := 0.97
const STICK_DEADZONE := 0.2
## Средние суставы цепи (локоть) при активной руке сгибаются позой (в сторону их позы покоя: у doll.tscn локоть 10°): из прямой руки
## к близкой цели не выйти (сингулярность). Плечо–локоть–кисть — сгиб по IK на расстояние до цели, иначе FLEX_DEG.
const FLEX_DEG := 45.0             # цепь длиннее двух звеньев: средние суставы сгибаются до стольки
const FLEX_MAX_DEG := 135.0        # IK-сгиб не дальше (лимит локтя doll.tscn 140°)
const FLEX_BLEND_S := 0.12         # сгибание и возврат позы — плавно (без рывка PD)
const UNFLEX_BLEND_S := 0.3

# --- захват ---
const GRAB_RADIUS := 0.4           # м от точки хвата до ближайшей точки предмета (контракт: ~0.4)
const GRAB_DOLLS := true           # хватать части чужих кукол (живых — держит так же слабо, вырываются тягой 480 Н)
## рад/с: собственная частота пружины хвата по приведённой массе μ (кисть 0.5 кг): ящик 10 кг — k = 0.48·45² ≈ 960 Н/м, провис под
## весом 2 см, при HOLD_F_MAX растяжение ≈ 0.16 м. Неявная схема: ω·dt = 0.75 не ограничен устойчивостью.
const HOLD_OMEGA := 45.0
const HOLD_ZETA := 0.7
## Н: предел силы хвата — классы веса (контракт п. 4): лёгкие ≤ 15 кг (≤ 30 Н веса) летят, средние 15–40 (≤ 80 Н) тащатся и
## раскачиваются, тяжёлые ≥ 80 (≥ 160 Н) не поднять.
const HOLD_F_MAX := 150.0
## м: растяжение пружины хвата, при котором предмет срывается, если держится дольше HOLD_SLIP_S (у ящика 10 кг при HOLD_F_MAX ≈ 0.16 м):
## рывок на махе с разбегом тянет бочку 15 кг на 0.5 м на доли секунды и отпускает — не срыв; ящик 80 кг держит растяжение — срыв.
## Вдвое больше — срыв сразу.
const HOLD_SLIP_M := 0.45
const HOLD_SLIP_S := 0.2
const RELEASE_EXCEPT_S := 0.3      # с после отпускания: исключения коллизий со своими частями снимаются (если предмет отошёл)
const RELEASE_EXCEPT_MAX_S := 2.0  # и не позже этого, даже если предмет лежит на кукле (Jolt растолкнёт)
const RELEASE_CLEAR_M := 0.15      # «отошёл»: зазор AABB предмета и частей куклы, м
const REPICK_BLOCK_S := 1.0        # после броска оружия клавишей захвата WeaponPickup не подбирает столько секунд
const REATTACH_TOUCH_M := 0.3      # своя оторванная деталь ближе этого к любой части куклы — прикручивается обратно
const REATTACH_GRACE_S := 1.0      # но не раньше, чем через столько после отрыва (иначе прирастала бы в руках у вора на старте бегства)

# --- жёсткий хват и бросок (29.09) ---
const WELD_MAX_KG := PropHeft.LIGHT_MAX_KG
const WELD_SNAP_M := 0.07          # точка хвата подтянулась ближе — приварить
const WELD_SNAP_MAX_S := 0.25      # или через столько после захвата (остаток досняпывается)
const HOLD_ANG_OMEGA := 12.0       # рад/с: удержание поворота среднего предмета
const HOLD_ANG_ZETA := 0.9
const HOLD_TORQUE_MAX := 30.0      # Н·м
## Приваренный: момент к углу при сварке поверх сустава (реакция в торс). Ящик идёт за рукой плавно; оставшиеся ±15–20° между
## ящиком и кистью на резком махе — это кисть: Jolt правит положение запястья (кисть 0.5 кг против ящика 10 кг), и она проворачивается
## относительно ящика, а не ящик на шарнире. Жёстче (доводка по скорости) — хуже: спорит с позиционной поправкой сустава (проба weld).
const WELD_ANG_OMEGA := 25.0
const WELD_TORQUE_MAX := 60.0
const THROW_ENERGY := 110.0        # Дж: ящик 10 кг — 4.7 м/с, бочка 15 кг — 3.8, взрывная 12 кг — 4.3, голова 2.6 кг — 9.2
const THROW_SPEED_MIN := 2.0
const THROW_SPEED_MAX := 12.0
const THROW_RECOIL := 0.5          # доля импульса броска, которую получает торс назад
const THROW_CARRY := 0.6           # доля скорости торса, которую предмет наследует (разбег помогает, но не удваивает дальность)
const THROW_SPIN := 5.0            # рад/с закрутки лёгкого предмета

# --- подсказки ---
const MARKER_RADIUS := 0.07        # м, кольцо цели
const HIGHLIGHT_ALPHA := 0.42
const HIGHLIGHT_PULSE_HZ := 2.2
const HINT_UP_M := 0.35            # подпись над верхом предмета
const HINT_COLOURS := {"grab": Color(1.0, 0.95, 0.8), "medium": Color(1.0, 0.72, 0.3), "heavy": Color(1.0, 0.35, 0.3),
	"held": Color(0.85, 0.95, 1.0)}

## Имя управляемого тела; пусто — авто (ModularDoll: blueprint.control[0], иначе "Hand_R").
@export var control_part := ""
## −1 авто (мышь только у p1), 0 — нет, 1 — да.
@export var use_mouse := -1
## Кнопка тяги: "lmb" — ЛКМ / правый стик, "rmb" — ПКМ / стик с LB. У главной руки "" — авто (control_rmb чертежа).
@export var button := ""
## Главная рука: захват, бросок, возврат деталей, подсказки предмета и сёстры-тяги. У сестёр false (их создаёт главная).
@export var primary := true
## Реакция −F в торс. false — только для проб (контраст «без реакции рука летает»), в игре всегда true.
@export var reaction_to_torso := true
@export var show_hints := true
## Жёсткий хват лёгких предметов. false — только для проб (контраст «как было»: пружина и свободный шарнир).
@export var weld_light := true

var doll: Doll
var part: RigidBody3D
var part_name := ""
var torso: RigidBody3D
var reach := 0.0
var grip_local := Vector3.ZERO
## Предмет в руке (null — пусто) и точка хвата на нём (локальные координаты предмета).
var held: RigidBody3D = null
var anchor_local := Vector3.ZERO
## Кандидат на захват в этом тике (подсвечен).
var candidate: RigidBody3D = null
## Активна ли рука в этом тике и куда тянется (клэмпнутая цель), сила помощи и сила хвата (для проб).
var arm_active := false
var target := Vector3.ZERO
var last_assist_force := Vector3.ZERO
var last_hold_force := Vector3.ZERO
## Последнее отпускание: {body, reason, t, velocity, position}.
var last_release: Dictionary = {}
## Последнее действие клавиши захвата: "grab" | "release" | "drop_weapon" | "reattach" | "none".
var last_grab_action := ""
## Последняя возвращённая деталь: {body, name, t, how: "touch" | "grab"} (для проб).
var last_reattach: Dictionary = {}
## Тяжёлый предмет на якоре рядом с кистью (подсказка «слишком тяжело»).
var blocked_candidate: RigidBody3D = null
## Последний бросок: {body, t, dir, speed} (для проб).
var last_throw: Dictionary = {}

var _ready_done := false
var _time := 0.0
var _root_body: RigidBody3D        # ребёнок корневого сустава (плечо: UpperArm_R)
var _root_local := Vector3.ZERO    # точка корневого сустава в его системе
var _override_active := false
var _mid_joints: Array[String] = []   # средние суставы цепи (локоть): сгибаются позой, пока рука активна
var _flex_saved: Dictionary = {}      # сустав -> прежний угол позы (градусы), пока согнут
var _l1 := 0.0                        # звенья для IK локтя: корень → средний сустав, средний сустав → хват
var _l2 := 0.0
var _overstretch_t := 0.0            # сколько секунд подряд растяжение хвата > HOLD_SLIP_M
var _ik: Dictionary = {}              # IK плеча и локтя (см. _setup_ik); пусто — только сгиб локтя
var _override_target := Vector3.ZERO
var _grab_requested := false
var _pending_release: Array = []   # [body, t_min, t_max]
var _credit: ThrownCredit = null
var _wp_saved: Variant = null      # прежний WeaponPickup.auto_pickup, пока мы его держим выключенным
var _wp_block_until := -1.0
var _marker: MeshInstance3D
var _highlighted: RigidBody3D = null
var _saved_overlays: Dictionary = {}   # instance id GeometryInstance3D, подсвеченных этой рукой -> true
var _hl_material: StandardMaterial3D
var _query: PhysicsShapeQueryParameters3D
var _bounds_cache: Dictionary = {}     # instance id -> AABB (локальные границы коллизий)
var _detach_seen: Dictionary = {}      # instance id своей оторванной детали -> _time, когда её впервые увидели оторванной
var _chain_joint_names: Array[String] = []   # суставы цепи деталь → торс (жёсткость руки с приваренным предметом)
var _weld: Generic6DOFJoint3D = null
var _weld_pending := false
var _stiff_set: Array[String] = []
var _grab_t := 0.0
var _hold_angle := 0.0                 # угол предмета относительно детали при захвате (рад, вокруг Z)
var _hint: Label3D
var _sisters: Array[ArmAssist] = []   # тяги control[1..] (главная рука создаёт и убирает)
var _auto_part := false               # деталь выбрана по чертежу (control_part пуст) — только такая рука заводит сестёр

static var _actions_done := false
## Общий реестр подсветки: instance id GeometryInstance3D -> {orig: исходный material_overlay, users: [ArmAssist, …]}.
static var _hl_registry: Dictionary = {}
## Кто что держит: instance id тела -> ArmAssist (своя оторванная деталь в чужой руке не прирастает от касания).
static var _holders: Dictionary = {}
const HL_META := &"arm_assist_highlight"   # метка материала подсветки


func _ready() -> void:
	doll = get_parent() as Doll
	if doll == null:
		push_error("ArmAssist must be a child of Doll")
		return
	ensure_input_actions()
	if doll.is_node_ready():
		_setup()
	else:
		doll.ready.connect(_setup, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	for s2 in _sisters:
		if is_instance_valid(s2) and s2.is_inside_tree():
			s2.queue_free()
	_sisters.clear()
	_set_highlight(null)
	if doll != null and is_instance_valid(doll) and doll.alive:
		_set_flex(false)
	if held != null:
		release("exit")
	for e in _pending_release:
		if is_instance_valid(e[0]):   # предмет мог разбиться (Breakable) или взорваться, пока снимались исключения
			_remove_exceptions(e[0])
	_pending_release.clear()
	_restore_weapon_pickup()


## Удобный вход: повесить руку на куклу (возвращает узел).
static func attach_to(target_doll: Doll) -> ArmAssist:
	var a := ArmAssist.new()
	a.name = "ArmAssist"
	target_doll.add_child(a)
	return a


# ------------------------------------------------------------------ ввод

## Действия p1..p4: _arm (мышь), _arm_left/_right/_up/_down (правый стик), _grab (E у p1, RB у всех). Добавляются, только если
## действия нет (если автор завёл своё в project.godot — не трогаем). Пустые действия тоже создаются: опрос несуществующего
## действия в Input сыплет ошибками.
static func ensure_input_actions() -> void:
	if _actions_done:
		return
	_actions_done = true
	for i in range(4):
		var p := "p%d" % (i + 1)
		var arm: Array = []
		var arm2: Array = []
		var grab: Array = []
		if i == 0:
			var mb := InputEventMouseButton.new()
			mb.device = -1
			mb.button_index = MOUSE_BUTTON_LEFT
			arm.append(mb)
			var mb2 := InputEventMouseButton.new()
			mb2.device = -1
			mb2.button_index = MOUSE_BUTTON_RIGHT
			arm2.append(mb2)
			var k := InputEventKey.new()
			k.device = -1
			k.physical_keycode = KEY_E
			grab.append(k)
		var rb := InputEventJoypadButton.new()
		rb.device = i
		rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
		grab.append(rb)
		var lb := InputEventJoypadButton.new()
		lb.device = i
		lb.button_index = JOY_BUTTON_LEFT_SHOULDER
		arm2.append(lb)
		_add_action(p + "_arm", arm)
		_add_action(p + "_arm2", arm2)   # ПКМ-тяги: ПКМ у p1, LB (со стиком) у геймпада
		_add_action(p + "_grab", grab)
		for e in [["_arm_left", JOY_AXIS_RIGHT_X, -1.0], ["_arm_right", JOY_AXIS_RIGHT_X, 1.0],
				["_arm_up", JOY_AXIS_RIGHT_Y, -1.0], ["_arm_down", JOY_AXIS_RIGHT_Y, 1.0]]:
			var m := InputEventJoypadMotion.new()
			m.device = i
			m.axis = e[1]
			m.axis_value = e[2]
			_add_action(p + String(e[0]), [m])


static func _add_action(action: String, events: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, STICK_DEADZONE)
	for ev in events:
		InputMap.action_add_event(action, ev)


## Тестовый / бот-вход: цель в мире (z игнорируется), рука активна до clear_target_override().
func set_target_override(p: Vector3) -> void:
	_override_active = true
	_override_target = Vector3(p.x, p.y, 0.0)


func clear_target_override() -> void:
	_override_active = false


## Тестовый / бот-вход: как нажатие клавиши захвата (срабатывает в ближайшем физическом тике).
func press_grab() -> void:
	_grab_requested = true


func _mouse_enabled() -> bool:
	if use_mouse >= 0:
		return use_mouse > 0
	return doll.input_prefix == "p1"


## Зажата ли мышиная кнопка тяги: ЛКМ (p1_arm) или ПКМ (p1_arm2 — в нём и LB геймпада, поэтому кнопку мыши проверяем прямо).
func _mouse_pressed(rmb: bool) -> bool:
	if rmb:
		return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and InputMap.has_action(doll.input_prefix + "_arm2")
	return Input.is_action_pressed(doll.input_prefix + "_arm")


## Курсор мыши на плоскости z = 0 (луч активной камеры); null — нет камеры или луч параллелен плоскости.
func mouse_on_plane() -> Variant:
	var vp := get_viewport()
	if vp == null:
		return null
	var cam := vp.get_camera_3d()
	if cam == null:
		return null
	var mp := vp.get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.z) < 1e-6:
		return null
	var t := -o.z / d.z
	if t < 0.0:
		return null
	var p := o + d * t
	return Vector3(p.x, p.y, 0.0)


## Ввод этого тика: [активна?, цель, нажат захват?].
func _read_input() -> Array:
	var active := false
	var tgt := Vector3.ZERO
	var grab_now := _grab_requested
	_grab_requested = false
	if _override_active:
		active = true
		tgt = _override_target
	elif not doll.external_input and doll.control_enabled:
		var p := doll.input_prefix
		var rmb := button == "rmb"
		if _mouse_enabled() and _mouse_pressed(rmb):
			var mp: Variant = mouse_on_plane()
			if mp != null:
				active = true
				tgt = mp
		if not active:
			# стик ведёт ЛКМ-тяги, со зажатым LB — ПКМ-тяги (мышиная кнопка p1_arm2 тут тоже считается: ПКМ без мыши не бывает)
			var s := Input.get_vector(p + "_arm_left", p + "_arm_right", p + "_arm_down", p + "_arm_up")
			if s.length() > STICK_DEADZONE and Input.is_action_pressed(p + "_arm2") == rmb:
				active = true
				tgt = root_point() + Vector3(s.x, s.y, 0.0).limit_length(1.0) * reach
		if primary and Input.is_action_just_pressed(p + "_grab"):
			grab_now = true
	return [active, tgt, grab_now]


# ------------------------------------------------------------------ деталь и цепь

func _setup() -> void:
	if _ready_done or doll == null:
		return
	_auto_part = control_part == ""
	part_name = _resolve_control_part()
	part = doll.parts.get(part_name) as RigidBody3D
	torso = doll.parts.get("Torso") as RigidBody3D
	if part == null or torso == null:
		push_warning("ArmAssist: no control part '%s' in %s" % [part_name, doll.name])
		return
	if doll.has_signal("part_detached") and not doll.is_connected("part_detached", _on_part_detached):
		doll.connect("part_detached", _on_part_detached)
	if doll.has_signal("part_reattached") and not doll.is_connected("part_reattached", _on_part_reattached):
		doll.connect("part_reattached", _on_part_reattached)
	var g := part.get_node_or_null("Grip") as Node3D
	if g != null:
		grip_local = g.position
	elif part_name.begins_with("Hand"):
		grip_local = Vector3(0, -0.03, 0)   # как WeaponPickup.hand_grip_offset
	# цепь деталь → торс: ребёнок -> [сустав, родитель]
	var parent_of := {}
	for j in doll.joints.values():
		var jj := j as Generic6DOFJoint3D
		var a := jj.get_node_or_null(jj.node_a) as RigidBody3D
		var b := jj.get_node_or_null(jj.node_b) as RigidBody3D
		if a != null and b != null:
			parent_of[b] = [jj, a]
	var chain: Array = []   # [тело, его проксимальный сустав] от детали к торсу: кисть/Wrist, предплечье/Elbow, плечо/Shoulder
	var cur: RigidBody3D = part
	while parent_of.has(cur) and cur != torso and chain.size() < 16:
		var e: Array = parent_of[cur]
		chain.append([cur, e[0]])
		cur = e[1]
	_chain_joint_names.clear()
	for e2 in chain:
		_chain_joint_names.append(String((e2[1] as Node).name))
	_root_body = part
	_root_local = grip_local
	reach = 0.7
	if not chain.is_empty():
		# досягаемость: хват → проксимальный сустав детали (в её системе), дальше — между соседними суставами цепи: узлы суставов
		# стоят на местах сборки и друг с другом согласованы (звено между ними — одно твёрдое тело)
		reach = grip_local.distance_to(_pivot_local(part, chain[0][1]))
		for i in range(1, chain.size()):
			reach += (chain[i - 1][1] as Node3D).position.distance_to((chain[i][1] as Node3D).position)
		_root_body = chain[chain.size() - 1][0]
		_root_local = _pivot_local(_root_body, chain[chain.size() - 1][1])
		for i in range(1, chain.size() - 1):
			_mid_joints.append(String((chain[i][1] as Node).name))
		if chain.size() == 3:
			_l1 = (chain[1][1] as Node3D).position.distance_to((chain[2][1] as Node3D).position)
			_l2 = reach - _l1
		_setup_ik(chain)
	_ready_done = true
	if button == "":
		button = _button_of(part_name)
	if show_hints and _marker == null:
		_make_hints()
	if primary and _auto_part:
		_spawn_sisters.call_deferred()


## Точка сустава joint в системе тела b (его ребёнка). Узлы Generic6DOFJoint3D не двигаются с телами, а Doll._snap_to_pose
## при спавне поворачивает конечности в позу — поэтому b.to_local(узел сустава) после спавна врёт (у кисти на ~0.8 м). Якорь Jolt
## посчитан при создании сустава, в позе сборки. Откуда брать позу сборки:
##   1) маркер "Socket" детали (ModularDoll, BODY_CRAFT §1: точка крепления к родителю) — точно всегда;
##   2) сцена куклы (doll.scene_file_path: doll.tscn / doll_dark.tscn) — трансформы тела и сустава из SceneState;
##   3) иначе — живые узлы (точно, только если физика и поза ещё не сдвинули тело).
func _pivot_local(b: RigidBody3D, joint: Node3D) -> Vector3:
	var sock := b.get_node_or_null("Socket") as Node3D
	if sock != null:
		return sock.position
	var bt: Variant = _build_transform(String(b.name))
	var jt: Variant = _build_transform(String(joint.name))
	if bt is Transform3D and jt is Transform3D:
		return (bt as Transform3D).affine_inverse() * (jt as Transform3D).origin
	return b.to_local(joint.global_position)


static var _scene_build_cache: Dictionary = {}   # scene path -> {имя прямого ребёнка корня: Transform3D}

## Трансформ прямого ребёнка корня сцены куклы в позе сборки (null — нет сцены / узла).
func _build_transform(node_name: String) -> Variant:
	var path := doll.scene_file_path
	if path == "":
		return null
	if not _scene_build_cache.has(path):
		var map := {}
		var ps := load(path) as PackedScene
		if ps != null:
			var st := ps.get_state()
			for i in st.get_node_count():
				if String(st.get_node_path(i, true)) != ".":
					continue
				var tr := Transform3D.IDENTITY
				for k in st.get_node_property_count(i):
					if st.get_node_property_name(i, k) == &"transform":
						tr = st.get_node_property_value(i, k)
				map[String(st.get_node_name(i))] = tr
		_scene_build_cache[path] = map
	var m: Dictionary = _scene_build_cache[path]
	return m.get(node_name, null)


## Тяги control[1..] чертежа: по сестре ArmAssist на каждую (главная рука, после _setup). Сёстры — дети куклы, как главная.
func _spawn_sisters() -> void:
	if not primary or doll == null or not is_instance_valid(doll):
		return
	var bp: Variant = doll.get("blueprint")
	if not (bp is Resource):
		return
	var ctrl: Variant = (bp as Resource).get("control")
	if ctrl == null or ctrl.size() < 2:
		return
	var taken := {}   # детали, которые уже ведёт другой ArmAssist куклы (сцена врага: ArmL / ArmR с явным control_part)
	for c in doll.get_children():
		if c is ArmAssist and c != self:
			taken[(c as ArmAssist).control_part] = true
	for i in range(1, mini(ctrl.size(), BodyBlueprint.MAX_PULLS)):
		var nm := _body_name_of_uid(bp as Resource, String(ctrl[i]))
		if nm == "" or nm == part_name or taken.has(nm):
			continue
		var s2 := ArmAssist.new()
		s2.name = "ArmAssist_%s" % nm
		s2.control_part = nm
		s2.primary = false
		s2.use_mouse = use_mouse
		s2.reaction_to_torso = reaction_to_torso
		s2.show_hints = show_hints
		s2.button = _button_of(nm)
		doll.add_child(s2)
		_sisters.append(s2)


## Тяги этой куклы (главная и сёстры) — для проб и мастерской.
func pulls() -> Array[ArmAssist]:
	var out: Array[ArmAssist] = [self]
	for s2 in _sisters:
		if is_instance_valid(s2):
			out.append(s2)
	return out


## Кнопка тяги детали по имени тела: "rmb", если её uid в blueprint.control_rmb, иначе "lmb".
func _button_of(body_name: String) -> String:
	var bp: Variant = doll.get("blueprint") if doll != null else null
	if not (bp is Resource):
		return "lmb"
	var rmb: Variant = (bp as Resource).get("control_rmb")
	if rmb == null:
		return "lmb"
	for uid in rmb:
		if _body_name_of_uid(bp as Resource, String(uid)) == body_name:
			return "rmb"
	return "lmb"


## Имя тела узла uid чертежа (явное name, иначе <name_prefix>_<uid>, иначе тело с суффиксом _<uid>); "" — нет тела.
func _body_name_of_uid(bp: Resource, uid: String) -> String:
	var nm := ""
	var nodes: Variant = bp.get("nodes")
	if nodes is Array:
		for n in nodes:
			if n is Dictionary and String((n as Dictionary).get("uid", "")) == uid:
				nm = String((n as Dictionary).get("name", ""))
				if nm == "":
					var pd: Variant = null
					if bp.has_method("part_def"):
						pd = bp.call("part_def", String((n as Dictionary).get("part", "")))
					if pd != null and (pd as Resource).get("name_prefix") != null:
						nm = String((pd as Resource).get("name_prefix")) + "_" + uid
				break
	if nm != "" and doll.parts.has(nm):
		return nm
	for k in doll.parts.keys():
		if String(k).ends_with("_" + uid):
			return String(k)
	return ""


## Имя управляемого тела: явное control_part, иначе blueprint.control[0] у ModularDoll, иначе "Hand_R".
func _resolve_control_part() -> String:
	if control_part != "":
		return control_part
	var bp: Variant = doll.get("blueprint")
	if bp is Resource:
		var ctrl: Variant = (bp as Resource).get("control")
		if ctrl != null and (ctrl is PackedStringArray or ctrl is Array) and ctrl.size() > 0:
			var uid := String(ctrl[0])
			var nm := ""
			var nodes: Variant = (bp as Resource).get("nodes")
			if nodes is Array:
				for n in nodes:
					if n is Dictionary and String((n as Dictionary).get("uid", "")) == uid:
						nm = String((n as Dictionary).get("name", ""))
						if nm == "":
							var pd: Variant = null
							if (bp as Resource).has_method("part_def"):
								pd = (bp as Resource).call("part_def", String((n as Dictionary).get("part", "")))
							if pd != null and (pd as Resource).get("name_prefix") != null:
								nm = String((pd as Resource).get("name_prefix")) + "_" + uid
						break
			if nm != "" and doll.parts.has(nm):
				return nm
			for k in doll.parts.keys():
				if String(k).ends_with("_" + uid):
					return String(k)
	return "Hand_R"


func grip_global() -> Vector3:
	return part.to_global(grip_local) if part != null else Vector3.ZERO


## Корневой сустав цепи (плечо) в мире — центр круга досягаемости и IK.
func root_point() -> Vector3:
	if _root_body == null or not is_instance_valid(_root_body):
		return grip_global()
	return _root_body.to_global(_root_local)


## Цель, клэмпнутая кругом досягаемости.
func clamp_to_reach(p: Vector3) -> Vector3:
	var r := root_point()
	var off := Vector3(p.x - r.x, p.y - r.y, 0.0)
	var lim := reach * REACH_FRAC
	if off.length() > lim:
		off = off.normalized() * lim
	return r + off


func is_holding() -> bool:
	return held != null and is_instance_valid(held)


## Растяжение пружины хвата (м); INF — ничего не держит.
func hold_distance() -> float:
	if not is_holding():
		return INF
	var d := grip_global() - held.to_global(anchor_local)
	d.z = 0.0
	return d.length()


func credit() -> ThrownCredit:
	return _credit if _credit != null and is_instance_valid(_credit) else null


# ------------------------------------------------------------------ тик

func _physics_process(delta: float) -> void:
	_time += delta
	if doll == null or not _ready_done:
		return
	if primary:
		_tick_reattach()   # и без управляемой детали: её саму могли оторвать, вернуть можно касанием
	if part == null:
		return
	_tick_pending_release()
	var dead := not doll.alive or doll.is_broken() or not is_instance_valid(part) or not is_instance_valid(torso)
	if dead:
		if held != null:
			release("ko")
		_flex_saved.clear()   # суставов больше нет (break_apart)
		arm_active = false
		_update_hints()
		_update_weapon_pickup_block()
		return
	if held != null and not is_instance_valid(held):
		_forget_held("gone")
	if held != null and doll.is_stunned():
		release("stun")
	var inp := _read_input()
	if inp[2]:
		toggle_grab()
	if bool(inp[0]) != arm_active:
		_set_flex(bool(inp[0]))
	arm_active = inp[0]
	last_assist_force = Vector3.ZERO
	if arm_active:
		target = clamp_to_reach(inp[1])
		_tick_flex()
		_apply_assist()
	if held != null:
		_apply_hold()
	# Кандидат на хват нужен только подсветке и подписи (toggle_grab ищет свежий сам): у ботов (show_hints = false) запрос формы каждый тик ≈ 8 мкс зря
	candidate = null if held != null or not primary or not show_hints else find_candidate()
	if held != null:
		blocked_candidate = null
	_update_hints()
	if primary:
		_update_weapon_pickup_block()


## Сгиб средних суставов цепи на время помощи (on) и возврат прежней позы (off). Направление — знак позы покоя сустава.
func _set_flex(on: bool) -> void:
	if not doll.has_method("set_pose"):
		return
	if on:
		var pose: Dictionary = doll.get_pose()
		var names: Array[String] = _mid_joints.duplicate()
		if not _ik.is_empty():
			names.append(String(_ik["root"]))
		for jn in names:
			if pose.has(jn) and not _flex_saved.has(jn):
				_flex_saved[jn] = float(pose[jn])
	elif not _flex_saved.is_empty():
		doll.set_pose(_flex_saved.duplicate(), UNFLEX_BLEND_S)
		_flex_saved.clear()


## Каждый тик активной руки — поза цепи под цель (мышцы помогают силе, а не спорят с ней; set_pose с FLEX_BLEND_S каждый тик —
## сглаживание первого порядка, τ ≈ FLEX_BLEND_S):
##   плечо–локоть–кисть с позой сборки из сцены (doll.tscn, doll_dark.tscn) — IK двух звеньев: сгиб локтя δ по теореме косинусов на
##   расстояние плечо→цель (cos δ = (d² − l1² − l2²) / (2·l1·l2), сторона — как у позы покоя, |δ| не меньше её и ≤ FLEX_MAX_DEG),
##   угол плеча = направление на цель − угол треугольника β (в системе торса, от позы сборки);
##   иначе (ModularDoll без сцены, длинная цепь) — только сгиб средних суставов: IK-угол для одного среднего, FLEX_DEG для нескольких.
func _tick_flex() -> void:
	if _flex_saved.is_empty():
		return
	var want := {}
	var ik_deg := -1.0
	var d := 0.0
	if _mid_joints.size() == 1 and _l1 > 0.01 and _l2 > 0.01:
		d = clampf(root_point().distance_to(target), absf(_l1 - _l2) + 0.01, _l1 + _l2 - 0.005)
		var cphi := clampf((d * d - _l1 * _l1 - _l2 * _l2) / (2.0 * _l1 * _l2), -1.0, 1.0)
		ik_deg = rad_to_deg(acos(cphi))
	if not _ik.is_empty() and ik_deg >= 0.0 and _flex_saved.has(String(_ik["mid"])) and _flex_saved.has(String(_ik["root"])):
		var mid := String(_ik["mid"])
		var rest2 := deg_to_rad(float(_flex_saved[mid]))
		var a21: float = _ik["a21"]
		var rb2: float = _ik["rb2"]
		var bend0 := a21 + rest2 - rb2                       # изгиб в позе покоя (угол звено 2 − звено 1)
		var sgn := signf(bend0) if absf(bend0) > 1e-3 else -1.0
		var bend := sgn * clampf(deg_to_rad(ik_deg), absf(bend0), deg_to_rad(FLEX_MAX_DEG))
		var beta := atan2(_l2 * sin(bend), _l1 + _l2 * cos(bend))
		var t := target - root_point()
		var alpha := torso.global_rotation.z
		var seg1 := atan2(t.y, t.x) - beta                   # мировой угол звена 1 (плечо → локоть)
		var th1 := wrapf(seg1 - alpha - float(_ik["a1"]) + float(_ik["rb1"]), -PI, PI)
		var th2 := bend - a21 + rb2
		want[String(_ik["root"])] = rad_to_deg(th1)
		want[mid] = rad_to_deg(th2)
	else:
		for jn in _mid_joints:
			if not _flex_saved.has(jn):
				continue
			var rest: float = _flex_saved[jn]
			if absf(rest) < 1.0:
				continue   # без позы покоя не знаем, куда сустав гнётся
			var deg := ik_deg if ik_deg >= 0.0 else FLEX_DEG
			want[jn] = signf(rest) * clampf(deg, absf(rest), FLEX_MAX_DEG)
	if not want.is_empty():
		doll.set_pose(want, FLEX_BLEND_S)


## Геометрия IK из позы сборки (SceneState сцены куклы): углы звеньев в системе торса и относительные повороты тел при сборке
## (measured-угол сустава = поворот ребёнка − поворот родителя; 0 — как собрано). Пусто — IK плеча недоступен.
func _setup_ik(chain: Array) -> void:
	_ik = {}
	if chain.size() != 3:
		return
	var hand_b: RigidBody3D = chain[0][0]
	var lower_b: RigidBody3D = chain[1][0]
	var upper_b: RigidBody3D = chain[2][0]
	var tt: Variant = _build_transform("Torso")
	var ut: Variant = _build_transform(String(upper_b.name))
	var lt: Variant = _build_transform(String(lower_b.name))
	var ht: Variant = _build_transform(String(hand_b.name))
	if not (tt is Transform3D and ut is Transform3D and lt is Transform3D and ht is Transform3D):
		return
	var p_root: Vector3 = (chain[2][1] as Node3D).position
	var p_mid: Vector3 = (chain[1][1] as Node3D).position
	var p_grip: Vector3 = (ht as Transform3D) * grip_local
	var b1 := p_mid - p_root
	var b2 := p_grip - p_mid
	var rot := func(t: Transform3D) -> float: return t.basis.get_euler().z
	_ik = {
		"root": String((chain[2][1] as Node).name), "mid": String((chain[1][1] as Node).name),
		"a1": atan2(b1.y, b1.x) - rot.call(tt),
		"a21": atan2(b2.y, b2.x) - atan2(b1.y, b1.x),
		"rb1": rot.call(ut) - rot.call(tt),
		"rb2": rot.call(lt) - rot.call(ut),
	}
	_l1 = b1.length()
	_l2 = b2.length()


## Сила помощи к цели: +F детали в точке хвата, −F в центр торса.
func _apply_assist() -> void:
	var p := grip_global()
	var r := root_point()
	var v_rel := _point_velocity(part, p) - _point_velocity(torso, r)
	v_rel.z = 0.0
	# неявный Эйлер (как у хвата): ẍ = F/m, F = k·e − c·v, e = цель − хват → v' = (v + dt·k·e/m) / (1 + dt·c/m + dt²·k/m),
	# F = m·(v' − v)/dt; m — голая деталь. Явная сила с c·dt/m_кисти ≈ 0.8 вместе с пружиной хвата раскачивала кисть с грузом через тик.
	var dt := maxf(get_physics_process_delta_time(), 1e-4)
	var m := maxf(part.mass, 0.01)
	var e := target - p
	e.z = 0.0
	var v_new := (v_rel + e * (dt * ASSIST_K / m)) / (1.0 + dt * ASSIST_C / m + dt * dt * ASSIST_K / m)
	var f := m * (v_new - v_rel) / dt
	var fmax := ASSIST_F_MAX
	if is_holding():
		fmax = minf(ASSIST_F_MAX + ASSIST_LOAD_ACCEL * held.mass, maxf(ASSIST_F_MAX_LOADED, ASSIST_F_MAX))
	if doll.is_stunned():
		fmax *= 1.0 - Tuning.STUN_CONTROL_LOSS
	f = f.limit_length(fmax)
	part.apply_force(f, p - part.global_position)
	if reaction_to_torso:
		torso.apply_central_force(-f)   # в центр торса: в плечо — та же сумма сил, но торс качается втрое сильнее (5.8° против 1.9°)
	last_assist_force = f


## Пружина хвата: +F предмету в его точке хвата, −F детали в её точке хвата; растяжение > HOLD_SLIP_M — срыв.
func _apply_hold() -> void:
	if _weld != null:
		last_hold_force = Vector3.ZERO
		_apply_hold_angle(WELD_ANG_OMEGA, WELD_TORQUE_MAX)
		return
	if _weld_pending and (hold_distance() <= WELD_SNAP_M or _time - _grab_t >= WELD_SNAP_MAX_S):
		_make_weld()
		return
	var p_h := grip_global()
	var p_i := held.to_global(anchor_local)
	var d := p_h - p_i
	d.z = 0.0
	var stretch := d.length()
	_overstretch_t = _overstretch_t + get_physics_process_delta_time() if stretch > HOLD_SLIP_M else 0.0
	if _overstretch_t >= HOLD_SLIP_S or stretch > 2.0 * HOLD_SLIP_M:
		release("slip")
		return
	var dv := _point_velocity(part, p_h) - _point_velocity(held, p_i)
	dv.z = 0.0
	# неявный Эйлер для относительного движения d = p_h − p_i: d̈ = −F/μ, F = k·d + c·ḋ →
	# ḋ' = (ḋ − dt·k·d/μ) / (1 + dt·c/μ + dt²·k/μ), F = μ·(ḋ − ḋ')/dt. μ — по голой детали (кисть 0.5 кг): настоящая масса на цепи
	# больше, схема тогда недожимает (мягче), но не раскачивается; явная пружина на кисти дрожала через тик (проба classes).
	var dt := maxf(get_physics_process_delta_time(), 1e-4)
	var m_h := maxf(part.mass, 0.01)
	var m_i := maxf(held.mass, 0.01)
	var mu := m_h * m_i / (m_h + m_i)
	var k := mu * HOLD_OMEGA * HOLD_OMEGA
	var c := 2.0 * HOLD_ZETA * mu * HOLD_OMEGA
	var dv_new := (dv - d * (dt * k / mu)) / (1.0 + dt * c / mu + dt * dt * k / mu)
	var f := (mu * (dv - dv_new) / dt).limit_length(HOLD_F_MAX)
	held.apply_force(f, p_i - held.global_position)
	part.apply_force(-f, p_h - part.global_position)
	last_hold_force = f
	_apply_hold_angle()


## Удержание поворота предмета на пружине (средние): момент к углу при захвате, реакция — в торс (у кисти 0.5 кг инерция мала,
## момент в неё раскачал бы руку). I ≈ m·L²/12 по наибольшему размеру коллизии.
func _apply_hold_angle(omega: float = HOLD_ANG_OMEGA, t_max: float = HOLD_TORQUE_MAX) -> void:
	if held.get_parent() is Doll:
		return   # части кукол (живых — вырываются, мёртвых — болтаются как тряпка) не выравниваем
	var box := local_bounds(held)
	var l := maxf(box.size.x, box.size.y)
	var inertia := maxf(held.mass * l * l / 12.0, 0.02)
	var err := wrapf(_z_angle(part) + _hold_angle - _z_angle(held), -PI, PI)
	var w_rel := held.angular_velocity.z - part.angular_velocity.z
	var t := inertia * (omega * omega * err - 2.0 * HOLD_ANG_ZETA * omega * w_rel)
	t = clampf(t, -t_max, t_max)
	held.apply_torque(Vector3(0.0, 0.0, t))
	if reaction_to_torso:
		torso.apply_torque(Vector3(0.0, 0.0, -t))


static func _z_angle(b: Node3D) -> float:
	var x := b.global_transform.basis.x
	return atan2(x.y, x.x)


## Приварить держимый предмет к детали: остаток растяжения досняпывается (точка хвата предмета — в точку хвата детали), жёсткий
## сустав как у WeaponPickup, рука этой стороны — жёсткость руки с оружием.
func _make_weld() -> void:
	_weld_pending = false
	if held == null or not is_instance_valid(held) or part == null:
		return
	var g := grip_global()
	var gap := g - held.to_global(anchor_local)
	gap.z = 0.0
	held.global_position += gap
	held.linear_velocity = _point_velocity(part, g)
	held.angular_velocity = part.angular_velocity
	var j := Generic6DOFJoint3D.new()
	j.name = "Weld_" + part_name
	add_child(j)
	j.global_transform = Transform3D(part.global_transform.basis, g)
	j.exclude_nodes_from_collision = true
	j.node_a = j.get_path_to(part)
	j.node_b = j.get_path_to(held)
	for ax in ["x", "y", "z"]:
		j.set("linear_limit_%s/enabled" % ax, true)
		j.set("linear_limit_%s/upper_distance" % ax, 0.0)
		j.set("linear_limit_%s/lower_distance" % ax, 0.0)
		j.set("angular_limit_%s/enabled" % ax, true)
		j.set("angular_limit_%s/upper_angle" % ax, 0.0)
		j.set("angular_limit_%s/lower_angle" % ax, 0.0)
	_weld = j
	_hold_angle = wrapf(_z_angle(held) - _z_angle(part), -PI, PI)
	_stiff_set.clear()
	for jn in _chain_joint_names:
		var grp := jn.split("_")[0]
		if Tuning.WEAPON_ARM_MUSCLES.has(grp) and doll.joints.has(jn):
			var e: Dictionary = Tuning.WEAPON_ARM_MUSCLES[grp]
			doll.set_muscle_joint(jn, float(e["k"]), float(e.get("tmax", -1.0)), float(e.get("zeta", -1.0)))
			_stiff_set.append(jn)


func is_welded() -> bool:
	return _weld != null and is_instance_valid(_weld)


func _unweld() -> void:
	_weld_pending = false
	if _weld != null and is_instance_valid(_weld):
		_weld.node_a = NodePath()
		_weld.node_b = NodePath()
		_weld.queue_free()
	_weld = null
	if doll != null and is_instance_valid(doll):
		for jn in _stiff_set:
			doll.clear_muscle_joint(jn)
	_stiff_set.clear()


## Бросок к цели руки: скорость √(2·E/m) в [THROW_SPEED_MIN, THROW_SPEED_MAX] поверх скорости торса, отдача торсу, закрутка.
## Части живых кукол и тяжёлые не бросаются (только отпускаются).
func _throw(b: RigidBody3D) -> void:
	if b == null or not is_instance_valid(b) or torso == null:
		return
	var od := b.get_parent() as Doll
	if (od != null and od.alive) or PropHeft.heft_of(b) == PropHeft.Heft.HEAVY:
		return
	var aim := target - root_point()
	aim.z = 0.0
	if aim.length() < 0.15:
		aim = _point_velocity(part, grip_global())
		aim.z = 0.0
	if aim.length_squared() < 1e-4:
		aim = Vector3.UP
	var dir := aim.normalized()
	var m := maxf(b.mass, 0.05)
	var v := clampf(sqrt(2.0 * THROW_ENERGY / m), THROW_SPEED_MIN, THROW_SPEED_MAX)
	var base := torso.linear_velocity * THROW_CARRY
	base.z = 0.0
	b.linear_velocity = base + dir * v
	b.angular_velocity = Vector3(0.0, 0.0, -signf(dir.x if absf(dir.x) > 0.1 else 1.0) * THROW_SPIN * clampf(4.0 / m, 0.3, 1.0))
	torso.apply_central_impulse(-dir * minf(m * v, 150.0) * THROW_RECOIL)
	last_throw = {"body": b, "t": _time, "dir": dir, "speed": v}
	var sfx := get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	if sfx != null:
		sfx.play_layer("whoosh", 0.0, clampf(1.3 - m * 0.03, 0.7, 1.3), SfxDirector.BUS_SFX, sfx.pan_for(b.global_position))


## Нажал захват у тяжёлого на якоре: кисть «упирается» — пыль, глухой звук, подпись мигает.
func _too_heavy_feedback(b: RigidBody3D) -> void:
	var p := closest_point(b, grip_global())
	var m := get_tree().get_first_node_in_group("match")
	ImpactFx.spawn_impact(m if m != null else doll.get_parent(), p, Vector3.UP, 3.0, "")
	var sfx := get_tree().get_first_node_in_group(SfxDirector.GROUP) as SfxDirector
	if sfx != null:
		sfx.play_layer("thud", -3.0, 0.7, SfxDirector.BUS_SFX, sfx.pan_for(p))
	if _hint != null:
		_hint.scale = Vector3.ONE * 1.35


## Скорость точки p тела b (v + ω × r от центра масс).
static func _point_velocity(b: RigidBody3D, p: Vector3) -> Vector3:
	var com := b.global_position
	var st := PhysicsServer3D.body_get_direct_state(b.get_rid())
	if st != null:
		com += st.center_of_mass
	return b.linear_velocity + b.angular_velocity.cross(p - com)


# ------------------------------------------------------------------ захват

## Клавиша захвата: держит — отпустить (бросок); в кисти оружие — бросить оружие; иначе — схватить ближайшее.
func toggle_grab() -> void:
	if held != null:
		release("toggle")
		last_grab_action = "release"
		return
	if doll.is_stunned():
		last_grab_action = "none"
		return   # в стане кукла — пассивный рэгдолл, кисть не хватает
	var own := _own_detached_near(grip_global(), GRAB_RADIUS)
	if own != null and reattach_own(own, "grab"):
		last_grab_action = "reattach"
		return
	var wp := _weapon_pickup()
	if wp != null and wp.call("weapon_in", part_name) != null:
		var w := wp.call("weapon_in", part_name) as RigidBody3D
		wp.call("drop", part_name)
		_wp_block_until = _time + REPICK_BLOCK_S
		last_grab_action = "drop_weapon"
		if arm_active and w != null and is_instance_valid(w):
			_throw(w)
		return
	var c := find_candidate()
	if c != null and grab(c):
		last_grab_action = "grab"
	elif c == null and blocked_candidate != null and is_instance_valid(blocked_candidate):
		last_grab_action = "too_heavy"
		_too_heavy_feedback(blocked_candidate)
	else:
		last_grab_action = "none"


## Можно ли схватить тело (без проверки расстояния).
func can_grab(b: Node) -> bool:
	var rb := b as RigidBody3D
	if rb == null or not is_instance_valid(rb) or rb.freeze or rb == held:
		return false
	if rb is Weapon or rb.is_in_group(Weapon.GROUP):
		return false
	var owner_doll := rb.get_parent() as Doll
	if owner_doll == doll:
		return false   # свои части (и после KO — тоже: сломанная кукла не хватает)
	if owner_doll != null and owner_doll.alive and not GRAB_DOLLS:
		return false
	return true


## Ближайший схватываемый предмет в GRAB_RADIUS от точки хвата (null — нет).
func find_candidate() -> RigidBody3D:
	if part == null or not part.is_inside_tree():
		return null
	var space := part.get_world_3d().direct_space_state
	if space == null:
		return null
	if _query == null:
		_query = PhysicsShapeQueryParameters3D.new()
		var sph := SphereShape3D.new()
		sph.radius = GRAB_RADIUS
		_query.shape = sph
		_query.collide_with_areas = false
		_query.collide_with_bodies = true
		var ex: Array[RID] = []
		for p in doll.parts.values():
			ex.append((p as RigidBody3D).get_rid())
		_query.exclude = ex
	var g := grip_global()
	_query.transform = Transform3D(Basis.IDENTITY, g)
	var best: RigidBody3D = null
	var best_d := INF
	var heavy: RigidBody3D = null
	var heavy_d := INF
	for r in space.intersect_shape(_query, 24):
		var b := r.get("collider") as RigidBody3D
		if b == null:
			continue
		var grabbable := can_grab(b)
		if not grabbable and not (b.freeze and PropHeft.anchor_of(b) != null):
			continue
		var dist := g.distance_to(closest_point(b, g))
		if dist > GRAB_RADIUS:
			continue
		if grabbable and dist < best_d:
			best_d = dist
			best = b
		elif not grabbable and dist < heavy_d:
			heavy_d = dist
			heavy = b
	blocked_candidate = heavy
	return best


## Схватить тело: точка хвата на предмете — ближайшая к кисти точка его коллизий (пружина стягивает их за доли секунды).
func grab(b: RigidBody3D) -> bool:
	if held != null or not can_grab(b):
		return false
	_cancel_pending_release(b)
	held = b
	_overstretch_t = 0.0
	var cp := closest_point(b, grip_global())
	anchor_local = b.to_local(cp)
	var exc := b.get_collision_exceptions()
	for p in doll.parts.values():
		if not exc.has(p):
			b.add_collision_exception_with(p)   # Jolt хранит дубли: повторный захват до снятия исключений оставил бы копию навсегда
	var od := b.get_parent() as Doll
	_credit = null
	if od == null or not od.alive:
		_credit = ThrownCredit.attach(b, doll)
	_grab_t = _time
	_weld_pending = weld_light and (od == null or not od.alive) and b.mass <= WELD_MAX_KG and PropHeft.heft_of(b) == PropHeft.Heft.LIGHT
	_hold_angle = wrapf(_z_angle(b) - _z_angle(part), -PI, PI)
	_set_highlight(null)
	_holders[b.get_instance_id()] = self
	grabbed.emit(b)
	return true


## Отпустить (бросок): предмет уходит со своей скоростью, зачёт — ThrownCredit.WINDOW_S; исключения коллизий снимаются позже.
func release(reason: String = "toggle") -> void:
	if held == null:
		return
	var b := held
	held = null
	last_hold_force = Vector3.ZERO
	_unweld()
	_unregister_hold(b)
	if is_instance_valid(b):
		if reason == "toggle" and arm_active and doll.alive:
			_throw(b)
		var pos := b.global_position if b.is_inside_tree() else b.position   # выход из дерева (смена арены): глобального нет
		last_release = {"body": b, "reason": reason, "t": _time, "velocity": b.linear_velocity, "position": pos}
		var c := credit()
		if c != null:
			c.release()
		_pending_release.append([b, _time + RELEASE_EXCEPT_S, _time + RELEASE_EXCEPT_MAX_S])
	_credit = null
	released.emit(b, reason)


## Break_apart куклы зовёт drop_all у детей (как у WeaponPickup) — KO отпускает предмет.
func drop_all() -> void:
	release("ko")


## Doll.detach_part (Разборщик, пресс): если оторвали управляемую деталь или цепь, на которой она висит (её больше нет в
## doll.parts), — отпустить предмет, вернуть позу руки и перестать управлять: мышь не таскает оторванную кисть.
func _on_part_detached(_detached_name: String, _by: Node) -> void:
	if part == null or doll.parts.has(part_name):
		return
	if held != null:
		release("detached")
	_set_flex(false)
	arm_active = false
	candidate = null
	_update_hints()
	_restore_weapon_pickup()
	part = null


## Doll.part_reattached: вернулась управляемая деталь (или цепь, на которой она висит) — собрать цепь и IK заново (как _setup).
func _on_part_reattached(_name: String) -> void:
	if part == null and doll.parts.has(part_name):
		_rebind()


func _rebind() -> void:
	_ready_done = false
	_mid_joints.clear()
	_ik = {}
	_l1 = 0.0
	_l2 = 0.0
	_flex_saved.clear()
	_query = null   # исключения запроса кандидатов — по текущим частям куклы
	_setup()


## Кто держит тело (ArmAssist) или null.
static func holder_of(b: Object) -> ArmAssist:
	if b == null or not is_instance_valid(b):
		return null
	var h: Variant = _holders.get(b.get_instance_id(), null)
	if h == null or not is_instance_valid(h) or (h as ArmAssist).held != b:
		return null
	return h


func _unregister_hold(b: Object) -> void:
	if b == null:
		return
	var id := b.get_instance_id()
	if _holders.get(id, null) == self:
		_holders.erase(id)


## Своя оторванная деталь: касание любой частью куклы → на место (см. шапку: REATTACH_TOUCH_M, REATTACH_GRACE_S, не в чужой руке).
func _tick_reattach() -> void:
	if not doll.has_method("detached_parts") or not doll.alive or doll.is_broken():
		return
	var list: Array = doll.call("detached_parts")
	if list.is_empty():
		_detach_seen.clear()
		return
	for b in list:
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		var id := rb.get_instance_id()
		if not _detach_seen.has(id):
			_detach_seen[id] = _time
			continue
		if _time - float(_detach_seen[id]) < REATTACH_GRACE_S:
			continue
		var h := holder_of(rb)
		if h != null and h != self:
			continue   # в руке у вора (или у товарища) — сначала выбить
		for p in doll.parts.values():
			var pp := (p as Node3D).global_position
			if closest_point(rb, pp).distance_to(pp) <= REATTACH_TOUCH_M:
				if reattach_own(rb, "touch"):
					return
				break


## Своя оторванная деталь в radius от точки p (для клавиши захвата), null — нет.
func _own_detached_near(p: Vector3, radius: float) -> RigidBody3D:
	if not doll.has_method("detached_parts"):
		return null
	var best: RigidBody3D = null
	var best_d := radius
	for b in doll.call("detached_parts"):
		var rb := b as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			continue
		var h := holder_of(rb)
		if h != null and h != self:
			continue
		var d := closest_point(rb, p).distance_to(p)
		if d <= best_d:
			best_d = d
			best = rb
	return best


## Прикрутить свою оторванную деталь (Doll.reattach_part). Чужую — нет (meta detached_from).
func reattach_own(rb: RigidBody3D, how: String) -> bool:
	if rb == null or not is_instance_valid(rb) or rb.get_meta("detached_from", null) != doll:
		return false
	if held == rb:
		release("reattach")
	if not bool(doll.call("reattach_part", rb)):
		return false
	_detach_seen.erase(rb.get_instance_id())
	last_reattach = {"body": rb, "name": String(rb.name), "t": _time, "how": how}
	return true


func _forget_held(reason: String) -> void:
	var b := held
	held = null
	_unweld()
	_unregister_hold(b)
	_credit = null
	released.emit(b, reason)


func _tick_pending_release() -> void:
	var i := 0
	while i < _pending_release.size():
		var e: Array = _pending_release[i]
		if not is_instance_valid(e[0]):
			_pending_release.remove_at(i)
			continue
		var b: RigidBody3D = e[0]
		if not is_instance_valid(b):
			_pending_release.remove_at(i)
			continue
		if _time >= float(e[1]) and (_time >= float(e[2]) or not _near_doll(b)):
			_remove_exceptions(b)
			_pending_release.remove_at(i)
		else:
			i += 1


func _cancel_pending_release(b: RigidBody3D) -> void:
	for i in range(_pending_release.size() - 1, -1, -1):
		if _pending_release[i][0] == b:
			_pending_release.remove_at(i)


func _remove_exceptions(b: RigidBody3D) -> void:
	if not is_instance_valid(b) or b == held:
		return
	for p in doll.parts.values():
		if is_instance_valid(p):
			b.remove_collision_exception_with(p)


## Пересекается ли AABB предмета (с зазором RELEASE_CLEAR_M) с AABB частей куклы.
func _near_doll(b: RigidBody3D) -> bool:
	var box := b.global_transform * local_bounds(b)
	box = box.grow(RELEASE_CLEAR_M)
	for p in doll.parts.values():
		if not is_instance_valid(p):
			continue
		var pb := (p as RigidBody3D).global_transform * local_bounds(p)
		if box.intersects(pb):
			return true
	return false


## Ближайшая к p точка тела (по AABB его коллизий в локальных координатах: для боксов точно, для цилиндров/оболочек — оценка).
func closest_point(b: RigidBody3D, p: Vector3) -> Vector3:
	var box := local_bounds(b)
	var lp := b.to_local(p)
	var c := Vector3(clampf(lp.x, box.position.x, box.end.x), clampf(lp.y, box.position.y, box.end.y), clampf(lp.z, box.position.z, box.end.z))
	return b.to_global(c)


## Объединённый AABB коллизий тела в его локальных координатах (кэш по телу).
func local_bounds(b: RigidBody3D) -> AABB:
	var id := b.get_instance_id()
	if _bounds_cache.has(id):
		return _bounds_cache[id]
	var box := AABB()
	var first := true
	for cs in b.find_children("*", "CollisionShape3D", true, false):
		var shape_node := cs as CollisionShape3D
		if shape_node.shape == null or shape_node.disabled:
			continue
		var sb := _shape_aabb(shape_node.shape)
		var tb := (b.global_transform.affine_inverse() * shape_node.global_transform) * sb
		if first:
			box = tb
			first = false
		else:
			box = box.merge(tb)
	if first:
		box = AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	_bounds_cache[id] = box
	return box


static func _shape_aabb(sh: Shape3D) -> AABB:
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		return AABB(-s / 2.0, s)
	if sh is SphereShape3D:
		var r := (sh as SphereShape3D).radius
		return AABB(-Vector3.ONE * r, Vector3.ONE * r * 2.0)
	if sh is CylinderShape3D:
		var cy := sh as CylinderShape3D
		return AABB(Vector3(-cy.radius, -cy.height / 2.0, -cy.radius), Vector3(cy.radius * 2.0, cy.height, cy.radius * 2.0))
	if sh is CapsuleShape3D:
		var ca := sh as CapsuleShape3D
		return AABB(Vector3(-ca.radius, -ca.height / 2.0, -ca.radius), Vector3(ca.radius * 2.0, ca.height, ca.radius * 2.0))
	if sh is ConvexPolygonShape3D:
		var pts := (sh as ConvexPolygonShape3D).points
		if pts.size() > 0:
			var bx := AABB(pts[0], Vector3.ZERO)
			for q in pts:
				bx = bx.expand(q)
			return bx
	return sh.get_debug_mesh().get_aabb() if sh.get_debug_mesh() != null else AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))


# ------------------------------------------------------------------ оружие в кисти

func _weapon_pickup() -> Node:
	for c in doll.get_children():
		if c != self and c.has_method("weapon_in") and c.has_method("drop"):
			return c
	return null


## Авто-подбор WeaponPickup выключен, пока держим пропс, и REPICK_BLOCK_S после броска оружия клавишей. Если WeaponPickup умеет
## блокировать одну кисть (set_hand_blocked), блокируем только управляемую — вторая рука продолжает подбирать оружие; иначе, как
## раньше, выключаем общий auto_pickup и потом возвращаем прежнее значение (после KO не возвращаем: break_apart сам выключает подбор).
func _update_weapon_pickup_block() -> void:
	var wp := _weapon_pickup()
	if wp == null:
		return
	var want := held != null or _time < _wp_block_until
	if wp.has_method("set_hand_blocked"):
		if part_name != "" and bool(wp.call("is_hand_blocked", part_name)) != want:
			wp.call("set_hand_blocked", part_name, want)
		return
	if wp.get("auto_pickup") == null:
		return
	if want and _wp_saved == null:
		_wp_saved = wp.get("auto_pickup")
		wp.set("auto_pickup", false)
	elif not want and _wp_saved != null:
		if doll.alive and not doll.is_broken():
			wp.set("auto_pickup", _wp_saved)
		_wp_saved = null


func _restore_weapon_pickup() -> void:
	if doll == null or not is_instance_valid(doll):
		return
	var wp := _weapon_pickup()
	if wp != null and wp.has_method("set_hand_blocked") and part_name != "":
		wp.call("set_hand_blocked", part_name, false)
	if _wp_saved == null:
		return
	if wp != null and doll.alive and not doll.is_broken():
		wp.set("auto_pickup", _wp_saved)
	_wp_saved = null


# ------------------------------------------------------------------ подсказки

func _make_hints() -> void:
	var col: Color = Tuning.PLAYER_COLORS[clampi(doll.player_index, 0, Tuning.PLAYER_COLORS.size() - 1)]
	var ring := TorusMesh.new()
	ring.inner_radius = MARKER_RADIUS * 0.62
	ring.outer_radius = MARKER_RADIUS
	ring.rings = 24
	ring.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	mat.render_priority = 10
	ring.material = mat
	_marker = MeshInstance3D.new()
	_marker.name = "ArmTarget"
	_marker.mesh = ring
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level = true
	_marker.visible = false
	add_child(_marker)
	_hl_material = StandardMaterial3D.new()
	_hl_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hl_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hl_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hl_material.albedo_color = Color(lerpf(col.r, 1.0, 0.5), lerpf(col.g, 1.0, 0.5), lerpf(col.b, 1.0, 0.5), HIGHLIGHT_ALPHA)
	_hl_material.set_meta(HL_META, true)
	_hint = Label3D.new()
	_hint.name = "GrabHint"
	_hint.font_size = 30
	_hint.pixel_size = 0.004
	_hint.outline_size = 10
	_hint.outline_modulate = Color(0.06, 0.04, 0.02, 0.9)
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.no_depth_test = true
	_hint.shaded = false
	_hint.double_sided = true
	_hint.render_priority = 5
	_hint.outline_render_priority = 4
	_hint.top_level = true
	_hint.visible = false
	add_child(_hint)


func _update_hints() -> void:
	if _marker != null:
		_marker.visible = arm_active and show_hints
		if _marker.visible:
			# кольцо лицом к камере (+Z): TorusMesh лежит в XZ — поворот на 90° вокруг X
			_marker.global_transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), target + Vector3(0, 0, 0.3))
	_set_highlight(candidate if show_hints and doll.alive else null)
	if _hl_material != null:
		var a := HIGHLIGHT_ALPHA * (0.75 + 0.25 * sin(_time * TAU * HIGHLIGHT_PULSE_HZ))
		_hl_material.albedo_color.a = a
	_update_label()


## Подпись над предметом (только живой игрок: у ботов и проб — нет).
func _update_label() -> void:
	if _hint == null:
		return
	var show := show_hints and doll.alive and not doll.external_input
	var key := "E" if _mouse_enabled() else "RB"
	var aim := "ЛКМ" if _mouse_enabled() else "стик"
	var b: RigidBody3D = null
	var text := ""
	var kind := "grab"
	if held != null and is_instance_valid(held):
		b = held
		if held.get_parent() is Doll and (held.get_parent() as Doll).alive:
			text = "%s — отпустить" % key
		else:
			text = "%s+%s — бросок · %s — отпустить" % [aim, key, key]
		kind = "held"
	elif candidate != null and is_instance_valid(candidate):
		b = candidate
		var h := PropHeft.heft_of(candidate)
		if h == PropHeft.Heft.MEDIUM and not (candidate.get_parent() is Doll):
			text = "%s — тащить (тяжёлое)" % key
			kind = "medium"
		else:
			text = "%s — взять" % key
	elif blocked_candidate != null and is_instance_valid(blocked_candidate):
		b = blocked_candidate
		text = "слишком тяжело"
		kind = "heavy"
	if not show or b == null:
		_hint.visible = false
		return
	_hint.text = text
	_hint.modulate = HINT_COLOURS[kind]
	var box := b.global_transform * local_bounds(b)
	_hint.global_position = Vector3(box.get_center().x, box.end.y + HINT_UP_M, 0.6)
	_hint.scale = _hint.scale.lerp(Vector3.ONE, 0.2)
	_hint.visible = true


## Подсветка предмета. Один предмет могут подсвечивать несколько рук (P1 и P2 тянутся к одному ящику): исходный overlay и
## список рук — в общем реестре _hl_registry, так что рука никогда не сохраняет чужую подсветку как «исходную» (иначе после
## отпускания обеими подсветка залипала). Сверху — подсветка последней подсветившей руки; ушла последняя — исходный overlay.
func _set_highlight(b: RigidBody3D) -> void:
	if b == _highlighted and (b == null or is_instance_valid(b)):
		return
	for id in _saved_overlays.keys():
		_hl_release(int(id))
	_saved_overlays.clear()
	_highlighted = b
	if b == null or _hl_material == null or not is_instance_valid(b):
		return
	for gi in b.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		var id := g.get_instance_id()
		if not _hl_registry.has(id):
			_hl_registry[id] = {"orig": g.material_overlay, "users": []}
		(_hl_registry[id]["users"] as Array).append(self)
		g.material_overlay = _hl_material
		_saved_overlays[id] = true


## Рука снимает свою подсветку с GeometryInstance3D (по instance id): остались другие руки — сверху подсветка последней из них,
## никого — исходный overlay (если сверху всё ещё чья-то подсветка, а не материал, поставленный кем-то другим).
func _hl_release(id: int) -> void:
	var e: Dictionary = _hl_registry.get(id, {})
	if e.is_empty():
		return
	var users: Array = e["users"]
	users.erase(self)
	var i := users.size() - 1
	while i >= 0:
		if not is_instance_valid(users[i]):
			users.remove_at(i)
		i -= 1
	var g := instance_from_id(id) as GeometryInstance3D
	if users.is_empty():
		_hl_registry.erase(id)
	if g == null or not is_instance_valid(g):
		_hl_registry.erase(id)
		return
	var ours := g.material_overlay != null and g.material_overlay.has_meta(HL_META)
	if not ours:
		return   # overlay сменил кто-то другой — не трогаем
	g.material_overlay = (users.back() as ArmAssist)._hl_material if not users.is_empty() else e["orig"]
