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

# --- урон (CONCEPT.md §8, план 06): Damage = m_eff × max(0, v − MIN_IMPACT_SPEED) × DAMAGE_COEF × BodyMult × TargetMult × WeaponMult × combo ---
# Калибровка (scripts/core/damage.gd печатает таблицу; tests/combat_gate.gd проверяет полосы): торс о торс 3 м/с ≈ 2.9 (1–3),
# кисть в торс 10 м/с ≈ 8.1 (8–15), молот 8 м/с ≈ 29.6 (20–30), торс в голову 15 м/с ≈ 38 (30–50).
const MIN_IMPACT_SPEED := 1.5           # м/с относительной скорости по нормали, ниже урона нет
const DAMAGE_COEF := 0.95               # HP на (кг·м/с) сверх порога
const MASS_CAP := 4.0                   # кг; только ЧАСТИ ТЕЛА (торс 12 не «давит массой» — иначе полосы концепта не сходятся) и окружение
# Потолок массы 29.09 (решение автора «сделай»): оружие (стандартное, крафтовое, брошенный пропс) MASS_CAP не режется — тяжелее
# головка, сильнее удар (Damage.weapon_mass). Кап стандартного оружия перенесён в его множитель: WEAPON[id].damage_mult × 4/масса
# для масс > 4 кг (молот 6 кг: 1.2 → 0.8), урон стандартного оружия прежний (combat_gate). Выше мягкого потолка масса растёт по
# корню S·√(m/S): 30-кг хлам считается как 17.3 кг, 6.5-кг кистень — как есть.
const WEAPON_MASS_SOFT_CAP := 10.0      # кг
const DAMAGE_MAX := 60.0                # HP за один удар; «экстремальное столкновение 30–50+», один удар не снимает 100
# Голова как бьющая часть 0.35 (ниже торса 0.5): голова — уязвимая цель (×1.5), а не таран; оружие скилла — конечности по
# инерции (Hand 2.0). В CONCEPT_GAP предлагалось 1.5: тогда обычный встречный разбег давал обоим по 40 HP, и таран головой бил
# сильнее любой техники; при 0.5 клинч голов в непрерывной рубке (гейт rush_damage) всё ещё давал > 120 HP за 15 с.
# Скорость удара = min(сближение, собственная скорость бьющего по нормали): встречные 9 + 9 м/с = удар 9, не 18.
const BODY_MULT := {"Head": 0.35, "Torso": 0.5, "Hand": 2.0, "Foot": 1.2, "UpperArm": 0.8, "LowerArm": 1.0, "UpperLeg": 0.6, "LowerLeg": 0.7}
const HEAD_HIT_MULT := 1.5              # удар В голову (TargetMult); клинч голова-о-голову бьёт обоих без него
## Удар В кисть (TargetMult, решение автора 30.09, WORKSHOP_V3.md §5): кисть — «блок», урон почти не проходит. Кулак в кулак —
## медленный кулак получает ×0.25; удар оружием в подставленную кисть — тоже.
const HAND_HIT_MULT := 0.25
## Форма бьющей детали × скорость (WORKSHOP_V3.md §4): бонус формы (PartDef.hit_mult, шипастый декор) не выше SHAPE_MULT_MAX;
## профиль решает, на какой скорости он работает — колющий (sharp: шипы, когти, рога) в полную силу до SHAPE_SLOW_V и сходит на ×1
## к SHAPE_FAST_V, дробящий (blunt: кулак, тиски, тяжёлые головы) наоборот; soft / "" — множитель постоянный (верёвка 0.85).
const SHAPE_MULT_MAX := 1.2
const SHAPE_SLOW_V := 4.0               # м/с
const SHAPE_FAST_V := 10.0              # м/с
const PAIR_HIT_COOLDOWN_S := 0.25       # одна пара (атакующий, жертва) — не чаще; исключение — DOUBLE BLOW
const DOUBLE_BLOW_WINDOW_S := 0.1       # второе попадание другим телом по той же жертве в это окно = DOUBLE BLOW (RM)
const DOUBLE_BLOW_MULT := 0.6           # урон второго попадания: в клинче двух рэгдоллов по 10 частей второй контакт почти всегда есть
const ANNOUNCE_MIN_DAMAGE := 5.0        # надписи HEAD/BODY BLOW только от этого урона (иначе спам от касаний)

