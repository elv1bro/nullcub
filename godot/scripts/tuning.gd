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
## Броня (04.10): доля урона, которую деталь снимает с ударов В СВОЁ ТЕЛО: щиток — в тело, с которым он слит (наруч на предплечье
## бережёт предплечье), ядро с толстыми стенками — в себя (тяжёлое ядро платит массой, лёгкое остаётся без защиты).
## Ключ — id детали или его начало (размеры _s / _l идут одной строкой, берётся самое длинное совпадение); деталей без строки броня
## не защищает. Броня на одном теле складывается как 1 − Π(1 − a), итог не выше ARMOR_MAX. Отброс броня не гасит: режется
## урон и стан, как у блока кистью. Плата за защиту — масса и энергия. Числа стартовые, под баланс.
const PART_ARMOR := {
	"shield_plate": 0.35,
	"kit_deco_pauldron": 0.25,
	"kit_deco_gauntlet": 0.2,
	"kit_deco_league_shield": 0.3,
	"kit_deco_pro_panel": 0.3,
	"kit_deco_aoe_carapace": 0.3,
	# ядра: котёл 18 кг и реактор 16 кг — самые толстые; клетка, бак и хаб — железо и листовой металл; бочка, ящик, игрушка — без брони
	"kit_mod_sail": 0.3,             # модуль «Парус-щит» (PartMods, WORKSHOP_V4.md «Модули»): броня, но парусит в воздухе
	"kit_core_boiler": 0.2,
	"kit_core_pro_reactor": 0.15,
	"kit_core_cage": 0.1,
	"kit_core_drum": 0.1,
	"kit_core_ball": 0.1,
}
const ARMOR_MAX := 0.6
## Прочность материала 0…1 (металл крепче дерева); нет в таблице — 0.5. Деталь: + DURABILITY_ARMOR_BONUS у щитков и брони,
## + DURABILITY_CORE_BONUS у ядра (Damage.part_durability). Показатель мастерской и основа запаса прочности в бою (ниже).
const MAT_DURABILITY := {
	"iron": 1.0, "brass": 0.9, "rust": 0.8, "rust_red": 0.85, "bone": 0.6, "rubber": 0.7, "wood_dark": 0.6, "wood": 0.5,
	"maple": 0.5, "planks": 0.45, "paint_red": 0.5, "paint_blue": 0.5, "paint_yellow": 0.5, "paint_white": 0.5, "paint_green": 0.5,
	"cloth": 0.3,
}
const DURABILITY_ARMOR_BONUS := 0.25
const DURABILITY_CORE_BONUS := 0.1
## Прочность деталей в бою (04.10): у каждого тела ModularDoll, кроме ядра и головы, свой запас — PART_INTEGRITY × прочность детали
## (Damage.part_durability, 0…1: клён 0.5 → 45, кость 0.6 → 54, железо 1.0 → 90); слитый щиток добавляет телу
## PART_INTEGRITY × ARMOR_INTEGRITY_BONUS. Запас тратит урон, пришедший именно В это тело (после брони и блока кистью); кончился —
## деталь отлетает вместе со всем, что на ней висит (Doll.detach_part), кукла дерётся дальше. Ядро и голова не ломаются: у них HP
## куклы. PART_BREAK = false — как до 04.10, детали не отлетают. Числа стартовые, под баланс.
## В релизе 0.0.3 выключено: в живом бою механику никто не играл, а автор 04.10 просил пробовать отрыв деталей отдельным режимом
## (прочность суставов, клавиша C — JOINT_BREAK.md). Запас part_integrity считается всегда, не тратится только износ.
const PART_BREAK := false
const PART_INTEGRITY := 90.0
const ARMOR_INTEGRITY_BONUS := 0.25
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
const DASH_MULT := 1.8                  # ускорение (Shift удерживается, пока есть Заряд): тяга и потолок скорости ×
const DASH_DURATION_S := 2.0            # только пробы/клипы: принудительный рывок без траты Заряда (Doll.dash_until); в игре не читается
const DASH_COOLDOWN_S := 10.0           # только пробы: в игре кулдауна нет (его заменил Заряд), Doll.dash_ready_at всегда ≤ _time
const FLIP_IMPULSE := 6.0               # угловой импульс торсу: Doll.request_flip() (боты, пробы) и feel_probe; клавиша Space теперь держит раскрутку

# --- Заряд: ресурс ускорения и раскрутки (docs/plan-demo/COMBAT_CHARGE.md, 02.10) ---
# Старт полный. Ускорение (Shift/пад A) и раскрутка (Space/пад B + A/D) тратят Заряд, пока удерживаются; обычная тяга бесплатна.
# Копится сам (пауза после траты), растёт от ударов по сопернику, серия поднимает выше 100 — перезаряд, он тает, когда серия оборвалась.
# Числа стартовые (посчитаны по частоте ударов ботов match_probe): цель — около ⅓ заряда боя приходит от ударов (charge_probe / match_probe).
const CHARGE_MAX := 100.0
const CHARGE_OVER_MAX := 150.0          # потолок перезаряда (только удары атакующего; жертве выше CHARGE_MAX не набрать)
const CHARGE_DRAIN_PER_S := 35.0        # ускорение: полный бак ≈ 2.9 с; как прежние 2 с рывка из 10 (20 % времени) при накоплении ниже
const CHARGE_SPIN_DRAIN_PER_S := 22.0   # раскрутка (Space + A/D): полный бак ≈ 4.5 с; платит только пока торс реально получает момент
const CHARGE_REGEN_PER_S := 7.0
const CHARGE_REGEN_PAUSE_S := 0.6       # после траты накопление стоит
const CHARGE_RESTART := 25.0            # выдохся (0) → ускорение и раскрутка заперты, пока заряд не вернётся до этого (не мерцают на нуле)
const CHARGE_OVER_DECAY_PER_S := 8.0    # перезаряд тает до CHARGE_MAX …
const CHARGE_OVER_HOLD_S := COMBO_WINDOW_S   # … но только когда с последнего засчитанного удара прошло столько (серия оборвалась)
const CHARGE_MIN_HIT_DAMAGE := ANNOUNCE_MIN_DAMAGE   # удар слабее заряд не даёт (ни атакующему, ни жертве)
const CHARGE_PER_DAMAGE := 0.9          # заряд атакующему = урон × это × (1 + CHARGE_COMBO_STEP·(min(комбо, MAX_N) − 1)) (+ бонусы)
const CHARGE_COMBO_STEP := 0.25
const CHARGE_COMBO_MAX_N := 4
const CHARGE_CRIT_BONUS := 15.0         # crit / ko_crit
const CHARGE_KO_BONUS := 30.0           # ko / ko_crit
const CHARGE_VICTIM_SHARE := 0.25       # жертве: эта доля полученного урона (не выше CHARGE_MAX) — чтобы побеждаемый мог уйти или ответить

# --- раскрутка: торс крутится по A/D, пока держится Space; цена — Заряд (CHARGE_SPIN_DRAIN_PER_S) ---
# Направление как в режиме rotate: вправо — по часовой (кувырок вперёд по ходу), влево — против. Тело вертится целиком: инерция куклы
# с раскинутыми руками и ногами ≈ 10 кг·м² (замер 02.10: торс 160 Н·м без тяги — ω 3.3 рад/с за 0.2 с, 5.4 за 0.8 с), а не 1.2 из
# feel_probe torso_kick (то пик торса за первые тики от FLIP_IMPULSE, пока конечности не подтянулись). Отпустил — вращение гаснет само
# за ~1.5 с (мышцы и трение суставов), своего торможения нет. Тяга A/D идёт как обычно: можно катиться и вертеться.
const SPIN_TORQUE_PER_KG := 4.0         # Н·м на кг thrust_mass() при полном вводе: 40 кг → 160 Н·м
const SPIN_MAX_W := 5.5                 # рад/с (≈ 315 °/с, RM 200–360): выше этого момент не прикладывается
const SPIN_INPUT_MIN := 0.15            # |ввод X| меньше — раскрутки нет (и заряд не тратится)

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
	"stick": {"mass": 1.0, "damage_mult": 0.5, "length": 1.45},   # ХОККЕЙ (HOCKEY.md): клюшка — лёгкая, длинная, урон вполовину
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
const AUDIO_WORLD_ENABLED := true      # Match создаёт CrowdDirector, ImpactAudio, ArenaAmbience (docs/plan-demo/AUDIO.md §4); false — только SfxDirector
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
# обводка бойцов цветом игрока (автор 02.10: «сложно прочитать тело на фоне»), клавиша B — DollOutline
const JUICE_OUTLINE_DEFAULT := true

# --- тренировочный зал за воротами мастерской (docs/plan-demo/MENU_GARAGE.md, «Тренировочный зал»; автор 02.10) ---
# груша: шар на цепи с пружинной «связью» (цепь натягивается, но не толкает) — масса, радиус и длина цепи
const HEAVY_BAG_MASS := 45.0              # кг
const HEAVY_BAG_RADIUS := 0.55            # м
const HEAVY_BAG_CHAIN_LEN := 4.1          # м: от ушка шара до проушины балки
const HEAVY_BAG_CHAIN_K := 3200.0         # Н/м: жёсткость натянутой цепи
const HEAVY_BAG_CHAIN_C := 95.0           # Н·с/м: гашение вдоль цепи
const HEAVY_BAG_LIN_DAMP := 0.05
const HEAVY_BAG_ANG_DAMP := 1.4
## удар по груше считается, когда сила превысила порог (Н); пока касание не кончилось, запоминается пик
const HEAVY_BAG_HIT_MIN_N := 120.0
const HEAVY_BAG_HIT_GAP_S := 0.18         # пауза без касаний, после которой следующий контакт — новый удар
## экран «сила удара»: шкала до этого значения (кН), слова по порогам (кН): лёгкий < 1.5 ≤ средний < 4 ≤ тяжёлый < 8 ≤ нокаут
const HALL_FORCE_SCALE_KN := 12.0
const HALL_FORCE_WORDS := [[1.5, "ЛЁГКИЙ"], [4.0, "СРЕДНИЙ"], [8.0, "ТЯЖЁЛЫЙ"], [1.0e9, "НОКАУТ"]]
## экран «скорость»: шкала до этого значения (м/с)
const HALL_SPEED_SCALE_MS := 24.0

