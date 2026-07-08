# Каталог hit-эффектов (MK-style)

Живой документ: что уже есть, что в очереди, как добавлять новое.  
Эффекты включаются настройкой **«Эффекты ударов»** в меню.

---

## Статусы

| Статус | Значение |
|--------|----------|
| ✅ **Есть** | Работает в игре |
| 🚧 **Выбрано** | В текущем MK-пакете, реализовано |
| 📋 **В очереди** | Описано, можно взять позже |

---

## MK-пакет (реализовано)

| # | ID | Название | Что делает | Порог | Код |
|---|-----|----------|------------|-------|-----|
| 3 | `hit-stop` | **Hit Stop** | Физика замирает на ~55 ms | урон ≥ 30 | `dispatch.ts` → `timeSegments` → `useHitEffectClock.ts` |
| 4 | `screen-shake` | **Screen Shake** | Тряска камеры | любой удар | `drawScreenFx.sampleShake` + `Viewport.tsx` |
| 5 | `flash-frame` | **Flash Frame** | Цветная вспышка экрана | любой удар | `drawScreenFx.drawScreenFlash` |
| 10 | `slow-mo` | **Slow-Mo Hit** | timeScale ≈ 0.38 на ~300 ms после hit-stop | урон ≥ 30 | `dispatch.ts` + `useHitEffectClock.ts` |
| 12 | `finisher-cam` | **KO Finisher Cam** | Zoom на победителя + vignette + slow-mo | нокаут | `dispatchKnockoutEffects` + `Viewport` + `drawFinisherVignette` |
| 17 | `ground-shockwave` | **Ground Shockwave** | Эллипс-кольцо по полу | урон ≥ 15, y > 82% арены | `drawGroundShockwaves` |
| 18 | `combo-counter` | **Combo Counter** | «×N КОМБО!» сверху | 2+ удара за 900 ms | `comboAnnouncer.updateCombo` |
| 19 | `announcer` | **Announcer Text** | BRUTAL! / FATALITY! / … | комбо 3+ или heavy/KO | `comboAnnouncer.spawnAnnouncer` |

### Пороги урона

```
лёгкий:   damage < 15
средний:  15 ≤ damage < 30
тяжёлый:  damage ≥ 30
нокаут:   HP → 0
```

---

## Уже было до MK-пакета

| ID | Название | Статус | Код |
|----|----------|--------|-----|
| `impact-ring` | Impact Ring + sparks | ✅ | `src/lib/hitVfx.ts` |
| `damage-popup` | −♥ попапы | ✅ | `src/lib/hitPopups.ts` |
| `blood-splatter` | Кровь (цвет жертвы) | ✅ | `src/lib/useBloodyParticules.ts` |
| `body-flash` | Вспышка тела атакующим цветом | ✅ | `src/lib/handleImpacts.ts` |
| `banter-quips` | Фразы у точки удара | ✅ | `src/lib/banterQuips.ts` |

---

## В очереди (можно добавить позже)

| # | ID | Название | Описание | Сложность | Идея реализации |
|---|-----|----------|----------|-----------|-----------------|
| 1 | `impact-ring+` | Impact Ring (усиленный) | Двойное кольцо, больше искр | 🟢 | расширить `hitVfx.ts` |
| 2 | `spark-shower` | Spark Shower | 20–40 частиц с гравитацией | 🟢 | `src/lib/hitEffects/sparks.ts` |
| 6 | `blood-wall` | Blood on Wall | Брызги остаются на стенах | 🟡 | декали в overlay, точка + нормаль стены |
| 7 | `body-flash+` | Body Flash (усиленный) | Пульс по всем частям тела | 🟢 | `handleImpacts.ts` |
| 8 | `crack-overlay` | Crack Overlay | «Трещины» при ударе в голову | 🟡 | SVG/Canvas overlay на canvas |
| 9 | `ragdoll-wobble` | Ragdoll Wobble | Желе-деформация жертвы 0.3 s | 🟡 | scale тел через render или временный constraint |
| 11 | `zoom-punch` | Zoom Punch | Лёгкий zoom к точке удара (не только KO) | 🟡 | временный offset bounds в `Viewport` |
| 13 | `xray-flash` | X-Ray Flash | Силуэт скелета на 0.2 s | 🔴 | отрисовка wireframe composite |
| 14 | `lightning-arc` | Lightning Arc | Молния между бойцами | 🟡 | Bezier + flicker в `drawScreenFx` |
| 15 | `fire-ignite` | Fire Ignite | Огонь на частях + DoT | 🟡 | контент-эффект + частицы |
| 16 | `ice-shatter` | Ice Shatter | Лёд + замедление физики | 🟡 | tint + `timeSegments` на жертве |
| 20 | `stun-stars` | Stun Stars | Звёзды над головой после хэда | 🟢 | orbit particles в overlay |

---

## Как добавить новый эффект

### Быстрый путь (сейчас)

1. **Данные** — тип в `src/lib/hitEffects/store.ts`, спавн в `dispatch.ts` (или отдельный `spawnXxx.ts`).
2. **Триггер** — `useHealth.ts` уже вызывает `dispatchHitEffects` / `dispatchKnockoutEffects`.
3. **Камера** — `Viewport.tsx` (`beforeRender`): shake, zoom, finisher.
4. **Отрисовка** — `useBattleOverlay.ts` (`afterRender`): flash, shockwave, UI-текст.
5. **Время** — `useHitEffectClock.ts`: `engine.timing.timeScale`.
6. **Тест** — `*.test.ts` рядом, если есть логика порогов/комбо.

### Путь через контент (будущее)

Когда появится `src/content/effects/`:

```ts
content.hitEffects.register({
  id: "lightning-arc",
  minDamage: 25,
  attach({ bus }) {
    bus.on("damageDealt", (e) => { /* spawn */ });
  },
});
```

Ядро не трогаем — только событие `hit` / `damageDealt` и `WorldApi`.

---

## Настройки игрока

| Настройка | Влияет на |
|-----------|-----------|
| **Эффекты ударов** | весь MK-пак + bursts + blood flash |
| **Фразы при ударах** | banter (независимо) |
| **Без цензуры (18+)** | только текст banter |

---

## Файлы MK-пакета

```
src/lib/hitEffects/
  store.ts           — состояние (shake, flash, segments, combo…)
  dispatch.ts        — когда что включать
  comboAnnouncer.ts  — комбо + тексты комментатора RU/EN
  drawScreenFx.ts    — рисование + камера
  useHitEffectClock.ts — hit-stop / slow-mo
  index.ts
```

Связки: `useHealth.ts` → `LeveL1.tsx` → `Viewport.tsx` + `useBattleOverlay.ts`.

---

## Changelog

- **2026-07-05** — MK-пакет: #3, #4, #5, #10, #12, #17, #18, #19
