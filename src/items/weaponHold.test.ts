import { describe, expect, it } from "vitest";
import Matter, { Body } from "matter-js";
import { createStickman } from "@/utils/createStickman";
import { createBattleSession } from "@/core/battleSession";
import { createArenaWalls } from "@/battle/headlessWalls";
import { tagStickmanHands } from "@/lib/grab/hands";
import { WEAPON_HOLD_ENABLED } from "@/lib/battleTuning";
import {
  buildItem,
  items,
  itemOwnerId,
  WEAPON_CATALOG,
  WEAPON_CATALOG_IDS,
  pickArenaWeapons,
} from "@/items";
import "./index";
import {
  dist2,
  findGripBody,
  findNearestUnownedWeapon,
  gripWorldPoint,
  heldWeaponMoveMult,
  isHoldingAnyWeapon,
  pickFreeHand,
} from "./weaponHold";
import { createFighterGrabState } from "@/lib/grab/types";
import { getHandBody } from "@/lib/grab/hands";

describe("weapon catalog", () => {
  it("registers 30+ unique weapons with a grip", () => {
    expect(WEAPON_CATALOG.length).toBeGreaterThanOrEqual(30);
    expect(new Set(WEAPON_CATALOG_IDS).size).toBe(WEAPON_CATALOG.length);
    for (const def of WEAPON_CATALOG) {
      const built = buildItem(items.get(def.id), 100, 100);
      expect(findGripBody(built)).toBeTruthy();
      expect(def.atkMult).toBeGreaterThan(1);
      expect(items.get(def.id).damageType).toBeTruthy();
    }
  });

  it("pickArenaWeapons returns unique sample", () => {
    const picked = pickArenaWeapons(4, () => 0.42);
    expect(picked).toHaveLength(4);
    expect(new Set(picked).size).toBe(4);
  });
});

describe("weaponHold helpers", () => {
  it("finds nearest unowned weapon", () => {
    const a = buildItem(items.get("sword"), 200, 200);
    const b = buildItem(items.get("taser"), 400, 200);
    const near = findNearestUnownedWeapon({ x: 210, y: 200 }, [a, b], 80);
    expect(near?.composite).toBe(a);
  });

  it("pickFreeHand prefers left then right", () => {
    const st = createFighterGrabState("p");
    expect(pickFreeHand(st)).toBe("left");
    st.left.phase = "attached";
    st.left.target = { bodyId: 1, kind: "grip" };
    expect(pickFreeHand(st)).toBe("right");
    st.right.phase = "attached";
    st.right.target = { bodyId: 2, kind: "grip" };
    expect(pickFreeHand(st)).toBeNull();
    expect(isHoldingAnyWeapon(st)).toBe(true);
  });
});

