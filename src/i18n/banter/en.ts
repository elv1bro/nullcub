import { buildBanterTier } from "./buildPool";
import * as seeds from "./seeds/en";

export const enBanterSafe = buildBanterTier(
  seeds.enSafePlayerCore,
  seeds.enSafeOpponentCore,
  [...seeds.enPlayerTemplates, ...seeds.enMemeTemplates("player")],
  [...seeds.enOpponentTemplates, ...seeds.enMemeTemplates("opponent")],
  seeds.enMemeRefs,
);

export const enBanterSpicy = buildBanterTier(
  seeds.enSpicyPlayerCore,
  seeds.enSpicyOpponentCore,
  [...seeds.enPlayerTemplates, ...seeds.enMemeTemplates("player")],
  [...seeds.enOpponentTemplates, ...seeds.enMemeTemplates("opponent")],
  seeds.enMemeRefs,
);