# --- урон от окружения (В6, по умолчанию включён): стены, пол, пропсы бьют при v ≥ ENV_MIN_IMPACT_SPEED ---
const ENV_DAMAGE_ENABLED := false   # решение автора 28.09: стены/пол/пропсы урона не наносят (статистика wall_collisions остаётся)
const ENV_MIN_IMPACT_SPEED := 6.0       # м/с; падение с яруса — 0, влёт головой в стену на 15 м/с ≈ 26 HP
const ENV_DAMAGE_MULT := 0.5
const TEAM_DAMAGE_MULT := 0.25          # урон между куклами одной непустой Doll.team (PvE-волны: враги толкают друг друга в пропасть,
                                        # но почти не ранят); толчки/отброс/стан — полные
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
	"hammer": {"mass": 6.0, "damage_mult": 0.8, "length": 1.05},   # 1.2 × 4/6: до 29.09 масса резалась MASS_CAP 4 кг — урон тот же
	"mace": {"mass": 4.0, "damage_mult": 1.1, "length": 0.97},
	"sword": {"mass": 1.5, "damage_mult": 1.6, "length": 0.93},
	"axe": {"mass": 3.0, "damage_mult": 1.3, "length": 0.90},
	"pan": {"mass": 2.0, "damage_mult": 1.5, "length": 0.80},
}

