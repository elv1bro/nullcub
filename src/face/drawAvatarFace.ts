import type { EmotionId } from "./emotions";
import type { FaceOverlayEffectId } from "./faceEffects";
import { drawFaceOverlayEffect } from "./faceEffects";
import { HEAD_FACE_CLIP } from "./drawFace";
import type {
  AvatarFacePreset,
  AvatarKind,
  HumanHairStyle,
} from "./avatarPresets";
import type Matter from "matter-js";
import { worldToCanvas } from "@/render/worldToCanvas";
import { darken, lighten, mixHex, withAlpha } from "./color";

type Ctx = CanvasRenderingContext2D;

const TAU = Math.PI * 2;

/* ── объёмные примитивы ── */

/** Шар с бликом сверху-слева и тенью к краю. */
function shadedDisc(
  ctx: Ctx,
  x: number,
  y: number,
  rad: number,
  base: string,
  dark: string,
): void {
  const g = ctx.createRadialGradient(
    x - rad * 0.32,
    y - rad * 0.38,
    rad * 0.08,
    x,
    y,
    rad,
  );
  g.addColorStop(0, lighten(base, 0.22));
  g.addColorStop(0.55, base);
  g.addColorStop(1, dark);
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(x, y, rad, 0, TAU);
  ctx.fill();
}

/** Мягкий специальный блик. */
function gloss(ctx: Ctx, x: number, y: number, rad: number, alpha = 0.3): void {
  const g = ctx.createRadialGradient(
    x - rad * 0.36,
    y - rad * 0.45,
    0,
    x - rad * 0.36,
    y - rad * 0.45,
    rad * 0.55,
  );
  g.addColorStop(0, `rgba(255,255,255,${alpha})`);
  g.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(x, y, rad, 0, TAU);
  ctx.fill();
}

/** База головы: шар + затемнение низа + rim-свет. */
function headBase(ctx: Ctx, r: number, base: string, dark: string): void {
  shadedDisc(ctx, 0, 0, r, base, dark);
  ctx.save();
  ctx.beginPath();
  ctx.arc(0, 0, r, 0, TAU);
  ctx.clip();
  const ao = ctx.createRadialGradient(0, r * 0.5, r * 0.35, 0, r * 0.5, r * 1.1);
  ao.addColorStop(0, "rgba(0,0,0,0)");
  ao.addColorStop(1, "rgba(0,0,0,0.26)");
  ctx.fillStyle = ao;
  ctx.fillRect(-r, -r, r * 2, r * 2);
  ctx.strokeStyle = "rgba(255,255,255,0.22)";
  ctx.lineWidth = r * 0.07;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.95, Math.PI * 1.1, Math.PI * 1.5);
  ctx.stroke();
  ctx.restore();
  gloss(ctx, 0, 0, r, 0.24);
}

function roundRectPath(
  ctx: Ctx,
  x: number,
  y: number,
  w: number,
  h: number,
  rad: number,
): void {
  const rr = Math.min(rad, w / 2, h / 2);
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x, y + h, rr);
  ctx.arcTo(x, y + h, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
}

function star4(ctx: Ctx, x: number, y: number, rad: number, color: string): void {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(x, y - rad);
  ctx.quadraticCurveTo(x, y, x + rad, y);
  ctx.quadraticCurveTo(x, y, x, y + rad);
  ctx.quadraticCurveTo(x, y, x - rad, y);
  ctx.quadraticCurveTo(x, y, x, y - rad);
  ctx.fill();
}

/* ── глаза ── */

interface EyeSpec {
  dx: number;
  y: number;
  size: number;
  iris: string;
  white?: string;
  pupil?: "round" | "slit";
  /** Цвет века для злого прищура (кожа/шерсть). */
  lid?: string;
  /** Цвет закрытых глаз / боли. */
  ink?: string;
  /** Улыбка закрывает глаза дугой ∩. */
  smileClosed?: boolean;
  lash?: boolean;
}

function drawEyeOne(
  ctx: Ctx,
  r: number,
  e: EmotionId,
  s: EyeSpec,
  side: -1 | 1,
  sizeMul = 1,
  droop = 0,
): void {
  const ink = s.ink ?? "#241812";
  const cx = side * s.dx * r;
  const cy = (s.y + droop) * r;
  const er = s.size * r * sizeMul;

  if (e === "pain") {
    ctx.strokeStyle = ink;
    ctx.lineWidth = er * 0.42;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(cx - side * er * 0.75, cy - er * 0.6);
    ctx.lineTo(cx + side * er * 0.55, cy);
    ctx.lineTo(cx - side * er * 0.75, cy + er * 0.6);
    ctx.stroke();
    return;
  }

  if (e === "smile" && s.smileClosed !== false) {
    ctx.strokeStyle = ink;
    ctx.lineWidth = er * 0.42;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.arc(cx, cy + er * 0.3, er * 0.85, Math.PI * 1.05, Math.PI * 1.95);
    ctx.stroke();
    if (s.lash) {
      ctx.lineWidth = er * 0.3;
      ctx.beginPath();
      ctx.moveTo(cx + side * er * 0.8, cy - er * 0.25);
      ctx.lineTo(cx + side * er * 1.25, cy - er * 0.55);
      ctx.stroke();
    }
    return;
  }

  const wide = e === "scared" || e === "surprised";
  const rx = er * (wide ? 1.22 : 1);
  const ry = er * (wide ? 1.4 : 1.1);

  ctx.fillStyle = s.white ?? "#fdfdfd";
  ctx.beginPath();
  ctx.ellipse(cx, cy, rx, ry, 0, 0, TAU);
  ctx.fill();

  const ir = er * (wide ? 0.48 : e === "angry" ? 0.56 : 0.62);
  const g = ctx.createRadialGradient(
    cx - ir * 0.25,
    cy - ir * 0.3,
    ir * 0.12,
    cx,
    cy,
    ir,
  );
  g.addColorStop(0, lighten(s.iris, 0.35));
  g.addColorStop(0.62, s.iris);
  g.addColorStop(1, darken(s.iris, 0.45));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(cx, cy, ir, 0, TAU);
  ctx.fill();

  ctx.fillStyle = "#100d0b";
  ctx.beginPath();
  if (s.pupil === "slit") {
    ctx.ellipse(cx, cy, ir * 0.24, ir * 0.82, 0, 0, TAU);
  } else {
    ctx.arc(cx, cy, ir * (wide ? 0.4 : 0.5), 0, TAU);
  }
  ctx.fill();

  ctx.fillStyle = "rgba(255,255,255,0.95)";
  ctx.beginPath();
  ctx.arc(cx - ir * 0.32, cy - ir * 0.35, ir * 0.24, 0, TAU);
  ctx.fill();
  ctx.fillStyle = "rgba(255,255,255,0.4)";
  ctx.beginPath();
  ctx.arc(cx + ir * 0.3, cy + ir * 0.3, ir * 0.12, 0, TAU);
  ctx.fill();

  if (e === "angry" && s.lid) {
    ctx.fillStyle = s.lid;
    ctx.beginPath();
    ctx.moveTo(cx + side * rx * 1.3, cy - ry * 1.4);
    ctx.lineTo(cx + side * rx * 1.3, cy - ry * 0.72);
    ctx.lineTo(cx - side * rx * 1.3, cy - ry * 0.02);
    ctx.lineTo(cx - side * rx * 1.3, cy - ry * 1.4);
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = withAlpha(ink, 0.7);
    ctx.lineWidth = er * 0.18;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(cx + side * rx * 0.95, cy - ry * 0.75);
    ctx.lineTo(cx - side * rx * 1.02, cy - ry * 0.02);
    ctx.stroke();
  }

  if (s.lash) {
    ctx.strokeStyle = ink;
    ctx.lineWidth = er * 0.16;
    ctx.lineCap = "round";
    for (const a of [0.1, 0.32] as const) {
      ctx.beginPath();
      ctx.moveTo(cx + side * rx * (0.85 - a * 0.3), cy - ry * (0.75 + a));
      ctx.lineTo(cx + side * rx * (1.25 - a * 0.2), cy - ry * (0.95 + a * 1.4));
      ctx.stroke();
    }
  }
}

function drawEyePair(ctx: Ctx, r: number, e: EmotionId, s: EyeSpec): void {
  drawEyeOne(ctx, r, e, s, -1);
  drawEyeOne(ctx, r, e, s, 1);
}

/* ── брови ── */

interface BrowSpec {
  color: string;
  y: number;
  dx: number;
  w: number;
  thick: number;
}

function drawBrowPair(ctx: Ctx, r: number, e: EmotionId, b: BrowSpec): void {
  let inner = 0;
  let outer = -0.01;
  let arch = 0.05;
  if (e === "angry") {
    inner = 0.09;
    outer = -0.05;
    arch = 0;
  } else if (e === "scared" || e === "surprised") {
    inner = -0.09;
    outer = -0.05;
    arch = 0.09;
  } else if (e === "pain") {
    inner = -0.06;
    outer = 0.02;
    arch = 0.02;
  } else if (e === "smile") {
    inner = -0.02;
    arch = 0.07;
  }
  ctx.strokeStyle = b.color;
  ctx.lineWidth = r * b.thick;
  ctx.lineCap = "round";
  const by = b.y * r;
  for (const side of [-1, 1] as const) {
    ctx.beginPath();
    ctx.moveTo(side * (b.dx + b.w) * r, by + outer * r);
    ctx.quadraticCurveTo(
      side * b.dx * r,
      by - arch * r,
      side * (b.dx - b.w) * r,
      by + inner * r,
    );
    ctx.stroke();
  }
}

/* ── рты ── */

interface MouthSpec {
  y: number;
  w: number;
  lip: string;
  inner?: string;
  teeth?: boolean;
  tongue?: boolean;
}

function drawMouthPlain(ctx: Ctx, r: number, e: EmotionId, m: MouthSpec): void {
  const y = m.y * r;
  const w = m.w * r;
  const inner = m.inner ?? darken(m.lip, 0.5);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  if (e === "smile") {
    const sw = w * 1.5;
    const path = (): void => {
      ctx.beginPath();
      ctx.moveTo(-sw, y - r * 0.01);
      ctx.quadraticCurveTo(0, y + r * 0.05, sw, y - r * 0.01);
      ctx.quadraticCurveTo(0, y + r * 0.27, -sw, y - r * 0.01);
      ctx.closePath();
    };
    path();
    ctx.fillStyle = inner;
    ctx.fill();
    ctx.save();
    ctx.clip();
    if (m.teeth !== false) {
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(-sw, y - r * 0.02, sw * 2, r * 0.08);
    }
    if (m.tongue) {
      ctx.fillStyle = withAlpha("#ff7d8f", 0.9);
      ctx.beginPath();
      ctx.ellipse(0, y + r * 0.18, sw * 0.5, r * 0.08, 0, 0, TAU);
      ctx.fill();
    }
    ctx.restore();
    path();
    ctx.strokeStyle = darken(m.lip, 0.25);
    ctx.lineWidth = r * 0.028;
    ctx.stroke();
    return;
  }

  if (e === "pain") {
    const h = r * 0.1;
    ctx.beginPath();
    roundRectPath(ctx, -w * 1.2, y - h / 2, w * 2.4, h, h * 0.4);
    ctx.fillStyle = "#f3f0ea";
    ctx.fill();
    ctx.strokeStyle = darken(m.lip, 0.25);
    ctx.lineWidth = r * 0.03;
    ctx.stroke();
    ctx.strokeStyle = "rgba(0,0,0,0.24)";
    ctx.lineWidth = r * 0.014;
    ctx.beginPath();
    for (const fx of [-0.55, 0, 0.55] as const) {
      ctx.moveTo(w * 1.2 * fx, y - h * 0.4);
      ctx.lineTo(w * 1.2 * fx, y + h * 0.4);
    }
    ctx.stroke();
    return;
  }

  if (e === "scared" || e === "surprised") {
    const path = (): void => {
      ctx.beginPath();
      ctx.ellipse(0, y + r * 0.02, w * 0.55, w * 0.7, 0, 0, TAU);
    };
    path();
    ctx.fillStyle = inner;
    ctx.fill();
    if (m.teeth !== false) {
      ctx.save();
      path();
      ctx.clip();
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(-w, y - w * 0.7, w * 2, w * 0.28);
      ctx.restore();
    }
    path();
    ctx.strokeStyle = darken(m.lip, 0.25);
    ctx.lineWidth = r * 0.026;
    ctx.stroke();
    return;
  }

  if (e === "angry") {
    ctx.strokeStyle = darken(m.lip, 0.25);
    ctx.lineWidth = r * 0.04;
    ctx.beginPath();
    ctx.moveTo(-w * 1.1, y + r * 0.03);
    ctx.quadraticCurveTo(0, y - r * 0.06, w * 1.1, y + r * 0.03);
    ctx.stroke();
    return;
  }

  ctx.strokeStyle = darken(m.lip, 0.18);
  ctx.lineWidth = r * 0.036;
  ctx.beginPath();
  ctx.moveTo(-w * 0.85, y);
  ctx.quadraticCurveTo(0, y + r * 0.05, w * 0.85, y);
  ctx.stroke();
}

