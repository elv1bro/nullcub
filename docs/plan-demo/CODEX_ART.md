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

## Проверено

- `loading_probe` зелёная; снимок лоадера — арт справа, текст слева читается (шторка-градиент).
- `garage_menu_shots` (title/quick/trophies/workshop/settings) — знамя, фото и плакаты на стенах, 0 SCRIPT ERROR.

## Открыто

- Арт для арен (рекламные щиты Лиги в куполе) и экраны телевизора гаража (`textures/garage/tv/`) — пока прежние.
- Страница магазина: размеры капсул Steam (460×215, 616×353, 231×87, 600×900, 3840×1240) нарезать из `docs/steam/` при подаче.
