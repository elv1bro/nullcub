---
name: workshop-in-garage
description: "02.10 мастерская встроена в гараж меню (без смены сцены): как устроено, зачем, что осталось"
metadata:
  node_type: memory
  type: project
  originSessionId: 564c840b-8ee7-474f-b9ef-a8b8e0f16c7f
  modified: 2026-10-02T15:07:38.346Z
---

02.10 автор: загрузка мастерской долгая — «не менять даже локацию, всё делать прямо в гараже» (выбрал «сразу целиком», не «быстро, потом глубоко»). Сделано, слито в main (мерж 61b8890), запушено в origin (43c0f04).

Как: `scenes/workshop/workshop_embed.tscn` — тот же `workshop_build.gd` без комнаты (`embedded = $Workshop отсутствует`), контроллер `scenes/menu/garage_workshop.gd` (фоновая загрузка → постановка спящей → нырок камеры → `take_camera_from` без скачка → двойной Esc → `exit_requested`), `GarageDoll.rebuild()`, `GarageStage` (bounds + невидимые коллайдеры). Проба `tests/garage_workshop_probe.tscn` (32 проверки), кадры `tests/garage_workshop_shots.tscn`. Подробно — `docs/plan-demo/MENU_GARAGE.md` («Мастерская внутри гаража»).

**Why:** бой 2.5D зашит на плоскость z = 0 (`ArmAssist.mouse_on_plane`, `DynamicCamera.plane_z`), а стенд гаража стоит у стены (z = −1.2) — поэтому испытание идёт на `TestSpot` z = 0 перед стендом, а не на самом стенде.

**How to apply:** отдельная `workshop_build.tscn` оставлена (тестовое меню, `workshop_probe`); правя `workshop_build.gd`, гонять и `workshop_probe` (226), и `garage_workshop_probe`. Открыто: коллайдеры у пропсов гаража (кукла в бою проходит сквозь ковёр/ящики), постановка 0.7 с одним куском на титуле, N0 не комментирует сборку. См. [[godot-test-workflow]].
