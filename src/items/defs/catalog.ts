import type {
  ItemBodySpec,
  ItemDef,
  ItemLinkSpec,
  SolidWeaponPart,
  SolidWeaponSpec,
} from "../registry";

type Part = {
  x: number;
  y: number;
  r?: number;
  w?: number;
  h?: number;
  grip?: boolean;
  color: string;
};

function part(p: Part): ItemBodySpec {
  const base: ItemBodySpec = {
    x: p.x,
    y: p.y,
    grip: p.grip,
    render: { fillStyle: p.color, strokeStyle: "#0f172a", lineWidth: 1.5 },
  };
  if (p.w != null && p.h != null) {
    return { ...base, width: p.w, height: p.h, radius: Math.min(p.w, p.h) / 2 };
  }
  return { ...base, radius: p.r ?? 8 };
}

function links(...pairs: Array<[number, number, ItemLinkSpec["type"]?]>): ItemLinkSpec[] {
  return pairs.map(([from, to, type]) => ({
    from,
    to,
    type: type ?? "rigid",
  }));
}

const HANDLE = "#78350f";
const HANDLE_DARK = "#44403c";
const METAL = "#e2e8f0";
const METAL_DARK = "#94a3b8";
const GUARD = "#a8a29e";

function solid(
  id: string,
  name: string,
  damageType: string,
  atk: number,
  drop: number,
  solidSpec: SolidWeaponSpec,
  toughnessBonus = 0,
): ItemDef {
  return {
    id,
    name,
    damageType,
    atkMult: atk,
    dropChanceMult: drop,
    toughnessBonus,
    bodies: [],
    links: [],
    solid: solidSpec,
  };
}

/** Рукоять + гарда + лезвие. Origin = геометрический центр. */
function bladed(
  id: string,
  name: string,
  damageType: string,
  atk: number,
  drop: number,
  opts: {
    length: number;
    thickness: number;
    mass: number;
    bladeColor?: string;
    handleColor?: string;
    /** Доля длины: рукоять (default 0.22). */
    handleFrac?: number;
  },
): ItemDef {
  const L = opts.length;
  const T = opts.thickness;
  const handleFrac = opts.handleFrac ?? 0.22;
  const handleLen = L * handleFrac;
  const bladeLen = L * (1 - handleFrac) - 4;
  const left = -L / 2;
  const handleCx = left + handleLen / 2;
  const guardX = left + handleLen + 1;
  const bladeCx = guardX + 3 + bladeLen / 2;
  const bladeColor = opts.bladeColor ?? METAL;
  const handleColor = opts.handleColor ?? HANDLE;
  const parts: SolidWeaponPart[] = [
    {
      x: handleCx,
      y: 0,
      w: handleLen,
      h: Math.max(8, T * 0.85),
      color: handleColor,
      label: "Handle",
    },
    {
      x: guardX,
      y: 0,
      w: 5,
      h: T * 2.2,
      color: GUARD,
      label: "Guard",
    },
    {
      x: bladeCx,
      y: 0,
      w: bladeLen,
      h: T,
      color: bladeColor,
      label: "Blade",
    },
  ];
  return solid(id, name, damageType, atk, drop, {
    length: L,
    thickness: T,
    mass: opts.mass,
    color: bladeColor,
    gripLocal: { x: left + handleLen * 0.35, y: 0 },
    parts,
  });
}

