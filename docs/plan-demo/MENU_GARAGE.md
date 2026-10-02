# Главное меню «Гараж + эфир» — идея, болванка, промты (02.10.2026)

> Идея автора (02.10): слева тёмная комната — гараж бойца, в ней телевизор, по нему идёт трансляция NULL Fighting; справа — красивое меню. Что показывает телевизор, может зависеть от момента истории. На разные пункты меню камера плавно переезжает в разные стороны.
>
> Ниже: как я понял идею, моё мнение, кадры болванки (Godot, без моделей), промты для референсов и 3D-предметов. Всё, что сверх слов автора, — **предложение**, пока автор не принял. Прошлый разбор вариантов меню лежит в чате облачной сессии 02.10; этот документ его заменяет.

## 0. Сделано: гараж v1 в Godot (02.10.2026)

Автор прислал кадр стиля и два листа предметов (`docs/refs/menu-garage/G01–G03`) и сказал «делай». Модели сделаны Blender-скриптом по правилу 1 `ASSET_PIPELINE.md`, сгенерированные 3D-модели не понадобились. Куклы в гараже пока нет (просьба автора).

Гараж — главная сцена проекта (решение автора 02.10): `godot --path godot` открывает меню.

Поток экранов (autoload `Flow`, `godot/scripts/menu/flow.gd`): из боя Esc — пауза «ПРОДОЛЖИТЬ / ЗАНОВО / В ГАРАЖ», MAIN MENU в итогах — в гараж, двойной Esc в мастерской — в гараж (с автосохранением). В гараж возвращаемся сразу списком, на пункте, с которого ушли, без титула. Настройки (экран у радио и щитка, `scenes/menu/garage_settings.gd`): громкость, эффекты ударов, полный экран, V-SYNC, субтитры N0, схема управления; сохраняются в `user://settings.cfg` и применяются при запуске. Громкость видна и в гараже: чем громче, тем ярче шкала радио.

| Что | Где |
|---|---|
| Модели (54 штуки: ТВ, тумба, ворота лифта с рампой, пульт, верстак, перфопанель, стенд, лампа, полки, кубки, магнитола, шлем, плющ, шкафчики, стеллаж, «?»-ящик, радио, щиток, флаг, трубы, стены, пол, потолок, карточки с картинками…) | `godot/tools/blender/garage_kit.py` → `godot/assets/models/garage/Garage_*.glb` |
| Текстуры (крашеный металл, полосы опасности, рифлёный лист, пол, ковёр, флаг с эмблемой, плющ, чертёж, фото и афиши из кадров игры, кадры эфира) | `godot/tools/gen_garage_textures.py` (numpy + Pillow) → `godot/assets/textures/garage/` |
| Материалы по ролям (в glb плоские материалы с именем роли, при импорте ставится настоящий) | `godot/scripts/menu/garage_materials.gd`, пост-импорт `godot/tools/garage_import.gd` |
| Сцена (расстановка, свет по зонам, точки камер `CamSpots/*`) | `godot/tools/build_garage_menu.gd` → `godot/scenes/menu/garage_menu.tscn` |
| Поведение (меню справа, переезды камеры, свет зон, эфир на ТВ, вход в пункты) | `godot/scenes/menu/garage_menu.gd`, кинескоп `crt_screen.gdshader` |
| Шрифты меню (OFL, кириллица) | `godot/assets/fonts/` — Oswald, Rubik, JetBrains Mono |
| Проверки | `tests/garage_menu_probe.tscn` (headless, JSON + exit code), `tests/garage_kit_sheet.tscn` (лист моделей), `tests/garage_menu_shots.tscn` (кадры и ролик) |

Пункты (с 02.10, после слияния в main): ИСТОРИЯ → нырок в экран → **кампания в эфире телевизора, без смены сцены** (см. «Кампания в телевизоре» ниже; строки под пунктом, карточка «Следующий бой» на ТВ и реплика N0 — из сохранения кампании: бой N из 4, соперник, счёт, трофеи; без сохранения — первый соперник лестницы; «Выход» на лестнице кампании — обратно в гараж); БЫСТРЫЙ БОЙ → к воротам → купол Old NULL Hall `playground_null_hall.tscn`; МАСТЕРСКАЯ → камера ныряет к стенду, и сборка идёт **в самом гараже, без смены сцены** (см. «Мастерская внутри гаража» ниже); ТРОФЕИ — витрина полки; НАСТРОЙКИ — экран настроек (громкость, графика — пресет `Gfx`, как F9, эффекты, экран, субтитры); ВСЕ РЕЖИМЫ → общий план гаража → тестовое меню сборки `menu/test_menu.tscn` (PvE, арены, пресеты тела; Esc там — обратно в гараж); ВЫХОД — лампы гаснут по зонам, телевизор схлопывается в полоску. Управление: ↑↓ / W S / крестовина, Enter / Space / A, Esc — к «Выходу», цифры 1–6, мышь. В бою Esc — пауза `Flow` (продолжить / заново / в гараж).

Рендерер проекта — Mobile (`PERF_PASS.md` §3): объёмного тумана, SSAO и SSIL в гараже нет (их выключает `Gfx`), кадр темнее и без дымки у ТВ и ворот — так и оставлено; в Forward+ (`--rendering-method forward_plus`) гараж как на кадрах v2. Кадры под Mobile — `docs/plan-demo/img/menu-garage/v3-mobile/`.

Проба (`godot --headless --path godot res://tests/garage_menu_probe.tscn`, 47 проверок, все зелёные 02.10 после слияния): камера доезжает до точки каждого пункта за 0.75 с (допуск 1.3 с), телевизор переключает канал, лампы зоны пункта ярче базы, чужие тусклее, Esc ведёт к «Выходу», от титула до боя 2 нажатия, сцена меняется через 1.16 с после Enter.

### Тренировочный зал за воротами мастерской и лоадер (02.10, просьба автора)

Просьба автора (02.10, к кадрам-референсам «training arena» — манекен на стойке, груша-шар, колонна из покрышек, фермы света, баннеры):
«сделай за дверьми при мастерской большое пространство, при тестировании открывай двери — и там можно вылететь и подраться с манекеном;
HUD — как экраны там + энергетическая сетка по краям, как на стенах комнаты; манекен + груша с экраном силы удара и твоей скорости;
все загрузки — под лоадером».

