/**
 * Рекламный probe 9:16 (quality pass):
 * 1) заставка YOBBO YOBBO
 * 2) быстрый roster настоящих stickman + лица
 * 3) кинематографичный удар
 * 4) title card
 */
import { drawAvatarOnHead } from "@/face/drawAvatarFace";
import {
  AVATAR_FACE_PRESETS,
  getAvatarFacePreset,
} from "@/face/avatarPresets";
import { bodyColorsFromAvatar } from "@/face/bodyColorsFromAvatar";
import {
  createSplashScene,
  SPLASH_DOLL_COUNT,
  type SplashScene,
} from "@/lib/splashScene";
import {
  pruneBloodyParticles,
  spawnBloodyParticles,
} from "@/lib/bloodyParticles";
import type { Particle } from "@/lib/Particle";
import { applyPlayerColors } from "@/lib/paintStickman";
import {
  BATTLE_BACKDROP_IDS,
  drawBattleBackdrop,
  type BattleBackdropId,
} from "@/render/battleBackdrops";
import { createStickman } from "@/utils/createStickman";
import {
  Bodies,
  Body,
  Composite,
  Engine,
  Events,
  type IEventCollision,
  type Body as MatterBody,
  type Composite as MatterComposite,
  type Render as MatterRender,
} from "matter-js";

export const AD_PROBE_W = 1080;
export const AD_PROBE_H = 1920;

const ROSTER_COUNT = 36;
/** Было 7500ms — смена в 5× быстрее. */
const ROSTER_MS = 1500;
const SLIDE_MS = ROSTER_MS / ROSTER_COUNT;

const SPLASH_HOLD_MS = 5200;
const BEAT_MS = 220;
const FLASH_MS = 200;
/** Подход → серия ударов → thrash → взрыв. */
const IMPACT_MS = 5600;
const EXPLOSION_AT_MS = 4000;
const TITLE_MS = 2000;

type Phase =
  | "splash"
  | "beat"
  | "roster"
  | "flash"
  | "impact"
  | "title"
  | "done";

export type AdProbeApi = {
  ready: boolean;
  phase: Phase;
  t: number;
  record: () => Promise<{ fps: number; frames: string[] }>;
  play: () => Promise<void>;
};

declare global {
  interface Window {
    __RAGDOLL_AD__?: AdProbeApi;
  }
}

interface Fighter {
  composite: MatterComposite;
  head: MatterBody;
  faceId: string;
}

interface Ring {
  x: number;
  y: number;
  life: number;
  max: number;
}

/** Поза относительно груди — чтобы возвращать стойку между ударами. */
interface RestPart {
  label: string;
  dx: number;
  dy: number;
  angle: number;
}

const RECORD_FPS = 30;
const RECORD_DT = 1000 / RECORD_FPS;

function easeOutCubic(x: number): number {
  return 1 - (1 - x) ** 3;
}

function pickRosterFaceIds(): string[] {
  const curated = AVATAR_FACE_PRESETS.slice(0, 29).map((p) => p.id);
  const ids = [...curated];
  let i = 0;
  while (ids.length < ROSTER_COUNT) {
    const p = AVATAR_FACE_PRESETS[i % AVATAR_FACE_PRESETS.length]!;
    if (!ids.includes(p.id)) ids.push(p.id);
    i += 1;
    if (i > AVATAR_FACE_PRESETS.length * 3) break;
  }
  return ids.slice(0, ROSTER_COUNT);
}

function worldToScreen(
  render: MatterRender,
  canvas: HTMLCanvasElement,
  point: { x: number; y: number },
): { x: number; y: number; scale: number } {
  const bw = render.bounds.max.x - render.bounds.min.x;
  const bh = render.bounds.max.y - render.bounds.min.y;
  const scale = Math.min(canvas.width / bw, canvas.height / bh);
  return {
    x: (point.x - render.bounds.min.x) * scale,
    y: (point.y - render.bounds.min.y) * scale,
    scale,
  };
}

export interface AdProbeScene {
  start: (opts?: {
    record?: boolean;
  }) => Promise<{ fps: number; frames: string[] } | void>;
  stop: () => void;
}

