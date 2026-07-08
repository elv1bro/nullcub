//

import { Engine, Vector, type IEventTimestamped } from "matter-js";
import { useEventBeforeUpdate } from "./useEventBeforeUpdate";
import { useKeyPressRef } from "./useKeyPressRef";

//

export function PlayerInput({ map, event, call }: Props) {
  const ArrowUp = useKeyPressRef("ArrowUp");
  const ArrowDown = useKeyPressRef("ArrowDown");
  const ArrowLeft = useKeyPressRef("ArrowLeft");
  const ArrowRight = useKeyPressRef("ArrowRight");
  const KeyW = useKeyPressRef("w");
  const KeyS = useKeyPressRef("s");
  const KeyA = useKeyPressRef("a");
  const KeyD = useKeyPressRef("d");

  useEventBeforeUpdate(
    (engineEvent) => {
      let vector = Vector.create();
      if (ArrowUp.current || KeyW.current) vector = Vector.add(vector, { x: 0, y: 1 });
      if (ArrowDown.current || KeyS.current) vector = Vector.add(vector, { x: 0, y: -1 });
      if (ArrowLeft.current || KeyA.current) vector = Vector.add(vector, { x: 1, y: 0 });
      if (ArrowRight.current || KeyD.current) vector = Vector.add(vector, { x: -1, y: 0 });
      if (vector.x !== 0 || vector.y !== 0) {
        call(engineEvent, vector);
      }
    },
    [map, event, call],
  );

  return null;
}

//

type Props = {
  map: string;
  event: string;
  call: (event: IEventTimestamped<Engine>, vector: Vector) => void;
};