/** Кошачий ω-рот с вариантами эмоций. */
function drawMouthCat(
  ctx: Ctx,
  r: number,
  e: EmotionId,
  opts: { y: number; ink: string; fangs?: boolean },
): void {
  const y = opts.y * r;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  if (e === "scared" || e === "surprised") {
    ctx.fillStyle = darken(opts.ink, 0.1);
    ctx.beginPath();
    ctx.ellipse(0, y + r * 0.03, r * 0.08, r * 0.1, 0, 0, TAU);
    ctx.fill();
    return;
  }
  if (e === "pain") {
    ctx.strokeStyle = opts.ink;
    ctx.lineWidth = r * 0.035;
    ctx.beginPath();
    ctx.moveTo(-r * 0.16, y + r * 0.02);
    ctx.lineTo(-r * 0.06, y - r * 0.03);
    ctx.lineTo(r * 0.05, y + r * 0.04);
    ctx.lineTo(r * 0.16, y - r * 0.02);
    ctx.stroke();
    return;
  }
  if (e === "angry") {
    const path = (): void => {
      ctx.beginPath();
      ctx.moveTo(-r * 0.16, y - r * 0.02);
      ctx.quadraticCurveTo(0, y + r * 0.1, r * 0.16, y - r * 0.02);
      ctx.quadraticCurveTo(0, y + r * 0.02, -r * 0.16, y - r * 0.02);
      ctx.closePath();
    };
    path();
    ctx.fillStyle = darken(opts.ink, 0.1);
    ctx.fill();
    if (opts.fangs) {
      ctx.fillStyle = "#ffffff";
      for (const side of [-1, 1] as const) {
        ctx.beginPath();
        ctx.moveTo(side * r * 0.13 - r * 0.03, y - r * 0.01);
        ctx.lineTo(side * r * 0.13 + r * 0.03, y - r * 0.01);
        ctx.lineTo(side * r * 0.13, y + r * 0.09);
        ctx.closePath();
        ctx.fill();
      }
    }
    return;
  }
  // neutral / smile: ω
  const deep = e === "smile" ? 1.25 : 1;
  ctx.strokeStyle = opts.ink;
  ctx.lineWidth = r * 0.035;
  ctx.beginPath();
  ctx.arc(-r * 0.09, y - r * 0.03, r * 0.09 * deep, 0.15 * Math.PI, 0.85 * Math.PI);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(r * 0.09, y - r * 0.03, r * 0.09 * deep, 0.15 * Math.PI, 0.85 * Math.PI);
  ctx.stroke();
  if (e === "smile") {
    ctx.fillStyle = "#ff8fa3";
    ctx.beginPath();
    ctx.ellipse(0, y + r * 0.1, r * 0.06, r * 0.07, 0, 0, TAU);
    ctx.fill();
  }
}

/** Клюв (сова, пингвин). */
function drawBeak(
  ctx: Ctx,
  r: number,
  e: EmotionId,
  opts: { y: number; w: number; color: string },
): void {
  const y = opts.y * r;
  const w = opts.w * r;
  const open = e === "scared" || e === "surprised";
  const g = ctx.createLinearGradient(0, y - w, 0, y + w);
  g.addColorStop(0, lighten(opts.color, 0.25));
  g.addColorStop(1, darken(opts.color, 0.3));
  ctx.fillStyle = g;
  if (open) {
    ctx.beginPath();
    ctx.ellipse(0, y + w * 0.35, w * 0.55, w * 0.6, 0, 0, TAU);
    ctx.fillStyle = "#2a1a12";
    ctx.fill();
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.moveTo(-w * 0.6, y - w * 0.4);
    ctx.lineTo(w * 0.6, y - w * 0.4);
    ctx.lineTo(0, y + w * 0.25);
    ctx.closePath();
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(-w * 0.4, y + w * 0.75);
    ctx.lineTo(w * 0.4, y + w * 0.75);
    ctx.lineTo(0, y + w * 1.1);
    ctx.closePath();
    ctx.fill();
    return;
  }
  ctx.beginPath();
  ctx.moveTo(0, y - w * 0.5);
  ctx.lineTo(w * 0.6, y);
  ctx.quadraticCurveTo(w * 0.2, y + w * 0.5, 0, y + w * 0.9);
  ctx.quadraticCurveTo(-w * 0.2, y + w * 0.5, -w * 0.6, y);
  ctx.closePath();
  ctx.fill();
  ctx.strokeStyle = withAlpha(darken(opts.color, 0.5), 0.6);
  ctx.lineWidth = r * 0.02;
  ctx.beginPath();
  ctx.moveTo(0, y - w * 0.35);
  ctx.lineTo(0, y + w * 0.55);
  ctx.stroke();
}

/* ── мелкие детали ── */

function triNose(ctx: Ctx, r: number, y: number, size: number, color: string): void {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(-size * r, y * r - size * r * 0.5);
  ctx.lineTo(size * r, y * r - size * r * 0.5);
  ctx.quadraticCurveTo(size * r * 0.7, y * r + size * r * 0.6, 0, y * r + size * r);
  ctx.quadraticCurveTo(-size * r * 0.7, y * r + size * r * 0.6, -size * r, y * r - size * r * 0.5);
  ctx.fill();
  ctx.fillStyle = "rgba(255,255,255,0.4)";
  ctx.beginPath();
  ctx.arc(-size * r * 0.3, y * r - size * r * 0.15, size * r * 0.22, 0, TAU);
  ctx.fill();
}

function ovalNose(ctx: Ctx, r: number, y: number, size: number, color: string): void {
  shadedDisc(ctx, 0, y * r, size * r, color, darken(color, 0.4));
  ctx.fillStyle = "rgba(255,255,255,0.35)";
  ctx.beginPath();
  ctx.ellipse(-size * r * 0.3, y * r - size * r * 0.3, size * r * 0.3, size * r * 0.2, -0.4, 0, TAU);
  ctx.fill();
}

function blush(ctx: Ctx, r: number, color = "#ff8fa3", alpha = 0.3, y = 0.18, dx = 0.52): void {
  ctx.fillStyle = withAlpha(color, alpha);
  ctx.beginPath();
  ctx.ellipse(-dx * r, y * r, r * 0.13, r * 0.08, 0, 0, TAU);
  ctx.ellipse(dx * r, y * r, r * 0.13, r * 0.08, 0, 0, TAU);
  ctx.fill();
}

/** Усы, выходящие за круг головы. */
function whiskers(ctx: Ctx, r: number, color: string, y = 0.3): void {
  ctx.strokeStyle = color;
  ctx.lineWidth = r * 0.022;
  ctx.lineCap = "round";
  for (const side of [-1, 1] as const) {
    for (const [dy, tilt] of [
      [-0.08, -0.12],
      [0, 0],
      [0.08, 0.12],
    ] as const) {
      ctx.beginPath();
      ctx.moveTo(side * r * 0.52, (y + dy) * r);
      ctx.quadraticCurveTo(
        side * r * 0.95,
        (y + dy + tilt * 0.5) * r,
        side * r * 1.28,
        (y + dy + tilt) * r,
      );
      ctx.stroke();
    }
  }
}

/** Треугольное ухо с внутренней частью. */
function earTriangle(
  ctx: Ctx,
  r: number,
  side: -1 | 1,
  o: {
    inX: number;
    inY: number;
    outX: number;
    outY: number;
    tipX: number;
    tipY: number;
    fur: string;
    dark: string;
    inner?: string;
    tipColor?: string;
  },
): void {
  const sx = (v: number): number => side * v * r;
  const g = ctx.createLinearGradient(0, o.tipY * r, 0, o.inY * r);
  g.addColorStop(0, lighten(o.fur, 0.12));
  g.addColorStop(1, o.dark);
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.moveTo(sx(o.inX), o.inY * r);
  ctx.quadraticCurveTo(sx(o.tipX * 0.85), o.tipY * r * 0.9, sx(o.tipX), o.tipY * r);
  ctx.quadraticCurveTo(sx(o.outX * 1.05), o.outY * r * 0.92, sx(o.outX), o.outY * r);
  ctx.closePath();
  ctx.fill();
  if (o.inner) {
    ctx.fillStyle = o.inner;
    ctx.beginPath();
    ctx.moveTo(sx(o.inX * 0.8 + o.tipX * 0.2), (o.inY * 0.75 + o.tipY * 0.25) * r);
    ctx.lineTo(sx(o.tipX * 0.94), o.tipY * r * 0.94);
    ctx.lineTo(sx(o.outX * 0.8 + o.tipX * 0.2), (o.outY * 0.75 + o.tipY * 0.25) * r);
    ctx.closePath();
    ctx.fill();
  }
  if (o.tipColor) {
    ctx.fillStyle = o.tipColor;
    ctx.beginPath();
    ctx.moveTo(sx(o.inX * 0.35 + o.tipX * 0.65), (o.inY * 0.35 + o.tipY * 0.65) * r);
    ctx.quadraticCurveTo(sx(o.tipX * 0.9), o.tipY * r * 0.92, sx(o.tipX), o.tipY * r);
    ctx.quadraticCurveTo(sx(o.outX * 0.4 + o.tipX * 0.6), (o.outY * 0.4 + o.tipY * 0.6) * r, sx(o.outX * 0.35 + o.tipX * 0.65), (o.outY * 0.35 + o.tipY * 0.65) * r);
    ctx.closePath();
    ctx.fill();
  }
}

/* ── звери ── */

function paintCat(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  for (const side of [-1, 1] as const) {
    earTriangle(ctx, r, side, {
      inX: 0.25, inY: -0.84, outX: 0.74, outY: -0.52, tipX: 0.72, tipY: -1.26,
      fur: p.primary, dark: p.shade, inner: "#f7a8b8",
    });
  }
  headBase(ctx, r, p.primary, p.shade);
  // полоски на лбу и щеках
  ctx.strokeStyle = withAlpha(p.accent2, 0.85);
  ctx.lineWidth = r * 0.075;
  ctx.lineCap = "round";
  for (const x of [-0.22, 0, 0.22] as const) {
    ctx.beginPath();
    ctx.moveTo(x * r, -r * 0.92 + Math.abs(x) * r * 0.2);
    ctx.lineTo(x * r * 1.15, -r * 0.6 + Math.abs(x) * r * 0.15);
    ctx.stroke();
  }
  for (const side of [-1, 1] as const) {
    ctx.beginPath();
    ctx.moveTo(side * r * 0.95, r * 0.02);
    ctx.lineTo(side * r * 0.68, r * 0.08);
    ctx.stroke();
  }
  // морда
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  ctx.ellipse(-r * 0.17, r * 0.42, r * 0.28, r * 0.24, 0, 0, TAU);
  ctx.ellipse(r * 0.17, r * 0.42, r * 0.28, r * 0.24, 0, 0, TAU);
  ctx.fill();
  drawEyePair(ctx, r, e, {
    dx: 0.34, y: -0.1, size: 0.17, iris: p.eyes, pupil: "slit",
    lid: p.primary, ink: "#2a1a10",
  });
  triNose(ctx, r, 0.26, 0.07, "#f56d8a");
  drawMouthCat(ctx, r, e, { y: 0.44, ink: "#5a3418", fangs: true });
  whiskers(ctx, r, withAlpha("#ffffff", 0.75), 0.34);
}

function paintFox(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  for (const side of [-1, 1] as const) {
    earTriangle(ctx, r, side, {
      inX: 0.2, inY: -0.86, outX: 0.78, outY: -0.42, tipX: 0.64, tipY: -1.4,
      fur: p.primary, dark: p.shade, tipColor: p.accent2,
    });
  }
  headBase(ctx, r, p.primary, p.shade);
  // белые щёки-пух с рваным краем
  ctx.fillStyle = p.accent;
  for (const side of [-1, 1] as const) {
    ctx.beginPath();
    ctx.moveTo(side * r * 0.9, r * 0.05);
    ctx.lineTo(side * r * 0.55, -r * 0.1);
    ctx.lineTo(side * r * 0.52, r * 0.18);
    ctx.lineTo(side * r * 0.2, r * 0.28);
    ctx.quadraticCurveTo(side * r * 0.55, r * 0.72, side * r * 0.88, r * 0.4);
    ctx.closePath();
    ctx.fill();
  }
  ctx.beginPath();
  ctx.ellipse(0, r * 0.52, r * 0.32, r * 0.34, 0, 0, TAU);
  ctx.fill();
  drawEyePair(ctx, r, e, {
    dx: 0.34, y: -0.14, size: 0.14, iris: p.eyes, pupil: "slit",
    lid: p.primary, ink: "#33200f",
  });
  triNose(ctx, r, 0.28, 0.065, "#3a2417");
  drawMouthCat(ctx, r, e, { y: 0.46, ink: "#4a2c14" });
  blush(ctx, r, "#ff9d6b", 0.35, 0.1, 0.55);
}

