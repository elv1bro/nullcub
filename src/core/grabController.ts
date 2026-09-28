import Matter, {
  type Composite,
  type Engine,
  type IEventCollision,
} from "matter-js";
import { itemLeafBodies, tagItemOwner } from "@/items/buildItem";
import {
  buildCompositeBodyMap,
  createGrabPin,
  createWeaponGuidePin,
  dampGrabBodies,
  forearmProximalWorld,
  grabAttachClosingSpeed,
  MAX_GRAB_ATTACH_CLOSING,
  removeGrabConstraints,
  resolveGrabTarget,
} from "@/lib/grab/attach";
import { getHandBody, isHandBody } from "@/lib/grab/hands";
import {
  createGrabHitTracker,
  isGrabAttachDamageGrace,
  recordGrabVictimHit,
  shouldForceReleaseGrabber,
} from "@/lib/grab/rules";
import {
  handGrabAttached,
  handGrabForcedRelease,
  handGrabKeyDown,
  handGrabKeyUp,
  isHandSeeking,
} from "@/lib/grab/stateMachine";
import {
  createFighterGrabState,
  type FighterGrabState,
  type HandSide,
} from "@/lib/grab/types";
import type { CoreFighterRuntime } from "./types";
import {
  AUTO_PICKUP_COOLDOWN_MS,
  AUTO_PICKUP_RANGE,
  GRAB_ENABLED,
  WEAPON_HOLD_ENABLED,
} from "@/lib/battleTuning";
import {
  findNearestUnownedWeapon,
  guideWorldPoint,
  handHoldsWeapon,
  pickFreeHand,
  snapWeaponGripToHand,
} from "@/items/weaponHold";

export class GrabController {
  readonly states = new Map<string, FighterGrabState>();
  private prevGrabL = new Map<string, boolean>();
  private prevGrabR = new Map<string, boolean>();
  private prevDrop = new Map<string, boolean>();
  private autoPickupUntil = new Map<string, number>();
  private engine: Engine | null = null;
  private victimHitTrackers = new Map<
    string,
    ReturnType<typeof createGrabHitTracker>
  >();
  private itemCompositesRef: Composite[] = [];

  setEngine(engine: Engine): void {
    this.engine = engine;
  }

  setItemComposites(items: Composite[]): void {
    this.itemCompositesRef = items;
  }

  ensure(fighter: CoreFighterRuntime): FighterGrabState {
    let st = this.states.get(fighter.id);
    if (!st) {
      st = createFighterGrabState(fighter.id);
      this.states.set(fighter.id, st);
      this.prevGrabL.set(fighter.id, false);
      this.prevGrabR.set(fighter.id, false);
      this.prevDrop.set(fighter.id, false);
    }
    return st;
  }

  syncInput(fighter: CoreFighterRuntime, now: number): void {
    const st = this.ensure(fighter);
    const grabL = GRAB_ENABLED && fighter.input.grabL;
    const grabR = GRAB_ENABLED && fighter.input.grabR;
    const wasL = this.prevGrabL.get(fighter.id) ?? false;
    const wasR = this.prevGrabR.get(fighter.id) ?? false;

    if (grabL && !wasL) {
      this.states.set(fighter.id, {
        ...st,
        left: handGrabKeyDown(st.left, now),
      });
    } else if (!grabL && wasL) {
      this.releaseSide(fighter.id, "left", now, false);
    }

    const st2 = this.states.get(fighter.id)!;
    if (grabR && !wasR) {
      this.states.set(fighter.id, {
        ...st2,
        right: handGrabKeyDown(st2.right, now),
      });
    } else if (!grabR && wasR) {
      this.releaseSide(fighter.id, "right", now, false);
    }

    this.prevGrabL.set(fighter.id, grabL);
    this.prevGrabR.set(fighter.id, grabR);

    const drop = WEAPON_HOLD_ENABLED && Boolean(fighter.input.dropWeapon);
    const wasDrop = this.prevDrop.get(fighter.id) ?? false;
    if (drop && !wasDrop) {
      this.dropHeldWeapons(fighter.id, now);
    }
    this.prevDrop.set(fighter.id, drop);
  }

