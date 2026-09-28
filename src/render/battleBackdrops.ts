/**
 * Набор фонов арены. Один выбирается случайно на бой
 * и рисуется destination-over под телами.
 */

export const BATTLE_BACKDROP_IDS = [
  "orbital",
  "ember_sun",
  "ice_wake",
  "neon_grid",
  "acid_rain",
  "deep_abyss",
  "copper_storm",
  "dawn_horizon",
  "asteroid_belt",
  "signal_void",
] as const;

export type BattleBackdropId = (typeof BATTLE_BACKDROP_IDS)[number];

export type BattleBackdropMeta = {
  id: BattleBackdropId;
  /** Короткое имя для дебага / будущего UI. */
  label: string;
};

export const BATTLE_BACKDROPS: BattleBackdropMeta[] = [
  { id: "orbital", label: "Orbital drift" },
  { id: "ember_sun", label: "Ember sun" },
  { id: "ice_wake", label: "Ice wake" },
  { id: "neon_grid", label: "Neon grid" },
  { id: "acid_rain", label: "Acid rain" },
  { id: "deep_abyss", label: "Deep abyss" },
  { id: "copper_storm", label: "Copper storm" },
  { id: "dawn_horizon", label: "Dawn horizon" },
  { id: "asteroid_belt", label: "Asteroid belt" },
  { id: "signal_void", label: "Signal void" },
];

export function battleBackdropLabel(id: BattleBackdropId): string {
  return BATTLE_BACKDROPS.find((b) => b.id === id)?.label ?? id;
}

type Star = { u: number; v: number; z: number; warm: boolean };
type Streak = { u: number; v: number; len: number; z: number };
type Rock = { u: number; v: number; r: number; z: number };

type Field = {
  w: number;
  h: number;
  theme: BattleBackdropId;
  stars: Star[];
  streaks: Streak[];
  rocks: Rock[];
};

type ThemeStyle = {
  void: [string, string, string];
  nebulaA: string;
  nebulaB: string;
  glow: string;
  glowSoft: string;
  starCool: string;
  starWarm: string;
  streakNear: string;
  streakFar: string;
  driftX: number;
  driftY: number;
  vignette: number;
  /** extra features */
  grid?: boolean;
  scanlines?: boolean;
  aurora?: boolean;
  horizon?: boolean;
  rocks?: boolean;
  rain?: boolean;
};

