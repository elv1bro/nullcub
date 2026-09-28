import { Body } from "matter-js";

/** Частота записи поз; на slow-mo сглаживаем lerp между кадрами. */
export const FIGHT_TAPE_HZ = 30;
const SAMPLE_MS = 1000 / FIGHT_TAPE_HZ;
/** Запас под тайм-аут боя (3 мин) + чуть сверху. */
export const FIGHT_TAPE_MAX_FRAMES = FIGHT_TAPE_HZ * 200;
const FLOATS_PER_BODY = 3; // x, y, angle

export type FightTapeFrame = {
  /** мс от старта боя */
  t: number;
  poses: Float32Array;
  /** 0..1 — «горячесть» момента (удары / комбо / KO) */
  excitement: number;
  playerHp: number;
  opponentHp: number;
};

export type FightTapeHitEvent = {
  t: number;
  kind: "hit" | "ko";
  damage: number;
  x: number;
  y: number;
  victimSide: "player" | "opponent";
  damageTypeId?: string;
  /** Направление удара для directional gore в повторе. */
  dirX?: number;
  dirY?: number;
  /** HP сразу после события — точнее ступеней кадров. */
  playerHp: number;
  opponentHp: number;
};

export type FightTapeSnapshot = {
  frames: FightTapeFrame[];
  bodyCount: number;
  durationMs: number;
};

/** Компактный клип для буфера обмена (без Float32Array). */
export type FightTapeClip = {
  v: 1;
  bodyCount: number;
  durationMs: number;
  times: number[];
  poses: number[][];
  events: Array<{
    t: number;
    kind: "hit" | "ko";
    damage: number;
    x: number;
    y: number;
    victimSide: "player" | "opponent";
    dirX?: number;
    dirY?: number;
  }>;
};

/** Look-ahead: тормозим ДО удара, а не только в пике. */
export const REPLAY_LOOKAHEAD_MS = 520;
/** После удара держим slow-mo ещё чуть-чуть (эффект «замедленной драки»). */
export const REPLAY_HIT_HOLD_MS = 640;
/** Хвост после KO: разлёт, потом конец повтора. */
export const REPLAY_POST_KO_MS = 5000;

/**
 * Кинематографичный Auto: крейсер ~1.6×, скучное ~3× (не ×8),
 * удар/пики → глубокий slow-mo.
 */
export function speedFromExcitement(excitement: number): number {
  const e = Math.max(0, Math.min(1, excitement));
  if (e < 0.08) return 3.0;
  if (e < 0.22) return 2.0;
  if (e < 0.4) return 1.35;
  if (e < 0.58) return 0.85;
  if (e < 0.75) return 0.55;
  if (e < 0.9) return 0.42;
  return 0.35;
}

/** Макс. excitement в [t, t+lookahead] — чтобы замедлиться заранее. */
export function peakExcitementAhead(
  tape: { excitementAt: (t: number) => number; durationMs: number },
  tMs: number,
  lookaheadMs = REPLAY_LOOKAHEAD_MS,
): number {
  let peak = tape.excitementAt(tMs);
  const end = Math.min(tape.durationMs, tMs + lookaheadMs);
  const step = 80;
  for (let t = tMs + step; t <= end; t += step) {
    peak = Math.max(peak, tape.excitementAt(t));
  }
  return peak;
}

/**
 * Кольцевой буфер боя: позы тел + кривая excitement + события ударов для FX.
 */
export class FightTape {
  private frames: FightTapeFrame[] = [];
  private events: FightTapeHitEvent[] = [];
  private bodyCount = 0;
  private excitement = 0;
  private lastSampleAt = -Infinity;
  private startedAt = 0;
  private frozen = false;
  private lastPlayerHp = 100;
  private lastOpponentHp = 100;
  private maxPlayerHp = 100;
  private maxOpponentHp = 100;
  /** Время KO на ленте (мс от старта); null — ещё не было. */
  private koAtMs: number | null = null;

  begin(
    now: number,
    bodyCount: number,
    maxPlayerHp = 100,
    maxOpponentHp = 100,
  ): void {
    this.frames = [];
    this.events = [];
    this.bodyCount = bodyCount;
    this.excitement = 0;
    this.lastSampleAt = -Infinity;
    this.startedAt = now;
    this.frozen = false;
    this.maxPlayerHp = maxPlayerHp;
    this.maxOpponentHp = maxOpponentHp;
    this.lastPlayerHp = maxPlayerHp;
    this.lastOpponentHp = maxOpponentHp;
    this.koAtMs = null;
  }

