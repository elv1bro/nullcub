//

import debug from "debug";
import { type PropsWithChildren } from "react";
import { CompositeContext } from "./CompositeContext";
import { useEngine } from "./EngineContext";

//

const log = debug("@1.framework:matter4react:WorldComposite");

//

export const WorldComposite = ({ children }: PropsWithChildren) => {
  log("!");
  const engine = useEngine();
  if (!engine) return null;
  return (
    <CompositeContext.Provider value={engine.world}>
      {children}
    </CompositeContext.Provider>
  );
};