  releaseSide(
    fighterId: string,
    side: HandSide,
    now: number,
    forced = false,
  ): void {
    const st = this.states.get(fighterId);
    if (!st) return;
    const handState = side === "left" ? st.left : st.right;
    this.clearOwnerIfWeapon(handState);
    if (this.engine && handState.constraints.length) {
      removeGrabConstraints(this.engine, handState.constraints);
    }
    const released = forced
      ? handGrabForcedRelease(handState, now)
      : handGrabKeyUp(handState);
    if (side === "left") {
      this.states.set(fighterId, { ...st, left: released });
    } else {
      this.states.set(fighterId, { ...st, right: released });
    }
  }

  /** Сброс только оружия (не fighter-grab). */
  dropHeldWeapons(fighterId: string, now: number): void {
    const st = this.states.get(fighterId);
    if (!st) return;
    let dropped = false;
    if (handHoldsWeapon(st, "left")) {
      this.releaseSide(fighterId, "left", now, false);
      dropped = true;
    }
    const st2 = this.states.get(fighterId);
    if (st2 && handHoldsWeapon(st2, "right")) {
      this.releaseSide(fighterId, "right", now, false);
      dropped = true;
    }
    // Иначе в том же тике tryAutoPickup сразу подберёт снова.
    if (dropped) {
      this.autoPickupUntil.set(fighterId, now + AUTO_PICKUP_COOLDOWN_MS);
    }
  }

  /**
   * Автоподбор ближайшего оружия свободной рукой.
   * Не требует GRAB_ENABLED (отдельный weapon-hold).
   */
  tryAutoPickup(
    fighter: CoreFighterRuntime,
    itemComposites: Composite[],
    now: number,
    range = AUTO_PICKUP_RANGE,
  ): boolean {
    if (!WEAPON_HOLD_ENABLED || !this.engine) return false;
    if (fighter.hp <= 0) return false;
    const until = this.autoPickupUntil.get(fighter.id) ?? 0;
    if (now < until) return false;

    const st = this.ensure(fighter);
    const side = pickFreeHand(st);
    if (!side) return false;

    const handBody = getHandBody(fighter.composite, side);
    if (!handBody) return false;

    const nearest = findNearestUnownedWeapon(
      handBody.position,
      itemComposites,
      range,
    );
    if (!nearest) return false;

    const target = {
      bodyId: nearest.pinBody.id,
      compositeId: nearest.composite.id,
      kind: "grip" as const,
    };
    // Сначала snap рукояти в кисть — иначе constraint тянет через тело.
    snapWeaponGripToHand(nearest.composite, handBody);
    const gripWorld = {
      x: handBody.position.x,
      y: handBody.position.y,
    };
    // Жёстче обычного grab — оружие должно ехать с рукой.
    const constraints = createGrabPin(
      this.engine,
      handBody,
      nearest.pinBody,
      "grip",
      gripWorld,
      { stiffness: 0.85 },
    );
    // Мягкая направляющая вдоль руки (не болтается маятником).
    constraints.push(
      createWeaponGuidePin(
        this.engine,
        handBody,
        nearest.pinBody,
        guideWorldPoint(nearest.composite),
        forearmProximalWorld(handBody, fighter.composite),
      ),
    );
    dampGrabBodies(handBody, nearest.pinBody);
    tagItemOwner(nearest.composite, fighter.id);

    const handState = side === "left" ? st.left : st.right;
    // Автоподбор: idle → seeking → attached (handGrabAttached требует seeking).
    const seeking = handGrabKeyDown(handState, now);
    const attached = {
      ...handGrabAttached(seeking, target, now),
      constraints,
    };
    if (side === "left") {
      this.states.set(fighter.id, { ...st, left: attached });
    } else {
      this.states.set(fighter.id, { ...st, right: attached });
    }
    this.autoPickupUntil.set(fighter.id, now + AUTO_PICKUP_COOLDOWN_MS);
    return true;
  }

  private clearOwnerIfWeapon(handState: {
    target: { kind: string; bodyId: number } | null;
  }): void {
    if (!handState.target) return;
    if (handState.target.kind !== "grip" && handState.target.kind !== "item") {
      return;
    }
    const item = this.itemCompositesRef.find(
      (c) =>
        c.bodies.some((b) => b.id === handState.target!.bodyId) ||
        itemLeafBodies(c).some((b) => b.id === handState.target!.bodyId),
    );
    if (item) tagItemOwner(item, null);
  }