  /** Обновить HP на ленте (после удара / каждый семпл). */
  noteHp(playerHp: number, opponentHp: number): void {
    this.lastPlayerHp = Math.max(0, playerHp);
    this.lastOpponentHp = Math.max(0, opponentHp);
  }

  private battleTime(now = performance.now()): number {
    return Math.max(0, now - this.startedAt);
  }

  /** Урон / крутой удар — всплеск на волне (+ опционально событие для FX в повторе). */
  noteHit(
    damage: number,
    meta?: {
      x: number;
      y: number;
      victimSide: "player" | "opponent";
      damageTypeId?: string;
      dirX?: number;
      dirY?: number;
      now?: number;
      playerHp?: number;
      opponentHp?: number;
    },
  ): void {
    if (this.frozen || damage <= 0) return;
    this.excitement = Math.min(1, this.excitement + Math.min(0.55, damage / 90));
    if (meta?.playerHp != null && meta?.opponentHp != null) {
      this.noteHp(meta.playerHp, meta.opponentHp);
    }
    if (meta) {
      this.events.push({
        t: this.battleTime(meta.now),
        kind: "hit",
        damage,
        x: meta.x,
        y: meta.y,
        victimSide: meta.victimSide,
        damageTypeId: meta.damageTypeId,
        dirX: meta.dirX,
        dirY: meta.dirY,
        playerHp: this.lastPlayerHp,
        opponentHp: this.lastOpponentHp,
      });
      if (this.events.length > 400) {
        this.events.splice(0, this.events.length - 400);
      }
    }
  }

  noteCombo(tier: number): void {
    if (this.frozen || tier <= 0) return;
    this.excitement = Math.min(1, this.excitement + 0.12 * Math.min(tier, 5));
  }

  noteKo(meta?: {
    x: number;
    y: number;
    victimSide: "player" | "opponent";
    now?: number;
    playerHp?: number;
    opponentHp?: number;
  }): void {
    if (this.frozen) return;
    this.excitement = 1;
    if (meta?.playerHp != null && meta?.opponentHp != null) {
      this.noteHp(meta.playerHp, meta.opponentHp);
    } else if (meta?.victimSide === "player") {
      this.lastPlayerHp = 0;
    } else if (meta?.victimSide === "opponent") {
      this.lastOpponentHp = 0;
    }
    const t = this.battleTime(meta?.now);
    if (this.koAtMs == null) this.koAtMs = t;
    if (meta) {
      this.events.push({
        t,
        kind: "ko",
        damage: 999,
        x: meta.x,
        y: meta.y,
        victimSide: meta.victimSide,
        playerHp: this.lastPlayerHp,
        opponentHp: this.lastOpponentHp,
      });
    }
  }

  maybeSample(
    now: number,
    bodies: Body[],
    hp?: { player: number; opponent: number },
  ): void {
    if (this.frozen) return;
    if (bodies.length === 0) return;
    if (now - this.lastSampleAt < SAMPLE_MS) return;

    if (this.bodyCount === 0) this.bodyCount = bodies.length;
    if (hp) this.noteHp(hp.player, hp.opponent);

    // Медленнее спад — пики «живут» дольше для волны и Auto slow-mo.
    this.excitement *= 0.93;

    const poses = new Float32Array(this.bodyCount * FLOATS_PER_BODY);
    const n = Math.min(this.bodyCount, bodies.length);
    for (let i = 0; i < n; i++) {
      const body = bodies[i]!;
      const o = i * FLOATS_PER_BODY;
      poses[o] = body.position.x;
      poses[o + 1] = body.position.y;
      poses[o + 2] = body.angle;
    }

    this.frames.push({
      t: Math.max(0, now - this.startedAt),
      poses,
      excitement: this.excitement,
      playerHp: this.lastPlayerHp,
      opponentHp: this.lastOpponentHp,
    });
    this.lastSampleAt = now;

    if (this.frames.length > FIGHT_TAPE_MAX_FRAMES) {
      this.frames.splice(0, this.frames.length - FIGHT_TAPE_MAX_FRAMES);
    }
  }

  freeze(): void {
    this.frozen = true;
  }

  get isFrozen(): boolean {
    return this.frozen;
  }

  get knockoutAtMs(): number | null {
    return this.koAtMs;
  }

