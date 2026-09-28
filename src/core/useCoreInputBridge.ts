import {
  useMovementVectorRef,
  type ExternalMoveRef,
} from "@/input/movementKeys";
import type { ControlBindings } from "@/settings/SettingsContext";
import { useEventBeforeUpdate } from "@1.framework/matter4react";
import type { RefObject } from "react";
import { useRef } from "react";
import type { NetInputPayload } from "@/net/protocol";
import { emptyInput, netInputFromFlags } from "./abilityTick";

export interface CoreAbilityFlagsRef {
  current: {
    dash: boolean;
    flip: boolean;
    freeze: boolean;
    reset: boolean;
    dropWeapon: boolean;
    abilitySlot: boolean;
  };
}

/** Один слот ввода → fighterId (локальный / remote). */
export interface CoreInputSlot {
  fighterId: string;
  controls: ControlBindings;
  grabL: RefObject<boolean>;
  grabR: RefObject<boolean>;
  abilityFlags?: CoreAbilityFlagsRef;
  gamepadIndex?: number | null;
  externalMoveRef?: ExternalMoveRef;
  /** Если задан — слот берёт remote, а не локальные клавиши. */
  remoteInput?: RefObject<NetInputPayload | null>;
}

export interface UseCoreInputBridgeOpts {
  enabled: boolean;
  setPlayerInput: (input: NetInputPayload) => void;
  setOpponentInput?: (input: NetInputPayload) => void;
  playerControls: ControlBindings;
  opponentControls?: ControlBindings;
  playerGrabL: RefObject<boolean>;
  playerGrabR: RefObject<boolean>;
  opponentGrabL?: RefObject<boolean>;
  opponentGrabR?: RefObject<boolean>;
  playerAbilityFlags?: CoreAbilityFlagsRef;
  opponentAbilityFlags?: CoreAbilityFlagsRef;
  remoteOpponentInput?: RefObject<NetInputPayload | null>;
  includeOpponentLocal?: boolean;
  /** Виртуальный стик игрока (телефон). */
  playerExternalMoveRef?: ExternalMoveRef;
  playerGamepadIndex?: number | null;
  /**
   * Мультислотовый режим: карта слот → session.setInput(fighterId).
   * Если задан вместе с setInput — перекрывает пару player/opponent.
   */
  slots?: CoreInputSlot[];
  setInput?: (fighterId: string, input: NetInputPayload) => void;
}

/** После стольки мс без пакета remote — обнуляем move (анти-coast). */
const REMOTE_INPUT_STALE_MS = 220;

function consumeAbilityFlags(
  flags: CoreAbilityFlagsRef["current"] | undefined,
): {
  dash: boolean;
  flip: boolean;
  freeze: boolean;
  reset: boolean;
  dropWeapon: boolean;
  abilitySlot: boolean;
} {
  if (!flags) {
    return {
      dash: false,
      flip: false,
      freeze: false,
      reset: false,
      dropWeapon: false,
      abilitySlot: false,
    };
  }
  const snapshot = {
    dash: flags.dash,
    flip: flags.flip,
    freeze: flags.freeze,
    reset: flags.reset,
    dropWeapon: flags.dropWeapon,
    abilitySlot: flags.abilitySlot,
  };
  // One-shot: иначе level-triggered abilityTick спамит по кулдауну.
  flags.dash = false;
  flags.flip = false;
  flags.freeze = false;
  flags.reset = false;
  flags.dropWeapon = false;
  flags.abilitySlot = false;
  return snapshot;
}

