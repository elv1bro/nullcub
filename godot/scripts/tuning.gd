## Единственный источник чисел баланса. Основа — CONCEPT.md автора (27.09.2026);
## тайминги матча совпадают с TS-проектом (src/lib/battleTuning.ts).
extends Node

# --- матч (CONCEPT.md §1, §12) ---
const MAX_HP := 100.0
const BATTLE_TIME_LIMIT_S := 90.0       # дальше Sudden Death
const COUNTDOWN_S := 3.0                # отсчёт до FIGHT!
const SUDDEN_DEATH_STEP_S := 10.0
const BATTLE_HARD_TIMEOUT_S := 180.0
const SPAWN_GRACE_S := 0.7

# --- урон (CONCEPT.md §8, план 06): Damage = min(m, MASS_CAP) × max(0, v − MIN_IMPACT_SPEED) × DAMAGE_COEF × BodyMult × TargetMult × WeaponMult × combo ---
# Калибровка (scripts/core/damage.gd печатает таблицу; tests/combat_gate.gd проверяет полосы): торс о торс 3 м/с ≈ 2.9 (1–3),
# кисть в торс 10 м/с ≈ 8.1 (8–15), молот 8 м/с ≈ 29.6 (20–30), торс в голову 15 м/с ≈ 38 (30–50).
const MIN_IMPACT_SPEED := 1.5           # м/с относительной скорости по нормали, ниже урона нет
const DAMAGE_COEF := 0.95               # HP на (кг·м/с) сверх порога
const MASS_CAP := 4.0                   # кг; торс 12 и молот 6 не «давят массой» — иначе полосы концепта не сходятся
const DAMAGE_MAX := 60.0                # HP за один удар; «экстремальное столкновение 30–50+», один удар не снимает 100
# Голова как бьющая часть 0.35 (ниже торса 0.5): голова — уязвимая цель (×1.5), а не таран; оружие скилла — конечности по
# инерции (Hand 2.0). В CONCEPT_GAP предлагалось 1.5: тогда обычный встречный разбег давал обоим по 40 HP, и таран головой бил
# сильнее любой техники; при 0.5 клинч голов в непрерывной рубке (гейт rush_damage) всё ещё давал > 120 HP за 15 с.
# Скорость удара = min(сближение, собственная скорость бьющего по нормали): встречные 9 + 9 м/с = удар 9, не 18.
const BODY_MULT := {"Head": 0.35, "Torso": 0.5, "Hand": 2.0, "Foot": 1.2, "UpperArm": 0.8, "LowerArm": 1.0, "UpperLeg": 0.6, "LowerLeg": 0.7}
const HEAD_HIT_MULT := 1.5              # удар В голову (TargetMult); клинч голова-о-голову бьёт обоих без него
const PAIR_HIT_COOLDOWN_S := 0.25       # одна пара (атакующий, жертва) — не чаще; исключение — DOUBLE BLOW
const DOUBLE_BLOW_WINDOW_S := 0.1       # второе попадание другим телом по той же жертве в это окно = DOUBLE BLOW (RM)
const DOUBLE_BLOW_MULT := 0.6           # урон второго попадания: в клинче двух рэгдоллов по 10 частей второй контакт почти всегда есть
const ANNOUNCE_MIN_DAMAGE := 5.0        # надписи HEAD/BODY BLOW только от этого урона (иначе спам от касаний)

# --- урон от окружения (В6, по умолчанию включён): стены, пол, пропсы бьют при v ≥ ENV_MIN_IMPACT_SPEED ---
const ENV_DAMAGE_ENABLED := false   # решение автора 28.09: стены/пол/пропсы урона не наносят (статистика wall_collisions остаётся)
const ENV_MIN_IMPACT_SPEED := 6.0       # м/с; падение с яруса — 0, влёт головой в стену на 15 м/с ≈ 26 HP
const ENV_DAMAGE_MULT := 0.5
const ENV_WALL_COLLISION_SPEED := 4.0   # м/с: с этой скорости контакт со статикой идёт в stats.wall_collisions (Wall Inspector)
const WEAPON_ATTACKER_WINDOW_S := 3.0   # брошенное оружие засчитывается бывшему владельцу столько секунд, дальше «environment»

