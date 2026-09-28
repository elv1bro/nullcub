import { MEDALS, MEDAL_BY_ID, computePlayerLevel } from "@/lib/achievements";
import { medalProgressRatio } from "@/lib/achievements/medalProgress";
import { useAchievements } from "@/achievements/AchievementsContext";
import { useTranslation } from "@/settings/SettingsContext";
import { useEffect } from "react";

interface Props {
  embedded?: boolean;
}

export function AchievementsPanel({ embedded }: Props) {
  const t = useTranslation();
  const { stats, refreshStats } = useAchievements();

  useEffect(() => {
    refreshStats();
  }, [refreshStats]);
  const totalMedals = Object.values(stats.medals).reduce(
    (sum, count) => sum + (count ?? 0),
    0,
  );
  const unlockedKinds = Object.values(stats.medals).filter((c) => (c ?? 0) > 0)
    .length;
  const overallProgress = MEDALS.length
    ? (unlockedKinds / MEDALS.length) * 100
    : 0;
  const level = computePlayerLevel(stats);

  const inner = (
    <>
      <div className="menu-level-banner">
        <div className="menu-level-banner__main">
          <span className="menu-level-banner__level font-display">
            {t.achievements.level} {level.level}
          </span>
          <span className="menu-level-banner__rank font-ui">
            {t.ranks[level.titleId]}
          </span>
        </div>
        <p className="menu-level-banner__xp font-ui">
          {t.achievements.xpToNext(level.xpIntoLevel, level.xpForNext)}
        </p>
        <div
          className="menu-level-banner__bar"
          role="progressbar"
          aria-valuenow={Math.round(level.progress * 100)}
          aria-valuemin={0}
          aria-valuemax={100}
        >
          <div
            className="menu-level-banner__fill"
            style={{ width: `${Math.round(level.progress * 100)}%` }}
          />
        </div>
      </div>

      <div className="menu-stats-bar">
        <div className="menu-stats-bar__item">
          <span className="menu-stats-bar__value font-display text-cyan-300">
            {stats.wins}
          </span>
          <span className="menu-stats-bar__label font-ui">
            {t.customize.statWins}
          </span>
        </div>
        <div className="menu-stats-bar__item">
          <span className="menu-stats-bar__value font-display text-red-300">
            {stats.losses}
          </span>
          <span className="menu-stats-bar__label font-ui">
            {t.customize.statLosses}
          </span>
        </div>
        <div className="menu-stats-bar__item">
          <span className="menu-stats-bar__value font-display text-white/90">
            {stats.battles}
          </span>
          <span className="menu-stats-bar__label font-ui">
            {t.achievements.battles}
          </span>
        </div>
        <div className="menu-stats-bar__item">
          <span className="menu-stats-bar__value font-display text-amber-200">
            {totalMedals}
          </span>
          <span className="menu-stats-bar__label font-ui">
            {t.customize.statMedals}
          </span>
        </div>
      </div>

      <p className="menu-achievements-progress font-ui">
        {t.achievements.progress(unlockedKinds, MEDALS.length)}
      </p>
      <div
        className="menu-achievements-progress-bar"
        role="progressbar"
        aria-valuenow={unlockedKinds}
        aria-valuemin={0}
        aria-valuemax={MEDALS.length}
      >
        <div
          className="menu-achievements-progress-bar__fill"
          style={{ width: `${overallProgress}%` }}
        />
      </div>

      <ul className="menu-achievement-grid">
        {MEDALS.map((medal) => {
          const count = stats.medals[medal.id] ?? 0;
          const unlocked = count > 0;
          const def = MEDAL_BY_ID[medal.id];
          const ratio = medalProgressRatio(stats, medal.id);
          return (
            <li
              key={medal.id}
              className={[
                "menu-achievement-card",
                unlocked ? "menu-achievement-card--unlocked" : "menu-achievement-card--locked",
              ].join(" ")}
            >
              <span className="menu-achievement-card__icon" aria-hidden>
                {def.icon}
              </span>
              <div className="menu-achievement-card__body">
                <p className="menu-achievement-card__name font-hand">
                  {t.medals[medal.id]}
                </p>
                <p className="menu-achievement-card__desc font-ui">
                  {t.medalDesc[medal.id]}
                </p>
                <div
                  className="menu-achievement-card__progress"
                  role="progressbar"
                  aria-valuenow={Math.round(ratio * 100)}
                  aria-valuemin={0}
                  aria-valuemax={100}
                >
                  <div
                    className="menu-achievement-card__progress-fill"
                    style={{ width: `${ratio * 100}%` }}
                  />
                </div>
                <p className="menu-achievement-card__meta font-ui">
                  {unlocked
                    ? t.achievements.earnedCount(count)
                    : t.achievements.locked}
                </p>
              </div>
            </li>
          );
        })}
      </ul>
    </>
  );

  if (embedded) return <div className="menu-achievements-panel">{inner}</div>;

  return (
    <div className="w-full max-w-md p-4 rounded-lg bg-dark-800/90 border border-gray-700">
      <h3 className="font-display text-lg uppercase text-white font-bold tracking-wide mb-4">
        {t.achievements.title}
      </h3>
      {inner}
    </div>
  );
}
