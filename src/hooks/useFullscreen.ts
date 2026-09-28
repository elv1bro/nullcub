import { useCallback, useEffect, useState } from "react";

type FsDoc = Document & {
  webkitFullscreenElement?: Element | null;
  webkitExitFullscreen?: () => Promise<void> | void;
  webkitFullscreenEnabled?: boolean;
};

type FsEl = HTMLElement & {
  webkitRequestFullscreen?: () => Promise<void> | void;
};

function fullscreenElement(): Element | null {
  const doc = document as FsDoc;
  return document.fullscreenElement ?? doc.webkitFullscreenElement ?? null;
}

export function canUseFullscreen(): boolean {
  if (typeof document === "undefined") return false;
  const doc = document as FsDoc;
  const el = document.documentElement as FsEl;
  return Boolean(
    document.fullscreenEnabled ||
      doc.webkitFullscreenEnabled ||
      el.requestFullscreen ||
      el.webkitRequestFullscreen,
  );
}

async function requestFs(el: HTMLElement): Promise<void> {
  const target = el as FsEl;
  if (target.requestFullscreen) {
    await target.requestFullscreen();
    return;
  }
  if (target.webkitRequestFullscreen) {
    await target.webkitRequestFullscreen();
  }
}

async function exitFs(): Promise<void> {
  const doc = document as FsDoc;
  if (document.exitFullscreen) {
    await document.exitFullscreen();
    return;
  }
  if (doc.webkitExitFullscreen) {
    await doc.webkitExitFullscreen();
  }
}

async function tryLockLandscape(): Promise<void> {
  try {
    const orientation = screen.orientation as ScreenOrientation & {
      lock?: (type: string) => Promise<void>;
    };
    await orientation.lock?.("landscape");
  } catch {
    /* iOS / без разрешения — ок */
  }
}

/** Браузерный Fullscreen API (+ webkit). На iPhone часто недоступен. */
export function useFullscreen(target?: HTMLElement | null): {
  supported: boolean;
  active: boolean;
  enter: () => void;
  toggle: () => void;
} {
  const [supported] = useState(canUseFullscreen);
  const [active, setActive] = useState(
    () => (typeof document !== "undefined" ? Boolean(fullscreenElement()) : false),
  );

  useEffect(() => {
    if (!supported) return;
    const sync = () => setActive(Boolean(fullscreenElement()));
    document.addEventListener("fullscreenchange", sync);
    document.addEventListener("webkitfullscreenchange", sync);
    sync();
    return () => {
      document.removeEventListener("fullscreenchange", sync);
      document.removeEventListener("webkitfullscreenchange", sync);
    };
  }, [supported]);

  const enter = useCallback(() => {
    if (!supported) return;
    if (fullscreenElement()) {
      void tryLockLandscape();
      return;
    }
    const root = target ?? document.documentElement;
    void requestFs(root)
      .then(() => tryLockLandscape())
      .catch(() => undefined);
  }, [supported, target]);

  const toggle = useCallback(() => {
    if (!supported) return;
    if (fullscreenElement()) {
      void exitFs().catch(() => undefined);
    } else {
      enter();
    }
  }, [supported, enter]);

  return { supported, active, enter, toggle };
}