# --- knockback (CONCEPT.md §5): импульс жертве J = clamp(Damage × KNOCKBACK_PER_DAMAGE × sd, 0, KNOCKBACK_MAX) ---
# RM (FEEL_TARGET §9, H = 1.8 м): обычный удар шлёт жертву на 1–2 H/с (1.8–3.6 м/с), тяжёлый (рывок, оружие, в голову) ≤ ~3 H/с (5.5),
# полёт гаснет до < 0.4 м/с за ~1–1.2 с, оседание после удара постоянное 0.7–1.25 м/с. Было 9 / 500 / FLIGHT 0.1: 30 HP → 6.4 м/с
# и полёт не гас 3 с (14 м), оседание разгонялось до 3.9 м/с. Кукла 40 кг, апбиас 0.35 → vx ЦМ = 0.944·J/40.
const KNOCKBACK_PER_DAMAGE := 10.0      # Н·с на 1 HP: 10 HP → 100 Н·с → 2.3 м/с ЦМ (feel_probe hit_flight_10)
const KNOCKBACK_MAX := 210.0            # Н·с: с 21 HP → 4.8 м/с ЦМ, дальше режет FLIGHT_MAX_SPEED (hit_flight_30: 4.3 м/с)
const KNOCKBACK_UP_BIAS := 0.35         # прибавка к y нормализованного направления — кукла отрывается от земли
const KNOCKBACK_TORSO_SHARE := 0.5      # доля импульса в торс, остальное в ударенную часть (закрутка). v6.2: критик круга 2 предлагал 0.3 —
                                        # складывание в пробе то же (кисть/стопу режет KNOCKBACK_PART_MAX_DV), а конечность после удара в 6 HP
                                        # хлещет в ответ до 14 м/с: combat_gate rush_damage 36 → 94 HP за 15 с (голень → стопа 17.7 HP). Оставлено 0.5
const KNOCKBACK_PART_MAX_DV := 20.0     # м/с: кисть 0.5 кг не получает 200 м/с — излишек уходит в торс
const KNOCKBACK_FREE_S := 1.5           # с после удара вместо клэмпа MAX_MOVE_SPEED торса — клэмп ЦМ FLIGHT_MAX_SPEED
const FLIGHT_MAX_SPEED := 4.5           # м/с ЦМ жертвы в полёте, 2.5 H/с (RM тяжёлый ≤ 3 H/с): контакт атакующего в шаге физики добавляет
                                        # ещё до +0.5; рывок 14 м/с продавливал жертву до 6–7.3 м/с, теперь 3.0–4.5 (hit_dash, 7 зазоров)
const FLIGHT_LINEAR_DAMP := 1.8         # дамп частей в полёте до первого касания статики: 2.3 м/с → 0.4 за 0.93 с, 4.3 → 0.4 за 1.25 с;
                                        # оседание g/d = 1.1 м/с (было 0.1: полёт 3+ с, падение разгонялось до 3.9 м/с)
const FLIGHT_TRACK_DAMAGE := 15.0       # HP: с такого удара считается дальность полёта (stats.flight_distance)
# v6.2 (критик круга 2, «Отброс» = 2/5): в клипе v6 лобовой удар гасил обе куклы в ноль за кадр, и они 5 с летели, сцепившись (< 1 H
# между ЦМ): импульс отброса 10 Н·с/HP × 7 HP = 70 Н·с меньше встречного импульса атакующего 40 кг × 4.7 м/с ≈ 188 Н·с. У RM жертва
# уходит на ~1 H/с, бьющий зависает поодаль. DollCombat._deliver на засчитанный удар куклой/оружием (feel_probe hit_rush/dash/clash:
# ЦМ разошлись с 1.9 до 3.2–3.4 м за 0.6 с — было 0.7–1.0; атакующий через 0.3 с отходит — было +3.0…+3.9 м/с к жертве; клип Void:
# 1.57 → 2.72 м и 1.23 → 3.20 м за 0.6 с — было < 1 H 5 с подряд). 85 Н·с / 0.35 давали в клипе 2.42 и 2.14 м (< 1.5 H):
const KNOCKBACK_MIN := 100.0            # Н·с: нижняя граница импульса жертве → 0.944·100/40 = 2.4 м/с ЦМ (RM 1–2 H/с = 1.8–3.6); добор
                                        # до минимума — только в торс; подлёт жертвы к бьющему вдоль удара гасится (Doll.apply_knockback)
