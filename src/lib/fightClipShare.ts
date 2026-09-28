import type { FightTapeClip } from "@/lib/fightTape";

const SHARE_PREFIX = "RFR1.";
const MAX_CLIP_MS = 12_000;
const MAX_POSE_ROWS = 140;

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/");
  const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
  const binary = atob(padded + pad);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function roundPose(n: number): number {
  return Math.round(n * 10) / 10;
}

/** Сжать клип перед кодированием (лимит длины / числа кадров). */
export function compactFightClip(clip: FightTapeClip): FightTapeClip {
  let poses = clip.poses;
  let times = clip.times;
  if (clip.durationMs > MAX_CLIP_MS && times.length > 2) {
    // Обрезаем с конца до лимита.
    const keepUntil = times[0]! + MAX_CLIP_MS;
    const nextTimes: number[] = [];
    const nextPoses: number[][] = [];
    for (let i = 0; i < times.length; i++) {
      if (times[i]! > keepUntil) break;
      nextTimes.push(times[i]!);
      nextPoses.push(poses[i]!);
    }
    times = nextTimes;
    poses = nextPoses;
  }
  if (poses.length > MAX_POSE_ROWS) {
    const step = Math.ceil(poses.length / MAX_POSE_ROWS);
    const nextTimes: number[] = [];
    const nextPoses: number[][] = [];
    for (let i = 0; i < poses.length; i += step) {
      nextTimes.push(times[i]!);
      nextPoses.push(poses[i]!);
    }
    const last = poses.length - 1;
    if (nextTimes[nextTimes.length - 1] !== times[last]) {
      nextTimes.push(times[last]!);
      nextPoses.push(poses[last]!);
    }
    times = nextTimes;
    poses = nextPoses;
  }
  return {
    v: 1,
    bodyCount: clip.bodyCount,
    durationMs: Math.min(MAX_CLIP_MS, clip.durationMs),
    times,
    poses: poses.map((row) => row.map(roundPose)),
    events: clip.events.filter((e) => e.t <= MAX_CLIP_MS),
  };
}

export function encodeFightClipShare(clip: FightTapeClip): string {
  const payload = compactFightClip(clip);
  const json = JSON.stringify(payload);
  const bytes = new TextEncoder().encode(json);
  return SHARE_PREFIX + toBase64Url(bytes);
}

export function decodeFightClipShare(raw: string): FightTapeClip | null {
  const text = raw.trim();
  if (!text.startsWith(SHARE_PREFIX)) return null;
  try {
    const bytes = fromBase64Url(text.slice(SHARE_PREFIX.length));
    const json = new TextDecoder().decode(bytes);
    const data = JSON.parse(json) as FightTapeClip;
    if (
      data?.v !== 1 ||
      !Array.isArray(data.poses) ||
      !Array.isArray(data.times) ||
      typeof data.bodyCount !== "number"
    ) {
      return null;
    }
    if (data.poses.length === 0 || data.poses.length > MAX_POSE_ROWS + 4) {
      return null;
    }
    return data;
  } catch {
    return null;
  }
}

export async function copyFightClipShare(clip: FightTapeClip): Promise<boolean> {
  const text = encodeFightClipShare(clip);
  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* fall through */
  }
  try {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.left = "-9999px";
    document.body.appendChild(ta);
    ta.select();
    const ok = document.execCommand("copy");
    document.body.removeChild(ta);
    return ok;
  } catch {
    return false;
  }
}
