import { describe, expect, it } from "vitest";
import {
  canCompositeDealDamage,
  canFightersTradeDamage,
  filterDamageFromDeadAggressors,
} from "./combatActive";
import { markKoScattered } from "./victoryKoScatter";
import Matter from "matter-js";

describe("canFightersTradeDamage", () => {
  const a = Matter.Composite.create({ label: "a" });
  const b = Matter.Composite.create({ label: "b" });
  const playerId = a.id;
  const opponentId = b.id;

  it("blocks after battle over", () => {
    expect(
      canFightersTradeDamage(a.id, b.id, [a, b], {
        battleOver: true,
        playerHp: 100,
        opponentHp: 10,
        playerCompositeId: playerId,
        opponentCompositeId: opponentId,
      }),
    ).toBe(false);
  });

  it("blocks when loser ragdoll is scattered", () => {
    markKoScattered(b);
    expect(
      canFightersTradeDamage(a.id, b.id, [a, b], {
        battleOver: false,
        playerHp: 100,
        opponentHp: 10,
        playerCompositeId: playerId,
        opponentCompositeId: opponentId,
      }),
    ).toBe(false);
  });

  it("allows hits during active fight", () => {
    const freshA = Matter.Composite.create({ label: "a2" });
    const freshB = Matter.Composite.create({ label: "b2" });
    expect(
      canFightersTradeDamage(freshA.id, freshB.id, [freshA, freshB], {
        battleOver: false,
        playerHp: 100,
        opponentHp: 10,
        playerCompositeId: freshA.id,
        opponentCompositeId: freshB.id,
      }),
    ).toBe(true);
  });

  it("blocks outgoing damage from dead player ghost head", () => {
    expect(
      canCompositeDealDamage(playerId, {
        battleOver: false,
        playerHp: 0,
        opponentHp: 50,
        playerCompositeId: playerId,
        opponentCompositeId: opponentId,
      }),
    ).toBe(false);

    const filtered = filterDamageFromDeadAggressors(
      playerId,
      opponentId,
      0,
      25,
      {
        battleOver: false,
        playerHp: 0,
        opponentHp: 50,
        playerCompositeId: playerId,
        opponentCompositeId: opponentId,
      },
    );
    expect(filtered.damageB).toBe(0);
  });
});