# --- спорт-зал (docs/plan-demo/SPORT.md, автор 04.10: «режим ФУТБОЛ: пинать мяч в чужие ворота, до 3 голов» + баскетбол, волейбол) ---
# Поле в плоскости боя: внутренние грани стен x = ±SPORT_FIELD_HALF_W, пол y = 0, потолок y = SPORT_FIELD_H.
const SPORT_FIELD_HALF_W := 11.0
const SPORT_FIELD_H := 10.0
const SPORT_GOALS_TO_WIN := 3            # матч до стольких голов / очков
const SPORT_TIME_LIMIT_S := 180.0        # основное время; при равном счёте — «золотой гол» ещё SPORT_GOLDEN_S, потом ничья
const SPORT_GOLDEN_S := 90.0
const SPORT_KICKOFF_S := 2.0             # отсчёт перед вводом мяча после гола (первый ввод — обычный COUNTDOWN_S)
const SPORT_GOAL_PAUSE_S := 2.2          # с (физических) от гола до расстановки: мяч в сетке, повтор надписи
const SPORT_GOAL_SLOWMO := 0.35          # замедление в момент гола на SPORT_GOAL_SLOWMO_S реальных секунд
const SPORT_GOAL_SLOWMO_S := 0.7
const SPORT_KO_RESPAWN_S := 2.5          # нокаут в спорте — «удаление»: кукла возвращается у своих ворот через столько
const SPORT_SPAWN_X := 5.5               # куклы на вводе мяча: x = ∓SPORT_SPAWN_X
const SPORT_BALL_RADIUS := 0.4           # м (кукла 1.8 м): мяч крупный — читается в общем плане зала
const SPORT_BALL_MAX_SPEED := 16.0       # м/с: потолок скорости мяча (тоннелирование сквозь сетку, читаемость)
const SPORT_BALL_IDLE_S := 6.0           # мяч лежит без касаний столько — подброс (страховка от «застрял в углу»)
const SPORT_BALL_CORNER_S := 2.5         # мяч зажат в углу у пола (куклы сидят на нём) столько — выброс к центру, касания не считаются
# Автор 06.10: «в футболе, волейболе и баскетболе по умолчанию режим на ; (конечности отрываются), между матчами не чиним — как есть».
const SPORT_PARTHP := true               # зал включает «Запас из деталей» (PartHp, клавиша «;»); вышли из зала — режимы как были
const SPORT_KEEP_DAMAGE := true          # после гола кукла не чинится: оторванное не отрастает до конца матча, запас и износ — как были
## Виды спорта: мяч (масса кг, тяжесть × поля 2.0 м/с², отскок, трение, дамп) и снаряд.
##   football   — ворота у пола: линия x = ±goal_x, перекладина на goal_h, глубина до стены;
##   basketball — кольца на стенах: центр кольца (±hoop_x, hoop_y), полуширина просвета hoop_r; очко — мяч прошёл кольцо сверху вниз;
##                мяч сам стучит об пол: после касания пола летит вверх не медленнее floor_kick м/с (5.0 → до 4.8 м, чуть ниже кольца);
##   volleyball — сетка по центру высотой net_h; очко — мяч коснулся пола на чужой половине; куклы на свою половину заперты.
const SPORTS := {
	"football": {"title": "ФУТБОЛ", "mass": 3.0, "gravity_scale": 1.6, "bounce": 0.62, "friction": 0.5, "lin_damp": 0.12, "ang_damp": 0.6,
		"goal_x": 9.2, "goal_h": 3.2, "ball_y": 3.2},
	"basketball": {"title": "БАСКЕТБОЛ", "mass": 2.5, "gravity_scale": 1.3, "bounce": 0.74, "friction": 0.6, "lin_damp": 0.1, "ang_damp": 0.6,
		"hoop_x": 9.5, "hoop_y": 5.4, "hoop_r": 1.0, "ball_y": 4.0, "floor_kick": 5.0},
	"volleyball": {"title": "ВОЛЕЙБОЛ", "mass": 1.6, "gravity_scale": 0.85, "bounce": 0.7, "friction": 0.4, "lin_damp": 0.18, "ang_damp": 0.6,
		"net_h": 3.4, "ball_y": 6.0, "serve_x": 4.5},
	# ХОККЕЙ (HOCKEY.md, 08.10): шайба (Puck), не мяч; ворота 1.2 м у стен; вбрасывание — падает с 2 м. Числа шайбы — HOCKEY_PUCK_* ниже.
	"hockey": {"title": "ХОККЕЙ", "mass": 0.5, "gravity_scale": 2.0, "bounce": 0.55, "friction": 0.02, "lin_damp": 0.2, "ang_damp": 6.0,
		"goal_x": 9.2, "goal_h": 1.2, "ball_y": 2.0},
}
const SPORT_ORDER := ["football", "basketball", "volleyball", "hockey"]   # hockey — ХОККЕЙ (HOCKEY.md)
## Бот спорт-зала (SportBrain): доля полной тяги, ошибка прицела (м), упреждение мяча (с), пользуется ли ускорением.
const SPORT_BOT_LEVELS := {
	1: {"max_in": 0.72, "aim_error_m": 0.55, "lead_s": 0.12, "dash": false},
	2: {"max_in": 0.88, "aim_error_m": 0.3, "lead_s": 0.2, "dash": true},
	3: {"max_in": 1.0, "aim_error_m": 0.12, "lead_s": 0.28, "dash": true},
}

# --- ДРАЙВ (docs/plan-demo/DRIVE.md, 02.10): пресет «импульс живёт» — клавиша J или кнопка в панели Tab, по умолчанию выкл ---
# Разбор 02.10 (автор: «бой сухой, нет драйва как в тех играх и в JS»): физику подогнали под цифры RM вязкостью (дамп полёта 1.8 —
# скорость гаснет за ~0.55 с) при g 1.1 H/с², а в RM и JS почти нет ни гравитации, ни сопротивления (JS: g 0.2 H/с², τ ≈ 1.7 с).
# В бою ботов купола 18 из 26 стычек — размены (обе куклы получают одинаково), удар 3 HP и 30 HP разлетаются почти одинаково,
# бот после касания отступает 1.1–1.5 с, камера держит одного игрока. Пресет меняет только это; выключен — игра как раньше (гейты).
const DRIVE_DEFAULT := false
const DRIVE_MAX_HP := 150.0              # запас HP обычной куклы с ДРАЙВОМ (Match.begin): удары сильнее и чаще — бой той же длины (~23 с)
const DRIVE_GRAVITY_MULT := 0.35          # × гравитации на частях куклы (gravity_scale): поле 2.0 → 0.7 м/с² ≈ 0.39 H/с² (JS 0.2, RM ≈ 0)
const DRIVE_MOVE_DAMP_MULT := 0.8         # × дампа управляемого хода: ядро 2.25 → 1.8, конечности 1.5 → 1.2 (потолок скорости тот же)
const DRIVE_BRAKE_DAMP := 4.0             # ввода нет и не в полёте: торс +4 — ход гаснет за ~0.3 с и кукла висит (JS: −22 %/кадр и якорь)
const DRIVE_FLIGHT_DAMP_CORE := 0.7       # полёт после удара: ядро 1.8 → 0.7, конечности 1.5 → 0.6 — скорость живёт ~1.5 с, а не 0.55
const DRIVE_FLIGHT_DAMP_LIMB := 0.6
# отброс ∝ урону: J = BASE + PER_HP × урон, не меньше MIN (только удар куклой), не больше MAX. ЦМ 40 кг: 3 HP → ~2 м/с, 8 → 4,
# 15 → 6.6, 30 → 12 (было: любой удар < 10 HP — 2.4 м/с, потолок 4.5)
const DRIVE_KB_BASE := 40.0               # Н·с
const DRIVE_KB_PER_HP := 16.0             # Н·с на 1 HP
const DRIVE_KB_MIN := 60.0                # Н·с
const DRIVE_KB_MAX := 640.0               # Н·с
const DRIVE_KB_TORSO_SHARE := 0.35        # доля в торс (было 0.5): больше в ударенную часть — тело закручивает
const DRIVE_FLIGHT_MAX_SPEED := 14.0      # м/с ЦМ в полёте (было 4.5)
const DRIVE_RECOIL := 0.7                 # атакующий отскакивает на 0.7 × Δv жертвы (было 0.5) — пинг-понг, как в JS
const DRIVE_THRUST_LOCK_S := 0.08         # тяга атакующего после удара выключена (было 0.3 с) — сразу можно вернуться в бой
# «кто сильнее ударил, тот и выиграл размен»: встречные удары двух кукол в одном шаге (или в DRIVE_TRADE_WINDOW_FRAMES тиков) —
# если один сильнее другого в WIN_RATIO раз, слабый встречный × LOSER_MULT. Голова о голову: урон по собственной скорости
# бьющей головы к цели (а не общей скорости сближения) — налетевший бьёт, стоявший почти нет.
const DRIVE_TRADE_WIN_RATIO := 1.3
const DRIVE_TRADE_LOSER_MULT := 0.25
const DRIVE_TRADE_WINDOW_FRAMES := 6
# отклик удара: свой вариант замедления (кроме «выкл» клавиши 0), heavy ниже порогом, криты чаще, толчок кадра на каждый удар
const DRIVE_HEAVY_SCORE := 8.0            # было 9
const DRIVE_CRIT_COOLDOWN_S := 4.0        # было 8 (матч) и 15 (атакующий): 1–2 крита за бой
const DRIVE_CRIT_ATTACKER_COOLDOWN_S := 8.0
const DRIVE_CRIT_LAUNCH_MIN_SPEED := 9.0  # отлёт крита (было 5.5 … 7.5 м/с)
const DRIVE_CRIT_FLIGHT_MAX_SPEED := 16.0
const DRIVE_SHAKE_MULT := 2.5             # × тряски 0.03 м на 10 HP (на кадре 4.8 м её не было видно)
const DRIVE_KICK_MIN_DAMAGE := 2.5        # HP: с этого удара кадр толкает в сторону удара ...
const DRIVE_KICK_FRAC := 0.03             # ... на эту долю полувысоты кадра за 10 HP (× 0.4 … 2) ...
const DRIVE_KICK_S := 0.16                # ... и возвращает за столько реальных секунд
const DRIVE_HEAVY_KICK_MULT := 2.5        # × толчка кадра heavy (HitFxDirector 0.06 м)
const DRIVE_TIME := {"title": "ДРАЙВ", "light_dmg": 2.5, "light_stop": 0.045, "light_scale": 0.5, "light_s": 0.12, "light_ramp": 0.06,
	"light_gap": 0.15, "heavy_scale": 0.35, "heavy_s": 0.3, "heavy_ramp": 0.1, "heavy_stop": 0.07}
