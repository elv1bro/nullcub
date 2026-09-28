import { useEffect, useState } from "react";

function readPortrait(): boolean {
  if (typeof window === "undefined") return false;
  return window.innerHeight > window.innerWidth;
}

function readCoarsePointer(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }
  return window.matchMedia("(pointer: coarse)").matches;
}

/** Portrait / coarse-pointer — для подсказки «переверни» и виртуального стика. */
export function useViewportFlags(): { portrait: boolean; coarse: boolean } {
  const [portrait, setPortrait] = useState(readPortrait);
  const [coarse, setCoarse] = useState(readCoarsePointer);

  useEffect(() => {
    const onResize = () => setPortrait(readPortrait());
    window.addEventListener("resize", onResize);
    window.addEventListener("orientationchange", onResize);

    const mq =
      typeof window.matchMedia === "function"
        ? window.matchMedia("(pointer: coarse)")
        : null;
    const onPointer = () => setCoarse(readCoarsePointer());
    mq?.addEventListener?.("change", onPointer);

    onResize();
    onPointer();
    return () => {
      window.removeEventListener("resize", onResize);
      window.removeEventListener("orientationchange", onResize);
      mq?.removeEventListener?.("change", onPointer);
    };
  }, []);

  return { portrait, coarse };
}