const HIT_ATTACKER_RECOIL := 0.5        # атакующий: сближающая скорость ЦМ вдоль удара → −0.5 × Δv ЦМ жертвы (−1.25 м/с при 100 Н·с)
const HIT_ATTACKER_THRUST_LOCK_S := 0.3 # с без тяги у атакующего после удара (не «дожимает» жертву телом; v6 — +2.9…5.3 м/с следом)
# Ослабление мышц жертвы на удар (RM 00:16.6–17.3: все четыре конечности складываются в одну сторону и возвращаются к +0.67 с).
# v6.2: 0.2 на 0.4 с + 0.3 с — 10 HP в торс складывали ведущее бедро на 44°, плечо на 31° (RM ≥ 90°).
# v7 (FEEL_TARGET §9.4, feel_probe hit_flight_10): складывание держало не пружина, а трение шарнира — после толчка сложенная рука
# едет медленно, и 1.4 Н·м плеча останавливали её на ~40° даже при k = 0 (f_Shoulder 0 → 59°, + k 0 → 83°). Поэтому на удар
# конечности на 0.35 с полностью расслаблены (k, tmax, c и трение × 0) и за 0.2 с возвращаются: плечо 79° / бедро 61° за 0.4 с,
# в ±10° позы к 0.60 / 0.85 с после удара. Перебор: 0.05–0.1 → плечо 44–51°, бедро 55–58°; hold 0.4 / recover 0.3 → возврат бедра 0.97 с.
const HIT_MUSCLE_SOFT := 0.0            # множитель k и tmax мышц (c — × √, ζ сохраняется); 1 = выкл.
const HIT_MUSCLE_SOFT_S := 0.35         # держится столько, затем линейный возврат за HIT_MUSCLE_RECOVER_S
const HIT_MUSCLE_RECOVER_S := 0.2
const HIT_FRICTION_SOFT := true         # v7: трение шарниров × тот же множитель на время ослабления (Doll._refresh_friction)
# v7: колено на удар НЕ слабеет — нога складывается в бедре одним рычагом (RM), а не в колене: с мягким коленом голень гасила
# складывание бедра (10 HP в торс: бедро 59° → 66° за 0.4 с при жёстком колене)
const HIT_MUSCLE_SOFT_GROUPS := ["Neck", "Shoulder", "Elbow", "Wrist", "Hip", "Ankle"]

# --- стан (CONCEPT.md §9, В7): удар ≥ порога → 0.8 + 0.06·Damage с, clamp ---
const STUN_DAMAGE_THRESHOLD := 20.0
const STUN_BASE_S := 0.8
const STUN_PER_DAMAGE_S := 0.06
const STUN_MIN_S := 1.0
const STUN_MAX_S := 3.5
const STUN_CONTROL_LOSS := 0.85         # доля потерянного контроля в стане
const STUN_MUSCLE_STIFFNESS := 0.0      # в стане кукла — пассивный рэгдолл
const STUN_JOINT_FRICTION := 1.0        # Н·м
const STUN_RECOVER_S := 0.5             # мышцы возвращаются линейно, кукла не «вскакивает»

# --- комбо (RM, В7): урон × (1 + COMBO_STEP·min(n, COMBO_MAX_N)), n = удары атакующего в окне; сбрасывается, когда его бьют ---
const COMBO_WINDOW_S := 1.5
const COMBO_STEP := 0.15
const COMBO_MAX_N := 4