  /**
   * Конец повтора: KO + 5с разлёта (или вся лента, если KO не было).
   */
  get playbackEndMs(): number {
    const dur = this.durationMs;
    if (this.koAtMs == null) return dur;
    return Math.min(dur, this.koAtMs + REPLAY_POST_KO_MS);
  }

  /** Ещё пишем хвост после KO (разлёт), даже если battleOver. */
  wantsPostKoTail(now = performance.now()): boolean {
    if (this.frozen || this.koAtMs == null) return false;
    return this.battleTime(now) < this.koAtMs + REPLAY_POST_KO_MS;
  }

  clear(): void {
    this.frames = [];
    this.events = [];
    this.bodyCount = 0;
    this.excitement = 0;
    this.frozen = false;
    this.lastPlayerHp = this.maxPlayerHp;
    this.lastOpponentHp = this.maxOpponentHp;
    this.koAtMs = null;
  }

  /** HP на момент t: последний кадр/удар не позже t. */
  hpAt(tMs: number): { playerHp: number; opponentHp: number } {
    let playerHp = this.maxPlayerHp;
    let opponentHp = this.maxOpponentHp;
    let bestT = -1;
    if (this.frames.length > 0) {
      const frame = this.frames[this.indexFloorAtTime(tMs)]!;
      if (frame.t <= tMs) {
        playerHp = frame.playerHp;
        opponentHp = frame.opponentHp;
        bestT = frame.t;
      }
    }
    for (const event of this.events) {
      if (event.t > tMs) break;
      if (event.t >= bestT) {
        playerHp = event.playerHp;
        opponentHp = event.opponentHp;
        bestT = event.t;
      }
    }
    return { playerHp, opponentHp };
  }

  get frameCount(): number {
    return this.frames.length;
  }

  get eventCount(): number {
    return this.events.length;
  }

  get durationMs(): number {
    const last = this.frames[this.frames.length - 1];
    return last?.t ?? 0;
  }

  snapshot(): FightTapeSnapshot {
    return {
      frames: this.frames,
      bodyCount: this.bodyCount,
      durationMs: this.durationMs,
    };
  }

  frameAt(index: number): FightTapeFrame | null {
    if (index < 0 || index >= this.frames.length) return null;
    return this.frames[index]!;
  }

