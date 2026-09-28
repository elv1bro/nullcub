/** Идентификаторы способностей (база + активные/пассивные слоты). */
export type AbilityId =
  | "dash"
  | "flip"
  | "brace"
  | "shield"
  | "slam"
  | "magnet"
  | "push"
  | "vamp"
  | "giant"
  | "spikes"
  | "secondWind"
  | "freezeEnemy"
  | "ghost"
  | "uppercut"
  | "counter"
  | "dodgeRoll"
  | "lasso"
  | "sharePain"
  | "luckyStrike"
  | "magnetHands"
  | "bellyflop"
  | "parry"
  | "doubleJump"
  | "tripwire"
  | "cheer"
  | "banana"
  | "disarmPulse"
  | "headbutt"
  | "turtle"
  | "wallKick"
  | "stunSlap"
  | "medic"
  | "fart"
  | "weaponYank"
  | "spinKick"
  | "foamArmor"
  | "slide"
  | "confuse"
  | "guardAlly"
  | "inflatable"
  | "scavenge"
  | "dropkick"
  | "ironJaw"
  | "rocketJump"
  | "vacuum"
  | "tagTeam"
  | "shrink"
  | "timeout"
  | "clothesline"
  | "thickSkin"
  | "grapple"
  | "repel"
  | "lootSense"
  | "mirror"
  | "scout"
  | "suplex"
  | "lastStand"
  | "teleportSwap"
  | "glue"
  | "rngBomb"
  | "warmup"
  | "piledriver"
  | "bandage"
  | "blink"
  | "banish"
  | "drunk"
  | "cooldownCut"
  | "shoulderCharge"
  | "regen"
  | "hover"
  | "taunt"
  | "hotPotato"
  | "doubleTap"
  | "elbowDrop"
  | "adrenaline"
  | "sprint"
  | "silence"
  | "pirouette"
  | "nullField"
  | "whiplash"
  | "bubble"
  | "moonwalk"
  | "slowField"
  | "yodel"
  | "overclock"
  | "groundPound"
  | "anchor"
  | "stickyFeet"
  | "chain"
  | "rubber"
  | "echo"
  | "haymaker"
  | "softLanding"
  | "jetpack"
  | "mark"
  | "copycat"
  | "knee"
  | "emergencyExit"
  | "pin"
  | "lowGravity";

/** Пассивные предметы лодаута. */
export type PassiveItemId =
  | "gloves"
  | "helm"
  | "boots"
  | "armor"
  | "amulet"
  | "horseshoe"
  | "brassKnuckles"
  | "padding"
  | "sprintShoes"
  | "magnetBand"
  | "bananaPeel"
  | "redBandana"
  | "friendshipBracelet"
  | "weightedWraps"
  | "chainmail"
  | "springBoots"
  | "glueGloves"
  | "whoopeeCushion"
  | "denimVest"
  | "coachWhistle"
  | "razorTape"
  | "asbestosCloak"
  | "iceSkates"
  | "grease"
  | "clownNose"
  | "chainWallet"
  | "sharedCanteen"
  | "spikeCollar"
  | "rubberSuit"
  | "cleats"
  | "toolBelt"
  | "rubberChicken"
  | "pilotGoggles"
  | "mascotHead"
  | "powerBelt"
  | "kneePads"
  | "rocketSoles"
  | "stopwatch"
  | "fidgetSpinner"
  | "leatherJacket"
  | "berserkerCharm"
  | "elbowGuards"
  | "featherHat"
  | "battery"
  | "cursedSock"
  | "propellerBeanie"
  | "critCoin"
  | "cup"
  | "tailwindCape"
  | "spyglass"
  | "mysteryBox"
  | "chefHat"
  | "heavyMedal"
  | "riotShieldShard"
  | "anchorBoots"
  | "luckyDice"
  | "mirrorShard"
  | "apron"
  | "vampireTooth"
  | "guardianAngel"
  | "rollerBlades"
  | "contract"
  | "hotSauce"
  | "ladle"
  | "executionSeal"
  | "plasterKit"
  | "gripSocks"
  | "coffee"
  | "leadBalloon"
  | "refereeShirt"
  | "comboBeads"
  | "secondHeart"
  | "warpShoelaces"
  | "energyDrink"
  | "echoFlower"
  | "whistle"
  | "impactGel"
  | "thornMail"
  | "balloonBelt"
  | "mapScrap"
  | "partyHat"
  | "boxingRobe"
  | "nailBatGrip"
  | "foamHelmet"
  | "backpack"
  | "rivalRibbon"
  | "championshipBelt"
  | "spearOil"
  | "sandbag"
  | "bandageRoll"
  | "emptyBottle"
  | "mouthguard"
  | "flameRag"
  | "corkJacket"
  | "trophyEar"
  | "crownOfFool"
  | "ninjaHeadband"
  | "iceCube"
  | "smokeFilter"
  | "practiceDummy";

export type DraftCardId = AbilityId | PassiveItemId;

export type BaseAbilityId = "dash" | "flip" | "brace";

export interface FighterLoadout {
  /** Базовая способность — всегда доступна. */
  base: BaseAbilityId;
  /** Два слота активных/пассивных способностей. */
  abilities: [AbilityId | null, AbilityId | null];
  /** Два слота предметов. */
  items: [PassiveItemId | null, PassiveItemId | null];
}