# --- Sudden Death (CONCEPT.md §12, В8): хаос растёт, урон нет. Шаг n = floor((t − 90) / 10): 100 с → n = 1 ---
const SUDDEN_DEATH_KNOCKBACK_STEP := 0.25     # knockback × (1 + 0.25·n)
const SUDDEN_DEATH_STABILITY_STEP := 0.15     # мышцы и трение × max(SUDDEN_DEATH_STABILITY_MIN, 1 − 0.15·n)
const SUDDEN_DEATH_STABILITY_MIN := 0.3
const SUDDEN_DEATH_HEAVY_WEAPON_STEP := 1     # n = 1 (100 с): молот в центре арены (спавн — интегратор/арена)
const SUDDEN_DEATH_BREAK_PLATFORMS_STEP := 3  # n = 3 (120 с): деревянный мост ломается (арена)

# --- подача удара (05 «Камера», INSPIRATION_GAMES.md): читает Match.hit_feel ---
const HIT_SHAKE_PER_10HP := 0.03        # м тряски камеры на 10 HP (макс — DynamicCamera.max_shake)
const HIT_ZOOM_DAMAGE := 20.0           # zoom impulse −5 % на 0.2 с от этого урона
const HIT_ZOOM_FRAC := -0.05
const HIT_ZOOM_S := 0.2
const HIT_STOP_DAMAGE_1 := 20.0         # hit stop 80 мс
const HIT_STOP_DAMAGE_2 := 35.0         # hit stop 120 мс
const HIT_STOP_S_1 := 0.08
const HIT_STOP_S_2 := 0.12
const HIT_STOP_TIME_SCALE := 0.05
const KO_SLOWMO_SCALE := 0.25           # 09: в момент KO замедление на KO_SLOWMO_S
const KO_SLOWMO_S := 1.2
const KO_BURST_SPEED := Vector2(2.0, 4.0)  # м/с радиального разлёта частей при KO (В3: суставы рвутся, как в RM)

# --- мир: arcade physics (CONCEPT.md §5), полёты на 10–20 длин тела ---
const GRAVITY := 2.0                    # м/с²; решение автора 28.09: между RM (≈0) и концептом (5); тяга вверх > g — парить можно
const LINEAR_DAMP := 0.25               # воздушное сопротивление мира: оружие (weapon.gd, build_weapon_scenes.gd), пропсы
const DOLL_LINEAR_DAMP := 2.25          # v6.2: дамп ЯДРА (голова + торс, 16 кг); конечности — DOLL_LIMB_LINEAR_DAMP (см. doll_linear_damp()).
                                        # v6 было 1.5 на всех частях (FEEL_TARGET §4). 2.25 → средневзвешенный (16·2.25 + 24·1.5)/40 = 1.8:
                                        # оседание g/d 1.1 м/с (feel_probe hover_fall −0.89 м/с через 1 с, RM 0.7–1.25), терминальная тяги
                                        # 12/1.8 = 6.7 м/с — «полка» скорости (было 8; критик круга 2), разгон 0 → 4.1 м/с за 0.5 с (RM 3.6–5.4),
                                        # стоп после отпускания 1.23 → 1.00 с, накат 2.83 → 2.17 м (RM ~1 с, ~1 H), перелёт руки 22.6 → 29.4 %.
                                        # Отдельно от LINEAR_DAMP: при 1.5 на оружии брошенный молот 10 м/с долетал 5.6 м/с (combat_gate loose_weapon)