# --- удар-презентация и крит (docs/plan-demo/HIT_FX.md, 29.09): уровни light / heavy / crit / ko / ko_crit ---
# Оценка удара score = урон × (1 + CRIT_HEAD_BONUS·[в голову]) × (1 + CRIT_DASH_BONUS·[бьющий в рывке]) × (1 + CRIT_COMBO_BONUS·[комбо ≥ N]).
# Урон уже включает MASS_CAP (тело) / WEAPON_MASS_SOFT_CAP (оружие), HEAD_HIT_MULT и комбо; бонусы — «стиль» удара. Калибровка на ботах match_probe (29.09, 98 ударов,
# 87.5 с боя на трёх площадках): heavy 15 (раз в ~6 с), crit 3 + ko_crit 1 (раз в ~22 с), light 77, ko 2.
# Перекалибровка 29.09 (вечер, tests/hitfx_core_probe: боты match_probe, 8 матчей до KO × Void/Руины/Мастерская × 2 сида, ~2100 с
# боя, ~1350 ударов): после правок куклы за день боты бьют слабее (95-й перцентиль урона ~12 HP), и с засухой 40 с × 0.8 / MIN 16
# крит выходил раз в 57–68 с (Void — раз в 96 с). Основной порог 22 оставлен: сильный удар человека — крит, частоту держат кулдауны.
# Засуха короче и глубже: 15 с без крита → порог 22 × 0.5 = 11 при уроне ≥ 10 — вялый бой тоже получает кинематограф (первый
# крепкий удар после паузы). Итог: crit + ko_crit раз в 35–48 с (8 матчей × сид), 30.6 с в пробе по умолчанию (6 матчей × сиды 29, 7),
# heavy 12–15 % (полосы проекта 15–45 с, 5–30 %).
# v2 «честный крит» (HIT_FX.md §11.1, критик v1: 56 % критов давала засуха, 18 из 64 — удары 10–14 HP): CRIT_MIN_DAMAGE 14 — слабее
# никогда не крит; засуха × 0.75 и только «стильным» ударам (голова, рывок, оружие, комбо ≥ 3); CRIT_SCORE 22 → 18 (2 × heavy, топ ~3 %
# ударов ботов), иначе честных критов у ботов раз в 45–55 с. Итог (боты, 4 площадки × 2 сида, ~1850 с): раз в 35–39 с, засуха 2–11 %,
# слабейший крит 14.4 HP, heavy 14 %.
# Для людей — перепроверить после ручной игры автора (HIT_FX.md §6).
const HITFX_ENABLED := true             # Match создаёт HitFxDirector и SfxDirector; false — только старый hit_feel
const HITFX_HEAVY_SCORE := 9.0          # score ≥ — heavy (ниже — light)
const CRIT_ENABLED := true              # false — уровни не выше heavy (и ko без крита)
const CRIT_SCORE := 18.0                # score ≥ — crit («CRUSHING BLOW!»); v2: было 22 (§11.1) — 2 × heavy
const CRIT_MIN_DAMAGE := 15.0           # HP: слабее — никогда не крит (и не ko_crit) при любых бонусах и засухе; v2: 10 → 14 (§11.1), v3: 14 → 15 (§12.4)
const CRIT_HEAD_BONUS := 0.25
const CRIT_DASH_BONUS := 0.15
const CRIT_COMBO_BONUS := 0.1
const CRIT_COMBO_N := 3                 # комбо атакующего (n нового удара) с этого числа
const CRIT_KINDS := ["head", "body", "weapon"]   # environment/self и DOUBLE BLOW (второе тело клинча) критом не бывают
const CRIT_MIN_FIGHT_S := 5.0           # с от FIGHT!: первая сшибка — не кинематограф
const CRIT_COOLDOWN_S := 8.0            # с боя (Match.fight_time) между критами в матче — не чаще раза в 8 с
const CRIT_ATTACKER_COOLDOWN_S := 15.0  # с боя между критами одного атакующего
const CRIT_DROUGHT_S := 15.0            # без крита столько с боя — порог × CRIT_DROUGHT_SCORE_MULT, только «стильным» ударам (HitTier.stylish)
const CRIT_DROUGHT_SCORE_MULT := 0.75   # 18 × 0.75 = 13.5 < CRIT_MIN_DAMAGE: засуха лишь подтягивает стильные удары ≥ 15 HP со score < 18
const CRIT_KO_GAP_S := 2.0              # ko_crit: кулдауны не действуют, но от прошлого крита не меньше столько с боя
# v3 (HIT_FX.md §12.4, критик v2: кулдаун атакующего 15 с отдавал в heavy удары 25–41 HP, а критом становились 14–16 HP): «сокрушительный»
# удар — score ≥ CRIT_BYPASS_SCORE или урон ≥ CRIT_BYPASS_DAMAGE — крит сквозь кулдауны 8 / 15 с, если от прошлого крита ≥ CRIT_BYPASS_GAP_S боя
# (кинематограф 1.3 с реального времени — ≈ 0.4 с боя — к тому времени кончился). Обход снимает и CRIT_MIN_FIGHT_S, и исключение DOUBLE BLOW
# (у ботов 40–50 HP оружием на 1-й секунде и молот 36 HP вторым телом клинча оставались heavy); CRIT_MIN_DAMAGE и CRIT_KINDS действуют.
# Обход добавляет ~6 критов на 1800 с боя ботов; CRIT_MIN_DAMAGE 14 → 15 возвращает их из нижнего края (стильные 14–15 HP) и держит
# частоту в середине полосы 25–45 с (боты, 4 площадки × 2 пары сидов, §12.4).
const CRIT_BYPASS_SCORE := 27.0         # 1.5 × CRIT_SCORE
const CRIT_BYPASS_DAMAGE := 25.0        # HP: удар такой силы не остаётся heavy из-за кулдауна
const CRIT_BYPASS_GAP_S := 4.0          # с боя от прошлого крита (любого атакующего)
const CRIT_KNOCKBACK_MULT := 1.6        # отлёт крита: скорость ЦМ жертвы вдоль удара × это после обычного отброса,
const CRIT_LAUNCH_MIN_SPEED := 5.5      # м/с, но не меньше (≈ 3 H/с) ...
const CRIT_FLIGHT_MAX_SPEED := 7.5      # ... и не больше (≈ 4 H/с): свой клэмп полёта вместо FLIGHT_MAX_SPEED на CRIT_FLIGHT_S
const CRIT_FLIGHT_S := 1.6              # с (физических) окна крит-полёта: клэмп CRIT_FLIGHT_MAX_SPEED, дамп CRIT_FLIGHT_LINEAR_DAMP до land()
const CRIT_FLIGHT_LINEAR_DAMP := 1.0    # дамп всех частей в крит-полёте (обычный 1.8/1.5): 7.5 м/с → стена Void за ~1 с
const CRIT_ATTACKER_STOP_SPEED := 1.5   # м/с: v2 — ЦМ атакующего вдоль отлёта не быстрее (не летит следом за жертвой, не дожимает её)
const CRIT_ATTACKER_LOCK_S := 0.5       # с (физических): тяга атакующего после крита выключена, рывок снят (почти всё — внутри замедления)
const HEAVY_ATTACKER_BRAKE_SPEED := 2.5 # м/с: v3 (HIT_FX.md §12.2) — на heavy ЦМ атакующего вдоль отлёта в момент удара не быстрее
const HEAVY_ATTACKER_BRAKE_S := 0.0     # с (физических) окна тормоза; 0 — только мгновенный клэмп. Окно 0.18 с разлёт не увеличило
                                        # (отдача DollCombat уже гасит сближение; в клинче тормоз держит жертву: −0.28…+0.04 м на +400 мс)