**Зал.** Левая стена гаража (x = −4.7, проём z −0.6…3.0) — теперь двустворчатые ворота (`Fighter_Gate` кита Old NULL Hall × 0.58,
`scenes/menu/garage_hall_gate.gd`; ящики и бочка переехали к переднему левому углу). За ними — зал `scenes/arena/training_hall.tscn`
(builder `tools/build_training_hall.tscn`, сценой, а не `-s`: скриптам нужны autoload): 41 м вдоль плоскости боя (x −4.7…−47), потолок 10 м,
пол y = 0 — продолжение пола гаража. Кит Old NULL Hall: платформы пола, панели стен, колонны-фермы, световые фермы с прожекторами,
мостки, баннеры, ящики, кабели; новые модули (Blender, `tools/blender/arena_null_hall.py`, роли материалов Hall_*): `Heavy_Bag`,
`Chain_Link`, `Tire_Column`, `Hang_Beam`. Зал спит (`set_awake(false)`: невидим, физика и свет выключены) и просыпается на время испытания.

| Что | Где |
|---|---|
| Зал: пол, стены, колонны, фермы, свет, экраны, сетка, груша, колонна из покрышек | `scenes/arena/training_hall.tscn` + `training_hall.gd` (`TrainingHall`) |
| Груша: шар 45 кг на цепи (пружинная «цепь»: тянет, но не толкает), замер удара | `scenes/props/heavy_bag.tscn` + `heavy_bag.gd` (`HeavyBag`), числа — `Tuning.HEAVY_BAG_*` |
| Экраны на стене (рамы — табло кита, картинка — свой SubViewport + кинескоп) | `scenes/arena/hall_screen.gd` (`HallScreen`: speed / impact / dummy) |
| Энергетическая сетка (светящиеся линии, волна, подсветка у бойца) | `assets/shaders/energy_grid.gdshader` |
| Ворота в стене гаража | `scenes/menu/garage_hall_gate.gd` (`GarageHallGate`), стена — `tools/build_garage_menu.gd` |
| Связка: загрузка зала, ворота, экраны, камера | `scenes/menu/garage_workshop.gd` (`prepare_hall`, `_enter_test`, `_leave_test`) |

Как это идёт: «Испытать» (T) → первый раз зал грузится **под лоадером** («ПОДГОТОВКА ЗАЛА», фоновая загрузка стартует при входе в мастерскую, постановка ≈ 0.1–0.7 с) и испытание
стартует само → кукла оживает в гараже на `TestSpot`, **ворота открываются** (1.1 с), заглушка проёма (`Stage/Bounds/WallL`) снимается → вылетаешь в зал.
Манекен (`TrainingDummy`, на подвесе с балки `Hang_Beam`) — на x = −17, груша — на x = −30 (ушко цепи на балке 6.6 м), колонна из покрышек (с коллайдером) —
на x = −40, ящик и бочка — между воротами и манекеном. Камера испытания ведёт только куклу игрока (`follow_mode = "humans"`) и плавно отъезжает от гаражного кадра
(`min_half_height` 1.55) к залу (3.7) по мере вылета. Esc / Tab → назад к сборке, ворота закрываются, зал засыпает.

**HUD как экраны** (трёх экранов на задней стене, 4.8 × 2.7 м; старые плашки «Урон по манекену» и HP над головой в встроенной мастерской скрыты):
- **СКОРОСТЬ** (у входа) — м/с крупно, км/ч, 24 сегмента шкалы до `HALL_SPEED_SCALE_MS`, максимум, график последних ~3 с;
- **СИЛА УДАРА** (у груши) — пик силы последнего удара в кН крупно, слово (ЛЁГКИЙ / СРЕДНИЙ / ТЯЖЁЛЫЙ / НОКАУТ, пороги `HALL_FORCE_WORDS`), шкала,
  скорость удара и импульс, число ударов и рекорд, столбики последних ударов; вспышка на новом ударе;
- **МАНЕКЕН** — HP-полоса, последний удар, суммарный урон, удары, нокауты.

**Энергетическая сетка** — `energy_grid.gdshader` на панелях: дальняя стена во всю высоту, края задней стены (у ворот и у дальнего конца), полосы у пола
и под потолком вдоль всей стены, слабая сетка потолка; линии сглажены по производным (не рассыпаются вдали), по сетке бежит волна, ближе к бойцу линии ярче.

**Груша.** Замер — по изменению импульса шара за шаг и `get_contact_impulse` (берётся большее), пик за касание; удар засчитан, когда сила ≥ `HEAVY_BAG_HIT_MIN_N`
(120 Н) и прошла пауза без касаний (`HEAVY_BAG_HIT_GAP_S`). Груша не хватается (`meta no_grab` → `ArmAssist.can_grab`), урона не получает.

**Лоадер** (`scripts/menu/loading.gd`, autoload `Loading`; главная сцена теперь `scenes/boot.tscn`): экран «подключение» в стиле эфира ТВ — красная плашка «● ЭФИР»,
полоса прогресса, совет, бегущая строка, кинескоп. API: `begin/set_progress/finish`, `hold/release` (держит, пока в фоне ставится мастерская гаража), `load_async`
(фоновая загрузка с живой полосой), `change_scene` (смена сцены под лоадером). Под ним теперь: запуск игры и гараж, «Быстрый бой» и «Все режимы», возврат в гараж из боя,
постановка купола в кампании, зал при первом испытании. Пробы (dry_run гаража) лоадер не берут. Проба `tests/loading_probe.tscn`.

Пробы и кадры: `tests/garage_workshop_probe.tscn` (теперь 43 проверки: зал под лоадером, ворота, вылет в зал, удар по груше и экран силы, закрытие), `tests/loading_probe.tscn`,
`tests/garage_workshop_shots.tscn`, `tests/training_hall_shots.tscn`, `tests/boot_shots.tscn`. Кадры — `docs/plan-demo/img/menu-garage/v5-hall/`.

Не сделано / идеи: толпа и трибуны в глубине зала (как на референсе); экран «сила» одним числом — можно добавить ранги; звук (гул ворот, удар по груше); коллайдеры гаражных пропсов.

### Кампания в телевизоре (02.10, решение автора: «перестроить как в телек, когда влетаем; желательно не переключать локацию, всё показывать там и красиво»)

Раньше «ИСТОРИЯ» меняла сцену на `campaign/campaign.tscn`: плоские тёмные экраны, бой и мастерская — отдельными сценами. Теперь вся кампания — **эфир внутри телевизора гаража**; сцена не меняется ни разу.

