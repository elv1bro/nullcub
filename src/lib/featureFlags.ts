/**
 * Feature flags для legacy / незавершённых режимов.
 * P2P (Trystero) и 4FFA (useRosterHealth) выключены по умолчанию —
 * основной онлайн-путь: WS dedicated.
 */
export const ENABLE_P2P =
  import.meta.env.VITE_ENABLE_P2P === "1" ||
  import.meta.env.VITE_ENABLE_P2P === "true";

export const ENABLE_LOCAL_FFA =
  import.meta.env.VITE_ENABLE_LOCAL_FFA === "1" ||
  import.meta.env.VITE_ENABLE_LOCAL_FFA === "true";