function paintPanda(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  shadedDisc(ctx, -r * 0.62, -r * 0.72, r * 0.33, p.accent, darken(p.accent, 0.3));
  shadedDisc(ctx, r * 0.62, -r * 0.72, r * 0.33, p.accent, darken(p.accent, 0.3));
  headBase(ctx, r, p.primary, p.shade);
  // пятна вокруг глаз
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  ctx.ellipse(-r * 0.33, -r * 0.06, r * 0.23, r * 0.29, 0.35, 0, TAU);
  ctx.ellipse(r * 0.33, -r * 0.06, r * 0.23, r * 0.29, -0.35, 0, TAU);
  ctx.fill();
  drawEyePair(ctx, r, e, {
    dx: 0.32, y: -0.08, size: 0.1, iris: p.eyes,
    lid: p.accent, ink: "#f3efe8", white: "#f7f3ee",
  });
  ovalNose(ctx, r, 0.24, 0.08, "#2b2724");
  drawMouthPlain(ctx, r, e, { y: 0.42, w: 0.14, lip: "#3a3430", teeth: false, tongue: true });
  blush(ctx, r, "#ff8fa3", 0.4, 0.22, 0.56);
}

function paintShiba(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  for (const side of [-1, 1] as const) {
    earTriangle(ctx, r, side, {
      inX: 0.3, inY: -0.82, outX: 0.8, outY: -0.42, tipX: 0.72, tipY: -1.18,
      fur: p.primary, dark: p.shade, inner: "#fde3cf",
    });
  }
  headBase(ctx, r, p.primary, p.shade);
  // белая маска: щеки + морда
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  ctx.ellipse(-r * 0.42, r * 0.3, r * 0.34, r * 0.36, 0.3, 0, TAU);
  ctx.ellipse(r * 0.42, r * 0.3, r * 0.34, r * 0.36, -0.3, 0, TAU);
  ctx.ellipse(0, r * 0.4, r * 0.34, r * 0.4, 0, 0, TAU);
  ctx.fill();
  // брови-точки
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  ctx.ellipse(-r * 0.3, -r * 0.38, r * 0.09, r * 0.06, 0, 0, TAU);
  ctx.ellipse(r * 0.3, -r * 0.38, r * 0.09, r * 0.06, 0, 0, TAU);
  ctx.fill();
  drawEyePair(ctx, r, e, {
    dx: 0.32, y: -0.12, size: 0.11, iris: p.eyes,
    lid: p.primary, ink: "#33241a",
  });
  ovalNose(ctx, r, 0.2, 0.07, "#221812");
  drawMouthPlain(ctx, r, e, { y: 0.44, w: 0.15, lip: "#4a3020", teeth: false, tongue: true });
  blush(ctx, r, "#ff9d6b", 0.4, 0.14, 0.58);
}

function paintBunny(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  for (const side of [-1, 1] as const) {
    const x0 = side * r * 0.34;
    const x1 = side * r * 0.52;
    ctx.strokeStyle = p.primary;
    ctx.lineWidth = r * 0.4;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(x0, -r * 0.72);
    ctx.quadraticCurveTo(side * r * 0.4, -r * 1.15, x1, -r * 1.42);
    ctx.stroke();
    ctx.strokeStyle = p.accent;
    ctx.lineWidth = r * 0.18;
    ctx.beginPath();
    ctx.moveTo(x0 + side * r * 0.01, -r * 0.82);
    ctx.quadraticCurveTo(side * r * 0.42, -r * 1.14, x1, -r * 1.36);
    ctx.stroke();
  }
  headBase(ctx, r, p.primary, p.shade);
  drawEyePair(ctx, r, e, {
    dx: 0.33, y: -0.12, size: 0.13, iris: p.eyes,
    lid: p.primary, ink: "#3a2e28",
  });
  triNose(ctx, r, 0.2, 0.055, "#f56d8a");
  drawMouthCat(ctx, r, e, { y: 0.36, ink: "#5a4438" });
  // передние зубы
  if (e !== "pain") {
    ctx.fillStyle = "#ffffff";
    ctx.strokeStyle = "rgba(0,0,0,0.18)";
    ctx.lineWidth = r * 0.014;
    ctx.beginPath();
    roundRectPath(ctx, -r * 0.09, r * 0.46, r * 0.09, r * 0.13, r * 0.03);
    ctx.fill();
    ctx.stroke();
    ctx.beginPath();
    roundRectPath(ctx, 0, r * 0.46, r * 0.09, r * 0.13, r * 0.03);
    ctx.fill();
    ctx.stroke();
  }
  blush(ctx, r, "#ff8fa3", 0.35, 0.16, 0.52);
  whiskers(ctx, r, withAlpha("#8a7a70", 0.6), 0.24);
}

function paintBear(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  for (const side of [-1, 1] as const) {
    shadedDisc(ctx, side * r * 0.6, -r * 0.7, r * 0.29, p.primary, p.shade);
    ctx.fillStyle = p.accent;
    ctx.beginPath();
    ctx.arc(side * r * 0.57, -r * 0.68, r * 0.14, 0, TAU);
    ctx.fill();
  }
  headBase(ctx, r, p.primary, p.shade);
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  ctx.ellipse(0, r * 0.38, r * 0.35, r * 0.28, 0, 0, TAU);
  ctx.fill();
  drawEyePair(ctx, r, e, {
    dx: 0.32, y: -0.14, size: 0.1, iris: p.eyes,
    lid: p.primary, ink: "#2f1d0e",
  });
  ovalNose(ctx, r, 0.24, 0.09, "#2f1d0e");
  drawMouthPlain(ctx, r, e, { y: 0.5, w: 0.14, lip: "#3f2812", teeth: false });
  // шрам над глазом
  ctx.strokeStyle = withAlpha(p.shade, 0.9);
  ctx.lineWidth = r * 0.03;
  ctx.beginPath();
  ctx.moveTo(r * 0.18, -r * 0.44);
  ctx.lineTo(r * 0.44, -r * 0.3);
  ctx.moveTo(r * 0.36, -r * 0.44);
  ctx.lineTo(r * 0.26, -r * 0.28);
  ctx.stroke();
}

function paintTiger(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  for (const side of [-1, 1] as const) {
    shadedDisc(ctx, side * r * 0.62, -r * 0.68, r * 0.26, p.primary, p.shade);
    ctx.fillStyle = p.accent;
    ctx.beginPath();
    ctx.arc(side * r * 0.6, -r * 0.66, r * 0.12, 0, TAU);
    ctx.fill();
  }
  headBase(ctx, r, p.primary, p.shade);
  // морда
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  ctx.ellipse(-r * 0.16, r * 0.42, r * 0.27, r * 0.23, 0, 0, TAU);
  ctx.ellipse(r * 0.16, r * 0.42, r * 0.27, r * 0.23, 0, 0, TAU);
  ctx.fill();
  // полосы
  ctx.fillStyle = p.accent2;
  const stripe = (x0: number, y0: number, x1: number, y1: number, w: number): void => {
    const ang = Math.atan2(y1 - y0, x1 - x0);
    const px = Math.sin(ang) * w * r;
    const py = -Math.cos(ang) * w * r;
    ctx.beginPath();
    ctx.moveTo(x0 * r - px, y0 * r - py);
    ctx.quadraticCurveTo(((x0 + x1) / 2) * r + px * 1.6, ((y0 + y1) / 2) * r + py * 1.6, x1 * r, y1 * r);
    ctx.quadraticCurveTo(((x0 + x1) / 2) * r - px * 0.2, ((y0 + y1) / 2) * r - py * 0.2, x0 * r + px, y0 * r + py);
    ctx.closePath();
    ctx.fill();
  };
  stripe(0, -0.95, 0, -0.55, 0.05);
  stripe(-0.3, -0.92, -0.26, -0.6, 0.04);
  stripe(0.3, -0.92, 0.26, -0.6, 0.04);
  stripe(-0.95, -0.15, -0.55, -0.05, 0.045);
  stripe(0.95, -0.15, 0.55, -0.05, 0.045);
  stripe(-0.9, 0.28, -0.6, 0.3, 0.04);
  stripe(0.9, 0.28, 0.6, 0.3, 0.04);
  drawEyePair(ctx, r, e, {
    dx: 0.33, y: -0.16, size: 0.14, iris: p.eyes, pupil: "slit",
    lid: p.primary, ink: "#221a12",
  });
  triNose(ctx, r, 0.26, 0.075, "#c96a5a");
  drawMouthCat(ctx, r, e, { y: 0.45, ink: "#3a2410", fangs: true });
  whiskers(ctx, r, withAlpha("#ffffff", 0.7), 0.36);
}

function paintOwl(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  for (const side of [-1, 1] as const) {
    earTriangle(ctx, r, side, {
      inX: 0.42, inY: -0.78, outX: 0.82, outY: -0.42, tipX: 0.92, tipY: -1.1,
      fur: p.primary, dark: p.shade,
    });
  }
  headBase(ctx, r, p.primary, p.shade);
  // лицевые диски
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  ctx.arc(-r * 0.3, -r * 0.02, r * 0.43, 0, TAU);
  ctx.arc(r * 0.3, -r * 0.02, r * 0.43, 0, TAU);
  ctx.fill();
  ctx.strokeStyle = withAlpha(p.shade, 0.5);
  ctx.lineWidth = r * 0.025;
  ctx.beginPath();
  ctx.arc(-r * 0.3, -r * 0.02, r * 0.43, 0, TAU);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(r * 0.3, -r * 0.02, r * 0.43, 0, TAU);
  ctx.stroke();
  // V-пёрышки на лбу
  ctx.strokeStyle = withAlpha(p.accent2, 0.8);
  ctx.lineWidth = r * 0.04;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(0, -r * 0.5);
  ctx.lineTo(-r * 0.3, -r * 0.85);
  ctx.moveTo(0, -r * 0.5);
  ctx.lineTo(r * 0.3, -r * 0.85);
  ctx.stroke();
  drawEyePair(ctx, r, e, {
    dx: 0.3, y: -0.02, size: 0.19, iris: p.eyes,
    lid: p.accent, ink: "#3a2a14", white: "#fffcf2",
  });
  drawBeak(ctx, r, e, { y: 0.42, w: 0.16, color: "#ef9b2d" });
  // перья на груди
  ctx.strokeStyle = withAlpha(p.shade, 0.6);
  ctx.lineWidth = r * 0.03;
  for (const x of [-0.28, 0, 0.28] as const) {
    ctx.beginPath();
    ctx.arc(x * r, r * 0.78, r * 0.12, Math.PI * 0.15, Math.PI * 0.85);
    ctx.stroke();
  }
}