| Что | Где |
|---|---|
| Контроллер: нырок в ТВ, сетка → бой → итоги → мастерская → следующий бой, сохранение, выход | `godot/scenes/menu/garage_campaign.gd` (`GarageCampaign`, создаётся в `garage_menu.gd`) |
| Экраны эфира на весь кадр: турнирная сетка, итоги, «подключение», плашка мастерской | `godot/scenes/menu/campaign_tv_ui.gd` (`CampaignTvUi`) |
| Кинескоп поверх всего: развёртка, виньетка, закруглённые углы, помехи при смене экрана, схлопывание | `godot/scenes/menu/tv_overlay.gdshader` |
| Портреты бойцов (рендер сборки в рантайме, свой SubViewport, кэш) | `godot/scenes/menu/doll_portrait.gd` (`DollPortrait`); иконка трофея — `PartIcons` мастерской |
| Проба / кадры | `tests/garage_campaign_probe.tscn` (headless, 50 проверок, включая настоящий бой ботов), `tests/garage_campaign_shots.tscn` (окно; `-- entrance=1` — выход бойцов) |

Вид — язык карточки «Следующий бой» на самом телевизоре: красная плашка «● LIVE», тёмная полоса заголовка, бордовый градиент (зелёный на победе), косые полосы, крупное имя Oswald, косые плашки и кнопки (`BcStyle`, как у HUD боя), жёлтая бегущая строка внизу, реплика N0 в плашке. Кадры — `docs/plan-demo/img/menu-garage/v4-campaign/`.

| Экран | Что на нём |
|---|---|
| Турнирная сетка | слева «Следующий бой»: портрет игрока против соперника (рендер по сборке, не картинка), VS, имена, уровень, «ФИНАЛ»; справа 4 строки лиги с миниатюрой, статусом и трофеем; рекорд и трофеи; N0 или причина, почему «В БОЙ» не пускает; кнопки В БОЙ / МАСТЕРСКАЯ / НОВАЯ КАМПАНИЯ (второе нажатие подтверждает) / ВЫХОД; у чемпиона — «ЧЕМПИОН 4–0» |
| Итоги боя | гигантские «ПОБЕДА» / «ПОРАЖЕНИЕ» / «НИЧЬЯ», соперник и время, плашка **TROPHY RIGHTS** с иконкой и названием детали (или «трофея нет»), портреты (проигравший серый), полоска прогресса лиги, кнопки |
| Подключение | настроечная таблица и «ПЕРЕКЛЮЧАЕМ НА ПЛОЩАДКУ» на время постановки купола |
| Мастерская | плашка «КАМПАНИЯ · ПРОТИВ: …» с регламентом и кнопками В БОЙ / К СЕТКЕ над 3D-мастерской гаража |

Как это работает:
- **Вход.** Enter на «ИСТОРИЯ» → `state = "campaign"`, меню гаснет, камера за 1.05 с ныряет к телевизору (`IntoTV`), на последних кадрах слой кинескопа даёт «снег», и показывается сетка. Купол (`campaign_fight.tscn`) грузится в фоне, пока игрок читает сетку.
- **Бой — в том же мире.** Экран «подключение» → постановка купола (`campaign_fight.setup`, как в старом потоке) как ребёнка гаража → `GarageMenu.set_world_visible(false)`: комната, мебель, лампы, `WorldEnvironment` и эфир на ТВ спрятаны/остановлены (в мире только купол), камера боя берёт кадр (`DynamicCamera`/`EntranceCam`), поверх — кинескоп силой 0.32, чтобы бой выглядел «по телевизору», но читался. Выход бойцов, отсчёт, HUD, итоги HUD — как раньше. Бой не в отдельном SubViewport: часть эффектов (`hit_fx_director`, `crit_cinematic`) кладёт узлы под `current_scene` — в чужой мир они бы не попали.
- **Итоги.** `fight_finished` → `record_result` (случайная деталь соперника, `CampaignState`), сохранение (`user://campaign.tres` + `user://blueprints/_campaign.tres`), комната возвращается, камера гаража снова текущая, экран итогов. Поражение — лестница стоит, штрафа нет; сдача боя (Esc) — к сетке без записи.
- **Мастерская между боями — встроенная** (`GarageWorkshop.open_campaign`): полка = стартовый кит + трофеи, шаблоны закрыты, регламент энергии лиги, сборка и автосейв — чертёж кампании (`_campaign`), Esc без инструмента — сразу к сетке (`WorkshopBuild.single_esc_exit`), камера плывёт к стенду и обратно к телевизору. После выхода свободной мастерской возвращаются её полка, шаблоны и автосейв игрока.
- **Выход.** Esc на сетке или «ВЫХОД» → помехи, камера отъезжает к пункту меню, строки пункта «ИСТОРИЯ» и карточка на ТВ обновляются (`GarageMenu.refresh_story`: «Лига пройдена · 4–0», «ЧЕМПИОН»).
- **Отдельная сцена кампании осталась** (`campaign/campaign.tscn`, `campaign_flow.gd`): клавиша 9 в тестовом меню и `campaign_probe` (headless); правила те же, экраны — старые.

Замеры (окно, Mobile, 1920×1080, Mac под нагрузкой): вход → сетка 1.2 с; «В БОЙ» → бой на экране ≈ 2.6 с (постановка купола в основном потоке; заставка «подключение» закрывает её).

Не сделано / идеи: куплю можно догружать в фоне заранее (сейчас `load_threaded_request` стартует при входе в эфир); итоги кампании дальше лиги (город → страна) — вне демо; свой звук эфира (щелчок смены канала, гул кинескопа).

### Мастерская внутри гаража (02.10, решение автора: «не менять даже локацию, всё делать прямо в гараже»)

Раньше «МАСТЕРСКАЯ» меняла сцену на `workshop_build.tscn` (своя комната, ~2–4 с загрузки). Теперь это состояние гаража `state = "workshop"`.

| Что | Где |
|---|---|
| Сцена встроенной мастерской: тот же `workshop_build.gd` + интерфейс + стойка стенда + свет, **без** своей комнаты (`$Workshop` нет), точки на гаражных координатах | `godot/scenes/workshop/workshop_embed.tscn` |
| Контроллер: фоновая загрузка, постановка спящей, нырок камеры, возврат | `godot/scenes/menu/garage_workshop.gd` (`GarageWorkshop`, создаётся в `garage_menu.gd`) |
| Сцена-коробка испытания: `bounds()` для камеры + невидимые пол, стены, потолок | `godot/scenes/workshop/garage_stage.gd`, узел `Stage` в `workshop_embed.tscn` |
| Проба / кадры | `tests/garage_workshop_probe.tscn` (headless, 32 проверки), `tests/garage_workshop_shots.tscn` (окно) |

