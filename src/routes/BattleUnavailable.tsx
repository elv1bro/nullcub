import { useContext } from "react";
import { GameContext } from "@/GameContext";

/** Заглушка для отключённых режимов (P2P / FFA). */
export function BattleUnavailable({ reason }: { reason: string }) {
  const { gameM } = useContext(GameContext);
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-dark-900/95">
      <div className="flex flex-col items-center gap-4 p-8 rounded-xl border border-gray-700 bg-dark-800 max-w-md text-center">
        <h1 className="text-xl font-bold text-white">Режим недоступен</h1>
        <p className="text-sm text-gray-400">{reason}</p>
        <button
          type="button"
          className="px-6 py-3 rounded-lg font-bold bg-cyan-700 text-white hover:bg-cyan-600"
          onClick={() => gameM.send({ type: "BACK" })}
        >
          В меню
        </button>
      </div>
    </div>
  );
}