function paintFrog(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // глаза-купола над головой
  for (const side of [-1, 1] as const) {
    shadedDisc(ctx, side * r * 0.42, -r * 0.8, r * 0.33, p.primary, p.shade);
  }
  headBase(ctx, r, p.primary, p.shade);
  // светлое брюшко-подбородок
  ctx.fillStyle = withAlpha(p.accent, 0.75);
  ctx.beginPath();
  ctx.ellipse(0, r * 0.62, r * 0.55, r * 0.34, 0, 0, TAU);
  ctx.fill();
  // сами глаза на куполах
  for (const side of [-1, 1] as const) {
    const cx = side * r * 0.42;
    const cy = -r * 0.84;
    const er = r * 0.2;
    if (e === "pain") {
      ctx.strokeStyle = "#1e3a10";
      ctx.lineWidth = er * 0.4;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(cx - er * 0.6, cy - er * 0.5);
      ctx.lineTo(cx + er * 0.6, cy + er * 0.5);
      ctx.moveTo(cx + er * 0.6, cy - er * 0.5);
      ctx.lineTo(cx - er * 0.6, cy + er * 0.5);
      ctx.stroke();
      continue;
    }
    ctx.fillStyle = "#fdfdf6";
    ctx.beginPath();
    ctx.arc(cx, cy, er, 0, TAU);
    ctx.fill();
    ctx.fillStyle = p.eyes;
    const wide = e === "scared" || e === "surprised";
    ctx.beginPath();
    ctx.arc(cx, cy + er * 0.1, er * (wide ? 0.55 : 0.42), 0, TAU);
    ctx.fill();
    ctx.fillStyle = "rgba(255,255,255,0.9)";
    ctx.beginPath();
    ctx.arc(cx - er * 0.2, cy - er * 0.12, er * 0.14, 0, TAU);
    ctx.fill();
    // ленивое веко
    if (!wide) {
      ctx.fillStyle = p.primary;
      ctx.beginPath();
      ctx.arc(cx, cy - er * (e === "angry" ? 0.1 : 0.35), er * 1.04, Math.PI, TAU);
      ctx.fill();
    }
  }
  // ноздри
  ctx.fillStyle = "#2f6b16";
  ctx.beginPath();
  ctx.arc(-r * 0.09, -r * 0.12, r * 0.03, 0, TAU);
  ctx.arc(r * 0.09, -r * 0.12, r * 0.03, 0, TAU);
  ctx.fill();
  // широченный рот
  ctx.strokeStyle = "#2f5512";
  ctx.lineWidth = r * 0.045;
  ctx.lineCap = "round";
  if (e === "smile") {
    drawMouthPlain(ctx, r, e, { y: 0.28, w: 0.42, lip: "#2f5512", teeth: false, tongue: true });
  } else if (e === "scared" || e === "surprised") {
    drawMouthPlain(ctx, r, e, { y: 0.32, w: 0.24, lip: "#2f5512", teeth: false });
  } else if (e === "pain") {
    ctx.beginPath();
    ctx.moveTo(-r * 0.5, r * 0.34);
    ctx.quadraticCurveTo(-r * 0.2, r * 0.24, 0, r * 0.34);
    ctx.quadraticCurveTo(r * 0.2, r * 0.44, r * 0.5, r * 0.3);
    ctx.stroke();
  } else {
    ctx.beginPath();
    ctx.moveTo(-r * 0.56, r * 0.24);
    ctx.quadraticCurveTo(0, r * (e === "angry" ? 0.18 : 0.42), r * 0.56, r * 0.24);
    ctx.stroke();
  }
  blush(ctx, r, "#ff9d6b", 0.35, 0.14, 0.6);
}

function paintPenguin(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // хохолок
  ctx.strokeStyle = p.shade;
  ctx.lineWidth = r * 0.05;
  ctx.lineCap = "round";
  for (const [x, tip] of [
    [-0.12, -1.16],
    [0, -1.24],
    [0.12, -1.14],
  ] as const) {
    ctx.beginPath();
    ctx.moveTo(x * r * 0.5, -r * 0.9);
    ctx.quadraticCurveTo(x * r, -r * 1.05, x * r * 1.6, tip * r);
    ctx.stroke();
  }
  headBase(ctx, r, p.primary, p.shade);
  // белая манишка
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  ctx.ellipse(-r * 0.24, r * 0.16, r * 0.32, r * 0.44, 0.25, 0, TAU);
  ctx.ellipse(r * 0.24, r * 0.16, r * 0.32, r * 0.44, -0.25, 0, TAU);
  ctx.ellipse(0, r * 0.3, r * 0.3, r * 0.42, 0, 0, TAU);
  ctx.fill();
  drawEyePair(ctx, r, e, {
    dx: 0.28, y: -0.14, size: 0.1, iris: p.eyes,
    lid: p.primary, ink: "#1d232b",
  });
  drawBeak(ctx, r, e, { y: 0.14, w: 0.17, color: p.accent2 });
  blush(ctx, r, "#ff8fa3", 0.35, 0.14, 0.5);
}

function paintAxolotl(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // жабры-веточки
  for (const side of [-1, 1] as const) {
    for (const [y0, y1, len] of [
      [-0.45, -0.75, 1.28],
      [-0.1, -0.2, 1.38],
      [0.25, 0.35, 1.3],
    ] as const) {
      const tipX = side * len * r;
      ctx.strokeStyle = p.accent;
      ctx.lineWidth = r * 0.09;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(side * r * 0.62, y0 * r);
      ctx.quadraticCurveTo(side * r * 1.0, ((y0 + y1) / 2) * r, tipX, y1 * r);
      ctx.stroke();
      ctx.fillStyle = lighten(p.accent, 0.25);
      for (const t of [0.55, 0.78, 1] as const) {
        const bx = side * r * 0.62 + (tipX - side * r * 0.62) * t;
        const by = (y0 + (y1 - y0) * t) * r;
        ctx.beginPath();
        ctx.arc(bx, by, r * 0.075 * (1.25 - t * 0.35), 0, TAU);
        ctx.fill();
      }
    }
  }
  headBase(ctx, r, p.primary, p.shade);
  drawEyePair(ctx, r, e, {
    dx: 0.34, y: -0.1, size: 0.11, iris: p.eyes,
    lid: p.primary, ink: "#4a3440",
  });
  drawMouthCat(ctx, r, e, { y: 0.32, ink: "#8f5468" });
  blush(ctx, r, p.accent2, 0.6, 0.14, 0.5);
  ctx.fillStyle = withAlpha("#ffffff", 0.5);
  ctx.beginPath();
  ctx.arc(-r * 0.62, -r * 0.08, r * 0.025, 0, TAU);
  ctx.arc(-r * 0.52, 0, r * 0.02, 0, TAU);
  ctx.arc(r * 0.62, -r * 0.08, r * 0.025, 0, TAU);
  ctx.arc(r * 0.52, 0, r * 0.02, 0, TAU);
  ctx.fill();
}

function paintUnicorn(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  const mane = [p.accent2, mixHex(p.accent2, "#7a5fc0", 0.55), mixHex(p.accent2, "#5fc0f0", 0.6)];
  // грива сзади
  const lobes: ReadonlyArray<readonly [number, number, number, number]> = [
    [-0.42, -0.88, 0.34, 0],
    [0.5, -0.78, 0.36, 1],
    [0.85, -0.4, 0.32, 2],
    [1.0, 0.05, 0.28, 1],
    [1.02, 0.5, 0.24, 2],
  ];
  for (const [x, y, rad, ci] of lobes) {
    const color = mane[ci]!;
    shadedDisc(ctx, x * r, y * r, rad * r, color, darken(color, 0.25));
  }
  // рог
  const hg = ctx.createLinearGradient(0, -r * 1.45, 0, -r * 0.7);
  hg.addColorStop(0, lighten(p.accent, 0.4));
  hg.addColorStop(1, darken(p.accent, 0.2));
  ctx.fillStyle = hg;
  ctx.beginPath();
  ctx.moveTo(-r * 0.13, -r * 0.78);
  ctx.lineTo(r * 0.15, -r * 0.78);
  ctx.lineTo(r * 0.05, -r * 1.44);
  ctx.closePath();
  ctx.fill();
  ctx.strokeStyle = withAlpha(darken(p.accent, 0.45), 0.7);
  ctx.lineWidth = r * 0.028;
  for (const t of [0.25, 0.5, 0.75] as const) {
    ctx.beginPath();
    ctx.moveTo((-0.13 + 0.16 * t) * r, (-0.78 - 0.6 * t) * r);
    ctx.lineTo((0.15 - 0.08 * t) * r, (-0.78 - 0.66 * t - 0.06) * r);
    ctx.stroke();
  }
  for (const side of [-1, 1] as const) {
    earTriangle(ctx, r, side, {
      inX: 0.4, inY: -0.8, outX: 0.78, outY: -0.5, tipX: 0.74, tipY: -1.08,
      fur: p.primary, dark: p.shade, inner: "#ffc9de",
    });
  }
  headBase(ctx, r, p.primary, p.shade);
  // чёлка
  shadedDisc(ctx, -r * 0.1, -r * 0.72, r * 0.3, mane[1]!, darken(mane[1]!, 0.25));
  shadedDisc(ctx, -r * 0.45, -r * 0.6, r * 0.24, mane[0]!, darken(mane[0]!, 0.25));
  drawEyePair(ctx, r, e, {
    dx: 0.32, y: -0.06, size: 0.13, iris: p.eyes,
    lid: p.primary, ink: "#4a3a58", lash: true,
  });
  ctx.fillStyle = withAlpha("#e88fb0", 0.8);
  ctx.beginPath();
  ctx.arc(-r * 0.1, r * 0.34, r * 0.035, 0, TAU);
  ctx.arc(r * 0.1, r * 0.34, r * 0.035, 0, TAU);
  ctx.fill();
  drawMouthPlain(ctx, r, e, { y: 0.5, w: 0.14, lip: "#c9738f", teeth: false });
  blush(ctx, r, "#ff8fa3", 0.35, 0.16, 0.54);
  star4(ctx, r * 0.68, -r * 0.3, r * 0.07, withAlpha("#ffd23e", 0.9));
  star4(ctx, -r * 0.72, r * 0.42, r * 0.05, withAlpha("#ffffff", 0.8));
}

/* ── монстры и прочие ── */

function paintRobot(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // антенна
  ctx.strokeStyle = p.shade;
  ctx.lineWidth = r * 0.06;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(0, -r * 0.9);
  ctx.lineTo(0, -r * 1.22);
  ctx.stroke();
  const glowColor = e === "angry" ? p.accent2 : p.accent;
  const ag = ctx.createRadialGradient(0, -r * 1.3, 0, 0, -r * 1.3, r * 0.28);
  ag.addColorStop(0, withAlpha(glowColor, 0.65));
  ag.addColorStop(1, withAlpha(glowColor, 0));
  ctx.fillStyle = ag;
  ctx.beginPath();
  ctx.arc(0, -r * 1.3, r * 0.28, 0, TAU);
  ctx.fill();
  shadedDisc(ctx, 0, -r * 1.3, r * 0.11, glowColor, darken(glowColor, 0.3));
  // боковые болты
  for (const side of [-1, 1] as const) {
    shadedDisc(ctx, side * r * 0.97, -r * 0.05, r * 0.17, p.shade, darken(p.shade, 0.35));
    ctx.fillStyle = p.primary;
    ctx.beginPath();
    ctx.arc(side * r * 0.97, -r * 0.05, r * 0.09, 0, TAU);
    ctx.fill();
    ctx.strokeStyle = withAlpha("#000000", 0.4);
    ctx.lineWidth = r * 0.025;
    ctx.beginPath();
    ctx.moveTo(side * r * 0.91, -r * 0.05);
    ctx.lineTo(side * r * 1.03, -r * 0.05);
    ctx.stroke();
  }
  headBase(ctx, r, p.primary, p.shade);
  // швы и заклёпки
  ctx.strokeStyle = "rgba(0,0,0,0.28)";
  ctx.lineWidth = r * 0.022;
  ctx.beginPath();
  ctx.moveTo(-r * 0.72, r * 0.42);
  ctx.quadraticCurveTo(0, r * 0.56, r * 0.72, r * 0.42);
  ctx.stroke();
  ctx.fillStyle = "rgba(0,0,0,0.3)";
  for (const [bx, by] of [
    [-0.55, 0.56],
    [0.55, 0.56],
    [-0.2, -0.86],
    [0.2, -0.86],
  ] as const) {
    ctx.beginPath();
    ctx.arc(bx * r, by * r, r * 0.028, 0, TAU);
    ctx.fill();
  }
  // визор
  ctx.fillStyle = withAlpha(darken(p.shade, 0.45), 0.55);
  ctx.beginPath();
  roundRectPath(ctx, -r * 0.58, -r * 0.34, r * 1.16, r * 0.46, r * 0.16);
  ctx.fill();
  // LED-глаза
  const led = (side: -1 | 1): void => {
    const cx = side * r * 0.29;
    const cy = -r * 0.11;
    ctx.strokeStyle = glowColor;
    ctx.fillStyle = glowColor;
    ctx.lineCap = "round";
    ctx.save();
    ctx.translate(cx, cy);
    if (e === "angry") ctx.rotate(side * 0.32);
    ctx.lineWidth = r * 0.1;
    if (e === "pain") {
      ctx.beginPath();
      ctx.moveTo(-r * 0.09, -r * 0.09);
      ctx.lineTo(r * 0.09, r * 0.09);
      ctx.moveTo(r * 0.09, -r * 0.09);
      ctx.lineTo(-r * 0.09, r * 0.09);
      ctx.stroke();
    } else if (e === "smile") {
      ctx.beginPath();
      ctx.arc(0, r * 0.05, r * 0.12, Math.PI * 1.1, Math.PI * 1.9);
      ctx.stroke();
    } else if (e === "scared" || e === "surprised") {
      ctx.lineWidth = r * 0.06;
      ctx.beginPath();
      ctx.arc(0, 0, r * 0.11, 0, TAU);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(0, 0, r * 0.035, 0, TAU);
      ctx.fill();
    } else {
      ctx.beginPath();
      roundRectPath(ctx, -r * 0.14, -r * 0.05, r * 0.28, r * 0.1, r * 0.05);
      ctx.fill();
    }
    ctx.restore();
    // свечение
    const eg = ctx.createRadialGradient(cx, cy, 0, cx, cy, r * 0.26);
    eg.addColorStop(0, withAlpha(glowColor, 0.4));
    eg.addColorStop(1, withAlpha(glowColor, 0));
    ctx.fillStyle = eg;
    ctx.beginPath();
    ctx.arc(cx, cy, r * 0.26, 0, TAU);
    ctx.fill();
  };
  led(-1);
  led(1);
  // LED-рот
  ctx.strokeStyle = glowColor;
  ctx.lineWidth = r * 0.055;
  ctx.lineCap = "round";
  ctx.beginPath();
  const my = r * 0.38;
  if (e === "smile") {
    ctx.arc(0, my - r * 0.06, r * 0.2, Math.PI * 0.12, Math.PI * 0.88);
  } else if (e === "angry") {
    ctx.moveTo(-r * 0.22, my);
    ctx.lineTo(-r * 0.08, my - r * 0.06);
    ctx.lineTo(r * 0.06, my + r * 0.05);
    ctx.lineTo(r * 0.22, my - r * 0.03);
  } else if (e === "scared" || e === "surprised") {
    ctx.arc(0, my, r * 0.09, 0, TAU);
  } else if (e === "pain") {
    ctx.moveTo(-r * 0.16, my);
    ctx.lineTo(r * 0.16, my);
    ctx.moveTo(-r * 0.1, my - r * 0.06);
    ctx.lineTo(-r * 0.1, my + r * 0.06);
    ctx.moveTo(r * 0.1, my - r * 0.06);
    ctx.lineTo(r * 0.1, my + r * 0.06);
  } else {
    ctx.moveTo(-r * 0.18, my);
    ctx.lineTo(r * 0.18, my);
  }
  ctx.stroke();
}

