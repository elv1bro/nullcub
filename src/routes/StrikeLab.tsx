import { Renderer } from "@/components/Renderer";
import { Viewport } from "@/components/Viewport";
import { applyPlayerColors } from "@/lib/paintStickman";
import {
  applyLabStrike,
  previewStrike,
  STRIKE_LIMB_LABELS,
  type StrikeLimbLabel,
} from "@/lib/knockback";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { createStickman } from "@/utils/createStickman";
import { Composite, SurroundingWalls } from "@1.framework/matter4react";
import Matter, { Body, type Composite as MatterComposite } from "matter-js";
import { useCallback, useEffect, useMemo, useState } from "react";

const SIZE = 1000;
const BOUNDS = Matter.Bounds.create([
  { x: 0, y: 0 },
  { x: SIZE, y: SIZE },
]);

function findLimb(composite: MatterComposite, label: StrikeLimbLabel): Body | undefined {
  return composite.bodies.find((b) => b.label === label);
}

function StrikeLabScene() {
  const { profile } = usePlayerProfile();
  const [attacker, setAttacker] = useState<MatterComposite>();
  const [dummy, setDummy] = useState<MatterComposite>();
  const [protagonists, setProtagonists] = useState<Body[]>([]);

  const [attackerLimb, setAttackerLimb] = useState<StrikeLimbLabel>("Upper Right Arm");
  const [targetLimb, setTargetLimb] = useState<StrikeLimbLabel>("Head");
  const [speed, setSpeed] = useState(10);
  const [lastResult, setLastResult] = useState<string>("—");

  useEffect(() => {
    const a = createStickman(SIZE * 0.32, SIZE * 0.5, {
      render: { fillStyle: profile.colors.main },
    });
    applyPlayerColors(a, profile.colors.main, profile.colors.secondary);

    const d = createStickman(SIZE * 0.68, SIZE * 0.5, {
      render: { fillStyle: "#444" },
    });
    applyPlayerColors(d, "#444444", "#888888");

    setAttacker(a);
    setDummy(d);
    setProtagonists([...a.bodies, ...d.bodies]);
  }, [profile.colors.main, profile.colors.secondary]);

  const preview = useMemo(() => {
    if (!attacker || !dummy) return null;
    const aBody = findLimb(attacker, attackerLimb);
    const tBody = findLimb(dummy, targetLimb);
    if (!aBody || !tBody) return null;
    return previewStrike(aBody, tBody, speed);
  }, [attacker, dummy, attackerLimb, targetLimb, speed]);

  const resetPoses = useCallback(() => {
    if (!attacker || !dummy) return;
    for (const body of [...attacker.bodies, ...dummy.bodies]) {
      Matter.Body.setVelocity(body, { x: 0, y: 0 });
      Matter.Body.setAngularVelocity(body, 0);
    }
    Matter.Composite.translate(attacker, {
      x: SIZE * 0.32 - (attacker.bodies[0]?.position.x ?? 0),
      y: SIZE * 0.5 - (attacker.bodies[0]?.position.y ?? 0),
    });
    Matter.Composite.translate(dummy, {
      x: SIZE * 0.68 - (dummy.bodies[0]?.position.x ?? 0),
      y: SIZE * 0.5 - (dummy.bodies[0]?.position.y ?? 0),
    });
  }, [attacker, dummy]);

  const fireStrike = useCallback(() => {
    if (!attacker || !dummy) return;
    const aBody = findLimb(attacker, attackerLimb);
    const tBody = findLimb(dummy, targetLimb);
    if (!aBody || !tBody) return;

    const result = applyLabStrike(aBody, tBody, speed);
    const dmg =
      result.damage.victim === "b"
        ? result.damage.damageB
        : result.damage.victim === "a"
          ? result.damage.damageA
          : Math.max(result.damage.damageA, result.damage.damageB);

    setLastResult(
      [
        `impact ${result.damage.impactSpeed.toFixed(2)}`,
        `damage ${dmg.toFixed(1)} ♥`,
        `push ${result.knockback.victimMagnitude.toFixed(1)}`,
        `victim ${result.damage.victim}`,
      ].join(" · "),
    );
  }, [attacker, dummy, attackerLimb, targetLimb, speed]);

  return (
    <>
      <Viewport protagonists={protagonists} />
      <SurroundingWalls thick={SIZE} bounds={BOUNDS} options={{ render: { fillStyle: "#222" } }} />
      {attacker && <Composite.add object={attacker} />}
      {dummy && <Composite.add object={dummy} />}

      <div className="strike-lab-panel menu-panel-surface menu-panel-pad menu-stack font-ui">
        <h2 className="menu-panel-title">Strike lab</h2>
        <p className="menu-hint">?lab=1 — старый тест ударов/урона (не каталог Тесты)</p>

        <label className="menu-field">
          <span className="menu-label">Attacker limb</span>
          <select
            className="menu-select"
            value={attackerLimb}
            onChange={(e) => setAttackerLimb(e.target.value as StrikeLimbLabel)}
          >
            {STRIKE_LIMB_LABELS.map((l) => (
              <option key={l} value={l}>
                {l}
              </option>
            ))}
          </select>
        </label>

        <label className="menu-field">
          <span className="menu-label">Target zone</span>
          <select
            className="menu-select"
            value={targetLimb}
            onChange={(e) => setTargetLimb(e.target.value as StrikeLimbLabel)}
          >
            {STRIKE_LIMB_LABELS.map((l) => (
              <option key={l} value={l}>
                {l}
              </option>
            ))}
          </select>
        </label>

        <label className="menu-field">
          <span className="menu-label">Closing speed: {speed.toFixed(1)}</span>
          <input
            type="range"
            min={1}
            max={18}
            step={0.5}
            value={speed}
            onChange={(e) => setSpeed(Number(e.target.value))}
            className="menu-range"
          />
        </label>

        {preview && (
          <div className="menu-stat-box">
            <p>
              Preview damage:{" "}
              <strong>{Math.max(preview.damage.damageA, preview.damage.damageB).toFixed(1)} ♥</strong>
            </p>
            <p>
              Preview push: <strong>{preview.knockback.victimMagnitude.toFixed(1)}</strong>
            </p>
            <p>Impact speed: {preview.damage.impactSpeed.toFixed(2)}</p>
          </div>
        )}

        <button type="button" className="menu-nav-btn menu-nav-btn--primary" onClick={fireStrike}>
          Strike!
        </button>
        <button type="button" className="menu-nav-btn" onClick={resetPoses}>
          Reset positions
        </button>

        <p className="menu-result">Last: {lastResult}</p>
      </div>
    </>
  );
}

export function StrikeLab() {
  return (
    <section className="strike-lab-root h-full overflow-hidden relative">
      <Renderer
        engine={{ gravity: { x: 0, y: 1 / 10, scale: 1 / 1_000 } }}
        render={{ options: { background: "#14141c", wireframes: false } }}
      >
        <StrikeLabScene />
      </Renderer>
    </section>
  );
}

export default StrikeLab;
