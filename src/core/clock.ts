/** Инжектируемые часы и RNG для headless/сервера. */
export interface BattleClock {
  now(): number;
  random(): number;
}

export function createBattleClock(startMs = 1000): BattleClock {
  let t = startMs;
  return {
    now: () => t,
    random: () => Math.random(),
    advance(ms: number) {
      t += ms;
    },
  } as BattleClock & { advance(ms: number): void };
}

export function createSeededClock(seed: number, startMs = 1000): BattleClock & { advance(ms: number): void } {
  let rng = seed || 1;
  let t = startMs;
  return {
    now: () => t,
    random: () => {
      rng = (rng * 1664525 + 1013904223) >>> 0;
      return rng / 0x1_0000_0000;
    },
    advance(ms: number) {
      t += ms;
    },
  };
}