function paintAlien(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  for (const side of [-1, 1] as const) {
    ctx.strokeStyle = p.shade;
    ctx.lineWidth = r * 0.05;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(side * r * 0.26, -r * 0.82);
    ctx.quadraticCurveTo(side * r * 0.5, -r * 1.12, side * r * 0.6, -r * 1.28);
    ctx.stroke();
    const bg = ctx.createRadialGradient(side * r * 0.62, -r * 1.32, 0, side * r * 0.62, -r * 1.32, r * 0.2);
    bg.addColorStop(0, withAlpha(p.accent2, 0.7));
    bg.addColorStop(1, withAlpha(p.accent2, 0));
    ctx.fillStyle = bg;
    ctx.beginPath();
    ctx.arc(side * r * 0.62, -r * 1.32, r * 0.2, 0, TAU);
    ctx.fill();
    shadedDisc(ctx, side * r * 0.62, -r * 1.32, r * 0.09, p.accent2, darken(p.accent2, 0.3));
  }
  headBase(ctx, r, p.primary, p.shade);
  // огромные чёрные глаза
  for (const side of [-1, 1] as const) {
    const cx = side * r * 0.33;
    const cy = -r * 0.08;
    if (e === "pain") {
      ctx.strokeStyle = darken(p.shade, 0.4);
      ctx.lineWidth = r * 0.06;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.14, cy - r * 0.12);
      ctx.lineTo(cx + r * 0.14, cy + r * 0.12);
      ctx.moveTo(cx + r * 0.14, cy - r * 0.12);
      ctx.lineTo(cx - r * 0.14, cy + r * 0.12);
      ctx.stroke();
      continue;
    }
    const wide = e === "scared" || e === "surprised";
    const squeeze = e === "angry" ? 0.72 : e === "smile" ? 0.88 : 1;
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(side * (e === "angry" ? 0.5 : 0.32));
    const rx = r * 0.31 * (wide ? 1.12 : 1);
    const ry = r * 0.17 * (wide ? 1.3 : squeeze);
    const eg = ctx.createLinearGradient(-rx, -ry, rx, ry);
    eg.addColorStop(0, lighten(p.accent, 0.22));
    eg.addColorStop(0.5, p.accent);
    eg.addColorStop(1, "#000000");
    ctx.fillStyle = eg;
    ctx.beginPath();
    ctx.ellipse(0, 0, rx, ry, 0, 0, TAU);
    ctx.fill();
    ctx.fillStyle = "rgba(157,123,255,0.35)";
    ctx.beginPath();
    ctx.ellipse(-rx * 0.35, -ry * 0.3, rx * 0.34, ry * 0.32, 0, 0, TAU);
    ctx.fill();
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    ctx.beginPath();
    ctx.arc(-rx * 0.55, -ry * 0.25, r * 0.035, 0, TAU);
    ctx.fill();
    ctx.restore();
  }
  ctx.fillStyle = darken(p.shade, 0.3);
  ctx.beginPath();
  ctx.arc(-r * 0.05, r * 0.22, r * 0.022, 0, TAU);
  ctx.arc(r * 0.05, r * 0.22, r * 0.022, 0, TAU);
  ctx.fill();
  drawMouthPlain(ctx, r, e, { y: 0.44, w: 0.13, lip: darken(p.primary, 0.45), teeth: false });
}

function paintZombie(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  headBase(ctx, r, p.primary, p.shade);
  // шрам со стежками
  ctx.strokeStyle = p.accent;
  ctx.lineWidth = r * 0.035;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(-r * 0.55, -r * 0.6);
  ctx.quadraticCurveTo(-r * 0.05, -r * 0.46, r * 0.42, -r * 0.52);
  ctx.stroke();
  ctx.lineWidth = r * 0.025;
  for (const t of [0.15, 0.4, 0.65, 0.88] as const) {
    const x = -r * 0.55 + r * 0.97 * t;
    const y = -r * 0.55 + Math.sin(t * Math.PI) * r * 0.06;
    ctx.beginPath();
    ctx.moveTo(x, y - r * 0.07);
    ctx.lineTo(x + r * 0.04, y + r * 0.07);
    ctx.stroke();
  }
  // гнилая щека
  ctx.fillStyle = withAlpha(p.accent, 0.7);
  ctx.beginPath();
  ctx.ellipse(-r * 0.52, r * 0.3, r * 0.13, r * 0.1, 0.3, 0, TAU);
  ctx.fill();
  ctx.fillStyle = darken(p.accent, 0.35);
  ctx.beginPath();
  ctx.arc(-r * 0.56, r * 0.28, r * 0.035, 0, TAU);
  ctx.arc(-r * 0.46, r * 0.34, r * 0.028, 0, TAU);
  ctx.fill();
  // разные глаза
  drawEyeOne(ctx, r, e, {
    dx: 0.3, y: -0.12, size: 0.11, iris: "#8a9a4a",
    lid: p.primary, ink: "#3a4426", white: p.accent2,
  }, -1);
  drawEyeOne(ctx, r, e, {
    dx: 0.3, y: -0.12, size: 0.11, iris: "#c9b24a",
    lid: p.primary, ink: "#3a4426", white: p.accent2,
  }, 1, 1.5, 0.06);
  ctx.strokeStyle = withAlpha(p.shade, 0.9);
  ctx.lineWidth = r * 0.03;
  ctx.beginPath();
  ctx.arc(r * 0.3, r * 0.12, r * 0.2, Math.PI * 0.15, Math.PI * 0.85);
  ctx.stroke();
  // кривой рот со стежком
  ctx.save();
  ctx.rotate(-0.08);
  drawMouthPlain(ctx, r, e, { y: 0.42, w: 0.2, lip: "#4a5d33", teeth: true });
  ctx.restore();
  if (e === "smile") {
    // золотой зуб
    ctx.fillStyle = "#e8c34a";
    ctx.beginPath();
    ctx.fillRect(r * 0.08, r * 0.38, r * 0.08, r * 0.07);
  }
}

function paintSkull(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  headBase(ctx, r, p.primary, p.shade);
  // трещина
  ctx.strokeStyle = withAlpha(p.accent, 0.75);
  ctx.lineWidth = r * 0.03;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(r * 0.24, -r * 0.9);
  ctx.lineTo(r * 0.14, -r * 0.7);
  ctx.lineTo(r * 0.26, -r * 0.62);
  ctx.lineTo(r * 0.16, -r * 0.46);
  ctx.stroke();
  // скулы
  ctx.fillStyle = withAlpha(p.shade, 0.5);
  ctx.beginPath();
  ctx.ellipse(-r * 0.56, r * 0.22, r * 0.14, r * 0.09, 0.4, 0, TAU);
  ctx.ellipse(r * 0.56, r * 0.22, r * 0.14, r * 0.09, -0.4, 0, TAU);
  ctx.fill();
  // глазницы
  for (const side of [-1, 1] as const) {
    const cx = side * r * 0.3;
    const cy = -r * 0.12;
    shadedDisc(ctx, cx, cy, r * 0.2, "#171310", "#050403");
    if (e === "angry") {
      ctx.fillStyle = p.primary;
      ctx.beginPath();
      ctx.moveTo(cx + side * r * 0.24, cy - r * 0.26);
      ctx.lineTo(cx + side * r * 0.24, cy - r * 0.1);
      ctx.lineTo(cx - side * r * 0.24, cy - r * 0.02);
      ctx.lineTo(cx - side * r * 0.24, cy - r * 0.26);
      ctx.closePath();
      ctx.fill();
    }
    // огонёк
    const glow = p.eyes;
    if (e === "pain") {
      ctx.strokeStyle = glow;
      ctx.lineWidth = r * 0.035;
      ctx.beginPath();
      ctx.moveTo(cx - r * 0.07, cy - r * 0.07);
      ctx.lineTo(cx + r * 0.07, cy + r * 0.07);
      ctx.moveTo(cx + r * 0.07, cy - r * 0.07);
      ctx.lineTo(cx - r * 0.07, cy + r * 0.07);
      ctx.stroke();
    } else {
      const gr = e === "scared" || e === "surprised" ? 0.085 : 0.055;
      const gg = ctx.createRadialGradient(cx, cy, 0, cx, cy, r * gr * 2.6);
      gg.addColorStop(0, withAlpha(glow, 0.6));
      gg.addColorStop(1, withAlpha(glow, 0));
      ctx.fillStyle = gg;
      ctx.beginPath();
      ctx.arc(cx, cy, r * gr * 2.6, 0, TAU);
      ctx.fill();
      ctx.fillStyle = glow;
      ctx.beginPath();
      if (e === "smile") {
        ctx.arc(cx, cy + r * 0.02, r * gr, Math.PI, TAU);
      } else {
        ctx.arc(cx, cy, r * gr, 0, TAU);
      }
      ctx.fill();
    }
  }
  // носовая впадина
  ctx.fillStyle = "#171310";
  ctx.beginPath();
  ctx.moveTo(0, r * 0.08);
  ctx.lineTo(r * 0.09, r * 0.26);
  ctx.quadraticCurveTo(0, r * 0.32, -r * 0.09, r * 0.26);
  ctx.closePath();
  ctx.fill();
  // зубы
  const jawDrop = e === "surprised" || e === "scared" ? r * 0.12 : 0;
  const grin = e === "smile" ? 1.2 : 1;
  const tw = r * 0.62 * grin;
  const ty = r * 0.42;
  if (jawDrop > 0) {
    ctx.fillStyle = "#171310";
    ctx.beginPath();
    roundRectPath(ctx, -tw / 2, ty, tw, r * 0.2 + jawDrop, r * 0.05);
    ctx.fill();
  }
  const rowH = r * 0.13;
  const teethRow = (yy: number): void => {
    const g = ctx.createLinearGradient(0, yy, 0, yy + rowH);
    g.addColorStop(0, lighten(p.primary, 0.1));
    g.addColorStop(1, darken(p.primary, 0.15));
    ctx.fillStyle = g;
    ctx.beginPath();
    roundRectPath(ctx, -tw / 2, yy, tw, rowH, r * 0.05);
    ctx.fill();
    ctx.strokeStyle = "rgba(0,0,0,0.4)";
    ctx.lineWidth = r * 0.018;
    ctx.beginPath();
    for (let i = 1; i < 5; i += 1) {
      const x = -tw / 2 + (tw / 5) * i;
      ctx.moveTo(x, yy + rowH * 0.12);
      ctx.lineTo(x, yy + rowH * 0.88);
    }
    ctx.stroke();
  };
  teethRow(ty);
  teethRow(ty + rowH + jawDrop);
  if (e === "pain") {
    ctx.strokeStyle = "rgba(0,0,0,0.55)";
    ctx.lineWidth = r * 0.035;
    ctx.beginPath();
    ctx.moveTo(-tw / 2, ty + rowH);
    ctx.lineTo(tw / 2, ty + rowH);
    ctx.stroke();
  }
}

