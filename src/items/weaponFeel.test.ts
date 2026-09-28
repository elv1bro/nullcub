import { describe, expect, it } from "vitest";
import Matter, { Body } from "matter-js";
import {
  buildItem,
  tagItemOwner,
  weaponHoldMoveMult,
  weaponMassOf,
} from "./buildItem";
import { items } from "./registry";
import {
  filterFriendlyWeaponDamage,
  resolveWeaponFromBody,
} from "./resolveWeaponHit";
import { WEAPON_CATALOG } from "./defs/catalog";
import { findGripBody, gripWorldPoint } from "./weaponHold";
import "./index";

describe("solid weapons", () => {
  it("default arena rigid weapons are single solid bodies with mass", () => {
    for (const id of ["sword", "taser", "frying-pan"] as const) {
      const def = items.get(id);
      expect(def.solid, `${id} solid`).toBeTruthy();
      const built = buildItem(def, 0, 0);
      expect(built.bodies.length).toBe(1);
      expect(built.constraints.length).toBe(0);
      expect(built.bodies[0]!.mass).toBeGreaterThan(0.5);
      expect(findGripBody(built)).toBe(built.bodies[0]);
      const grip = gripWorldPoint(built);
      expect(Number.isFinite(grip.x)).toBe(true);
    }
  });

  it("shaped weapons are compound with ≥2 parts", () => {
    for (const id of ["sword", "axe", "spear", "taser", "hammer"] as const) {
      const def = items.get(id);
      expect(def.solid?.parts?.length, `${id} parts`).toBeGreaterThanOrEqual(2);
      const built = buildItem(def, 100, 100);
      const body = built.bodies[0]!;
      expect(body.parts.length).toBeGreaterThan(1);
      const grip = gripWorldPoint(built);
      expect(Number.isFinite(grip.x)).toBe(true);
      expect(Number.isFinite(grip.y)).toBe(true);
      // Плагин на part — коллизии приходят по частям.
      const leaf = body.parts.find((p) => p !== body)!;
      expect((leaf.plugin as { itemId?: string }).itemId).toBe(id);
    }
  });

  it("catalog still has 30+ weapons", () => {
    expect(WEAPON_CATALOG.length).toBeGreaterThanOrEqual(30);
    for (const def of WEAPON_CATALOG) {
      const built = buildItem(def, 0, 0);
      expect(findGripBody(built)).toBeTruthy();
    }
  });

  it("rope flail stays multi-body", () => {
    const flail = buildItem(items.get("chain-flail"), 0, 0);
    expect(flail.bodies.length).toBeGreaterThan(1);
    expect(flail.constraints.length).toBeGreaterThan(0);
  });

  it("sword settles without wild spin under gravity", () => {
    const engine = Matter.Engine.create({
      gravity: { x: 0, y: 1, scale: 0.001 },
    });
    const sword = buildItem(items.get("sword"), 400, 200);
    const ground = Matter.Bodies.rectangle(400, 900, 800, 40, {
      isStatic: true,
    });
    Matter.Composite.add(engine.world, [sword, ground]);
    for (let i = 0; i < 240; i++) Matter.Engine.update(engine, 1000 / 60);
    const w = sword.bodies[0]!.angularVelocity;
    expect(Number.isFinite(w)).toBe(true);
    expect(Math.abs(w)).toBeLessThan(0.4);
  });

  it("heavier weapons slow move more", () => {
    expect(weaponHoldMoveMult(0.75)).toBeGreaterThan(weaponHoldMoveMult(2.5));
    expect(weaponHoldMoveMult(3.6)).toBeLessThan(0.6);
    expect(weaponMassOf(buildItem(items.get("shotput"), 0, 0))).toBeGreaterThan(
      weaponMassOf(buildItem(items.get("dagger"), 0, 0)),
    );
  });
});

describe("friendly weapon damage", () => {
  it("zeros damage when owned weapon hits owner", () => {
    const weapon = buildItem(items.get("sword"), 100, 100);
    tagItemOwner(weapon, "player");
    const blade = weapon.bodies[0]!;
    const chest = Matter.Bodies.rectangle(120, 100, 40, 40, {
      label: "Chest",
    });
    (chest.plugin as { fighterId?: string }) = { fighterId: "player" };

    const info = resolveWeaponFromBody(blade);
    expect(info?.ownerFighterId).toBe("player");

    const filtered = filterFriendlyWeaponDamage(
      blade,
      chest,
      undefined,
      "player",
      0,
      80,
    );
    expect(filtered.damageA).toBe(0);
    expect(filtered.damageB).toBe(0);
  });

  it("allows damage when weapon hits enemy", () => {
    const weapon = buildItem(items.get("sword"), 100, 100);
    tagItemOwner(weapon, "player");
    const blade = weapon.bodies[0]!;
    Body.setVelocity(blade, { x: 8, y: 0 });
    const filtered = filterFriendlyWeaponDamage(
      blade,
      Matter.Bodies.circle(200, 100, 20, { label: "Chest" }),
      undefined,
      "opponent",
      0,
      80,
    );
    expect(filtered.damageB).toBe(80);
  });

  it("compound part resolves as weapon for damage", () => {
    const weapon = buildItem(items.get("sword"), 100, 100);
    tagItemOwner(weapon, "attacker");
    const parent = weapon.bodies[0]!;
    const leaf = parent.parts.find((p) => p !== parent && p.label === "Blade")!;
    expect(leaf).toBeTruthy();
    const info = resolveWeaponFromBody(leaf);
    expect(info?.itemId).toBe("sword");
    expect(info?.ownerFighterId).toBe("attacker");
    const filtered = filterFriendlyWeaponDamage(
      leaf,
      Matter.Bodies.circle(200, 100, 20, { label: "Chest" }),
      undefined,
      "victim",
      0,
      80,
    );
    expect(filtered.damageB).toBe(80);
  });
});
