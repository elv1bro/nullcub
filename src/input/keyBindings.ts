import { useEffect, useRef, type MutableRefObject } from "react";

const LEGACY_LETTER: Record<string, string> = {
  w: "KeyW",
  a: "KeyA",
  s: "KeyS",
  d: "KeyD",
};

const CODE_LABELS: Record<string, string> = {
  ArrowUp: "↑",
  ArrowDown: "↓",
  ArrowLeft: "←",
  ArrowRight: "→",
  Space: "Space",
};

/** Приводит сохранённую клавишу к KeyboardEvent.code. */
export function migrateBinding(stored: string): string {
  if (
    stored.startsWith("Key") ||
    stored.startsWith("Digit") ||
    stored.startsWith("Arrow") ||
    stored === "Space"
  ) {
    return stored;
  }
  const lower = stored.toLowerCase();
  const legacy = LEGACY_LETTER[lower];
  if (legacy) return legacy;
  if (/^[0-9]$/.test(stored)) return `Digit${stored}`;
  if (lower === " ") return "Space";
  return stored;
}

export function keyEventMatches(binding: string, e: KeyboardEvent): boolean {
  const code = migrateBinding(binding);
  if (e.code === code) return true;
  if (binding.length === 1 && e.key.toLowerCase() === binding.toLowerCase()) {
    return true;
  }
  return false;
}

export function formatBindingLabel(binding: string): string {
  const code = migrateBinding(binding);
  if (CODE_LABELS[code]) return CODE_LABELS[code];
  if (code.startsWith("Key") && code.length === 4) return code.slice(3);
  if (code.startsWith("Digit") && code.length === 6) return code.slice(5);
  return code;
}

export function bindingFromKeyboardEvent(e: KeyboardEvent): string {
  return e.code;
}

export function useBindingPressRef(binding: string): MutableRefObject<boolean> {
  const ref = useRef(false);
  const bindingRef = useRef(binding);
  bindingRef.current = binding;

  useEffect(() => {
    const onDown = (e: KeyboardEvent) => {
      if (keyEventMatches(bindingRef.current, e)) ref.current = true;
    };
    const onUp = (e: KeyboardEvent) => {
      if (keyEventMatches(bindingRef.current, e)) ref.current = false;
    };
    window.addEventListener("keydown", onDown);
    window.addEventListener("keyup", onUp);
    return () => {
      window.removeEventListener("keydown", onDown);
      window.removeEventListener("keyup", onUp);
      ref.current = false;
    };
  }, [binding]);

  return ref;
}
