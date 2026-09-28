import type { AbilityId, PassiveItemId } from "@/loadout/types";
export type Language = "en" | "ru";

export interface LocaleStrings {
  game: {
    title: string;
    titleAccent: string;
    subtitle: string;
    tapToStart: string;
  };
  menu: Record<
    | "play"
    | "customize"
    | "hideCustomize"
    | "options"
    | "controls"
    | "back"
    | "close"
    | "webcamOff"
    | "breadcrumbHome"
    | "playPickHint"
    | "yourFighter"
    | "workshop"
    | "achievements"
    | "account"
    | "credits"
    | "lab"
    | "signIn",
    string
  >;
  lab: {
    title: string;
    hint: string;
    tabWeapons: string;
    tabAbilities: string;
    tabItems: string;
    search: string;
    pickHint: string;
    weaponBlurb: string;
    statDamage: string;
    statAtk: string;
    statDef: string;
    statDrop: string;
    statParts: string;
    statKind: string;
    statCat: string;
    statRarity: string;
    statCd: string;
    statDur: string;
    statMove: string;
    statCrit: string;
    statKb: string;
    unlockToast: string;
    startFight: string;
    loadoutSummary: string;
    castHint: string;
    modeCatalog: string;
    modeArena: string;
    modeSandbox: string;
    sandboxTitle: string;
    sandboxHint: string;
    sandboxDragHint: string;
    sandboxStart: string;
    arenaTitle: string;
    arenaHint: string;
    arenaPlayerHp: string;
    arenaOpponentHp: string;
    arenaBotCount: string;
    arenaAbilities: string;
    arenaItems: string;
    arenaWeapons: string;
    arenaCastHint: string;
    arenaStart: string;
  };
  credits: {
    title: string;
    intro: string;
    sectionCode: string;
    sectionFonts: string;
    sectionAudio: string;
    sectionTech: string;
    codeOrigin: string;
    fontsNote: string;
    audioNote: string;
    techNote: string;
    rights: string;
  };
  account: Record<
    | "title"
    | "hint"
    | "gateHint"
    | "google"
    | "discord"
    | "orEmail"
    | "emailPlaceholder"
    | "emailSend"
    | "emailCodeSent"
    | "emailCodePlaceholder"
    | "emailVerify"
    | "emailInvalid"
    | "signOut"
    | "sync"
    | "syncFailed"
    | "loading"
    | "notConfigured"
    | "signedIn"
    | "guest"
    | "devBypass",
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
  common: Record<
    | "back"
    | "landscapeTitle"
    | "landscapeBody"
    | "landscapeAnyway"
    | "fullscreenEnter"
    | "fullscreenExit"
    | "fullscreenGateTitle"
    | "fullscreenGateBody",
    string
  >;
  campaign: Record<
    | "title"
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
    | "name"
    | "defaultName"
    | "toolLink"
    | "toolMove"
    | "toolMoveHint"
    | "toolLinkHint"
    | "sizeHead"
    | "save"
    | "clear"
    | "clearConfirm"
    | "kindSwitchConfirm"
    | "fight"
    | "saved"
    | "savedStarting"
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
    | "partRoleHurtbox"
    | "partRoleArmor"
    | "partSelected"
    | "selectedPart"
    | "selectedLink"
    | "changeLinkType"
    | "deleteLink"
    | "headAlwaysHurtbox"
    | "deletePart"
    | "linkType"
    | "linkRigid"
    | "linkSpring"
    | "linkRope"
    | "linkRigidDesc"
    | "linkSpringDesc"
    | "linkRopeDesc"
    | "readyToFight"
    | "notReadyToFight"
    | "checkHead"
    | "checkHurtbox"
    | "checkLinks"
    | "checkConnected"
    | "checkStress"
    | "stressTest"
    | "stressShort"
    | "stressOk"
    | "stressBlocked"
    | "shareMonster"
    | "shareShort"
    | "shareCopied"
    | "sharePrompt"
    | "importMonster"
    | "importShort"
    | "importPrompt"
    | "importOk"
    | "importFail"
    | "physicsStop"
    | "physicsStartShort"
    | "physicsStopShort"
    | "physicsOn"
    | "physicsOff"
    | "physicsBanner"
    | "onboardTitle"
    | "onboardStep1"
    | "onboardStep2"
    | "onboardStep3"
    | "onboardLoadTemplate"
    | "onboardStartEmpty"
    | "onboardSkip"
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
    orphanParts: (n: number) => string;
    stressFail: (n: number) => string;
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
    | "hint"
    | "player1"
    | "player2"
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
    | "close"
    | "descUp"
    | "descDown"
    | "descLeft"
    | "descRight"
    | "descDash"
    | "descFlip"
    | "descFreeze"
    | "descReset"
    | "descGrabL"
    | "descGrabR"
    | "descDropWeapon"
    | "descAbilitySlot",
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
    | "characterLastMedal"
    | "characterLevel"
    | "characterRecord",
    string
  >;
  achievements: {
    title: string;
    battles: string;
    locked: string;
    level: string;
    xpToNext: (current: number, need: number) => string;
    earnedCount: (count: number) => string;
    progress: (unlocked: number, total: number) => string;
  };
  ranks: Record<
    "rookie" | "brawler" | "slugger" | "contender" | "champion" | "legend",
    string
  >;
  battle: Record<
    | "victory"
    | "defeat"
    | "draw"
    | "drawHint"
    | "suddenDeath"
    | "controlsHint"
    | "onboardTitle"
    | "onboardStepMove"
    | "onboardStepDash"
    | "onboardStepHit"
    | "onboardGo"
    | "player1"
    | "player2"
    | "abilitiesHint"
    | "abilityDash"
    | "abilityFlip"
    | "abilityFreeze"
    | "abilityGrabL"
    | "abilityGrabR"
    | "abilityDropWeapon"
    | "abilityLoadoutSlot"
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
    | "recapMedals"
    | "replayTitle"
    | "replayAuto"
    | "replayPlay"
    | "replayPause"
    | "replayScrub"
    | "replayToRecap"
    | "replayMarkIn"
    | "replayMarkOut"
    | "replayShareClip"
    | "replayClearClip"
    | "replayClipCopied"
    | "replayClipFailed"
    | "replayClipNeedMarks"
    | "touchStick"
    | "touchDash"
    | "touchFlip"
    | "touchBrace"
    | "touchReset",
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
  loadout: {
    draftTitle: string;
    confirm: string;
    release: string;
    baseLabel: string;
    poolHint: string;
    poolEmpty: string;
    noCards: string;
    playerLabel: string;
    kindItem: string;
    ability: Record<AbilityId, string>;
    abilityDesc: Record<AbilityId, string>;
    item: Record<PassiveItemId, string>;
    itemDesc: Record<PassiveItemId, string>;
  };
  lobby: {
    title: string;
    hint: string;
    partyHint: string;
    /** Подсказка для стандартного режима «против бота». */
    vsHint: string;
    opponentHp: string;
    opponentHpStandard: string;
    modeTitle: string;
    empty: string;
    you: string;
    host: string;
    localTag: string;
    onlineTag: string;
    addLocal: string;
    invite: string;
    remove: string;
    start: string;
    slotLabel: string;
    botDifficulty: string;
    localPhoneBlocked: string;
    localPcHint: string;
    localFull: string;
    inviteUnavailable: string;
    invitePanel: string;
    inviteHint: string;
    copyInvite: string;
    inviteCopied: string;
    onlineCount: string;
    readyOn: string;
    readyOff: string;
    /** Табличка на режиме «в разработке». */
    wipBadge: string;
    roguelikeWip: string;
    mode: Record<"vs" | "campaign" | "roguelike", string>;
    difficulty: Record<"easy" | "normal" | "hard" | "boss", string>;
  };
  roguelike: {
    title: string;
    floor: string;
    lootTitle: string;
    lootHint: string;
    lootEmpty: string;
    portalsTitle: string;
    pathHint: string;
    abilitiesTitle: string;
    itemsTitle: string;
    lootFreedomHint: string;
    takeSelf: string;
    giveTo: string;
    steal: string;
    drop: string;
    stealHint: string;
    noGear: string;
    youTag: string;
    rivalTag: string;
    rarity: Record<
      "common" | "uncommon" | "rare" | "epic" | "legendary",
      string
    >;
    dirLeft: string;
    dirForward: string;
    dirRight: string;
    enterPortal: string;
    goFight: string;
    cleared: string;
    entering: string;
    bots: string;
    party: string;
    emptySlot: string;
    victory: string;
    defeat: string;
    victoryHint: string;
    defeatHint: string;
    backToLobby: string;
    noRun: string;
  };
}
