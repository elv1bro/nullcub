import { GameContext } from "@/GameContext";
import { e2eFail, e2eMatches, e2eOk, e2eSetPhase } from "@/dev/e2eHarness";
import { Viewport } from "@/components/Viewport";
import { Renderer } from "@/components/Renderer";
import { setBattleConfig } from "@/lib/battleConfig";
import { playMenuSound } from "@/audio";
import { BlockPalette } from "@/components/workshop/BlockPalette";
import { WorkshopParamsPanel } from "@/components/workshop/WorkshopParamsPanel";
import { WorkshopSelectedPart } from "@/components/workshop/WorkshopSelectedPart";
import {
  defaultBlueprintName,
  emptyBlueprint,
  snapshotBlueprintFromComposite,
  validateBlueprint,
} from "@/workshop/blueprintAdapters";
import {
  deleteBlueprint,
  listBlueprints,
  saveBlueprint,
} from "@/workshop/blueprintStore";
import type { BlueprintDef, BlueprintMeta, WorkshopKind } from "@/workshop/blueprintTypes";
import { DEFAULT_BLUEPRINT_META } from "@/workshop/blueprintTypes";
import { buildBlueprintPhysics } from "@/workshop/buildBlueprint";
import { paletteForKind, type BlockTemplate } from "@/workshop/blockCatalog";
import { createBlockMeta, type BlockMeta } from "@/workshop/blockMeta";
import { usePaletteDrag } from "@/workshop/usePaletteDrag";
import { ensureStarterMonsters } from "@/monster/monsterStore";
import {
  type MonsterLinkType,
  defaultLinkType,
  rebuildCompositeLinks,
} from "@/monster/linkTypes";
import { useMonsterLinkPhysics } from "@/lib/useMonsterLinkPhysics";
import { BATTLE_GRAVITY } from "@/lib/battleTuning";
import { BLUEPRINT_GRID, drawBlueprint, snapToGrid } from "@/workshop/blueprintGrid";
import {
  applyBlueprintPartRender,
  freezeWorkshopBody,
  syncWorkshopComposite,
  unfreezeWorkshopBody,
} from "@/workshop/workshopPartRender";
import { drawWorkshopLink, drawWorkshopLinks } from "@/workshop/drawWorkshopLinks";
import {
  bodyIndexAt,
  canvasToWorld,
  linkIndexAt,
} from "@/workshop/workshopHitTest";
import { useSettings } from "@/settings/SettingsContext";
import {
  Composite,
  SurroundingWalls,
  useEngine,
  useRender,
  useRenderEvent,
} from "@1.framework/matter4react";
import Matter, { Body, Composite as MatterComposite, type Vector } from "matter-js";
import { useCallback, useContext, useEffect, useRef, useState } from "react";
import { useKeyPressEvent } from "react-use";
import { worldToCanvas } from "@/render/worldToCanvas";

const SIZE = 900;
const BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: SIZE, y: SIZE },
]);
const CENTER = { x: SIZE / 2, y: SIZE / 2 };

type LinkRecord = {
  a: number;
  b: number;
  type: MonsterLinkType;
};

type DragRef = {
  x: number;
  y: number;
  fromBody: number | null;
  linkMode: boolean;
};

type LeftTab = "params" | "library";

