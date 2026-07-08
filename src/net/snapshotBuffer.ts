import { SNAPSHOT_HZ } from "./protocol";

export type SnapshotFrame = { at: number; data: Float32Array };

/** Буфер из двух снапшотов + задержка рендера для плавной интерполяции. */
export class SnapshotInterpolator {
  private scratch: Float32Array | null = null;
  private lerpBuf: Float32Array | null = null;
  private prev: SnapshotFrame | null = null;
  private next: SnapshotFrame | null = null;
  readonly renderDelayMs: number;

  constructor(renderDelayMs = (1000 / SNAPSHOT_HZ) * 1.5) {
    this.renderDelayMs = renderDelayMs;
  }

  push(raw: ArrayLike<number>, at = performance.now()): void {
    const len = raw.length;
    if (!this.scratch || this.scratch.length !== len) {
      this.scratch = new Float32Array(len);
    }
    this.scratch.set(raw);
    this.prev = this.next;
    this.next = { at, data: this.scratch };
    this.scratch = new Float32Array(len);
  }

  sample(
    now = performance.now(),
  ):
    | { mode: "single"; data: Float32Array }
    | { mode: "lerp"; data: Float32Array; alpha: number; from: Float32Array; to: Float32Array }
    | null {
    if (!this.next) return null;
    const t = now - this.renderDelayMs;
    if (!this.prev) return { mode: "single", data: this.next.data };

    const span = this.next.at - this.prev.at;
    if (span <= 1 || t >= this.next.at) {
      return { mode: "single", data: this.next.data };
    }

    const alpha = Math.max(0, Math.min(1, (t - this.prev.at) / span));
    if (!this.lerpBuf || this.lerpBuf.length !== this.next.data.length) {
      this.lerpBuf = new Float32Array(this.next.data.length);
    }
    return {
      mode: "lerp",
      data: this.lerpBuf,
      alpha,
      from: this.prev.data,
      to: this.next.data,
    };
  }

  reset(): void {
    this.prev = null;
    this.next = null;
  }
}
