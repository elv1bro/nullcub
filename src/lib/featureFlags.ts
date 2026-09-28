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

/**
 * Онлайн-дуэль требует запущенный WS-сервер, которого нет ни в упакованной
 * игре, ни на статике, ни в обычном `yarn dev`. Пункт меню показываем только
 * когда адрес сервера задан явно — иначе кнопка ведёт в никуда.
 * Deep-link по коду дуэли работает независимо от флага.
 */
export const ENABLE_ONLINE_DUEL =
  typeof import.meta.env.VITE_WS_URL === "string" &&
  import.meta.env.VITE_WS_URL.length > 0;
