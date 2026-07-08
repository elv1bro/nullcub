/**
 * Версионированное хранение в localStorage.
 *
 * Формат на диске: `{ v: number, data: T }`. Записи без обёртки считаются
 * легаси (fromVersion = 0) и прогоняются через migrate — так старые сейвы
 * не теряются при смене схемы.
 */

interface VersionedEnvelope {
  v: number;
  data: unknown;
}

function isEnvelope(value: unknown): value is VersionedEnvelope {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    typeof (value as VersionedEnvelope).v === "number" &&
    "data" in value
  );
}

export function loadVersioned<T>(opts: {
  key: string;
  version: number;
  /**
   * Приводит сырые данные (легаси или прошлая версия) к текущей схеме.
   * Вернуть null — данные невосстановимы, использовать fallback.
   */
  migrate: (data: unknown, fromVersion: number) => T | null;
  fallback: () => T;
}): T {
  try {
    const raw = localStorage.getItem(opts.key);
    if (!raw) return opts.fallback();
    const parsed: unknown = JSON.parse(raw);
    const [data, fromVersion] = isEnvelope(parsed)
      ? [parsed.data, parsed.v]
      : [parsed, 0];
    return opts.migrate(data, fromVersion) ?? opts.fallback();
  } catch {
    return opts.fallback();
  }
}

export function saveVersioned<T>(key: string, version: number, data: T): void {
  try {
    localStorage.setItem(key, JSON.stringify({ v: version, data }));
  } catch {
    // localStorage может быть недоступен (private mode / quota) — молча пропускаем.
  }
}
