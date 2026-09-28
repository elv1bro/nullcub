import {
  normalizeMonsterDef,
  type MonsterDef,
} from "./monsterTypes";

const SHARE_PREFIX = "RFM1.";

type SharePayload = {
  v: 1;
  name: string;
  parts: MonsterDef["parts"];
  links: MonsterDef["links"];
  stats?: MonsterDef["stats"];
};

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

/** Компактная строка для Discord: RFM1.<base64url(json)>. */
export function encodeMonsterShare(def: MonsterDef): string {
  const normalized = normalizeMonsterDef(def);
  const payload: SharePayload = {
    v: 1,
    name: normalized.name.slice(0, 28),
    parts: normalized.parts,
    links: normalized.links,
    stats: normalized.stats,
  };
  const json = JSON.stringify(payload);
  const bytes = new TextEncoder().encode(json);
  return SHARE_PREFIX + toBase64Url(bytes);
}

export function decodeMonsterShare(raw: string): MonsterDef | null {
  const text = raw.trim();
  if (!text.startsWith(SHARE_PREFIX)) return null;
  try {
    const bytes = fromBase64Url(text.slice(SHARE_PREFIX.length));
    const json = new TextDecoder().decode(bytes);
    const data = JSON.parse(json) as SharePayload;
    if (data?.v !== 1 || !Array.isArray(data.parts) || !Array.isArray(data.links)) {
      return null;
    }
    if (data.parts.length === 0 || data.parts.length > 24) return null;
    return normalizeMonsterDef({
      id: crypto.randomUUID(),
      name: String(data.name ?? "Shared").slice(0, 28),
      parts: data.parts,
      links: data.links,
      stats: data.stats,
      createdAt: Date.now(),
    });
  } catch {
    return null;
  }
}
