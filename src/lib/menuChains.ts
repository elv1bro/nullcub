import Matter from "matter-js";

export interface MenuChainLink {
  side: "left" | "right";
  /** Фиксированная точка на стене — не двигается после создания. */
  anchor: Matter.Vector;
  constraint: Matter.Constraint;
}

export interface ChainBreakEvent {
  anchor: Matter.Vector;
  attach: Matter.Vector;
  side: "left" | "right";
}

export interface MenuChainSet {
  links: MenuChainLink[];
  spawnX: number;
  spawnY: number;
}

export const MENU_CHAIN_COUNT = 2;

const CHAIN_SPREAD_X = 108;
const CHAIN_TOP_OFFSET_Y = 188;
const CHAIN_STIFFNESS = 0.72;
const CHAIN_DAMPING = 0.08;

export function findHandBody(
  composite: Matter.Composite,
  side: "left" | "right",
): Matter.Body | undefined {
  const label = side === "left" ? "Lower Left Arm" : "Lower Right Arm";
  const candidates = composite.bodies.filter((b) => b.label === label);
  if (candidates.length === 0) return undefined;

  return side === "left"
    ? candidates.reduce((a, b) => (a.position.x < b.position.x ? a : b))
    : candidates.reduce((a, b) => (a.position.x > b.position.x ? a : b));
}

export function handAttachWorld(
  composite: Matter.Composite,
  side: "left" | "right",
): Matter.Vector | null {
  const hand = findHandBody(composite, side);
  if (!hand) return null;

  const r = hand.circleRadius ?? 10;
  const local = { x: side === "left" ? -r : r, y: 0 };
  const cos = Math.cos(hand.angle);
  const sin = Math.sin(hand.angle);
  return {
    x: hand.position.x + local.x * cos - local.y * sin,
    y: hand.position.y + local.x * sin + local.y * cos,
  };
}

export function chainAnchorForSide(
  centerX: number,
  centerY: number,
  side: "left" | "right",
): Matter.Vector {
  const topY = centerY - CHAIN_TOP_OFFSET_Y;
  return side === "left"
    ? { x: centerX - CHAIN_SPREAD_X, y: topY }
    : { x: centerX + CHAIN_SPREAD_X, y: topY };
}

function chainCenterFromRagdoll(composite: Matter.Composite): Matter.Vector | null {
  const head = composite.bodies.find((b) => b.label === "Head");
  if (!head) return null;
  return { x: head.position.x, y: head.position.y + 30 };
}

function sideToAttach(chainSet: MenuChainSet): "left" | "right" | null {
  const present = new Set(chainSet.links.map((l) => l.side));
  if (!present.has("left")) return "left";
  if (!present.has("right")) return "right";
  return null;
}

type AnchorMode = "spawn" | "current";

function resolveAnchor(
  chainSet: MenuChainSet,
  composite: Matter.Composite,
  side: "left" | "right",
  mode: AnchorMode,
): Matter.Vector {
  if (mode === "spawn") {
    return chainAnchorForSide(chainSet.spawnX, chainSet.spawnY, side);
  }
  const center = chainCenterFromRagdoll(composite);
  if (!center) {
    return chainAnchorForSide(chainSet.spawnX, chainSet.spawnY, side);
  }
  return chainAnchorForSide(center.x, center.y, side);
}

function makeChainLink(
  chainSet: MenuChainSet,
  composite: Matter.Composite,
  side: "left" | "right",
  anchorMode: AnchorMode,
): MenuChainLink | null {
  const hand = findHandBody(composite, side);
  if (!hand) return null;

  const anchor = resolveAnchor(chainSet, composite, side, anchorMode);
  const attach = handAttachWorld(composite, side) ?? hand.position;
  const r = hand.circleRadius ?? 10;

  // Длина = текущее расстояние рука↔якорь. 14px ломало всё — рвало вверх.
  const length = Math.max(
    40,
    Matter.Vector.magnitude(Matter.Vector.sub(anchor, attach)),
  );

  const constraint = Matter.Constraint.create({
    pointA: { x: anchor.x, y: anchor.y },
    bodyB: hand,
    pointB: { x: side === "left" ? -r : r, y: 0 },
    length,
    stiffness: CHAIN_STIFFNESS,
    damping: CHAIN_DAMPING,
    render: { visible: false },
  });

  Matter.Composite.add(composite, constraint);
  return { side, anchor, constraint };
}

export function attachChainSide(
  chainSet: MenuChainSet,
  composite: Matter.Composite,
  side: "left" | "right",
  anchorMode: AnchorMode = "spawn",
): boolean {
  if (chainSet.links.some((l) => l.side === side)) return false;
  const link = makeChainLink(chainSet, composite, side, anchorMode);
  if (!link) return false;
  chainSet.links.push(link);
  return true;
}

export function createMenuChains(
  composite: Matter.Composite,
  spawnX: number,
  spawnY: number,
): MenuChainSet {
  const chainSet: MenuChainSet = { links: [], spawnX, spawnY };
  attachChainSide(chainSet, composite, "left", "spawn");
  attachChainSide(chainSet, composite, "right", "spawn");
  return chainSet;
}

export function breakOneChain(
  chainSet: MenuChainSet,
  composite: Matter.Composite,
  side?: "left" | "right",
): ChainBreakEvent | null {
  const idx = side ? chainSet.links.findIndex((l) => l.side === side) : 0;
  if (idx < 0) return null;

  const [link] = chainSet.links.splice(idx, 1);
  if (!link) return null;

  Matter.Composite.remove(composite, link.constraint);

  const attach = handAttachWorld(composite, link.side) ?? link.anchor;
  return { anchor: { ...link.anchor }, attach, side: link.side };
}

export function syncMenuChains(
  chainSet: MenuChainSet,
  composite: Matter.Composite,
  brokenCount: number,
): ChainBreakEvent[] {
  const wantRemaining = Math.max(0, MENU_CHAIN_COUNT - brokenCount);
  const events: ChainBreakEvent[] = [];

  while (chainSet.links.length > wantRemaining) {
    const evt = breakOneChain(chainSet, composite);
    if (!evt) break;
    events.push(evt);
  }

  // Восстановление: якоря над текущей позицией — без телепорта к spawn.
  while (chainSet.links.length < wantRemaining) {
    const side = sideToAttach(chainSet);
    if (!side) break;
    if (!attachChainSide(chainSet, composite, side, "current")) break;
  }

  return events;
}

export function clearMenuChains(
  chainSet: MenuChainSet,
  composite: Matter.Composite,
): void {
  for (const link of chainSet.links) {
    Matter.Composite.remove(composite, link.constraint);
  }
  chainSet.links = [];
}

export function chainSegments(
  chainSet: MenuChainSet,
  composite: Matter.Composite,
): Array<{ ax: number; ay: number; bx: number; by: number }> {
  return chainSet.links.flatMap((l) => {
    const hand = handAttachWorld(composite, l.side);
    if (!hand) return [];
    return [{ ax: l.anchor.x, ay: l.anchor.y, bx: hand.x, by: hand.y }];
  });
}

export function chainAnchors(chainSet: MenuChainSet): Matter.Vector[] {
  return chainSet.links.map((l) => l.anchor);
}