  /** Пропуск урона сразу после pin — constraint даёт ложный мега-удар. */
  isAttachDamageGrace(now: number): boolean {
    for (const st of this.states.values()) {
      if (isGrabAttachDamageGrace(st, now)) return true;
    }
    return false;
  }

  /**
   * Жертва бьёт держателя: после N ударов за окно — forced release рук,
   * держащих эту жертву.
   */
  notifyVictimHit(
    holderFighterId: string,
    victimCompositeId: number,
    now: number,
  ): void {
    const grab = this.states.get(holderFighterId);
    if (!grab) return;
    const key = `${holderFighterId}:${victimCompositeId}`;
    let tracker = this.victimHitTrackers.get(key);
    if (!tracker) {
      tracker = createGrabHitTracker();
      this.victimHitTrackers.set(key, tracker);
    }
    if (!recordGrabVictimHit(tracker, now)) return;
    const sides = shouldForceReleaseGrabber(grab, victimCompositeId);
    for (const side of sides) this.releaseSide(holderFighterId, side, now, true);
    this.victimHitTrackers.delete(key);
  }

  handleCollision(
    event: IEventCollision<Engine>,
    fighters: CoreFighterRuntime[],
    allComposites: Composite[],
    itemComposites: Composite[],
    now: number,
  ): void {
    if (!GRAB_ENABLED && !WEAPON_HOLD_ENABLED) return;
    const engine = event.source;
    this.engine = engine;
    this.itemCompositesRef = itemComposites;
    const compositeMap = buildCompositeBodyMap(allComposites);

    for (const pair of event.pairs) {
      const { bodyA, bodyB, collision } = pair;
      const contact = collision.supports[0];
      for (const [handBody, otherBody] of [
        [bodyA, bodyB] as const,
        [bodyB, bodyA] as const,
      ]) {
        if (!isHandBody(handBody)) continue;
        const fighterId = handBody.plugin?.fighterId as string | undefined;
        if (!fighterId) continue;
        const fighter = fighters.find((f) => f.id === fighterId);
        if (!fighter) continue;

        const st = this.ensure(fighter);
        const side: HandSide =
          handBody.plugin?.part === "handR" ? "right" : "left";
        const handState = side === "left" ? st.left : st.right;
        if (!isHandSeeking(handState, now)) continue;

        const target = resolveGrabTarget(handBody, otherBody, compositeMap);
        if (!target) continue;

        const isWeapon = target.kind === "grip" || target.kind === "item";
        if (isWeapon && !WEAPON_HOLD_ENABLED) continue;
        if (!isWeapon && !GRAB_ENABLED) continue;

        const closing = Matter.Vector.sub(otherBody.position, handBody.position);
        if (Matter.Vector.magnitude(closing) > 120) continue;
        if (grabAttachClosingSpeed(handBody, otherBody) > MAX_GRAB_ATTACH_CLOSING) {
          continue;
        }

        let pinContact = contact;
        let pinStiffness: number | undefined;
        let itemComposite: Composite | undefined;
        if (isWeapon) {
          itemComposite = itemComposites.find(
            (c) =>
              c.bodies.some((b) => b.id === target.bodyId) ||
              itemLeafBodies(c).some((b) => b.id === target.bodyId),
          );
          if (itemComposite) {
            snapWeaponGripToHand(itemComposite, handBody);
            pinContact = {
              x: handBody.position.x,
              y: handBody.position.y,
            };
            pinStiffness = 0.85;
            tagItemOwner(itemComposite, fighterId);
          }
        }

        const constraints = createGrabPin(
          engine,
          handBody,
          otherBody,
          target.kind,
          pinContact,
          pinStiffness != null ? { stiffness: pinStiffness } : undefined,
        );
        if (isWeapon && itemComposite && fighter) {
          constraints.push(
            createWeaponGuidePin(
              engine,
              handBody,
              otherBody,
              guideWorldPoint(itemComposite),
              forearmProximalWorld(handBody, fighter.composite),
            ),
          );
        }
        dampGrabBodies(handBody, otherBody.isStatic ? null : otherBody);

        const attached = {
          ...handGrabAttached(handState, target, now),
          constraints,
        };
        if (side === "left") {
          this.states.set(fighterId, { ...st, left: attached });
        } else {
          this.states.set(fighterId, { ...st, right: attached });
        }
      }
    }
  }

  getPlayerGrab(fighterId: string): FighterGrabState | null {
    return this.states.get(fighterId) ?? null;
  }
}