describe("auto-pickup + drop", () => {
  it("auto-picks nearby weapon and drops on dropWeapon", () => {
    expect(WEAPON_HOLD_ENABLED).toBe(true);
    const arena = 1000;
    const bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: arena, y: arena },
    ]);
    const walls = createArenaWalls(bounds, arena);
    const fighter = createStickman(300, 500, { render: { visible: false } });
    tagStickmanHands(fighter, "player");
    const head = fighter.bodies.find((b) => b.label === "Head")!;
    for (const body of fighter.bodies) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }

    const hand = getHandBody(fighter, "left")!;
    expect(hand).toBeTruthy();
    const weapon = buildItem(
      items.get("taser"),
      hand.position.x + 10,
      hand.position.y,
    );
    const session = createBattleSession({
      arenaSize: arena,
      walls,
      fighters: [
        {
          id: "player",
          composite: fighter,
          head,
          maxHp: 200,
          // без team — иначе 1 боец = бой сразу окончен (teams.size<=1)
        },
      ],
      itemComposites: [weapon],
      compositesInWorld: false,
    });
    session.beginBattle();
    session.engine.gravity.scale = 0;

    const fighterRt = session.getFighter("player")!;
    expect(
      session.grab.tryAutoPickup(
        fighterRt,
        session.itemComposites,
        1000,
        120,
      ),
    ).toBe(true);
    expect(itemOwnerId(weapon)).toBe("player");
    const held = session.grab.getPlayerGrab("player")!;
    expect(held.left.phase === "attached" || held.right.phase === "attached").toBe(
      true,
    );
    expect(isHoldingAnyWeapon(held)).toBe(true);

    // Тяжёлое в руках режет moveSpeedMult.
    session.tick(1000 / 60, false);
    {
      const g = session.grab.getPlayerGrab("player");
      expect(g && isHoldingAnyWeapon(g)).toBe(true);
      expect(heldWeaponMoveMult(g!, session.itemComposites)).toBeLessThan(0.98);
      expect(session.getFighter("player")!.moveSpeedMult).toBeLessThan(0.98);
    }

    // Оружие едет с бойцом и держит рукоять у кисти.
    // advanceEngine=true: иначе Matter не интегрирует pin/движение.
    const handNow =
      getHandBody(fighter, "left") ?? getHandBody(fighter, "right")!;
    const startHx = handNow.position.x;
    const startWx = weapon.bodies[0]!.position.x;
    // move.x < 0 → вправо (конвенция moveBody / abilityTick).
    session.setInput("player", {
      ...fighterRt.input,
      move: { x: -1, y: 0 },
    });
    for (let i = 0; i < 48; i++) {
      session.tick(1000 / 60, true);
    }
    expect(handNow.position.x).toBeGreaterThan(startHx + 20);
    expect(weapon.bodies[0]!.position.x).toBeGreaterThan(startWx + 12);
    expect(
      Math.sqrt(dist2(gripWorldPoint(weapon), handNow.position)),
    ).toBeLessThan(48);

    // drop через input one-shot на тике
    session.setInput("player", {
      ...fighterRt.input,
      dropWeapon: true,
    });
    session.tick(1000 / 60, false);

    expect(itemOwnerId(weapon)).toBeNull();
    expect(isHoldingAnyWeapon(session.grab.getPlayerGrab("player")!)).toBe(
      false,
    );

    session.destroy();
  });

  it("does not steal an already owned weapon", () => {
    const arena = 1000;
    const bounds = Matter.Bounds.create([
      { x: 0, y: 0 },
      { x: arena, y: arena },
    ]);
    const walls = createArenaWalls(bounds, arena);
    const a = createStickman(250, 500, { render: { visible: false } });
    const b = createStickman(450, 500, { render: { visible: false } });
    tagStickmanHands(a, "a");
    tagStickmanHands(b, "b");
    const headA = a.bodies.find((x) => x.label === "Head")!;
    const headB = b.bodies.find((x) => x.label === "Head")!;
    for (const body of [...a.bodies, ...b.bodies]) {
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }
    const handA = getHandBody(a, "left")!;
    const weapon = buildItem(
      items.get("sword"),
      handA.position.x + 10,
      handA.position.y,
    );
    const session = createBattleSession({
      arenaSize: arena,
      walls,
      fighters: [
        { id: "a", composite: a, head: headA, maxHp: 200, team: 0 },
        { id: "b", composite: b, head: headB, maxHp: 200, team: 1 },
      ],
      itemComposites: [weapon],
      compositesInWorld: false,
    });
    session.beginBattle();
    session.engine.gravity.scale = 0;
    const aRt = session.getFighter("a")!;
    const bRt = session.getFighter("b")!;
    expect(
      session.grab.tryAutoPickup(aRt, session.itemComposites, 1000, 120),
    ).toBe(true);
    expect(itemOwnerId(weapon)).toBe("a");

    // b рядом — не должен перехватить
    expect(session.grab.tryAutoPickup(bRt, session.itemComposites, 2000)).toBe(
      false,
    );
    expect(itemOwnerId(weapon)).toBe("a");
    session.destroy();
  });
});
