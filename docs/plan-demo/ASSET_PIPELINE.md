# Пайплайн ассетов и сцен (решение автора 27.09.2026)

**Правило 1. Все модели — настоящие 3D-меши из Blender.** Никаких примитивов Godot и самописных glTF-генераторов в игре. Модели делаются headless-скриптами Blender (`godot/tools/blender/*.py`, общие хелперы в `common.py`) и экспортируются в `godot/assets/models/**.glb`. Скрипт = исходник модели: его можно перезапустить, поправив числа. Blender 4.5 LTS стоит в `/Applications/Blender.app`.

Требования к мешам: сглаженное затенение, фаски на рёбрах (Bevel), где нужно — Subdivision; материалы Principled BSDF (цвет, шероховатость, металличность), при необходимости запечённые текстуры (`common.bake_material`). Бюджет: кукла-герой ≤ 90 000 треугольников (v3.1 — 87.8k), оружие ≤ 4 000, модуль арены ≤ 3 000. Ориентация: в Blender Z вверх, «лицо» в −Y (после экспорта с Y вверх это +Z в Godot, то есть к камере), X — вбок.

**Правило 2. Всё взаимодействие собирается сценами Godot.** Кукла, оружие, арена, площадка — это `.tscn` с полным деревом узлов (RigidBody3D, CollisionShape3D, MeshInstance3D, Generic6DOFJoint3D, StaticBody3D, свет, окружение), которые открываются и правятся в редакторе. Скрипты (`.gd`) содержат только поведение (управление, урон, камера), а не построение сцены в `_ready()`.

Сцены с большим числом узлов (кукла: 14 тел + 13 суставов) генерируются один раз builder-скриптом Godot (`godot/tools/build_*.gd`, запуск `godot --headless --path godot -s res://tools/build_<x>.gd`), который создаёт узлы, назначает `owner`, упаковывает `PackedScene` и сохраняет `.tscn`. После генерации сцена живёт как обычный файл проекта; повторный запуск builder-а перезаписывает её (правки руками в редакторе тогда теряются — поэтому правки, которые нужно сохранить, вносятся в builder).

**Правило 3. Числа баланса — только в `scripts/tuning.gd`.** Сцены не хранят массы и силы в дублирующих местах: builder читает `tuning.gd` при генерации, скрипты поведения читают autoload `Tuning`.

## Структура

```
godot/tools/blender/common.py           хелперы bpy (материалы, фаски, экспорт)
godot/tools/blender/mannequin.py        → assets/models/heroes/mannequin/<Part>.glb + mannequin.glb
godot/tools/blender/weapons.py          → assets/models/weapons/<id>.glb
godot/tools/blender/arena_kit.py        → assets/models/arena/kit.glb (модули по именам) + отдельные модули
godot/tools/build_doll_scene.gd         → scenes/doll/doll.tscn
godot/tools/build_arena_ruins.gd        → scenes/arena/ruins.tscn
godot/tools/build_weapon_scenes.gd      → scenes/weapons/weapon_<id>.tscn
godot/scenes/playground.tscn            площадка: арена + куклы + камера + окружение (собрана как сцена)
```

## Проверка

1. `Blender -b --python <script>` без ошибок, размер glb и число треугольников в пределах бюджета (скрипт печатает `common.stats()`).
2. `godot --headless --path godot --import` без ошибок.
3. Builder сохраняет `.tscn`; открытие сцены в редакторе (`godot --path godot -e`) показывает дерево узлов.
4. Скриншоты через `tests/*_snapshot.tscn` и сравнение с R14/R15/R16 глазами.
5. Гейт `tests/run_gate.sh` зелёный (кукла из сцены ведёт себя так же, как процедурная).