function paintOni(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // грива
  ctx.fillStyle = p.accent2;
  ctx.beginPath();
  for (const [x, y, rad] of [
    [-0.7, -0.6, 0.34],
    [-0.3, -0.85, 0.36],
    [0.15, -0.9, 0.34],
    [0.6, -0.7, 0.34],
    [0.95, -0.35, 0.28],
    [-0.98, -0.25, 0.26],
  ] as const) {
    ctx.moveTo((x + rad) * r, y * r);
    ctx.arc(x * r, y * r, rad * r, 0, TAU);
  }
  ctx.fill();
  // рога
  for (const side of [-1, 1] as const) {
    const hg = ctx.createLinearGradient(side * r * 0.4, -r * 1.3, side * r * 0.4, -r * 0.6);
    hg.addColorStop(0, lighten(p.accent, 0.35));
    hg.addColorStop(1, darken(p.accent, 0.15));
    ctx.fillStyle = hg;
    ctx.beginPath();
    ctx.moveTo(side * r * 0.28, -r * 0.72);
    ctx.quadraticCurveTo(side * r * 0.42, -r * 1.05, side * r * 0.62, -r * 1.28);
    ctx.quadraticCurveTo(side * r * 0.66, -r * 0.95, side * r * 0.56, -r * 0.6);
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = withAlpha(darken(p.accent, 0.5), 0.6);
    ctx.lineWidth = r * 0.03;
    ctx.beginPath();
    ctx.moveTo(side * r * 0.36, -r * 0.88);
    ctx.lineTo(side * r * 0.55, -r * 0.82);
    ctx.stroke();
  }
  headBase(ctx, r, p.primary, p.shade);
  // серьги-кольца
  ctx.strokeStyle = p.accent;
  ctx.lineWidth = r * 0.045;
  ctx.beginPath();
  ctx.arc(-r * 0.88, r * 0.32, r * 0.1, -0.4, Math.PI + 0.4);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(r * 0.88, r * 0.32, r * 0.1, Math.PI - 0.6, 0.4 + TAU / 2 + Math.PI, true);
  ctx.stroke();
  drawBrowPair(ctx, r, e, { color: p.accent2, y: -0.3, dx: 0.32, w: 0.2, thick: 0.09 });
  drawEyePair(ctx, r, e, {
    dx: 0.32, y: -0.1, size: 0.13, iris: p.eyes,
    lid: p.primary, ink: "#2a1210", white: "#ffe9c9",
  });
  ctx.strokeStyle = darken(p.shade, 0.2);
  ctx.lineWidth = r * 0.035;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(-r * 0.05, r * 0.14);
  ctx.quadraticCurveTo(r * 0.06, r * 0.2, 0, r * 0.26);
  ctx.stroke();
  // пасть с клыками
  const my = r * 0.48;
  const mw = r * (e === "smile" || e === "angry" ? 0.38 : 0.3);
  const mouthPath = (): void => {
    ctx.beginPath();
    if (e === "scared" || e === "surprised") {
      ctx.ellipse(0, my, mw * 0.5, mw * 0.62, 0, 0, TAU);
    } else if (e === "pain") {
      ctx.moveTo(-mw, my - r * 0.02);
      ctx.quadraticCurveTo(0, my + r * 0.08, mw, my - r * 0.02);
      ctx.quadraticCurveTo(0, my + r * 0.14, -mw, my - r * 0.02);
      ctx.closePath();
    } else {
      const lift = e === "angry" ? -r * 0.06 : r * 0.04;
      ctx.moveTo(-mw, my - r * 0.03);
      ctx.quadraticCurveTo(0, my + lift, mw, my - r * 0.03);
      ctx.quadraticCurveTo(0, my + r * 0.24, -mw, my - r * 0.03);
      ctx.closePath();
    }
  };
  mouthPath();
  ctx.fillStyle = "#3a0f10";
  ctx.fill();
  ctx.save();
  mouthPath();
  ctx.clip();
  ctx.fillStyle = "#fff3e0";
  ctx.fillRect(-mw, my - r * 0.06, mw * 2, r * 0.07);
  ctx.restore();
  mouthPath();
  ctx.strokeStyle = darken(p.primary, 0.45);
  ctx.lineWidth = r * 0.03;
  ctx.stroke();
  // нижние клыки вверх
  if (e !== "scared" && e !== "surprised") {
    ctx.fillStyle = "#fff3e0";
    for (const side of [-1, 1] as const) {
      ctx.beginPath();
      ctx.moveTo(side * mw * 0.72 - r * 0.045, my + r * 0.1);
      ctx.lineTo(side * mw * 0.72 + r * 0.045, my + r * 0.1);
      ctx.lineTo(side * mw * 0.72, my - r * 0.12);
      ctx.closePath();
      ctx.fill();
    }
  }
}

function paintPumpkin(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // черенок и завиток
  ctx.strokeStyle = "#4a7a1e";
  ctx.lineWidth = r * 0.13;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(0, -r * 0.86);
  ctx.quadraticCurveTo(r * 0.06, -r * 1.05, r * 0.14, -r * 1.18);
  ctx.stroke();
  ctx.strokeStyle = "#6a9a2a";
  ctx.lineWidth = r * 0.04;
  ctx.beginPath();
  ctx.arc(r * 0.34, -r * 1.08, r * 0.09, Math.PI * 0.8, Math.PI * 2.3);
  ctx.stroke();
  ctx.fillStyle = p.accent;
  ctx.save();
  ctx.translate(-r * 0.22, -r * 1.02);
  ctx.rotate(-0.5);
  ctx.beginPath();
  ctx.ellipse(0, 0, r * 0.18, 0.07 * r, 0, 0, TAU);
  ctx.fill();
  ctx.restore();
  headBase(ctx, r, p.primary, p.shade);
  // рёбра тыквы
  for (const x of [-0.55, -0.2, 0.2, 0.55] as const) {
    ctx.strokeStyle = withAlpha(p.shade, 0.55);
    ctx.lineWidth = r * 0.05;
    ctx.beginPath();
    ctx.moveTo(x * r * 0.42, -r * 0.86);
    ctx.quadraticCurveTo(x * r * 1.4, 0, x * r * 0.42, r * 0.86);
    ctx.stroke();
    ctx.strokeStyle = withAlpha("#ffffff", 0.12);
    ctx.lineWidth = r * 0.025;
    ctx.beginPath();
    ctx.moveTo(x * r * 0.42 - r * 0.04, -r * 0.84);
    ctx.quadraticCurveTo(x * r * 1.32 - r * 0.04, 0, x * r * 0.42 - r * 0.04, r * 0.84);
    ctx.stroke();
  }
  // вырезанное лицо со свечением
  const carve = (path: () => void): void => {
    ctx.save();
    path();
    ctx.clip();
    const g = ctx.createRadialGradient(0, 0, r * 0.05, 0, 0, r * 0.9);
    g.addColorStop(0, "#fff3b0");
    g.addColorStop(0.55, p.accent2);
    g.addColorStop(1, "#ff8a1f");
    ctx.fillStyle = g;
    ctx.fillRect(-r, -r, r * 2, r * 2);
    ctx.restore();
    path();
    ctx.strokeStyle = withAlpha(darken(p.primary, 0.5), 0.8);
    ctx.lineWidth = r * 0.03;
    ctx.stroke();
  };
  // глаза
  for (const side of [-1, 1] as const) {
    if (e === "pain") {
      ctx.strokeStyle = p.accent2;
      ctx.lineWidth = r * 0.06;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(side * r * 0.42, -r * 0.24);
      ctx.lineTo(side * r * 0.18, -r * 0.02);
      ctx.moveTo(side * r * 0.18, -r * 0.24);
      ctx.lineTo(side * r * 0.42, -r * 0.02);
      ctx.stroke();
      continue;
    }
    carve(() => {
      ctx.beginPath();
      if (e === "scared" || e === "surprised") {
        ctx.arc(side * r * 0.3, -r * 0.14, r * 0.13, 0, TAU);
      } else if (e === "angry") {
        ctx.moveTo(side * r * 0.5, -r * 0.3);
        ctx.lineTo(side * r * 0.5, -r * 0.06);
        ctx.lineTo(side * r * 0.12, -r * 0.02);
        ctx.closePath();
      } else {
        ctx.moveTo(side * r * 0.3 - r * 0.15, -r * 0.04);
        ctx.lineTo(side * r * 0.3 + r * 0.15, -r * 0.04);
        ctx.lineTo(side * r * 0.3, -r * 0.3);
        ctx.closePath();
      }
    });
  }
  // рот
  if (e === "scared" || e === "surprised") {
    carve(() => {
      ctx.beginPath();
      ctx.ellipse(0, r * 0.42, r * 0.14, r * 0.18, 0, 0, TAU);
    });
  } else if (e === "pain") {
    carve(() => {
      ctx.beginPath();
      ctx.moveTo(-r * 0.3, r * 0.4);
      ctx.lineTo(-r * 0.1, r * 0.32);
      ctx.lineTo(r * 0.1, r * 0.44);
      ctx.lineTo(r * 0.3, r * 0.34);
      ctx.lineTo(r * 0.3, r * 0.46);
      ctx.lineTo(-r * 0.3, r * 0.5);
      ctx.closePath();
    });
  } else {
    const up = e === "angry" ? -1 : 1;
    const wm = e === "smile" ? 1.15 : 0.9;
    carve(() => {
      ctx.beginPath();
      ctx.moveTo(-r * 0.42 * wm, r * (0.36 - 0.04 * up));
      ctx.quadraticCurveTo(0, r * (0.36 + 0.14 * up), r * 0.42 * wm, r * (0.36 - 0.04 * up));
      const zig = 4;
      for (let i = 0; i <= zig; i += 1) {
        const t = i / zig;
        const x = r * 0.42 * wm - t * r * 0.84 * wm;
        const yBase = r * (0.36 + (0.14 - 0.28 * Math.abs(t - 0.5)) * up * 0.4);
        ctx.lineTo(x, yBase + (i % 2 === 0 ? r * 0.12 : r * 0.02) * up);
      }
      ctx.closePath();
    });
    if (e === "smile") {
      // квадратный «выбитый зуб»
      ctx.fillStyle = p.primary;
      ctx.fillRect(r * 0.08, r * 0.34, r * 0.12, r * 0.09);
    }
  }
}

function paintGhost(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // внешнее свечение
  for (const [rad, a] of [
    [1.28, 0.14],
    [1.12, 0.18],
  ] as const) {
    ctx.fillStyle = withAlpha(p.accent2, a);
    ctx.beginPath();
    ctx.arc(0, 0, r * rad, 0, TAU);
    ctx.fill();
  }
  headBase(ctx, r, p.primary, p.shade);
  // волнистый подол
  ctx.strokeStyle = withAlpha(p.accent, 0.75);
  ctx.lineWidth = r * 0.05;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(-r * 0.78, r * 0.5);
  for (const [cx, cy, x, y] of [
    [-0.5, 0.78, -0.28, 0.62],
    [-0.08, 0.5, 0.16, 0.66],
    [0.4, 0.86, 0.62, 0.6],
  ] as const) {
    ctx.quadraticCurveTo(cx * r, cy * r, x * r, y * r);
  }
  ctx.stroke();
  drawEyePair(ctx, r, e, {
    dx: 0.3, y: -0.1, size: 0.12, iris: p.eyes,
    lid: p.primary, ink: "#2c3350",
  });
  drawMouthPlain(ctx, r, e, { y: 0.32, w: 0.15, lip: "#3a4260", teeth: false });
  blush(ctx, r, "#9db4e0", 0.5, 0.12, 0.5);
  star4(ctx, r * 0.85, -r * 0.85, r * 0.1, withAlpha("#ffffff", 0.9));
  star4(ctx, -r * 0.95, -r * 0.45, r * 0.07, withAlpha(p.accent2, 0.8));
  star4(ctx, r * 1.05, r * 0.35, r * 0.06, withAlpha("#ffffff", 0.6));
}