Как это работает:
- **Загрузка.** Пока игрок на титуле / в меню, `ResourceLoader.load_threaded_request` грузит `workshop_embed.tscn` в тредах (≈1.3 с, кадр не страдает), потом сцена **один раз** ставится в мир гаража спящей (`process_mode DISABLED`, невидима; ≈0.7 с — подвисание приходится на титул, пока камера стоит). Вход «МАСТЕРСКАЯ» после этого не грузит ничего; повторный вход — тот же экземпляр.
- **Вход.** Enter → меню гаснет, кукла-на-ящике и модель стенда гаража прячутся, камера гаража за 0.95 с плывёт к кадру мастерской (`WorkshopBuild.snap_camera_pose()`), затем `take_camera_from(cam)` отдаёт камеру мастерской **без скачка**, интерфейс сборки проявляется. Стенд — `BuildStand` на месте гаражного стенда (−0.75, 0, −1.2) на фоне верстака и афиши; свет — `StandLights` (ключ/контур) поверх света зоны «верстак».
- **Верстак оружия** (Tab): `BenchSpot` над гаражным верстаком; кукла и стенд на это время прячутся (иначе стоят между камерой и верстаком).
- **Испытание.** Бой 2.5D идёт в плоскости **z = 0** (она зашита в `ArmAssist.mouse_on_plane`, `DynamicCamera.plane_z`), а стенд гаража стоит у задней стены (z = −1.2) — поэтому кукла оживает на `TestSpot` (−0.75, 0, 0) прямо на полу гаража. Манекен слева (у ворот), ящик и бочка справа. `Stage/Bounds` — невидимые пол (верх y = 0), стены x = ±4.5 и потолок 3.4 м; камера испытания берёт границы у `Stage` (`test_arena_path`, `test_min_half_height = 1.55` — потолок низкий). На время боя включается `TestLights` (две омни-лампы), лампы зон гаража выравниваются (`_set_zone_mult("")`). Props гаража (ковёр, ящики) коллайдеров не имеют — кукла проходит сквозь них; бой идёт в зазоре между афишей и ковром.
- **Выход.** Двойной Esc (как раньше) → `exit_requested` → `GarageWorkshop.close()`: камера гаража встаёт на кадр мастерской, мастерская засыпает (автосейв пишется), кукла на ящике **пересобирается** по новому чертежу (`GarageDoll.rebuild()`), камера плывёт к пункту меню.
- **Отдельная сцена не удалена**: `workshop_build.tscn` остаётся (тестовое меню «ВСЕ РЕЖИМЫ» → «Мастерская» и проба `workshop_probe`); у неё Esc-Esc по-прежнему `Flow.to_menu()`. Режимы различаются полем `WorkshopBuild.embedded` (нет узла `$Workshop`).

Замеры (окно, Mobile, 1920×1080, 02.10, Mac под нагрузкой): фоновая загрузка 1.3 с, постановка 0.7 с, нырок до передачи камеры 1.3 с (из них 0.95 — сам переезд).

Не сделано / идеи: коллайдеры у крупных пропсов гаража (чтобы бой не шёл сквозь ковёр и ящики); растянуть постановку по кадрам (сейчас 0.7 с одним куском на титуле); N0 комментирует сборку.

Пересборка после правок:

```bash
blender -b --python godot/tools/blender/garage_kit.py [-- Имя …]   # модели (сводка JSON, код 1 при превышении бюджета)
python3 godot/tools/gen_garage_textures.py                          # текстуры
godot --headless --path godot --import
godot --headless --path godot -s res://tools/build_garage_menu.gd   # сцена (перезаписывает .tscn — правки вносить в builder)
godot --headless --path godot res://tests/garage_menu_probe.tscn    # проба
godot --path godot --resolution 1920x1080 res://tests/garage_menu_shots.tscn -- out=/абс/папка   # кадры
```

Кадры v1 — `docs/plan-demo/img/menu-garage/v1/`, v2 (кукла, живой эфир с N0, экраны трофеев и настроек, пауза) — `v2/`, лист моделей — `docs/plan-demo/img/menu-garage/garage-kit-v1.png`.

Сделано по плану 02.10 (было «не сделано»):
1. ~~Меню — главная сцена, возврат из боя в гараж~~ — сделано 02.10 (`Flow`, проба `tests/flow_probe.tscn`).
2. ~~Экраны «Трофеи» и «Настройки»~~ — сделано 02.10. Трофеи (`scenes/menu/garage_trophies.gd`): витрина полки — шлем новичка, магнитола, «?»-место для первой детали соперника (правило трофея), кубки прошлого хозяина бокса; камера подъезжает к предмету, лампа над ним ярче. Настоящих трофеев пока нет — появятся с профилем кампании.
3. ~~Кукла игрока в гараже~~ — сделано 02.10: `scenes/menu/garage_doll.gd` — текущая сборка из мастерской (`user://blueprints/_autosave.tres`, иначе пресет human) сидит на ящике лицом к телевизору (тела заморожены, поза сидя ставится поворотами деталей вокруг суставов в 3D), голова поворачивается к месту пункта меню.
4. ~~Живой эфир~~ — сделано 02.10: `scenes/menu/tv_bout.gd` — свой 3D-мир в SubViewport телевизора: арена Void, «Громила» против «Рогатого» (кит), боты дерутся наскоками без урона (ускорение за Заряд, `Doll.request_dash`), камера трансляции; на каналах с полноэкранной графикой 3D не рисуется. Выключить — `-- menu_live_tv=0` (вместо него смена кадров).
5. ~~N0~~ — в эфире официальный N0 v1 по листу автора (`scenes/n0/n0.tscn`, `ART_NULL.md`): парит в правом верхнем углу кадра, по очереди «говорит» и меняет выражение экрана с жестом. Моё раннее предложение модели (`Garage_N0.glb`) при слиянии убрано.

Дальше (порядок — по решению автора):
1. Профиль игрока из кампании в гараже: трофеи кампании (`CampaignState.trophies`) на полке и в «Трофеях», кукла на ящике — сборка кампании, эфир по моменту истории (§3).
2. Замер кадра на настоящей видеокарте (Mobile): в гараже 7 теней и второй 3D-мир эфира (кадры снимались программным рендером).
3. Реплики N0 в гараже голосом (`N0_VOICE.md`), сейчас — субтитры.