# камера купола (follow_mode "humans"): соперник ближе FRAME_BOTH_M — кадр держит обоих (масштаб игрока не съедает отступы);
# дальше FRAME_RELEASE_M — снова игрок + стрелка с метрами (решение автора 02.10 остаётся для дальней дистанции)
const DRIVE_FRAME_BOTH_M := 7.0
const DRIVE_FRAME_RELEASE_M := 9.0
const DRIVE_FRAME_PAD_MULT := 0.55       # × отступов кадра (купол 3 / 2 м → 1.65 / 1.1), только follow_mode "humans"
const DRIVE_FRAME_LEAD_M := 1.2           # м: потолок упреждения летящей куклы в кадре (lead_time 0.4 × 14 м/с дали бы 5.6 м)
# бот-соперник кампании (RivalBrain): не отступает после касания, а давит зигзагом (JS: смена стороны обхода каждые 0.7 с)
const DRIVE_RIVAL_RETREAT_S := 0.25
const DRIVE_RIVAL_ZIGZAG_S := 0.7
const DRIVE_RIVAL_ZIGZAG := 0.45
# вариант управления: включая ДРАЙВ при варианте ТЕЛО, ставим ГОЛОВА-ТАРАН (конечности хлещут, whip 1.11 → 1.61); выключая — обратно
const DRIVE_VARIANT := "dive"

# --- прочность суставов: пробный режим (docs/plan-demo/JOINT_BREAK.md, автор 04.10) — клавиша C в бою, по умолчанию выкл ---
## «При ударах суставы имеют прочность, может отвалиться рука, нога или ещё что; чем дальше от центра, тем меньше у сустава HP».
## Запас сустава считается по глубине от ядра: суставы на ядре (плечо, бедро) — JOINT_HP_BASE, каждый следующий по цепочке
## (локоть, колено → запястье, лодыжка) × JOINT_HP_FALLOFF, но не ниже JOINT_HP_MIN (длинные хвосты сборок): 40 → 28 → 19.6.
## Запас тратит урон, пришедший В деталь, которая на этом суставе висит (удар в предплечье бьёт по локтю), × JOINT_WEAR_MULT;
## блок кистью режет HP, но не износ запястья (как отброс). Запас кончился — деталь отлетает со всем, что на ней висит
## (Doll.detach_part), кукла дерётся дальше. Работает на любой кукле (doll.tscn и ModularDoll); пока режим включён, поломка
## деталей по материалу (PART_BREAK) молчит. Состояние — JointBreak.on. Числа стартовые, под оценку автора.
const JOINT_BREAK_DEFAULT := false
const JOINT_HP_BASE := 32.0
const JOINT_HP_FALLOFF := 0.7
const JOINT_HP_MIN := 8.0
const JOINT_WEAR_MULT := 1.0
const JOINT_BREAK_HEAD := false           # true — у шеи тоже запас (как у сустава на ядре); оторванная голова = KO
const JOINT_BREAK_REATTACH := false       # true — отлетевшую деталь можно вернуть касанием / клавишей захвата (как у Разборщика в PvE)
# вид: сустав с запасом ниже JOINT_SPARK_BELOW (доля) искрит — тем чаще, чем меньше осталось (раз в MAX … MIN секунд)
const JOINT_SPARK_BELOW := 0.5
const JOINT_SPARK_GAP_S := Vector2(0.35, 1.4)
const JOINT_BREAK_FX_STRENGTH := 14.0     # сила вспышки ImpactFx в точке сустава в момент отрыва

# --- СТАЗИС: пробный режим (docs/plan-demo/STASIS.md, автор 05.10) — клавиша X в бою, по умолчанию выкл ---
## «Чтобы время шло, только если движется игрок» (референс — SUPERHOT; в интерфейсе это имя не пишется). Двигает время ВВОД людей:
## любое действие InputMap с префиксом куклы (Stasis.input_strength; стик — доля наклона). Нет ввода — Engine.time_scale тянется к
## STASIS_IDLE_SCALE за STASIS_RAMP_DOWN_S реальных секунд, есть — к 1 за STASIS_RAMP_UP_S. Не ноль: часть кода делит на масштаб
## времени, нижняя граница — HITFX_TIME_SCALE_MIN. Со стоп-кадрами и замедлениями складывается минимумом (Match._apply_time_scale).
## Режим молчит (масштаб сразу 1): людей нет или все в нокауте, отсчёт и итоги, крит-кино, пауза. Состояние — Stasis.on.
const STASIS_DEFAULT := false
const STASIS_IDLE_SCALE := 0.05
const STASIS_RAMP_UP_S := 0.06
const STASIS_RAMP_DOWN_S := 0.2

# --- запас из деталей: стандартный режим (docs/plan-demo/WORKSHOP_V4.md, автор 05.10; по умолчанию вкл — автор 06.10) — клавиша «;» («Ж» — жизнь) в бою выключает (старый запас 100) ---
## «Каждая деталь даёт общее HP; деталь имеет своё HP и, когда оно кончилось, отрывается; ядро и голова дают базовый разгон и энергию,
## любая деталь уменьшает разгон весом; голова оторвана — KO». Состояние — PartHp.on, формулы — scripts/core/part_hp.gd.
##   • ❤ детали = масса тела × PARTHP_PER_KG × множитель материала (1 + прочность) / 1.5 (дерево 1.0, железо 1.33, ткань 0.87), вверх до
##     целого, не меньше PARTHP_MIN; запас бойца = Σ ❤ деталей на нём (у «Человека» 40 кг — ровно 100, решение автора 05.10);
##   • урон в деталь копится; набралось ❤ × PARTHP_BREAK_MULT (не меньше PARTHP_BREAK_MIN) — деталь отлетает со всем, что на ней висит,
##     и запас бойца (и его максимум) теряет их ❤; голова отлетает — KO; ядро не отлетает;
##   • энергия сборки = энергия ядра (PartDef.mass × PARTHP_CORE_ENERGY_PER_KG) + головы (× PARTHP_HEAD_ENERGY_PER_KG) + надбавка чертежа
##     (energy_budget − PARTHP_ENERGY_BASE: регламент лиги, враги); голова сама энергии больше не стоит;
##   • тяга = мотор ядра (PARTHP_CORE_THRUST по id, иначе PARTHP_CORE_THRUST_N) + PARTHP_HEAD_THRUST_N; у «Человека» 400 + 80 = 480 Н, как
##     сейчас; разгон = тяга / масса всей сборки. Моторы разные (автор 05.10: «разное»): у каждого ядра свой характер, ни одно не лучше во всём.
const PARTHP_DEFAULT := true   # автор 06.10: «делай ; как стандартный режим вообще для всего включённый»
const PARTHP_PER_KG := 2.2
const PARTHP_MIN := 3.0
const PARTHP_BREAK_MULT := 4.0
const PARTHP_BREAK_MIN := 16.0
const PARTHP_HEAD_BREAK_MULT := 6.0
const PARTHP_ENERGY_BASE := 100
const PARTHP_CORE_ENERGY_PER_KG := 6.667   # торс «Человека» 12 кг → 80
const PARTHP_HEAD_ENERGY_PER_KG := 5.0     # голова «Человека» 4 кг → 20
const PARTHP_CORE_THRUST_N := 400.0     # мотор ядра, которого нет в PARTHP_CORE_THRUST (торс «Человека», клён, бочка, хаб, око, кристалл)
## Мотор ядра, Н (WORKSHOP_V4.md «Моторы»). Лёгкие с сильным мотором — быстрые и хрупкие; бронированные — с мотором слабее; у ядер лиги
## уже есть пассивы (ActiveBlocks.PASSIVE: заряд, лечение), поэтому их моторы около обычного.
const PARTHP_CORE_THRUST := {
	"junk_torso": 340.0,            # бочонок из хлама 9 кг: дешёвый мотор
	"kit_core_crate": 380.0,        # ящик 11 кг
	"kit_core_toy": 440.0,          # игрушка 11 кг: заводная пружина — быстрая, но мало энергии и ❤
	"kit_core_aoe_heart": 440.0,    # сердце Аоэлюн 13 кг: живая мышца
	"kit_core_drum": 380.0,         # бочка из-под масла 13 кг, броня 0.1
	"kit_core_pro_gyro": 460.0,     # гиростаб про-лиги 13 кг: спортивный мотор
	"kit_core_cage": 360.0,         # клетка 14 кг, броня 0.1: толстые прутья, слабый мотор
	"kit_core_league_gyro": 420.0,  # гироскоп лиги 15 кг (+3 заряда/с)
	"kit_core_pro_reactor": 480.0,  # реактор 16 кг, броня 0.15: сильный мотор, тяжёлый
	"kit_core_boiler": 440.0,       # котёл 18 кг, броня 0.2: пар тянет, но котёл тяжёлый
}
const PARTHP_HEAD_THRUST_N := 80.0

# --- СТЫЧКА 3 НА 3: пробный режим (docs/plan-demo/SQUAD.md, автор 05.10: «карта побольше, стычки 3 на 3 как в шутерах, базовые пулемёты») ---
## Две команды по три бойца на «Полигоне» — карте 64 × 16 м из пропсов Руин. Команда синих — чётные player_index (P1 и два бота, слева),
## красных — нечётные (три бота, справа). Смерть — возрождение на своей базе через SQUAD_RESPAWN_S. Режимы (SquadSettings.mode):
## «перестрелка» — очко команде за каждого выбывшего соперника, матч до SquadSettings.score_to_win; «захват флага» — очко за
## доставленный флаг (SQUAD_FLAG_*). Время — SquadSettings.time_min (ведущий победил; равный счёт — ничья). Свои не ранят
## (team_damage_mult 0), толкают полностью.
const SQUAD_SCORE_TO_WIN := 100              # автор 06.10: «фрагов общих пока 100»
const SQUAD_TIME_LIMIT_S := 1200.0             # 20 минут: до 100 очков боты идут 12–16
const SQUAD_RESPAWN_S := 4.0
const SQUAD_SPAWN_SHIELD_S := 1.5        # после возрождения урон не проходит столько с (иначе встречают очередью у базы)
const SQUAD_KO_SLOWMO_S := 0.35          # замедление KO в стычке (обычный бой 1.2 с: при 15+ нокаутах за матч кино надоедает)
## Корпус вертикально (как ControlFeel «upright», но только в стычке, у всех бойцов): × PD-момента ControlFeel.UPRIGHT_K / _D. Без него
## торс в зависании заваливается на 40–70°, и плечо не достаёт до целей выше головы. После удара, в стане и в раскрутке молчит.
const SQUAD_UPRIGHT := 0.55
const SQUAD_COLORS := [Color("2f6fde"), Color("d9342b")]   # синие, красные — рубашки, обводка, HUD
## Рука с оружием (автор 05.10: «у команды справа левая рука, у левой — правая»): та, что на экране со стороны соперника. Кукла
## смотрит в камеру, поэтому у синих (слева, бьют вправо) это анатомически левая кисть Hand_L, у красных — правая Hand_R. Ею же
## управляет ЛКМ, как в обычном бою. [синие, красные] — uid кисти в kit_human.
const SQUAD_GUN_HAND := ["3", "9"]

