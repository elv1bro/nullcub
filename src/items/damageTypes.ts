export interface DamageTypeDef {
  id: string;
  name: string;
  color: string;
  /** Доля игнорируемой защиты (pierce). */
  pierceIgnoreDefPct?: number;
  /** Множитель отброса (force). */
  knockbackMult?: number;
  /** DoT за тик (fire). */
  dotPerTick?: number;
}

const damageTypes = new Map<string, DamageTypeDef>();

export function registerDamageType(def: DamageTypeDef): void {
  damageTypes.set(def.id, def);
}

export function getDamageType(id: string): DamageTypeDef {
  return damageTypes.get(id) ?? damageTypes.get("blunt")!;
}

export function allDamageTypes(): DamageTypeDef[] {
  return [...damageTypes.values()];
}

registerDamageType({
  id: "blunt",
  name: "Blunt",
  color: "#f87171",
});

registerDamageType({
  id: "force",
  name: "Force",
  color: "#38bdf8",
  knockbackMult: 1.6,
});

registerDamageType({
  id: "pierce",
  name: "Pierce",
  color: "#a78bfa",
  pierceIgnoreDefPct: 0.5,
});

registerDamageType({
  id: "fire",
  name: "Fire",
  color: "#fb923c",
  dotPerTick: 3,
});

registerDamageType({
  id: "slash",
  name: "Slash",
  color: "#f472b6",
  pierceIgnoreDefPct: 0.25,
});

registerDamageType({
  id: "shock",
  name: "Shock",
  color: "#facc15",
  knockbackMult: 1.25,
});
