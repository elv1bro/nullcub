# Арт через codex (23.10)

Картинки для гаража, лоадера и магазина нарисованы генератором изображений codex на этом компьютере
(`/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex exec`). Карточки «ВСЕ РЕЖИМЫ» остаются снимками самой игры
(`tests/modes_shots.tscn`) — так они честно показывают режим.

## Что где

| Картинка | Куда | Размер |
|---|---|---|
| poster_a «NULL LEAGUE / FIGHT NIGHT», poster_b «LIVE FROM THE DOME» (N0 у телевизора), poster_c «ZERO-G» | `godot/assets/textures/garage/poster_{a,b,c}.png` (роли `Poster_*`) | 408×620 |
| photo_a верстак, photo_b бой с трибун, photo_c N0 и недособранный боец, photo_d кубок, photo_e Свалка на закате, photo_f команда | `godot/assets/textures/garage/photo_{a..f}.png` (роли `Photo_*`, бумажная рамка) | 340×290 |
| banner — знамя Лиги NULL | `godot/assets/textures/garage/banner.png` (роль `BannerCloth`) | 512×832 |
| keyart_wide — два бойца сталкиваются в куполе, N0 снимает | фон лоадера `godot/assets/ui/brand/keyart.jpg` (`scripts/menu/loading.gd`, константа `KEYART`) | 1920×1080 |
| keyart_wide, capsule_tall, эмблема Лиги, три плаката в полном размере | `docs/steam/` — для страницы магазина и пресс-кита | исходный |
| экраны ТВ гаража: эфир (tv_live_a–d), «быстрый бой», «ПОВТОР» | `godot/assets/textures/garage/tv/` — не codex, а снимки карточек режимов (`assets/ui/modes/*.jpg`), `tools/gen_garage_textures.py` → `tv_from_modes()` | 768×432 |

Размеры и имена — как у прежних заглушек `tools/gen_garage_textures.py` (UV моделей гаража рассчитаны на эти пропорции).
Генератор заглушек их больше не перезаписывает (старые — только с `--old-art`).

## Как перегенерировать

```bash
cd godot/tools/codex_art
python3 codex_gen.py jobs_garage.json /абс/папка/out 4     # ~1–3 мин на картинку, 4 параллельно; готовые пропускает
python3 apply_art.py /абс/папка/out                         # раскладка по игре + docs/steam
gtimeout 900 /usr/bin/arch -arm64 /usr/local/bin/godot --headless --path godot --import
```

`jobs_garage.json` — промпты (id, prompt, aspect, refs); общий стиль (куклы-роботы на шарнирах, купол NULL, эфир Лиги, N0,
палитра navy/amber/cyan, запрет на «Ragdoll Master») — в `STYLE` в `codex_gen.py`. Референсы — `refs/` (кадры игры).
Подводный камень: codex без закрытого stdin ждёт ввода («Reading additional input from stdin…») — в скрипте `stdin=DEVNULL`.

## Реклама на аренах (23.10)

Щиты выдуманной Лиги NULL и её выдуманных спонсоров (ORBIT JOINTS — шарниры, VOLTA CORES — ядра, NULL TV — канал Лиги,
SCRAP CUP — кубок Свалки). Реальных марок нет; «Ragdoll Master» нигде нет.

| Что | Файлы |
|---|---|
| Модели (Blender) | `godot/tools/blender/arena_ads.py` → `godot/assets/models/arena/ads/*.glb` + `kit_report.json`: `Ad_Ribbon` (LED-лента борта 5.6×0.62 м, 46 tris), `Ad_Billboard` (щит 16:9 6.4×3.6 м на ногах, 1314), `Ad_Billboard_Pole` (тот же щит на ферме-мачте 7 м, 3522 / 4000), `Ad_Banner_Curved` (дуга R 26 м на 26°, полотно 2 м, 796), `Ad_Flag` (флаг 1:2 на мачте 6.2 м, 102) |
| Материалы ролей | `godot/assets/materials/ads/Ad_*.tres` (ставит `tools/import/role_import.gd` по папке glb); полотно — роль `Ad_Screen`, картинку кладёт расстановка (surface override: альбедо + свечение той же картинкой) |
| Картинки | `godot/tools/codex_art/arena_ads.py` → `godot/assets/textures/arena_ads/`: щиты `board_{fight_night,joints,cores,nulltv,scrap_cup}` 1024×576, ленты `ribbon_{league,joints,cores,nulltv}` 1800×200 (LED-сетка), `banner_curved` 2048×344, `flag_null` 512×1000 |
| Задания codex | `godot/tools/codex_art/jobs_arena_ads.json` — 7 реклам (`ad_*`) + `hero_wide` (широкий арт для Steam, без текста) |
| Расстановка | `godot/scenes/arena/league_boards.gd` (`LeagueBoards.attach(host, layout)`), вызов в `_ready()` арены: `null_hall.gd` (купол), `scrap.gd` (Свалка). Сгенерированные сцены (`tools/build_null_hall.gd`, `scrap.tscn`) не тронуты |