## Настройки перед боем (SquadSetup, автор 06.10: «режим настроек перед запуском боя — количество фрагов + ещё что-то»): варианты строк.
const SQUAD_SCORE_CHOICES := [25, 50, 100, 150]
const SQUAD_CAPTURE_CHOICES := [3, 5, 7]
const SQUAD_TIME_CHOICES := [5, 10, 20, 30]   # минуты

## Оружие стрелков (SquadGun). Огонь — ЛКМ (или I), пока зажата, не чаще interval с; рука с оружием всегда тянется к курсору, ствол
## смотрит по руке (плечо → кисть). Магазин mag, запас reserve (ящики добавляют), перезарядка reload_s — сама на пустом магазине или Q.
## Патронов нет совсем — рукопашная.
##   damage — урон пули (дроби — за дробину), pellets — пуль за выстрел, spread_deg — ± разброс, range — м (дальше пуля гаснет),
##   speed — м/с полёта пули, ball — толщина трассера (м), streak — длина хвоста трассера (м), impulse — Н·с в задетое тело, recoil — Н·с
##   в кисть стрелка, pierce — пуля проходит сквозь бойцов (до 3), len — длина ствола (м, вид и точка вылета), tracer — цвет ядра
##   трассера, sound — [слой SfxDirector, питч].
##   Гаусс (charge_s > 0, автор 06.10: «мощность зависит от того, сколько было зажато; бьёт сквозь всех, но каждое препятствие —
##   минус процент урона»): ЛКМ держишь — копится заряд (полный за charge_s), отпустил — выстрел; урон от damage_min до damage по
##   заряду; летит сквозь бойцов и стены (through_walls), каждая стена или пропс — × (1 − wall_loss), каждый боец — × (1 − body_loss).
const SQUAD_WEAPONS := {
	"pistol": {"title": "ПИСТОЛЕТ", "note": "точно, магазин 12", "damage": 9.0, "pellets": 1, "interval": 0.28, "mag": 12,
		"reserve": 48, "reload_s": 1.1, "spread_deg": 1.5, "range": 18.0, "speed": 40.0, "ball": 0.070, "streak": 0.50, "impulse": 6.0, "recoil": 1.5, "pierce": false, "len": 0.26,
		"tracer": Color(1.0, 0.85, 0.4), "sound": ["snap", 1.55]},
	"sawnoff": {"title": "ОБРЕЗ", "note": "дробь вплотную, 2 выстрела", "damage": 5.0, "pellets": 7, "interval": 0.45, "mag": 2,
		"reserve": 24, "reload_s": 1.4, "spread_deg": 11.0, "range": 9.0, "speed": 34.0, "ball": 0.050, "streak": 0.28, "impulse": 6.0, "recoil": 6.0, "pierce": false, "len": 0.34,
		"tracer": Color(1.0, 0.92, 0.6), "sound": ["thud", 1.0]},
	"shotgun": {"title": "ДРОБОВИК", "note": "дробь, магазин 6, отбрасывает", "damage": 5.5, "pellets": 8, "interval": 0.65, "mag": 6,
		"reserve": 30, "reload_s": 2.0, "spread_deg": 8.0, "range": 12.0, "speed": 38.0, "ball": 0.050, "streak": 0.32, "impulse": 9.0, "recoil": 7.0, "pierce": false, "len": 0.62,
		"tracer": Color(1.0, 0.92, 0.6), "sound": ["thud", 0.85]},
	"smg": {"title": "АВТОМАТ", "note": "очередь на бегу, магазин 32", "damage": 6.0, "pellets": 1, "interval": 0.08, "mag": 32,
		"reserve": 128, "reload_s": 1.5, "spread_deg": 4.0, "range": 17.0, "speed": 48.0, "ball": 0.060, "streak": 0.45, "impulse": 3.0, "recoil": 0.8, "pierce": false, "len": 0.4,
		"tracer": Color(1.0, 0.75, 0.3), "sound": ["snap", 2.0]},
	"rifle": {"title": "ВИНТОВКА", "note": "точно и далеко, магазин 5", "damage": 24.0, "pellets": 1, "interval": 0.8, "mag": 5,
		"reserve": 30, "reload_s": 1.8, "spread_deg": 0.4, "range": 32.0, "speed": 85.0, "ball": 0.070, "streak": 1.10, "impulse": 18.0, "recoil": 5.0, "pierce": false, "len": 0.72,
		"tracer": Color(0.85, 0.95, 1.0), "sound": ["snap", 1.0]},
	"marksman": {"title": "СНАЙПЕРКА", "note": "быстрее и дальше, магазин 8", "damage": 30.0, "pellets": 1, "interval": 0.5, "mag": 8,
		"reserve": 40, "reload_s": 1.6, "spread_deg": 0.2, "range": 42.0, "speed": 140.0, "ball": 0.075, "streak": 1.40, "impulse": 20.0, "recoil": 4.0, "pierce": false, "len": 0.86,
		"tracer": Color(0.92, 0.98, 1.0), "sound": ["snap", 0.9]},
	"gauss": {"title": "ГАУСС", "note": "держи ЛКМ — заряд; насквозь бойцов и стен", "damage": 85.0, "damage_min": 15.0, "charge_s": 1.6,
		"pellets": 1, "interval": 0.9, "mag": 4, "reserve": 16, "reload_s": 2.6, "spread_deg": 0.0, "range": 55.0, "speed": 190.0, "ball": 0.130,
		"streak": 2.2, "impulse": 40.0, "recoil": 10.0, "pierce": true, "through_walls": true, "wall_loss": 0.35, "body_loss": 0.15, "len": 0.9,
		"tracer": Color(0.4, 0.9, 1.0), "sound": ["whoosh", 1.2]},
}
const SQUAD_START_WEAPON := "pistol"
## Усиления: множители чисел оружия (складываются умножением) и свойства бойца. Открываются уровнями класса (SQUAD_CLASSES).
##   tough — броня при каждом возврате, hp — запас HP, dash — полёт громилы быстрее (× speed) и чаще (пауза / speed).
const SQUAD_PERKS := {
	"damage": {"title": "УРОН +20 %", "mult": {"damage": 1.2, "damage_min": 1.2}},
	"mag": {"title": "МАГАЗИН И ЗАПАС +50 %", "mult": {"mag": 1.5, "reserve": 1.5}},
	"speed": {"title": "ПЕРЕЗАРЯДКА И ТЕМП +25 %", "mult": {"reload_s": 0.75, "interval": 0.8}},
	"charge": {"title": "ЗАРЯД ГАУССА БЫСТРЕЕ", "mult": {"charge_s": 0.7}},
	"tough": {"title": "БРОНЯ +30 ПРИ ВОЗВРАТЕ", "armor": 30.0},
	"hp": {"title": "ЗАПАС +20 HP", "hp": 20.0},
	"dash": {"title": "ПОЛЁТ БЫСТРЕЕ И ЧАЩЕ", "dash": 1.2},
}
## Классы бойцов (автор 06.10: «стрелка убрать, оставим 3 класса: рукопашный, снайпер и налётчик; на 5 уровне можно взять подкласс»).
## Класс — клавишами 1–3 на отсчёте и пока ждёшь возврата (в бою — с возрождения). Опыт (SQUAD_XP_*) копится сам — за урон и фраги;
## уровни (SQUAD_XP_LEVELS) открывают levels класса (1–4: общий ствол древа), на SQUAD_BRANCH_LEVEL — выбор ветки (branches: подкласс,
## его levels — уровни 5–8). Что открывает уровень: weapon (SQUAD_WEAPONS), melee (SQUAD_MELEE), perk (SQUAD_PERKS).
## hp — запас здоровья, armor — броня при каждом возврате, bullet_mult — × урона пуль по бойцу класса, zoom — камера игрока
## дальше во столько раз (автор 06.10: «для снайпера зум дальше, сразу берёшь — и у тебя не такой зум, как у других»),
## icon — оружие на карточке класса.
const SQUAD_CLASSES := {
	"brawler": {"title": "ГРОМИЛА", "note": "рукопашная: ЛКМ — полёт за оружием, пули × 0.5", "hp": 140.0, "armor": 30.0,
		"bullet_mult": 0.5, "zoom": 1.0, "icon": "hammer",
		"levels": [{"melee": "pan"}, {"perk": "tough"}, {"perk": "dash"}, {"perk": "hp"}],
		"branches": {
			"hammer": {"levels": [{"melee": "hammer"}, {"perk": "hp"}, {"perk": "tough"}, {"perk": "dash"}]},
			"sword": {"levels": [{"melee": "sword"}, {"perk": "dash"}, {"perk": "hp"}, {"perk": "dash"}]},
			"axe": {"levels": [{"melee": "axe"}, {"perk": "tough"}, {"perk": "hp"}, {"perk": "dash"}]},
		}, "branch_order": ["hammer", "sword", "axe"]},
	"sniper": {"title": "СНАЙПЕР", "note": "издалека; обзор шире, чем у всех", "hp": 90.0, "armor": 0.0, "zoom": 1.4, "icon": "rifle",
		"levels": [{"weapon": "rifle"}, {"perk": "speed"}, {"perk": "damage"}, {"perk": "mag"}],
		"branches": {
			"gauss": {"levels": [{"weapon": "gauss"}, {"perk": "charge"}, {"perk": "damage"}, {"perk": "mag"}]},
			"marksman": {"levels": [{"weapon": "marksman"}, {"perk": "speed"}, {"perk": "damage"}, {"perk": "mag"}]},
		}, "branch_order": ["gauss", "marksman"]},
	"raider": {"title": "НАЛЁТЧИК", "note": "вплотную: дробь и рывки", "hp": 110.0, "armor": 20.0, "zoom": 1.0, "icon": "sawnoff",
		"levels": [{"weapon": "sawnoff"}, {"perk": "speed"}, {"perk": "mag"}, {"perk": "damage"}],
		"branches": {
			"shotgun": {"levels": [{"weapon": "shotgun"}, {"perk": "damage"}, {"perk": "mag"}, {"perk": "speed"}]},
			"smg": {"levels": [{"weapon": "smg"}, {"perk": "mag"}, {"perk": "damage"}, {"perk": "speed"}]},
		}, "branch_order": ["shotgun", "smg"]},
}
const SQUAD_CLASS_ORDER := ["brawler", "sniper", "raider"]
## Уровень выбора ветки и сколько ждать выбора игрока (потом — первая ветка сама; боты выбирают сразу).
const SQUAD_BRANCH_LEVEL := 5
const SQUAD_BRANCH_AUTO_S := 20.0
## Класс по месту в команде (player_index / 2): составы зеркальные — налётчик, снайпер, громила. P1 — на месте 0 (налётчик), меняет сам.
const SQUAD_SLOT_CLASSES := ["raider", "sniper", "brawler"]
## Опыт: за 1 HP урона по соперникам и за фраг; пороги уровней 1…8 (опыт с начала матча).
const SQUAD_XP_PER_DAMAGE := 1.0
const SQUAD_XP_PER_FRAG := 40.0
const SQUAD_XP_LEVELS := [0.0, 60.0, 160.0, 300.0, 480.0, 700.0, 960.0, 1260.0]

