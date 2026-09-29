# Звуки ударов (SfxDirector) — источники и лицензии

Все файлы — OGG Vorbis, моно, 44.1 кГц. Их собирает `tools/audio/gen_hitfx_audio.py`: он обрезает тишину и хвост, нормализует пик до −1 dBFS и при необходимости фильтрует звук. Сцену со слоями собирает `tools/audio/build_sfx_director_scene.gd`. Папка — это слой SfxDirector (`docs/plan-demo/HIT_FX.md` §2.5).

Внешние сэмплы взяты из старого TS-проекта `public/sounds/`. Лицензии описаны там в `combat/README.txt` и `sfx/README.txt`. Все они CC0 (public domain), поэтому атрибуция не обязательна, но мы её указываем.

| Файлы | Источник | Автор | Лицензия | Обработка |
|---|---|---|---|---|
| `punch/qubodup_punch_01…05.ogg` | Punch — https://opengameart.org/content/punch | Iwan Gabovitch (qubodup) | CC0 | обрезка до 0.32 с |
| `punch/hit_28.ogg`, `punch/hit_34.ogg` | 37 hits/punches — https://opengameart.org/content/37-hitspunches (hit-28, hit-34) | Independent.nu | CC0 | обрезка до 0.3 с |
| `thud/hit_19_low.ogg`, `thud/hit_35_low.ogg` | 37 hits/punches (hit-19, hit-35) | Independent.nu | CC0 | low-pass 380 Гц, обрезка |
| `ko/ko_01.ogg`, `ko/ko_02.ogg` | `combat/ko-01.ogg`, `ko-02.ogg` TS-проекта. Это побайтовые копии hit-37 (Independent.nu) и qubodupPunch05 (qubodup) | Independent.nu, qubodup | CC0 | обрезка до 0.42 с |
| `zap_low/zap_1.ogg`, `zap_2.ogg` | Digital Audio — https://kenney.nl/assets/digital-audio | Kenney | CC0 | обрезка до 0.85 с (питч 0.5 задаёт директор) |
| `whistle/phaser_up_1.ogg`, `phaser_up_3.ogg` | Digital Audio — https://kenney.nl/assets/digital-audio | Kenney | CC0 | обрезка (питч 0.6 задаёт директор) |
| `gong/fight_gong.ogg` | boxing_matchbell.wav — https://opengameart.org/content/boxing-ring-0 | Umplix | CC0 | нормализация |
| `crowd_cheer/crowd_cheer.ogg` | «Well Done» — https://opengameart.org/content/well-done | qubodup | CC0 | обрезка до 2.6 с, мягкая компрессия, фейд |

Синтезированные звуки (numpy + scipy, seed 29, `tools/audio/gen_hitfx_audio.py`) сделаны для этого проекта. Лицензия CC0.

| Файлы | Что это |
|---|---|
| `tok/wood_tok_01…08.ogg` | деревянный стук: шумовой импульс проходит через резонаторы бруска (1 : 2.76 : 5.40 : 8.93) |
| `crack/wood_crack_01…04.ogg` | треск дерева: снап + микрощелчки щепок + резонанс детали |
| `creak/fiber_creak_01…02.ogg` | скрип волокна (stick-slip через резонаторы) с треском в конце |
| `thud/thud_01…03.ogg` | низкий тумп: синус 120 → 46 Гц + шум ниже 300 Гц |
| `boom/boom_01…02.ogg` | бум крита: суб-провал 90 → 32 Гц, средний удар, тёмный хвост |
| `whoosh/whoosh_01…04.ogg` | «вух» отлёта: шум в полосе, которая скользит вверх и вниз |
| `inhale/inhale_rev_01…02.ogg` | вдох-реверс: хвост треска, развёрнутый назад, 95 мс; обрывается на пике |
| `crash/crash_01…02.ogg` | удар о стену в крит-полёте: тумп + треск + стук щепок |
| `shatter/shatter_01…02.ogg` | кукла рассыпается: снап + детали стучат об пол |
| `crowd_oof/crowd_oof_01…02.ogg` | «ох» толпы: 24–28 голосов, тон падает, форманты «о». Файл `sfx/crowd-oof.ogg` из TS-проекта не подошёл: он битый, там тишина −91 dB |

Не используются: `sfx/victory.ogg`, `sfx/defeat.ogg` (Spring Enterprises, CC0) и музыка.