const ANGULAR_DAMP := 0.6               # мир/оружие и ядро куклы
# v6.2 (FEEL_TARGET §9.2, критик круга 2): дамп конечностей отдельно от ядра. Линейный дамп части m·d·v на махе руки ω·r — лишнее
# демпфирование сустава c_extra ≈ d·I_конечности (плечо 1.5 × 0.57 = 0.86 Н·м·с при c мышцы 1.58). Перебор feel_probe
# (ldc/ldl/adl/brake/z_Shoulder/t_Shoulder/f_Shoulder, ~270 прогонов): конечности 0.6–1.25 поднимают перелёт «звезды» 23 → 26–28 %,
# но сборка затягивается до 0.98–1.07 с (цель < 0.9, RM 0.5–0.8), лаг при разгоне даёт 43–62 % (> 40) при возврате 0.15–0.17 с,
# а разный дамп частей в невесомости «гребёт» (дрейф ЦМ 0.025–0.037 м > 0.02). Предложенные 2.5 / 0.6 / 0.2 — сборка 1.05 с, лаг 51 %.
# Поэтому конечности как в v6 (1.5), а тяжелее стало ядро (DOLL_LINEAR_DAMP 2.25): руки при остановке торса пролетают дальше.
const DOLL_LIMB_LINEAR_DAMP := 1.5      # плечо/предплечье/кисть/бедро/голень/стопа (24 кг)
const DOLL_LIMB_ANGULAR_DAMP := 0.6     # 0.2–0.4: перелёт тот же, сборка дольше (0.6 → 0: 0.72 → 0.95 с)
const FLIGHT_LIMB_LINEAR_DAMP := 1.5    # конечности в полёте (ядро FLIGHT_LINEAR_DAMP 1.8): 10 HP гаснет за 1.02 с (было 0.93), рывок 1.12 с;
                                        # оседание (16·1.8 + 24·1.5)/40 = 1.62 → g/d 1.23 м/с (проба: vy min −1.08…−1.14)
# Торможение без ввода (критик круга 2): ввод = 0, кукла жива, не в полёте → торс +IDLE_BRAKE_DAMP (RM: скорость гаснет за ~1 с, накат ~1 H).
# Проба (ядро 2.25): 0.25 → стоп 0.97 с / 2.10 м, перелёт 31 %, но стоя (idle_air) 4.97° при пороге 5°; 0.5+ — idle_air > 5°.
# При ядре 1.5 тормоз 0.75 давал 1.17 с / 2.55 м: тяжёлое ядро делает то же без отдельного режима, поэтому 0 (механизм оставлен).
const IDLE_BRAKE_DAMP := 0.0
const DOLL_CORE_PARTS := ["Head", "Torso"]


## Линейный дамп части куклы (имя узла): ядро DOLL_LINEAR_DAMP / FLIGHT_LINEAR_DAMP, конечности DOLL_LIMB_* / FLIGHT_LIMB_*.
## Читают doll.gd (покой/полёт/KO) и tools/build_doll_scene.gd (печёт в doll.tscn).
func doll_linear_damp(part: String, flight: bool = false) -> float:
	if DOLL_CORE_PARTS.has(part):
		return FLIGHT_LINEAR_DAMP if flight else DOLL_LINEAR_DAMP
	return FLIGHT_LIMB_LINEAR_DAMP if flight else DOLL_LIMB_LINEAR_DAMP


func doll_angular_damp(part: String) -> float:
	return ANGULAR_DAMP if DOLL_CORE_PARTS.has(part) else DOLL_LIMB_ANGULAR_DAMP

# --- движение (CONCEPT.md §3: управление центром тела) ---
const CONTROL_TARGET := "torso"         # "torso" (центр тела, концепт) | "head" (порт Ragdoll Masters)
const CONTROL_MODE := "thrust4"         # "thrust4": сила по 4 направлениям | "rotate": ←→ момент, ↑↓ тяга
const MOVE_FORCE_PER_KG := 12.0         # Н на кг общей массы
const ROTATE_TORQUE := 80.0             # Н·м на торс в режиме rotate
const MAX_MOVE_SPEED := 9.0             # м/с, клэмп управляемого тела (полёт после удара не клэмпится)
const DASH_MULT := 1.8
const DASH_DURATION_S := 2.0
const DASH_COOLDOWN_S := 10.0
const FLIP_IMPULSE := 6.0               # угловой импульс торсу