## 1. Как устроено

Бокс 07 — гараж бойца под ареной местной лиги. Ночь, свет почти только от телевизора. Кукла игрока (его текущая сборка) сидит на ящике и смотрит трансляцию. Справа поверх тёмной части кадра — меню.

Каждый пункт меню — место в гараже. Когда фокус переходит на пункт:
- камера за 0.6–0.8 с переезжает к этому месту, движение плавное, с лёгкой дугой;
- над местом загорается своя лампа, остальные зоны притухают;
- телевизор через 2–3 кадра помех переключается на нужный канал;
- ввод не блокируется: следующее нажатие перебивает переезд.

| Пункт | Место в гараже | Камера | Что по телевизору | Свет |
|---|---|---|---|---|
| ИСТОРИЯ | телевизор, кукла на ящике | вперёд, через плечо куклы | следующий соперник и что на кону | экран |
| БЫСТРЫЙ БОЙ | ворота лифта на арену, афиши арен | влево | выставочный канал, превью арены ◀ ▶ | поле NULL из-под ворот |
| МАСТЕРСКАЯ | верстак, стенд, чертёж | влево-назад | карточка бойца: имя, масса, ENERGY | лампа над верстаком |
| ТРОФЕИ | полка с деталями побеждённых | вправо | повтор боя, где взят выбранный трофей | подсветка полок |
| НАСТРОЙКИ | радио, щиток, доска эфира | вправо-назад | настроечная таблица (по ней яркость) | шкала радио |
| ВЫХОД | рубильник на щитке | — | телевизор схлопывается в точку | свет гаснет |

Вход в пункт (предложение):
- **ИСТОРИЯ** — камера ныряет в экран (1.1 с), картинка эфира заполняет кадр, и мы уже в трансляции боя: выход бойца, проход сквозь мембрану. После боя камера выезжает из телевизора обратно в гараж, по ТВ — повтор.
- **БЫСТРЫЙ БОЙ** — ворота поднимаются, фиолетовый свет заливает гараж, к лифту подходят участники (лобби P1–P4), лифт везёт наверх и прячет загрузку арены.
- **МАСТЕРСКАЯ** — кукла встаёт с ящика, камера ныряет к стенду, поверх ложится интерфейс сборки v0.3. Сделано 02.10: мастерская живёт в этой же комнате, переход бесшовный (ниже).
- **ВЫХОД** — рубильник: лампы гаснут по очереди, телевизор схлопывается в белую точку.

Мышь: наведение на предмет в гараже тоже переводит фокус, клик — вход. Цифры 1–5 — сразу к пункту. Геймпад — стики и A/B.

## 2. Мнение

Идея сильная. Она берёт лучшее из двух вариантов прошлого разбора: эфир даёт дешёвый и понятный канал для сюжета, а гараж — личное место игрока, трофеи и мастерскую. Слабые места обоих закрываются: купол NULL виден с первой секунды (на экране), а меню остаётся обычным списком справа — быстрым и понятным.

Что даёт игре:
- **Кадр с первой секунды объясняет, кто ты.** Кукла в тёмном гараже смотрит, как дерутся профи, — это мечта новичка, как в «Рокки». ИСТОРИЯ — это записаться в лигу.
- **Телевизор — главный голос сюжета.** Новости, соперники, повторы, экстренные выпуски, позже — пиратский сигнал Тишины. «Сюжет создаёт геймплей»: что показали по ТВ, то и открылось в меню.
- **NULL объясняется без текста** (предложение). Гараж вне поля, поэтому кукла здесь тяжёлая и сидит обмякнув. В куполе она впервые всплывает. Контраст «тяжело в гараже — легко на арене» — готовое первое «вау» дебюта.
- **Сборка и покраска имеют зрителя.** В гараже сидит твоя текущая сборка, а после победы тебя показывают по телевизору. Ради этого и стоит строить (§7 документа автора).
- **Правило трофея видно вещами.** Полка с деталями побеждённых и пустое место «?» для следующей.

Риски и как их снять:
- **«Сначала весело и ярко».** Тёмная комната может уйти в нуар. Поэтому яркость держат эфир (цветной, спортивный) и тёплые лампы. N0 шутит с первого кадра. Хоррора и мрака нет.
- **Объём.** Нужно 15–20 предметов. С генерацией 3D это реально; главное — одна палитра и один масштаб (требования в §7).
- **Второй рендер — сам эфир.** Живой бой ботов в SubViewport стоит видеокарты. Запасной путь — заранее записанные ролики из самой игры (Movie Maker → `.ogv`, `VideoStreamPlayer`). Для сюжетных выпусков ролики даже удобнее.
- **Правило 1 `ASSET_PIPELINE.md`.** Там все модели — только из Blender-скриптов. Сгенерированные 3D-модели — исключение, его надо записать (решение автора). Для статичных предметов гаража это годится. Куклы и детали остаются из кита: трофеи на полке — тоже детали кита.
- **Узкие экраны** (16:10, Steam Deck). Левая часть кадра сужается — композицию проверить и там.

## 3. Что идёт по телевизору — предложение

| Момент | По телевизору | Зачем |
|---|---|---|
| Первый запуск | живой матч местной лиги; бегущая строка «ОТКРЫТ НАБОР НОВИЧКОВ · БОКСЫ 01–12» | приглашение: ты новичок, ИСТОРИЯ = записаться |
| Перед боем кампании | карточка соперника, его лучшие удары, «НА КОНУ: деталь» | правило трофея: видно, что можно выиграть и проиграть |
| После победы | повтор твоего KO, твоё имя в таблице лиги, N0 хвалит сборку | награда: тебя показывают |
| После поражения | повтор в замедлении и шутка N0 | смягчить и позвать на реванш |
| Фокус на Быстром бое | выставочный канал: превью выбранной арены | выбор арены = переключение каналов ◀ ▶ |
| Фокус на Мастерской | карточка бойца как на выходе (имя, масса, ENERGY, детали) | сборка связана с эфиром |
| Фокус на Трофеях | повтор боя, где взят выбранный трофей | память о победах |
| Настройки | настроечная таблица; яркость подбирают по ней | функция в мире |
| Акт 2 | «ЭКСТРЕННЫЙ ВЫПУСК»: мембрану продавливают снаружи | новый режим (PvE) открывается через эфир |
| Акты 3–4 | чемпионат мира, межмировая лига, первые кадры завоевателей | следующая ступень карьеры |
| Тайна (поздно) | ночью эфир на секунду перебивает пиратский сигнал Тишины; N0 сбивается на полуслове | тайна в предметах, не в диалогах |