/** Древко + голова на правом конце. */
function headed(
  id: string,
  name: string,
  damageType: string,
  atk: number,
  drop: number,
  opts: {
    length: number;
    thickness: number;
    mass: number;
    headW: number;
    headH: number;
    shaftColor?: string;
    headColor?: string;
    headCircle?: boolean;
  },
): ItemDef {
  const L = opts.length;
  const T = opts.thickness;
  const left = -L / 2;
  const shaftLen = L - opts.headW * 0.55;
  const shaftCx = left + shaftLen / 2;
  const headCx = left + L - opts.headW / 2;
  const shaftColor = opts.shaftColor ?? HANDLE;
  const headColor = opts.headColor ?? METAL_DARK;
  const parts: SolidWeaponPart[] = [
    {
      x: shaftCx,
      y: 0,
      w: shaftLen,
      h: T,
      color: shaftColor,
      label: "Shaft",
    },
  ];
  if (opts.headCircle) {
    parts.push({
      x: headCx,
      y: 0,
      r: Math.max(opts.headW, opts.headH) / 2,
      color: headColor,
      label: "Head",
    });
  } else {
    parts.push({
      x: headCx,
      y: 0,
      w: opts.headW,
      h: opts.headH,
      color: headColor,
      label: "Head",
    });
  }
  return solid(id, name, damageType, atk, drop, {
    length: L,
    thickness: Math.max(T, opts.headH),
    mass: opts.mass,
    color: headColor,
    gripLocal: { x: left + shaftLen * 0.2, y: 0 },
    parts,
  });
}

/** Длинное древко + наконечник(и). */
function pole(
  id: string,
  name: string,
  damageType: string,
  atk: number,
  drop: number,
  opts: {
    length: number;
    thickness: number;
    mass: number;
    tipKind?: "point" | "fork" | "blade" | "cap";
    shaftColor?: string;
    tipColor?: string;
  },
): ItemDef {
  const L = opts.length;
  const T = opts.thickness;
  const left = -L / 2;
  const tipKind = opts.tipKind ?? "point";
  const tipLen = tipKind === "fork" ? 18 : tipKind === "blade" ? 22 : 14;
  const shaftLen = L - tipLen;
  const shaftCx = left + shaftLen / 2;
  const tipBase = left + shaftLen;
  const shaftColor = opts.shaftColor ?? HANDLE;
  const tipColor = opts.tipColor ?? METAL;
  const parts: SolidWeaponPart[] = [
    {
      x: shaftCx,
      y: 0,
      w: shaftLen,
      h: T,
      color: shaftColor,
      label: "Shaft",
    },
  ];
  if (tipKind === "fork") {
    parts.push(
      { x: tipBase + 8, y: -T * 1.1, w: 14, h: T * 0.7, color: tipColor, label: "Tine" },
      { x: tipBase + 10, y: 0, w: 16, h: T * 0.7, color: tipColor, label: "Tine" },
      { x: tipBase + 8, y: T * 1.1, w: 14, h: T * 0.7, color: tipColor, label: "Tine" },
    );
  } else if (tipKind === "blade") {
    parts.push({
      x: tipBase + tipLen / 2,
      y: -T * 0.6,
      w: tipLen,
      h: T * 1.4,
      color: tipColor,
      label: "Blade",
    });
  } else if (tipKind === "cap") {
    parts.push({
      x: tipBase + tipLen / 2,
      y: 0,
      r: Math.max(8, T * 1.2),
      color: tipColor,
      label: "Cap",
    });
  } else {
    parts.push({
      x: tipBase + tipLen / 2,
      y: 0,
      w: tipLen,
      h: T * 1.3,
      color: tipColor,
      label: "Tip",
    });
  }
  return solid(id, name, damageType, atk, drop, {
    length: L,
    thickness: T,
    mass: opts.mass,
    color: tipColor,
    gripLocal: { x: left + L * 0.12, y: 0 },
    parts,
  });
}

