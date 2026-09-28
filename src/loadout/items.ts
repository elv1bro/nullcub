import type { PassiveItemId } from "./types";
import { PASSIVE_ITEM_IDS } from "./types";

export interface PassiveItemDef {
  id: PassiveItemId;
  /** Ключ в t.loadout.item */
  nameKey: PassiveItemId;
  /** Множитель атаки (1 = без изменений). */
  atkMult?: number;
  /**
   * Множитель защиты относительно 1.
   * В combat-модах: (defMult - 1) * 100 → defPct.
   */
  defMult?: number;
  /** Доп. защита головы (доля 0..1). */
  headDefBonus?: number;
  /** Множитель скорости движения. */
  moveMult?: number;
  /** Множитель исходящего knockback. */
  knockbackOutMult?: number;
  /** Шанс крита 0..1. */
  critChance?: number;
}

export const ITEM_DEFS: Record<PassiveItemId, PassiveItemDef> = {
  gloves: {
    id: "gloves",
    nameKey: "gloves",
    atkMult: 1.12,
  },
  helm: {
    id: "helm",
    nameKey: "helm",
    headDefBonus: 0.15,
    defMult: 1.05,
  },
  boots: {
    id: "boots",
    nameKey: "boots",
    moveMult: 1.12,
  },
  armor: {
    id: "armor",
    nameKey: "armor",
    defMult: 1.15,
  },
  amulet: {
    id: "amulet",
    nameKey: "amulet",
    critChance: 0.08,
    atkMult: 1.04,
  },
  horseshoe: {
    id: "horseshoe",
    nameKey: "horseshoe",
    knockbackOutMult: 1.18,
  },
  brassKnuckles: {
    id: "brassKnuckles",
    nameKey: "brassKnuckles",
    atkMult: 1.092,
  },
  padding: {
    id: "padding",
    nameKey: "padding",
    defMult: 1.06,
  },
  sprintShoes: {
    id: "sprintShoes",
    nameKey: "sprintShoes",
    moveMult: 1.113,
  },
  magnetBand: {
    id: "magnetBand",
    nameKey: "magnetBand",
    atkMult: 1.03,
  },
  bananaPeel: {
    id: "bananaPeel",
    nameKey: "bananaPeel",
    critChance: 0.04,
    atkMult: 1.03,
  },
  redBandana: {
    id: "redBandana",
    nameKey: "redBandana",
    atkMult: 1.04,
    defMult: 1.04,
  },
  friendshipBracelet: {
    id: "friendshipBracelet",
    nameKey: "friendshipBracelet",
    defMult: 1.04,
    moveMult: 1.03,
  },
  weightedWraps: {
    id: "weightedWraps",
    nameKey: "weightedWraps",
    atkMult: 1.04,
  },
  chainmail: {
    id: "chainmail",
    nameKey: "chainmail",
    defMult: 1.113,
  },
  springBoots: {
    id: "springBoots",
    nameKey: "springBoots",
    moveMult: 1.166,
  },
  glueGloves: {
    id: "glueGloves",
    nameKey: "glueGloves",
    atkMult: 1.03,
  },
  whoopeeCushion: {
    id: "whoopeeCushion",
    nameKey: "whoopeeCushion",
    critChance: 0.04,
    atkMult: 1.03,
  },
  denimVest: {
    id: "denimVest",
    nameKey: "denimVest",
    atkMult: 1.04,
    defMult: 1.04,
  },
  coachWhistle: {
    id: "coachWhistle",
    nameKey: "coachWhistle",
    defMult: 1.04,
    moveMult: 1.03,
  },
  razorTape: {
    id: "razorTape",
    nameKey: "razorTape",
    atkMult: 1.144,
  },
  asbestosCloak: {
    id: "asbestosCloak",
    nameKey: "asbestosCloak",
    defMult: 1.166,
  },
  iceSkates: {
    id: "iceSkates",
    nameKey: "iceSkates",
    moveMult: 1.113,
  },
  grease: {
    id: "grease",
    nameKey: "grease",
    atkMult: 1.03,
  },
  clownNose: {
    id: "clownNose",
    nameKey: "clownNose",
    critChance: 0.04,
    atkMult: 1.03,
  },
  chainWallet: {
    id: "chainWallet",
    nameKey: "chainWallet",
    atkMult: 1.04,
    defMult: 1.04,
  },
  sharedCanteen: {
    id: "sharedCanteen",
    nameKey: "sharedCanteen",
    defMult: 1.04,
    moveMult: 1.03,
  },
  spikeCollar: {
    id: "spikeCollar",
    nameKey: "spikeCollar",
    atkMult: 1.092,
  },
  rubberSuit: {
    id: "rubberSuit",
    nameKey: "rubberSuit",
    defMult: 1.113,
  },
  cleats: {
    id: "cleats",
    nameKey: "cleats",
    moveMult: 1.06,
  },
  toolBelt: {
    id: "toolBelt",
    nameKey: "toolBelt",
    atkMult: 1.03,
  },
  rubberChicken: {
    id: "rubberChicken",
    nameKey: "rubberChicken",
    critChance: 0.04,
    atkMult: 1.03,
  },
  pilotGoggles: {
    id: "pilotGoggles",
    nameKey: "pilotGoggles",
    atkMult: 1.04,
    defMult: 1.04,
  },
  mascotHead: {
    id: "mascotHead",
    nameKey: "mascotHead",
    defMult: 1.04,
    moveMult: 1.03,
  },
  powerBelt: {
    id: "powerBelt",
    nameKey: "powerBelt",
    atkMult: 1.144,
  },
  kneePads: {
    id: "kneePads",
    nameKey: "kneePads",
    defMult: 1.06,
  },
  rocketSoles: {
    id: "rocketSoles",
    nameKey: "rocketSoles",
    moveMult: 1.219,
  },
  stopwatch: {
    id: "stopwatch",
    nameKey: "stopwatch",
    moveMult: 1.04,
  },
  fidgetSpinner: {
    id: "fidgetSpinner",
    nameKey: "fidgetSpinner",
    critChance: 0.04,
    atkMult: 1.03,
  },
  leatherJacket: {
    id: "leatherJacket",
    nameKey: "leatherJacket",
    atkMult: 1.04,
    defMult: 1.04,
  },
  berserkerCharm: {
    id: "berserkerCharm",
    nameKey: "berserkerCharm",
    atkMult: 1.196,
    critChance: 0.06,
  },
  elbowGuards: {
    id: "elbowGuards",
    nameKey: "elbowGuards",
    defMult: 1.06,
  },
  featherHat: {
    id: "featherHat",
    nameKey: "featherHat",
    moveMult: 1.166,
  },
  battery: {
    id: "battery",
    nameKey: "battery",
    moveMult: 1.04,
  },
  cursedSock: {
    id: "cursedSock",
    nameKey: "cursedSock",
    critChance: 0.04,
    atkMult: 1.03,
  },
  propellerBeanie: {
    id: "propellerBeanie",
    nameKey: "propellerBeanie",
    atkMult: 1.04,
    defMult: 1.04,
  },
  critCoin: {
    id: "critCoin",
    nameKey: "critCoin",
    atkMult: 1.144,
  },
  cup: {
    id: "cup",
    nameKey: "cup",
    defMult: 1.113,
  },
  tailwindCape: {
    id: "tailwindCape",
    nameKey: "tailwindCape",
    moveMult: 1.219,
  },
  spyglass: {
    id: "spyglass",
    nameKey: "spyglass",
    atkMult: 1.03,
  },
  mysteryBox: {
    id: "mysteryBox",
    nameKey: "mysteryBox",
    critChance: 0.04,
    atkMult: 1.03,
  },
  chefHat: {
    id: "chefHat",
    nameKey: "chefHat",
    atkMult: 1.04,
    defMult: 1.04,
  },
  heavyMedal: {
    id: "heavyMedal",
    nameKey: "heavyMedal",
    atkMult: 1.092,
    knockbackOutMult: 1.18,
  },
  riotShieldShard: {
    id: "riotShieldShard",
    nameKey: "riotShieldShard",
    defMult: 1.166,
  },
  anchorBoots: {
    id: "anchorBoots",
    nameKey: "anchorBoots",
    moveMult: 0.92,
    defMult: 1.08,
  },
  luckyDice: {
    id: "luckyDice",
    nameKey: "luckyDice",
    atkMult: 1.03,
  },
  mirrorShard: {
    id: "mirrorShard",
    nameKey: "mirrorShard",
    critChance: 0.04,
    atkMult: 1.03,
  },
  apron: {
    id: "apron",
    nameKey: "apron",
    atkMult: 1.04,
    defMult: 1.04,
  },
  vampireTooth: {
    id: "vampireTooth",
    nameKey: "vampireTooth",
    atkMult: 1.196,
    critChance: 0.06,
  },
  guardianAngel: {
    id: "guardianAngel",
    nameKey: "guardianAngel",
    defMult: 1.293,
  },
  rollerBlades: {
    id: "rollerBlades",
    nameKey: "rollerBlades",
    moveMult: 1.166,
  },
  contract: {
    id: "contract",
    nameKey: "contract",
    atkMult: 1.03,
  },
  hotSauce: {
    id: "hotSauce",
    nameKey: "hotSauce",
    critChance: 0.04,
    atkMult: 1.03,
  },
  ladle: {
    id: "ladle",
    nameKey: "ladle",
    atkMult: 1.04,
    defMult: 1.04,
  },
  executionSeal: {
    id: "executionSeal",
    nameKey: "executionSeal",
    atkMult: 1.269,
    critChance: 0.1,
  },
  plasterKit: {
    id: "plasterKit",
    nameKey: "plasterKit",
    defMult: 1.113,
  },
  gripSocks: {
    id: "gripSocks",
    nameKey: "gripSocks",
    moveMult: 1.06,
  },
  coffee: {
    id: "coffee",
    nameKey: "coffee",
    atkMult: 1.03,
  },
  leadBalloon: {
    id: "leadBalloon",
    nameKey: "leadBalloon",
    critChance: 0.04,
    atkMult: 1.03,
  },
  refereeShirt: {
    id: "refereeShirt",
    nameKey: "refereeShirt",
    atkMult: 1.04,
    defMult: 1.04,
  },
  comboBeads: {
    id: "comboBeads",
    nameKey: "comboBeads",
    atkMult: 1.144,
  },
  secondHeart: {
    id: "secondHeart",
    nameKey: "secondHeart",
    defMult: 1.293,
  },
  warpShoelaces: {
    id: "warpShoelaces",
    nameKey: "warpShoelaces",
    moveMult: 1.293,
  },
  energyDrink: {
    id: "energyDrink",
    nameKey: "energyDrink",
    moveMult: 1.04,
  },
  echoFlower: {
    id: "echoFlower",
    nameKey: "echoFlower",
    critChance: 0.04,
    atkMult: 1.03,
  },
  whistle: {
    id: "whistle",
    nameKey: "whistle",
    atkMult: 1.04,
    defMult: 1.04,
  },
  impactGel: {
    id: "impactGel",
    nameKey: "impactGel",
    atkMult: 1.092,
  },
  thornMail: {
    id: "thornMail",
    nameKey: "thornMail",
    defMult: 1.219,
  },
  balloonBelt: {
    id: "balloonBelt",
    nameKey: "balloonBelt",
    moveMult: 1.166,
  },
  mapScrap: {
    id: "mapScrap",
    nameKey: "mapScrap",
    atkMult: 1.03,
  },
  partyHat: {
    id: "partyHat",
    nameKey: "partyHat",
    critChance: 0.04,
    atkMult: 1.03,
  },
  boxingRobe: {
    id: "boxingRobe",
    nameKey: "boxingRobe",
    atkMult: 1.04,
    defMult: 1.04,
  },
  nailBatGrip: {
    id: "nailBatGrip",
    nameKey: "nailBatGrip",
    atkMult: 1.144,
  },
  foamHelmet: {
    id: "foamHelmet",
    nameKey: "foamHelmet",
    defMult: 1.06,
    headDefBonus: 0.12,
  },
  backpack: {
    id: "backpack",
    nameKey: "backpack",
    atkMult: 1.03,
  },
  rivalRibbon: {
    id: "rivalRibbon",
    nameKey: "rivalRibbon",
    critChance: 0.04,
    atkMult: 1.03,
  },
  championshipBelt: {
    id: "championshipBelt",
    nameKey: "championshipBelt",
    atkMult: 1.04,
    defMult: 1.04,
  },
  spearOil: {
    id: "spearOil",
    nameKey: "spearOil",
    atkMult: 1.092,
  },
  sandbag: {
    id: "sandbag",
    nameKey: "sandbag",
    defMult: 1.166,
  },
  bandageRoll: {
    id: "bandageRoll",
    nameKey: "bandageRoll",
    atkMult: 1.03,
  },
  emptyBottle: {
    id: "emptyBottle",
    nameKey: "emptyBottle",
    critChance: 0.04,
    atkMult: 1.03,
  },
  mouthguard: {
    id: "mouthguard",
    nameKey: "mouthguard",
    atkMult: 1.04,
    defMult: 1.04,
  },
  flameRag: {
    id: "flameRag",
    nameKey: "flameRag",
    atkMult: 1.144,
  },
  corkJacket: {
    id: "corkJacket",
    nameKey: "corkJacket",
    defMult: 1.113,
  },
  trophyEar: {
    id: "trophyEar",
    nameKey: "trophyEar",
    atkMult: 1.03,
  },
  crownOfFool: {
    id: "crownOfFool",
    nameKey: "crownOfFool",
    critChance: 0.04,
    atkMult: 1.03,
  },
  ninjaHeadband: {
    id: "ninjaHeadband",
    nameKey: "ninjaHeadband",
    atkMult: 1.04,
    defMult: 1.04,
  },
  iceCube: {
    id: "iceCube",
    nameKey: "iceCube",
    atkMult: 1.144,
  },
  smokeFilter: {
    id: "smokeFilter",
    nameKey: "smokeFilter",
    defMult: 1.06,
  },
  practiceDummy: {
    id: "practiceDummy",
    nameKey: "practiceDummy",
    atkMult: 1.03,
  },
};

export function getItemDef(id: PassiveItemId): PassiveItemDef {
  return ITEM_DEFS[id];
}

export function allItemIds(): PassiveItemId[] {
  return [...PASSIVE_ITEM_IDS];
}