## Оружие громилы — настоящее оружие игры (Tuning.WEAPON, бьёт физикой через DollCombat). Своё у каждого (ветка 5-го уровня,
## автор 06.10: «выбор из 3 оружий, каждое оружие своё даёт»): speed / cooldown — × скорости и паузы полёта; wave_* — удар в
## полёте поднимает ударную волну (радиус м, импульс Н·с, стан с, урон HP); armor_pierce — броня стычки не гасит урон этим оружием;
## joint_mult — × урона суставам (прочность суставов).
const SQUAD_MELEE := {
	"pan": {"title": "СКОВОРОДА", "note": "звонко и обидно"},
	"hammer": {"title": "МОЛОТ", "note": "удар в полёте — ударная волна вокруг", "speed": 0.9, "cooldown": 1.15,
		"wave_m": 3.0, "wave_impulse": 26.0, "wave_stun_s": 0.6, "wave_damage": 8.0},
	"sword": {"title": "МЕЧ", "note": "полёт быстрее, пауза вдвое короче", "speed": 1.2, "cooldown": 0.5},
	"axe": {"title": "ТОПОР", "note": "сквозь броню, рубит суставы", "armor_pierce": true, "joint_mult": 2.5},
}
## Полёт громилы (SquadMelee, автор 06.10: «выпад сделай как молот Тора — резкое ускорение на 5 секунд в сторону оружия; проверь,
## чтобы импульс был нормальный и не ваншотил сразу всех»): ЛКМ зажата — оружие тянет бойца к курсору до SQUAD_DASH_S (отпустил —
## полёт кончился), скорость до SQUAD_DASH_SPEED с разгоном SQUAD_DASH_ACCEL, кисть с оружием впереди (× SQUAD_DASH_HAND); потом пауза
## SQUAD_DASH_COOLDOWN_S. Удар оружием в полёте — не больше SQUAD_DASH_HIT_MAX HP и по одному бойцу не чаще SQUAD_DASH_HIT_GAP_S
## (молот на 12 м/с иначе снимал 60 HP с касания и добивал прижатого за секунду).
const SQUAD_DASH_S := 5.0
const SQUAD_DASH_SPEED := 12.0
const SQUAD_DASH_ACCEL := 38.0
const SQUAD_DASH_HAND := 1.6
const SQUAD_DASH_COOLDOWN_S := 4.0
const SQUAD_DASH_HIT_MAX := 35.0
const SQUAD_DASH_HIT_GAP_S := 0.6
## Удар оружием громилы не в полёте — не больше этого (молот махом мыши иначе снимал 60).
const SQUAD_MELEE_HIT_MAX := 40.0
## Удары телом и оружием в стычке (SquadMatch.on_hit, автор 06.10: «в рукопашке всё трясётся, и не прерывается»): без стоп-кадров,
## замедлений и толчков кадра; камеру чуть трясёт только удар не слабее SQUAD_MELEE_SHAKE_MIN HP, в котором участвует человек.
const SQUAD_MELEE_SHAKE_MIN := 14.0
const SQUAD_MELEE_SHAKE_MULT := 0.5
## Прочность суставов (Tuning.JOINT_*, клавиша C в бою) в стычке включена по умолчанию (автор 06.10): конечности отлетают. Оторвало
## руку с оружием — стрелять нечем; любой ящик возвращает руку с оружием (и даёт своё).
const SQUAD_JOINTS_DEFAULT := true
## Запас суставов бойцов стычки × столько (JOINT_HP_BASE рассчитан на удары телом; винтовка в 24 HP иначе отрывала предплечье с
## одного выстрела). Пуля в кисть изнашивает сустав предплечья, а не кисти (износ кисти × 4 — Damage.target_mult кисти 0.25).
const SQUAD_JOINT_HP_MULT := 2.0
## Броня: пока она есть, входящий урон × SQUAD_ARMOR_MULT (Doll.incoming_mult), снятое с брони = прошедшему урону.
const SQUAD_ARMOR_MAX := 100.0
const SQUAD_ARMOR_MULT := 0.5
## Ящики (SupplyCrate): появляются на точках карты (ProvingGround.supply_points) раз в SQUAD_SUPPLY_EVERY_S, не больше SQUAD_SUPPLY_MAX
## сразу, живут SQUAD_SUPPLY_LIFE_S; берёт тот, кто коснулся (любая деталь ближе SQUAD_SUPPLY_PICK_M к центру). Виды: weight — доля
## появлений; патроны (amount — доля полного запаса), жизни (HP), броня; бонусы на seconds (автор 06.10: «бонусы как зум»): обзор —
## камера дальше × mult (боту — дальность восприятия), ярость — урон × mult, форсаж — тяга и скорость × mult, полёт громилы чаще.
const SQUAD_SUPPLY_EVERY_S := 6.0
const SQUAD_SUPPLY_MAX := 5
const SQUAD_SUPPLY_LIFE_S := 40.0
const SQUAD_SUPPLY_PICK_M := 0.9
const SQUAD_SUPPLY := {
	"ammo": {"weight": 0.30, "amount": 0.6, "title": "+ПАТРОНЫ", "colour": Color(1.0, 0.82, 0.25)},
	"health": {"weight": 0.26, "amount": 40.0, "title": "+ЖИЗНИ", "colour": Color(0.35, 1.0, 0.45)},
	"armor": {"weight": 0.16, "amount": 50.0, "title": "+БРОНЯ", "colour": Color(0.45, 0.8, 1.0)},
	"zoom": {"weight": 0.10, "seconds": 25.0, "mult": 1.35, "title": "ОБЗОР", "colour": Color(0.78, 0.55, 1.0)},
	"rage": {"weight": 0.09, "seconds": 12.0, "mult": 1.5, "title": "ЯРОСТЬ", "colour": Color(1.0, 0.35, 0.2)},
	"haste": {"weight": 0.09, "seconds": 12.0, "mult": 1.35, "title": "ФОРСАЖ", "colour": Color(0.3, 1.0, 0.85)},
}
const SQUAD_BOOSTS := ["zoom", "rage", "haste"]

## Захват флага (SquadMatch.mode «ctf», автор 06.10: «CTF режим я не увидел — добавь»): флаг у базы каждой команды. Чужой флаг берёт
## касание (ближе SQUAD_FLAG_PICK_M), свой упавший — касание возвращает домой; донёс чужой флаг до своего флага (а свой — дома) — очко.
## Выбыл с флагом — флаг падает, через SQUAD_FLAG_RETURN_S сам уходит домой. Несущий летит медленнее (× SQUAD_FLAG_CARRIER_THRUST).
const SQUAD_CAPTURES_TO_WIN := 3
const SQUAD_FLAG_PICK_M := 1.3
const SQUAD_FLAG_RETURN_S := 15.0
const SQUAD_FLAG_CARRIER_THRUST := 0.85
const SQUAD_XP_PER_CAPTURE := 80.0
const SQUAD_XP_PER_RETURN := 20.0

## Бот стычки (SquadBrain): держит дистанцию своего оружия (SQUAD_BOT_RANGE[оружие]), ходит вверх-вниз, стреляет, когда ствол
## смотрит на цель и своих на линии нет; патронов нет — ищет ящик или идёт в рукопашную. Уровни: доля тяги, ошибка прицела (м),
## задержка восприятия (с), конус выстрела (°).
const SQUAD_BOT_LEVELS := {
	1: {"max_in": 0.75, "aim_error_m": 0.9, "reaction_s": 0.4, "fire_cone_deg": 14.0},
	2: {"max_in": 0.88, "aim_error_m": 0.55, "reaction_s": 0.3, "fire_cone_deg": 10.0},
	3: {"max_in": 1.0, "aim_error_m": 0.3, "reaction_s": 0.2, "fire_cone_deg": 7.0},
}
const SQUAD_BOT_RANGE := {"pistol": Vector2(6.0, 11.0), "smg": Vector2(5.0, 10.0), "sawnoff": Vector2(2.5, 5.0),
	"shotgun": Vector2(3.0, 6.5), "rifle": Vector2(10.0, 18.0), "marksman": Vector2(12.0, 24.0), "gauss": Vector2(14.0, 28.0)}
const SQUAD_BOT_MELEE_M := 2.2                # цель ближе — наскок с ускорением, как в обычном бою
const SQUAD_BOT_SUPPLY_M := 16.0              # за ящиком (жизни, броня, бонус) бот идёт, если он ближе этого; за патронами — всегда

# --- связки (docs/plan-demo/WORKSHOP_V4.md «Связки», KitLink; автор 06.10: «можно перебить») ---
## Запас связки вне «Запаса из деталей»: столько урона в её тела — и она рвётся (в «Запасе из деталей» — PartHp.break_hp от её ❤).
const LINK_BREAK_HP := 30.0

