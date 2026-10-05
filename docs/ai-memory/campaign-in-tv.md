---
name: campaign-in-tv
description: 02.10 кампания «История» перенесена в эфир телевизора гаража (без смены сцены): архитектура, почему бой не в SubViewport, что осталось
metadata:
  type: project
---

02.10 автор: «дизайн кампании перестроить как в телек, когда влетаем; желательно не переключать локацию, всё показывать там и красиво». Сделано (мерж a5daf1b в main; в origin на момент записи **не запушено**).

Как: `scenes/menu/garage_campaign.gd` (`GarageCampaign` — нырок в ТВ, сетка → бой → итоги → мастерская, сохранение), `campaign_tv_ui.gd` (экраны эфира в стиле карточки ТВ: LIVE, бордовый градиент, косые плашки `BcStyle`, бегущая строка), `tv_overlay.gdshader` (кинескоп поверх), `doll_portrait.gd` (портреты бойцов рендером в рантайме; первый рендер за сессию — прогревочный). Мастерская между боями — встроенная (`GarageWorkshop.open_campaign`, см. [[workshop-in-garage]]). Проба `tests/garage_campaign_probe.tscn` (50 проверок, настоящий бой ботов), кадры — `docs/plan-demo/img/menu-garage/v4-campaign/`.

**Why не SubViewport с отдельным миром для боя:** `hit_fx_director`, `crit_cinematic`, `fx_clock` кладут узлы под `current_scene`/root — в чужой мир они бы не попали. Поэтому бой ставится ребёнком гаража в тот же мир, а комната гаража прячется (`GarageMenu.set_world_visible`, вместе с `WorldEnvironment` и эфиром на ТВ).

**How to apply:** отдельная `scenes/campaign/campaign.tscn` + `campaign_flow.gd` оставлены (клавиша 9, `campaign_probe`) — правила дублируются в `GarageCampaign`, при правке правил менять оба. Открыто: догрузка купола заранее, звук эфира (щелчок канала), коллайдеры гаражных пропсов.