Тайну N0 (MEMORY RESET, CYCLE 217) в меню до конца первого акта не показываем.

## 4. Болванка

Отдельный маленький проект Godot: `docs/plan-demo/menu-garage-blockout/`. Это не часть игры: комната и предметы собраны из примитивов, цвет примитива обозначает роль материала. На экране телевизора — кадры из игры (`docs/plan-demo/img/`) и графика эфира. Шрифты меню — Oswald, Rubik и JetBrains Mono (OFL, с кириллицей), кандидаты и для настоящего меню.

Кадры (1600×900) лежат в `docs/plan-demo/img/menu-garage/`:

| Файл | Что |
|---|---|
| `garage-title.png` | титул: общий план, «НАЖМИ ЛЮБУЮ КНОПКУ» |
| `garage-story.png` | ИСТОРИЯ: через плечо куклы, на ТВ — карточка соперника |
| `garage-quick.png` | БЫСТРЫЙ БОЙ: ворота лифта, свет поля, афиши |
| `garage-workshop.png` | МАСТЕРСКАЯ: верстак, стенд, лампа |
| `garage-trophies.png` | ТРОФЕИ: полка, бирки, пустое место «?» |
| `garage-settings.png` | НАСТРОЙКИ: радио, щиток, доска эфира, на ТВ — настроечная таблица |
| `garage-into_tv.png` | вход в бой: камера в экране |
| `garage-plan.png` | план сверху: зоны и точки камер |
| `garage-moves.mp4` | ролик: перелёты камеры по пунктам и нырок в телевизор |
| `no-doll/garage-{title,story,workshop}.png` | те же кадры без куклы (ящик пустой) — по просьбе автора 02.10; в остальных кадрах куклы и так не видно |

Перерисовать (нужно окно; на сервере — `xvfb-run`):

```bash
cd docs/plan-demo/menu-garage-blockout
godot --path . --resolution 1600x900 -- shots=all out=/абс/папка
godot --path . --resolution 1280x720 -- video=1 out=/абс/кадры   # потом ffmpeg -framerate 24 -i f%04d.png …
godot --path . --resolution 1600x900 -- shots=all doll=0 out=/абс/папка   # без куклы
```

Точки камер и зоны — в таблице `SHOTS` в `garage.gd`. В настоящей сцене меню они переедут как есть.

## 5. Как работаем с картинками

1. **Кадр стиля.** Генерируешь «Титул» (промт V1). Как образец композиции прикладываешь `garage-title.png`, как образец кукол — `docs/plan-demo/img/body-kit-v1.png`. Из 4–8 вариантов выбираешь один, он становится эталоном стиля.
2. **Остальные виды** (V2–V7) — тем же стилем: к промту прикладываешь выбранный кадр как образец стиля и кадр болванки как образец композиции.
3. **Предметы для 3D** (§7): картинка по промту → генератор 3D по картинке (Meshy, Tripo, Rodin, Hunyuan3D…). Тоже с эталоном стиля в приложении, чтобы предметы были из одного мира.
4. **Отдаёшь мне** картинки (сохраню в `docs/refs/menu-garage/`) и модели (`.glb`, положу в `godot/assets/models/garage/`). Я собираю настоящую сцену меню и меняю примитивы болванки на модели по одной, с проверкой кадров.

Надписей генераторы не сделают — все тексты (табло, бирки, афиши, эфир) накладываю в движке. Поэтому в промтах везде «без текста».

## 6. Промты: виды (концепт-арт)

Общий блок стиля — добавлять в конец каждого промта вида:

```text
Stylized 3D game art of a handcrafted toy-like world of modular wooden fighters. Chunky, simple, readable shapes. Materials: painted and weathered wood, riveted iron, brass, cream ceramic and bakelite, worn cloth. Muted palette (maroon, teal, mustard, olive, warm wood) with cool blue TV glow and the violet light of the NULL field. Cozy night mood but colorful and inviting, not grim. Cinematic lighting, light volumetric haze, soft bloom. High-end stylized PC game look (It Takes Two, Ratchet & Clank: Rift Apart, Psychonauts 2), Unreal Engine render. 16:9.
```

Описание куклы — добавлять, где она в кадре:

```text
The fighter: a modular wooden ragdoll about 1.5 m tall built from parts — a barrel torso with dark iron hoops and a small glowing porthole on the chest, a box-shaped wooden head with a cream face plate and two small dot eyes, cylindrical wooden limbs, dark ball joints wrapped with teal cloth rings, mitten-like hands. A hand-made toy, not a robot, not a human.
```

Негатив (или «avoid: …» в конце):

```text
humans, realistic people, humanoid robots, cyberpunk, neon city, anime, photorealism, gore, readable text, letters, watermark, logo, UI
```

**V1 — Титул, общий план** (образец: `garage-title.png`)

```text
Wide establishing shot, eye level slightly above. Night interior of a small fighter's garage — a pit bay under a sports arena. The room is dark; the main light source is an old retro-futuristic CRT television with a wooden case and a cream bezel, standing on a low wooden sideboard against the back wall of dark wooden planks. Its screen shows a bright, colorful live sports broadcast of a fight inside a glowing transparent dome. In front of the TV, on a low wooden crate, the fighter sits slumped and heavy, watching the screen, its back three-quarters to the camera. Left side of the room: a workbench with a pegboard full of tools, a pale blue blueprint pinned to the wall, an empty build stand (round steel turntable base, vertical rail, orange saddle ring) under a hanging green enamel lamp with a warm cone of light. Far left wall: a big roller-shutter lift gate with a yellow-black hazard frame, a round porthole and violet light leaking from under the shutter. Concrete floor with a faded painted bay number. The right 40% of the frame is dark, calm, nearly empty negative space reserved for the game menu.
```

**V2 — ИСТОРИЯ, через плечо** (`garage-story.png`)

```text
Over-the-shoulder shot from behind and to the right of the seated fighter, looking at the CRT television on the sideboard. The TV sits left of center and shows a "next opponent" broadcast card: a horned fighter in a dark iron helmet on a maroon background, blank title bars. Blue TV light rims the fighter's shoulder and the edge of its box head in the foreground. Behind the TV: a wall of dark wooden planks, a pale blue blueprint, antenna shadows. The right 40% of the frame is dark and empty.
```

