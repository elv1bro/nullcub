/** `?lab=1` — лаборатория ударов. */
export function isStrikeLabMode(): boolean {
  if (typeof window === "undefined") return false;
  const params = new URLSearchParams(window.location.search);
  return params.has("lab");
}

export function ensureLabParam() {
  const url = new URL(window.location.href);
  if (!url.searchParams.has("lab")) {
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
  url.searchParams.delete("lab");
  window.history.replaceState({}, "", url);
}
