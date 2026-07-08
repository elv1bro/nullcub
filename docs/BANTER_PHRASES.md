# Banter phrase pools

Each language has **500 safe + 500 spicy** lines (`250` victim + `250` aggressor per tier).

## Logic

| Setting | Behavior |
|---------|----------|
| Banter on | ~30% chance per qualifying hit, 900ms cooldown |
| 18+ off | Safe pool only |
| 18+ on | 70% spicy / 30% safe per line |
| MK announcer | Probabilistic on heavy/combo; always on KO |

## Adding phrases

Edit seed arrays in:

- `src/i18n/banter/seeds/ru.ts`
- `src/i18n/banter/seeds/en.ts`

`buildPool.ts` expands seeds with meme templates to 250 per side.

Meme / punchline seeds go in `*MemeSeeds` arrays — keep references short and recognizable
(«я думал это сова», skill issue, «это база», bonk, «this is fine», etc.).

After editing seeds, run `npm test` — `banterPools.test.ts` checks pool sizes.
