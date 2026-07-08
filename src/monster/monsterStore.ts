import type { MonsterDef } from "./monsterTypes";
import { normalizeMonsterDef } from "./monsterTypes";
import { STARTER_MONSTERS } from "./starterMonsters";

const STORAGE_KEY = "ragdoll-monsters";
const SEED_VERSION_KEY = "ragdoll-monsters-seed-v";
const SEED_VERSION = 2;

function templatesToDefs(
  templates: typeof STARTER_MONSTERS,
  baseTime = Date.now(),
): MonsterDef[] {
  return templates.map((template, i) =>
    normalizeMonsterDef({
      ...template,
      id: crypto.randomUUID(),
      createdAt: baseTime - i,
    }),
  );
}

function loadAll(): MonsterDef[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as MonsterDef[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveAll(monsters: MonsterDef[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(monsters));
}

export function listMonsters(): MonsterDef[] {
  return loadAll().sort((a, b) => b.createdAt - a.createdAt);
}

export function getMonster(id: string): MonsterDef | undefined {
  return loadAll().find((m) => m.id === id);
}

export function saveMonster(monster: MonsterDef): void {
  const all = loadAll();
  const index = all.findIndex((m) => m.id === monster.id);
  const next = { ...monster, createdAt: monster.createdAt || Date.now() };
  if (index >= 0) all[index] = next;
  else all.push(next);
  saveAll(all);
}

export function deleteMonster(id: string): void {
  saveAll(loadAll().filter((m) => m.id !== id));
}

/** Первый заход — пресеты в библиотеке; при обновлении — добавляет новые по имени. */
export function ensureStarterMonsters(): void {
  const all = loadAll();
  const savedVersion = Number(localStorage.getItem(SEED_VERSION_KEY) ?? 0);

  if (all.length === 0) {
    saveAll(templatesToDefs(STARTER_MONSTERS));
    localStorage.setItem(SEED_VERSION_KEY, String(SEED_VERSION));
    return;
  }

  if (savedVersion >= SEED_VERSION) return;

  const existingNames = new Set(all.map((m) => m.name));
  const missing = STARTER_MONSTERS.filter((t) => !existingNames.has(t.name));
  if (missing.length > 0) {
    saveAll([...all, ...templatesToDefs(missing)]);
  }
  localStorage.setItem(SEED_VERSION_KEY, String(SEED_VERSION));
}