const CRIT_KO_LAUNCH_SPEED := 3.0       # м/с: ko_crit — части разорванной куклы получают это вдоль удара сверх KO_BURST_SPEED
const CRIT_SLOWMO_SCALE := 0.3          # после крупного плана: отлёт в замедлении (реальные секунды, Match.request_time_scale)
const CRIT_SLOWMO_S := 0.55
const HITFX_HEAVY_STOP_S := 0.083       # v2: было 0.05 (5 кадров при 60 fps); hit stop heavy-удара ниже HIT_STOP_DAMAGE_1 (там уже 80/120 мс), time_scale HIT_STOP_TIME_SCALE
const HITFX_TIME_SCALE_MIN := 0.02      # «стоп-кадр» не 0: Match._process считает реальное время как delta / time_scale
const HITFX_SLAM_SPEED := 4.0           # м/с: касание статики с этой скорости → Match.env_slam (пыль/звук, урона нет)
const HITFX_SLAM_SHAKE_SPEED := 6.0     # м/с: с этой скорости удар о стену/пол ещё и трясёт камеру
# Доступность (фоточувствительность): значения по умолчанию; HitFxDirector копирует их в свои var (меню 11 меняет на лету).
const HITFX_FLASH_INTENSITY := 1.0      # 0–1: вспышки, impact frame, белый кадр крита
const HITFX_SHAKE_INTENSITY := 1.0      # 0–1: тряска, крен и наезд камеры
const HITFX_IMPACT_FRAMES := true       # кадры инверсии (heavy/ko/crit); false — без них
const HITFX_CRIT_CINEMATIC := true      # false — крит без крупного плана/рентгена: надпись, отлёт, замедление
const HITFX_MAX_FLASHES_PER_S := 3      # полноэкранных вспышек/инверсий не больше 3 в секунду (WCAG 2.3.1)
const HITFX_SFX_VOLUME_DB := 0.0        # громкость шин SFX и SFX_Crit (SfxDirector, дБ; 0 — как смикшировано; −80 — без звука ударов)
# Пресеты FX для игрока (v2, HIT_FX.md §11.2): F10 на площадке — full → reduced → off. FxPreset.apply пишет flash/shake/impact_frames/
# crit_cinematic в HitFxDirector (CritCinematic читает их у директора); time_fx = false — Match.request_time_scale отказывает всем тегам,
# кроме ko* (heavy_stop, стоп-кадр и замедление крита), и старый hit stop 80/120 мс не ставится; KO slow-mo остаётся всегда.
# Щепки, пыль, звук и крит-отлёт (баланс) — во всех пресетах.
const HITFX_PRESETS := {
	"full": {"flash": HITFX_FLASH_INTENSITY, "shake": HITFX_SHAKE_INTENSITY, "impact_frames": HITFX_IMPACT_FRAMES, "crit_cinematic": HITFX_CRIT_CINEMATIC, "time_fx": true},
	"reduced": {"flash": 0.4, "shake": 0.5, "impact_frames": false, "crit_cinematic": false, "time_fx": true},   # крит без ката: надпись, стоп 80 мс, замедление 0.4 с
	"off": {"flash": 0.0, "shake": 0.0, "impact_frames": false, "crit_cinematic": false, "time_fx": false},
}
const HITFX_PRESET_ORDER := ["full", "reduced", "off"]
const HITFX_PRESET_DEFAULT := "full"

