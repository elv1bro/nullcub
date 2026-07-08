import type { FighterColors } from "@/lib/fighterColors";
import type { AvatarFacePreset } from "./avatarPresets";
import { darken, lighten, mixHex, parseHex } from "./color";

function colorfulness(hex: string): number {
  const [r, g, b] = parseHex(hex);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  if (max === 0) return 0;
  return (max - min) / max;
}

function luminance(hex: string): number {
  const [r, g, b] = parseHex(hex);
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

/** Подбирает main/secondary тела рэгдолла в тон палитре лица (для ботов и NPC). */
export function bodyColorsFromAvatar(preset: AvatarFacePreset): FighterColors {
  switch (preset.kind) {
    case "robot":
      return ensureDarkerBodyPair(
        preset.accent,
        mixHex(preset.primary, preset.shade, 0.55),
      );
    case "ninja":
      return ensureDarkerBodyPair(
        mixHex(preset.primary, preset.accent2, 0.35),
        preset.shade,
      );
    case "ghost":
    case "skull":
      return ensureDarkerBodyPair(
        lighten(preset.primary, 0.12),
        mixHex(preset.shade, preset.primary, 0.35),
      );
    case "oni":
      return ensureDarkerBodyPair(
        preset.primary,
        mixHex(preset.shade, preset.accent, 0.35),
      );
    case "slime":
    case "frog":
      return ensureDarkerBodyPair(
        preset.primary,
        mixHex(preset.accent, preset.shade, 0.45),
      );
    case "alien":
      return ensureDarkerBodyPair(preset.primary, preset.accent2);
    default:
      break;
  }

  const candidates = [
    preset.accent,
    preset.eyes,
    preset.accent2,
    lighten(preset.primary, 0.08),
  ];

  let main = preset.accent;
  let best = -1;
  for (const c of candidates) {
    const sat = colorfulness(c);
    const lum = luminance(c);
    const score =
      sat * 2.2 +
      (lum > 0.22 && lum < 0.88 ? 0.6 : 0) -
      (lum < 0.15 ? 0.8 : 0);
    if (score > best) {
      best = score;
      main = c;
    }
  }

  if (luminance(main) < 0.2) main = lighten(main, 0.28);
  if (colorfulness(main) < 0.12) {
    main = mixHex(main, preset.accent2, 0.45);
  }

  let secondary = mixHex(main, preset.shade, 0.58);
  if (luminance(secondary) >= luminance(main) * 0.92) {
    secondary = darken(main, 0.32);
  }

  return ensureDarkerBodyPair(main, secondary);
}

function ensureDarkerBodyPair(
  main: string,
  secondary: string,
): FighterColors {
  if (luminance(secondary) >= luminance(main) - 0.02) {
    return { main, secondary: darken(main, 0.32) };
  }
  return { main, secondary };
}
