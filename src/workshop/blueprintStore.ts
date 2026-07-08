import { loadVersioned, saveVersioned } from "@/lib/storageSchema";
import type { BlueprintDef, WorkshopKind } from "./blueprintTypes";
import { blueprintToMonsterDef, monsterDefToBlueprint } from "./blueprintAdapters";
import {
  deleteMonster,
  getMonster,
  listMonsters,
  saveMonster,
} from "@/monster/monsterStore";

const BLUEPRINT_STORAGE_KEY = "ragdoll-blueprints";
const SCHEMA_VERSION = 1;

function normalizeKind(kind: string): WorkshopKind {
  if (kind === "prop") return "arena";
  if (kind === "monster" || kind === "item" || kind === "arena") return kind;
  return "monster";
}

function loadBlueprints(): BlueprintDef[] {
  return loadVersioned<BlueprintDef[]>({
    key: BLUEPRINT_STORAGE_KEY,
    version: SCHEMA_VERSION,
    migrate: (data) => {
      if (!Array.isArray(data)) return null;
      return (data as BlueprintDef[]).map((b) => ({
        ...b,
        kind: normalizeKind(b.kind as string),
      }));
    },
    fallback: () => [],
  });
}

function saveBlueprints(all: BlueprintDef[]): void {
  saveVersioned(BLUEPRINT_STORAGE_KEY, SCHEMA_VERSION, all);
}

export function listBlueprints(kind?: WorkshopKind): BlueprintDef[] {
  const monsters = listMonsters().map(monsterDefToBlueprint);
  const custom = loadBlueprints().filter((b) => b.kind !== "monster");
  const merged = [...monsters, ...custom];
  const filtered = kind ? merged.filter((b) => b.kind === kind) : merged;
  return filtered.sort((a, b) => b.createdAt - a.createdAt);
}

export function getBlueprint(id: string): BlueprintDef | undefined {
  const monster = getMonster(id);
  if (monster) return monsterDefToBlueprint(monster);
  return loadBlueprints().find((b) => b.id === id);
}

export function saveBlueprint(def: BlueprintDef): void {
  if (def.kind === "monster") {
    saveMonster(blueprintToMonsterDef(def));
    return;
  }
  const all = loadBlueprints();
  const index = all.findIndex((b) => b.id === def.id);
  const next = { ...def, createdAt: def.createdAt || Date.now() };
  if (index >= 0) all[index] = next;
  else all.push(next);
  saveBlueprints(all);
}

export function deleteBlueprint(id: string): void {
  const monster = getMonster(id);
  if (monster) {
    deleteMonster(id);
    return;
  }
  saveBlueprints(loadBlueprints().filter((b) => b.id !== id));
}
