import { useMovementVectorRef } from "@/input/movementKeys";
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
  };
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
}

/** После стольки мс без пакета remote — обнуляем move (анти-coast). */
const REMOTE_INPUT_STALE_MS = 220;

function consumeAbilityFlags(
  flags: CoreAbilityFlagsRef["current"] | undefined,
): { dash: boolean; flip: boolean; freeze: boolean; reset: boolean } {
  if (!flags) {
    return { dash: false, flip: false, freeze: false, reset: false };
  }
  const snapshot = {
    dash: flags.dash,
    flip: flags.flip,
    freeze: flags.freeze,
    reset: flags.reset,
  };
  // One-shot: иначе level-triggered abilityTick спамит по кулдауну.
  flags.dash = false;
  flags.flip = false;
  flags.freeze = false;
  flags.reset = false;
  return snapshot;
}

export function useCoreInputBridge(opts: UseCoreInputBridgeOpts): void {
  const playerSeq = useRef(0);
  const opponentSeq = useRef(0);
  const readPlayerMove = useMovementVectorRef(opts.playerControls);
  const readOpponentMove = useMovementVectorRef(
    opts.opponentControls ?? opts.playerControls,
    { includeArrows: false },
  );

  useEventBeforeUpdate(() => {
    if (!opts.enabled) return;

    const now = performance.now();
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
        opts.opponentGrabL?.current ?? false,
        opts.opponentGrabR?.current ?? false,
        opponentFlags,
        opponentSeq.current++,
        now,
      ),
    );
  }, [
    opts.enabled,
    opts.setPlayerInput,
    opts.setOpponentInput,
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
  ]);
}