# --- Поле NULL и мембрана купола (арена 01 «Old NULL Hall», scenes/arena/null_field.gd; docs/plan-demo/ART_NULL.md) ---
# Гравитация поля — Area3D с заменой гравитации; табло показывает её в G (1 G = G_EARTH м/с²). По умолчанию — та же, что в проекте
# (GRAVITY 2.0 = «NULL FIELD: 0.20G», LORE_NULL.md). Смена поля (голосование, отладочная клавиша G) идёт плавно за NULL_FIELD_BLEND_S.
const G_EARTH := 9.81
const NULL_FIELD_BLEND_S := 1.2          # с: переход силы и направления гравитации поля
# Мембрана — упругая граница купола (полуэллипс над полом): за контуром на каждое тело действует ускорение пружины по нормали
# a = K·растяжение (одинаково для лёгких и тяжёлых частей — поле, а не резина), при уходе наружу — ещё демпфер; при возврате
# пружина сильнее в MEMBRANE_RETURN_GAIN раз: мембрана «выстреливает» бойца обратно (§4 лора: отскок от мембраны — приём).
const MEMBRANE_K := 44.0                 # 1/с²: на 8 м/с растяжение ≈ 1.2 м
const MEMBRANE_DAMP_OUT := 0.3           # 1/с: гашение скорости наружу, пока растянута
const MEMBRANE_RETURN_GAIN := 1.25       # пружина на возврате сильнее: шар без дампа отскакивает ≈ с той же скоростью, кукла (дамп 2.25) — медленнее
const MEMBRANE_MAX_STRETCH := 2.5        # м: дальше — жёсткий упор (K × MEMBRANE_HARD_MULT)
const MEMBRANE_HARD_MULT := 8.0
const MEMBRANE_NEAR_M := 2.5             # м: ближе к мембране — она начинает светиться у бойца (лист камеры: «видна только вблизи»)

# --- Кампания «История», карьера (docs/plan-demo/17-career-trophy.md; решения автора 30.09) ---
# Энергия — регламент лиги: бюджет сборки задаёт ступень лиги и растёт с ней. В демо одна ступень — местная лига.
const LEAGUE_ENERGY := {"local": 100}
# Оружие в руке ест ту же энергию: ceil(масса оружия, кг × это). Киянка 2.1 кг → 11, молот 4.1 → 21, кистень 6.5 → 33.
const LEAGUE_WEAPON_ENERGY_PER_KG := {"local": 5.0}
# Уровни бота-соперника (scripts/campaign/rival_brain.gd): реакция (с), ошибка прицела (м), упреждение (с), отход после наскока (с),
# рывок с разбега. 1 — первый соперник лестницы, 4 — финал местной лиги.
const RIVAL_LEVELS := {
	1: {"reaction_s": 0.36, "aim_error_m": 0.55, "lead_s": 0.15, "retreat_s": 1.5, "dash": false},
	2: {"reaction_s": 0.30, "aim_error_m": 0.45, "lead_s": 0.2, "retreat_s": 1.35, "dash": true},
	3: {"reaction_s": 0.24, "aim_error_m": 0.35, "lead_s": 0.25, "retreat_s": 1.2, "dash": true},
	4: {"reaction_s": 0.2, "aim_error_m": 0.25, "lead_s": 0.3, "retreat_s": 1.1, "dash": true},
}
const CAMPAIGN_RESULT_DELAY_S := 3.5     # с реального времени: после конца боя — итоги HUD, потом экран исхода кампании

