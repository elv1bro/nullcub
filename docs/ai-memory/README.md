# Память ИИ-сессий о проекте (снимок 30.09.2026)

Копия файловой памяти Claude Code с машины автора (`~/.claude/projects/-Users-eliseyvrublevskiy-Projects-ragdoll-faces/memory/`), чтобы облачная сессия продолжила с тем же контекстом. `MEMORY.md` — оглавление, остальные файлы — по одному факту: решения автора, состояние работ, договорённости между сессиями, подводные камни.

С чего начинать:
- **Что это за игра сейчас:** `concept-v2-roguelite.md` → `docs/plan-demo/CONCEPT_V2.md`, `LORE.md`.
- **Вид куклы, детали, крафт, мастерская:** `body-kit-v2.md` → `docs/plan-demo/BODY_KIT.md`, покраска → `docs/plan-demo/BODY_PAINT.md`.
- **Как гонять Godot и пробы:** `godot-test-workflow.md`, `godot/README.md`, `AGENTS.md` (веб-часть).
- **Бой и эффекты:** `docs/plan-demo/HIT_FX.md`, производительность — `docs/plan-demo/PERF_AUDIT.md`.
- **Вес пропсов, броски, взрывы:** `prop-heft-throw.md`.

Что на локальной машине было, а в облаке не нужно:
- Обёртка блокировки `godot_locked.py` в `/private/tmp/...` — нужна была, пока в одном чекауте параллельно работали 3–5 сессий. Одной сессии в облаке достаточно запускать `godot` напрямую.
- `gtimeout … /usr/bin/arch -arm64` — особенность Mac автора (Rosetta).
- Blender (`/Applications/Blender.app`) — для пересборки деталей кита (`godot/tools/blender/body_kit.py`); сами glb уже в репозитории.
- Кэш импорта `godot/.godot/` не в git: первый запуск — `godot --headless --path godot --import` (несколько минут).

Незакончено на момент снимка:
- ветки `claude/xenodochial-hawking-2dce18` (фикс двойного KO — победителем называли мёртвую куклу; ждёт решения автора о переносе в main) и `claude/youthful-albattani-0b5cdb` (общие текстуры Свалки и правки импорта моделей, `ASSET_PIPELINE.md`) — закоммичены как были, в main не слиты;
- решения автора: палитра красок кита (сейчас приглушённая: бордовый/бирюзовый/горчичный/оливковый — вернуть яркую?), стартовые числа hit_mult (шипы ×1.3 и т. д.);
- префикс `_md_` для приватных хелперов ModularDoll (страховка от коллизий имён с Doll).
