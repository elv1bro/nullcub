/** `?lab=1` / `?lab=strike` — старая лаборатория ударов (не путать с каталогом Тесты). */

function labParam(): string | null {
  if (typeof window === "undefined") return null;
  return new URLSearchParams(window.location.search).get("lab");
}

export function isStrikeLabMode(): boolean {
  const v = labParam();
  return v === "1" || v === "strike";
}

export function ensureLabParam() {
  const url = new URL(window.location.href);
  if (!isStrikeLabMode()) {
    url.searchParams.set("lab", "1");
    window.history.replaceState({}, "", url);
  }
}

export function openStrikeLab(enterLab: () => void) {
  ensureLabParam();
  enterLab();
}

export function closeStrikeLab() {
  const url = new URL(window.location.href);
  const v = url.searchParams.get("lab");
  if (v === "1" || v === "strike") {
    url.searchParams.delete("lab");
    window.history.replaceState({}, "", url);
  }
}
