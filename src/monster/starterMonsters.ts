import { PART_RADIUS, type MonsterDef } from "./monsterTypes";

type StarterTemplate = Omit<MonsterDef, "id" | "createdAt">;

/** Готовые монстры для библиотеки — каждый с характерным силуэтом и тактикой. */
export const STARTER_MONSTERS: StarterTemplate[] = [
  {
    name: "MONSTER KNUCKLE",
    parts: [
      { x: 0, y: -48, radius: PART_RADIUS.head, isHead: true },
      { x: 0, y: -8, radius: PART_RADIUS.m, isHead: false },
      { x: -38, y: 8, radius: PART_RADIUS.l, isHead: false, role: "armor" },
      { x: 38, y: 8, radius: PART_RADIUS.l, isHead: false, role: "armor" },
      { x: -22, y: 32, radius: PART_RADIUS.s, isHead: false },
      { x: 22, y: 32, radius: PART_RADIUS.s, isHead: false },
    ],
    links: [
      { a: 0, b: 1, type: "rigid" },
      { a: 1, b: 2, type: "rigid" },
      { a: 1, b: 3, type: "rigid" },
      { a: 1, b: 4, type: "spring" },
      { a: 1, b: 5, type: "spring" },
      { a: 4, b: 2, type: "rope" },
      { a: 5, b: 3, type: "rope" },
    ],
    stats: { maxHp: 220, defense: 12 },
  },
  {
    name: "MONSTER MEDUSA",
    parts: [
      { x: 0, y: -18, radius: PART_RADIUS.head, isHead: true },
      { x: 0, y: 12, radius: PART_RADIUS.l, isHead: false },
      { x: -44, y: 0, radius: PART_RADIUS.s, isHead: false, role: "armor" },
      { x: 44, y: 0, radius: PART_RADIUS.s, isHead: false, role: "armor" },
      { x: -28, y: 38, radius: PART_RADIUS.s, isHead: false },
      { x: 28, y: 38, radius: PART_RADIUS.s, isHead: false },
      { x: 0, y: 48, radius: PART_RADIUS.s, isHead: false },
    ],
    links: [
      { a: 0, b: 1, type: "rigid" },
      { a: 1, b: 2, type: "rope" },
      { a: 1, b: 3, type: "rope" },
      { a: 1, b: 4, type: "spring" },
      { a: 1, b: 5, type: "spring" },
      { a: 1, b: 6, type: "rope" },
    ],
    stats: { maxHp: 260, defense: 6 },
  },
  {
    name: "MONSTER BULL",
    parts: [
      { x: 0, y: -56, radius: PART_RADIUS.head, isHead: true },
      { x: 0, y: -18, radius: PART_RADIUS.m, isHead: false },
      { x: 0, y: 28, radius: PART_RADIUS.l, isHead: false, role: "armor" },
      { x: 0, y: 58, radius: PART_RADIUS.s, isHead: false },
    ],
    links: [
      { a: 0, b: 1, type: "spring" },
      { a: 1, b: 2, type: "rigid" },
      { a: 2, b: 3, type: "rope" },
    ],
    stats: { maxHp: 280, defense: 18 },
  },
  {
    name: "MONSTER TRIPOD",
    parts: [
      { x: 0, y: -42, radius: PART_RADIUS.head, isHead: true },
      { x: 0, y: 0, radius: PART_RADIUS.m, isHead: false },
      { x: -36, y: 44, radius: PART_RADIUS.m, isHead: false, role: "armor" },
      { x: 36, y: 44, radius: PART_RADIUS.m, isHead: false, role: "armor" },
      { x: 0, y: 52, radius: PART_RADIUS.s, isHead: false, role: "armor" },
    ],
    links: [
      { a: 0, b: 1, type: "rigid" },
      { a: 1, b: 2, type: "rope" },
      { a: 1, b: 3, type: "rope" },
      { a: 1, b: 4, type: "rope" },
      { a: 2, b: 3, type: "spring" },
    ],
    stats: { maxHp: 240, defense: 22 },
  },
  {
    name: "MONSTER GLASS",
    parts: [
      { x: 0, y: -64, radius: PART_RADIUS.head, isHead: true },
      { x: 0, y: -32, radius: PART_RADIUS.s, isHead: false },
      { x: 0, y: 8, radius: PART_RADIUS.l, isHead: false },
      { x: -32, y: 4, radius: PART_RADIUS.s, isHead: false, role: "armor" },
      { x: 32, y: 4, radius: PART_RADIUS.s, isHead: false, role: "armor" },
    ],
    links: [
      { a: 0, b: 1, type: "spring" },
      { a: 1, b: 2, type: "spring" },
      { a: 2, b: 3, type: "rigid" },
      { a: 2, b: 4, type: "rigid" },
    ],
    stats: { maxHp: 180, defense: 4 },
  },
];

export const STARTER_MONSTER_NAMES = STARTER_MONSTERS.map((m) => m.name);
