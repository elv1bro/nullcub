# 03 — Проект Godot

Вход: ничего, можно делать параллельно с 01–02. Выход: пустой, но запускающийся проект с правильной физикой и структурой.

## Шаги

1. Godot 4.x последний стабильный (4.6+, где Jolt по умолчанию). Записать точную версию сюда в `## Итог`.
2. Папка `godot/` в корне репозитория ragdoll-faces (общий git, коммиты рядом с TS-кодом). `project.godot`, имя проекта «Ragdoll Master Demo».
3. Настройки проекта:
   - Physics → 3D → Physics Engine: **Jolt Physics**.
   - Physics ticks per second: 60. Max physics steps per frame: 8.
   - Rendering: Forward+ для десктопа; Compatibility-профиль отложить.
   - Display: 1920×1080, stretch mode `canvas_items`, aspect `keep`.
4. Структура папок:
   ```
   godot/
     assets/models, assets/textures, assets/audio, assets/fonts
     scenes/doll, scenes/arena, scenes/weapons, scenes/ui, scenes/fx
     scripts/tuning.gd       ← все числа баланса, единственный источник
     scripts/core/           ← бой, урон, таймер (без UI)
     scripts/input/          ← схемы управления игроков
     tests/                  ← gdUnit4 или встроенные сцены-проверки
   ```
5. `tuning.gd` как autoload с константами, перенесёнными из TS-проекта: время боя 90 с, sudden death шаг 25 % каждые 10 с, жёсткий тайм-аут 180 с, HP 1000, spawn grace 0.7 с, рывок ×1.8 на 2 с с перезарядкой 10 с. Источник: `src/lib/battleTuning.ts`, `src/lib/combat.ts`.
6. InputMap: `p1_left/right/up/down/dash/flip`, то же для p2–p4; клавиатура WASD + стрелки, геймпады 0–3.
7. Тестовая сцена `scenes/sandbox.tscn`: пол, свет, камера сбоку, одна `RigidBody3D`-сфера, которая падает. Запуск F5 показывает падение.
8. `.gitignore` для `.godot/`, `export/`.

## Критерий готовности

Проект открывается, F5 показывает падающую сферу на Jolt, `tuning.gd` подключён как autoload, версия Godot записана.

## Итог

**27.09.2026 — готово.** Godot **4.7.2.stable** (`/usr/local/bin/godot`), проект в `godot/`, физика Jolt (подтверждено в отчёте гейта: `physics_engine: Jolt Physics`), 60 тиков/с, Forward+, 1920×1080 canvas_items/keep.

- `scripts/tuning.gd` — autoload с числами из TS-проекта (90 с, sudden death +25 %/10 с, 180 с, HP 1000, grace 0.7 с, рывок ×1.8/2 с/10 с) плюс параметры рэгдолла (см. 04).
- `scripts/input/input_setup.gd` — autoload, регистрирует `p1..p4_{left,right,up,down,dash,flip}` в InputMap кодом: P1 WASD+Shift+Space, P2 стрелки+Ctrl+Enter, геймпады 0–3.
- `scenes/sandbox.tscn` — пол, свет, камера, падающая сфера.
- Headless-импорт: `godot --headless --path godot --import`. Проверки без окна: `godot --headless --path godot --fixed-fps 60 res://tests/<сцена>.tscn -- "k=..,c=..,f=..,tmax=.."`. `--fixed-fps 60` даёт фиксированный шаг быстрее реального времени (33 с симуляции за 4 с).
- Особенность: до скрипта доходит только **первый** аргумент после `--`, поэтому параметры передаются одной строкой `k=20,c=2,f=6,tmax=30`.
- Скриншоты из CLI требуют окна: `godot --path godot --resolution 1280x720 res://tests/snapshot.tscn` (окно открывается на 2–3 с и закрывается само).
