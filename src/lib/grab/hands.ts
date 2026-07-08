import type { Body, Composite } from "matter-js";
import { grabPlugin, type HandSide } from "./types";

const HAND_LABELS: Record<HandSide, string> = {
  left: "Lower Left Arm",
  right: "Lower Right Arm",
};

function getDistalArmBody(
  composite: Composite,
  side: HandSide,
): Body | undefined {
  const label = HAND_LABELS[side];
  const arms = composite.bodies.filter((b) => b.label === label);
  if (!arms.length) return undefined;
  if (side === "left") {
    return arms.reduce((a, b) => (a.position.x < b.position.x ? a : b));
  }
  return arms.reduce((a, b) => (a.position.x > b.position.x ? a : b));
}

/** Кисть = дистальный сегмент предплечья. */
export function getHandBody(
  composite: Composite,
  side: HandSide,
): Body | undefined {
  for (const body of composite.bodies) {
    const plugin = grabPlugin(body);
    if (plugin.part === (side === "left" ? "handL" : "handR")) return body;
  }
  return getDistalArmBody(composite, side);
}

export function tagStickmanHands(
  composite: Composite,
  fighterId: string,
): void {
  const leftHand = getDistalArmBody(composite, "left");
  const rightHand = getDistalArmBody(composite, "right");

  for (const body of composite.bodies) {
    const plugin = grabPlugin(body);
    plugin.fighterId = fighterId;
    if (body === leftHand) plugin.part = "handL";
    if (body === rightHand) plugin.part = "handR";
    body.plugin = plugin;
  }
}

export function isHandBody(body: Body): boolean {
  const part = grabPlugin(body).part;
  return part === "handL" || part === "handR";
}