# --- Голосование зрителей купола (docs/plan-demo/15-audience-vote.md; лор §8, §14) ---
const VOTE_FIRST_S := 30.0               # с боя: первое голосование (второе — на Sudden Death)
const VOTE_DURATION_S := 6.0             # с: проценты растут на табло
const VOTE_EFFECT_S := 20.0              # с: выбранное поле держится, потом — регламент
const VOTE_RESULT_SHOW_S := 2.5          # с реального времени: «… WINS» на панели
const VOTE_MAX_PER_MATCH := 2
const VOTE_DEBRIS_COUNT := 5             # DEBRIS DROP: ящиков сверху купола
const VOTE_CHAOS_PER_CRIT := 0.25        # крит сдвигает голоса к хаосу (0..1 копится до голосования)
const VOTE_CHAOS_PER_COMBO := 0.1        # комбо 3+

# --- Выход бойца (docs/plan-demo/16-fighter-entrance.md; лор §7) ---
const ENTRANCE_DIM_S := 0.4              # с: свет зала гаснет / возвращается
const ENTRANCE_DIM_ENERGY := 0.3         # доля энергии ламп зала во время выхода
const ENTRANCE_GATE_S := 0.6             # с: створки ворот
const ENTRANCE_CARRY_S := 3.0            # с: от ворот сквозь мембрану внутрь поля
const ENTRANCE_HOLD_S := 0.9             # с: кадр на бойце после мембраны (конечности всплывают)
const ENTRANCE_RELEASE_SPEED := 2.5      # м/с: боец влетает внутрь поля после мембраны
const ENTRANCE_FAST := 3.0               # первая кнопка — выход быстрее во столько раз, вторая — пропуск

