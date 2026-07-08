import Matter, {
  type Composite,
  type Engine,
  type IEventCollision,
} from "matter-js";
import { tagItemOwner } from "@/items/buildItem";
import {
  buildCompositeBodyMap,
  createGrabPin,
  dampGrabBodies,
  grabAttachClosingSpeed,
  MAX_GRAB_ATTACH_CLOSING,
  removeGrabConstraints,
  resolveGrabTarget,
} from "@/lib/grab/attach";
import { isHandBody } from "@/lib/grab/hands";
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
import { GRAB_ENABLED } from "@/lib/battleTuning";

export class GrabController {
  readonly states = new Map<string, FighterGrabState>();
  private prevGrabL = new Map<string, boolean>();
  private prevGrabR = new Map<string, boolean>();
  private engine: Engine | null = null;
  private victimHitTrackers = new Map<
    string,
    ReturnType<typeof createGrabHitTracker>
  >();

  setEngine(engine: Engine): void {
    this.engine = engine;
  }

  ensure(fighter: CoreFighterRuntime): FighterGrabState {
    let st = this.states.get(fighter.id);
    if (!st) {
      st = createFighterGrabState(fighter.id);
      this.states.set(fighter.id, st);
      this.prevGrabL.set(fighter.id, false);
      this.prevGrabR.set(fighter.id, false);
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
    if (!GRAB_ENABLED) return;
    const engine = event.source;
    this.engine = engine;
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

        const closing = Matter.Vector.sub(otherBody.position, handBody.position);
        if (Matter.Vector.magnitude(closing) > 120) continue;
        if (grabAttachClosingSpeed(handBody, otherBody) > MAX_GRAB_ATTACH_CLOSING) {
          continue;
        }

        const constraints = createGrabPin(
          engine,
          handBody,
          otherBody,
          target.kind,
          contact,
        );
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

        if (target.kind === "item") {
          const itemComposite = itemComposites.find((c) =>
            c.bodies.some((b) => b.id === target.bodyId),
          );
          if (itemComposite) tagItemOwner(itemComposite, fighterId);
        }
      }
    }
  }

  getPlayerGrab(fighterId: string): FighterGrabState | null {
    return this.states.get(fighterId) ?? null;
  }
}
