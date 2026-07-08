// Дополнения к @types/matter-js: поля, которые есть в рантайме,
// но отсутствуют в официальных типах. Файл — модуль (есть top-level import),
// поэтому declare module ниже АУГМЕНТИРУЕТ пакет, а не заменяет его.
import "matter-js";

declare module "matter-js" {
  interface IEventTimestamped<T> {
    /** Matter передаёт delta в событиях update (есть в рантайме с 0.19). */
    delta?: number;
  }

  interface Constraint {
    /** Слот для данных плагинов/собственной меты (есть в рантайме). */
    plugin?: Record<string, unknown>;
  }

  namespace Render {
    function startViewTransform(render: Render): void;
    function endViewTransform(render: Render): void;
    function bodies(
      render: Render,
      bodies: Body[],
      context: CanvasRenderingContext2D,
    ): void;
  }
}