const THEMES: Record<BattleBackdropId, ThemeStyle> = {
  orbital: {
    void: ["#05080f", "#0a1520", "#101018"],
    nebulaA: "rgba(34, 120, 140, 0.16)",
    nebulaB: "rgba(180, 110, 55, 0.10)",
    glow: "rgba(255, 186, 120, 0.14)",
    glowSoft: "rgba(255, 160, 90, 0.05)",
    starCool: "220, 235, 245",
    starWarm: "255, 210, 150",
    streakNear: "210, 230, 240",
    streakFar: "140, 180, 190",
    driftX: 14,
    driftY: 9,
    vignette: 0.45,
  },
  ember_sun: {
    void: ["#100806", "#1a0e0a", "#120c10"],
    nebulaA: "rgba(200, 80, 30, 0.18)",
    nebulaB: "rgba(120, 40, 20, 0.12)",
    glow: "rgba(255, 140, 60, 0.22)",
    glowSoft: "rgba(255, 90, 30, 0.08)",
    starCool: "255, 220, 190",
    starWarm: "255, 170, 90",
    streakNear: "255, 180, 120",
    streakFar: "180, 90, 50",
    driftX: 10,
    driftY: 6,
    vignette: 0.5,
  },
  ice_wake: {
    void: ["#060b12", "#0a1824", "#0c141c"],
    nebulaA: "rgba(90, 180, 220, 0.14)",
    nebulaB: "rgba(160, 210, 230, 0.08)",
    glow: "rgba(180, 230, 255, 0.12)",
    glowSoft: "rgba(120, 190, 230, 0.05)",
    starCool: "210, 240, 255",
    starWarm: "200, 230, 255",
    streakNear: "200, 235, 255",
    streakFar: "100, 160, 190",
    driftX: 18,
    driftY: 4,
    vignette: 0.4,
    aurora: true,
  },
  neon_grid: {
    void: ["#05070c", "#081018", "#0a0e14"],
    nebulaA: "rgba(20, 160, 170, 0.10)",
    nebulaB: "rgba(40, 90, 120, 0.08)",
    glow: "rgba(40, 220, 210, 0.10)",
    glowSoft: "rgba(20, 140, 150, 0.04)",
    starCool: "160, 240, 240",
    starWarm: "120, 220, 200",
    streakNear: "80, 220, 210",
    streakFar: "40, 120, 130",
    driftX: 8,
    driftY: 22,
    vignette: 0.55,
    grid: true,
  },
  acid_rain: {
    void: ["#070c08", "#0c1610", "#0a120e"],
    nebulaA: "rgba(80, 180, 70, 0.14)",
    nebulaB: "rgba(140, 160, 40, 0.08)",
    glow: "rgba(120, 220, 80, 0.10)",
    glowSoft: "rgba(90, 160, 50, 0.04)",
    starCool: "200, 240, 180",
    starWarm: "220, 255, 140",
    streakNear: "160, 240, 120",
    streakFar: "80, 140, 70",
    driftX: 6,
    driftY: 28,
    vignette: 0.48,
    rain: true,
  },
  deep_abyss: {
    void: ["#02060a", "#041018", "#06141c"],
    nebulaA: "rgba(20, 90, 120, 0.14)",
    nebulaB: "rgba(10, 60, 90, 0.10)",
    glow: "rgba(40, 180, 200, 0.10)",
    glowSoft: "rgba(20, 100, 130, 0.04)",
    starCool: "80, 220, 230",
    starWarm: "120, 255, 200",
    streakNear: "60, 180, 190",
    streakFar: "30, 90, 110",
    driftX: 5,
    driftY: 7,
    vignette: 0.6,
  },
  copper_storm: {
    void: ["#120c08", "#1a120c", "#14100e"],
    nebulaA: "rgba(180, 100, 50, 0.16)",
    nebulaB: "rgba(90, 50, 30, 0.12)",
    glow: "rgba(255, 200, 80, 0.10)",
    glowSoft: "rgba(200, 120, 40, 0.05)",
    starCool: "240, 210, 170",
    starWarm: "255, 180, 100",
    streakNear: "220, 160, 90",
    streakFar: "140, 80, 40",
    driftX: 20,
    driftY: 12,
    vignette: 0.5,
  },
  dawn_horizon: {
    void: ["#0a0c14", "#141820", "#1c1410"],
    nebulaA: "rgba(255, 140, 80, 0.12)",
    nebulaB: "rgba(80, 120, 160, 0.10)",
    glow: "rgba(255, 170, 90, 0.18)",
    glowSoft: "rgba(255, 120, 60, 0.06)",
    starCool: "230, 235, 245",
    starWarm: "255, 200, 140",
    streakNear: "255, 190, 140",
    streakFar: "120, 130, 150",
    driftX: 7,
    driftY: 3,
    vignette: 0.42,
    horizon: true,
  },
  asteroid_belt: {
    void: ["#07070c", "#0e1016", "#12141a"],
    nebulaA: "rgba(100, 110, 130, 0.10)",
    nebulaB: "rgba(160, 120, 70, 0.08)",
    glow: "rgba(200, 180, 140, 0.08)",
    glowSoft: "rgba(140, 120, 90, 0.04)",
    starCool: "220, 225, 230",
    starWarm: "255, 220, 170",
    streakNear: "200, 200, 210",
    streakFar: "120, 120, 130",
    driftX: 16,
    driftY: 10,
    vignette: 0.5,
    rocks: true,
  },
  signal_void: {
    void: ["#040806", "#07140e", "#0a100c"],
    nebulaA: "rgba(40, 160, 90, 0.10)",
    nebulaB: "rgba(180, 140, 40, 0.06)",
    glow: "rgba(80, 220, 120, 0.08)",
    glowSoft: "rgba(200, 160, 40, 0.04)",
    starCool: "120, 255, 160",
    starWarm: "255, 220, 80",
    streakNear: "100, 240, 140",
    streakFar: "60, 120, 80",
    driftX: 4,
    driftY: 14,
    vignette: 0.55,
    scanlines: true,
  },
};