/** Корпус + выступающая деталь (сковорода, тазер, кирпич…). */
function chunky(
  id: string,
  name: string,
  damageType: string,
  atk: number,
  drop: number,
  opts: {
    length: number;
    thickness: number;
    mass: number;
    bodyColor: string;
    accentColor?: string;
    kind:
      | "pan"
      | "taser"
      | "brick"
      | "bottle"
      | "extinguisher"
      | "cone"
      | "chainsaw"
      | "banjo"
      | "baton";
  },
): ItemDef {
  const L = opts.length;
  const T = opts.thickness;
  const left = -L / 2;
  const accent = opts.accentColor ?? HANDLE;
  const parts: SolidWeaponPart[] = [];

  switch (opts.kind) {
    case "pan": {
      const handleLen = L * 0.42;
      parts.push(
        {
          x: left + handleLen / 2,
          y: 0,
          w: handleLen,
          h: T * 0.45,
          color: accent,
          label: "Handle",
        },
        {
          x: left + handleLen + (L - handleLen) / 2,
          y: 0,
          r: Math.max(14, T * 0.7),
          color: opts.bodyColor,
          label: "Pan",
        },
      );
      break;
    }
    case "taser": {
      parts.push(
        {
          x: 0,
          y: 0,
          w: L * 0.7,
          h: T,
          color: opts.bodyColor,
          label: "Body",
        },
        {
          x: left + L * 0.12,
          y: 0,
          w: L * 0.22,
          h: T * 0.7,
          color: accent,
          label: "Grip",
        },
        {
          x: left + L - 4,
          y: -T * 0.45,
          w: 8,
          h: 4,
          color: METAL,
          label: "Prong",
        },
        {
          x: left + L - 4,
          y: T * 0.45,
          w: 8,
          h: 4,
          color: METAL,
          label: "Prong",
        },
      );
      break;
    }
    case "brick": {
      parts.push({
        x: 0,
        y: 0,
        w: L,
        h: T,
        color: opts.bodyColor,
        label: "Brick",
      });
      break;
    }
    case "bottle": {
      parts.push(
        {
          x: left + L * 0.35,
          y: 0,
          w: L * 0.55,
          h: T,
          color: opts.bodyColor,
          label: "Body",
        },
        {
          x: left + L * 0.78,
          y: 0,
          w: L * 0.28,
          h: T * 0.45,
          color: accent,
          label: "Neck",
        },
      );
      break;
    }
    case "extinguisher": {
      parts.push(
        {
          x: 0,
          y: 0,
          w: L * 0.7,
          h: T,
          color: opts.bodyColor,
          label: "Tank",
        },
        {
          x: left + L * 0.15,
          y: 0,
          w: 8,
          h: T * 0.5,
          color: HANDLE_DARK,
          label: "Handle",
        },
        {
          x: left + L * 0.85,
          y: -T * 0.2,
          w: 10,
          h: 8,
          color: METAL_DARK,
          label: "Nozzle",
        },
      );
      break;
    }
    case "cone": {
      parts.push(
        {
          x: 0,
          y: 0,
          w: L * 0.55,
          h: T,
          color: opts.bodyColor,
          label: "Cone",
        },
        {
          x: left + L * 0.15,
          y: 0,
          w: L * 0.35,
          h: T * 0.55,
          color: "#fafafa",
          label: "Stripe",
        },
      );
      break;
    }
    case "chainsaw": {
      parts.push(
        {
          x: left + L * 0.22,
          y: 0,
          w: L * 0.4,
          h: T,
          color: opts.bodyColor,
          label: "Body",
        },
        {
          x: left + L * 0.65,
          y: 0,
          w: L * 0.5,
          h: T * 0.55,
          color: METAL_DARK,
          label: "Bar",
        },
        {
          x: left + L * 0.12,
          y: T * 0.35,
          w: 10,
          h: 8,
          color: accent,
          label: "Grip",
        },
      );
      break;
    }
    case "banjo": {
      parts.push(
        {
          x: left + L * 0.28,
          y: 0,
          w: L * 0.5,
          h: T * 0.4,
          color: accent,
          label: "Neck",
        },
        {
          x: left + L * 0.75,
          y: 0,
          r: Math.max(12, T * 0.55),
          color: opts.bodyColor,
          label: "Body",
        },
      );
      break;
    }
    case "baton": {
      parts.push(
        {
          x: 0,
          y: 0,
          w: L,
          h: T,
          color: opts.bodyColor,
          label: "Shaft",
        },
        {
          x: left + L * 0.12,
          y: 0,
          w: L * 0.22,
          h: T * 1.15,
          color: accent,
          label: "Grip",
        },
        {
          x: left + L - 5,
          y: 0,
          r: T * 0.55,
          color: "#67e8f9",
          label: "Tip",
        },
      );
      break;
    }
  }

  return solid(id, name, damageType, atk, drop, {
    length: L,
    thickness: T,
    mass: opts.mass,
    color: opts.bodyColor,
    gripLocal: { x: left + L * 0.14, y: 0 },
    parts,
  });
}