**V3 — БЫСТРЫЙ БОЙ, ворота лифта** (`garage-quick.png`)

```text
The camera turns to the left wall of the garage: a huge industrial roller-shutter lift gate, 3 m wide and 3 m tall, in a heavy steel frame with yellow-black hazard stripes. A round porthole in the shutter glows violet; violet light from the arena field spills across the concrete floor from the gap under the shutter. A big stenciled bay number on the shutter, a small red warning lamp and a dark blank sign plate above. Framed painterly posters of arenas hang on both sides of the gate. It feels like the tunnel to the arena is right behind this door. The right 40% of the frame is dark.
```

**V4 — МАСТЕРСКАЯ, верстак и стенд** (`garage-workshop.png`)

```text
The camera turns to the back-left corner: a sturdy wooden workbench with an olive metal drawer unit, a cast-iron bench vise, a hammer and spare wooden limbs lying on it; a pegboard of tools; a pale blue blueprint of a ragdoll body pinned above. In front of the bench stands an empty build stand — a round steel turntable with brass screws, a vertical rail and a saddle clamp — waiting for the fighter. A hanging green enamel lamp throws a warm cone of light onto the stand through light haze. A wooden bin full of spare limbs in different colors. The right 40% of the frame is dark.
```

**V5 — ТРОФЕИ, полка** (`garage-trophies.png`)

```text
The camera turns to the right wall: a dark wooden shelving unit lit by three small warm clamp spotlights. On the shelves stand trophies taken from defeated opponents: a horned dark iron helmet, a small golden crown, a wooden box head with a cream face plate, a red spiked mace ball, a striped painted forearm, a spring limb. Each trophy has a small blank paper tag; one empty spot is marked with a chalk circle for the next trophy. A teal pennant of the local league hangs above. The right 40% of the frame is dark.
```

**V6 — НАСТРОЙКИ, радио и щиток** (`garage-settings.png`)

```text
The camera turns to the back-right corner: a cream bakelite tube radio with a glowing amber dial on a dark wooden cabinet; a grey-green fuse box on the wall with a big knife-switch lever with a red handle and three indicator lamps (green, amber, red); cables running up to the ceiling; a small wooden-framed chalkboard with blank chalk scribbles; one small warm spotlight. The right 40% of the frame is dark.
```

**V7 — Нырок в телевизор** (`garage-into_tv.png`)

```text
Extreme close-up: the camera pushes into the curved CRT screen of the television, the broadcast fills almost the whole frame — a huge glowing transparent dome arena with wooden fighters floating inside, a scoreboard bar and a red LIVE tag with blank text, crowd lights around. Scanlines, slight barrel distortion, phosphor glow; the cream bezel is visible only at the very edges.
```

**V8 — Выход, свет гаснет** (по желанию; композиция как V1)

```text
Same wide shot of the garage, but every lamp is off and the CRT television is collapsing into a single bright horizontal line in the dark; only the violet light under the lift gate remains, outlining the seated fighter.
```

## 7. Промты: предметы для 3D

Требования к картинке для генератора 3D: один предмет, по центру, целиком в кадре, светло-серый фон, вид спереди-слева и чуть сверху (три четверти), ровный свет без падающих теней. Если генератор принимает несколько видов — добавь вид спереди и сбоку.

Требования к модели:
- `.glb`, масштаб в метрах (размеры — в таблице);
- ориентацию не трогаю: разверну сам;
- треугольников: крупные предметы (телевизор, ворота, верстак, полка) до ~20k, мелкие до ~5k. Если генератор даёт больше — присылай как есть, я упрощу;
- текстуры PBR 1–2K.

Экран телевизора, шкалу радио, иллюминатор ворот и лампы я накрываю своими светящимися материалами. Если генератор не умеет делать их отдельным материалом — не страшно.

Шаблон — подставить предмет вместо `[OBJECT]`:

```text
[OBJECT]. Stylized 3D game asset, single object isolated on a plain light-grey background, centered, whole object in frame, three-quarter view from the front-left and slightly above, neutral even studio lighting, no cast shadows, no other props. Clean readable silhouette, chunky handcrafted proportions, hand-painted PBR materials (worn painted wood, riveted iron, brass, cream bakelite), muted palette (maroon, teal, mustard, olive, warm wood). No text, no logo.
```

| # | Предмет | Размер, м (Ш × В × Г) | Пункт | Вставка вместо `[OBJECT]` |
|---|---|---|---|---|
| 1 | Телевизор | 1.5 × 1.05 × 0.85 | ИСТОРИЯ | `A retro-futuristic CRT television set: chunky wooden case with rounded corners, cream bezel around a large slightly curved dark glass screen (screen off, plain dark), two maroon knobs and a speaker grille on the right side of the bezel, a small red power light, rabbit-ear antenna on top, short tapered legs` |
| 2 | Тумба под ТВ | 1.9 × 0.85 × 0.62 | ИСТОРИЯ | `A low wooden sideboard / TV cabinet with three drawers and brass handles, worn edges, short legs` |
| 3 | Ящик-сиденье | 0.7 × 0.42 × 0.7 | ИСТОРИЯ | `A low sturdy wooden crate with dark corner posts and a diagonal brace, scuffed, used as a seat` |
| 4 | Ворота лифта | 3.4 × 3.6 × 0.4 | БЫСТРЫЙ БОЙ | `An industrial roller-shutter gate set into a heavy steel frame with yellow-black hazard stripes: horizontal metal slats, a round porthole window in the shutter, a small red warning lamp and a blank dark sign plate above the frame` |
| 5 | Верстак | 2.3 × 0.9 × 0.7 | МАСТЕРСКАЯ | `A heavy wooden workbench with a thick worn top, an olive-green metal drawer unit on one side, a cast-iron bench vise on the corner, a lower shelf` |
| 6 | Перфопанель с инструментом | 2.3 × 1.15 × 0.1 | МАСТЕРСКАЯ | `A wall pegboard panel with hanging tools: hammers, wrenches, screwdrivers, clamps, a coil of rope; flat panel, front view` |
| 7 | Подвесная лампа | 0.6 × 0.3 × 0.6 | МАСТЕРСКАЯ | `An industrial pendant lamp with a green enamel cone shade, white inside, an exposed warm bulb and a black cord` |
| 8 | Полка трофеев | 2.6 × 2.2 × 0.4 | ТРОФЕИ | `A wall shelving unit of dark wood with three long shelves and side posts, three small brass clamp spotlights on top, small blank paper tags hanging from the shelf edges, shelves empty` |
| 9 | Радио | 0.74 × 0.42 × 0.3 | НАСТРОЙКИ | `A vintage tube radio of cream bakelite with a rounded top, a large amber tuning dial window, a fabric speaker grille, two maroon knobs and a small telescopic antenna` |
| 10 | Щиток с рубильником | 0.55 × 0.75 × 0.15 | НАСТРОЙКИ / ВЫХОД | `A wall-mounted grey-green metal fuse box with a big knife-switch lever with a red handle and three round indicator lamps (green, amber, red), cables going up` |
| 11 | Тумба под радио | 1.7 × 0.9 × 0.5 | НАСТРОЙКИ | `A dark wooden low cabinet with two doors and iron hinges` |
| 12 | Ящик запчастей | 0.6 × 0.4 × 0.5 | МАСТЕРСКАЯ | `An open wooden bin, empty, with rope handles and painted stencil marks` (конечности в нём — детали кита) |
| 13 | Мелочь гаража | разные | фон | по одному: `a dented oil can`, `a metal bucket`, `a red metal toolbox`, `an extension cable reel`, `a small desk fan`, `a stack of old sports magazines` |