# --- БОМБА: передай касанием (docs/plan-demo/BOMB.md, MODES_PACK.md §1, 06.10) ---
## Пятеро в куполе Old NULL Hall (P1 + 4 бота, P2 на стрелках — клавиша U). У одной куклы бомба: коснулся любой деталью любой детали
## другой живой куклы — бомба у неё; вернуть тому, от кого получил, нельзя BOMB_RETURN_LOCK_S. Фитиль скрытый, случайный
## BOMB_FUSE_MIN_S…BOMB_FUSE_MAX_S, при передаче не сбрасывается. Конец фитиля — взрыв у держателя: он выбывает, соседей раскидывает без
## урона; через BOMB_NEXT_S бомба у случайного живого. Последний живой берёт партию, матч — до BOMB_WINS_TO_WIN побед.
const BOMB_DOLLS := 5
## Автор 06.10 после первого прогона ботов («давай чуть короче»): было 20–30 с и до 3 побед — матч 11–20 минут.
const BOMB_WINS_TO_WIN := 2
const BOMB_FUSE_MIN_S := 14.0
const BOMB_FUSE_MAX_S := 20.0
const BOMB_RETURN_LOCK_S := 1.0
## Бомбу только что передали — держатель отдаст её дальше не раньше этого (касание в куче не прыгает по трём куклам за один тик).
const BOMB_PASS_MIN_HOLD_S := 0.15
const BOMB_NEXT_S := 2.0                    # после взрыва — новая бомба у случайного живого
const BOMB_ROUND_PAUSE_S := 3.0             # партия кончилась — столько до следующей (или итогов матча)
const BOMB_COUNTDOWN_S := 2.0               # отсчёт перед каждой партией, кроме первой (первая — обычный COUNTDOWN_S)
## Держатель быстрее (автор 06.10: «держатель быстрее — догнать реально»): тяга и предел скорости управления × (Doll.thrust_mult /
## speed_cap_mult). Без предела скорости тяга ×1.2 дала бы только разгон: оба упираются в MAX_MOVE_SPEED за секунду.
const BOMB_HOLDER_THRUST_MULT := 1.2
const BOMB_HOLDER_SPEED_MULT := 1.2
## Взрыв (Explosion.detonate, сила × это): держатель выбывает, соседей раскидывает (урона нет — Doll.incoming_mult = 0 у всех).
const BOMB_BLAST_POWER := 1.0
const BOMB_KO_SLOWMO_S := 0.5               # замедление на взрыв (обычный KO — 1.2 с: за матч взрывов десяток)
## Писк и мигание весь фитиль, темп растёт к концу (автор 06.10: «скрытый таймер, но по миганию и звуку чуть-чуть понятно»). Пауза между
## писками — от доли сгоревшего фитиля k (0 → 1): BEEP_SLOW_S → BEEP_FAST_S по кривой k^BEEP_CURVE; каждая пауза × (1 ± BEEP_JITTER)
## случайно, а у каждой бомбы своя поправка k ± BEEP_BIAS — по темпу «чуть-чуть понятно», но точно не высчитать.
const BOMB_BEEP_SLOW_S := 1.0
const BOMB_BEEP_FAST_S := 0.11
const BOMB_BEEP_CURVE := 1.7
const BOMB_BEEP_JITTER := 0.15
const BOMB_BEEP_BIAS := 0.06
const BOMB_BEEP_FLASH_S := 0.09             # вспышка лампы и света на писк
## Точки появления пятерых (x, y) — на точках арены их четыре; внутри мембраны купола 16 × 19 м.
const BOMB_SPAWN := [Vector2(-10.0, 2.5), Vector2(10.0, 2.5), Vector2(-5.0, 2.5), Vector2(5.0, 2.5), Vector2(0.0, 5.5)]
## Цвета пятерых: первые четыре — PLAYER_COLORS, пятый — фиолетовый (рубашки, метки, HUD).
const BOMB_COLORS := [Color("2f6fde"), Color("d9342b"), Color("2e9e4f"), Color("e8b820"), Color("9b4dde")]
## Камера: игрок + держатель (если он ближе этого, м); дальше — только игрок и стрелка к бомбе у края экрана.
const BOMB_FOCUS_M := 14.0
## Боты (BombBrain): доля тяги, ошибка прицела (м), задержка восприятия (с), упреждение (с), рывок за Заряд.
const BOMB_BOT_LEVELS := {
	1: {"max_in": 0.8, "aim_error_m": 0.6, "reaction_s": 0.35, "lead_s": 0.2, "dash": false},
	2: {"max_in": 0.92, "aim_error_m": 0.35, "reaction_s": 0.25, "lead_s": 0.3, "dash": true},
	3: {"max_in": 1.0, "aim_error_m": 0.2, "reaction_s": 0.15, "lead_s": 0.4, "dash": true},
}
const BOMB_BOT_DASH_M := Vector2(1.2, 6.0)  # держатель-бот жмёт ускорение, когда цель в этом коридоре (м)
const BOMB_BOT_PANIC_M := 3.5               # держатель ближе — бот без бомбы удирает напрямую, с рывком
const BOMB_BOT_FLEE_MARGIN_M := Vector2(3.0, 3.5)   # кольцо бегства — эллипс мембраны, ужатый на столько (по x, по y)

# --- ГОНКА: 10 точек (docs/plan-demo/MODES_PACK.md §4, 06.10; docs/plan-demo/RACE.md) ---
## Автор 06.10: «гонки — нужно быстрее собрать 10 пунктов, кто быстрее соберёт их»; «у всех одни и те же точки: если кто-то взял, то
## у тебя этой точки уже нет, и надо к следующей». RaceMatch (scripts/race/race_match.gd), бот RaceBrain, площадка scenes/race/.
## Сколько точек горит одновременно (1 — драка за каждую точку, 5 — больше маршрута; работает любое 1..6) и сколько собрать для победы.
const RACE_VISIBLE := 3
const RACE_TO_WIN := 10
## Взятие: любая деталь живой куклы ближе RACE_PICK_M к центру точки. Новая точка — на случайной свободной метке не ближе
## RACE_NEW_MIN_M к взявшему (и первые — не ближе этого к центру старта).
const RACE_PICK_M := 0.9
const RACE_NEW_MIN_M := 8.0
## KO → возврат через RACE_RESPAWN_S у последней точки, которую взяла эта кукла (не брала — на старте), на RACE_RESPAWN_DROP_M ниже
## центра точки (точка кукле по грудь, а не под ногами); первые RACE_SPAWN_SHIELD_S урон не проходит.
const RACE_RESPAWN_S := 2.0
const RACE_RESPAWN_DROP_M := 0.9
const RACE_SPAWN_SHIELD_S := 1.5
## Лимит гонки: вышло — побеждает тот, у кого больше точек (равно — кто раньше их набрал).
const RACE_TIME_LIMIT_S := 300.0
## Гонщиков: P1 + боты (P2 — бот или второй игрок на стрелках, клавиша U).
const RACE_RACERS := 4
## Бот гонки (RaceBrain) по уровням 1–3: max_in — доля тяги; dash — ускорение на длинной прямой; yield — соперник ближе к точке в
## столько раз (и на 3 м) — бот берёт другую; shove — вероятность наскочить на соперника, который рядом и ближе к моей точке.
const RACE_BOT_LEVELS := {
	1: {"max_in": 0.8, "dash": false, "yield": 0.6, "shove": 0.0},
	2: {"max_in": 0.92, "dash": true, "yield": 0.65, "shove": 0.4},
	3: {"max_in": 1.0, "dash": true, "yield": 0.7, "shove": 0.8},
}

# --- РЕЖИМЫ: реестр 100+ (docs/plan-demo/MODES_100.md, 08.10) ---
## Автор 08.10: «хочу сделать более 100+ режимов игр разных». Карточки — scripts/modes/mode_catalog.gd, модификаторы — mutators.gd,
## раннер — autoload ModeRun. Числа модификаторов (множители, периоды) — в Mutators.CATALOG и args карточек; здесь — общее.
const MODES_FIELD_BLEND_S := 0.8            # плавная смена поля у «качелей» и «рулетки» (с)
const MODES_RAIN_FUSE_S := 3.0              # «дождь из бочек»: фитиль упавшей бочки (с)
const MODES_HARD_TIMEOUT_EXTRA_S := 90.0    # блиц / марафон: hard_timeout = лимит + столько (Sudden Death успевает решить)

# --- СТЕНКА НА СТЕНКУ 5×5 (docs/plan-demo/BRAWL.md, 08.10) ---
## Автор 08.10: «5×5 это другой режим». Две команды по пять на Полигоне, без оружия, классов и ящиков — только тело. Раунд берёт
## последняя живая команда (возрождения внутри раунда нет), матч — до BRAWL_WINS_TO_WIN побед. BrawlMatch (scripts/brawl/brawl_match.gd),
## бот BrawlBrain, площадка scenes/brawl/.
const BRAWL_PER_TEAM := 5
const BRAWL_WINS_TO_WIN := 2
## Раунд не дольше BRAWL_ROUND_LIMIT_S: дальше Sudden Death как в Match (отброс растёт шагами SUDDEN_DEATH_STEP_S); на
## BRAWL_ROUND_HARD_S раунд — команде, у которой больше суммарный запас живых (равно — ничья, раунд никому).
const BRAWL_ROUND_LIMIT_S := 120.0
const BRAWL_ROUND_HARD_S := 180.0
const BRAWL_ROUND_PAUSE_S := 3.0            # раунд кончился — столько до следующего (или итогов)
const BRAWL_COUNTDOWN_S := 2.0              # отсчёт перед каждым раундом, кроме первого (первый — обычный COUNTDOWN_S)
const BRAWL_TEAM_DAMAGE_MULT := 0.0         # свои не ранят и не оглушают (толчки полные), как в стычке
const BRAWL_KO_SLOWMO_S := 0.4              # замедление на KO с участием человека (обычное 1.2 с: за матч нокаутов десятки)
## Точки появления пятерых синих (x, y) — две линии у левого края Полигона (палуба базы x −28, укрытие x −21); красные — зеркально
## по x. Слот команды k = player_index / 2.
const BRAWL_SPAWN := [Vector2(-28.5, 2.8), Vector2(-24.5, 0.5), Vector2(-28.5, 5.2), Vector2(-24.5, 3.4), Vector2(-28.5, 7.6)]
const BRAWL_COLORS := [Color("2f6fde"), Color("d9342b")]   # синие, красные — рубашки, обводка, HUD
## Камера: человек + до BRAWL_FOCUS_N ближайших к нему живых врагов не дальше BRAWL_FOCUS_M (м); людей нет — все живые.
const BRAWL_FOCUS_M := 12.0
const BRAWL_FOCUS_N := 2
## Бот (BrawlBrain): наскок — отход — наскок на ближайшего живого врага. max_in — доля тяги; reaction_s — задержка восприятия;
## aim_error_m — ошибка прицела; lead_s — упреждение; retreat_s — отход после наскока; dash — ускорение с разбега.
const BRAWL_BOT_LEVELS := {
	1: {"max_in": 0.8, "reaction_s": 0.36, "aim_error_m": 0.55, "lead_s": 0.15, "retreat_s": 1.5, "dash": false},
	2: {"max_in": 0.92, "reaction_s": 0.30, "aim_error_m": 0.45, "lead_s": 0.2, "retreat_s": 1.3, "dash": true},
	3: {"max_in": 1.0, "reaction_s": 0.24, "aim_error_m": 0.35, "lead_s": 0.25, "retreat_s": 1.1, "dash": true},
}
## Держится своих: дальше BRAWL_BOT_COHESION_M от центра живых своих — тяга к ним примешивается (до полной на
## BRAWL_BOT_COHESION_M × 2); один в поле не улетает к краю.
const BRAWL_BOT_COHESION_M := 9.0