# --- сок удара на языке игры (docs/plan-demo/HIT_FX.md §13, 02.10): обломки по материалу, сколы на детали, цифры-обломки, замедление ---
# Автор 02.10: «не хватает спецэффектов в бою — в прошлом проекте брызги каждый удар, замедление, фразы, цифры»; буквальный порт веба
# (цветные шарики, «-25» в 2D, фразы бойцов) — «ерунда, не подходит игре». Поэтому принцип веба (отклик на каждый удар) — формой игры:
# удар ломает МАТЕРИАЛ ударенной детали (щепки, хлопья краски, искры, сколы кости), след остаётся на детали, урон выпадает 3D-цифрой
# как обломок, говорят только N0 и табло (LORE_NULL.md «Голоса и тон»). Узел HitJuice — ребёнок Match.
const JUICE_ENABLED := true             # Match создаёт HitJuice (сколы, цифры, поводы N0) и ставит замедления варианта; false — как до 02.10
# сколы на детали: оверлей-шейдер на мешах ударенной детали (assets/shaders/doll_marks.gdshader), до JUICE_MARKS_PER_MESH на меш
const JUICE_MARKS := true
const JUICE_MARK_MIN_DAMAGE := 2.0      # HP: слабее — без следа (только обломки)
const JUICE_MARK_R0 := 0.045            # м: радиус следа от 2 HP ...
const JUICE_MARK_R_PER_HP := 0.004      # ... + на 1 HP ...
const JUICE_MARK_R_MAX := 0.13          # ... не больше (следы видно с игровой камеры: кукла — четверть кадра)
const JUICE_MARK_FULL_HP := 14.0        # HP: глубина следа 1 (скол + трещины); слабее — пропорционально, не меньше 0.3
const JUICE_MARK_MERGE := 0.7           # новый удар ближе радиус × это к старому следу — след растёт (× 1.15, глубина +)
const JUICE_MARKS_PER_MESH := 8
const JUICE_WORN_POWER := 2.5           # сумма глубин следов на детали — «вся в сколах» (повод N0 worn)
# цифры-обломки: 3D-цифра урона (цвет краски жертвы) вылетает из точки удара, падает, отскакивает и лежит
const JUICE_DIGITS := true
const JUICE_DIGIT_MIN_DAMAGE := 3.0     # HP: слабее — цифры нет (64 % ударов ботов < 5 HP — иначе россыпь «1» и «2»)
const JUICE_DIGIT_H0 := 0.22            # м: высота цифры при 3 HP ...
const JUICE_DIGIT_H_PER_HP := 0.014     # ... + на 1 HP ...
const JUICE_DIGIT_H_MAX := 0.62         # ... не больше
const JUICE_DIGIT_GRAVITY := 9.0        # м/с²: тяжелее поля NULL (2.0), чтобы ложились, а не парили
const JUICE_DIGIT_BOUNCE := 0.35
const JUICE_DIGIT_REST_S := 4.0         # с лежит, потом уходит в пол
const JUICE_DIGIT_MAX := 14             # кусков на арене (пул; старый уходит)
const JUICE_DIGIT_BIG := 15.0           # HP: «большая цифра» — повод N0 digit_big и свечение
# замедление: варианты на выбор автора (клавиша 0 в бою, HitJuice.time_variant; «−» — цифры). Числа — реальные секунды.
#   stop   — А «микростоп»: light с 6 HP — стоп 35 мс + 0.55× 0.12 с (не чаще 0.25 с); heavy — 0.4× 0.3 с за стоп-кадром;
#   cinema — Б «кино на сильных»: light — ничего; heavy — глубокое 0.25× на 0.6 с с долгим выходом 0.35 с (bullet time);
#   web    — В «как в вебе» (src/lib/hitEffects/dispatch.ts): каждый удар с 4 HP — 0.5× 0.15 с без стопа; heavy — стоп 55 мс + 0.38× 0.3 с;
#   off    — как до 02.10: только hit stop 80/120 мс, heavy_stop 83 мс, крит и KO.
const JUICE_TIME_VARIANTS := {
	"stop": {"title": "А · микростоп", "light_dmg": 6.0, "light_stop": 0.035, "light_scale": 0.55, "light_s": 0.12, "light_ramp": 0.08,
		"light_gap": 0.25, "heavy_scale": 0.4, "heavy_s": 0.3, "heavy_ramp": 0.15, "heavy_stop": 0.0},
	"cinema": {"title": "Б · кино на сильных", "light_dmg": INF, "light_stop": 0.0, "light_scale": 1.0, "light_s": 0.0, "light_ramp": 0.0,
		"light_gap": 0.0, "heavy_scale": 0.25, "heavy_s": 0.6, "heavy_ramp": 0.35, "heavy_stop": 0.0},
	"web": {"title": "В · как в вебе", "light_dmg": 4.0, "light_stop": 0.0, "light_scale": 0.5, "light_s": 0.15, "light_ramp": 0.05,
		"light_gap": 0.0, "heavy_scale": 0.38, "heavy_s": 0.3, "heavy_ramp": 0.05, "heavy_stop": 0.055},
	"off": {"title": "выкл (как было)", "light_dmg": INF, "light_stop": 0.0, "light_scale": 1.0, "light_s": 0.0, "light_ramp": 0.0,
		"light_gap": 0.0, "heavy_scale": 1.0, "heavy_s": 0.0, "heavy_ramp": 0.0, "heavy_stop": 0.0},
}
const JUICE_TIME_ORDER := ["stop", "cinema", "web", "off"]
const JUICE_TIME_DEFAULT := "stop"
# табло (N0_VOICE.md п. 3, решение автора 30.09): крит пишет силу удара — «IMPACT 18.4G» (score крита) вместо CRUSHING BLOW!
const JUICE_IMPACT_CAPTION := true
# стиль вспышки удара (автор 02.10: «вспышка — детская ерунда, надо серьёзнее»): "serious" — горячее пятно 2–3 кадра, короткий свет
# в точке удара, на heavy/ko волна воздуха (искажение) и плотная пыль, без белого кадра, цветных колец, искр цвета атакующего, инверсии,
# послеобразов и линий скорости; "cartoon" — прежний стиль RM (звезда-блик, кольца). Клавиша «=» в бою (HitJuice.impact_style).
const JUICE_IMPACT_STYLE_DEFAULT := "serious"
