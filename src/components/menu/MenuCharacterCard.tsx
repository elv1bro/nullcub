import { getAvatarFacePreset } from "@/face/avatarPresets";
import { MEDAL_BY_ID } from "@/lib/achievements";
import { formatHeartCount } from "@/lib/fighterColors";
import { MAX_HP } from "@/lib/combat";
import { findMatchingPreset } from "@/player/colorPresets";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";

export function MenuCharacterCard() {
  const { profile } = usePlayerProfile();
  const { t, settings } = useSettings();
  const lang = settings.language;
  const preset = findMatchingPreset(profile.colors);
  const avatarPreset = getAvatarFacePreset(profile.avatarFaceId);
  const lastMedal = profile.lastBattleMedalId
    ? MEDAL_BY_ID[profile.lastBattleMedalId]
    : null;

  return (
    <div className="menu-character-card pointer-events-none">
      <div
        className="menu-character-card__glow"
        style={{
          background: `radial-gradient(circle, color-mix(in srgb, ${profile.colors.main} 35%, transparent) 0%, transparent 70%)`,
        }}
      />
      <p
        className="menu-character-card__name font-display"
        style={{ color: profile.colors.main }}
      >
        {profile.name}
      </p>
      <p
        className="menu-character-card__hearts font-hand"
        style={{ color: profile.colors.main }}
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
            {t.customize.characterLastMedal}: {t.medals[profile.lastBattleMedalId]}
          </span>
        </p>
      )}
    </div>
  );
}
