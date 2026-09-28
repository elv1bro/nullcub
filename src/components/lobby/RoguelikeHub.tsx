import { playMenuSound } from "@/audio";
import { LootTooltip } from "@/components/lobby/LootTooltip";
import {
  ABILITY_DEFS,
  BASE_ABILITY_IDS,
  isAbilityId,
  isPassiveItemId,
  type AbilityId,
  type BaseAbilityId,
  type DraftCardId,
  type FighterLoadout,
  type PassiveItemId,
} from "@/loadout";
import { rarityForCard, type LootRarity } from "@/roguelike/lootRarity";
import type { PortalDirection, RoguelikePortal } from "@/roguelike/map";
import {
  claimHubCard,
  dropCardToHub,
  enterPortal,
  getCurrentPortals,
  getRoguelikeRun,
  giveHubCard,
  setPlayerBase,
  stealCard,
  type RoguelikePlayerSlot,
} from "@/roguelike/runState";
import { useTranslation } from "@/settings/SettingsContext";
import {
  useCallback,
  useMemo,
  useState,
  type MouseEvent as ReactMouseEvent,
} from "react";

export interface RoguelikeHubProps {
  onEnterBattle: () => void;
  onBack: () => void;
  onLeaveRun: () => void;
  localPlayerId?: string;
}

type Tip = { card: DraftCardId; x: number; y: number } | null;

function cardTitle(
  card: DraftCardId,
  t: ReturnType<typeof useTranslation>,
): string {
  if (isPassiveItemId(card)) return t.loadout.item[card];
  return t.loadout.ability[card];
}

function cardDesc(
  card: DraftCardId,
  t: ReturnType<typeof useTranslation>,
): string {
  if (isPassiveItemId(card)) return t.loadout.itemDesc[card];
  return t.loadout.abilityDesc[card];
}

function dirLabel(
  dir: PortalDirection,
  t: ReturnType<typeof useTranslation>,
): string {
  if (dir === "left") return t.roguelike.dirLeft;
  if (dir === "right") return t.roguelike.dirRight;
  return t.roguelike.dirForward;
}

function dirArrow(dir: PortalDirection): string {
  if (dir === "left") return "←";
  if (dir === "right") return "→";
  return "↑";
}

function glyph(card: DraftCardId): string {
  return card.slice(0, 1).toUpperCase();
}

function rarityLabel(
  r: LootRarity,
  t: ReturnType<typeof useTranslation>,
): string {
  return t.roguelike.rarity[r];
}

