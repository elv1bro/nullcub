/**
 * Node/tsx не видит named exports у `matter-js` (только default).
 * Vite/Vitest их подставляет сам; этот shim нужен для `yarn server` и headless-кода.
 */
import Matter from "matter-js/build/matter.js";

export default Matter;

export const Axes = Matter.Axes;
export const Bodies = Matter.Bodies;
export const Body = Matter.Body;
export const Bounds = Matter.Bounds;
export const Common = Matter.Common;
export const Composite = Matter.Composite;
export const Composites = Matter.Composites;
export const Constraint = Matter.Constraint;
export const Contact = Matter.Contact;
export const Detector = Matter.Detector;
export const Engine = Matter.Engine;
export const Events = Matter.Events;
export const Grid = Matter.Grid;
export const Mouse = Matter.Mouse;
export const Pair = Matter.Pair;
export const Pairs = Matter.Pairs;
export const Plugin = Matter.Plugin;
export const Query = Matter.Query;
export const Render = Matter.Render;
export const Runner = Matter.Runner;
export const Sleeping = Matter.Sleeping;
export const Svg = Matter.Svg;
export const Vector = Matter.Vector;
export const Vertices = Matter.Vertices;
export const World = Matter.World;

// Bounds/Composite/Engine выше уже экспортированы как значения (классы);
// повторный type-реэкспорт этих имён конфликтует (TS2323).
export type {
  Body as MatterBody,
  Constraint as MatterConstraint,
  IBodyDefinition,
  IChamferableBodyDefinition,
  IEngineDefinition,
  IEventCollision,
  IEventTimestamped,
  IRunnerOptions,
  Render as MatterRender,
  Vector as MatterVector,
  World as MatterWorld,
} from "matter-js";
