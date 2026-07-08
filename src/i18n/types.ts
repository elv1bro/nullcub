export type Language = "en" | "ru";

export interface LocaleStrings {
  game: {
    title: string;
    titleAccent: string;
    subtitle: string;
  };
  menu: Record<
    | "play"
    | "customize"
    | "hideCustomize"
    | "options"
    | "controls"
    | "back"
    | "close"
    | "previewHint"
    | "webcamOff"
    | "breadcrumbHome"
    | "breakingFree"
    | "playPickHint"
    | "workshop"
    | "achievements",
    string
  >;
  gameType: Record<
    | "title"
    | "quickBattle"
    | "quickBattleHint"
    | "campaign"
    | "campaignHint"
    | "back",
    string
  >;
  playScope: Record<
    | "title"
    | "local"
    | "localHint"
    | "local2p"
    | "local2pHint"
    | "local4ffa"
    | "local4ffaHint"
    | "multiplayer"
    | "multiplayerSoon"
    | "back",
    string
  >;
  multiplayer: Record<
    | "createRoom"
    | "roomId"
    | "join"
    | "cam"
    | "mic"
    | "faceVideo"
    | "faceTracking"
    | "faceNone"
    | "readyOn"
    | "readyOff"
    | "start",
    string
  >;
  team: Record<
    | "title"
    | "hint"
    | "emptySlot"
    | "badgeYou"
    | "badgeLocal"
    | "badgeOnline"
    | "addPlayer"
    | "copyLink"
    | "linkCopied"
    | "pasteLink"
    | "addLocal"
    | "remove"
    | "soloHint"
    | "localHint"
    | "onlineHint"
    | "localPlayer"
    | "start"
    | "startOnline"
    | "waitHost"
    | "slotInvite"
    | "mediaLabel"
    | "localControlsHint",
    string
  >;
  common: Record<"back", string>;
  campaign: Record<
    | "title"
    | "local"
    | "localHint"
    | "online"
    | "onlineSoon"
    | "wip"
    | "back"
    | "bouncerTitle"
    | "bouncerHint"
    | "chapterLocked"
    | "chapterFight"
    | "chapterIntro",
    string
  >;
  workshop: Record<
    | "title"
    | "hint"
    | "name"
    | "defaultName"
    | "toolAdd"
    | "toolLink"
    | "toolDelete"
    | "sizeHead"
    | "save"
    | "clear"
    | "fight"
    | "saved"
    | "loaded"
    | "removed"
    | "cleared"
    | "partAdded"
    | "linked"
    | "linkRemoved"
    | "deleted"
    | "pickSecond"
    | "oneHead"
    | "needParts"
    | "needHead"
    | "needLinks"
    | "needConnected"
    | "needHurtbox"
    | "remove"
    | "library"
    | "libraryEmpty"
    | "params"
    | "tools"
    | "statHp"
    | "statDefense"
    | "newPartSize"
    | "newPartRole"
    | "partRoleHurtbox"
    | "partRoleArmor"
    | "partSelected"
    | "selectedPart"
    | "headAlwaysHurtbox"
    | "deletePart"
    | "linkHint"
    | "linkType"
    | "linkRigid"
    | "linkSpring"
    | "linkRope"
    | "physicsPreview"
    | "physicsHint"
    | "physicsStart"
    | "physicsStop"
    | "physicsOn"
    | "physicsOff"
    | "studioTitle"
    | "kindLabel"
    | "kindMonster"
    | "kindItem"
    | "kindArena"
    | "kindMonsterDesc"
    | "kindItemDesc"
    | "kindArenaDesc"
    | "projectType"
    | "monsterStats"
    | "itemStats"
    | "arenaStats"
    | "arenaStatic"
    | "arenaHint"
    | "itemToughness"
    | "paletteLead"
    | "paletteDropActive"
    | "paletteFoot"
    | "canvasDropHint"
    | "kindSwitched"
    | "palette"
    | "paletteHint"
    | "testMode"
    | "fightMonsterOnly"
    | "needGrip"
    | "itemDamageType"
    | "itemAtk"
    | "damageBlunt"
    | "damagePierce"
    | "damageForce"
    | "damageFire"
    | "blockHead"
    | "blockCoreS"
    | "blockCoreM"
    | "blockCoreL"
    | "blockArmor"
    | "blockSpike"
    | "blockGrip"
    | "blockJoint"
    | "blockMass"
    | "blockHeadDesc"
    | "blockCoreDesc"
    | "blockArmorDesc"
    | "blockSpikeDesc"
    | "blockGripDesc"
    | "blockJointDesc"
    | "blockMassDesc"
    | "confirmDelete",
    string
  > & {
    partsCount: (n: number) => string;
  };
  options: Record<
    | "title"
    | "language"
    | "langEn"
    | "langRu"
    | "showBanter"
    | "matureBanter"
    | "matureBanterHint"
    | "screenEffects"
    | "soundEffects"
    | "sfxVolume"
    | "music"
    | "musicVolume"
    | "resetControls"
    | "close",
    string
  >;
  music: Record<
    | "nowPlaying"
    | "quieter"
    | "louder"
    | "mute"
    | "unmute"
    | "muteShort"
    | "unmuteShort"
    | "next"
    | "prev"
    | "off",
    string
  >;
  controls: Record<
    | "title"
    | "move"
    | "up"
    | "down"
    | "left"
    | "right"
    | "abilities"
    | "arrowsHint"
    | "moveP2"
    | "moveP2Hint"
    | "abilitiesP2"
    | "backKey"
    | "pressKey"
    | "reset"
    | "close",
    string
  >;
  customize: Record<
    | "title"
    | "name"
    | "presets"
    | "body"
    | "limbTips"
    | "limbTipsHint"
    | "statWins"
    | "statLosses"
    | "statMedals"
    | "customPreset"
    | "customTitle"
    | "customHint"
    | "customApply"
    | "customPreview"
    | "openAchievements"
    | "presetCustomName"
    | "mediaTitle"
    | "camera"
    | "cameraHint"
    | "microphone"
    | "microphoneHint"
    | "faceEffects"
    | "avatarFaces"
    | "avatarFacesHint"
    | "avatarRandom"
    | "avatarLastBattle"
    | "characterCameraOn"
    | "characterCameraOff"
    | "characterLastMedal",
    string
  >;
  achievements: {
    title: string;
    battles: string;
    locked: string;
    earnedCount: (count: number) => string;
    progress: (unlocked: number, total: number) => string;
  };
  battle: Record<
    | "victory"
    | "defeat"
    | "draw"
    | "drawHint"
    | "suddenDeath"
    | "controlsHint"
    | "player1"
    | "player2"
    | "abilitiesHint"
    | "abilityDash"
    | "abilityFlip"
    | "abilityFreeze"
    | "abilityGrabL"
    | "abilityGrabR"
    | "abilitySlotEmpty"
    | "abilityReset"
    | "victoryHint"
    | "backToMenu"
    | "webcamOff"
    | "webcamOn"
    | "debugHint"
    | "opponentName"
    | "recapDealt"
    | "recapReceived"
    | "recapKnockout"
    | "recapVs"
    | "defeatGhostHint"
    | "recapZoomHint"
    | "recapCloseZoom"
    | "recapMedals",
    string
  >;
  medals: Record<
    | "first_blood"
    | "combo_3"
    | "combo_5"
    | "heavy_hit"
    | "brutal_hit"
    | "knockout"
    | "clutch"
    | "victory"
    | "revenge"
    | "flawless"
    | "bouncer"
    | "workshop",
    string
  >;
  medalDesc: Record<
    | "first_blood"
    | "combo_3"
    | "combo_5"
    | "heavy_hit"
    | "brutal_hit"
    | "knockout"
    | "clutch"
    | "victory"
    | "revenge"
    | "flawless"
    | "bouncer"
    | "workshop",
    string
  >;
  hit: {
    damage: (amount: number) => string;
  };
}
