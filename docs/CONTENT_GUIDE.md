# Ragdoll Faces — гайд по добавлению контента

> **Статус:** рецепты ниже описывают *целевой* ContentRegistry (`src/content/…`).  
> Сейчас контент живёт в `src/items/`, `src/face/`, `src/campaign/`, `src/monster/` без единого реестра.  
> См. as-built в [ARCHITECTURE.md](ARCHITECTURE.md) §0 и проверку в [`AGENTS.md`](../AGENTS.md).

Пошаговые рецепты «как добавить X». Все опираются на реестры и хуки из [ARCHITECTURE.md](ARCHITECTURE.md). Общий принцип (целевой): **один элемент контента = один файл в `src/content/...` + одна строка импорта в `src/content/index.ts`**. Ядро не трогаем.

---

## Добавить новый тип урона

Пример: яд.

1. Создать `src/content/damage-types/poison.ts`:

```ts
import { content } from "../../core/registry";

content.damageTypes.register({
  id: "poison",
  name: "Ядовитый",
  color: "#7cb518",
  onApply(ctx) {
    // слабый дот: 2 урона в секунду 4 секунды, стакается до 3 раз
    ctx.world.addDot(ctx.target, { dps: 2, seconds: 4, maxStacks: 3, key: "poison" });
  },
});
```

2. Импортировать файл в `src/content/index.ts`.
3. Готово: любое оружие теперь может указать `damageType: "poison"`, любая броня — `resists: { poison: 0.5 }`. Старые предметы автоматически имеют резист 0.

---

## Добавить новый предмет (шапку, оружие, артефакт)

Пример: шляпа-цилиндр с эффектом вежливости.

1. Если нужен новый эффект — сначала создать его (см. следующий рецепт).
2. Создать `src/content/items/top-hat.ts`:

```ts
import { content } from "../../core/registry";

content.items.register({
  id: "top-hat",
  name: "Цилиндр джентльмена",
  slot: "head",
  rarity: "rare",
  physics: { massKg: 1.2, shape: { kind: "box", w: 0.25, h: 0.35 }, anchor: { x: 0, y: -0.2 } },
  stats: { def: 2 },
  effects: ["polite-bow"],   // id эффекта из реестра effects
  visual: { kind: "vector", parts: [ /* примитивы отрисовки */ ] },
});
```

3. Импортировать в `src/content/index.ts`. Предмет появится в гардеробе и на экране экипировки автоматически (UI строится по реестру).

Чек-лист баланса предмета:
- эффект меняет одну вещь и слегка (±10–20% или редкий триггер);
- сила компенсируется физикой (масса, габарит) или проклятием;
- есть смешной звук/частица — предмет должен радовать, даже когда бесполезен.

---

## Добавить новый эффект

Пример: «вежливый поклон» — после нокаута противника ваш боец кланяется и получает +5% DEF до конца раунда.

1. Создать `src/content/effects/polite-bow.ts`:

```ts
import { content } from "../../core/registry";

content.effects.register({
  id: "polite-bow",
  description: "После нокаута противника: поклон и +5% защиты до конца раунда",
  attach({ fighter, bus, world }) {
    bus.on("knockout", (e) => {
      if (e.by !== fighter) return;
      world.playPose(fighter, "bow", 1.0);
      world.addStatModifier(fighter, { def: +0.05, key: "polite-bow", untilRoundEnd: true });
    });
  },
});
```

2. Импортировать в `src/content/index.ts`, указать id в `effects` любого предмета.

Доступные триггеры — события шины (`hit`, `damageDealt`, `knockout`, `emotionStart/End`, `voiceLevel`, `tick`, `itemActivated`...). Подписки снимаются автоматически при снятии предмета.

---

## Добавить новую эмоцию

Пример: «надутые щёки».

1. Создать `src/content/emotions/puffed-cheeks.ts`:

```ts
import { content } from "../../core/registry";

content.emotions.register({
  id: "puffed-cheeks",
  name: "Надутые щёки",
  // blendshapes — вектор MediaPipe (0..1 на каждый параметр)
  detect(bs) {
    return Math.min(bs.cheekPuff, 1 - bs.jawOpen); // щёки надуты, рот закрыт
  },
  threshold: 0.6, // выше порога — событие emotionStart
});
```

2. Импортировать в `src/content/index.ts`. Эффекты предметов могут ссылаться на `"puffed-cheeks"` в `emotionStart`.

---

## Добавить новый мутатор

Пример: «Мыльная арена».

```ts
// src/content/mutators/soap.ts
import { content } from "../../core/registry";

content.mutators.register({
  id: "soap",
  name: "Мыльная арена",
  apply({ world }) { world.setFriction(0.02); world.spawnBubbles(true); },
  remove({ world }) { world.resetFriction(); world.spawnBubbles(false); },
});
```

Мутатор автоматически попадает в пул случайных мутаторов раунда и в список для чит-кодов.

---

## Добавить новую кампанию

Кампания — папка с данными, почти без кода.

1. Создать `src/content/campaigns/pirate-bay/index.ts`:

```ts
import { content } from "../../core/registry";

content.campaigns.register({
  id: "pirate-bay",
  poster: {
    title: "Требуется герой в Пиратскую бухту",
    teaser: "Оплата: рыба. Много рыбы.",
    art: "poster-pirate.png",
  },
  chapters: [
    {
      id: "ch1",
      intro: {
        panels: [
          { speaker: "player", text: "Я пришёл по объявлению.", playerFace: true },
          { speaker: "captain", text: "Ты убил моего сенсея... и съел мой бутерброд!", pose: "angry" },
        ],
      },
      battle: {
        arena: "docks",
        enemies: [{ build: ["cutlass", "bandana"], ai: "aggressive", stats: { hp: 60 } }],
        mutators: ["wind"],
      },
      outro: { panels: [{ speaker: "captain", text: "Пощади!.. У меня семеро попугаев." }] },
      reward: ["cutlass"],
    },
    // ...главы 2–7
  ],
});
```

2. Импортировать в `src/content/index.ts` — объявление само появится на доске в таверне.
3. Босс с гиммиком: в `battle` указать `gimmick: "<id эффекта>"` — гиммик пишется как обычный эффект (см. выше), только вешается на бой, а не на предмет.

---

## Добавить чит-код

```ts
// src/content/cheats/fishparty.ts
import { content } from "../../core/registry";

content.cheats.register({
  id: "fishparty",
  code: "fishparty",          // что набрать с клавиатуры
  apply({ world }) { world.enableMutator("all-weapons-fish"); },
  remove({ world }) { world.disableMutator("all-weapons-fish"); },
});
```

---

## Добавить режим игры

Регистрируется `GameModeDef`: условие победы + настройка раунда. Смотреть на `src/content/modes/sumo.ts` как на образец (появится на Этапе 4).

---

## Правила, чтобы контент не ломал игру

1. Ядро (`src/core/`) при добавлении контента не изменяется. Если не хватает события или API мира — расширяем ядро отдельным осознанным шагом, затем пишем контент.
2. Каждый эффект подчищает за собой (модификаторы со своим `key`, `remove` у мутаторов).
3. Никаких прямых обращений контента к Rapier/Pixi — только через `WorldApi`. Это гарантия, что контент переживёт смену движка/рендера и появление сети.
4. Один файл — одна вещь. Пачка предметов = пачка файлов.
5. Названия и описания сразу пишем смешными: тултип — часть фана.
