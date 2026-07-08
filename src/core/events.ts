export type BattleEventMap = {
  hit: {
    victimCompositeId: number;
    aggressorCompositeId: number;
    damage: number;
    x: number;
    y: number;
    damageTypeId?: string;
  };
  knockout: {
    victimCompositeId: number;
    winnerCompositeId: number;
  };
  disarm: {
    fighterCompositeId: number;
    itemCompositeId: number;
  };
  battleEnd: {
    winner: string | null;
  };
};

type Handler<T> = (payload: T) => void;

export class BattleEventBus {
  private listeners = new Map<keyof BattleEventMap, Set<Handler<unknown>>>();

  on<K extends keyof BattleEventMap>(
    event: K,
    handler: Handler<BattleEventMap[K]>,
  ): () => void {
    let set = this.listeners.get(event);
    if (!set) {
      set = new Set();
      this.listeners.set(event, set);
    }
    set.add(handler as Handler<unknown>);
    return () => set!.delete(handler as Handler<unknown>);
  }

  emit<K extends keyof BattleEventMap>(event: K, payload: BattleEventMap[K]): void {
    const set = this.listeners.get(event);
    if (!set) return;
    for (const h of set) {
      (h as Handler<BattleEventMap[K]>)(payload);
    }
  }

  clear(): void {
    this.listeners.clear();
  }
}
