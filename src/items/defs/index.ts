import type { ItemDef } from "../registry";

export const fryingPanDef: ItemDef = {
  id: "frying-pan",
  name: "Frying Pan",
  damageType: "blunt",
  atkMult: 1.8,
  dropChanceMult: 0.8,
  toughnessBonus: 0,
  bodies: [
    { x: 0, y: 0, radius: 8, grip: true, render: { fillStyle: "#555" } },
    { x: 28, y: 0, radius: 18, render: { fillStyle: "#999" } },
  ],
  links: [{ from: 0, to: 1, type: "rigid" }],
};

export const spearDef: ItemDef = {
  id: "spear",
  name: "Spear",
  damageType: "pierce",
  atkMult: 1.6,
  dropChanceMult: 1.2,
  toughnessBonus: 0.1,
  bodies: [
    { x: 0, y: 0, radius: 7, grip: true, render: { fillStyle: "#654" } },
    { x: 22, y: 0, radius: 6, render: { fillStyle: "#876" } },
    { x: 44, y: 0, radius: 5, render: { fillStyle: "#cba" } },
    { x: 66, y: 0, radius: 4, render: { fillStyle: "#ddd" } },
  ],
  links: [
    { from: 0, to: 1, type: "rigid" },
    { from: 1, to: 2, type: "rigid" },
    { from: 2, to: 3, type: "rigid" },
  ],
};

export const chainFlailDef: ItemDef = {
  id: "chain-flail",
  name: "Chain Flail",
  damageType: "force",
  atkMult: 2.2,
  dropChanceMult: 1.5,
  toughnessBonus: 0.05,
  bodies: [
    { x: 0, y: 0, radius: 8, grip: true, render: { fillStyle: "#444" } },
    { x: 20, y: 0, radius: 6, render: { fillStyle: "#666" } },
    { x: 42, y: 0, radius: 14, render: { fillStyle: "#888" } },
  ],
  links: [
    { from: 0, to: 1, type: "rope" },
    { from: 1, to: 2, type: "spring" },
  ],
};

export const torchDef: ItemDef = {
  id: "torch",
  name: "Torch",
  damageType: "fire",
  atkMult: 1.5,
  dropChanceMult: 1.0,
  toughnessBonus: 0,
  bodies: [
    { x: 0, y: 0, radius: 7, grip: true, render: { fillStyle: "#5c4033" } },
    { x: 24, y: 0, radius: 10, render: { fillStyle: "#f97316" } },
  ],
  links: [{ from: 0, to: 1, type: "rigid" }],
};
