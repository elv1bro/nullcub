import { useMemo, useState } from "react";
import { useTranslation } from "@/settings/SettingsContext";
import {
  ABILITY_DEFS,
  buildDraftPool,
  claimCard,
  releaseCard,
  type DraftCardId,
  type DraftInventory,
  type FighterLoadout,
  type BaseAbilityId,
  emptyLoadout,
  isAbilityId,
  isPassiveItemId,
  BASE_ABILITY_IDS,
} from "@/loadout";

export interface DraftScreenProps {
  playerCount: number;
  localPlayerIds: string[];
  onConfirm: (loadouts: Record<string, FighterLoadout>) => void;
  onBack: () => void;
}

function playerIdsForDraft(
  playerCount: number,
  localPlayerIds: string[],
): string[] {
  const ids: string[] = [];
  for (let i = 0; i < playerCount; i++) {
    ids.push(localPlayerIds[i] ?? `player-${i}`);
  }
  return ids;
}

function emptyInventory(ids: string[]): DraftInventory {
  const inv: DraftInventory = {};
  for (const id of ids) inv[id] = [];
  return inv;
}

/** Собирает лодаут из базы + карт инвентаря (способности → слоты, предметы → слоты). */
function inventoryToLoadout(
  base: BaseAbilityId,
  cards: DraftCardId[],
): FighterLoadout {
  const loadout = emptyLoadout(base);
  let ai = 0;
  let ii = 0;
  for (const card of cards) {
    if (isAbilityId(card) && ai < 2) {
      loadout.abilities[ai] = card;
      ai += 1;
    } else if (isPassiveItemId(card) && ii < 2) {
      loadout.items[ii] = card;
      ii += 1;
    }
  }
  return loadout;
}

function cardLabel(
  card: DraftCardId,
  t: ReturnType<typeof useTranslation>,
): string {
  if (isPassiveItemId(card)) return t.loadout.item[card];
  return t.loadout.ability[card];
}

/**
 * Заглушка экрана драфта: N+1 карт в центре, панели игроков по бокам.
 * Локальный игрок 0 кликает карты; «Отдать» возвращает в пул.
 */
export function DraftScreen({
  playerCount,
  localPlayerIds,
  onConfirm,
  onBack,
}: DraftScreenProps) {
  const t = useTranslation();
  const playerIds = useMemo(
    () => playerIdsForDraft(playerCount, localPlayerIds),
    [playerCount, localPlayerIds],
  );
  const localId = localPlayerIds[0] ?? playerIds[0]!;

  const [pool, setPool] = useState<DraftCardId[]>(() =>
    buildDraftPool(playerCount),
  );
  const [inventory, setInventory] = useState<DraftInventory>(() =>
    emptyInventory(playerIds),
  );
  const [bases, setBases] = useState<Record<string, BaseAbilityId>>(() => {
    const init: Record<string, BaseAbilityId> = {};
    for (const id of playerIds) init[id] = "dash";
    return init;
  });

  const claimForLocal = (cardId: DraftCardId) => {
    const result = claimCard(pool, inventory, localId, cardId);
    if (!result.ok) return;
    setPool(result.pool);
    setInventory(result.inventoryByPlayer);
  };

  const releaseForPlayer = (playerId: string, cardId: DraftCardId) => {
    // Отдавать может только локальный игрок свои карты (заглушка).
    if (playerId !== localId) return;
    const result = releaseCard(pool, inventory, playerId, cardId);
    if (!result.ok) return;
    setPool(result.pool);
    setInventory(result.inventoryByPlayer);
  };

  const handleConfirm = () => {
    const loadouts: Record<string, FighterLoadout> = {};
    for (const id of playerIds) {
      loadouts[id] = inventoryToLoadout(
        bases[id] ?? "dash",
        inventory[id] ?? [],
      );
    }
    onConfirm(loadouts);
  };

  return (
    <div className="draft-screen">
      <header className="draft-screen__header">
        <button type="button" className="draft-screen__back" onClick={onBack}>
          {t.common.back}
        </button>
        <h2 className="draft-screen__title font-display">{t.loadout.draftTitle}</h2>
        <button
          type="button"
          className="draft-screen__confirm"
          onClick={handleConfirm}
        >
          {t.loadout.confirm}
        </button>
      </header>

      <div className="draft-screen__body">
        <aside className="draft-screen__sides">
          {playerIds.map((id, index) => (
            <PlayerDraftPanel
              key={id}
              playerId={id}
              label={t.loadout.playerLabel.replace("{n}", String(index + 1))}
              base={bases[id] ?? "dash"}
              onBaseChange={(base) =>
                setBases((prev) => ({ ...prev, [id]: base }))
              }
              cards={inventory[id] ?? []}
              canRelease={id === localId}
              onRelease={(card) => releaseForPlayer(id, card)}
              t={t}
            />
          ))}
        </aside>

        <div className="draft-screen__pool">
          <p className="draft-screen__pool-hint font-ui">{t.loadout.poolHint}</p>
          <div className="draft-screen__cards">
            {pool.map((card) => (
              <button
                key={card}
                type="button"
                className="draft-card"
                onClick={() => claimForLocal(card)}
              >
                <span className="draft-card__kind">
                  {isPassiveItemId(card)
                    ? t.loadout.kindItem
                    : ABILITY_DEFS[card].kind}
                </span>
                <span className="draft-card__name font-display">
                  {cardLabel(card, t)}
                </span>
                <span className="draft-card__desc font-ui">
                  {isPassiveItemId(card)
                    ? t.loadout.itemDesc[card]
                    : t.loadout.abilityDesc[card]}
                </span>
              </button>
            ))}
            {pool.length === 0 && (
              <p className="draft-screen__empty font-ui">{t.loadout.poolEmpty}</p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function PlayerDraftPanel({
  playerId,
  label,
  base,
  onBaseChange,
  cards,
  canRelease,
  onRelease,
  t,
}: {
  playerId: string;
  label: string;
  base: BaseAbilityId;
  onBaseChange: (base: BaseAbilityId) => void;
  cards: DraftCardId[];
  canRelease: boolean;
  onRelease: (card: DraftCardId) => void;
  t: ReturnType<typeof useTranslation>;
}) {
  return (
    <section className="draft-panel" data-player={playerId}>
      <h3 className="draft-panel__title font-display">{label}</h3>
      <label className="draft-panel__base font-ui">
        <span>{t.loadout.baseLabel}</span>
        <select
          value={base}
          onChange={(e) => onBaseChange(e.target.value as BaseAbilityId)}
          disabled={!canRelease}
        >
          {BASE_ABILITY_IDS.map((id) => (
            <option key={id} value={id}>
              {t.loadout.ability[id]}
            </option>
          ))}
        </select>
      </label>
      <ul className="draft-panel__cards">
        {cards.map((card) => (
          <li key={`${playerId}-${card}`} className="draft-panel__card">
            <span>{cardLabel(card, t)}</span>
            {canRelease && (
              <button
                type="button"
                className="draft-panel__release"
                onClick={() => onRelease(card)}
              >
                {t.loadout.release}
              </button>
            )}
          </li>
        ))}
        {cards.length === 0 && (
          <li className="draft-panel__empty font-ui">{t.loadout.noCards}</li>
        )}
      </ul>
    </section>
  );
}