Где стоят (всё — фон: вне поля боя, без коллизий, без теней):
- **Купол** (`NullHall`, быстрый бой и пр.): лента на борту каждой из 33 секций трибун (`Stand_<ярус>_<секция>`, 4 ленты
  по кругу), 3 изогнутых баннера «NULL LEAGUE · SEASON ZERO» на R 26 м, y 10.3 — в тёмной щели между 2-м и 3-м ярусом,
  над головами бойцов.
- **Свалка**: два щита на мачтах за горами (z −13.5…−14.5, по бокам кадра: FIGHT NIGHT слева, SCRAP CUP справа), два
  флага NULL за отвалами (z −7…−7.5, x ±15). Щит на ногах (`Ad_Billboard`) и щиты joints/cores/nulltv сделаны, но пока
  не поставлены (запас для Руин / Void / мастерской).

С 23.10 (днём) щиты, баннер и флаг — **из codex** (`arena_ads.py --codex`); LED-ленты по-прежнему набраны Oswald (текст
на ленте 9:1 надёжнее набирать, чем рисовать). Без `--codex` `arena_ads.py` собирает всё из кадров codex, что уже в репо
(`docs/steam/keyart_wide`, плакаты, эмблема, фото Свалки из гаража) + надписи Oswald — запасной путь.

Прогон 23.10 — 8 заданий, 8 картинок, все приняты (каждую смотрели целиком и крупно: текст, марки, название игры):

| Задание | Размер codex | Куда | Что на картинке |
|---|---|---|---|
| `ad_fight_night` | 1672×941 | `board_fight_night` (Свалка, левый щит) | NULL LEAGUE / FIGHT NIGHT, две куклы бьются в куполе |
| `ad_joints` | 1672×941 | `board_joints` (спорт-зал, борт у пола слева) | ORBIT JOINTS / HOLDS IN ZERO-G. (точка в конце — от codex, читается) |
| `ad_cores` | 1672×941 | `board_cores` (спорт-зал, борт у пола справа) | VOLTA CORES / MORE CHARGE PER HIT, ядро с молниями; самый яркий щит — для тёмных арен ставить с glow ниже |
| `ad_nulltv` | 1672×941 | `board_nulltv` (спорт-зал, борт у пола по центру) | NULL TV, ● LIVE FROM THE DOME, N0 с микрофоном машет; бегущая строка на заднем плане размыта, букв не видно |
| `ad_scrap_cup` | 1672×941 | `board_scrap_cup` (Свалка, правый щит) | SCRAP CUP / BUILT FROM JUNK трафаретом, кукла на куче лома, магнит крана |
| `ad_banner_wide` | 2172×724 (3:1) | `banner_curved` (купол, 3 дуги) | NULL LEAGUE ◯ SEASON ZERO, эмблема — купол над куклой; при обрезке до 6:1 текст и эмблема целы (средняя половина по высоте) |
| `ad_vertical` | 887×1774 (1:2) | `flag_null` (Свалка, 2 флага) | NULL столбиком, кукла вверх ногами над куполом, ZERO-G мелко внизу (в игре читается только NULL) |
| `hero_wide` | 2172×724 (3:1) | `docs/steam/hero_wide.jpg` → `capsules/library_hero_3840x1240.jpg` | те же две куклы и N0 с камерой, что в keyart, панорама купола с трибунами; без текста и логотипов. Вписан ×1.77 без растяжения (обрезка 40 пкс по высоте) |

Отбраковка: ни одной (кривых букв, чужих марок, «Ragdoll Master» не было). Исходники PNG codex в git не кладутся —
в репо только результат (`assets/textures/arena_ads/*.jpg`, `docs/steam/hero_wide.jpg`, капсулы).
Codex рисует 16:9 как 1672×941, «ultra-wide» — 2172×724 (3:1, шире не даёт), 1:2 — 887×1774.

Перегенерация через codex (`codex_gen.py` запускать из корня репо — пути `refs` в заданиях от корня):

```bash
python3 godot/tools/codex_art/codex_gen.py godot/tools/codex_art/jobs_arena_ads.json /абс/папка/ads 4   # <id>.png; готовые пропускает
cd godot/tools/codex_art
python3 arena_ads.py --codex /абс/папка/ads                    # щиты/баннер/флаг из codex, ленты — набор; hero_wide.png → docs/steam/hero_wide.jpg
python3 steam_capsules.py                                      # library_hero возьмёт docs/steam/hero_wide.jpg
cd ../.. && /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/blender/arena_ads.py -- --export   # только если менялись модели
gtimeout 900 /usr/bin/arch -arm64 /usr/local/bin/godot --headless --path . --import
```