function hash01(n: number): number {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

export function pickBattleBackdrop(rng: () => number = Math.random): BattleBackdropId {
  const i = Math.floor(rng() * BATTLE_BACKDROP_IDS.length) % BATTLE_BACKDROP_IDS.length;
  return BATTLE_BACKDROP_IDS[i]!;
}

export function isBattleBackdropId(value: string): value is BattleBackdropId {
  return (BATTLE_BACKDROP_IDS as readonly string[]).includes(value);
}

export function buildBattleBackdropField(
  w: number,
  h: number,
  theme: BattleBackdropId,
): Field {
  const area = Math.max(1, w * h);
  // Жёсткий потолок: каждый arc/stroke в afterRender ест кадр боя.
  const starCount = Math.min(90, Math.max(40, Math.floor(area / 18000)));
  const streakCount = Math.min(22, Math.max(10, Math.floor(area / 70000)));
  const rockCount =
    theme === "asteroid_belt"
      ? Math.min(14, Math.max(6, Math.floor(area / 90000)))
      : 0;
  const seed = BATTLE_BACKDROP_IDS.indexOf(theme) * 97;

  const stars: Star[] = [];
  for (let i = 0; i < starCount; i++) {
    stars.push({
      u: hash01(seed + i * 3.1 + 1),
      v: hash01(seed + i * 5.7 + 2),
      z: 0.15 + hash01(seed + i * 9.3 + 3) * 0.85,
      warm: hash01(seed + i * 11.1 + 4) > 0.78,
    });
  }
  const streaks: Streak[] = [];
  for (let i = 0; i < streakCount; i++) {
    streaks.push({
      u: hash01(seed + i * 17.3 + 50),
      v: hash01(seed + i * 19.7 + 51),
      len: 18 + hash01(seed + i * 23.1 + 52) * 54,
      z: 0.25 + hash01(seed + i * 29.9 + 53) * 0.75,
    });
  }
  const rocks: Rock[] = [];
  for (let i = 0; i < rockCount; i++) {
    rocks.push({
      u: hash01(seed + i * 41.3 + 80),
      v: hash01(seed + i * 43.7 + 81),
      r: 3 + hash01(seed + i * 47.1 + 82) * 14,
      z: 0.3 + hash01(seed + i * 53.9 + 83) * 0.7,
    });
  }
  return { w, h, theme, stars, streaks, rocks };
}

let cached: Field | null = null;

export function getBattleBackdropField(
  w: number,
  h: number,
  theme: BattleBackdropId,
): Field {
  const bw = Math.round(w);
  const bh = Math.round(h);
  if (!cached || cached.w !== bw || cached.h !== bh || cached.theme !== theme) {
    cached = buildBattleBackdropField(bw, bh, theme);
  }
  return cached;
}

export function resetBattleBackdropCache(): void {
  cached = null;
}

export function drawBattleBackdrop(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  nowMs: number,
  theme: BattleBackdropId,
): void {
  if (width < 2 || height < 2) return;
  const style = THEMES[theme];
  const field = getBattleBackdropField(width, height, theme);
  const t = nowMs * 0.001;
  const driftX = t * style.driftX;
  const driftY = t * style.driftY;
  const nearBoost = t * (style.driftX + style.driftY) * 0.7;

  ctx.save();

  const voidGrad = ctx.createLinearGradient(0, 0, width * 0.15, height);
  voidGrad.addColorStop(0, style.void[0]);
  voidGrad.addColorStop(0.55, style.void[1]);
  voidGrad.addColorStop(1, style.void[2]);
  ctx.fillStyle = voidGrad;
  ctx.fillRect(0, 0, width, height);

  if (style.horizon) {
    drawHorizon(ctx, width, height, t, style);
  } else {
    const sunX = width * 0.78 + Math.sin(t * 0.07) * 12;
    const sunY = height * (theme === "ember_sun" ? 0.35 : 0.22) + Math.cos(t * 0.05) * 10;
    const sunR = Math.max(width, height) * (theme === "ember_sun" ? 0.55 : 0.42);
    const sun = ctx.createRadialGradient(sunX, sunY, 0, sunX, sunY, sunR);
    sun.addColorStop(0, style.glow);
    sun.addColorStop(0.35, style.glowSoft);
    sun.addColorStop(1, "rgba(0,0,0,0)");
    ctx.fillStyle = sun;
    ctx.fillRect(0, 0, width, height);
  }

  ctx.globalCompositeOperation = "lighter";
  drawNebulaBlob(
    ctx,
    width * 0.28 + Math.sin(t * 0.11) * 20,
    height * 0.62,
    width * 0.55,
    height * 0.38,
    style.nebulaA,
  );
  drawNebulaBlob(
    ctx,
    width * 0.7 + Math.cos(t * 0.09) * 16,
    height * 0.45,
    width * 0.4,
    height * 0.32,
    style.nebulaB,
  );
  if (style.aurora) {
    drawAurora(ctx, width, height, t);
  }
  ctx.globalCompositeOperation = "source-over";

  if (style.grid) {
    drawNeonGrid(ctx, width, height, t);
  }

  if (style.rocks) {
    for (const rock of field.rocks) {
      const speed = 0.3 + rock.z * 1.2;
      const x =
        ((rock.u * width + driftX * speed) % (width + 60) + width + 60) %
          (width + 60) -
        30;
      const y =
        ((rock.v * height + driftY * speed * 0.6) % (height + 40) + height + 40) %
          (height + 40) -
        20;
      const rr = rock.r * (0.6 + rock.z);
      ctx.fillStyle = `rgba(40, 42, 48, ${0.35 + rock.z * 0.4})`;
      ctx.beginPath();
      ctx.moveTo(x, y - rr);
      ctx.lineTo(x + rr * 0.9, y - rr * 0.2);
      ctx.lineTo(x + rr * 0.5, y + rr * 0.8);
      ctx.lineTo(x - rr * 0.7, y + rr * 0.5);
      ctx.closePath();
      ctx.fill();
    }
  }

  for (const d of field.streaks) {
    const speed = 0.35 + d.z * 0.9;
    let x: number;
    let y: number;
    if (style.rain) {
      x = ((d.u * width + driftX * 0.3) % (width + 20)) - 10;
      y = ((d.v * height + nearBoost * (0.8 + d.z)) % (height + 60)) - 30;
      ctx.strokeStyle = `rgba(${style.streakNear}, ${0.05 + d.z * 0.12})`;
      ctx.lineWidth = 1 + d.z;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + d.len * 0.08, y + d.len * (0.9 + d.z * 0.4));
      ctx.stroke();
    } else {
      x = ((d.u * width + driftX * speed + nearBoost * d.z) % (width + 80)) - 40;
      y = ((d.v * height + driftY * speed * 0.7) % (height + 40)) - 20;
      const alpha = 0.04 + d.z * 0.1;
      ctx.strokeStyle =
        d.z > 0.6
          ? `rgba(${style.streakNear}, ${alpha})`
          : `rgba(${style.streakFar}, ${alpha * 0.85})`;
      ctx.lineWidth = 1 + d.z * 1.2;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x - d.len * (0.7 + d.z * 0.5), y + d.len * 0.35);
      ctx.stroke();
    }
  }

  for (const s of field.stars) {
    const speed = 0.2 + s.z * 1.1;
    const x =
      ((s.u * width + driftX * speed) % (width + 4) + width + 4) % (width + 4) - 2;
    const y =
      ((s.v * height + driftY * speed * 0.65) % (height + 4) + height + 4) %
        (height + 4) -
      2;
    const r = 0.55 + s.z * 1.65;
    const twinkle = 0.55 + 0.45 * Math.sin(t * (1.2 + s.z * 2.4) + s.u * 20);
    const a = (0.25 + s.z * 0.65) * twinkle;
    ctx.fillStyle = s.warm
      ? `rgba(${style.starWarm}, ${a})`
      : `rgba(${style.starCool}, ${a})`;
    // fillRect дешевле arc на сотнях точек/кадр.
    const d = Math.max(1, r * 1.6);
    ctx.fillRect(x - d * 0.5, y - d * 0.5, d, d);
  }

  // Copper storm: редкие вспышки.
  if (theme === "copper_storm") {
    const flash = Math.max(0, Math.sin(t * 3.7) * Math.sin(t * 1.3));
    if (flash > 0.92) {
      ctx.fillStyle = `rgba(255, 230, 160, ${(flash - 0.92) * 1.2})`;
      ctx.fillRect(0, 0, width, height);
    }
  }

  if (style.scanlines) {
    // Один полутон вместо сотен fillRect по строкам.
    ctx.fillStyle = "rgba(0, 0, 0, 0.14)";
    ctx.fillRect(0, 0, width, height);
    const sweepY = ((t * 40) % (height + 40)) - 20;
    const sweep = ctx.createLinearGradient(0, sweepY - 30, 0, sweepY + 30);
    sweep.addColorStop(0, "rgba(80, 220, 120, 0)");
    sweep.addColorStop(0.5, "rgba(80, 220, 120, 0.06)");
    sweep.addColorStop(1, "rgba(80, 220, 120, 0)");
    ctx.fillStyle = sweep;
    ctx.fillRect(0, 0, width, height);
  }

  const vig = ctx.createRadialGradient(
    width * 0.5,
    height * 0.48,
    Math.min(width, height) * 0.25,
    width * 0.5,
    height * 0.5,
    Math.max(width, height) * 0.72,
  );
  vig.addColorStop(0, "rgba(0,0,0,0)");
  vig.addColorStop(1, `rgba(0,0,0,${style.vignette})`);
  ctx.fillStyle = vig;
  ctx.fillRect(0, 0, width, height);

  ctx.restore();
}