function WorkshopScene() {
  const { t } = useSettings();
  const { sendN } = useContext(GameContext);
  const render = useRender();
  const engine = useEngine();

  const [composite, setComposite] = useState<MatterComposite>();
  const [protagonists, setProtagonists] = useState<Body[]>([]);
  const [physicsPreview, setPhysicsPreview] = useState(false);
  const [workshopKind, setWorkshopKind] = useState<WorkshopKind>("monster");
  const [linkType, setLinkType] = useState<MonsterLinkType>("rigid");
  const [name, setName] = useState(() => defaultBlueprintName("monster"));
  const [blueprintMeta, setBlueprintMeta] = useState<BlueprintMeta>(
    () => ({ ...DEFAULT_BLUEPRINT_META.monster }),
  );
  const [saved, setSaved] = useState<BlueprintDef[]>(() => {
    ensureStarterMonsters();
    return listBlueprints();
  });
  const [leftTab, setLeftTab] = useState<LeftTab>("params");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [selectedPartIndex, setSelectedPartIndex] = useState<number | null>(null);
  const [status, setStatus] = useState("");
  const [linkPreview, setLinkPreview] = useState<{
    from: number;
    x: number;
    y: number;
  } | null>(null);

  const partsMetaRef = useRef<BlockMeta[]>([]);
  const linksRef = useRef<LinkRecord[]>([]);
  const blueprintIdRef = useRef<string>(crypto.randomUUID());
  const initializedRef = useRef(false);
  const dragRef = useRef<DragRef | null>(null);
  const selectedPartRef = useRef<number | null>(null);
  const deleteFabRef = useRef<HTMLButtonElement>(null);
  const layoutSnapshotRef = useRef<BlueprintDef | null>(null);
  const scaleAnchorRef = useRef<Body>(
    Matter.Bodies.circle(CENTER.x, CENTER.y, 2, {
      isStatic: true,
      render: { visible: false },
      collisionFilter: { group: -1, mask: 0 },
    }),
  );

  selectedPartRef.current = selectedPartIndex;

  const syncProtagonists = useCallback((bodies: Body[]) => {
    setProtagonists([scaleAnchorRef.current, ...bodies]);
  }, []);

  useEffect(() => {
    syncProtagonists([]);
  }, [syncProtagonists]);

  useMonsterLinkPhysics(composite, physicsPreview);

  useEffect(() => {
    if (!engine) return;
    if (physicsPreview) {
      engine.gravity.x = BATTLE_GRAVITY.x;
      engine.gravity.y = BATTLE_GRAVITY.y;
      engine.gravity.scale = BATTLE_GRAVITY.scale;
    } else {
      engine.gravity.x = 0;
      engine.gravity.y = 0;
      engine.gravity.scale = 0;
    }
  }, [engine, physicsPreview]);

  const showConstraints = useCallback((comp: MatterComposite) => {
    for (const c of comp.constraints) {
      c.render.visible = false;
    }
  }, []);

  const rebuildFromDef = useCallback(
    (raw: BlueprintDef) => {
      const def: BlueprintDef = {
        ...raw,
        kind: raw.kind ?? workshopKind,
        meta: { ...DEFAULT_BLUEPRINT_META[raw.kind ?? workshopKind], ...raw.meta },
      };
      const built = buildBlueprintPhysics(def, CENTER.x, CENTER.y);
      if (!built) return;

      partsMetaRef.current = def.parts.map((p) => createBlockMeta(p.blockKind));
      linksRef.current = def.links.map((l) => ({
        a: l.a,
        b: l.b,
        type: defaultLinkType(l.type),
      }));
      showConstraints(built.composite);
      for (const body of built.composite.bodies) {
        Body.setPosition(body, snapToGrid(body.position));
      }
      rebuildCompositeLinks(built.composite, linksRef.current);
      syncWorkshopComposite(built.composite, partsMetaRef.current);
      setPhysicsPreview(false);
      layoutSnapshotRef.current = null;

      blueprintIdRef.current = def.id;
      setWorkshopKind(def.kind);
      setName(def.name);
      setBlueprintMeta(def.meta ?? { ...DEFAULT_BLUEPRINT_META[def.kind] });
      setComposite(built.composite);
      syncProtagonists([...built.composite.bodies]);
      setLinkPreview(null);
      setSelectedPartIndex(null);
    },
    [showConstraints, syncProtagonists, workshopKind],
  );

  const clearCanvas = useCallback(() => {
    const def = emptyBlueprint(workshopKind);
    blueprintIdRef.current = def.id;
    setName(def.name);
    setBlueprintMeta(def.meta ?? { ...DEFAULT_BLUEPRINT_META[workshopKind] });
    rebuildFromDef(def);
    setStatus(t.workshop.cleared);
  }, [rebuildFromDef, t.workshop.cleared, workshopKind]);

  const switchKind = useCallback(
    (kind: WorkshopKind) => {
      if (kind === workshopKind) return;
      setWorkshopKind(kind);
      const def = emptyBlueprint(kind);
      blueprintIdRef.current = def.id;
      setName(def.name);
      setBlueprintMeta(def.meta ?? { ...DEFAULT_BLUEPRINT_META[kind] });
      rebuildFromDef(def);
      setStatus(t.workshop.kindSwitched);
    },
    [rebuildFromDef, t.workshop.kindSwitched, workshopKind],
  );

  useEffect(() => {
    if (initializedRef.current) return;
    initializedRef.current = true;
    ensureStarterMonsters();
    setSaved(listBlueprints());
    const def = emptyBlueprint("monster");
    def.parts = [
      { x: 0, y: -40, radius: 20, blockKind: "head" },
      { x: 0, y: 20, radius: 12, blockKind: "core" },
    ];
    def.links = [{ a: 0, b: 1, type: "rigid" }];
    blueprintIdRef.current = def.id;
    setName(def.name);
    rebuildFromDef(def);
  }, [rebuildFromDef]);

  useEffect(() => {
    if (!e2eMatches("workshop")) return;
    if (!composite?.bodies.length) return;
    e2eSetPhase("running");
    const t = setTimeout(() => {
      const root = document.querySelector(".workshop-root");
      if (!root) {
        e2eFail("workshop root missing");
        return;
      }
      e2eOk({
        parts: composite.bodies.length,
        kind: workshopKind,
      });
    }, 1200);
    return () => clearTimeout(t);
  }, [composite, workshopKind]);

  const pointFromEvent = useCallback(
    (clientX: number, clientY: number): Vector | null => {
      if (!render?.canvas) return null;
      return canvasToWorld(render.canvas, render.bounds, clientX, clientY);
    },
    [render],
  );

  const addPartAt = useCallback(
    (point: Vector, template: BlockTemplate) => {
      if (!composite || physicsPreview) return;
      const snapped = snapToGrid(point);
      if (
        template.blockKind === "head" &&
        partsMetaRef.current.some((p) => p.isHead)
      ) {
        setStatus(t.workshop.oneHead);
        return;
      }

      const meta = createBlockMeta(template.blockKind);
      const group =
        composite.bodies[0]?.collisionFilter.group ?? Body.nextGroup(true);
      const body = Matter.Bodies.circle(snapped.x, snapped.y, template.radius, {
        label: meta.isHead ? "Head" : "Chest",
        collisionFilter: { group },
        render: { fillStyle: "#bae6fd", strokeStyle: "#f0f9ff" },
        restitution: 0,
        isStatic: true,
      });
      applyBlueprintPartRender(body, meta);
      freezeWorkshopBody(body);

      Matter.Composite.add(composite, body);
      partsMetaRef.current.push(meta);
      setComposite({ ...composite });
      syncProtagonists([...composite.bodies]);
      if (workshopKind === "monster") {
        setBlueprintMeta((m) => ({
          ...m,
          maxHp: Math.max(40, composite.bodies.length * 40),
        }));
      }
      setStatus(t.workshop.partAdded);
    },
    [composite, physicsPreview, t.workshop.oneHead, t.workshop.partAdded, workshopKind],
  );

  const { ghost, startDrag } = usePaletteDrag({
    canvas: render?.canvas,
    render,
    disabled: physicsPreview,
    onDrop: (world, template) => addPartAt(world, template),
  });

  const linkParts = useCallback(
    (a: number, b: number, type: MonsterLinkType) => {
      if (!composite || a === b || physicsPreview) return;
      const bodyA = composite.bodies[a];
      const bodyB = composite.bodies[b];
      if (!(bodyA && bodyB)) return;

      const exists = linksRef.current.some(
        (l) => (l.a === a && l.b === b) || (l.a === b && l.b === a),
      );
      if (exists) return;

      linksRef.current.push({ a, b, type });
      rebuildCompositeLinks(composite, linksRef.current);
      setComposite({ ...composite });
      setStatus(t.workshop.linked);
    },
    [composite, physicsPreview, t.workshop.linked],
  );

  const deleteLinkAt = useCallback(
    (index: number) => {
      if (!composite || physicsPreview) return;
      linksRef.current.splice(index, 1);
      rebuildCompositeLinks(composite, linksRef.current);
      setComposite({ ...composite });
      setStatus(t.workshop.linkRemoved);
    },
    [composite, physicsPreview, t.workshop.linkRemoved],
  );

  const deletePartAt = useCallback(
    (index: number) => {
      if (!composite || physicsPreview) return;
      const body = composite.bodies[index];
      if (!body) return;

      linksRef.current = linksRef.current
        .filter((l) => l.a !== index && l.b !== index)
        .map((l) => ({
          ...l,
          a: l.a > index ? l.a - 1 : l.a,
          b: l.b > index ? l.b - 1 : l.b,
        }));

      Matter.Composite.remove(composite, body);
      partsMetaRef.current.splice(index, 1);
      rebuildCompositeLinks(composite, linksRef.current);
      setComposite({ ...composite });
      syncProtagonists([...composite.bodies]);
      setLinkPreview(null);
      setSelectedPartIndex((prev) => {
        if (prev === null) return null;
        if (prev === index) return null;
        return prev > index ? prev - 1 : prev;
      });
      // maxHp — параметр только монстра; у оружия/арены мету не трогаем.
      if (workshopKind === "monster") {
        setBlueprintMeta((m) => ({
          ...m,
          maxHp: Math.max(40, composite.bodies.length * 40),
        }));
      }
      setStatus(t.workshop.deleted);
    },
    [composite, physicsPreview, workshopKind, t.workshop.deleted],
  );

  const togglePhysicsPreview = useCallback(() => {
    if (!composite || composite.bodies.length === 0) return;

    if (physicsPreview) {
      const snap = layoutSnapshotRef.current;
      if (snap) rebuildFromDef(snap);
      setPhysicsPreview(false);
      setStatus(t.workshop.physicsOff);
      playMenuSound("click");
      return;
    }

    layoutSnapshotRef.current = snapshotBlueprintFromComposite(
      composite,
      partsMetaRef.current,
      linksRef.current.map(({ a, b, type }) => ({ a, b, type })),
      workshopKind,
      name.trim() || defaultBlueprintName(workshopKind),
      blueprintIdRef.current,
      blueprintMeta,
    );
    rebuildCompositeLinks(composite, linksRef.current);
    for (const body of composite.bodies) {
      unfreezeWorkshopBody(body);
      Body.setVelocity(body, { x: 0, y: 0 });
      Body.setAngularVelocity(body, 0);
    }
    setPhysicsPreview(true);
    setStatus(t.workshop.physicsOn);
    playMenuSound("panel");
  }, [
    composite,
    physicsPreview,
    rebuildFromDef,
    name,
    blueprintMeta,
    workshopKind,
    t.workshop.physicsOff,
    t.workshop.physicsOn,
  ]);

  const selectPartAt = useCallback((index: number) => {
    setSelectedPartIndex(index);
    setStatus(t.workshop.partSelected);
  }, [t.workshop.partSelected]);

  const setPartRole = useCallback(
    (index: number, role: "hurtbox" | "armor") => {
      const meta = partsMetaRef.current[index];
      if (!meta || meta.isHead) return;
      meta.role = role;
      meta.blockKind = role === "armor" ? "armor" : "core";
      const body = composite?.bodies[index];
      if (body) applyBlueprintPartRender(body, meta);
      setComposite((c) => (c ? { ...c } : c));
      setStatus(
        role === "armor" ? t.workshop.partRoleArmor : t.workshop.partRoleHurtbox,
      );
    },
    [composite, t.workshop.partRoleArmor, t.workshop.partRoleHurtbox],
  );

  useEffect(() => {
    const canvas = render?.canvas;
    if (!canvas || !composite) return;

    const onContextMenu = (e: MouseEvent) => {
      e.preventDefault();
      if (physicsPreview) return;
      const point = pointFromEvent(e.clientX, e.clientY);
      if (!point) return;
      const index = bodyIndexAt(composite, point);
      if (index !== null) selectPartAt(index);
      else setSelectedPartIndex(null);
    };

    const onDown = (e: MouseEvent) => {
      if (e.button !== 0 || physicsPreview) return;
      const point = pointFromEvent(e.clientX, e.clientY);
      if (!point) return;

      const hitIndex = bodyIndexAt(composite, point);
      if (hitIndex !== null) {
        // Shift+LMB = режим связи; обычный ЛКМ = перемещение (раньше связь
        // создавалась всегда, а move работал только после ПКМ-select).
        const linkMode = e.shiftKey;
        dragRef.current = {
          x: e.clientX,
          y: e.clientY,
          fromBody: hitIndex,
          linkMode,
        };
        if (linkMode) {
          setLinkPreview({ from: hitIndex, x: point.x, y: point.y });
        } else {
          setSelectedPartIndex(hitIndex);
          setLinkPreview(null);
        }
      } else {
        dragRef.current = {
          x: e.clientX,
          y: e.clientY,
          fromBody: null,
          linkMode: false,
        };
      }
    };

    const onMove = (e: MouseEvent) => {
      const drag = dragRef.current;
      if (!drag || drag.fromBody === null) return;
      const point = pointFromEvent(e.clientX, e.clientY);
      if (!point) return;

      if (drag.linkMode) {
        const targetIndex = bodyIndexAt(composite, point);
        const targetBody =
          targetIndex !== null && targetIndex !== drag.fromBody
            ? composite.bodies[targetIndex]
            : null;
        const end = targetBody?.position ?? point;
        setLinkPreview({ from: drag.fromBody, x: end.x, y: end.y });
        return;
      }

      const body = composite.bodies[drag.fromBody];
      if (body) {
        Body.setPosition(body, snapToGrid(point));
        Body.setVelocity(body, { x: 0, y: 0 });
        rebuildCompositeLinks(composite, linksRef.current);
      }
    };

    const onUp = (e: MouseEvent) => {
      if (e.button !== 0 || physicsPreview) return;
      const drag = dragRef.current;
      dragRef.current = null;
      setLinkPreview(null);
      if (!drag) return;

      const point = pointFromEvent(e.clientX, e.clientY);
      if (!point) return;

      const dx = e.clientX - drag.x;
      const dy = e.clientY - drag.y;
      const moved = dx * dx + dy * dy > 36;
      const endBody = bodyIndexAt(composite, point);

      if (
        drag.linkMode &&
        drag.fromBody !== null &&
        endBody !== null &&
        drag.fromBody !== endBody
      ) {
        linkParts(drag.fromBody, endBody, linkType);
        return;
      }

      if (!moved && !drag.linkMode && endBody === null) {
        const linkIdx = linkIndexAt(composite, linksRef.current, point);
        if (linkIdx !== null) deleteLinkAt(linkIdx);
      }
    };

    canvas.addEventListener("contextmenu", onContextMenu);
    canvas.addEventListener("mousedown", onDown);
    canvas.addEventListener("mousemove", onMove);
    canvas.addEventListener("mouseup", onUp);
    return () => {
      canvas.removeEventListener("contextmenu", onContextMenu);
      canvas.removeEventListener("mousedown", onDown);
      canvas.removeEventListener("mousemove", onMove);
      canvas.removeEventListener("mouseup", onUp);
    };
  }, [
    render?.canvas,
    composite,
    pointFromEvent,
    deletePartAt,
    selectPartAt,
    physicsPreview,
    linkParts,
    deleteLinkAt,
    linkType,
  ]);

  useRenderEvent(
    "afterRender",
    () => {
      if (!render?.context || !render.canvas) return;
      const ctx = render.context;

      // Selection highlight + links drawn ON TOP of bodies (source-over)
      if (selectedPartIndex !== null && composite) {
        const body = composite.bodies[selectedPartIndex];
        if (body) {
          const p = worldToCanvas(render, body.position);
          const r = (body.circleRadius ?? 12) * p.scale + 8;
          ctx.save();
          ctx.strokeStyle = "#fcd34d";
          ctx.lineWidth = 2.5;
          ctx.setLineDash([6, 4]);
          ctx.beginPath();
          ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
          ctx.stroke();
          ctx.setLineDash([]);
          ctx.strokeStyle = "rgba(252, 211, 77, 0.35)";
          ctx.lineWidth = 6;
          ctx.stroke();
          ctx.restore();

          const fab = deleteFabRef.current;
          if (fab) {
            const rect = render.canvas.getBoundingClientRect();
            fab.style.display = "flex";
            fab.style.left = `${rect.left + p.x + r + 4}px`;
            fab.style.top = `${rect.top + p.y - 16}px`;
          }
        }
      } else {
        const fab = deleteFabRef.current;
        if (fab) fab.style.display = "none";
      }

      if (composite) {
        drawWorkshopLinks(ctx, render, composite, linksRef.current);
      }

      if (linkPreview && composite) {
        const fromBody = composite.bodies[linkPreview.from];
        if (fromBody) {
          drawWorkshopLink(
            ctx,
            render,
            fromBody.position.x,
            fromBody.position.y,
            linkPreview.x,
            linkPreview.y,
            linkType,
            3.5,
          );
          const targetIdx = composite.bodies.findIndex(
            (b) =>
              b.id !== fromBody.id &&
              Math.hypot(b.position.x - linkPreview.x, b.position.y - linkPreview.y) <
                (b.circleRadius ?? 12) + 4,
          );
          if (targetIdx >= 0) {
            const target = composite.bodies[targetIdx]!;
            ctx.save();
            ctx.strokeStyle = "rgba(252, 211, 77, 0.85)";
            ctx.lineWidth = 2;
            ctx.beginPath();
            const p = worldToCanvas(render, target.position);
            ctx.arc(p.x, p.y, (target.circleRadius ?? 12) * p.scale + 4, 0, Math.PI * 2);
            ctx.stroke();
            ctx.restore();
          }
        }
      }

      // Blueprint grid + silhouette BEHIND bodies via destination-over.
      // Grid is drawn first (closer to front), background gradient last (furthest back).
      ctx.save();
      ctx.globalCompositeOperation = "destination-over";
      drawBlueprint(ctx, render, CENTER);
      ctx.restore();
    },
    [render, composite, linkPreview, linkType, selectedPartIndex],
  );

  const handleSave = useCallback((): boolean => {
    if (!composite) return false;
    const draft = snapshotBlueprintFromComposite(
      composite,
      partsMetaRef.current,
      linksRef.current.map(({ a, b, type }) => ({ a, b, type })),
      workshopKind,
      name.trim() || defaultBlueprintName(workshopKind),
      blueprintIdRef.current,
      blueprintMeta,
    );
    const check = validateBlueprint(draft);
    if (!check.ok) {
      const key = check.reason as keyof typeof t.workshop;
      const msg = t.workshop[key];
      setStatus(typeof msg === "string" ? msg : t.workshop.needParts);
      return false;
    }

    saveBlueprint({ ...draft, createdAt: Date.now() });
    setSaved(listBlueprints());
    setSelectedId(draft.id);
    setStatus(t.workshop.saved);
    playMenuSound("panel");
    return true;
  }, [composite, name, blueprintMeta, workshopKind, t.workshop]);

  const handleLoad = useCallback(
    (id: string) => {
      const def = saved.find((m) => m.id === id);
      if (!def) return;
      rebuildFromDef(def);
      setSelectedId(id);
      setStatus(t.workshop.loaded);
    },
    [saved, rebuildFromDef, t.workshop.loaded],
  );

  const handleDeleteSaved = useCallback(
    (id: string) => {
      if (!window.confirm(t.workshop.confirmDelete)) return;
      deleteBlueprint(id);
      setSaved(listBlueprints());
      if (selectedId === id) setSelectedId(null);
      setStatus(t.workshop.removed);
    },
    [selectedId, t.workshop.confirmDelete, t.workshop.removed],
  );

  const startFight = useCallback(() => {
    if (workshopKind !== "monster") {
      setStatus(t.workshop.fightMonsterOnly);
      return;
    }
    if (!composite || composite.bodies.length === 0) {
      setStatus(t.workshop.needParts);
      return;
    }
    if (!handleSave()) return;
    setBattleConfig({ kind: "monster", monsterId: blueprintIdRef.current });
    playMenuSound("play");
    sendN("START_BATTLE")();
  }, [composite, handleSave, sendN, t.workshop, workshopKind]);

  useKeyPressEvent("Escape", () => {
    if (selectedPartIndex !== null) {
      setSelectedPartIndex(null);
      playMenuSound("click");
      return;
    }
    playMenuSound("click");
    sendN("BACK")();
  });

  useKeyPressEvent("Delete", () => {
    if (selectedPartIndex === null) return;
    deletePartAt(selectedPartIndex);
    playMenuSound("click");
  });

  useKeyPressEvent("Backspace", () => {
    if (selectedPartIndex === null) return;
    deletePartAt(selectedPartIndex);
    playMenuSound("click");
  });

  const kindBadge = (kind: WorkshopKind) => {
    if (kind === "monster") return t.workshop.kindMonster;
    if (kind === "item") return t.workshop.kindItem;
    return t.workshop.kindArena;
  };

  const partCount = composite?.bodies.length ?? 0;

  return (
    <>
      <header className="workshop-topbar pointer-events-auto">
        <button
          type="button"
          className="workshop-topbar__back"
          onClick={sendN("BACK")}
          aria-label={t.menu.back}
        >
          ←
        </button>
        <div className="workshop-topbar__title">
          <span className="workshop-topbar__eyebrow">
            {t.workshop.studioTitle} · {kindBadge(workshopKind)}
          </span>
          <span className="workshop-topbar__name">{name || defaultBlueprintName(workshopKind)}</span>
        </div>
        <div className="workshop-topbar__meta">
          <span className="workshop-badge">{partCount} pts</span>
          <span className="workshop-badge workshop-badge--grid">
            {BLUEPRINT_GRID}px
          </span>
        </div>
      </header>

      <aside className="workshop-rail workshop-rail--left pointer-events-auto">
        <WorkshopParamsPanel
          t={t.workshop}
          workshopKind={workshopKind}
          onKindChange={switchKind}
          name={name}
          onNameChange={setName}
          namePlaceholder={defaultBlueprintName(workshopKind)}
          meta={blueprintMeta}
          onMetaChange={(patch) =>
            setBlueprintMeta((m) => ({ ...m, ...patch }))
          }
          linkType={linkType}
          onLinkTypeChange={setLinkType}
          physicsPreview={physicsPreview}
          disabled={physicsPreview}
        />

        {selectedPartIndex !== null &&
          partsMetaRef.current[selectedPartIndex] && (
            <WorkshopSelectedPart
              t={t.workshop}
              meta={partsMetaRef.current[selectedPartIndex]}
              workshopKind={workshopKind}
              radius={composite?.bodies[selectedPartIndex]?.circleRadius}
              onRoleChange={(role) => setPartRole(selectedPartIndex, role)}
            />
          )}

        {leftTab === "library" && (
          <div className="ws-library-popup">
            <div className="ws-library-popup__head">
              <span>{t.workshop.library}</span>
              <button type="button" className="ws-library-popup__close" onClick={() => setLeftTab("params")}>×</button>
            </div>
            {saved.length === 0 && (
              <p className="ws-empty">{t.workshop.libraryEmpty}</p>
            )}
            <ul className="ws-library ws-library--popup">
              {[...saved]
                .sort((a, b) => b.createdAt - a.createdAt)
                .map((m) => (
                <li key={m.id} className="ws-library__row">
                  <button
                    type="button"
                    className={[
                      "ws-library__item",
                      selectedId === m.id ? "ws-library__item--active" : "",
                    ].join(" ")}
                    onClick={() => { handleLoad(m.id); setLeftTab("params"); }}
                  >
                    <span className="ws-library__name">{m.name}</span>
                    <span className="ws-library__meta">
                      <span className="ws-library__kind">{kindBadge(m.kind)}</span>
                      · {m.parts.length}
                      {m.kind === "monster" && m.meta?.maxHp && (
                        <span className="ws-library__hearts"> · ♥{m.meta.maxHp}</span>
                      )}
                    </span>
                  </button>
                  <button
                    type="button"
                    className="ws-library__delete"
                    onClick={() => handleDeleteSaved(m.id)}
                    aria-label={t.workshop.remove}
                  >
                    ×
                  </button>
                </li>
              ))}
            </ul>
          </div>
        )}

        <div className="ws-action-bar">
          <button type="button" className="ws-action-btn" onClick={() => setLeftTab(leftTab === "library" ? "params" : "library")} title={t.workshop.library}>
            📂
          </button>
          <button
            type="button"
            className={["ws-action-btn", physicsPreview ? "ws-action-btn--active" : ""].join(" ")}
            onClick={togglePhysicsPreview}
            title={physicsPreview ? t.workshop.physicsStop : t.workshop.testMode}
          >
            {physicsPreview ? "■" : "▶"}
          </button>
          {workshopKind === "monster" && (
            <button type="button" className="ws-action-btn ws-action-btn--fight" onClick={startFight} disabled={physicsPreview} title={t.workshop.fight}>
              ⚔
            </button>
          )}
          <button type="button" className="ws-action-btn" onClick={handleSave} disabled={physicsPreview} title={t.workshop.save}>
            💾
          </button>
          <button type="button" className="ws-action-btn ws-action-btn--ghost" onClick={clearCanvas} disabled={physicsPreview} title={t.workshop.clear}>
            🗑
          </button>
        </div>
      </aside>

      <aside className="workshop-rail workshop-rail--right pointer-events-auto">
        <BlockPalette
          templates={paletteForKind(workshopKind)}
          disabled={physicsPreview}
          dragging={Boolean(ghost)}
          t={t.workshop}
          onDragStart={startDrag}
        />
      </aside>

      {ghost && (
        <>
          <div className="ws-canvas-drop-hint pointer-events-none" aria-hidden>
            {t.workshop.canvasDropHint}
          </div>
          <div
            className="ws-drag-ghost pointer-events-none"
            style={{ left: ghost.x, top: ghost.y }}
          >
            <span
              className="ws-drag-ghost__orb"
              style={{
                width: ghost.template.radius * 2,
                height: ghost.template.radius * 2,
                borderColor: ghost.template.accent,
              }}
            />
          </div>
        </>
      )}

      <footer className="workshop-statusbar pointer-events-none">
        <span className="workshop-statusbar__meta">
          {BLUEPRINT_GRID}px · {t.workshop.partsCount(partCount)}
        </span>
        {status && (
          <span className="workshop-statusbar__msg">{status}</span>
        )}
      </footer>

      <Viewport protagonists={protagonists} />
      <SurroundingWalls
        thick={SIZE}
        bounds={BOUNDS}
        options={{
          isStatic: true,
          render: {
            fillStyle: "transparent",
            strokeStyle: "rgba(224, 242, 254, 0.12)",
            lineWidth: 1,
          },
        }}
      />
      {composite && <Composite.add object={composite} />}

      <button
        ref={deleteFabRef}
        type="button"
        className="workshop-delete-fab pointer-events-auto"
        style={{ display: "none" }}
        aria-label={t.workshop.deletePart}
        title={t.workshop.deletePart}
        onClick={() => {
          if (selectedPartIndex === null) return;
          deletePartAt(selectedPartIndex);
          playMenuSound("click");
        }}
      >
        <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden>
          <path
            fill="currentColor"
            d="M9 3h6l1 2h4v2H4V5h4l1-2zm1 6h2v9h-2V9zm4 0h2v9h-2V9zM7 9h2v9H7V9z"
          />
        </svg>
      </button>
    </>
  );
}

export default function Workshop() {
  return (
    <section className="workshop-root h-100% overflow-hidden relative">
      <Renderer
        engine={{
          gravity: { x: 0, y: 0, scale: 0 },
          constraintIterations: 20,
        }}
        render={{ options: { background: "transparent", wireframes: false } }}
      >
        <WorkshopScene />
      </Renderer>
    </section>
  );
}

export { Workshop };