# --- ЗАРАЖЕНИЕ: коснулся — заразил (docs/plan-demo/INFECTION.md, MODES_IDEAS.md Б5, 08.10) ---
## Семеро в куполе Old NULL Hall (P1 + боты, P2 на стрелках — клавиша U). Один случайный — заражённый (зелёный): коснулся любой
## деталью любой детали здорового — тот заражён сразу (перекраска, вспышка, тост). Урона нет (Doll.incoming_mult = 0), только толчки.
## Заражённые быстрее (INFECTION_ZOMBIE_*), но без руки мышью и без рывка (Заряд заперт). Партия INFECTION_ROUND_S: все заражены
## раньше — очко первому заражённому; кто-то дожил — очко каждому дожившему. Матч — INFECTION_ROUNDS партий, места по очкам.
const INFECTION_DOLLS := 7
const INFECTION_ROUNDS := 3
const INFECTION_ROUND_S := 90.0
## Только что заражённый сам заражает не раньше этого (в куче заражение не прыгает по трём куклам за один тик).
const INFECTION_TOUCH_GAP_S := 0.5
const INFECTION_ZOMBIE_THRUST_MULT := 1.15
const INFECTION_ZOMBIE_SPEED_MULT := 1.15
const INFECTION_ROUND_PAUSE_S := 3.0            # партия кончилась — столько до следующей (или итогов матча)
const INFECTION_COUNTDOWN_S := 2.0              # отсчёт перед каждой партией, кроме первой (первая — обычный COUNTDOWN_S)
## Последние INFECTION_PULSE_S партии — пульс мембраны и писк (как темп бомбы): пауза между ударами PULSE_SLOW_S → PULSE_FAST_S.
const INFECTION_PULSE_S := 15.0
const INFECTION_PULSE_SLOW_S := 1.0
const INFECTION_PULSE_FAST_S := 0.25
## Цвет заражённых (рубашки, метки, HUD) и цвета семерых здоровых: как BOMB_COLORS без зелёного (зелёный — заражение) плюс
## бирюзовый, оранжевый и розовый.
const INFECTION_COLOR := Color("3fdc4a")
const INFECTION_COLORS := [Color("2f6fde"), Color("d9342b"), Color("e8b820"), Color("9b4dde"), Color("2ab8c8"), Color("f07a1e"), Color("e86aa8")]
## Точки появления семерых (x, y) внутри мембраны купола 16 × 19 м — друг от друга не ближе 6 м (заражённый не берёт соседа на старте).
const INFECTION_SPAWN := [Vector2(-12.0, 2.5), Vector2(12.0, 2.5), Vector2(-6.0, 2.5), Vector2(6.0, 2.5), Vector2(0.0, 7.0),
	Vector2(-8.0, 9.0), Vector2(8.0, 9.0)]
## Камера: человек + ближайший заражённый (здоровому) или здоровый (заражённому), если он ближе этого, м.
const INFECTION_FOCUS_M := 14.0
## Боты (InfectionBrain): доля тяги, ошибка прицела (м), задержка восприятия (с), упреждение (с), рывок за Заряд (только здоровым).
const INFECTION_BOT_LEVELS := {
	1: {"max_in": 0.8, "aim_error_m": 0.6, "reaction_s": 0.35, "lead_s": 0.2, "dash": false},
	2: {"max_in": 0.92, "aim_error_m": 0.35, "reaction_s": 0.25, "lead_s": 0.3, "dash": true},
	3: {"max_in": 1.0, "aim_error_m": 0.2, "reaction_s": 0.15, "lead_s": 0.4, "dash": true},
}
const INFECTION_BOT_PANIC_M := 4.0              # заражённый ближе — здоровый бот удирает напрямую, с рывком
const INFECTION_BOT_CORNER_M := 2.5             # здоровый у мембраны ближе этого и заражённый между ним и серединой — рывок сквозь
const INFECTION_BOT_FLEE_MARGIN_M := Vector2(3.0, 3.5)   # кольцо бегства — эллипс мембраны, ужатый на столько (по x, по y)

# --- ОХОТА ЗА ГОЛОВАМИ: 3 на 3 (docs/plan-demo/HEADHUNT.md, MODES_IDEAS.md Б4, 08.10) ---
## Две команды по HEADHUNT_TEAM на Полигоне (синие слева, красные справа). Удары с уроном; выбитый оставляет голову (RigidBody3D в
## группе heads, meta owner_team) и возвращается через HEADHUNT_RESPAWN_S на своей стороне. Голову берёт касание любой деталью
## (ближе HEADHUNT_PICK_M), носитель несёт до HEADHUNT_CARRY_MAX голов на спине, тяга × HEADHUNT_CARRY_THRUST за каждую; выбили —
## все его головы и своя рассыпаются (HEADHUNT_DROP_LOCK_S их нельзя взять — разлетаются). Коснулся своей корзины (ближе
## HEADHUNT_BASKET_M) — чужие головы +1 каждая, свои — возвращены без очка. До HEADHUNT_SCORE_TO_WIN или HEADHUNT_TIME_S (больше очков).
const HEADHUNT_TEAM := 3
const HEADHUNT_SCORE_TO_WIN := 10
const HEADHUNT_TIME_S := 360.0
const HEADHUNT_RESPAWN_S := 4.0
const HEADHUNT_SPAWN_SHIELD_S := 1.5         # после возрождения урон не проходит столько с
const HEADHUNT_PICK_M := 0.9
const HEADHUNT_BASKET_M := 1.4
const HEADHUNT_CARRY_MAX := 3
const HEADHUNT_CARRY_THRUST := 0.9
const HEADHUNT_DROP_LOCK_S := 0.6
const HEADHUNT_DROP_SPEED := Vector2(2.0, 4.5)   # м/с разлёта голов с выбитого носителя
const HEADHUNT_KO_SLOWMO_S := 0.35
## Корзины (x, y) — на палубах баз Полигона (tools/build_proving_ground.gd: палуба 26…30 м, верх 2.65); знак x — команда.
const HEADHUNT_BASKET_AT := Vector2(29.4, 3.1)
## Голова упала в страховочный низ Полигона — возвращается сверху над серединой (случайный x в пределах ±, высота y).
const HEADHUNT_RESCUE := Vector2(6.0, 9.0)
const HEADHUNT_COLORS := [Color("2f6fde"), Color("d9342b")]   # синие, красные — рубашки, метки, HUD
## Боты (HeadhuntBrain): доля тяги, ошибка прицела (м), задержка восприятия (с), упреждение (с), отход после наскока (с), рывок за Заряд.
const HEADHUNT_BOT_LEVELS := {
	1: {"max_in": 0.8, "aim_error_m": 0.55, "reaction_s": 0.36, "lead_s": 0.15, "retreat_s": 1.5, "dash": false},
	2: {"max_in": 0.92, "aim_error_m": 0.42, "reaction_s": 0.28, "lead_s": 0.22, "retreat_s": 1.3, "dash": true},
	3: {"max_in": 1.0, "aim_error_m": 0.3, "reaction_s": 0.2, "lead_s": 0.3, "retreat_s": 1.1, "dash": true},
}
const HEADHUNT_BOT_HEAD_M := 8.0             # чужая голова лежит ближе — охотник летит за ней, а не за врагом
const HEADHUNT_BOT_DEFEND_M := 10.0          # защитник: враг ближе этого к корзине — бой, дальше — у корзины
const HEADHUNT_BOT_CRUISE_Y := 5.6           # высота перелёта через укрытия Полигона (верх укрытий 2.2, плит 4.8)
## Камера: человек + до HEADHUNT_FOCUS_N ближайших к нему живых врагов не дальше HEADHUNT_FOCUS_M (м); людей нет — все живые.
const HEADHUNT_FOCUS_M := 12.0
const HEADHUNT_FOCUS_N := 2