# --- рэгдолл: поза покоя (docs/plan-demo/FEEL_TARGET.md §2) ---
# Градусы ЛЕВОЙ стороны в measured-конвенции: угол = wrapf(child.rot.z − parent.rot.z), L (+X) наружу = +.
# Правая сторона (*_R) = −(угол L) автоматически (Doll._ready / set_pose). Т-поза Ragdoll Masters: руки ⟂ торсу, ноги слегка врозь.
# v7: плечо 90 → 85° (руки чуть ниже Т; RM стоя 50–100°): при 90° удар 10 HP вдоль Т-рук складывал плечо физически только до 56–58°
# при любых k (сила поперёк руки ∝ sin угла рука–удар), при 85° — 77° (feel_probe hit_flight_10, FEEL_TARGET §9.4)
const POSE := {"Neck": 0.0, "Shoulder": 85.0, "Elbow": 10.0, "Wrist": 0.0, "Hip": 12.0, "Knee": 5.0, "Ankle": 0.0}

# --- рэгдолл: мышцы = явный PD к позе покоя на 60 Гц + трение шарнира (мотор с v=0), FEEL_TARGET §3 ---
# torque = clamp(−k·(ang − rest) − c·w, ±tmax), c = 2·MUSCLE_ZETA·√(k·inertia) (inertia — дистальная цепь сустава, кг·м²).
# Почему так (вместо старого «k≥60 → ползёт»): явный PD неустойчив на лёгких кистях/стопах (k < I·(1.5/dt)²: кисть ≤ 44, стопа ≤ 84)
# и при ζ ≥ 0.4; tmax плеча/бедра < вес × рычаг, иначе лежащая кукла сама встаёт/переворачивается; PD лодыжки в цепи стопа–пол
# на 60 Гц дрожит вечно → Ankle k = 0 (только трение). Запасной путь при дрожи: physics_ticks_per_second = 120.
const MUSCLE_ZETA := 0.2                # допуск 0.1–0.3; ≥ 0.4 дрожит на 60 Гц. Группа может задать своё "zeta" (плечо 0.14, бедро 0.1)
const MUSCLE_GROUPS := {
	# k Н·м/рад, tmax Н·м, zeta (опц., иначе MUSCLE_ZETA), inertia кг·м², friction_factor × JOINT_FRICTION (builder печёт в .tscn force_limit мотора)
	"Neck":     {"k": 12.0, "tmax": 15.0, "inertia": 0.149,  "friction_factor": 1.4},
	# v7 (FEEL_TARGET §9.4): порог стойки ±5° заменён эталонным RM (плечо ≤ 25°, бедро ≤ 15°) → мягкие пружины конечностей.
	# Плечо k 38 → 32, tmax 22 → 16, ζ 0.17 → 0.14: разгон вверх — лаг 26 → 32°, возврат 0.22 с, перелёт 29 → 34 %; рывок 58 → 78°;
	# «звезда» из палки 0.72 → 0.80 с (перелёт 24 %); стоя 4.8 → 6.0°. Перебор ~200 прогонов feel_probe: k 25–28 — лаг 34–38°, но сборка
	# 0.83–0.87 с; ζ 0.10–0.12 — перелёт «звезды» 24–29 %, но сборка 1.1–1.2 с (> 0.9: оба RM-числа по-прежнему не сходятся, §9.2);
	# tmax 20 — рывок 66–69°, звезда > 1.0 с. ω·dt = √(32/0.572)/60 = 0.12 (устойчиво < 1.5). Рука с оружием — WEAPON_ARM_MUSCLES
	"Shoulder": {"k": 32.0, "tmax": 16.0, "zeta": 0.14, "inertia": 0.572, "friction_factor": 1.4},   # период руки 0.84 с (RM 0.7); 16 Н·м → 21 Н у кисти < 80 Н веса
	"Elbow":    {"k": 18.0, "tmax": 10.0, "inertia": 0.103,  "friction_factor": 1.4},   # 14 → бедро при ударе 59° (< 60); 20+ → лежащая ползёт
	"Wrist":    {"k": 5.0,  "tmax": 3.0,  "inertia": 0.0054, "friction_factor": 0.7},   # k ≤ 44 по устойчивости; с оружием лучше 0
	# v7: бедро k 90 → 50, tmax 45 → 30: разгон вбок — лаг 17 → 28°, возврат 0.27 с, перелёт 20 %; стоя 1.2° (ноги ставятся в позу при
	# спавне, Doll.spawn_in_pose). k 45 и ниже — лаг 30–33°, но толкнутая нога на полу остаётся в 5.2° от места (spring_foot_floor);
	# ζ 0.06–0.08 — перелёт 21–22 % вместо 20. 30 Н·м → 37 Н у стопы < 80 Н: лежащая не встаёт (85.8°)
	"Hip":      {"k": 50.0, "tmax": 30.0, "zeta": 0.1, "inertia": 2.17, "friction_factor": 2.1},
	"Knee":     {"k": 60.0, "tmax": 25.0, "inertia": 0.359,  "friction_factor": 2.1},   # 30 → колени стоя проседают на 9° под весом; 60 → 2–3°
	"Ankle":    {"k": 0.0,  "tmax": 0.0,  "inertia": 0.0104, "friction_factor": 1.4},   # только трение (PD стопы дрожит на 60 Гц)
}
const JOINT_FRICTION := 1.0             # Н·м × friction_factor (было 6.0: dead band f/k 24–36° съедал пружины; теперь 1.3–8°)
# v7: рука, держащая оружие (WeaponPickup.attach → Doll.set_muscle_joint, сброс/KO → clear_muscle_joint), жёстче групповой: мягкое плечо
# (k 32 / tmax 16) не удержит молот 6 кг — он провисал и первым бил торс, а не молот (combat_gate band_hammer / weapon_still, v6).
# Значения v6.2 (плечо k 38 / tmax 22 / ζ 0.17), пустая рука остаётся мягкой. Ключ — группа, суставы берутся той стороны, где кисть.
const WEAPON_ARM_MUSCLES := {
	"Shoulder": {"k": 38.0, "tmax": 22.0, "zeta": 0.17},
	"Elbow":    {"k": 18.0, "tmax": 10.0},
	"Wrist":    {"k": 5.0,  "tmax": 3.0},
}
const KO_MUSCLE_STIFFNESS := 0.0        # для частей после KO (суставы уже освобождены break_apart)
const KO_JOINT_FRICTION := 0.0

