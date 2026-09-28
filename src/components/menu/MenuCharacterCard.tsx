import { useAchievements } from "@/achievements/AchievementsContext";
import { AvatarFaceChipCanvas } from "@/components/AvatarFaceChipCanvas";
import { useAuth } from "@/cloud/AuthContext";
import { getAvatarFacePreset } from "@/face/avatarPresets";
import { MEDAL_BY_ID, computePlayerLevel } from "@/lib/achievements";
import { formatHeartCount } from "@/lib/fighterColors";
import { MAX_HP } from "@/lib/combat";
import { findMatchingPreset } from "@/player/colorPresets";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";

/** Карточка бойца + силуэт: на телефоне в «Облике» должен быть виден человек. */
export function MenuCharacterCard() {
  const { profile } = usePlayerProfile();
  const { stats } = useAchievements();
  const { user, configured } = useAuth();
  const { t, settings } = useSettings();
  const lang = settings.language;
  const preset = findMatchingPreset(profile.colors);
  const avatarPreset = getAvatarFacePreset(profile.avatarFaceId);
  const lastMedal = profile.lastBattleMedalId
    ? MEDAL_BY_ID[profile.lastBattleMedalId]
    : null;
  const level = computePlayerLevel(stats);
  const main = profile.colors.main;
  const tip = profile.colors.secondary;

  return (
    <div className="menu-character-card pointer-events-none">
      <div
        className="menu-character-card__glow"
        style={{
          background: `radial-gradient(circle, color-mix(in srgb, ${main} 35%, transparent) 0%, transparent 70%)`,
        }}
      />

      <div className="menu-character-card__row">
        <div className="menu-character-card__figure" aria-hidden>
          <div className="menu-character-card__head">
            {profile.useCamera ? (
              <span
                className="menu-character-card__head-cam"
                style={{ background: main, boxShadow: `inset 0 0 0 3px ${tip}` }}
              />
            ) : (
              <AvatarFaceChipCanvas preset={avatarPreset} />
            )}
          </div>
          <div
            className="menu-character-card__torso"
            style={{ background: main }}
          />
          <div className="menu-character-card__arms">
            <span style={{ background: main, boxShadow: `inset -6px 0 0 ${tip}` }} />
            <span style={{ background: main, boxShadow: `inset 6px 0 0 ${tip}` }} />
          </div>
          <div className="menu-character-card__legs">
            <span style={{ background: main }} />
            <span style={{ background: main }} />
          </div>
        </div>

        <div className="menu-character-card__meta">
          <p className="menu-character-card__label font-ui">{t.menu.yourFighter}</p>
          <p
            className="menu-character-card__name font-display"
            style={{ color: main }}
          >
            {profile.name}
          </p>

          <div className="menu-character-card__rank-row">
            <span
              className="menu-character-card__level font-display"
              style={{ color: tip }}
            >
              {t.customize.characterLevel} {level.level}
            </span>
            <span className="menu-character-card__title font-ui">
              {t.ranks[level.titleId]}
            </span>
            {configured && (
              <span
                className={[
                  "menu-character-card__cloud",
                  user
                    ? "menu-character-card__cloud--on"
                    : "menu-character-card__cloud--off",
                ].join(" ")}
              >
                {user ? t.account.signedIn : t.account.guest}
              </span>
            )}
          </div>

          <div
            className="menu-character-card__xp"
            role="progressbar"
            aria-valuenow={Math.round(level.progress * 100)}
            aria-valuemin={0}
            aria-valuemax={100}
          >
            <div
              className="menu-character-card__xp-fill"
              style={{
                width: `${Math.round(level.progress * 100)}%`,
                background: `linear-gradient(90deg, ${main}, ${tip})`,
              }}
            />
          </div>

          <p className="menu-character-card__record font-ui">
            {t.customize.characterRecord}: {stats.wins}–{stats.losses} ·{" "}
            {stats.battles} {t.achievements.battles.toLowerCase()}
          </p>

          <p
            className="menu-character-card__hearts font-hand"
            style={{ color: main }}
          >
            {formatHeartCount(MAX_HP)}
          </p>
          <p className="menu-character-card__preset font-ui">
            {preset ? preset.label[lang] : t.customize.presetCustomName}
          </p>
          <p className="menu-character-card__face font-ui">
            <span
              className={[
                "menu-character-card__camera-dot",
                profile.useCamera
                  ? "menu-character-card__camera-dot--on"
                  : "menu-character-card__camera-dot--off",
              ].join(" ")}
              aria-hidden
            />
            {profile.useCamera
              ? t.customize.characterCameraOn
              : avatarPreset.label[lang]}
          </p>
          {lastMedal && profile.lastBattleMedalId && (
            <p className="menu-character-card__medal font-ui">
              <span aria-hidden>{lastMedal.icon}</span>
              <span className="menu-character-card__medal-label">
                {t.customize.characterLastMedal}:{" "}
                {t.medals[profile.lastBattleMedalId]}
              </span>
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