# --- ПЕРЕТЯГИВАНИЕ КАНАТА: 2 на 2 (docs/plan-demo/TUG.md, MODES_IDEAS.md A4, 08.10) ---
## Спорт-зал, канат-цепь на полу, синие слева (P1, P3), красные справа (P2, P4). Рука (ArmAssist) хватает звено своей половины —
## звенья чужой не хватаются (meta grab_team); держишь — тяга «от центра» × TUG_PULL_MULT. Метка середины за чертой ±TUG_LINE_M
## TUG_HOLD_S подряд — очко той стороне, канат и куклы заново. До TUG_SCORE_TO_WIN или TUG_TIME_S (ведущий; равно — ничья).
## Удар — урон обычный; KO — возврат у своей стены через TUG_RESPAWN_S.
const TUG_TEAM := 2                         # кукол в команде
const TUG_ROPE_M := 10.0                    # длина каната
const TUG_ROPE_LINKS := 20                  # звеньев (чётное: метка — на стыке половин)
const TUG_ROPE_MASS_KG := 40.0              # масса каната целиком (звено 2 кг — PropHeft LIGHT: рука приваривает)
const TUG_LINK_FRICTION := 0.8              # трение звена о пол (материал звена; пол зала 0.8)
const TUG_LINK_RADIUS := 0.07
const TUG_LINE_M := 3.0                     # черты на полу: ±столько от центра
const TUG_HOLD_S := 1.0                     # метка за чертой столько подряд — очко
const TUG_SCORE_TO_WIN := 3
const TUG_TIME_S := 240.0                   # 4 мин; вышло — побеждает ведущий, равно — ничья
const TUG_PULL_MULT := 1.3                  # тяга держащего звено, когда ввод смотрит от центра (Doll.thrust_mult)
const TUG_RESPAWN_S := 3.0                  # KO → возврат у своей стены
const TUG_POINT_PAUSE_S := 2.0              # после очка — пауза, потом расстановка
const TUG_RESET_COUNTDOWN_S := 2.0          # отсчёт перед розыгрышем после очка (первый — обычный COUNTDOWN_S)
## Точки появления (x, y) по player_index: 0 / 2 — синие у левой стены, 1 / 3 — красные у правой (половина зала 11 м).
const TUG_SPAWN := [Vector2(-5.0, 0.05), Vector2(5.0, 0.05), Vector2(-7.5, 0.05), Vector2(7.5, 0.05)]
const TUG_COLORS := [Color("2f6fde"), Color("d9342b")]
## Боты (TugBrain) по уровням: pull — доля тяги в рывке; rest — доля тяги между рывками; heave — рывок (с, случайно в диапазоне),
## rest_s — пауза между рывками; regrip_s — задержка перехвата (звено ушло за центр или выпало из руки); dash — ускорение в рывке;
## strike — отпустить канат и ударить соперника ближе TUG_BOT_STRIKE_M, когда метка на нашей стороне.
const TUG_BOT_LEVELS := {
	1: {"pull": 0.62, "rest": 0.15, "heave": Vector2(0.6, 1.0), "rest_s": Vector2(0.5, 1.0), "regrip_s": 2.5, "dash": false, "strike": false},
	2: {"pull": 0.85, "rest": 0.0, "heave": Vector2(1.2, 2.2), "rest_s": Vector2(0.4, 1.0), "regrip_s": 1.4, "dash": true, "strike": false},
	3: {"pull": 1.0, "rest": 0.3, "heave": Vector2(1.2, 1.8), "rest_s": Vector2(0.2, 0.45), "regrip_s": 0.7, "dash": true, "strike": true},
}
const TUG_BOT_STRIKE_M := 5.0               # соперник ближе — бот ур. 3 иногда отпускает канат и бьёт (метка на нашей стороне, свой держит)
const TUG_BOT_WAIT_S := 3.0                 # начало розыгрыша: бот не рвёт канат, пока все боты не взялись (не дольше)
const TUG_BOT_PRESS_M := 2.0                # метка на нашей стороне дальше — бот тянет без передышек (дожимает)
const TUG_BOT_DOWN := 0.15                  # доля тяги вниз при держании (упор в пол)
const TUG_BOT_GRIP_LINKS := [2, 6]          # звено бота: от метки столько звеньев (передний, задний в команде)
const TUG_BOT_HOVER_Y := 0.1               # ЦМ бота над звеном при подлёте (кисть достаёт до пола, только когда кукла низко)

# --- ЦАРЬ ГОРЫ: зона переезжает, очко в секунду тому, кто в ней один (docs/plan-demo/KING.md, MODES_IDEAS.md Б10, 08.10) ---
## Пятеро в куполе Old NULL Hall, все против всех. Зона («гора») — круг радиуса KING_ZONE_R вокруг одной из точек KING_ZONE_SPOTS;
## раз в KING_ZONE_S переезжает на другую точку не ближе KING_ZONE_MIN_MOVE_M (за KING_ZONE_WARN_S до переезда кольцо мигает, новая зона
## подсвечена призраком). Очки — KING_POINT_PER_S в секунду тому, чей центр масс в зоне один; двое и больше — никому. Один и тот же в
## зоне один KING_STREAK_S подряд — «ЦАРЬ!», очки ×KING_STREAK_MULT, пока его не выбили. KO → возврат через KING_RESPAWN_S на случайной
## точке KING_SPAWN вне зоны. До KING_SCORE_TO_WIN очков или KING_TIME_S (больше очков).
const KING_DOLLS := 5
const KING_ZONE_R := 2.5
const KING_ZONE_S := 30.0
const KING_ZONE_WARN_S := 3.0
const KING_ZONE_MIN_MOVE_M := 6.0
## Точки зоны внутри мембраны купола (эллипс 16 × 19 м от (0, 0), пол y ≈ 0): пол слева / по центру / справа, воздух на 4–5 м,
## повыше по бокам и под потолком. У каждой — не меньше четырёх других не ближе KING_ZONE_MIN_MOVE_M.
const KING_ZONE_SPOTS := [Vector2(-9.0, 2.2), Vector2(0.0, 2.2), Vector2(9.0, 2.2), Vector2(-6.0, 4.5), Vector2(6.0, 4.5),
	Vector2(-3.0, 9.0), Vector2(3.0, 9.0), Vector2(0.0, 13.0)]
const KING_POINT_PER_S := 1.0
const KING_SCORE_TO_WIN := 60
const KING_TIME_S := 300.0
const KING_RESPAWN_S := 3.0
const KING_STREAK_S := 10.0
const KING_STREAK_MULT := 2.0
## Точки появления: по player_index в начале матча, после KO — случайная из них вне зоны (не ближе KING_ZONE_R + KING_SPAWN_CLEAR_M).
const KING_SPAWN := [Vector2(-10.0, 2.5), Vector2(10.0, 2.5), Vector2(-5.0, 2.5), Vector2(5.0, 2.5), Vector2(0.0, 5.5),
	Vector2(-12.0, 5.0), Vector2(12.0, 5.0)]
const KING_SPAWN_CLEAR_M := 1.0
## Камера: зона в кадре, если ближе этого (м) к человеку.
const KING_FOCUS_M := 14.0
## Бот (KingBrain) по уровням 1–3: max_in — доля тяги; aim_error_m / reaction_s / lead_s — прицел, задержка восприятия, упреждение
## (EnemyBrain); dash — ускорение в наскоке и на перелёте к зоне; foresee — зона мигает (скоро переедет) → летит к новой заранее;
## lurk — в зоне уже дерутся двое и больше → ждать у края (KING_BOT_LURK_M от кромки), пока не останется один, и тогда наскок.
const KING_BOT_LEVELS := {
	1: {"max_in": 0.8, "aim_error_m": 0.6, "reaction_s": 0.4, "lead_s": 0.15, "dash": false, "foresee": false, "lurk": false},
	2: {"max_in": 0.92, "aim_error_m": 0.35, "reaction_s": 0.25, "lead_s": 0.3, "dash": true, "foresee": false, "lurk": true},
	3: {"max_in": 1.0, "aim_error_m": 0.2, "reaction_s": 0.15, "lead_s": 0.4, "dash": true, "foresee": true, "lurk": true},
}
const KING_BOT_GUARD_M := 3.0               # бот один в зоне: чужой ближе этого — наскок на него, потом обратно к центру
const KING_BOT_DASH_M := Vector2(1.5, 7.0)  # наскок: ускорение, когда цель в этом коридоре (м)
const KING_BOT_LURK_M := 1.8               # lurk: на столько дальше кромки зоны ждать, пока в ней дерутся

# --- ХОККЕЙ: четвёртый вид спорт-зала (docs/plan-demo/HOCKEY.md, 08.10) ---
## Шайба (scenes/sport/puck.gd, Puck extends SportBall) — плоский диск, стоит ребром к камере (катится как монета, но почти не
## крутится: ang_damp 6), скользит по льду: трение 0.02 (у пола зала материала нет — берётся меньшее), дамп 0.2 → после удара
## 6 м/с проходит ≈ 24 м (до стены — отскок 0.55). Не подпрыгивает: вверх от пола медленнее HOCKEY_PUCK_HOP_KILL — гасится.
## Физика снаряда (масса, тяжесть, отскок, трение, дамп) — Tuning.SPORTS["hockey"], как у мячей.
const HOCKEY_PUCK_R := 0.28               # м: радиус диска (настоящая шайба 0.038 — куклой 1.8 м не попасть)
const HOCKEY_PUCK_THICK := 0.12           # м: толщина диска
const HOCKEY_PUCK_HOP_KILL := 2.6         # м/с: подскок от пола медленнее этого гасится (вбрасывание с 2 м даёт ≈ 2.2 — ляжет сразу)
const HOCKEY_GOALS_TO_WIN := 3            # матч до стольких голов
const HOCKEY_TIME_S := 240.0              # основное время 4:00; равный счёт — золотой гол ещё SPORT_GOLDEN_S
const HOCKEY_GOAL_H := 1.2                # м: ворота низкие (SPORTS["hockey"].goal_h — то же число для SportMatch / SportBrain)
## Клюшка — оружие "stick" (scenes/weapons/weapon_stick.tscn, Tuning.WEAPON["stick"]) в правой кисти каждой куклы: даёт HockeySticks
## (scripts/sport/hockey_sticks.gd) на старте, после расстановки, после нокаута — новая (старая убирается), без клюшки дольше
## HOCKEY_STICK_REGIVE_S (кисть оторвана вместе с клюшкой) — новая в свободную кисть. Ничья клюшка на льду дольше ORPHAN_S — убирается.
const HOCKEY_STICK_HAND := "Hand_R"
const HOCKEY_STICK_HOLD_DEG := 15.0       # угол хвата (WeaponPickup.hold_angle_deg): почти продолжение руки — крюк достаёт до льда
const HOCKEY_STICK_CHECK_S := 0.5         # как часто HockeySticks сверяет, у всех ли клюшка
const HOCKEY_STICK_REGIVE_S := 2.0        # без клюшки столько — новая
const HOCKEY_STICK_ORPHAN_S := 4.0        # ничья клюшка лежит столько — убирается
## Бот (HockeyBrain extends SportBrain): гонится за шайбой с упреждением и бьёт сквозь неё к чужим воротам (SportBrain), у
## шайбы в ударе — раскрутка (request_spin, замах клюшкой); шайба на своей половине дальше от своих ворот, чем бот, — вратарь:
## держится на луче ворота → шайба в HOCKEY_GOALIE_OUT_M от линии. Уровни 1..3: тяга, прицел, упреждение, ускорение, раскрутка, вратарь.
const HOCKEY_GOALIE_OUT_M := 1.3
const HOCKEY_SPIN_NEAR_M := 1.7           # раскрутка, когда до шайбы ближе этого в ударе
const HOCKEY_BOT_LEVELS := {
	1: {"max_in": 0.7, "aim_error_m": 0.6, "lead_s": 0.1, "dash": false, "spin": false, "goalie": false},
	2: {"max_in": 0.88, "aim_error_m": 0.3, "lead_s": 0.2, "dash": true, "spin": true, "goalie": true},
	3: {"max_in": 1.0, "aim_error_m": 0.12, "lead_s": 0.3, "dash": true, "spin": true, "goalie": true},
}