export function useCoreInputBridge(opts: UseCoreInputBridgeOpts): void {
  const playerSeq = useRef(0);
  const opponentSeq = useRef(0);
  const slotSeq = useRef<Record<string, number>>({});

  const readPlayerMove = useMovementVectorRef(opts.playerControls, {
    includeArrows: false,
    // null по умолчанию: иначе дрифт стика на pad[0] тянет влево с первого кадра.
    gamepadIndex: opts.playerGamepadIndex ?? null,
    externalMoveRef: opts.playerExternalMoveRef,
  });
  const readOpponentMove = useMovementVectorRef(
    opts.opponentControls ?? opts.playerControls,
    {
      includeArrows: false,
      gamepadIndex: opts.includeOpponentLocal ? 1 : null,
    },
  );

  const slot0 = opts.slots?.[0];
  const slot1 = opts.slots?.[1];
  const slot2 = opts.slots?.[2];
  const slot3 = opts.slots?.[3];

  const readSlot0 = useMovementVectorRef(
    slot0?.controls ?? opts.playerControls,
    {
      includeArrows: false,
      gamepadIndex: slot0?.gamepadIndex ?? null,
      externalMoveRef: slot0?.externalMoveRef,
    },
  );
  const readSlot1 = useMovementVectorRef(
    slot1?.controls ?? opts.playerControls,
    {
      includeArrows: false,
      gamepadIndex: slot1?.gamepadIndex ?? null,
      externalMoveRef: slot1?.externalMoveRef,
    },
  );
  const readSlot2 = useMovementVectorRef(
    slot2?.controls ?? opts.playerControls,
    {
      includeArrows: false,
      gamepadIndex: slot2?.gamepadIndex ?? null,
      externalMoveRef: slot2?.externalMoveRef,
    },
  );
  const readSlot3 = useMovementVectorRef(
    slot3?.controls ?? opts.playerControls,
    {
      includeArrows: false,
      gamepadIndex: slot3?.gamepadIndex ?? null,
      externalMoveRef: slot3?.externalMoveRef,
    },
  );

  const slotReaders = [readSlot0, readSlot1, readSlot2, readSlot3];

  useEventBeforeUpdate(() => {
    if (!opts.enabled) return;

    const now = performance.now();

    if (opts.slots?.length && opts.setInput) {
      for (let i = 0; i < opts.slots.length; i++) {
        const slot = opts.slots[i]!;
        const remote = slot.remoteInput?.current;
        if (slot.remoteInput) {
          if (!remote || now - remote.t > REMOTE_INPUT_STALE_MS) {
            opts.setInput(slot.fighterId, emptyInput());
          } else {
            opts.setInput(slot.fighterId, remote);
          }
          continue;
        }
        const seq = (slotSeq.current[slot.fighterId] ?? 0) + 1;
        slotSeq.current[slot.fighterId] = seq;
        const flags = consumeAbilityFlags(slot.abilityFlags?.current);
        const readMove = slotReaders[i] ?? readPlayerMove;
        opts.setInput(
          slot.fighterId,
          netInputFromFlags(
            readMove(),
            slot.grabL.current ?? false,
            slot.grabR.current ?? false,
            flags,
            seq,
            now,
          ),
        );
      }
      return;
    }

    const playerFlags = consumeAbilityFlags(opts.playerAbilityFlags?.current);
    opts.setPlayerInput(
      netInputFromFlags(
        readPlayerMove(),
        opts.playerGrabL.current ?? false,
        opts.playerGrabR.current ?? false,
        playerFlags,
        playerSeq.current++,
        now,
      ),
    );

    if (opts.remoteOpponentInput) {
      const remote = opts.remoteOpponentInput.current;
      if (!remote || now - remote.t > REMOTE_INPUT_STALE_MS) {
        opts.setOpponentInput?.(emptyInput());
      } else {
        opts.setOpponentInput?.(remote);
      }
      return;
    }

    if (!opts.includeOpponentLocal || !opts.setOpponentInput) return;

    const opponentFlags = consumeAbilityFlags(opts.opponentAbilityFlags?.current);
    opts.setOpponentInput(
      netInputFromFlags(
        readOpponentMove(),
        Boolean(opts.opponentGrabL?.current),
        Boolean(opts.opponentGrabR?.current),
        opponentFlags,
        opponentSeq.current++,
        now,
      ),
    );
  }, [
    opts.enabled,
    opts.setPlayerInput,
    opts.setOpponentInput,
    opts.setInput,
    opts.slots,
    opts.playerGrabL,
    opts.playerGrabR,
    opts.opponentGrabL,
    opts.opponentGrabR,
    opts.playerAbilityFlags,
    opts.opponentAbilityFlags,
    opts.remoteOpponentInput,
    opts.includeOpponentLocal,
    readPlayerMove,
    readOpponentMove,
    readSlot0,
    readSlot1,
    readSlot2,
    readSlot3,
  ]);
}