export function emptyLoadout(base: BaseAbilityId = "dash"): FighterLoadout {
  return {
    base,
    abilities: [null, null],
    items: [null, null],
  };
}

/** Классический старт: dash + пустые слоты. */
export function defaultLoadout(): FighterLoadout {
  return emptyLoadout("dash");
}

export const BASE_ABILITY_IDS: readonly BaseAbilityId[] = [
  "dash",
  "flip",
  "brace",
] as const;

export const ALL_ABILITY_IDS: readonly AbilityId[] = [
  "dash",
  "flip",
  "brace",
  "shield",
  "slam",
  "magnet",
  "push",
  "vamp",
  "giant",
  "spikes",
  "secondWind",
  "freezeEnemy",
  "ghost",
  "uppercut",
  "counter",
  "dodgeRoll",
  "lasso",
  "sharePain",
  "luckyStrike",
  "magnetHands",
  "bellyflop",
  "parry",
  "doubleJump",
  "tripwire",
  "cheer",
  "banana",
  "disarmPulse",
  "headbutt",
  "turtle",
  "wallKick",
  "stunSlap",
  "medic",
  "fart",
  "weaponYank",
  "spinKick",
  "foamArmor",
  "slide",
  "confuse",
  "guardAlly",
  "inflatable",
  "scavenge",
  "dropkick",
  "ironJaw",
  "rocketJump",
  "vacuum",
  "tagTeam",
  "shrink",
  "timeout",
  "clothesline",
  "thickSkin",
  "grapple",
  "repel",
  "lootSense",
  "mirror",
  "scout",
  "suplex",
  "lastStand",
  "teleportSwap",
  "glue",
  "rngBomb",
  "warmup",
  "piledriver",
  "bandage",
  "blink",
  "banish",
  "drunk",
  "cooldownCut",
  "shoulderCharge",
  "regen",
  "hover",
  "taunt",
  "hotPotato",
  "doubleTap",
  "elbowDrop",
  "adrenaline",
  "sprint",
  "silence",
  "pirouette",
  "nullField",
  "whiplash",
  "bubble",
  "moonwalk",
  "slowField",
  "yodel",
  "overclock",
  "groundPound",
  "anchor",
  "stickyFeet",
  "chain",
  "rubber",
  "echo",
  "haymaker",
  "softLanding",
  "jetpack",
  "mark",
  "copycat",
  "knee",
  "emergencyExit",
  "pin",
  "lowGravity",
] as const;

export const PASSIVE_ITEM_IDS: readonly PassiveItemId[] = [
  "gloves",
  "helm",
  "boots",
  "armor",
  "amulet",
  "horseshoe",
  "brassKnuckles",
  "padding",
  "sprintShoes",
  "magnetBand",
  "bananaPeel",
  "redBandana",
  "friendshipBracelet",
  "weightedWraps",
  "chainmail",
  "springBoots",
  "glueGloves",
  "whoopeeCushion",
  "denimVest",
  "coachWhistle",
  "razorTape",
  "asbestosCloak",
  "iceSkates",
  "grease",
  "clownNose",
  "chainWallet",
  "sharedCanteen",
  "spikeCollar",
  "rubberSuit",
  "cleats",
  "toolBelt",
  "rubberChicken",
  "pilotGoggles",
  "mascotHead",
  "powerBelt",
  "kneePads",
  "rocketSoles",
  "stopwatch",
  "fidgetSpinner",
  "leatherJacket",
  "berserkerCharm",
  "elbowGuards",
  "featherHat",
  "battery",
  "cursedSock",
  "propellerBeanie",
  "critCoin",
  "cup",
  "tailwindCape",
  "spyglass",
  "mysteryBox",
  "chefHat",
  "heavyMedal",
  "riotShieldShard",
  "anchorBoots",
  "luckyDice",
  "mirrorShard",
  "apron",
  "vampireTooth",
  "guardianAngel",
  "rollerBlades",
  "contract",
  "hotSauce",
  "ladle",
  "executionSeal",
  "plasterKit",
  "gripSocks",
  "coffee",
  "leadBalloon",
  "refereeShirt",
  "comboBeads",
  "secondHeart",
  "warpShoelaces",
  "energyDrink",
  "echoFlower",
  "whistle",
  "impactGel",
  "thornMail",
  "balloonBelt",
  "mapScrap",
  "partyHat",
  "boxingRobe",
  "nailBatGrip",
  "foamHelmet",
  "backpack",
  "rivalRibbon",
  "championshipBelt",
  "spearOil",
  "sandbag",
  "bandageRoll",
  "emptyBottle",
  "mouthguard",
  "flameRag",
  "corkJacket",
  "trophyEar",
  "crownOfFool",
  "ninjaHeadband",
  "iceCube",
  "smokeFilter",
  "practiceDummy",
] as const;

export function isBaseAbilityId(id: string): id is BaseAbilityId {
  return (BASE_ABILITY_IDS as readonly string[]).includes(id);
}

export function isAbilityId(id: string): id is AbilityId {
  return (ALL_ABILITY_IDS as readonly string[]).includes(id);
}

export function isPassiveItemId(id: string): id is PassiveItemId {
  return (PASSIVE_ITEM_IDS as readonly string[]).includes(id);
}