function drawNebulaBlob(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  rx: number,
  ry: number,
  color: string,
): void {
  ctx.save();
  ctx.translate(cx, cy);
  ctx.scale(rx, ry);
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 1);
  g.addColorStop(0, color);
  g.addColorStop(1, "rgba(0,0,0,0)");
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(0, 0, 1, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function drawAurora(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  t: number,
): void {
  for (let i = 0; i < 3; i++) {
    const y = height * (0.18 + i * 0.12) + Math.sin(t * 0.4 + i) * 12;
    const g = ctx.createLinearGradient(0, y, width, y + 40);
    g.addColorStop(0, "rgba(80, 200, 220, 0)");
    g.addColorStop(0.4, `rgba(100, 210, 230, ${0.05 + i * 0.02})`);
    g.addColorStop(0.7, `rgba(160, 230, 210, ${0.04 + i * 0.015})`);
    g.addColorStop(1, "rgba(80, 200, 220, 0)");
    ctx.fillStyle = g;
    ctx.fillRect(0, y - 20, width, 50);
  }
}

function drawNeonGrid(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  t: number,
): void {
  const horizon = height * 0.52;
  ctx.strokeStyle = "rgba(40, 200, 190, 0.14)";
  ctx.lineWidth = 1;
  const scroll = (t * 40) % 36;
  for (let i = 0; i < 14; i++) {
    const p = (i + scroll / 36) / 14;
    const y = horizon + Math.pow(p, 1.6) * (height - horizon);
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
    ctx.stroke();
  }
  const vanishX = width * 0.5;
  for (let i = -10; i <= 10; i++) {
    const x0 = vanishX + i * 70;
    ctx.beginPath();
    ctx.moveTo(vanishX, horizon);
    ctx.lineTo(x0 + (i >= 0 ? width * 0.2 : -width * 0.2), height);
    ctx.stroke();
  }
  // Горизонт-линия.
  ctx.strokeStyle = "rgba(60, 230, 220, 0.28)";
  ctx.beginPath();
  ctx.moveTo(0, horizon);
  ctx.lineTo(width, horizon);
  ctx.stroke();
}

function drawHorizon(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  t: number,
  style: ThemeStyle,
): void {
  const y = height * 0.62 + Math.sin(t * 0.05) * 4;
  const band = ctx.createLinearGradient(0, y - height * 0.35, 0, height);
  band.addColorStop(0, "rgba(0,0,0,0)");
  band.addColorStop(0.45, style.glowSoft);
  band.addColorStop(0.62, style.glow);
  band.addColorStop(0.7, "rgba(20, 16, 18, 0.85)");
  band.addColorStop(1, style.void[2]);
  ctx.fillStyle = band;
  ctx.fillRect(0, 0, width, height);

  // Силуэт «планеты» / края горизонта.
  ctx.fillStyle = "rgba(8, 10, 14, 0.9)";
  ctx.beginPath();
  ctx.ellipse(width * 0.5, height * 1.15, width * 0.85, height * 0.55, 0, Math.PI, 0, true);
  ctx.fill();
}
