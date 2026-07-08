import debug from "debug";
import {
  colorsForSide,
  type FighterColors,
} from "./fighterColors";
import {
  computeDamage,
  FIGHTER_HIT_COOLDOWN_MS,
  MAX_HP,
  BOT_DAMAGE_MULTIPLIER,
} from "./combat";
import { type CombatFxConfig, resolveHitParties } from "./combatFx";
import { isDebugMode } from "./debugMode";
import {
  createPopup,
  decayPopupPulse,
  findMergePopup,
  type HitPopup,
  prunePopups,
  stackPopup,
} from "./hitPopups";
import {
  dispatchHitEffects,
  dispatchKnockoutEffects,
} from "./hitEffects/dispatch";
import { isKnockoutFromLethalHit } from "./knockoutDetect";
import { playHitSound, playKnockoutSound, stereoPanForX } from "@/audio";
import { type HitBurst, pruneBursts } from "./hitVfx";
import {
  pickBanter,
  pruneBanter,
  type BanterQuip,
} from "./banterQuips";
import { pickBanterLine, shouldSpawnBanter } from "@/i18n/banter";
import { isSaveBody } from "./isSaveBody";
import { isBattleSpawnGrace } from "./combatGrace";
import { suddenDeathMultiplier } from "./battleTuning";
import {
  canFightersTradeDamage,
  filterDamageFromDeadAggressors,
} from "./combatActive";
import {
  maybeRecordTeamDealt,
  maybeRecordTeamReceived,
  scheduleKnockoutCapture,
  type BattleMomentsStore,
} from "./battleMoments";
import type { BattleTracker } from "./achievements/battleTracker";
import {
  recordBattleHit,
  recordPlayerKnockoutWin,
} from "./achievements/battleTracker";
import { useStickmanCollision } from "./useStickmanCollision";
import { filterGrabDamage, isGrabAttachDamageGrace } from "./grab/rules";
import type { FighterGrabState, HandSide } from "./grab/types";
import { notifyGrabVictimHit } from "./grab/useGrabSystem";
import type { BattleEventMap } from "@/core/events";
import { getDamageType } from "@/items/damageTypes";
import { computeDisarmChance, rollDisarm } from "@/items/disarm";
import { items } from "@/items/registry";
import { tagItemOwner, findItemComposite } from "@/items/buildItem";
import type { Bounds } from "matter-js";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type DependencyList,
  type MutableRefObject,
  type RefObject,
} from "react";

export const log = debug("@:lib:useHealth");

export type FighterSide = "player" | "opponent";

export interface HealthFxOptions {
  formatDamage: (amount: number) => string;
  showBanter: boolean;
  matureBanter: boolean;
  screenEffects: boolean;
  hitEffectsStore?: { current: import("./hitEffects/store").HitEffectStore | null };
  arenaHeight?: number;
  language?: "en" | "ru";
  getKnockoutFocus?: (winner: FighterSide) => { x: number; y: number } | null;
  battleStartRef?: RefObject<number>;
  battleMomentsStore?: RefObject<BattleMomentsStore | null>;
  ourTeamName?: string;
  enemyTeamName?: string;
  opponentDefensePct?: number;
  getSpeakerHead?: (side: FighterSide) => { x: number; y: number } | null;
  banterObstacleBodies?: () => Matter.Body[];
  battleTrackerRef?: RefObject<BattleTracker | null>;
  playerGrabRef?: RefObject<FighterGrabState>;
  opponentGrabRef?: RefObject<FighterGrabState>;
  releasePlayerGrab?: (side: HandSide, forced?: boolean) => void;
  releaseOpponentGrab?: (side: HandSide, forced?: boolean) => void;
  /** Нужны для выбора grab-refs при disarm по holderCompositeId. */
  playerCompositeId?: number;
  opponentCompositeId?: number;
  itemCompositesRef?: RefObject<Matter.Composite[]>;
  onItemDisarm?: (itemComposite: Matter.Composite) => void;
}

export interface HealthState {
  playerHp: number;
  opponentHp: number;
  battleOver: boolean;
  winner: FighterSide | null;
  lastHit: FighterSide | null;
  popupsRef: MutableRefObject<HitPopup[]>;
  burstsRef: MutableRefObject<HitBurst[]>;
  banterRef: MutableRefObject<BanterQuip[]>;
  lastHitDebugRef: MutableRefObject<string | null>;
}

