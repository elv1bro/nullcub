import {
  Bodies,
  Body,
  Composite,
  Constraint,
  Engine,
  Events,
  Vector,
  type IEventCollision,
} from "matter-js";

/** Свободное падение: буквы валятся и кувыркаются. */
const FALL_MS = 950;
/** Затем встают в строку — иначе логотип остаётся кучей. */
const SNAP_MS = 380;
/** Когда на логотип падает первый боец. */
const DOLL_MS = 1100;
/** Пауза между бойцами: сыплются очередью, а не одной кучей. */
const DOLL_GAP_MS = 50;
/** Сколько любуемся кучей после последнего бойца. */
const HOLD_MS = 650;
/** Наклон бойца на спавне, рад: падает боком, а не солдатиком. */
const DOLL_TILT = 2.1;
/** Не чаще, чем раз в столько мс, шлепок озвучивается. */
const THUD_GAP_MS = 90;
/** Через столько боец в режиме лоадера улетает наверх и падает заново. */
const DOLL_LIFE_MS = 2600;
/** Телефон не тянет полную толпу, режем её вдвое. */
const NARROW_W = 640;

export const SPLASH_FADE_MS = 420;
export const SPLASH_DOLL_COUNT = 40;
/** Лоадер живёт доли секунды, толпа там только мешала бы. */
export const LOADER_DOLL_COUNT = 16;

const DOLL_COLORS = [
  "#f87171",
  "#fbbf24",
  "#a3e635",
  "#34d399",
  "#22d3ee",
  "#60a5fa",
  "#a78bfa",
  "#f472b6",
  "#fb923c",
  "#e2e8f0",
];

export interface SplashWord {
  text: string;
  accent: boolean;
}

export interface SplashSceneOptions {
  canvas: HTMLCanvasElement;
  /** Слова логотипа: `accent` красится цветом темы, остальное белым. */
  words: SplashWord[];
  accentColor: string;
  dollCount?: number;
  /**
   * Фиксированный логический размер (CSS-пиксели). Для рекламного рендера /
   * записи: не трогаем `window` и не меняем `canvas.style`.
   */
  viewSize?: { w: number; h: number };
  /** Лоадер: логотип уже собран, падение букв показывать некогда. */
  assembled?: boolean;
  /** Лоадер: бойцы сыплются, пока сцену не остановят снаружи. */
  loop?: boolean;
  /**
   * Заставка: после сборки букв ждём `beginRain()` вместо автостарта дождя
   * по таймеру `DOLL_MS`.
   */
  waitForTap?: boolean;
  /**
   * Шлепок о логотип: сила удара и панорама от -1 до 1. Сцена не лезет в аудио
   * сама — решать, звучать ли, это дело вызывающего.
   */
  onThud?: (damage: number, pan: number) => void;
  /** Логотип собран — можно показать «Нажми, чтобы начать». */
  onAwaitingTap?: () => void;
  /** Не вызывается в режиме `loop`. */
  onDone?: () => void;
  /**
   * Остановить rAF после onDone. Для рекламного hold поставь `false` —
   * сцена продолжает сыпать бойцов, пока снаружи не вызовут `stop()`.
   * @default true
   */
  endOnDone?: boolean;
}

export interface SplashScene {
  start: () => Promise<void>;
  /** Запускает дождь бойцов (после тапа на заставке). */
  beginRain: () => void;
  /** Сразу завершает сцену (второй тап во время дождя). */
  finishNow: () => void;
  stop: () => void;
}

interface Letter {
  char: string;
  body: Body;
  accent: boolean;
  targetX: number;
  targetY: number;
  /** Цвет бойца, который первым (или последним) стукнул букву. */
  paint: string | null;
  /** Статичная опора после сборки логотипа — по ней ловим касания. */
  platform: Body | null;
}

interface Spark {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
  color: string;
}

interface Doll {
  bodies: Body[];
  joints: Constraint[];
  head: Body;
  headRadius: number;
  limbs: { body: Body; w: number; h: number }[];
  color: string;
  landed: boolean;
  spawnAt: number;
}

function easeOutBack(x: number): number {
  const c1 = 1.7;
  const c3 = c1 + 1;
  return 1 + c3 * (x - 1) ** 3 + c1 * (x - 1) ** 2;
}