# --- массы частей (кг); «персонажи относительно лёгкие» (§5) относительно оружия/пропсов ---
const MASS := {
	"Head": 4.0, "Torso": 12.0,
	"UpperArm": 2.0, "LowerArm": 1.5, "Hand": 0.5,
	"UpperLeg": 4.0, "LowerLeg": 3.0, "Foot": 1.0,
}

func total_mass() -> float:
	return MASS["Head"] + MASS["Torso"] + 2.0 * (MASS["UpperArm"] + MASS["LowerArm"] + MASS["Hand"] + MASS["UpperLeg"] + MASS["LowerLeg"] + MASS["Foot"])

# --- цвета игроков (R3) ---
const PLAYER_COLORS := [Color("2f6fde"), Color("d9342b"), Color("2e9e4f"), Color("e8b820")]

# --- оружие (CONCEPT.md §11, план 07 по R16): масса кг, множитель урона, длина м от хвата до дальнего конца ---
# Массы пишет в сцены tools/build_weapon_scenes.gd; damage_mult/length читает scenes/weapons/weapon.gd.
const WEAPON := {
	"hammer": {"mass": 6.0, "damage_mult": 1.2, "length": 1.05},
	"mace": {"mass": 4.0, "damage_mult": 1.1, "length": 0.97},
	"sword": {"mass": 1.5, "damage_mult": 1.6, "length": 0.93},
	"axe": {"mass": 3.0, "damage_mult": 1.3, "length": 0.90},
	"pan": {"mass": 2.0, "damage_mult": 1.5, "length": 0.80},
}
