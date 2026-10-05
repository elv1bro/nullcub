---
name: control-feel
description: "02.10 варианты управления (тяга на голову как в JS) + темп; панель Tab, клавиши V/T; main 334137f, ждёт ручной оценки автора"
metadata:
  type: project
---

02.10 автор: в JS-игре WASD толкал голову (`moveBody(head)`), в Godot — торс; бой «не смотрится экшеном как в JS». Сделано `ControlFeel`
(`godot/scripts/core/control_feel.gd`) + панель `scenes/ui/control_feel_panel.gd` (Tab; V — вариант, T — темп): варианты ТЕЛО / ГОЛОВА / ГОЛОВА+СТОЙКА /
ГОЛОВА-ТАРАН / 60-40 / РУЛЬ, темпы СЕЙЧАС / БОДРЫЙ / ЭКШЕН / ТАРАН, 8 ползунков. Doll читает их каждый тик; по умолчанию = Tuning (гейты зелёные).
Бой ботов: СЕЙЧАС 21–36 с, ЭКШЕН 9–16 с. Документ — `docs/plan-demo/CONTROL_FEEL.md`. Коммит 334137f в main, не в origin.

**Why:** автор хочет сам пощупать варианты, а не принимать решение по числам.
**How to apply:** ждать его выбор варианта/темпа и сделать его дефолтом (Tuning + `ControlFeel` defaults); боты (EnemyBrain) считают тягу «на торс» — подправить после выбора. См. [[combat-charge]], [[keys-no-f-keys]].