/** Тряпичный боец из нескольких тел: падает на логотип и обмякает. */
function createDoll(x: number, y: number, scale: number, color: string): Doll {
  const group = Body.nextGroup(true);
  const part = (px: number, py: number, w: number, h: number) =>
    Bodies.rectangle(px, py, w, h, {
      collisionFilter: { group },
      chamfer: { radius: Math.min(w, h) * 0.4 },
      friction: 0.6,
      frictionAir: 0.02,
    });

  const head = Bodies.circle(x, y, scale * 0.5, {
    collisionFilter: { group },
    friction: 0.6,
    frictionAir: 0.02,
  });
  const torso = part(x, y + scale * 1.15, scale * 0.7, scale * 1.4);
  const armL = part(x - scale * 0.7, y + scale * 1.0, scale * 0.32, scale * 1.1);
  const armR = part(x + scale * 0.7, y + scale * 1.0, scale * 0.32, scale * 1.1);
  const legL = part(x - scale * 0.28, y + scale * 2.4, scale * 0.36, scale * 1.3);
  const legR = part(x + scale * 0.28, y + scale * 2.4, scale * 0.36, scale * 1.3);

  const joint = (a: Body, b: Body, ax: number, ay: number, bx: number, by: number) =>
    Constraint.create({
      bodyA: a,
      bodyB: b,
      pointA: { x: ax, y: ay },
      pointB: { x: bx, y: by },
      stiffness: 0.55,
      damping: 0.1,
      length: 0,
    });

  const bodies = [head, torso, armL, armR, legL, legR];
  // Размеры держим отдельно: у скруглённого прямоугольника вершин больше
  // четырёх, по ним конечность не нарисуешь.
  const limbs = [
    { body: torso, w: scale * 0.7, h: scale * 1.4 },
    { body: armL, w: scale * 0.32, h: scale * 1.1 },
    { body: armR, w: scale * 0.32, h: scale * 1.1 },
    { body: legL, w: scale * 0.36, h: scale * 1.3 },
    { body: legR, w: scale * 0.36, h: scale * 1.3 },
  ];
  const joints = [
    joint(head, torso, 0, scale * 0.4, 0, -scale * 0.7),
    joint(torso, armL, -scale * 0.35, -scale * 0.5, 0, -scale * 0.5),
    joint(torso, armR, scale * 0.35, -scale * 0.5, 0, -scale * 0.5),
    joint(torso, legL, -scale * 0.2, scale * 0.7, 0, -scale * 0.6),
    joint(torso, legR, scale * 0.2, scale * 0.7, 0, -scale * 0.6),
  ];

  // Цвет вешаем на тело: collisionStart отдаёт только Body, без ссылки на Doll.
  for (const body of bodies) {
    (body as Body & { splashDollColor?: string }).splashDollColor = color;
  }

  return {
    bodies,
    joints,
    head,
    headRadius: scale * 0.5,
    limbs,
    color,
    landed: false,
    spawnAt: 0,
  };
}

/**
 * Буквы названия падают тряпичными телами на том же движке, что и бой, встают
 * в логотип, и сверху на него сыплется разноцветная толпа бойцов.
 *
 * Сцена ничего не знает про React и про звук: рисует в переданный канвас и
 * дёргает колбэки. Отсюда живут и заставка запуска, и лоадер между экранами.
 */