/** Верёвочное — бусины с gap. */
function ropeWeapon(
  id: string,
  name: string,
  damageType: string,
  atk: number,
  drop: number,
  beads: Part[],
  linkPairs: Array<[number, number, ItemLinkSpec["type"]?]>,
  toughnessBonus = 0,
): ItemDef {
  const gap = 3;
  let prevRight = 0;
  const laid: Part[] = beads.map((p, i) => {
    const half = p.w != null ? p.w / 2 : (p.r ?? 8);
    const x = i === 0 ? 0 : prevRight + gap + half;
    prevRight = x + half;
    return { ...p, x, y: 0 };
  });
  return {
    id,
    name,
    damageType,
    atkMult: atk,
    dropChanceMult: drop,
    toughnessBonus,
    bodies: laid.map(part),
    links: links(...linkPairs),
  };
}

/** Каталог: compound-силуэты + верёвочные flail/whip/nunchaku. */
export const WEAPON_CATALOG: readonly ItemDef[] = [
  chunky("frying-pan", "Frying Pan", "blunt", 1.8, 0.8, {
    length: 58,
    thickness: 22,
    mass: 2.1,
    bodyColor: "#a8a29e",
    accentColor: HANDLE_DARK,
    kind: "pan",
  }),
  pole("spear", "Spear", "pierce", 1.6, 1.2, {
    length: 88,
    thickness: 8,
    mass: 1.5,
    tipKind: "point",
    shaftColor: "#a16207",
  }),
  ropeWeapon(
    "chain-flail",
    "Chain Flail",
    "force",
    2.2,
    1.5,
    [
      { x: 0, y: 0, r: 8, grip: true, color: "#44403c" },
      { x: 0, y: 0, r: 5, color: "#78716c" },
      { x: 0, y: 0, r: 5, color: "#78716c" },
      { x: 0, y: 0, r: 14, color: "#a1a1aa" },
    ],
    [
      [0, 1, "rope"],
      [1, 2, "rope"],
      [2, 3, "rope"],
    ],
    0.05,
  ),
  headed("torch", "Torch", "fire", 1.5, 1.1, {
    length: 52,
    thickness: 10,
    mass: 1.2,
    headW: 16,
    headH: 16,
    shaftColor: HANDLE,
    headColor: "#f97316",
    headCircle: true,
  }),
  bladed("sword", "Sword", "slash", 1.9, 1.0, {
    length: 72,
    thickness: 10,
    mass: 1.65,
  }),
  chunky("taser", "Taser", "shock", 1.7, 0.9, {
    length: 44,
    thickness: 14,
    mass: 1.1,
    bodyColor: "#38bdf8",
    accentColor: HANDLE_DARK,
    kind: "taser",
  }),
  headed("bat", "Bat", "blunt", 1.7, 0.9, {
    length: 70,
    thickness: 12,
    mass: 1.55,
    headW: 18,
    headH: 16,
    shaftColor: "#a16207",
    headColor: "#854d0e",
  }),
  headed("crowbar", "Crowbar", "blunt", 1.85, 1.0, {
    length: 64,
    thickness: 9,
    mass: 1.9,
    headW: 14,
    headH: 18,
    shaftColor: "#71717a",
    headColor: "#52525b",
  }),
  bladed("katana", "Katana", "slash", 2.05, 1.1, {
    length: 82,
    thickness: 8,
    mass: 1.45,
    bladeColor: "#f8fafc",
    handleColor: "#1c1917",
    handleFrac: 0.2,
  }),
  bladed("dagger", "Dagger", "pierce", 1.55, 0.85, {
    length: 38,
    thickness: 9,
    mass: 0.75,
    handleFrac: 0.28,
  }),
  headed("hammer", "Hammer", "blunt", 2.0, 1.0, {
    length: 50,
    thickness: 10,
    mass: 2.4,
    headW: 22,
    headH: 28,
    shaftColor: HANDLE,
    headColor: "#a1a1aa",
  }),
  headed("axe", "Axe", "slash", 2.0, 1.05, {
    length: 56,
    thickness: 10,
    mass: 2.2,
    headW: 24,
    headH: 30,
    shaftColor: HANDLE,
    headColor: "#cbd5e1",
  }),
  headed("mace", "Mace", "blunt", 2.1, 1.1, {
    length: 58,
    thickness: 10,
    mass: 2.35,
    headW: 20,
    headH: 20,
    shaftColor: HANDLE_DARK,
    headColor: "#a1a1aa",
    headCircle: true,
  }),
  ropeWeapon(
    "whip",
    "Whip",
    "slash",
    1.45,
    1.3,
    [
      { x: 0, y: 0, r: 7, grip: true, color: "#78350f" },
      { x: 0, y: 0, r: 4, color: "#92400e" },
      { x: 0, y: 0, r: 4, color: "#a16207" },
      { x: 0, y: 0, r: 4, color: "#b45309" },
      { x: 0, y: 0, r: 5, color: "#d97706" },
    ],
    [
      [0, 1, "rope"],
      [1, 2, "rope"],
      [2, 3, "rope"],
      [3, 4, "rope"],
    ],
  ),
  ropeWeapon(
    "nunchaku",
    "Nunchaku",
    "blunt",
    1.65,
    1.2,
    [
      { x: 0, y: 0, r: 7, grip: true, color: "#44403c" },
      { x: 0, y: 0, w: 22, h: 9, color: "#78716c" },
      { x: 0, y: 0, r: 4, color: "#a8a29e" },
      { x: 0, y: 0, w: 22, h: 9, color: "#78716c" },
    ],
    [
      [0, 1],
      [1, 2, "rope"],
      [2, 3],
    ],
  ),
  pole("pitchfork", "Pitchfork", "pierce", 1.75, 1.15, {
    length: 80,
    thickness: 9,
    mass: 1.7,
    tipKind: "fork",
    shaftColor: "#a16207",
  }),
  pole("trident", "Trident", "pierce", 1.9, 1.15, {
    length: 84,
    thickness: 10,
    mass: 1.85,
    tipKind: "fork",
    shaftColor: "#78716c",
    tipColor: "#e2e8f0",
  }),
  pole("bo-staff", "Bo Staff", "blunt", 1.55, 0.95, {
    length: 100,
    thickness: 10,
    mass: 1.75,
    tipKind: "cap",
    shaftColor: "#a16207",
    tipColor: "#854d0e",
  }),
  headed("golf-club", "Golf Club", "blunt", 1.7, 1.0, {
    length: 76,
    thickness: 8,
    mass: 1.4,
    headW: 20,
    headH: 12,
    shaftColor: "#d4d4d8",
    headColor: "#71717a",
  }),
  headed("pipe", "Pipe", "blunt", 1.6, 0.9, {
    length: 56,
    thickness: 12,
    mass: 1.8,
    headW: 14,
    headH: 14,
    shaftColor: "#71717a",
    headColor: "#52525b",
    headCircle: true,
  }),
  chunky("brick", "Brick", "blunt", 1.5, 0.7, {
    length: 28,
    thickness: 16,
    mass: 2.0,
    bodyColor: "#b91c1c",
    kind: "brick",
  }),
  chunky("bottle", "Bottle", "slash", 1.4, 1.4, {
    length: 32,
    thickness: 14,
    mass: 0.9,
    bodyColor: "#34d399",
    accentColor: "#6ee7b7",
    kind: "bottle",
  }),
  chunky("chainsaw", "Toy Chainsaw", "slash", 2.15, 1.2, {
    length: 68,
    thickness: 18,
    mass: 2.7,
    bodyColor: "#a1a1aa",
    accentColor: "#f97316",
    kind: "chainsaw",
  }),
  chunky("stun-baton", "Stun Baton", "shock", 1.8, 0.95, {
    length: 52,
    thickness: 11,
    mass: 1.25,
    bodyColor: "#334155",
    accentColor: HANDLE_DARK,
    kind: "baton",
  }),
  pole("cattle-prod", "Cattle Prod", "shock", 1.85, 1.05, {
    length: 66,
    thickness: 9,
    mass: 1.35,
    tipKind: "point",
    shaftColor: "#84cc16",
    tipColor: "#a3e635",
  }),
  chunky("fire-extinguisher", "Fire Extinguisher", "blunt", 1.9, 1.0, {
    length: 36,
    thickness: 26,
    mass: 3.0,
    bodyColor: "#dc2626",
    kind: "extinguisher",
  }),
  chunky("traffic-cone", "Traffic Cone", "blunt", 1.45, 0.85, {
    length: 34,
    thickness: 24,
    mass: 1.3,
    bodyColor: "#f97316",
    kind: "cone",
  }),
  headed("plunger", "Plunger", "blunt", 1.35, 1.1, {
    length: 54,
    thickness: 10,
    mass: 1.05,
    headW: 22,
    headH: 14,
    shaftColor: "#e7e5e4",
    headColor: "#ef4444",
  }),
  pole("umbrella", "Umbrella", "blunt", 1.5, 1.0, {
    length: 70,
    thickness: 9,
    mass: 1.15,
    tipKind: "cap",
    shaftColor: "#0ea5e9",
    tipColor: "#0369a1",
  }),
  pole("scythe", "Scythe", "slash", 2.2, 1.25, {
    length: 78,
    thickness: 10,
    mass: 2.0,
    tipKind: "blade",
    shaftColor: HANDLE_DARK,
    tipColor: METAL,
  }),
  headed("morning-star", "Morning Star", "pierce", 2.15, 1.2, {
    length: 60,
    thickness: 10,
    mass: 2.5,
    headW: 22,
    headH: 22,
    shaftColor: HANDLE_DARK,
    headColor: "#a1a1aa",
    headCircle: true,
  }),
  bladed("las-saber", "Las Saber", "slash", 2.3, 1.0, {
    length: 74,
    thickness: 9,
    mass: 1.2,
    bladeColor: "#22d3ee",
    handleColor: "#0f172a",
    handleFrac: 0.18,
  }),
  headed("wrench", "Wrench", "blunt", 1.65, 0.9, {
    length: 48,
    thickness: 10,
    mass: 1.7,
    headW: 18,
    headH: 20,
    shaftColor: "#94a3b8",
    headColor: "#64748b",
  }),
  headed("frying-spatula", "Spatula", "blunt", 1.4, 0.85, {
    length: 50,
    thickness: 8,
    mass: 0.95,
    headW: 20,
    headH: 16,
    shaftColor: HANDLE,
    headColor: "#d6d3d1",
  }),
  chunky("banjo", "Banjo", "blunt", 1.55, 1.05, {
    length: 64,
    thickness: 18,
    mass: 1.6,
    bodyColor: "#fde68a",
    accentColor: HANDLE,
    kind: "banjo",
  }),
  solid("shotput", "Shot Put", "blunt", 2.4, 0.6, {
    length: 32,
    thickness: 32,
    mass: 3.6,
    color: "#a1a1aa",
    shape: "circle",
    radius: 16,
    gripLocal: { x: 0, y: 0 },
  }, 0.25),
];

export const WEAPON_CATALOG_IDS: readonly string[] = WEAPON_CATALOG.map((d) => d.id);

/** Пусто: на обычной арене оружие не спавним (lab / test / sandbox задают сами). */
export const DEFAULT_ARENA_WEAPON_IDS: readonly string[] = [];

export const LEGACY_WEAPON_IDS = [
  "frying-pan",
  "spear",
  "chain-flail",
  "torch",
] as const;