export function createAdProbeScene(canvas: HTMLCanvasElement): AdProbeScene {
  const ctx = canvas.getContext("2d", { alpha: false });
  if (!ctx) throw new Error("ad probe: no 2d context");

  const rosterIds = pickRosterFaceIds();
  const leftFaceId = "cat";
  const rightFaceId = "oni";

  let raf = 0;
  let running = false;
  let impactStarted = false;
  let splashStarted = false;
  let exploded = false;
  let camPunch = 0;
  let flashBurst = 0;
  let explosionFlash = 0;
  let left: Fighter | null = null;
  let right: Fighter | null = null;
  let roster: Fighter | null = null;
  let splash: SplashScene | null = null;
  let phase: Phase = "splash";
  let tMs = 0;
  let rings: Ring[] = [];
  let impactTime = 0;
  let lastBloodMs = -999;
  let beatCursor = 0;
  let debris: Particle[] = [];
  let explosionOrigin: { x: number; y: number } | null = null;
  let leftRest: RestPart[] = [];
  let rightRest: RestPart[] = [];
  let hitstopMs = 0;
  let camX = 0;
  let camY = 0;
  let camZoom = 1.1;
  let impactBurst: { x: number; y: number; life: number; power: number } | null =
    null;
  const BASE_GRAVITY = 0.001;
  const FIGHT_GRAVITY = 0.00038;

  const worldW = 900;
  const worldH = 1400;
  const STAND_Y = worldH - 380;
  const LEFT_X = worldW * 0.3;
  const RIGHT_X = worldW * 0.7;
  const AIR_Y = worldH * 0.42;
  const engine = Engine.create({
    gravity: { x: 0, y: 1.2, scale: BASE_GRAVITY },
  });
  const floor = Bodies.rectangle(worldW / 2, worldH - 40, worldW + 400, 100, {
    isStatic: true,
    friction: 0.95,
  });
  const wallL = Bodies.rectangle(-50, worldH / 2, 100, worldH * 2, {
    isStatic: true,
  });
  const wallR = Bodies.rectangle(worldW + 50, worldH / 2, 100, worldH * 2, {
    isStatic: true,
  });

  const fakeRender = {
    canvas,
    context: ctx,
    options: {
      hasBounds: true,
      width: AD_PROBE_W,
      height: AD_PROBE_H,
      pixelRatio: 1,
    },
    bounds: {
      min: { x: 0, y: 0 },
      max: { x: worldW, y: worldH },
    },
    textures: {},
  } as unknown as MatterRender;

  function fighterOwns(f: Fighter | null, body: MatterBody): boolean {
    return !!f && f.composite.bodies.includes(body);
  }

  Events.on(engine, "collisionStart", (ev: IEventCollision<Engine>) => {
    if (!impactStarted || exploded) return;
    for (const pair of ev.pairs) {
      const a = pair.bodyA;
      const b = pair.bodyB;
      const cross =
        (fighterOwns(left, a) && fighterOwns(right, b)) ||
        (fighterOwns(right, a) && fighterOwns(left, b));
      if (!cross) continue;
      const speed = Math.hypot(
        a.velocity.x - b.velocity.x,
        a.velocity.y - b.velocity.y,
      );
      if (speed < 8) continue;
      camPunch = Math.min(1, camPunch + speed * 0.028);
      flashBurst = Math.min(0.55, flashBurst + speed * 0.014);
      const x = (a.position.x + b.position.x) / 2;
      const y = (a.position.y + b.position.y) / 2;
      if (rings.length < 4) {
        rings.push({ x, y, life: 1, max: 1 });
      }
      if (impactTime - lastBloodMs > 70) {
        lastBloodMs = impactTime;
        const victim = fighterOwns(left, a) ? left! : right!;
        const color =
          (victim.head.render.fillStyle as string) || "#ef4444";
        const dirX = b.velocity.x - a.velocity.x;
        const dirY = b.velocity.y - a.velocity.y;
        debris = pruneBloodyParticles(engine.world, debris, 70);
        debris.unshift(
          ...spawnBloodyParticles(engine.world, x, y, color, {
            count: Math.min(18, 6 + Math.floor(speed * 0.7)),
            speed: 7 + speed * 0.35,
            dirX,
            dirY,
            alive: debris.length,
          }),
        );
      }
    }
  });

  function setApi(): void {
    if (!window.__RAGDOLL_AD__) return;
    window.__RAGDOLL_AD__.phase = phase;
    window.__RAGDOLL_AD__.t = tMs;
  }

  function resetCanvasFixed(): void {
    if (canvas.width !== AD_PROBE_W || canvas.height !== AD_PROBE_H) {
      canvas.width = AD_PROBE_W;
      canvas.height = AD_PROBE_H;
    }
    canvas.style.width = "min(100vw, calc(100vh * 9 / 16))";
    canvas.style.height = "min(100vh, calc(100vw * 16 / 9))";
  }

  function setCamera(cx: number, cy: number, zoom: number): void {
    const viewW = worldW / zoom;
    const viewH = worldH / zoom;
    fakeRender.bounds.min.x = cx - viewW / 2;
    fakeRender.bounds.min.y = cy - viewH / 2;
    fakeRender.bounds.max.x = cx + viewW / 2;
    fakeRender.bounds.max.y = cy + viewH / 2;
  }

  /** Глубокий stage: не плоский UI, не «карточка». */
  function paintStage(accent = "#38bdf8"): void {
    const g = ctx.createLinearGradient(0, 0, 0, AD_PROBE_H);
    g.addColorStop(0, "#06060c");
    g.addColorStop(0.45, "#0c1018");
    g.addColorStop(1, "#140c12");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);

    // мягкий свет сзади персонажа
    const glow = ctx.createRadialGradient(
      AD_PROBE_W / 2,
      AD_PROBE_H * 0.42,
      40,
      AD_PROBE_W / 2,
      AD_PROBE_H * 0.48,
      AD_PROBE_H * 0.55,
    );
    glow.addColorStop(0, `${accent}33`);
    glow.addColorStop(0.35, `${accent}14`);
    glow.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);

    // пол — тонкая линия горизонта
    const floorY = AD_PROBE_H * 0.72;
    const fg = ctx.createLinearGradient(0, floorY, 0, AD_PROBE_H);
    fg.addColorStop(0, "rgba(255,255,255,0.04)");
    fg.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = fg;
    ctx.fillRect(0, floorY, AD_PROBE_W, AD_PROBE_H - floorY);
  }

  function paintVignette(strength = 0.55): void {
    const g = ctx.createRadialGradient(
      AD_PROBE_W / 2,
      AD_PROBE_H * 0.42,
      AD_PROBE_W * 0.18,
      AD_PROBE_W / 2,
      AD_PROBE_H * 0.5,
      AD_PROBE_H * 0.78,
    );
    g.addColorStop(0, "rgba(0,0,0,0)");
    g.addColorStop(1, `rgba(0,0,0,${strength})`);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
  }

  function spawnFighter(
    x: number,
    y: number,
    faceId: string,
    opts?: { scale?: number; air?: number },
  ): Fighter {
    const preset = getAvatarFacePreset(faceId);
    const colors = bodyColorsFromAvatar(preset);
    // Чуть крупнее дефолта — тело читается в 9:16.
    const composite = createStickman(x, y, {
      scale: opts?.scale ?? 1.35,
      render: { fillStyle: colors.main },
    });
    applyPlayerColors(composite, colors.main, colors.secondary);
    const head = composite.bodies.find((b) => b.label === "Head");
    if (!head) throw new Error("ad probe: stickman head missing");
    head.render.visible = true;
    head.render.fillStyle = colors.secondary;
    head.render.strokeStyle = "#ffffff";
    head.render.lineWidth = 2;
    for (const b of composite.bodies) {
      Body.setVelocity(b, { x: 0, y: 0 });
      Body.setAngularVelocity(b, 0);
      if (opts?.air != null) Body.set(b, { frictionAir: opts.air });
    }
    return { composite, head, faceId };
  }

  function drawFighterSafe(
    f: Fighter,
    emotion: "angry" | "neutral" | "smile" = "angry",
  ): void {
    // Одна система координат с drawAvatarOnHead (worldToCanvas) —
    // Matter.Render.startViewTransform даёт другой scale → лицо «отлипает».
    for (const body of f.composite.bodies) {
      const fill = (body.render.fillStyle as string) || "#888";
      const { x, y, scale } = worldToScreen(fakeRender, canvas, body.position);
      const r = (body.circleRadius ?? 10) * scale;
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(body.angle);
      // Мягкий объём: заливка + тонкий светлый ободок.
      ctx.fillStyle = fill;
      ctx.beginPath();
      ctx.arc(0, 0, r, 0, Math.PI * 2);
      ctx.fill();
      if (body.label !== "Head") {
        ctx.strokeStyle = "rgba(255,255,255,0.14)";
        ctx.lineWidth = Math.max(1, r * 0.08);
        ctx.stroke();
      }
      ctx.restore();
    }
    drawAvatarOnHead(ctx, fakeRender, f.head, getAvatarFacePreset(f.faceId), {
      emotion,
    });
  }

  function bodiesByLabel(f: Fighter, label: string): MatterBody[] {
    return f.composite.bodies.filter((b) => b.label === label);
  }

  function rotateBodiesAround(
    bodies: MatterBody[],
    pivot: { x: number; y: number },
    angle: number,
  ): void {
    if (Math.abs(angle) < 1e-4) return;
    const c = Math.cos(angle);
    const s = Math.sin(angle);
    for (const b of bodies) {
      const dx = b.position.x - pivot.x;
      const dy = b.position.y - pivot.y;
      Body.setPosition(b, {
        x: pivot.x + dx * c - dy * s,
        y: pivot.y + dx * s + dy * c,
      });
      Body.setAngle(b, b.angle + angle);
    }
  }

  /** Статичные позы для roster (без физики / без сдвига камеры). */
  function applyRosterPose(f: Fighter, seed: number): void {
    const chest =
      f.composite.bodies.find((b) => b.label === "Chest") ??
      f.composite.bodies[0]!;
    const pivot = { x: chest.position.x, y: chest.position.y };
    const leftArm = [
      ...bodiesByLabel(f, "Upper Left Arm"),
      ...bodiesByLabel(f, "Lower Left Arm"),
    ];
    const rightArm = [
      ...bodiesByLabel(f, "Upper Right Arm"),
      ...bodiesByLabel(f, "Lower Right Arm"),
    ];
    const leftLeg = [
      ...bodiesByLabel(f, "Upper Left Leg"),
      ...bodiesByLabel(f, "Lower Left Leg"),
    ];
    const rightLeg = [
      ...bodiesByLabel(f, "Upper Right Leg"),
      ...bodiesByLabel(f, "Lower Right Leg"),
    ];

    // 8 читаемых поз — руки/ноги чуть иначе, центр кадра тот же.
    const pose = seed % 8;
    let lean = 0;
    let la = 0;
    let ra = 0;
    let ll = 0;
    let rl = 0;
    switch (pose) {
      case 0: // T-pose, лёгкий lean
        lean = -0.06;
        break;
      case 1: // руки вниз
        la = 1.05;
        ra = -1.05;
        lean = 0.04;
        break;
      case 2: // одна рука вверх
        la = -0.85;
        ra = -0.35;
        lean = -0.08;
        break;
      case 3: // обе вверх (celebration)
        la = -1.15;
        ra = 1.15;
        lean = 0.05;
        break;
      case 4: // guard / fight
        la = 0.55;
        ra = -0.75;
        ll = 0.18;
        rl = -0.12;
        lean = -0.1;
        break;
      case 5: // руки в стороны-вниз + шаг
        la = 0.45;
        ra = -0.45;
        ll = 0.22;
        rl = -0.2;
        lean = 0.07;
        break;
      case 6: // рука машет
        la = -1.35;
        ra = -0.2;
        lean = 0.1;
        break;
      default: // сжатый / готов
        la = 0.85;
        ra = -0.55;
        ll = 0.12;
        rl = 0.08;
        lean = -0.04;
        break;
    }

    rotateBodiesAround(leftArm, pivot, la);
    rotateBodiesAround(rightArm, pivot, ra);
    // Ноги крутим от таза чуть ниже груди.
    const hip = {
      x: pivot.x,
      y: pivot.y + (chest.circleRadius ?? 10) * 3,
    };
    rotateBodiesAround(leftLeg, hip, ll);
    rotateBodiesAround(rightLeg, hip, rl);

    Body.setAngle(chest, lean);
    Body.setAngle(f.head, lean * 0.55);
    // Голову чуть смещаем с lean, чтобы не «отлипала».
    Body.setPosition(f.head, {
      x: f.head.position.x + lean * 6,
      y: f.head.position.y,
    });
  }

  function poseRoster(faceId: string, seed: number): void {
    Composite.clear(engine.world, false, true);
    Composite.add(engine.world, [floor, wallL, wallR]);
    // Всегда в одном месте — без сдвига влево/вправо.
    const f = spawnFighter(worldW / 2, worldH * 0.58, faceId);
    roster = f;
    Composite.add(engine.world, f.composite);
    for (const b of f.composite.bodies) {
      Body.setStatic(b, true);
      Body.setVelocity(b, { x: 0, y: 0 });
      Body.setAngularVelocity(b, 0);
    }
    applyRosterPose(f, seed);
  }

  function fighterCenter(f: Fighter): { x: number; y: number } {
    let sx = 0;
    let sy = 0;
    let minY = Infinity;
    let maxY = -Infinity;
    const bodies = f.composite.bodies;
    for (const b of bodies) {
      sx += b.position.x;
      sy += b.position.y;
      minY = Math.min(minY, b.position.y);
      maxY = Math.max(maxY, b.position.y);
    }
    const n = Math.max(1, bodies.length);
    // Центр по bbox — голова и ноги влезают вместе.
    return { x: sx / n, y: (minY + maxY) / 2 };
  }

  function paintRoster(localMs: number): void {
    const idx = Math.min(
      rosterIds.length - 1,
      Math.max(0, Math.floor(localMs / SLIDE_MS)),
    );
    const within = localMs - idx * SLIDE_MS;
    const faceId = rosterIds[idx]!;
    const theme = BATTLE_BACKDROP_IDS[
      idx % BATTLE_BACKDROP_IDS.length
    ] as BattleBackdropId;

    if (!roster || roster.faceId !== faceId) {
      poseRoster(faceId, idx);
    }

    // Целое тело крупно; камера без горизонтального сдвига.
    const center = roster
      ? fighterCenter(roster)
      : { x: worldW / 2, y: worldH * 0.55 };
    const punchIn = Math.min(SLIDE_MS * 0.45, 28);
    const punch =
      3.25 + 0.12 * easeOutCubic(1 - Math.min(1, within / Math.max(1, punchIn)));
    setCamera(center.x, center.y, punch);

    drawBattleBackdrop(ctx, AD_PROBE_W, AD_PROBE_H, localMs + idx * 900, theme);
    const emotions = ["angry", "smile", "neutral"] as const;
    if (roster) drawFighterSafe(roster, emotions[idx % emotions.length]!);
    paintVignette(0.42);

    const flashMs = Math.min(10, SLIDE_MS * 0.25);
    if (within < flashMs) {
      ctx.fillStyle = `rgba(255,255,255,${0.18 * (1 - within / flashMs)})`;
      ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
    }
  }

  function clearDebris(): void {
    for (const p of debris) {
      Composite.remove(engine.world, p.body);
    }
    debris = [];
  }

  function captureRest(f: Fighter): RestPart[] {
    const chest =
      f.composite.bodies.find((b) => b.label === "Chest") ??
      f.composite.bodies[0]!;
    return f.composite.bodies.map((b) => ({
      label: String(b.label ?? ""),
      dx: b.position.x - chest.position.x,
      dy: b.position.y - chest.position.y,
      angle: b.angle,
    }));
  }

  function plantFighter(
    f: Fighter,
    rest: RestPart[],
    x: number,
    y: number,
    frozen: boolean,
  ): void {
    const byLabel = new Map(rest.map((p) => [p.label, p]));
    for (const b of f.composite.bodies) {
      const pose = byLabel.get(String(b.label ?? ""));
      if (!pose) continue;
      Body.setPosition(b, { x: x + pose.dx, y: y + pose.dy });
      Body.setAngle(b, pose.angle);
      Body.setVelocity(b, { x: 0, y: 0 });
      Body.setAngularVelocity(b, 0);
      Body.setStatic(b, frozen);
    }
  }

  function armBodies(f: Fighter, side: "Left" | "Right"): MatterBody[] {
    return f.composite.bodies.filter((b) =>
      String(b.label).includes(`${side} Arm`),
    );
  }

  /** Боевая стойка: руки не в T-pose навстречу, а чуть вниз/к лицу. */
  function applyGuard(f: Fighter, facing: 1 | -1): void {
    const chest =
      f.composite.bodies.find((b) => b.label === "Chest") ??
      f.composite.bodies[0]!;
    const pivot = { x: chest.position.x, y: chest.position.y };
    const lead = facing > 0 ? "Right" : "Left";
    const rear = facing > 0 ? "Left" : "Right";
    // lead ближе к сопернику — guard у груди; rear опущена.
    rotateBodiesAround(armBodies(f, lead), pivot, facing * 0.55);
    rotateBodiesAround(armBodies(f, rear), pivot, facing * 1.05);
  }

  function standBoth(frozen: boolean): void {
    if (!left || !right) return;
    plantFighter(left, leftRest, LEFT_X, STAND_Y, frozen);
    plantFighter(right, rightRest, RIGHT_X, STAND_Y, frozen);
    applyGuard(left, 1);
    applyGuard(right, -1);
  }

  function hitSpark(x: number, y: number, color: string, power = 1): void {
    rings.push({ x, y, life: 1, max: 1 });
    rings.push({ x, y, life: 0.85, max: 1 });
    impactBurst = { x, y, life: 1, power };
    debris = pruneBloodyParticles(engine.world, debris, 50);
    debris.unshift(
      ...spawnBloodyParticles(engine.world, x, y, color, {
        count: Math.round(12 * power),
        speed: 10 + 5 * power,
        alive: debris.length,
      }),
    );
    debris.unshift(
      ...spawnBloodyParticles(engine.world, x, y, "#fff7ed", {
        count: Math.round(6 * power),
        speed: 14 + 4 * power,
        alive: debris.length,
      }),
    );
    camPunch = Math.min(1, camPunch + 0.55 * power);
    flashBurst = Math.min(0.75, flashBurst + 0.28 * power);
    hitstopMs = Math.max(hitstopMs, 70 + 40 * power);
  }

  function fling(
    f: Fighter,
    vx: number,
    vy: number,
    spin = 0,
  ): void {
    for (const b of f.composite.bodies) {
      Body.setVelocity(b, { x: vx, y: vy });
      if (spin) Body.setAngularVelocity(b, spin);
    }
  }

  /** Целые силуэты в воздухе — «кадр» перед ударом, не лапша. */
  function placeAerial(
    f: Fighter,
    rest: RestPart[],
    x: number,
    y: number,
    facing: 1 | -1,
  ): void {
    plantFighter(f, rest, x, y, false);
    applyGuard(f, facing);
  }

  /**
   * Кинематографичный удар: оба в читаемой позе → вспышка → отлёт.
   */
  function cinematicStrike(
    side: "left" | "right",
    opts?: { y?: number; power?: number; loft?: number },
  ): void {
    if (!left || !right) return;
    const y = opts?.y ?? AIR_Y;
    const power = opts?.power ?? 1.3;
    const loft = opts?.loft ?? -8;
    placeAerial(left, leftRest, worldW * 0.38, y, 1);
    placeAerial(right, rightRest, worldW * 0.62, y, -1);

    const hx = (left.head.position.x + right.head.position.x) / 2;
    const hy = (left.head.position.y + right.head.position.y) / 2;

    if (side === "left") {
      const color = (right.head.render.fillStyle as string) || "#ef4444";
      hitSpark(hx + 16, hy, color, power);
      fling(left, 10, loft * 0.35, 0.1);
      for (const b of armBodies(left, "Right")) {
        Body.setVelocity(b, { x: 22, y: loft * 0.2 });
      }
      fling(right, 20 + 4 * power, loft - 2, -0.28);
      Body.setVelocity(right.head, { x: 24 + 4 * power, y: loft - 4 });
    } else {
      const color = (left.head.render.fillStyle as string) || "#d97706";
      hitSpark(hx - 16, hy, color, power);
      fling(right, -10, loft * 0.35, -0.1);
      for (const b of armBodies(right, "Left")) {
        Body.setVelocity(b, { x: -22, y: loft * 0.2 });
      }
      fling(left, -(20 + 4 * power), loft - 2, 0.28);
      Body.setVelocity(left.head, { x: -(24 + 4 * power), y: loft - 4 });
    }
  }

  function paintSpeedLines(f: Fighter): void {
    const v = f.head.velocity;
    const speed = Math.hypot(v.x, v.y);
    if (speed < 10) return;
    const { x, y, scale } = worldToScreen(
      fakeRender,
      canvas,
      f.head.position,
    );
    const len = Math.min(280, speed * 7) * scale;
    const ang = Math.atan2(v.y, v.x);
    ctx.save();
    ctx.lineCap = "round";
    for (let i = 0; i < 4; i += 1) {
      const off = (i - 1.5) * 12 * scale;
      const ox = Math.cos(ang + Math.PI / 2) * off;
      const oy = Math.sin(ang + Math.PI / 2) * off;
      const a = Math.min(0.65, speed * 0.018) * (1 - i * 0.12);
      ctx.strokeStyle = `rgba(255,230,200,${a})`;
      ctx.lineWidth = (4 - i * 0.5) * scale;
      ctx.beginPath();
      ctx.moveTo(x + ox, y + oy);
      ctx.lineTo(
        x + ox - Math.cos(ang) * len,
        y + oy - Math.sin(ang) * len,
      );
      ctx.stroke();
    }
    ctx.restore();
  }

  function paintImpactBurst(): void {
    if (!impactBurst || impactBurst.life <= 0) {
      impactBurst = null;
      return;
    }
    const b = impactBurst;
    b.life -= 0.06;
    const { x, y, scale } = worldToScreen(fakeRender, canvas, {
      x: b.x,
      y: b.y,
    });
    const t = 1 - b.life;
    const R = (30 + t * 160) * scale * b.power;
    ctx.save();
    // Ядро
    const g = ctx.createRadialGradient(x, y, 0, x, y, R);
    g.addColorStop(0, `rgba(255,255,255,${0.95 * b.life})`);
    g.addColorStop(0.25, `rgba(255,210,120,${0.7 * b.life})`);
    g.addColorStop(0.6, `rgba(255,80,40,${0.35 * b.life})`);
    g.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, R, 0, Math.PI * 2);
    ctx.fill();
    // Лучи
    ctx.strokeStyle = `rgba(255,245,220,${0.75 * b.life})`;
    ctx.lineWidth = 3 * scale;
    const spikes = 10;
    for (let i = 0; i < spikes; i += 1) {
      const ang = (i / spikes) * Math.PI * 2 + t * 0.4;
      const r0 = R * 0.25;
      const r1 = R * (0.7 + (i % 2) * 0.35);
      ctx.beginPath();
      ctx.moveTo(x + Math.cos(ang) * r0, y + Math.sin(ang) * r0);
      ctx.lineTo(x + Math.cos(ang) * r1, y + Math.sin(ang) * r1);
      ctx.stroke();
    }
    ctx.restore();
  }

  function paintFightGrade(): void {
    // Тёплый свет в центре + холодные края — «кино», не плоский коричневый.
    const g = ctx.createRadialGradient(
      AD_PROBE_W / 2,
      AD_PROBE_H * 0.42,
      40,
      AD_PROBE_W / 2,
      AD_PROBE_H * 0.48,
      AD_PROBE_H * 0.72,
    );
    g.addColorStop(0, "rgba(255,160,60,0.12)");
    g.addColorStop(0.45, "rgba(255,80,40,0.04)");
    g.addColorStop(1, "rgba(0,0,20,0.45)");
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
  }

  function spawnImpact(): void {
    clearDebris();
    Composite.clear(engine.world, false, true);
    Composite.add(engine.world, [floor, wallL, wallR]);
    engine.gravity.scale = FIGHT_GRAVITY;

    left = spawnFighter(LEFT_X, STAND_Y, leftFaceId, {
      scale: 1.5,
      air: 0.028,
    });
    right = spawnFighter(RIGHT_X, STAND_Y, rightFaceId, {
      scale: 1.5,
      air: 0.028,
    });
    leftRest = captureRest(left);
    rightRest = captureRest(right);
    Composite.add(engine.world, left.composite);
    Composite.add(engine.world, right.composite);
    standBoth(true);

    roster = null;
    impactStarted = false;
    exploded = false;
    camPunch = 0;
    flashBurst = 0;
    explosionFlash = 0;
    hitstopMs = 0;
    impactBurst = null;
    rings = [];
    impactTime = 0;
    lastBloodMs = -999;
    beatCursor = 0;
    explosionOrigin = null;
    camX = (LEFT_X + RIGHT_X) / 2;
    camY = AIR_Y;
    camZoom = 1.15;
  }

  function beginImpact(): void {
    if (impactStarted || !left || !right) return;
    impactStarted = true;
    // Старт: оба в воздухе напротив — сразу красивый кадр.
    placeAerial(left, leftRest, worldW * 0.34, AIR_Y + 40, 1);
    placeAerial(right, rightRest, worldW * 0.66, AIR_Y + 40, -1);
    fling(left, 7, -14, 0.06);
    fling(right, -7, -14, -0.06);
  }

  /** Мало ударов, каждый — отдельный «комикс-кадр» + отлёт. */
  function driveImpactBeats(t: number): void {
    if (!left || !right || exploded) return;
    const beats: { at: number; run: () => void }[] = [
      {
        at: 400,
        run: () => cinematicStrike("left", { power: 1.25, loft: -10 }),
      },
      {
        at: 1000,
        run: () =>
          cinematicStrike("right", {
            y: AIR_Y - 40,
            power: 1.4,
            loft: -16,
          }),
      },
      {
        at: 1650,
        run: () =>
          cinematicStrike("left", {
            y: AIR_Y + 60,
            power: 1.45,
            loft: 8,
          }),
      },
      {
        at: 2300,
        run: () =>
          cinematicStrike("right", {
            y: AIR_Y - 80,
            power: 1.5,
            loft: -18,
          }),
      },
      {
        at: 2950,
        run: () => {
          // Разлёт к краям — пауза перед финалом.
          placeAerial(left!, leftRest, worldW * 0.22, AIR_Y - 20, 1);
          placeAerial(right!, rightRest, worldW * 0.78, AIR_Y - 20, -1);
          fling(left!, -8, -6, 0.15);
          fling(right!, 8, -6, -0.15);
          camPunch = 0.6;
        },
      },
      {
        at: 3400,
        run: () => {
          // Финальный таран в центре.
          placeAerial(left!, leftRest, worldW * 0.36, AIR_Y, 1);
          placeAerial(right!, rightRest, worldW * 0.64, AIR_Y, -1);
          fling(left!, 22, -4, 0.35);
          fling(right!, -22, -4, -0.35);
          hitSpark(worldW / 2, AIR_Y, "#fb923c", 1.8);
          camPunch = 1;
          flashBurst = 0.85;
        },
      },
    ];
    while (beatCursor < beats.length && t >= beats[beatCursor]!.at) {
      beats[beatCursor]!.run();
      beatCursor += 1;
    }
  }

  function triggerExplosion(): void {
    if (exploded || !left || !right) return;
    exploded = true;
    engine.gravity.scale = BASE_GRAVITY;
    const ox = (left.head.position.x + right.head.position.x) / 2;
    const oy = (left.head.position.y + right.head.position.y) / 2;
    explosionOrigin = { x: ox, y: oy };
    explosionFlash = 1;
    camPunch = 1;
    flashBurst = 1;

    for (const f of [left, right]) {
      for (const b of f.composite.bodies) {
        const dx = b.position.x - ox + (Math.random() - 0.5) * 8;
        const dy = b.position.y - oy + (Math.random() - 0.5) * 8;
        const dist = Math.max(10, Math.hypot(dx, dy));
        const power = 38 + Math.random() * 22;
        Body.setVelocity(b, {
          x: (dx / dist) * power,
          y: (dy / dist) * power - 14 - Math.random() * 10,
        });
        Body.setAngularVelocity(b, (Math.random() - 0.5) * 1.8);
      }
    }

    const colors = [
      "#fb923c",
      "#fbbf24",
      "#f87171",
      "#fff7ed",
      "#ef4444",
      "#fdba74",
      "#ffffff",
    ];
    debris = pruneBloodyParticles(engine.world, debris, 24);
    for (let i = 0; i < colors.length; i += 1) {
      debris.unshift(
        ...spawnBloodyParticles(
          engine.world,
          ox + (Math.random() - 0.5) * 40,
          oy + (Math.random() - 0.5) * 40,
          colors[i]!,
          {
            count: 14,
            speed: 18 + i * 2.5,
            alive: debris.length,
          },
        ),
      );
    }
    for (let i = 0; i < 8; i += 1) {
      rings.push({
        x: ox + (Math.random() - 0.5) * 24,
        y: oy + (Math.random() - 0.5) * 24,
        life: 1 - i * 0.04,
        max: 1,
      });
    }
  }

  function paintRings(): void {
    for (let i = rings.length - 1; i >= 0; i -= 1) {
      const ring = rings[i]!;
      ring.life -= exploded ? 0.028 : 0.045;
      if (ring.life <= 0) {
        rings.splice(i, 1);
        continue;
      }
      const { x, y, scale } = worldToScreen(fakeRender, canvas, {
        x: ring.x,
        y: ring.y,
      });
      const boom = exploded ? 520 : 200;
      const radius = (1 - ring.life) * boom * scale;
      ctx.save();
      ctx.strokeStyle = exploded
        ? `rgba(255,200,90,${ring.life * 0.95})`
        : `rgba(255,230,180,${ring.life * 0.9})`;
      ctx.lineWidth = (exploded ? 14 : 8) * ring.life;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }
  }

  function paintDebris(frameDt: number): void {
    const lifeScale = frameDt / 1100;
    for (let i = debris.length - 1; i >= 0; i -= 1) {
      const p = debris[i]!;
      p.life -= lifeScale;
      p.body.render.opacity = Math.max(0, p.life);
      if (p.life <= 0) {
        Composite.remove(engine.world, p.body);
        debris.splice(i, 1);
        continue;
      }
      const fill = (p.body.render.fillStyle as string) || "#f00";
      const { x, y, scale } = worldToScreen(
        fakeRender,
        canvas,
        p.body.position,
      );
      const r = (p.body.circleRadius ?? 2) * scale;
      ctx.save();
      ctx.globalAlpha = Math.max(0, p.life);
      ctx.fillStyle = fill;
      ctx.beginPath();
      ctx.arc(x, y, Math.max(1.5, r), 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
  }

  function paintExplosionBloom(): void {
    if (!explosionOrigin || explosionFlash < 0.01) return;
    const { x, y, scale } = worldToScreen(
      fakeRender,
      canvas,
      explosionOrigin,
    );
    const t = 1 - explosionFlash;
    const r = (120 + t * 1100) * scale;
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, `rgba(255,255,255,${Math.min(1, explosionFlash)})`);
    g.addColorStop(0.08, `rgba(255,250,200,${0.98 * explosionFlash})`);
    g.addColorStop(0.25, `rgba(255,160,40,${0.85 * explosionFlash})`);
    g.addColorStop(0.5, `rgba(255,60,20,${0.55 * explosionFlash})`);
    g.addColorStop(0.78, `rgba(80,10,0,${0.25 * explosionFlash})`);
    g.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();

    // Только короткий белый пик — иначе кадр «выцветает» в беж.
    if (explosionFlash > 0.82) {
      const peak = (explosionFlash - 0.82) / 0.18;
      ctx.fillStyle = `rgba(255,255,255,${0.75 * peak})`;
      ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
    } else if (explosionFlash > 0.35) {
      ctx.fillStyle = `rgba(255,90,20,${0.18 * explosionFlash})`;
      ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
    }
  }

  function paintImpact(frameDt: number): void {
    if (!left || !right) return;
    beginImpact();
    impactTime += frameDt;
    driveImpactBeats(impactTime);
    if (impactTime >= EXPLOSION_AT_MS) triggerExplosion();

    // Hitstop: короткая пауза на ударе — читается «красивый» панч.
    if (hitstopMs > 0) {
      hitstopMs = Math.max(0, hitstopMs - frameDt);
    } else {
      const step = 1000 / 60;
      let leftMs = frameDt;
      while (leftMs > 0) {
        Engine.update(engine, Math.min(step, leftMs));
        leftMs -= step;
      }
    }
    camPunch *= exploded ? 0.95 : 0.9;
    flashBurst *= 0.91;
    explosionFlash *= exploded && explosionFlash > 0.55 ? 0.97 : 0.935;

    const targetX = exploded && explosionOrigin
      ? explosionOrigin.x
      : (left.head.position.x + right.head.position.x) / 2;
    const targetY = exploded && explosionOrigin
      ? explosionOrigin.y
      : (left.head.position.y + right.head.position.y) / 2 - 20;
    const targetZoom = exploded
      ? 1.1 + camPunch * 0.28
      : 1.2 + camPunch * 0.22;
    // Плавная камера — без дёрганья.
    camX += (targetX - camX) * 0.18;
    camY += (targetY - camY) * 0.18;
    camZoom += (targetZoom - camZoom) * 0.14;
    const shake = (exploded ? 36 : 10) * camPunch;
    setCamera(
      camX + (Math.random() - 0.5) * shake,
      camY + (Math.random() - 0.5) * shake * 0.5,
      camZoom,
    );

    drawBattleBackdrop(
      ctx,
      AD_PROBE_W,
      AD_PROBE_H,
      impactTime,
      "dawn_horizon",
    );
    paintFightGrade();
    paintSpeedLines(left);
    paintSpeedLines(right);
    drawFighterSafe(left, "angry");
    drawFighterSafe(right, "angry");
    paintDebris(frameDt);
    paintRings();
    paintImpactBurst();
    paintExplosionBloom();

    if (flashBurst > 0.02 && !exploded) {
      ctx.fillStyle = `rgba(255,220,180,${flashBurst * 0.85})`;
      ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
    }
    paintVignette(exploded ? 0.32 : 0.42 + camPunch * 0.15);
  }

  function paintTitle(localMs: number): void {
    const u = Math.min(1, localMs / 550);
    const a = easeOutCubic(u);
    drawBattleBackdrop(ctx, AD_PROBE_W, AD_PROBE_H, localMs + 8000, "orbital");
    ctx.fillStyle = `rgba(5,5,10,${0.55 + 0.35 * a})`;
    ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);

    ctx.save();
    ctx.globalAlpha = a;
    ctx.textAlign = "center";
    ctx.fillStyle = "#f8fafc";
    ctx.font = "800 100px Unbounded, Rubik, sans-serif";
    ctx.fillText("YOBBO", AD_PROBE_W / 2, AD_PROBE_H * 0.45);
    ctx.fillStyle = "#38bdf8";
    ctx.fillText("YOBBO", AD_PROBE_W / 2, AD_PROBE_H * 0.52);
    ctx.font = "500 34px Rubik, sans-serif";
    ctx.fillStyle = "rgba(248,250,252,0.7)";
    ctx.fillText("Throw limbs. Laugh.", AD_PROBE_W / 2, AD_PROBE_H * 0.6);
    ctx.restore();
    paintVignette(0.4);
  }

  function paintBeat(): void {
    ctx.fillStyle = "#050508";
    ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
  }

  function grabJpeg(): string {
    return canvas.toDataURL("image/jpeg", 0.9).split(",")[1] ?? "";
  }

  async function runSplash(capture: boolean): Promise<string[]> {
    if (splashStarted) return [];
    splashStarted = true;
    phase = "splash";
    setApi();
    resetCanvasFixed();

    const accent =
      getComputedStyle(document.documentElement)
        .getPropertyValue("--menu-accent")
        .trim() || "#38bdf8";

    splash = createSplashScene({
      canvas,
      words: [
        { text: "Yobbo", accent: false },
        { text: "Yobbo", accent: true },
      ],
      accentColor: accent,
      dollCount: Math.max(SPLASH_DOLL_COUNT, 56),
      viewSize: { w: AD_PROBE_W, h: AD_PROBE_H },
      waitForTap: false,
      endOnDone: false,
    });
    void splash.start().catch((err) => {
      console.error("[ad-probe] splash start failed", err);
    });

    const started = performance.now();
    const captured: string[] = [];
    while (running && performance.now() - started < SPLASH_HOLD_MS) {
      tMs = performance.now() - started;
      setApi();
      if (capture) captured.push(grabJpeg());
      await new Promise<void>((r) => requestAnimationFrame(() => r()));
    }
    splash.stop();
    splash = null;
    resetCanvasFixed();
    ctx.setTransform(1, 0, 0, 1, 0, 0);

    if (!capture || captured.length === 0) return [];
    const target = Math.round((SPLASH_HOLD_MS / 1000) * RECORD_FPS);
    return Array.from({ length: target }, (_, i) => {
      const src = Math.min(
        captured.length - 1,
        Math.floor((i * captured.length) / target),
      );
      return captured[src]!;
    });
  }

  function stop(): void {
    running = false;
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
    splash?.stop();
    splash = null;
  }

  async function runTimeline(recording: boolean): Promise<string[]> {
    const frames: string[] = [];
    const push = () => {
      if (recording) frames.push(grabJpeg());
    };
    const yieldOccasionally = async (i: number) => {
      if (recording && i % 12 === 0) {
        await new Promise<void>((r) => requestAnimationFrame(() => r()));
      }
    };

    // beat после заставки
    {
      const n = Math.round((BEAT_MS / 1000) * RECORD_FPS);
      for (let i = 0; i < n && running; i += 1) {
        phase = "beat";
        tMs = SPLASH_HOLD_MS + i * RECORD_DT;
        setApi();
        paintBeat();
        push();
      }
    }

    spawnImpact(); // walls ready; roster пересоздаст
    roster = null;

    {
      const n = Math.round((ROSTER_MS / 1000) * RECORD_FPS);
      for (let i = 0; i < n && running; i += 1) {
        phase = "roster";
        tMs = SPLASH_HOLD_MS + BEAT_MS + i * RECORD_DT;
        setApi();
        paintRoster(i * RECORD_DT);
        push();
        await yieldOccasionally(i);
      }
    }

    {
      const n = Math.round((FLASH_MS / 1000) * RECORD_FPS);
      for (let i = 0; i < n && running; i += 1) {
        phase = "flash";
        tMs = SPLASH_HOLD_MS + BEAT_MS + ROSTER_MS + i * RECORD_DT;
        setApi();
        paintRoster(ROSTER_MS - 1);
        const f = 1 - i / Math.max(1, n);
        ctx.fillStyle = `rgba(255,255,255,${0.92 * f})`;
        ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
        push();
      }
    }

    spawnImpact();
    {
      const n = Math.round((IMPACT_MS / 1000) * RECORD_FPS);
      for (let i = 0; i < n && running; i += 1) {
        phase = "impact";
        tMs = SPLASH_HOLD_MS + BEAT_MS + ROSTER_MS + FLASH_MS + i * RECORD_DT;
        setApi();
        paintImpact(RECORD_DT);
        push();
        await yieldOccasionally(i);
      }
    }

    {
      const n = Math.round((TITLE_MS / 1000) * RECORD_FPS);
      for (let i = 0; i < n && running; i += 1) {
        phase = "title";
        tMs =
          SPLASH_HOLD_MS +
          BEAT_MS +
          ROSTER_MS +
          FLASH_MS +
          IMPACT_MS +
          i * RECORD_DT;
        setApi();
        paintTitle(i * RECORD_DT);
        push();
        await yieldOccasionally(i);
      }
    }

    return frames;
  }

  async function playRealtime(): Promise<void> {
    // beat
    {
      const t0 = performance.now();
      await new Promise<void>((resolve) => {
        const tick = (now: number) => {
          if (!running || now - t0 >= BEAT_MS) {
            resolve();
            return;
          }
          phase = "beat";
          tMs = SPLASH_HOLD_MS + (now - t0);
          setApi();
          paintBeat();
          raf = requestAnimationFrame(tick);
        };
        raf = requestAnimationFrame(tick);
      });
    }

    const t0 = performance.now();
    let last = t0;
    await new Promise<void>((resolve) => {
      const tick = (now: number) => {
        if (!running) {
          resolve();
          return;
        }
        const local = now - t0;
        if (local < ROSTER_MS) {
          phase = "roster";
          tMs = SPLASH_HOLD_MS + BEAT_MS + local;
          setApi();
          paintRoster(local);
          raf = requestAnimationFrame(tick);
          return;
        }
        if (local < ROSTER_MS + FLASH_MS) {
          phase = "flash";
          tMs = SPLASH_HOLD_MS + BEAT_MS + local;
          setApi();
          paintRoster(ROSTER_MS - 1);
          const f = 1 - (local - ROSTER_MS) / FLASH_MS;
          ctx.fillStyle = `rgba(255,255,255,${0.92 * Math.max(0, f)})`;
          ctx.fillRect(0, 0, AD_PROBE_W, AD_PROBE_H);
          raf = requestAnimationFrame(tick);
          return;
        }
        const afterFlash = local - ROSTER_MS - FLASH_MS;
        if (afterFlash < IMPACT_MS) {
          if (!impactStarted) spawnImpact();
          phase = "impact";
          tMs = SPLASH_HOLD_MS + BEAT_MS + local;
          setApi();
          const dt = Math.min(40, now - last);
          last = now;
          paintImpact(dt);
          raf = requestAnimationFrame(tick);
          return;
        }
        const titleLocal = afterFlash - IMPACT_MS;
        if (titleLocal < TITLE_MS) {
          phase = "title";
          tMs = SPLASH_HOLD_MS + BEAT_MS + local;
          setApi();
          paintTitle(titleLocal);
          raf = requestAnimationFrame(tick);
          return;
        }
        resolve();
      };
      raf = requestAnimationFrame(tick);
    });
  }

  async function start(opts?: {
    record?: boolean;
  }): Promise<{ fps: number; frames: string[] } | void> {
    stop();
    running = true;
    impactStarted = false;
    splashStarted = false;
    exploded = false;
    camPunch = 0;
    flashBurst = 0;
    explosionFlash = 0;
    hitstopMs = 0;
    impactBurst = null;
    clearDebris();
    roster = null;
    left = null;
    right = null;
    leftRest = [];
    rightRest = [];
    rings = [];
    beatCursor = 0;
    explosionOrigin = null;
    engine.gravity.scale = BASE_GRAVITY;
    phase = "splash";
    tMs = 0;
    resetCanvasFixed();
    ctx.setTransform(1, 0, 0, 1, 0, 0);

    // Шрифт title card
    await Promise.race([
      document.fonts?.load("800 92px Unbounded", "YOBBO").catch(() => undefined) ??
        Promise.resolve(),
      new Promise((r) => setTimeout(r, 300)),
    ]);

    const recording = !!opts?.record;
    const frames: string[] = [];

    const splashFrames = await runSplash(recording);
    if (recording) frames.push(...splashFrames);
    if (!running) {
      return recording ? { fps: RECORD_FPS, frames } : undefined;
    }

    if (recording) {
      frames.push(...(await runTimeline(true)));
    } else {
      await playRealtime();
    }

    running = false;
    phase = "done";
    setApi();
    return recording ? { fps: RECORD_FPS, frames } : undefined;
  }

  return { start, stop };
}

export function installAdProbeApi(canvas: HTMLCanvasElement): AdProbeApi {
  const scene = createAdProbeScene(canvas);
  const api: AdProbeApi = {
    ready: true,
    phase: "splash",
    t: 0,
    async record() {
      const out = await scene.start({ record: true });
      return out ?? { fps: RECORD_FPS, frames: [] };
    },
    async play() {
      await scene.start({ record: false });
    },
  };
  window.__RAGDOLL_AD__ = api;
  return api;
}