export function createSplashScene(opts: SplashSceneOptions): SplashScene {
  const {
    canvas,
    words,
    accentColor,
    assembled = false,
    loop = false,
    waitForTap = false,
    endOnDone = true,
  } = opts;
  const ctx = canvas.getContext("2d");

  let raf = 0;
  let disposed = false;
  let rainArmed = !waitForTap || assembled || loop;
  let rainStartedAt: number | null = null;
  let awaitingTapNotified = false;
  let finishRequested = false;
  let doneNotified = false;
  const engine = Engine.create({ gravity: { x: 0, y: 2.4, scale: 0.001 } });
  const letters: Letter[] = [];
  const sparks: Spark[] = [];

  const plain = words
    .map((w) => w.text)
    .join(" ")
    .toUpperCase();

  const burst = (
    x: number,
    y: number,
    count: number,
    power: number,
    color: string = accentColor,
  ) => {
    for (let i = 0; i < count; i += 1) {
      const a = -Math.PI / 2 + (Math.random() - 0.5) * Math.PI * 1.1;
      const speed = power * (0.4 + Math.random() * 0.9);
      sparks.push({
        x,
        y,
        vx: Math.cos(a) * speed,
        vy: Math.sin(a) * speed,
        life: 1,
        color,
      });
    }
  };

  const start = async () => {
    if (!ctx || disposed) return;

    // Ждём именно Unbounded: без него буквы померяются запасным шрифтом и
    // строка разъедется. document.fonts.ready ждать нельзя — он висит, пока не
    // догрузятся все сабсеты страницы.
    await Promise.race([
      document.fonts?.load("800 96px Unbounded", plain).catch(() => undefined) ??
        Promise.resolve(),
      new Promise((resolve) => setTimeout(resolve, 400)),
    ]);
    if (disposed) return;

    const dpr = opts.viewSize ? 1 : Math.min(2, window.devicePixelRatio || 1);
    const cssW = opts.viewSize?.w ?? window.innerWidth;
    const cssH = opts.viewSize?.h ?? window.innerHeight;
    const nextW = Math.floor(cssW * dpr);
    const nextH = Math.floor(cssH * dpr);
    // Не трогаем width/height если размер тот же — иначе рвётся captureStream.
    if (canvas.width !== nextW || canvas.height !== nextH) {
      canvas.width = nextW;
      canvas.height = nextH;
    }
    if (!opts.viewSize) {
      canvas.style.width = `${cssW}px`;
      canvas.style.height = `${cssH}px`;
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const wanted = opts.dollCount ?? SPLASH_DOLL_COUNT;
    const dollCount = Math.max(4, Math.round(cssW < NARROW_W ? wanted / 2 : wanted));
    /** Задержка до первого бойца после старта дождя (или от начала сцены). */
    const dollStartMs = waitForTap && !loop ? 80 : assembled ? 120 : DOLL_MS;
    const rainHoldMs = dollStartMs + (dollCount - 1) * DOLL_GAP_MS + HOLD_MS;

    // Кегль подбираем так, чтобы строка влезла в 80% ширины экрана.
    let size = Math.min(104, Math.floor(cssH * 0.17));
    const fontAt = (px: number) => `800 ${px}px Unbounded, Rubik, sans-serif`;
    ctx.font = fontAt(size);
    const maxW = cssW * 0.8;
    const measured = ctx.measureText(plain).width;
    if (measured > maxW) size = Math.max(20, Math.floor((size * maxW) / measured));
    ctx.font = fontAt(size);

    const spaceW = ctx.measureText(" ").width;
    const chars: { char: string; accent: boolean; width: number }[] = [];
    words.forEach((word, wi) => {
      for (const char of word.text.toUpperCase()) {
        chars.push({ char, accent: word.accent, width: ctx.measureText(char).width });
      }
      if (wi < words.length - 1) {
        chars.push({ char: " ", accent: false, width: spaceW });
      }
    });

    const totalW = chars.reduce((sum, c) => sum + c.width, 0);
    const restY = cssH * 0.5;
    const boxH = size * 0.94;
    const floorY = restY + boxH / 2;
    let cursor = (cssW - totalW) / 2;

    for (const c of chars) {
      const targetX = cursor + c.width / 2;
      cursor += c.width;
      if (c.char === " ") continue;

      const body = Bodies.rectangle(
        assembled ? targetX : targetX + (Math.random() - 0.5) * 64,
        assembled ? restY : -140 - Math.random() * 220,
        Math.max(8, c.width * 0.86),
        boxH,
        {
          restitution: 0.3,
          friction: 0.45,
          frictionAir: 0.01,
          angle: assembled ? 0 : (Math.random() - 0.5) * 1.8,
        },
      );
      if (!assembled) Body.setAngularVelocity(body, (Math.random() - 0.5) * 0.3);
      Composite.add(engine.world, body);
      letters.push({
        char: c.char,
        body,
        accent: c.accent,
        targetX,
        targetY: restY,
        paint: null,
        platform: null,
      });
    }

    Composite.add(engine.world, [
      Bodies.rectangle(cssW / 2, floorY + 30, cssW * 1.6, 60, { isStatic: true }),
      Bodies.rectangle(-30, cssH / 2, 60, cssH * 4, { isStatic: true }),
      Bodies.rectangle(cssW + 30, cssH / 2, 60, cssH * 4, { isStatic: true }),
    ]);

    const startedAt = performance.now();
    // Шагаем по реальному времени: на слабом устройстве кадров мало, и по
    // кадрам буквы не успели бы упасть до конца заставки.
    let lastFrame = startedAt;
    let accumulator = 0;
    const STEP = 1000 / 60;
    /** Поза каждой буквы на момент, когда физика заканчивается. */
    let frozen: { x: number; y: number; angle: number }[] | null = null;
    const landed = new Set<number>();
    const dolls: Doll[] = [];
    let lastThudAt = -Infinity;

    // Тест: какой цвет бойца коснулся буквы — таким цветом она и красится.
    // Последний удар побеждает, чтобы в лоадере буквы «жили».
    const onLetterHit = (event: IEventCollision<Engine>) => {
      for (const pair of event.pairs) {
        const a = pair.bodyA as Body & {
          splashLetter?: Letter;
          splashDollColor?: string;
        };
        const b = pair.bodyB as Body & {
          splashLetter?: Letter;
          splashDollColor?: string;
        };
        const letter = a.splashLetter ?? b.splashLetter;
        const color = a.splashDollColor ?? b.splashDollColor;
        if (!letter || !color) continue;
        letter.paint = color;
        burst(letter.targetX, letter.targetY - boxH * 0.35, 5, 2.6, color);
      }
    };
    Events.on(engine, "collisionStart", onLetterHit);

    /** Полсотни шлепков подряд слились бы в кашу, поэтому звучит не каждый. */
    const thud = (x: number, damage: number) => {
      const at = performance.now();
      if (at - lastThudAt < THUD_GAP_MS) return;
      lastThudAt = at;
      opts.onThud?.(damage, (x / cssW) * 2 - 1);
    };

    const spawnPoint = () => ({
      x: cssW / 2 + (Math.random() - 0.5) * totalW * 0.9,
      y: -size * (1.4 + Math.random() * 1.2),
    });

    /** Роняем боком и с вращением: на ноги приземляться скучно. */
    const toss = (doll: Doll, at: number) => {
      for (const body of doll.bodies) {
        Body.setVelocity(body, { x: (Math.random() - 0.5) * 4, y: 7 });
        Body.setAngularVelocity(body, (Math.random() - 0.5) * 0.4);
      }
      doll.landed = false;
      doll.spawnAt = at;
    };

    const spawnDoll = (i: number, at: number) => {
      const { x, y } = spawnPoint();
      const doll = createDoll(
        x,
        y,
        size * (0.28 + Math.random() * 0.14),
        DOLL_COLORS[i % DOLL_COLORS.length] ?? accentColor,
      );
      // Body.rotate крутит тело вокруг своего центра, так что заваливаем бойца
      // целиком, перенося каждую часть вокруг точки спавна.
      const tilt = DOLL_TILT * (Math.random() < 0.5 ? -1 : 1) * (0.6 + Math.random());
      for (const body of doll.bodies) {
        Body.setPosition(body, Vector.rotateAbout(body.position, tilt, { x, y }));
        Body.rotate(body, tilt);
      }
      toss(doll, at);
      Composite.add(engine.world, [...doll.bodies, ...doll.joints]);
      dolls.push(doll);
    };

    /** В лоадере тела не плодим: отлежавшего своё уносим обратно наверх. */
    const recycle = (doll: Doll, at: number) => {
      const { x, y } = spawnPoint();
      const dx = x - doll.head.position.x;
      const dy = y - doll.head.position.y;
      for (const body of doll.bodies) {
        Body.setPosition(body, { x: body.position.x + dx, y: body.position.y + dy });
      }
      toss(doll, at);
    };

    const frame = () => {
      if (disposed) return;
      const now = performance.now();
      const elapsed = now - startedAt;

      accumulator += Math.min(120, now - lastFrame);
      lastFrame = now;
      for (let steps = 0; accumulator >= STEP && steps < 8; steps += 1) {
        Engine.update(engine, STEP);
        accumulator -= STEP;
      }

      // Искры в момент, когда буква впервые коснулась пола.
      if (!frozen) {
        letters.forEach((letter, i) => {
          if (landed.has(i)) return;
          if (letter.body.position.y + boxH / 2 < floorY - 4) return;
          landed.add(i);
          burst(letter.body.position.x, floorY, 7, 3.4);
          if (landed.size === 1) thud(letter.body.position.x, 14);
        });
      }

      if ((assembled || elapsed >= FALL_MS) && !frozen) {
        frozen = letters.map((l) => ({
          x: l.body.position.x,
          y: l.body.position.y,
          angle: l.body.angle,
        }));
        // Дальше буквы — декорация и опора: бойцы должны на них падать.
        for (const l of letters) {
          Composite.remove(engine.world, l.body);
          const platform = Bodies.rectangle(
            l.targetX,
            l.targetY,
            Math.max(8, size * 0.55),
            boxH,
            { isStatic: true, label: "splash-letter" },
          );
          (platform as Body & { splashLetter?: Letter }).splashLetter = l;
          l.platform = platform;
          Composite.add(engine.world, platform);
        }
      }

      // Сборка закончилась (snap + чуть подержать) — ждём тап.
      const assembledEnough =
        assembled || (frozen != null && elapsed >= FALL_MS + SNAP_MS + 120);
      if (waitForTap && !loop && assembledEnough && !rainArmed && !awaitingTapNotified) {
        awaitingTapNotified = true;
        opts.onAwaitingTap?.();
      }

      const rainElapsed =
        rainStartedAt != null ? now - rainStartedAt : rainArmed ? elapsed : -1;
      while (
        rainArmed &&
        rainElapsed >= 0 &&
        dolls.length < dollCount &&
        rainElapsed >= dollStartMs + dolls.length * DOLL_GAP_MS
      ) {
        spawnDoll(dolls.length, now);
      }

      for (const doll of dolls) {
        if (loop && now - doll.spawnAt > DOLL_LIFE_MS) recycle(doll, now);
        if (doll.landed) continue;
        if (doll.head.position.y <= restY - boxH * 0.9) continue;
        doll.landed = true;
        burst(doll.head.position.x, doll.head.position.y, 8, 4.2);
        thud(doll.head.position.x, 24);
      }

      const snap = frozen && !assembled ? Math.min(1, (elapsed - FALL_MS) / SNAP_MS) : 0;
      const k = assembled ? 1 : snap > 0 ? easeOutBack(snap) : 0;

      ctx.clearRect(0, 0, cssW, cssH);
      ctx.font = fontAt(size);
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";

      letters.forEach((letter, i) => {
        const from = frozen?.[i] ?? {
          x: letter.body.position.x,
          y: letter.body.position.y,
          angle: letter.body.angle,
        };
        ctx.save();
        ctx.translate(
          from.x + (letter.targetX - from.x) * k,
          from.y + (letter.targetY - from.y) * k,
        );
        ctx.rotate(from.angle * (1 - k));
        ctx.fillStyle =
          letter.paint ?? (letter.accent ? accentColor : "#ffffff");
        ctx.fillText(letter.char, 0, 0);
        ctx.restore();
      });

      ctx.lineCap = "round";
      for (const doll of dolls) {
        ctx.strokeStyle = doll.color;
        ctx.fillStyle = doll.color;
        for (const limb of doll.limbs) {
          const reach = Math.max(0, limb.h / 2 - limb.w / 2);
          ctx.save();
          ctx.translate(limb.body.position.x, limb.body.position.y);
          ctx.rotate(limb.body.angle);
          ctx.lineWidth = limb.w;
          ctx.beginPath();
          ctx.moveTo(0, -reach);
          ctx.lineTo(0, reach);
          ctx.stroke();
          ctx.restore();
        }
        ctx.beginPath();
        ctx.arc(doll.head.position.x, doll.head.position.y, doll.headRadius, 0, Math.PI * 2);
        ctx.fill();
      }

      // Искры живут вне физики: дешевле и не мешают телам.
      for (let i = sparks.length - 1; i >= 0; i -= 1) {
        const s = sparks[i];
        if (!s) continue;
        s.x += s.vx;
        s.y += s.vy;
        s.vy += 0.42;
        s.life -= 0.032;
        if (s.life <= 0) {
          sparks.splice(i, 1);
          continue;
        }
        ctx.globalAlpha = Math.max(0, s.life);
        ctx.fillStyle = s.color;
        ctx.fillRect(s.x, s.y, 3, 3);
      }
      ctx.globalAlpha = 1;

      const rainDone =
        rainArmed &&
        rainStartedAt != null &&
        now - rainStartedAt > rainHoldMs;
      const timedOut = !loop && !waitForTap && elapsed > rainHoldMs;
      if (!loop && (finishRequested || rainDone || timedOut)) {
        if (!doneNotified) {
          doneNotified = true;
          opts.onDone?.();
        }
        if (endOnDone || finishRequested) return;
      }
      raf = requestAnimationFrame(frame);
    };

    raf = requestAnimationFrame(frame);
  };

  const beginRain = () => {
    if (disposed || rainArmed) return;
    rainArmed = true;
    rainStartedAt = performance.now();
  };

  const finishNow = () => {
    if (disposed) return;
    finishRequested = true;
  };

  const stop = () => {
    disposed = true;
    cancelAnimationFrame(raf);
    Events.off(engine, "collisionStart");
    Composite.clear(engine.world, false);
    Engine.clear(engine);
  };

  return { start, beginRain, finishNow, stop };
}