function paintNinja(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // ленты повязки
  ctx.fillStyle = p.accent2;
  ctx.beginPath();
  ctx.moveTo(r * 0.82, -r * 0.52);
  ctx.quadraticCurveTo(r * 1.18, -r * 0.66, r * 1.38, -r * 0.52);
  ctx.quadraticCurveTo(r * 1.16, -r * 0.44, r * 1.02, -r * 0.32);
  ctx.closePath();
  ctx.fill();
  ctx.beginPath();
  ctx.moveTo(r * 0.84, -r * 0.42);
  ctx.quadraticCurveTo(r * 1.1, -r * 0.28, r * 1.32, -r * 0.1);
  ctx.quadraticCurveTo(r * 1.06, -r * 0.14, r * 0.92, -r * 0.22);
  ctx.closePath();
  ctx.fill();
  headBase(ctx, r, p.primary, p.shade);
  // складки капюшона
  ctx.strokeStyle = withAlpha(darken(p.primary, 0.4), 0.8);
  ctx.lineWidth = r * 0.035;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.arc(0, r * 0.9, r * 0.55, Math.PI * 1.2, Math.PI * 1.8);
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(0, r * 1.15, r * 0.7, Math.PI * 1.25, Math.PI * 1.75);
  ctx.stroke();
  // прорезь для глаз
  ctx.fillStyle = p.accent;
  ctx.beginPath();
  roundRectPath(ctx, -r * 0.58, -r * 0.32, r * 1.16, r * 0.42, r * 0.21);
  ctx.fill();
  ctx.fillStyle = "rgba(0,0,0,0.18)";
  ctx.beginPath();
  roundRectPath(ctx, -r * 0.58, -r * 0.32, r * 1.16, r * 0.12, r * 0.06);
  ctx.fill();
  // повязка
  ctx.strokeStyle = p.accent2;
  ctx.lineWidth = r * 0.17;
  ctx.beginPath();
  ctx.moveTo(-r * 0.93, -r * 0.38);
  ctx.quadraticCurveTo(0, -r * 0.6, r * 0.93, -r * 0.38);
  ctx.stroke();
  // пластина
  ctx.fillStyle = lighten(p.primary, 0.35);
  ctx.beginPath();
  roundRectPath(ctx, -r * 0.17, -r * 0.58, r * 0.34, r * 0.17, r * 0.04);
  ctx.fill();
  ctx.fillStyle = withAlpha("#000000", 0.35);
  ctx.beginPath();
  ctx.arc(0, -r * 0.5, r * 0.03, 0, TAU);
  ctx.fill();
  drawEyePair(ctx, r, e, {
    dx: 0.28, y: -0.1, size: 0.1, iris: p.eyes,
    lid: p.accent, ink: "#241a10",
  });
  drawBrowPair(ctx, r, e, { color: darken(p.accent, 0.45), y: -0.24, dx: 0.28, w: 0.13, thick: 0.045 });
}

function paintSlime(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  // капли на макушке
  shadedDisc(ctx, -r * 0.32, -r * 0.94, r * 0.19, p.primary, p.shade);
  shadedDisc(ctx, r * 0.26, -r * 1.0, r * 0.14, p.primary, p.shade);
  ctx.strokeStyle = p.primary;
  ctx.lineWidth = r * 0.16;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(r * 0.82, -r * 0.4);
  ctx.lineTo(r * 0.92, -r * 0.06);
  ctx.stroke();
  headBase(ctx, r, p.primary, p.shade);
  // желейный край
  ctx.strokeStyle = withAlpha(p.accent, 0.6);
  ctx.lineWidth = r * 0.08;
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.9, 0, TAU);
  ctx.stroke();
  // пузырьки
  ctx.strokeStyle = withAlpha("#ffffff", 0.4);
  ctx.lineWidth = r * 0.02;
  for (const [bx, by, brad] of [
    [-0.42, 0.34, 0.07],
    [0.48, 0.42, 0.05],
    [0.2, 0.62, 0.04],
    [-0.15, -0.55, 0.05],
  ] as const) {
    ctx.beginPath();
    ctx.arc(bx * r, by * r, brad * r, 0, TAU);
    ctx.stroke();
  }
  gloss(ctx, 0, 0, r, 0.4);
  drawEyePair(ctx, r, e, {
    dx: 0.3, y: -0.08, size: 0.12, iris: p.eyes,
    lid: p.primary, ink: p.eyes,
  });
  drawMouthPlain(ctx, r, e, {
    y: 0.32, w: 0.2, lip: darken(p.primary, 0.35),
    inner: darken(p.primary, 0.5), teeth: false, tongue: false,
  });
  blush(ctx, r, "#ffffff", 0.3, 0.16, 0.52);
}

/* ── люди ── */

function humanHairBack(
  ctx: Ctx,
  r: number,
  style: HumanHairStyle,
  hair: string,
  hi: string,
): void {
  switch (style) {
    case "mohawk": {
      for (let i = -2; i <= 2; i += 1) {
        const g = ctx.createLinearGradient(0, -r * 1.42, 0, -r * 0.6);
        g.addColorStop(0, hi);
        g.addColorStop(1, darken(hair, 0.15));
        ctx.fillStyle = g;
        const bx = i * r * 0.17;
        const tipX = i * r * 0.26;
        const tipY = -r * (1.36 - Math.abs(i) * 0.14);
        ctx.beginPath();
        ctx.moveTo(bx - r * 0.1, -r * 0.68);
        ctx.quadraticCurveTo(tipX - r * 0.02, tipY * 0.85, tipX, tipY);
        ctx.quadraticCurveTo(tipX + r * 0.03, tipY * 0.88, bx + r * 0.1, -r * 0.62);
        ctx.closePath();
        ctx.fill();
      }
      return;
    }
    case "afro": {
      shadedDisc(ctx, 0, -r * 0.3, r * 1.12, hair, darken(hair, 0.2));
      ctx.strokeStyle = withAlpha(hi, 0.5);
      ctx.lineWidth = r * 0.05;
      ctx.lineCap = "round";
      for (let i = 0; i < 6; i += 1) {
        const a = Math.PI * (1.05 + (i / 5) * 0.9);
        ctx.beginPath();
        ctx.arc(Math.cos(a) * r * 0.85, -r * 0.3 + Math.sin(a) * r * 0.85, r * 0.16, a - 0.8, a + 0.8);
        ctx.stroke();
      }
      return;
    }
    case "buns": {
      shadedDisc(ctx, -r * 0.62, -r * 0.94, r * 0.3, hair, darken(hair, 0.2));
      shadedDisc(ctx, r * 0.62, -r * 0.94, r * 0.3, hair, darken(hair, 0.2));
      ctx.strokeStyle = darken(hair, 0.35);
      ctx.lineWidth = r * 0.045;
      ctx.beginPath();
      ctx.arc(-r * 0.62, -r * 0.78, r * 0.16, Math.PI * 0.1, Math.PI * 0.9);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(r * 0.62, -r * 0.78, r * 0.16, Math.PI * 0.1, Math.PI * 0.9);
      ctx.stroke();
      return;
    }
    case "spiky": {
      const tips: ReadonlyArray<readonly [number, number, number]> = [
        [-0.95, -0.85, -0.5],
        [-0.55, -1.22, -0.28],
        [-0.05, -1.4, 0],
        [0.45, -1.25, 0.25],
        [0.9, -0.9, 0.5],
      ];
      for (const [tx, ty, bx] of tips) {
        const g = ctx.createLinearGradient(0, ty * r, 0, -r * 0.5);
        g.addColorStop(0, hi);
        g.addColorStop(1, hair);
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.moveTo(bx * r - r * 0.16, -r * 0.6);
        ctx.quadraticCurveTo(tx * r * 0.9, ty * r * 0.9, tx * r, ty * r);
        ctx.quadraticCurveTo(tx * r * 0.96, ty * r * 0.75, bx * r + r * 0.16, -r * 0.52);
        ctx.closePath();
        ctx.fill();
      }
      return;
    }
    case "long": {
      const g = ctx.createLinearGradient(0, -r, 0, r * 0.9);
      g.addColorStop(0, lighten(hair, 0.12));
      g.addColorStop(1, darken(hair, 0.3));
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.moveTo(0, -r * 1.0);
      ctx.quadraticCurveTo(-r * 1.05, -r * 0.7, -r * 0.92, r * 0.25);
      ctx.quadraticCurveTo(-r * 0.86, r * 0.7, -r * 0.6, r * 0.92);
      ctx.lineTo(-r * 0.3, r * 0.55);
      ctx.lineTo(0, r * 0.8);
      ctx.lineTo(r * 0.3, r * 0.55);
      ctx.lineTo(r * 0.6, r * 0.92);
      ctx.quadraticCurveTo(r * 0.86, r * 0.7, r * 0.92, r * 0.25);
      ctx.quadraticCurveTo(r * 1.05, -r * 0.7, 0, -r * 1.0);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = withAlpha(hi, 0.5);
      ctx.lineWidth = r * 0.04;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(-r * 0.55, -r * 0.6);
      ctx.quadraticCurveTo(-r * 0.78, -r * 0.1, -r * 0.7, r * 0.5);
      ctx.stroke();
      return;
    }
    case "braids": {
      for (const side of [-1, 1] as const) {
        const beads: ReadonlyArray<readonly [number, number, number]> = [
          [0.82, -0.02, 0.115],
          [0.88, 0.26, 0.095],
          [0.92, 0.5, 0.08],
        ];
        for (const [x, y, rad] of beads) {
          shadedDisc(ctx, side * x * r, y * r, rad * r, hair, darken(hair, 0.25));
        }
        ctx.strokeStyle = darken(hair, 0.4);
        ctx.lineWidth = r * 0.035;
        ctx.beginPath();
        ctx.moveTo(side * r * 0.88, r * 0.62);
        ctx.lineTo(side * r * 0.96, r * 0.68);
        ctx.stroke();
      }
      return;
    }
    case "granny": {
      shadedDisc(ctx, 0, -r * 1.0, r * 0.3, hair, darken(hair, 0.2));
      ctx.strokeStyle = withAlpha(hi, 0.7);
      ctx.lineWidth = r * 0.035;
      ctx.beginPath();
      ctx.arc(0, -r * 1.0, r * 0.18, Math.PI * 0.2, Math.PI * 1.4);
      ctx.stroke();
      return;
    }
    case "bald":
      return;
  }
}

