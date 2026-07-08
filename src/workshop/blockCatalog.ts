import { PART_RADIUS } from "@/monster/monsterTypes";
import type { BlockKind, WorkshopKind } from "./blueprintTypes";

export interface BlockTemplate {
  id: string;
  blockKind: BlockKind;
  labelKey:
    | "blockHead"
    | "blockCoreS"
    | "blockCoreM"
    | "blockCoreL"
    | "blockArmor"
    | "blockSpike"
    | "blockGrip"
    | "blockJoint"
    | "blockMass";
  icon: string;
  radius: number;
  kinds: WorkshopKind[];
  /** Краткое описание для tooltip */
  descKey:
    | "blockHeadDesc"
    | "blockCoreDesc"
    | "blockArmorDesc"
    | "blockSpikeDesc"
    | "blockGripDesc"
    | "blockJointDesc"
    | "blockMassDesc";
  accent: string;
}

export const BLOCK_TEMPLATES: BlockTemplate[] = [
  {
    id: "head",
    blockKind: "head",
    labelKey: "blockHead",
    descKey: "blockHeadDesc",
    icon: "◉",
    radius: PART_RADIUS.head,
    kinds: ["monster"],
    accent: "#f8fafc",
  },
  {
    id: "core-s",
    blockKind: "core",
    labelKey: "blockCoreS",
    descKey: "blockCoreDesc",
    icon: "●",
    radius: PART_RADIUS.s,
    kinds: ["monster", "item", "arena"],
    accent: "#bae6fd",
  },
  {
    id: "core-m",
    blockKind: "core",
    labelKey: "blockCoreM",
    descKey: "blockCoreDesc",
    icon: "●",
    radius: PART_RADIUS.m,
    kinds: ["monster", "item", "arena"],
    accent: "#7dd3fc",
  },
  {
    id: "core-l",
    blockKind: "core",
    labelKey: "blockCoreL",
    descKey: "blockCoreDesc",
    icon: "●",
    radius: PART_RADIUS.l,
    kinds: ["monster", "item", "arena"],
    accent: "#38bdf8",
  },
  {
    id: "armor",
    blockKind: "armor",
    labelKey: "blockArmor",
    descKey: "blockArmorDesc",
    icon: "⬡",
    radius: PART_RADIUS.m,
    kinds: ["monster", "arena"],
    accent: "#94a3b8",
  },
  {
    id: "spike",
    blockKind: "spike",
    labelKey: "blockSpike",
    descKey: "blockSpikeDesc",
    icon: "✦",
    radius: PART_RADIUS.s,
    kinds: ["item", "arena"],
    accent: "#f87171",
  },
  {
    id: "grip",
    blockKind: "grip",
    labelKey: "blockGrip",
    descKey: "blockGripDesc",
    icon: "✊",
    radius: PART_RADIUS.s,
    kinds: ["item"],
    accent: "#fbbf24",
  },
  {
    id: "joint",
    blockKind: "joint",
    labelKey: "blockJoint",
    descKey: "blockJointDesc",
    icon: "○",
    radius: 6,
    kinds: ["item", "arena"],
    accent: "#c4b5fd",
  },
  {
    id: "mass",
    blockKind: "mass",
    labelKey: "blockMass",
    descKey: "blockMassDesc",
    icon: "◆",
    radius: PART_RADIUS.l,
    kinds: ["item", "arena"],
    accent: "#64748b",
  },
];

export function paletteForKind(kind: WorkshopKind): BlockTemplate[] {
  return BLOCK_TEMPLATES.filter((t) => t.kinds.includes(kind));
}

export function templateById(id: string): BlockTemplate | undefined {
  return BLOCK_TEMPLATES.find((t) => t.id === id);
}