  /** Индекс кадра ближайший к времени t (мс от старта). */
  indexAtTime(tMs: number): number {
    if (this.frames.length === 0) return 0;
    let lo = 0;
    let hi = this.frames.length - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.frames[mid]!.t < tMs) lo = mid + 1;
      else hi = mid;
    }
    if (lo > 0) {
      const a = this.frames[lo - 1]!;
      const b = this.frames[lo]!;
      return Math.abs(a.t - tMs) <= Math.abs(b.t - tMs) ? lo - 1 : lo;
    }
    return lo;
  }

  /** Последний кадр с t ≤ tMs (для интерполяции). */
  indexFloorAtTime(tMs: number): number {
    if (this.frames.length === 0) return 0;
    let lo = 0;
    let hi = this.frames.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (this.frames[mid]!.t <= tMs) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  }

  excitementAt(tMs: number): number {
    const i0 = this.indexFloorAtTime(tMs);
    const a = this.frames[i0];
    if (!a) return 0;
    const b = this.frames[i0 + 1];
    if (!b || b.t <= a.t) return a.excitement;
    const u = Math.max(0, Math.min(1, (tMs - a.t) / (b.t - a.t)));
    return a.excitement + (b.excitement - a.excitement) * u;
  }

  /**
   * Позы в момент t с lerp между соседними кадрами —
   * иначе slow-mo выглядит как просадка FPS (кадр держится 50–100 мс).
   */
  samplePosesAt(tMs: number, out: Float32Array): Float32Array {
    const n = this.bodyCount * FLOATS_PER_BODY;
    if (out.length < n) {
      throw new Error("samplePosesAt: out buffer too small");
    }
    if (this.frames.length === 0 || this.bodyCount === 0) {
      out.fill(0, 0, n);
      return out;
    }
    const i0 = this.indexFloorAtTime(tMs);
    const a = this.frames[i0]!;
    const b = this.frames[Math.min(i0 + 1, this.frames.length - 1)]!;
    if (a === b || b.t <= a.t) {
      out.set(a.poses.subarray(0, n));
      return out;
    }
    const u = Math.max(0, Math.min(1, (tMs - a.t) / (b.t - a.t)));
    const pa = a.poses;
    const pb = b.poses;
    for (let i = 0; i < this.bodyCount; i++) {
      const o = i * FLOATS_PER_BODY;
      out[o] = pa[o]! + (pb[o]! - pa[o]!) * u;
      out[o + 1] = pa[o + 1]! + (pb[o + 1]! - pa[o + 1]!) * u;
      out[o + 2] = lerpAngle(pa[o + 2]!, pb[o + 2]!, u);
    }
    return out;
  }

  /**
   * События в полуинтервале (fromMs, toMs].
   * При перемотке назад вернёт пусто — FX не спамим.
   */
  eventsBetween(fromMs: number, toMs: number): FightTapeHitEvent[] {
    if (toMs <= fromMs) return [];
    return this.events.filter((e) => e.t > fromMs && e.t <= toMs);
  }

  /**
   * Срез для шеринга: позы прорежены (~10 Hz), события окна.
   * from/to — мс от старта боя.
   */
  exportClip(fromMs: number, toMs: number): FightTapeClip {
    const a = Math.max(0, Math.min(fromMs, toMs));
    const b = Math.max(fromMs, toMs);
    const step = 100; // ~10 Hz
    const poses: number[][] = [];
    const times: number[] = [];
    const scratch = new Float32Array(Math.max(1, this.bodyCount) * FLOATS_PER_BODY);
    for (let t = a; t <= b + 0.5; t += step) {
      this.samplePosesAt(t, scratch);
      times.push(Math.round(t));
      poses.push(Array.from(scratch.subarray(0, this.bodyCount * FLOATS_PER_BODY)));
    }
    const events = this.events
      .filter((e) => e.t >= a && e.t <= b)
      .map((e) => ({
        t: Math.round(e.t - a),
        kind: e.kind,
        damage: e.damage,
        x: e.x,
        y: e.y,
        victimSide: e.victimSide,
        dirX: e.dirX,
        dirY: e.dirY,
      }));
    return {
      v: 1,
      bodyCount: this.bodyCount,
      durationMs: Math.round(b - a),
      times,
      poses,
      events,
    };
  }

  /** Нормализованная волна 0..1 для отрисовки (сглаженная). */
  waveSamples(bucketCount = 64, untilMs?: number): number[] {
    if (this.frames.length === 0 || bucketCount <= 0) {
      return Array.from({ length: bucketCount }, () => 0);
    }
    const out = new Array<number>(bucketCount).fill(0);
    const dur = Math.max(1, untilMs ?? this.playbackEndMs);
    for (const frame of this.frames) {
      if (frame.t > dur) break;
      const i = Math.min(
        bucketCount - 1,
        Math.floor((frame.t / dur) * bucketCount),
      );
      out[i]! = Math.max(out[i]!, frame.excitement);
    }
    // Лёгкое размытие, чтобы волна была «ютубной», а не гребёнкой.
    const blurred = out.slice();
    for (let i = 0; i < bucketCount; i++) {
      const l = out[i - 1] ?? out[i]!;
      const c = out[i]!;
      const r = out[i + 1] ?? out[i]!;
      blurred[i] = Math.min(1, l * 0.2 + c * 0.6 + r * 0.2);
    }
    return blurred;
  }
}

/** Кратчайший lerp угла (избегаем скачков через ±π). */
export function lerpAngle(a: number, b: number, t: number): number {
  let d = b - a;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return a + d * t;
}

/** Выставить позы кадра на живые тела (кинематический повтор). */
export function applyFightTapePoses(bodies: Body[], poses: Float32Array): void {
  const count = Math.min(bodies.length, Math.floor(poses.length / FLOATS_PER_BODY));
  for (let i = 0; i < count; i++) {
    const body = bodies[i]!;
    if (body.isStatic) continue;
    const o = i * FLOATS_PER_BODY;
    Body.setPosition(body, { x: poses[o]!, y: poses[o + 1]! });
    Body.setAngle(body, poses[o + 2]!);
    Body.setVelocity(body, { x: 0, y: 0 });
    Body.setAngularVelocity(body, 0);
  }
}

/** Пики волны для «перемотки к крутому моменту». */
export function findExcitementPeaks(
  wave: number[],
  minHeight = 0.45,
): number[] {
  const peaks: number[] = [];
  for (let i = 1; i < wave.length - 1; i++) {
    const v = wave[i]!;
    if (v < minHeight) continue;
    if (v >= wave[i - 1]! && v >= wave[i + 1]!) peaks.push(i);
  }
  return peaks;
}