function humanHairFront(
  ctx: Ctx,
  r: number,
  style: HumanHairStyle,
  hair: string,
  hi: string,
): void {
  switch (style) {
    case "mohawk": {
      // выбритые виски
      ctx.strokeStyle = withAlpha(darken(hair, 0.1), 0.35);
      ctx.lineWidth = r * 0.16;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(0, -r * 0.05, r * 0.78, Math.PI * 1.14, Math.PI * 1.32);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(0, -r * 0.05, r * 0.78, Math.PI * 1.68, Math.PI * 1.86);
      ctx.stroke();
      return;
    }
    case "afro": {
      ctx.fillStyle = hair;
      ctx.beginPath();
      ctx.arc(0, -r * 0.18, r * 0.88, Math.PI * 1.06, Math.PI * 1.94);
      ctx.fill();
      return;
    }
    case "buns": {
      ctx.fillStyle = hair;
      ctx.beginPath();
      ctx.arc(0, -r * 0.06, r * 0.92, Math.PI * 1.04, Math.PI * 1.96);
      ctx.quadraticCurveTo(r * 0.6, -r * 0.44, 0, -r * 0.42);
      ctx.quadraticCurveTo(-r * 0.6, -r * 0.44, -r * 0.855, -r * 0.31);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = darken(hair, 0.3);
      ctx.lineWidth = r * 0.025;
      ctx.beginPath();
      ctx.moveTo(0, -r * 0.94);
      ctx.lineTo(0, -r * 0.44);
      ctx.stroke();
      ctx.strokeStyle = withAlpha(hi, 0.6);
      ctx.lineWidth = r * 0.04;
      ctx.beginPath();
      ctx.arc(-r * 0.35, -r * 0.52, r * 0.32, Math.PI * 1.15, Math.PI * 1.5);
      ctx.stroke();
      return;
    }
    case "spiky": {
      ctx.fillStyle = hair;
      ctx.beginPath();
      ctx.moveTo(-r * 0.87, -r * 0.3);
      ctx.arc(0, -r * 0.1, r * 0.88, Math.PI * 1.07, Math.PI * 1.93);
      for (const [x, y] of [
        [0.62, -0.38],
        [0.4, -0.56],
        [0.28, -0.4],
        [0.02, -0.62],
        [-0.24, -0.4],
        [-0.42, -0.56],
        [-0.64, -0.36],
      ] as const) {
        ctx.lineTo(x * r, y * r);
      }
      ctx.closePath();
      ctx.fill();
      return;
    }
    case "long": {
      ctx.fillStyle = hair;
      ctx.beginPath();
      ctx.moveTo(0, -r * 0.98);
      ctx.quadraticCurveTo(-r * 0.9, -r * 0.85, -r * 0.8, -r * 0.05);
      ctx.quadraticCurveTo(-r * 0.55, -r * 0.35, -r * 0.14, -r * 0.42);
      ctx.quadraticCurveTo(0, -r * 0.38, r * 0.14, -r * 0.42);
      ctx.quadraticCurveTo(r * 0.55, -r * 0.35, r * 0.8, -r * 0.05);
      ctx.quadraticCurveTo(r * 0.9, -r * 0.85, 0, -r * 0.98);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = withAlpha(hi, 0.45);
      ctx.lineWidth = r * 0.035;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(-r * 0.2, -r * 0.75);
      ctx.quadraticCurveTo(-r * 0.5, -r * 0.6, -r * 0.6, -r * 0.2);
      ctx.stroke();
      return;
    }
    case "braids": {
      ctx.fillStyle = hair;
      ctx.beginPath();
      ctx.arc(0, -r * 0.12, r * 0.87, Math.PI * 1.05, Math.PI * 1.95);
      ctx.fill();
      ctx.strokeStyle = withAlpha(hi, 0.55);
      ctx.lineWidth = r * 0.045;
      ctx.lineCap = "round";
      for (const x of [-0.4, -0.13, 0.13, 0.4] as const) {
        ctx.beginPath();
        ctx.moveTo(x * r, -r * 0.82);
        ctx.quadraticCurveTo(x * r * 1.25, -r * 0.6, x * r * 1.4, -r * 0.42);
        ctx.stroke();
      }
      return;
    }
    case "granny": {
      ctx.fillStyle = hair;
      ctx.beginPath();
      ctx.arc(0, -r * 0.08, r * 0.9, Math.PI * 1.04, Math.PI * 1.96);
      ctx.quadraticCurveTo(r * 0.5, -r * 0.52, 0, -r * 0.44);
      ctx.quadraticCurveTo(-r * 0.5, -r * 0.52, -r * 0.85, -r * 0.33);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = withAlpha(hi, 0.8);
      ctx.lineWidth = r * 0.028;
      ctx.lineCap = "round";
      for (const x of [-0.5, -0.25, 0, 0.25, 0.5] as const) {
        ctx.beginPath();
        ctx.moveTo(x * r, -r * 0.85 + Math.abs(x) * r * 0.18);
        ctx.quadraticCurveTo(x * r * 1.1, -r * 0.6, x * r * 0.9, -r * 0.48);
        ctx.stroke();
      }
      return;
    }
    case "bald": {
      ctx.strokeStyle = "rgba(255,255,255,0.28)";
      ctx.lineWidth = r * 0.09;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(0, -r * 0.05, r * 0.66, Math.PI * 1.14, Math.PI * 1.42);
      ctx.stroke();
      return;
    }
  }
}

function drawFreckles(ctx: Ctx, r: number): void {
  ctx.fillStyle = "rgba(150, 84, 48, 0.4)";
  for (const [fx, fy, s] of [
    [-0.34, 0.12, 1],
    [-0.26, 0.19, 0.8],
    [-0.42, 0.19, 0.7],
    [0.34, 0.12, 1],
    [0.26, 0.19, 0.8],
    [0.42, 0.19, 0.7],
    [-0.06, 0.2, 0.6],
    [0.06, 0.2, 0.6],
  ] as const) {
    ctx.beginPath();
    ctx.arc(fx * r, fy * r, r * 0.018 * s, 0, TAU);
    ctx.fill();
  }
}

function paintHuman(ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId): void {
  const traits = p.human ?? { hair: "bald" as const };
  const hair = p.accent;
  const hi = p.accent2;
  humanHairBack(ctx, r, traits.hair, hair, hi);
  headBase(ctx, r, p.primary, p.shade);
  // уши
  for (const side of [-1, 1] as const) {
    shadedDisc(ctx, side * r * 0.9, r * 0.02, r * 0.13, p.primary, p.shade);
    ctx.strokeStyle = withAlpha(p.shade, 0.8);
    ctx.lineWidth = r * 0.025;
    ctx.beginPath();
    ctx.arc(side * r * 0.9, r * 0.02, r * 0.055, Math.PI * 0.2, Math.PI * 1.2);
    ctx.stroke();
    if (traits.earrings) {
      ctx.strokeStyle = traits.hair === "bald" || traits.hair === "afro" ? "#f0c14b" : "#ffd23e";
      ctx.lineWidth = r * 0.04;
      ctx.beginPath();
      ctx.arc(side * r * 0.92, r * 0.2, r * 0.085, -0.3, Math.PI + 0.3);
      ctx.stroke();
    }
  }
  // борода викинга
  if (traits.beard) {
    const g = ctx.createLinearGradient(0, 0, 0, r * 1.0);
    g.addColorStop(0, hair);
    g.addColorStop(1, darken(hair, 0.3));
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.moveTo(-r * 0.6, r * 0.02);
    ctx.quadraticCurveTo(-r * 0.62, r * 0.6, -r * 0.22, r * 0.9);
    ctx.quadraticCurveTo(0, r * 1.02, r * 0.22, r * 0.9);
    ctx.quadraticCurveTo(r * 0.62, r * 0.6, r * 0.6, r * 0.02);
    ctx.quadraticCurveTo(r * 0.3, r * 0.2, 0, r * 0.2);
    ctx.quadraticCurveTo(-r * 0.3, r * 0.2, -r * 0.6, r * 0.02);
    ctx.closePath();
    ctx.fill();
    // перевязки косичек бороды
    ctx.strokeStyle = darken(hair, 0.45);
    ctx.lineWidth = r * 0.045;
    ctx.beginPath();
    ctx.moveTo(-r * 0.3, r * 0.62);
    ctx.lineTo(-r * 0.12, r * 0.68);
    ctx.moveTo(r * 0.12, r * 0.68);
    ctx.lineTo(r * 0.3, r * 0.62);
    ctx.stroke();
    // рот на фоне кожи
    ctx.fillStyle = mixHex(p.primary, p.shade, 0.35);
    ctx.beginPath();
    ctx.ellipse(0, r * 0.36, r * 0.17, r * 0.12, 0, 0, TAU);
    ctx.fill();
    // усы
    ctx.strokeStyle = lighten(hair, 0.12);
    ctx.lineWidth = r * 0.07;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(0, r * 0.26);
    ctx.quadraticCurveTo(-r * 0.2, r * 0.24, -r * 0.32, r * 0.38);
    ctx.moveTo(0, r * 0.26);
    ctx.quadraticCurveTo(r * 0.2, r * 0.24, r * 0.32, r * 0.38);
    ctx.stroke();
  }
  const brow =
    traits.hair === "bald" ? darken(p.shade, 0.5) : darken(hair, 0.28);
  drawBrowPair(ctx, r, e, { color: brow, y: -0.32, dx: 0.3, w: 0.16, thick: 0.06 });
  drawEyePair(ctx, r, e, {
    dx: 0.3, y: -0.11, size: 0.12, iris: p.eyes,
    lid: p.primary, smileClosed: false, ink: darken(p.shade, 0.45),
  });
  // нос
  ctx.strokeStyle = withAlpha(p.shade, 0.9);
  ctx.lineWidth = r * 0.032;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(r * 0.02, -r * 0.02);
  ctx.quadraticCurveTo(r * 0.08, r * 0.1, 0, r * 0.15);
  ctx.stroke();
  if (traits.freckles) drawFreckles(ctx, r);
  drawMouthPlain(ctx, r, e, {
    y: 0.36, w: 0.19, lip: mixHex(p.shade, "#b05a50", 0.5),
    teeth: true, tongue: true,
  });
  if (traits.glasses) {
    ctx.strokeStyle = "#4a4440";
    ctx.lineWidth = r * 0.04;
    ctx.fillStyle = "rgba(255,255,255,0.14)";
    for (const side of [-1, 1] as const) {
      ctx.beginPath();
      ctx.arc(side * r * 0.3, -r * 0.09, r * 0.2, 0, TAU);
      ctx.fill();
      ctx.stroke();
    }
    ctx.beginPath();
    ctx.moveTo(-r * 0.1, -r * 0.12);
    ctx.quadraticCurveTo(0, -r * 0.2, r * 0.1, -r * 0.12);
    ctx.moveTo(-r * 0.5, -r * 0.12);
    ctx.lineTo(-r * 0.86, -r * 0.06);
    ctx.moveTo(r * 0.5, -r * 0.12);
    ctx.lineTo(r * 0.86, -r * 0.06);
    ctx.stroke();
  }
  humanHairFront(ctx, r, traits.hair, hair, hi);
}

/* ── реестр painter'ов ── */

const PAINTERS: Record<AvatarKind, (ctx: Ctx, r: number, p: AvatarFacePreset, e: EmotionId) => void> = {
  human: paintHuman,
  cat: paintCat,
  fox: paintFox,
  panda: paintPanda,
  frog: paintFrog,
  bear: paintBear,
  tiger: paintTiger,
  owl: paintOwl,
  bunny: paintBunny,
  shiba: paintShiba,
  penguin: paintPenguin,
  axolotl: paintAxolotl,
  unicorn: paintUnicorn,
  robot: paintRobot,
  alien: paintAlien,
  zombie: paintZombie,
  skull: paintSkull,
  oni: paintOni,
  pumpkin: paintPumpkin,
  ghost: paintGhost,
  ninja: paintNinja,
  slime: paintSlime,
};

function drawAvatarFaceCore(
  ctx: Ctx,
  r: number,
  preset: AvatarFacePreset,
  emotion: EmotionId,
): void {
  PAINTERS[preset.kind](ctx, r, preset, emotion);
}

function headLocal(
  render: Matter.Render,
  head: Matter.Body,
): { x: number; y: number; r: number } {
  const radius = head.circleRadius ?? 20;
  const { x, y, scale } = worldToCanvas(render, head.position);
  return { x, y, r: radius * scale };
}

function hashHue(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i += 1) {
    h = (h * 31 + id.charCodeAt(i)) >>> 0;
  }
  return h % 360;
}

/** Мини-превью для карусели в меню: цветной фон + лицо с фирменной эмоцией. */
export function drawAvatarFacePreview(
  ctx: Ctx,
  size: number,
  preset: AvatarFacePreset,
): void {
  ctx.clearRect(0, 0, size, size);

  const hue = hashHue(preset.id);
  const bg = ctx.createRadialGradient(
    size * 0.5,
    size * 0.34,
    size * 0.06,
    size * 0.5,
    size * 0.56,
    size * 0.82,
  );
  bg.addColorStop(0, `hsl(${hue}, 44%, 46%)`);
  bg.addColorStop(1, `hsl(${hue}, 50%, 18%)`);
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, size, size);

  const r = size * 0.3;
  ctx.save();
  ctx.translate(size / 2, size * 0.57);
  // тень под головой
  ctx.fillStyle = "rgba(0,0,0,0.3)";
  ctx.beginPath();
  ctx.ellipse(0, r * 1.22, r * 0.85, r * 0.16, 0, 0, TAU);
  ctx.fill();
  drawAvatarFaceCore(ctx, r, preset, preset.mood);
  ctx.restore();
}

/** Пресет лица на голове рэгдолла: уши и рога выходят за круг головы. */
export function drawAvatarOnHead(
  ctx: Ctx,
  render: Matter.Render,
  head: Matter.Body,
  preset: AvatarFacePreset,
  options: {
    faceEffect?: FaceOverlayEffectId;
    now?: number;
    painFlash?: boolean;
    emotion?: EmotionId;
  } = {},
): void {
  const { x, y, r } = headLocal(render, head);
  const emotion =
    options.emotion && options.emotion !== "neutral"
      ? options.emotion
      : preset.mood;

  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(head.angle);

  drawAvatarFaceCore(ctx, r * 0.95, preset, emotion);

  if (options.painFlash) {
    const g = ctx.createRadialGradient(0, 0, r * 0.2, 0, 0, r * 1.4);
    g.addColorStop(0, "rgba(255, 40, 40, 0.5)");
    g.addColorStop(1, "rgba(255, 40, 40, 0)");
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(0, 0, r * 1.4, 0, TAU);
    ctx.fill();
  }

  if (options.faceEffect && options.faceEffect !== "none") {
    ctx.beginPath();
    ctx.arc(0, 0, r * HEAD_FACE_CLIP, 0, TAU);
    ctx.clip();
    drawFaceOverlayEffect(ctx, r, options.faceEffect, options.now ?? 0);
  }

  ctx.restore();
}
