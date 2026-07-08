import { PART_RADIUS } from "@/monster/monsterTypes";
import type { BlockKind } from "./blueprintTypes";
import type { LocaleStrings } from "@/i18n/types";

type LabelKey =
  | "blockHead"
  | "blockCoreS"
  | "blockCoreM"
  | "blockCoreL"
  | "blockArmor"
  | "blockSpike"
  | "blockGrip"
  | "blockJoint"
  | "blockMass";

const LABEL_KEYS: Record<BlockKind, LabelKey> = {
  head: "blockHead",
  core: "blockCoreM",
  armor: "blockArmor",
  spike: "blockSpike",
  grip: "blockGrip",
  joint: "blockJoint",
  mass: "blockMass",
};

/** Ядро бывает трёх размеров (S/M/L) при одном blockKind — различаем по радиусу. */
function coreLabelKey(radius: number): LabelKey {
  if (radius <= PART_RADIUS.s) return "blockCoreS";
  if (radius >= PART_RADIUS.l) return "blockCoreL";
  return "blockCoreM";
}

export function blockKindLabel(
  kind: BlockKind,
  t: LocaleStrings["workshop"],
  radius?: number,
): string {
  const key =
    kind === "core" && radius !== undefined
      ? coreLabelKey(radius)
      : LABEL_KEYS[kind];
  return t[key] ?? kind;
}