Не генерировать:
- стенд (`godot/scenes/workshop/stand/build_stand.tscn`) и трофеи — в игре уже есть: это стенд мастерской и детали кита (шлем с рогами, корона, голова-ящик, булава…);
- стены, потолок, балки, трубы — сделаю модулями сам.

Текстуры для стен и пола (бесшовные):

```text
Seamless tileable texture, flat front view, even lighting, stylized hand-painted PBR albedo, 2048x2048: [dark weathered vertical wooden planks wall | corrugated painted metal wall, grey-blue | stained concrete garage floor with faded yellow paint marks | worn maroon rug with a simple woven border pattern]
```

## 8. Промты: эфир, интерфейс, афиши (2D)

Это образцы стиля для графики эфира и меню; текст на них будет мусорный, настоящие надписи — в движке.

**Пакет графики эфира NULL Fighting**

```text
Sports broadcast graphics package for a fictional TV channel "NULL FIGHTING", design sheet on a near-black background: a red LIVE tag, a scoreboard bar for two fighters with team-color stripes, a lower third with fighter name and stats, a next-opponent card layout, a REPLAY badge, a news ticker, a field info panel (gravity vector arrow, membrane percent), an audience vote panel with three options and percentage bars. Retro-futuristic 1980s sports TV style mixed with handcrafted materials (paper, enamel, brass). Colors: warm orange, mustard, maroon, teal, cream on near-black. Bold condensed sans-serif headings. Clean flat vector, 16:9.
```

**Заставка и знак канала**

```text
Logo for a fictional sports channel "NULL FIGHTING": an emblem of a glowing hemisphere dome with an elastic membrane and a small wooden ragdoll figure bouncing off it, bold condensed lettering. Flat vector, orange and cream on black, plus a monochrome version.
```

**Меню справа**

```text
Main menu UI design for a stylized physics fighting game, 16:9 screenshot. The left 60% shows a dark cozy garage with a glowing CRT TV (soft focus). The right 40% is a clean menu panel on a dark translucent gradient: the game title "RAGDOLL MASTER" in bold condensed letters (white and orange), a vertical list of five items, the selected item highlighted by an orange accent bar with a two-line description under it, small key hints at the bottom. Premium AAA polish, sports-broadcast typography, no clutter.
```

**Афиши арен** (по одной; вертикальные 2:3)

```text
Vintage sports poster, portrait 2:3, painterly, bold simple shapes, limited palette, paper texture, no text: [wooden ragdoll fighters floating above heaps of junk and cranes at sunset inside a faint glowing dome — "The Scrapyard" | wooden fighters floating among stone ruins, arches and banners at golden hour — "The Ruins" | a huge glowing transparent dome in a packed night stadium, a giant screen with a gravity arrow behind it — "The NULL Dome"]
```

**Купольная арена** (ключевой кадр §27 — для эфира, афиш и будущей арены демо-среза)

```text
Key art: a huge transparent glowing hemisphere dome of the NULL field in the middle of a packed night stadium. Inside, modular wooden ragdoll fighters float in low gravity mid-fight, limbs swinging; the elastic membrane visibly bulges where a fighter hits it. Around: an excited crowd, floodlights, camera cranes, stadium architecture of wood, iron and brass. Behind: a massive screen showing a gravity vector arrow and field readouts. A small round host drone hovers near the dome. Colorful, spectacular, inviting.
```

## 9. N0 — дизайн персонажа

N0 появляется в эфире с первого кадра, а дизайна у него ещё нет. По лору это очень старый дрон исследований NULL, перекрашенный под ведущего лиги. Отсюда идея: свежая ливрея лиги поверх старой промышленной маркировки. Тайну (цифры, нацарапанные внутри) пока не показываем.

```text
Character design sheet of N0, a small flying host drone of a sports broadcast in a world of handcrafted wooden ragdoll fighters. Body the size of a football, rounded, made of old cream ceramic and brass with repaired seams and rivets; one large camera-lens eye with an iris aperture that works as its expressive face; a tiny antenna; a slim anti-gravity ring under the body; two tiny jointed arms, one holding a vintage microphone. Fresh league livery (orange and teal stripes) painted over older faded industrial markings. Friendly, charismatic, a bit mischievous. Front, side, back and three-quarter views, plus six eye expressions (happy, shocked, laughing, suspicious, glitching, sleepy). Neutral grey background, stylized 3D render.
```

## 10. Что дальше

1. Ты генерируешь V1 и выбираешь стиль, потом V2–V7, N0 и предметы.
2. Я собираю настоящую сцену `godot/scenes/menu/garage_menu.tscn`:
   - точки камер и зоны света — из болванки;
   - кукла — твоя сборка (ModularDoll), сидит под обычной гравитацией;
   - телевизор — SubViewport с эфиром (живые боты или ролики).
3. Машина экранов, Esc «назад», проба путей числами (≤ 2 нажатий до боя, нет тупиков) — как в общем скелете прошлого разбора.
4. Записываю исключение для сгенерированных моделей в `ASSET_PIPELINE.md`, если автор его примет.
