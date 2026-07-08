import { useEffect, useState } from "react";

/** Кастомный курсор — круг + «рука» при hover на кнопках. */
export function MenuArenaCursor() {
  const [pos, setPos] = useState({ x: -100, y: -100 });
  const [pressing, setPressing] = useState(false);
  const [hand, setHand] = useState(false);

  useEffect(() => {
    const move = (e: MouseEvent) => setPos({ x: e.clientX, y: e.clientY });
    const down = () => setPressing(true);
    const up = () => setPressing(false);

    const checkHand = (e: MouseEvent) => {
      const el = document.elementFromPoint(e.clientX, e.clientY);
      setHand(!!el?.closest("button, a, [role='button']"));
    };

    window.addEventListener("mousemove", move);
    window.addEventListener("mousemove", checkHand);
    window.addEventListener("mousedown", down);
    window.addEventListener("mouseup", up);
    return () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mousemove", checkHand);
      window.removeEventListener("mousedown", down);
      window.removeEventListener("mouseup", up);
    };
  }, []);

  return (
    <div
      className="menu-arena-cursor"
      style={{
        transform: `translate(${pos.x}px, ${pos.y}px) scale(${pressing ? 0.85 : 1})`,
      }}
      aria-hidden
    >
      <span className={hand ? "menu-arena-cursor__hand" : "menu-arena-cursor__ring"} />
    </div>
  );
}