Подводный камень: `craft_parts._obj` пересчитывает нормали «наружу» — у открытой дуги это выпуклая сторона, и Godot отсекал
полотно `Ad_Banner_Curved` как заднюю грань (баннер не было видно). В `build_Ad_Banner_Curved` грани развёрнуты после `_obj`.

Проверка: `tests/null_hall_snapshot.tscn` (окно; `role_materials` принимает и `assets/materials/ads/`), `tests/modes_shots.tscn`
`only=quick+scrap` — щиты читаются и не лезут в бой; `match_probe scene=scrap`, `modes_probe`, `run_gate.sh` зелёные.

## Доски «взрослого вида» бойцов (23.10)

Автор: бойцы выглядят «ужасно детские». Сделали три доски направлений — `godot/tools/codex_art/jobs_grownup.json`, результат в
`docs/plan-demo/grownup_art/boards/`:

- `dir_a_test_rig` — краш-тест-манекены;
- `dir_b_scrapyard` — свалочная техника;
- `dir_c_league_pro` — моторспорт и телеэфир Лиги.

Все три — без отказов. У досок свой стиль: в `codex_gen.py` поле `style` задания перекрывает общий стиль-ключ, потому что
общий `STYLE` тянет к нынешнему виду игры, а доски должны были от него уйти. Выбрали **C** и добавили износ из B и визор с меткой краш-теста из A.
Разбор, что сделано в игре, и кадры «до / после» — в `docs/plan-demo/grownup_art/README.md`. Спонсоры на досках — те же
выдуманные (ORBIT JOINTS, VOLTA CORES, NULL TV). В игру декали спонсоров не перенесены.

## Проверено

- Реклама из codex (23.10): `--import` чисто; `null_hall_snapshot` (окно через `tools/godot_nofocus.sh`, 1600×900) — OK 12/12:
  баннеры NULL LEAGUE · SEASON ZERO читаются над бойцами, янтарь на тёмных трибунах — как графика эфира, на кукол не
  тянет; ленты прежние. `scrap_snapshot` `shots=wide+start+fight` — все проверки ok, `fight_readable_P1` 0.474,
  `P2` 0.143 (порог 0.08): щиты FIGHT NIGHT / SCRAP CUP и флаги NULL читаются, в бою уходят в DOF и под плашки HUD.
  В кадре `start` щит FIGHT NIGHT стоял прямо за головой P2 — с 23.10 (вечер) поднят на мачте (y −2.2 → −0.4), низ щита
  над головами зоны старта; `fight_readable` прежние (P1 0.265, P2 0.12).
- Купол (23.10, вечер): изогнутые баннеры закрывали стойки каркаса («NULL LEAG|», «SEA|SON»). Теперь дуги стоят между колоннами
  (у нечётных стыков секций, `CURVED` в `league_boards.gd`), крайние уменьшены (0.84 / 0.88) и сдвинуты к центру кадра — в
  кадре 1 `null_hall_snapshot` все три «NULL LEAGUE ◯ SEASON ZERO» читаются целиком; проба OK 12/12.
- Спорт-зал (23.10, вечер): щиты спонсоров ORBIT JOINTS / NULL TV / VOLTA CORES — ряд бортов у пола задней стены под
  табло (`LAYOUT_SPORT`, плоский экран 2.2 × 1.24 м в раме, `LeagueBoards.panel()`), внутри колонн каркаса (x ±3.7, колонны
  ±5.6), свечение 0.35. `sport_snapshot` football/basketball/volleyball: все три читаются целиком, куклы и мяч перед ними видны.
- `loading_probe` зелёная; снимок лоадера — арт справа, текст слева читается (шторка-градиент).
- `garage_menu_shots` (title/quick/trophies/workshop/settings) — знамя, фото и плакаты на стенах, 0 SCRIPT ERROR.

## Открыто

- Реклама на аренах — купол, Свалка и спорт-зал (см. «Проверено»); Руины, Void, мастерская — без щитов (руины и пустота
  NULL — не место для рекламы Лиги, мастерская — гараж). Картинки щитов, баннера и флага — codex (23.10), ленты — набор.
- Экраны ТВ `tv_build` / `tv_opponent` — прежние (рисуются генератором, кадров веб-прототипа в них нет).
- Капсулы Steam нарезаны: `docs/steam/capsules/` (header 920×430, small 462×174, main 1232×706, vertical 748×896, library 600×900,
  hero 3840×1240, logo 1280×720 на прозрачности) — `python3 godot/tools/codex_art/steam_capsules.py`. Hero (23.10) больше не
  растянут. С 23.10 (днём) hero — из `docs/steam/hero_wide.jpg` (codex 2172×724, задание `hero_wide`), вписан ×1.77
  без растяжения; без этого файла — прежний запасной путь (keyart_wide ×1.32 в центре, бока — размытое зеркало).
  Для подачи 3840 пкс он мягковат (апскейл) — при случае перерисовать крупнее.
  Название юридически не проверено (`BRAND.md`).