function victimKeyForComposite(
  compositeId: number,
  playerCompositeId: number | undefined,
): string {
  if (compositeId === playerCompositeId) return "player";
  return "opponent";
}

function addDamagePopup(
  popups: HitPopup[],
  damage: number,
  x: number,
  y: number,
  now: number,
  victimKey: string,
  colors: FighterColors,
  slot: number,
  bounds: Bounds,
  formatDamage: (amount: number) => string,
): void {
  if (damage <= 0.5) return;

  const existing = findMergePopup(popups, victimKey, now);
  if (existing) {
    stackPopup(existing, damage, formatDamage, now);
    return;
  }

  popups.push(
    createPopup(
      damage,
      formatDamage(damage),
      x,
      y,
      now,
      victimKey,
      colors,
      slot,
      bounds,
    ),
  );
}

export function useHealth(
  composites: Matter.Composite[],
  playerCompositeId: number | undefined,
  opponentCompositeId: number | undefined,
  playerColors: FighterColors,
  bounds: Bounds,
  fx: HealthFxOptions,
  opponentMaxHp: number,
  deps: DependencyList,
  options?: { skipCollisions?: boolean },
): {
  playerHp: number;
  opponentHp: number;
  battleOver: boolean;
  winner: FighterSide | null;
  lastHit: FighterSide | null;
  popupsRef: MutableRefObject<HitPopup[]>;
  burstsRef: MutableRefObject<HitBurst[]>;
  banterRef: MutableRefObject<BanterQuip[]>;
  lastHitDebugRef: MutableRefObject<string | null>;
  syncHpFromCore: (player: number, opponent: number, lastHitSide?: FighterSide | null) => void;
  reportCoreHit: (payload: BattleEventMap["hit"]) => void;
  reportCoreKnockout: (payload: BattleEventMap["knockout"], contactX: number, contactY: number) => void;
} {
  const [playerHp, setPlayerHp] = useState(MAX_HP);
  const [opponentHp, setOpponentHp] = useState(opponentMaxHp);
  const [lastHit, setLastHit] = useState<FighterSide | null>(null);
  const cooldown = useRef(new Map<string, number>());
  const popupsRef = useRef<HitPopup[]>([]);
  const burstsRef = useRef<HitBurst[]>([]);
  const banterRef = useRef<BanterQuip[]>([]);
  const lastHitDebugRef = useRef<string | null>(null);
  const popupSlotRef = useRef(0);
  const banterSlotRef = useRef(0);
  const lastBanterAtRef = useRef(0);
  const effectSlotRef = useRef(0);
  const playerHpRef = useRef(MAX_HP);
  const opponentHpRef = useRef(opponentMaxHp);
  const battleOverRef = useRef(false);
  const knockoutDispatchedRef = useRef(false);

  playerHpRef.current = playerHp;
  opponentHpRef.current = opponentHp;

  useEffect(() => {
    setPlayerHp(MAX_HP);
    setOpponentHp(opponentMaxHp);
    playerHpRef.current = MAX_HP;
    opponentHpRef.current = opponentMaxHp;
    knockoutDispatchedRef.current = false;
  }, [opponentMaxHp, playerCompositeId, opponentCompositeId]);

  const fxConfig: CombatFxConfig = {
    playerCompositeId,
    opponentCompositeId,
    playerColors,
    opponentColors: colorsForSide("opponent"),
  };

  const battleOver = playerHp <= 0 || opponentHp <= 0;
  // Двойной нокаут (оба на нуле) — ничья: battleOver=true, winner=null.
  const winner: FighterSide | null =
    playerHp <= 0 && opponentHp <= 0
      ? null
      : playerHp <= 0
        ? "opponent"
        : opponentHp <= 0
          ? "player"
          : null;
  battleOverRef.current = battleOver;

  const sideForComposite = useCallback(
    (compositeId: number): FighterSide | null => {
      if (compositeId === playerCompositeId) return "player";
      if (compositeId === opponentCompositeId) return "opponent";
      return null;
    },
    [playerCompositeId, opponentCompositeId],
  );

  const applyDamage = useCallback(
    (compositeId: number, amount: number, damageTypeId = "blunt") => {
      if (amount <= 0) return;
      let dmg = amount;
      const battleStart = fx.battleStartRef?.current ?? 0;
      if (battleStart > 0) {
        dmg *= suddenDeathMultiplier(performance.now() - battleStart);
      }
      const dtype = getDamageType(damageTypeId);
      if (compositeId === playerCompositeId) {
        dmg *= BOT_DAMAGE_MULTIPLIER;
      }
      if (compositeId === playerCompositeId) {
        const next = Math.max(0, playerHpRef.current - dmg);
        playerHpRef.current = next;
        setPlayerHp(next);
        setLastHit("player");
      } else if (compositeId === opponentCompositeId) {
        const defense = fx.opponentDefensePct ?? 0;
        const effectiveDef = defense * (1 - (dtype.pierceIgnoreDefPct ?? 0));
        dmg *= 1 - effectiveDef / 100;
        const next = Math.max(0, opponentHpRef.current - dmg);
        opponentHpRef.current = next;
        setOpponentHp(next);
        setLastHit("opponent");
      }
    },
    [playerCompositeId, opponentCompositeId, fx.opponentDefensePct],
  );

  const tryKnockoutFx = useCallback(
    (
      compositeId: number,
      amount: number,
      winner: FighterSide,
      focusX: number,
      focusY: number,
      now: number,
    ) => {
      if (knockoutDispatchedRef.current) return;

      const hpAfter =
        compositeId === playerCompositeId
          ? playerHpRef.current
          : compositeId === opponentCompositeId
            ? opponentHpRef.current
            : null;
      if (hpAfter === null) return;

      const effective =
        compositeId === playerCompositeId
          ? amount * BOT_DAMAGE_MULTIPLIER
          : amount;
      if (!isKnockoutFromLethalHit(hpAfter, effective)) return;

      knockoutDispatchedRef.current = true;

      if (winner === "player") {
        const tracker = fx.battleTrackerRef?.current;
        if (tracker) recordPlayerKnockoutWin(tracker);
      }

      const moments = fx.battleMomentsStore?.current;
      if (moments) {
        const loserName =
          compositeId === playerCompositeId
            ? (fx.ourTeamName ?? "player")
            : (fx.enemyTeamName ?? "opponent");
        const winnerName =
          winner === "player"
            ? (fx.ourTeamName ?? "player")
            : (fx.enemyTeamName ?? "opponent");
        scheduleKnockoutCapture(moments, now, winnerName, loserName);
      }

      playKnockoutSound();

      const store = fx.hitEffectsStore?.current;
      if (!store || !fx.screenEffects) return;

      const focus = fx.getKnockoutFocus?.(winner) ?? { x: focusX, y: focusY };
      const winnerColors =
        winner === "player" ? playerColors : fxConfig.opponentColors;
      dispatchKnockoutEffects(
        store,
        winner,
        focus.x,
        focus.y,
        fx.language ?? "ru",
        effectSlotRef.current++,
        now,
        winnerColors,
      );
    },
    [fx, playerCompositeId, opponentCompositeId, playerColors, fxConfig.opponentColors],
  );

  const emitHitFx = useCallback(
    (
      victimCompositeId: number,
      victimDamage: number,
      contactX: number,
      contactY: number,
      _damageTypeId = "blunt",
    ) => {
      if (victimDamage <= 0) return;
      const now = performance.now();
      popupsRef.current = prunePopups(popupsRef.current, now);
      burstsRef.current = pruneBursts(burstsRef.current, now);
      banterRef.current = pruneBanter(banterRef.current, now);
      decayPopupPulse(popupsRef.current);

      const side = victimKeyForComposite(
        victimCompositeId,
        playerCompositeId,
      ) as FighterSide;
      const aggressorSide = side === "player" ? "opponent" : "player";
      const colors = side === "player" ? playerColors : colorsForSide(side);
      const aggressorColors =
        aggressorSide === "player" ? playerColors : fxConfig.opponentColors;

      const moments = fx.battleMomentsStore?.current;
      if (moments) {
        if (victimCompositeId === opponentCompositeId) {
          maybeRecordTeamDealt(moments, victimDamage, fx.formatDamage, now);
        } else if (victimCompositeId === playerCompositeId) {
          maybeRecordTeamReceived(moments, victimDamage, fx.formatDamage, now);
        }
      }

      addDamagePopup(
        popupsRef.current,
        victimDamage,
        contactX,
        contactY,
        now,
        side,
        colors,
        popupSlotRef.current++,
        bounds,
        fx.formatDamage,
      );

      if (victimDamage > 0.5) {
        playHitSound(
          victimDamage,
          stereoPanForX(contactX, bounds.min.x, bounds.max.x),
        );
      }

      const tracker = fx.battleTrackerRef?.current;
      if (tracker) {
        recordBattleHit(tracker, aggressorSide, victimDamage, now);
      }

      if (
        fx.showBanter &&
        shouldSpawnBanter(victimDamage, now, lastBanterAtRef.current)
      ) {
        lastBanterAtRef.current = now;
        const line = pickBanterLine(fx.language ?? "ru", fx.matureBanter, side);
        const head = fx.getSpeakerHead?.(side);
        const anchorX = head?.x ?? contactX;
        const anchorY = head?.y ?? contactY;
        banterRef.current.push(
          pickBanter(
            line,
            side,
            anchorX,
            anchorY,
            banterSlotRef.current++,
            now,
            colors,
            {
              bounds,
              bodies: fx.banterObstacleBodies?.() ?? [],
              existing: banterRef.current,
            },
          ),
        );
      }

      if (fx.screenEffects) {
        burstsRef.current.push({
          x: contactX,
          y: contactY,
          born: now,
          color: aggressorColors.main,
          secondary: aggressorColors.secondary,
          power: Math.min(1, victimDamage / 80),
        });

        const store = fx.hitEffectsStore?.current;
        if (store) {
          dispatchHitEffects(store, {
            damage: victimDamage,
            contactX,
            contactY,
            aggressorSide,
            aggressorColor: aggressorColors.main,
            aggressorColors,
            arenaHeight: fx.arenaHeight ?? bounds.max.y,
            language: fx.language ?? "ru",
            slot: effectSlotRef.current++,
            now,
          });
        }
      }

      tryKnockoutFx(
        victimCompositeId,
        victimDamage,
        aggressorSide,
        contactX,
        contactY,
        now,
      );
    },
    [
      bounds,
      fx,
      fxConfig.opponentColors,
      opponentCompositeId,
      playerColors,
      playerCompositeId,
      tryKnockoutFx,
    ],
  );

  const syncHpFromCore = useCallback(
    (nextPlayer: number, nextOpponent: number, lastHitSide?: FighterSide | null) => {
      playerHpRef.current = nextPlayer;
      opponentHpRef.current = nextOpponent;
      setPlayerHp((prev) => (prev === nextPlayer ? prev : nextPlayer));
      setOpponentHp((prev) => (prev === nextOpponent ? prev : nextOpponent));
      if (lastHitSide) setLastHit(lastHitSide);
    },
    [],
  );

  const reportCoreHit = useCallback(
    (payload: BattleEventMap["hit"]) => {
      const victimSide = sideForComposite(payload.victimCompositeId);
      if (victimSide) setLastHit(victimSide);
      emitHitFx(
        payload.victimCompositeId,
        payload.damage,
        payload.x,
        payload.y,
        payload.damageTypeId,
      );
    },
    [emitHitFx, sideForComposite],
  );

  const reportCoreKnockout = useCallback(
    (
      payload: BattleEventMap["knockout"],
      contactX: number,
      contactY: number,
    ) => {
      const winner = sideForComposite(payload.winnerCompositeId);
      if (!winner) return;
      tryKnockoutFx(
        payload.victimCompositeId,
        999,
        winner,
        contactX,
        contactY,
        performance.now(),
      );
    },
    [sideForComposite, tryKnockoutFx],
  );

  useStickmanCollision(
    options?.skipCollisions ? [] : composites,
    {
      onCollisionStart: (_event, { pair, compositeA, compositeB }) => {
        const tradeOpts = {
          battleOver: battleOverRef.current,
          playerHp: playerHpRef.current,
          opponentHp: opponentHpRef.current,
          playerCompositeId,
          opponentCompositeId,
        };
        if (!canFightersTradeDamage(compositeA, compositeB, composites, tradeOpts)) {
          return;
        }

        const now = performance.now();
        if (isBattleSpawnGrace(fx.battleStartRef?.current ?? 0, now)) return;

        const { bodyA, bodyB, collision } = pair;
        if ([bodyA, bodyB].every(isSaveBody)) return;

        const fighterKey = `${Math.min(compositeA, compositeB)}-${Math.max(compositeA, compositeB)}`;
        if ((cooldown.current.get(fighterKey) ?? 0) > now) return;

        const playerGrab = fx.playerGrabRef?.current ?? null;
        if (
          isGrabAttachDamageGrace(playerGrab, now) &&
          (compositeA === playerCompositeId || compositeB === playerCompositeId)
        ) {
          return;
        }

        const rawHit = computeDamage(bodyA, bodyB);
        const filteredGrab = filterGrabDamage(compositeA, compositeB, rawHit, {
          playerCompositeId,
          opponentCompositeId,
          playerGrab,
          opponentGrab: fx.opponentGrabRef?.current ?? null,
        });
        const result = filterDamageFromDeadAggressors(
          compositeA,
          compositeB,
          filteredGrab.damageA,
          filteredGrab.damageB,
          tradeOpts,
        );
        if (result.damageA <= 0 && result.damageB <= 0) return;

        if (
          fx.playerGrabRef &&
          fx.releasePlayerGrab &&
          opponentCompositeId &&
          playerCompositeId
        ) {
          const playerHurt =
            (compositeA === playerCompositeId && result.damageA > 0) ||
            (compositeB === playerCompositeId && result.damageB > 0);
          if (playerHurt) {
            notifyGrabVictimHit(
              fx.playerGrabRef,
              opponentCompositeId,
              fx.releasePlayerGrab,
            );
          }
        }
        if (
          fx.opponentGrabRef &&
          fx.releaseOpponentGrab &&
          playerCompositeId &&
          opponentCompositeId
        ) {
          const opponentHurt =
            (compositeA === opponentCompositeId && result.damageA > 0) ||
            (compositeB === opponentCompositeId && result.damageB > 0);
          if (opponentHurt) {
            notifyGrabVictimHit(
              fx.opponentGrabRef,
              playerCompositeId,
              fx.releaseOpponentGrab,
            );
          }
        }

        cooldown.current.set(fighterKey, now + FIGHTER_HIT_COOLDOWN_MS);

        applyDamage(compositeA, result.damageA, filteredGrab.damageTypeId);
        applyDamage(compositeB, result.damageB, filteredGrab.damageTypeId);

        if (result.damageA > 0) {
          tryDisarmHeldItem(fx, compositeA);
        }
        if (result.damageB > 0) {
          tryDisarmHeldItem(fx, compositeB);
        }

        if (isDebugMode()) {
          lastHitDebugRef.current =
            `${bodyA.label}↔${bodyB.label} hit ${rawHit.impactSpeed.toFixed(2)} ` +
            `→ ${result.damageA.toFixed(0)}/${result.damageB.toFixed(0)} ♥ (${filteredGrab.victim})`;
        }

        const contact = collision.supports.at(0);
        if (!contact) return;

        popupsRef.current = prunePopups(popupsRef.current, now);
        burstsRef.current = pruneBursts(burstsRef.current, now);
        banterRef.current = pruneBanter(banterRef.current, now);
        decayPopupPulse(popupsRef.current);

        const parties = resolveHitParties(
          { ...rawHit, damageA: result.damageA, damageB: result.damageB },
          compositeA,
          compositeB,
          fxConfig,
        );
        const moments = fx.battleMomentsStore?.current;
        if (moments) {
          for (const party of parties) {
            if (party.victimCompositeId === opponentCompositeId) {
              maybeRecordTeamDealt(
                moments,
                party.victimDamage,
                fx.formatDamage,
                now,
              );
            } else if (party.victimCompositeId === playerCompositeId) {
              maybeRecordTeamReceived(
                moments,
                party.victimDamage,
                fx.formatDamage,
                now,
              );
            }
          }
        }

        for (const party of parties) {
          const side = victimKeyForComposite(
            party.victimCompositeId,
            playerCompositeId,
          ) as FighterSide;
          const aggressorSide = side === "player" ? "opponent" : "player";
          const colors =
            side === "player" ? playerColors : colorsForSide(side);

          addDamagePopup(
            popupsRef.current,
            party.victimDamage,
            contact.x,
            contact.y,
            now,
            side,
            colors,
            popupSlotRef.current++,
            bounds,
            fx.formatDamage,
          );

          if (party.victimDamage > 0.5) {
            playHitSound(
              party.victimDamage,
              stereoPanForX(contact.x, bounds.min.x, bounds.max.x),
            );
          }

          const tracker = fx.battleTrackerRef?.current;
          if (tracker) {
            recordBattleHit(
              tracker,
              aggressorSide,
              party.victimDamage,
              now,
            );
          }

          if (
            fx.showBanter &&
            shouldSpawnBanter(party.victimDamage, now, lastBanterAtRef.current)
          ) {
            lastBanterAtRef.current = now;
            const line = pickBanterLine(
              fx.language ?? "ru",
              fx.matureBanter,
              side,
            );
            const head = fx.getSpeakerHead?.(side);
            const anchorX = head?.x ?? contact.x;
            const anchorY = head?.y ?? contact.y;
            banterRef.current.push(
              pickBanter(
                line,
                side,
                anchorX,
                anchorY,
                banterSlotRef.current++,
                now,
                colors,
                {
                  bounds,
                  bodies: fx.banterObstacleBodies?.() ?? [],
                  existing: banterRef.current,
                },
              ),
            );
          }

          if (fx.screenEffects) {
            burstsRef.current.push({
              x: contact.x,
              y: contact.y,
              born: now,
              color: party.aggressorColors.main,
              secondary: party.aggressorColors.secondary,
              power: Math.min(1, party.victimDamage / 80),
            });

            const store = fx.hitEffectsStore?.current;
            if (store) {
              dispatchHitEffects(store, {
                damage: party.victimDamage,
                contactX: contact.x,
                contactY: contact.y,
                aggressorSide,
                aggressorColor: party.aggressorColors.main,
                aggressorColors: party.aggressorColors,
                arenaHeight: fx.arenaHeight ?? bounds.max.y,
                language: fx.language ?? "ru",
                slot: effectSlotRef.current++,
                now,
              });
            }
          }

          tryKnockoutFx(
            party.victimCompositeId,
            party.victimDamage,
            aggressorSide,
            contact.x,
            contact.y,
            now,
          );
        }

        if (popupsRef.current.length > 16) {
          popupsRef.current.splice(0, popupsRef.current.length - 16);
        }
        if (burstsRef.current.length > 20) {
          burstsRef.current.splice(0, burstsRef.current.length - 20);
        }
        if (banterRef.current.length > 8) {
          banterRef.current.splice(0, banterRef.current.length - 8);
        }
      },
    },
    deps,
  );

  return {
    playerHp,
    opponentHp,
    battleOver,
    winner,
    lastHit,
    popupsRef,
    burstsRef,
    banterRef,
    lastHitDebugRef,
    syncHpFromCore,
    reportCoreHit,
    reportCoreKnockout,
  };
}

