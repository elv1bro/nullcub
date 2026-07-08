/** `?debug` в URL — оверлей скоростей и урона. */
export function isDebugMode(): boolean {
  if (typeof window === "undefined") return false;
  return new URLSearchParams(window.location.search).has("debug");
}