export function RoguelikeHub({
  onEnterBattle,
  onBack,
  onLeaveRun,
  localPlayerId = "you",
}: RoguelikeHubProps) {
  const t = useTranslation();
  const run = getRoguelikeRun();
  const [, bump] = useState(0);
  const refresh = useCallback(() => bump((n) => n + 1), []);
  const [tip, setTip] = useState<Tip>(null);
  const [entering, setEntering] = useState(false);
  /** Выбранный дроп в центре — кому отдать. */
  const [focusLoot, setFocusLoot] = useState<DraftCardId | null>(null);

  const portals = useMemo(
    () => getCurrentPortals(),
    [run?.floor, run?.hubEpoch],
  );

  if (!run) {
    return (
      <div className="rl-hub">
        <p className="font-ui">{t.roguelike.noRun}</p>
        <button type="button" className="draft-screen__back" onClick={onBack}>
          {t.common.back}
        </button>
      </div>
    );
  }

  if (run.phase === "victory" || run.phase === "defeat") {
    const win = run.phase === "victory";
    return (
      <div className="rl-hub rl-hub--end">
        <h2 className="rl-hub__title font-display">
          {win ? t.roguelike.victory : t.roguelike.defeat}
        </h2>
        <p className="rl-hub__hint font-ui">
          {win ? t.roguelike.victoryHint : t.roguelike.defeatHint}
        </p>
        <button
          type="button"
          className="draft-screen__confirm"
          onClick={() => {
            playMenuSound("panel");
            onLeaveRun();
          }}
        >
          {t.roguelike.backToLobby}
        </button>
      </div>
    );
  }

  const openTip = (card: DraftCardId, e: ReactMouseEvent) => {
    e.stopPropagation();
    playMenuSound("click");
    setTip({ card, x: e.clientX, y: e.clientY });
  };

  const onPortal = (portal: RoguelikePortal) => {
    if (entering || portal.cleared) return;
    playMenuSound("play");
    setEntering(true);
    const ok = enterPortal(portal.id);
    if (!ok) {
      setEntering(false);
      return;
    }
    window.setTimeout(() => onEnterBattle(), 420);
  };

  const humans = run.players.filter((p) => !p.id.startsWith("empty-"));
  const orderedPortals = (["left", "forward", "right"] as const)
    .map((d) => portals.find((p) => p.direction === d))
    .filter((p): p is RoguelikePortal => Boolean(p));

  const byCorner = (c: RoguelikePlayerSlot["corner"]) =>
    run.players.find((p) => p.corner === c)!;

  return (
    <div
      className="rl-hub rl-hub--arena"
      data-epoch={run.hubEpoch}
      data-layout="arena5"
    >
      {entering && (
        <div className="rl-hub__reload font-display" aria-live="polite">
          {t.roguelike.entering}
        </div>
      )}
      {tip && (
        <LootTooltip
          card={tip.card}
          x={tip.x}
          y={tip.y}
          onClose={() => setTip(null)}
        />
      )}

      <header className="rl-hub__header">
        <button
          type="button"
          className="draft-screen__back rl-hub__back"
          onClick={onBack}
          disabled={entering}
        >
          {t.common.back}
        </button>
        <div className="rl-hub__header-mid">
          <h2 className="rl-hub__title font-display">{t.roguelike.title}</h2>
          <p className="rl-hub__wip font-ui" role="status">
            {t.lobby.wipBadge}
          </p>
          <p className="rl-hub__floor font-ui">
            {t.roguelike.floor
              .replace("{n}", String(run.floor))
              .replace("{total}", String(run.floorsTotal))}
            {" · "}
            {t.roguelike.pathHint}
          </p>
        </div>
        <span className="rl-hub__seed font-ui">#{run.map.seed}</span>
      </header>

      {/*
        5 зон:
        tl 20×50 | center 60×100 | tr 20×50
        bl 20×50 | (center spans)  | br 20×50
      */}
      <div className="rl-arena">
        <PlayerPane
          slot={byCorner("tl")}
          loadout={run.loadouts[byCorner("tl").id]}
          localId={localPlayerId}
          humans={humans}
          onTip={openTip}
          onBaseChange={(id, base) => {
            setPlayerBase(id, base);
            refresh();
          }}
          onSteal={(victimId, card) => {
            playMenuSound("panel");
            if (stealCard(localPlayerId, victimId, card)) refresh();
          }}
          onDrop={(playerId, card) => {
            playMenuSound("click");
            if (dropCardToHub(playerId, card)) refresh();
          }}
          t={t}
        />
        <PlayerPane
          slot={byCorner("tr")}
          loadout={run.loadouts[byCorner("tr").id]}
          localId={localPlayerId}
          humans={humans}
          onTip={openTip}
          onBaseChange={(id, base) => {
            setPlayerBase(id, base);
            refresh();
          }}
          onSteal={(victimId, card) => {
            playMenuSound("panel");
            if (stealCard(localPlayerId, victimId, card)) refresh();
          }}
          onDrop={(playerId, card) => {
            playMenuSound("click");
            if (dropCardToHub(playerId, card)) refresh();
          }}
          t={t}
        />
        <PlayerPane
          slot={byCorner("bl")}
          loadout={run.loadouts[byCorner("bl").id]}
          localId={localPlayerId}
          humans={humans}
          onTip={openTip}
          onBaseChange={(id, base) => {
            setPlayerBase(id, base);
            refresh();
          }}
          onSteal={(victimId, card) => {
            playMenuSound("panel");
            if (stealCard(localPlayerId, victimId, card)) refresh();
          }}
          onDrop={(playerId, card) => {
            playMenuSound("click");
            if (dropCardToHub(playerId, card)) refresh();
          }}
          t={t}
        />
        <PlayerPane
          slot={byCorner("br")}
          loadout={run.loadouts[byCorner("br").id]}
          localId={localPlayerId}
          humans={humans}
          onTip={openTip}
          onBaseChange={(id, base) => {
            setPlayerBase(id, base);
            refresh();
          }}
          onSteal={(victimId, card) => {
            playMenuSound("panel");
            if (stealCard(localPlayerId, victimId, card)) refresh();
          }}
          onDrop={(playerId, card) => {
            playMenuSound("click");
            if (dropCardToHub(playerId, card)) refresh();
          }}
          t={t}
        />

        <section className="rl-center" aria-label={t.roguelike.lootTitle}>
          <div className="rl-center__paths">
            {orderedPortals.map((portal) => (
              <button
                key={portal.id}
                type="button"
                className={`rl-path-chip rl-path-chip--${portal.direction} ${portal.cleared ? "is-cleared" : ""}`}
                disabled={portal.cleared || entering}
                onClick={() => onPortal(portal)}
              >
                <span className="rl-path-chip__arrow" aria-hidden>
                  {dirArrow(portal.direction)}
                </span>
                <span className="rl-path-chip__dir font-display">
                  {dirLabel(portal.direction, t)}
                </span>
                <span className="rl-path-chip__meta font-ui">
                  {t.lobby.difficulty[portal.difficulty]} ·{" "}
                  {t.roguelike.bots.replace("{n}", String(portal.botCount))}
                </span>
                <span className="rl-path-chip__cta font-display">
                  {portal.cleared ? t.roguelike.cleared : t.roguelike.goFight}
                </span>
              </button>
            ))}
          </div>

          <div className="rl-center__loot-head">
            <h3 className="rl-center__loot-title font-display">
              {t.roguelike.lootTitle}
            </h3>
            <p className="rl-center__loot-hint font-hand">
              {t.roguelike.lootFreedomHint}
            </p>
          </div>

          <div className="rl-center__drops">
            {run.hubLoot.map((card, idx) => {
              const rarity = rarityForCard(card);
              const focused = focusLoot === card;
              return (
                <article
                  key={`${card}-${idx}`}
                  className={`rl-drop-card rl-drop-card--${rarity} ${focused ? "is-focus" : ""}`}
                >
                  <button
                    type="button"
                    className="rl-drop-card__art"
                    onClick={(e) => openTip(card, e)}
                    aria-label={cardTitle(card, t)}
                  >
                    <span className="rl-drop-card__glyph font-display">
                      {glyph(card)}
                    </span>
                    <span className="rl-drop-card__rarity font-ui">
                      {rarityLabel(rarity, t)}
                    </span>
                  </button>
                  <div className="rl-drop-card__body">
                    <span className="rl-drop-card__kind">
                      {isPassiveItemId(card)
                        ? t.loadout.kindItem
                        : isAbilityId(card)
                          ? ABILITY_DEFS[card].kind
                          : "?"}
                    </span>
                    <h4 className="rl-drop-card__name font-display">
                      {cardTitle(card, t)}
                    </h4>
                    <p className="rl-drop-card__desc font-ui">
                      {cardDesc(card, t)}
                    </p>
                    <div className="rl-drop-card__actions">
                      <button
                        type="button"
                        className="rl-act rl-act--take"
                        onClick={() => {
                          playMenuSound("panel");
                          if (claimHubCard(localPlayerId, card)) {
                            setFocusLoot(null);
                            refresh();
                          }
                        }}
                      >
                        {t.roguelike.takeSelf}
                      </button>
                      <button
                        type="button"
                        className="rl-act rl-act--give"
                        onClick={() => {
                          playMenuSound("click");
                          setFocusLoot(focused ? null : card);
                        }}
                      >
                        {t.roguelike.giveTo}
                      </button>
                    </div>
                    {focused && (
                      <div className="rl-drop-card__give-list">
                        {humans.map((p) => (
                          <button
                            key={p.id}
                            type="button"
                            className="rl-act rl-act--target"
                            disabled={p.id === localPlayerId}
                            onClick={() => {
                              playMenuSound("panel");
                              if (giveHubCard(p.id, card)) {
                                setFocusLoot(null);
                                refresh();
                              }
                            }}
                          >
                            {p.id === localPlayerId
                              ? t.lobby.you
                              : p.name || p.id}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                </article>
              );
            })}
            {run.hubLoot.length === 0 && (
              <p className="rl-center__empty font-ui">{t.roguelike.lootEmpty}</p>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}

function PlayerPane({
  slot,
  loadout,
  localId,
  humans,
  onTip,
  onBaseChange,
  onSteal,
  onDrop,
  t,
}: {
  slot: RoguelikePlayerSlot;
  loadout?: FighterLoadout;
  localId: string;
  humans: RoguelikePlayerSlot[];
  onTip: (card: DraftCardId, e: ReactMouseEvent) => void;
  onBaseChange: (playerId: string, base: BaseAbilityId) => void;
  onSteal: (victimId: string, card: DraftCardId) => void;
  onDrop: (playerId: string, card: DraftCardId) => void;
  t: ReturnType<typeof useTranslation>;
}) {
  const empty = slot.id.startsWith("empty-");
  const isLocal = slot.id === localId;
  const lo = loadout;
  const tone = `rl-pane--${slot.corner}`;

  const cards: DraftCardId[] = [];
  if (lo) {
    for (const a of lo.abilities) if (a) cards.push(a);
    for (const i of lo.items) if (i) cards.push(i);
  }

  return (
    <section
      className={`rl-pane rl-pane--${slot.corner} ${tone} ${empty ? "is-empty" : ""} ${isLocal ? "is-local" : ""}`}
      data-player={slot.id}
      data-corner={slot.corner}
    >
      <header className="rl-pane__head">
        <div className={`rl-pane__face rl-pane__face--${slot.corner}`} aria-hidden />
        <div>
          <h3 className="rl-pane__name font-display">
            {empty
              ? t.roguelike.emptySlot
              : isLocal
                ? `${slot.name || t.lobby.you} ★`
                : slot.name || slot.id}
          </h3>
          {!empty && (
            <p className="rl-pane__tag font-ui">
              {isLocal ? t.roguelike.youTag : t.roguelike.rivalTag}
            </p>
          )}
        </div>
      </header>

      {!empty && lo && (
        <>
          <div className="rl-pane__skills">
            <span className="rl-pane__label font-ui">{t.roguelike.abilitiesTitle}</span>
            <div className="rl-pane__row">
              {isLocal ? (
                <label className="rl-pane__base">
                  <span className="rl-pane__hk">Q</span>
                  <select
                    value={lo.base}
                    onChange={(e) =>
                      onBaseChange(slot.id, e.target.value as BaseAbilityId)
                    }
                  >
                    {BASE_ABILITY_IDS.map((id) => (
                      <option key={id} value={id}>
                        {t.loadout.ability[id]}
                      </option>
                    ))}
                  </select>
                </label>
              ) : (
                <OwnedChip
                  hotkey="Q"
                  card={lo.base}
                  title={cardTitle(lo.base, t)}
                  rarity={rarityForCard(lo.base)}
                  onTip={onTip}
                  canSteal={false}
                />
              )}
              <OwnedChip
                hotkey="W"
                card={lo.abilities[0]}
                title={
                  lo.abilities[0] ? cardTitle(lo.abilities[0], t) : "—"
                }
                rarity={
                  lo.abilities[0] ? rarityForCard(lo.abilities[0]) : "common"
                }
                onTip={onTip}
                canSteal={!isLocal && Boolean(lo.abilities[0])}
                onSteal={() =>
                  lo.abilities[0] && onSteal(slot.id, lo.abilities[0])
                }
                canDrop={isLocal && Boolean(lo.abilities[0])}
                onDrop={() =>
                  lo.abilities[0] && onDrop(slot.id, lo.abilities[0])
                }
                stealLabel={t.roguelike.steal}
                dropLabel={t.roguelike.drop}
              />
              <OwnedChip
                hotkey="E"
                card={lo.abilities[1]}
                title={
                  lo.abilities[1] ? cardTitle(lo.abilities[1], t) : "—"
                }
                rarity={
                  lo.abilities[1] ? rarityForCard(lo.abilities[1]) : "common"
                }
                onTip={onTip}
                canSteal={!isLocal && Boolean(lo.abilities[1])}
                onSteal={() =>
                  lo.abilities[1] && onSteal(slot.id, lo.abilities[1])
                }
                canDrop={isLocal && Boolean(lo.abilities[1])}
                onDrop={() =>
                  lo.abilities[1] && onDrop(slot.id, lo.abilities[1])
                }
                stealLabel={t.roguelike.steal}
                dropLabel={t.roguelike.drop}
              />
            </div>
          </div>

          <div className="rl-pane__items">
            <span className="rl-pane__label font-ui">{t.roguelike.itemsTitle}</span>
            <div className="rl-pane__item-grid">
              {Array.from({ length: 6 }, (_, i) => {
                const card: PassiveItemId | null =
                  i === 0 ? lo.items[0] : i === 1 ? lo.items[1] : null;
                return (
                  <OwnedChip
                    key={i}
                    hotkey={String(i + 1)}
                    card={card}
                    title={card ? cardTitle(card, t) : "—"}
                    rarity={card ? rarityForCard(card) : "common"}
                    compact
                    onTip={onTip}
                    canSteal={!isLocal && Boolean(card)}
                    onSteal={() => card && onSteal(slot.id, card)}
                    canDrop={isLocal && Boolean(card)}
                    onDrop={() => card && onDrop(slot.id, card)}
                    stealLabel={t.roguelike.steal}
                    dropLabel={t.roguelike.drop}
                  />
                );
              })}
            </div>
          </div>

          {cards.length === 0 && (
            <p className="rl-pane__empty font-ui">{t.roguelike.noGear}</p>
          )}
          {!isLocal && humans.length > 1 && (
            <p className="rl-pane__steal-hint font-hand">{t.roguelike.stealHint}</p>
          )}
        </>
      )}
    </section>
  );
}

function OwnedChip({
  hotkey,
  card,
  title,
  rarity,
  compact,
  onTip,
  canSteal,
  onSteal,
  canDrop,
  onDrop,
  stealLabel,
  dropLabel,
}: {
  hotkey: string;
  card: AbilityId | PassiveItemId | BaseAbilityId | null;
  title: string;
  rarity: LootRarity;
  compact?: boolean;
  onTip: (card: DraftCardId, e: ReactMouseEvent) => void;
  canSteal?: boolean;
  onSteal?: () => void;
  canDrop?: boolean;
  onDrop?: () => void;
  stealLabel?: string;
  dropLabel?: string;
}) {
  return (
    <div
      className={`rl-chipx rl-chipx--${rarity} ${compact ? "rl-chipx--compact" : ""} ${card ? "" : "is-empty"}`}
    >
      <span className="rl-chipx__hk font-ui">{hotkey}</span>
      <button
        type="button"
        className="rl-chipx__main"
        disabled={!card}
        onClick={(e) => card && onTip(card, e)}
        title={title}
      >
        <span className="rl-chipx__glyph font-display">
          {card ? glyph(card) : "·"}
        </span>
        {!compact && <span className="rl-chipx__name font-ui">{title}</span>}
      </button>
      {canSteal && onSteal && (
        <button
          type="button"
          className="rl-chipx__steal"
          onClick={onSteal}
          title={stealLabel}
        >
          {stealLabel}
        </button>
      )}
      {canDrop && onDrop && (
        <button
          type="button"
          className="rl-chipx__drop"
          onClick={onDrop}
          title={dropLabel}
        >
          {dropLabel}
        </button>
      )}
    </div>
  );
}