function tryDisarmHeldItem(
  fx: HealthFxOptions,
  holderCompositeId: number,
): void {
  const isPlayerHolder = holderCompositeId === fx.playerCompositeId;
  const isOpponentHolder = holderCompositeId === fx.opponentCompositeId;
  const grab = isPlayerHolder
    ? fx.playerGrabRef?.current
    : isOpponentHolder
      ? fx.opponentGrabRef?.current
      : null;
  const release = isPlayerHolder
    ? fx.releasePlayerGrab
    : isOpponentHolder
      ? fx.releaseOpponentGrab
      : undefined;
  if (!grab || !release) return;

  for (const side of ["left", "right"] as const) {
    const hand = side === "left" ? grab.left : grab.right;
    if (hand.phase !== "attached") continue;
    if (hand.target?.kind !== "grip" && hand.target?.kind !== "item") continue;

    const itemComposites = fx.itemCompositesRef?.current ?? [];
    const itemBody = itemComposites
      .flatMap((c) => c.bodies)
      .find((b) => b.id === hand.target!.bodyId);
    if (!itemBody) continue;

    const itemId = (itemBody.plugin as { itemId?: string }).itemId;
    if (!itemId) continue;

    const def = items.get(itemId);
    const chance = computeDisarmChance(def, 0);
    if (!rollDisarm(chance)) continue;

    release(side, true);
    const composite = findItemComposite(itemBody, itemComposites);
    if (composite) {
      tagItemOwner(composite, null);
      fx.onItemDisarm?.(composite);
    }
  }
}
