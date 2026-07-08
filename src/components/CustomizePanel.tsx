import { AvatarFaceChipCanvas } from "@/components/AvatarFaceChipCanvas";
import { FaceEffectChipCanvas } from "@/components/FaceEffectChipCanvas";
import { CustomPresetModal } from "@/components/CustomPresetModal";
import { AVATAR_FACE_PRESETS } from "@/face/avatarPresets";
import { FACE_OVERLAY_EFFECTS } from "@/face/faceEffects";
import type { FaceOverlayEffectId } from "@/player/PlayerProfileContext";
import {
  COLOR_PRESETS,
  findMatchingPreset,
  isPresetActive,
  presetColors,
  type ColorPreset,
} from "@/player/colorPresets";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { playMenuSound } from "@/audio";
import { useSettings, useTranslation } from "@/settings/SettingsContext";
import { useMemo, useState } from "react";

function MediaToggle({
  label,
  hint,
  checked,
  onChange,
}: {
  label: string;
  hint: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <label className="menu-media-toggle">
      <span className="menu-media-toggle__text">
        <span className="menu-media-toggle__label font-ui">{label}</span>
        <span className="menu-media-toggle__hint font-ui">{hint}</span>
      </span>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        className={[
          "menu-toggle",
          checked ? "menu-toggle--on" : "",
        ].join(" ")}
        onClick={() => {
          playMenuSound("click");
          onChange(!checked);
        }}
      >
        <span className="menu-toggle__knob" />
      </button>
    </label>
  );
}

interface Props {
  embedded?: boolean;
  onOpenAchievements?: () => void;
}

export function CustomizePanel({ embedded, onOpenAchievements }: Props) {
  const t = useTranslation();
  const { settings } = useSettings();
  const lang = settings.language;
  const {
    profile,
    setName,
    setColors,
    setUseCamera,
    setUseMicrophone,
    setFaceEffect,
    setAvatarFaceId,
  } = usePlayerProfile();
  const [customOpen, setCustomOpen] = useState(false);
  const activePreset = useMemo(
    () => findMatchingPreset(profile.colors),
    [profile.colors],
  );
  const isCustom = !activePreset;

  const pickPreset = (preset: ColorPreset) => {
    playMenuSound("panel");
    setColors(presetColors(preset));
  };

  const pickEffect = (id: FaceOverlayEffectId) => {
    playMenuSound("panel");
    setFaceEffect(id);
  };

  const pickAvatar = (id: string) => {
    playMenuSound("panel");
    setAvatarFaceId(id);
  };

  const pickRandomAvatar = () => {
    const idx = Math.floor(Math.random() * AVATAR_FACE_PRESETS.length);
    const face = AVATAR_FACE_PRESETS[idx];
    if (!face) return;
    pickAvatar(face.id);
  };

  const inner = (
    <>
      <div className="menu-media-section">
        <span className="menu-field__label font-ui">{t.customize.mediaTitle}</span>
        <MediaToggle
          label={t.customize.camera}
          hint={t.customize.cameraHint}
          checked={profile.useCamera}
          onChange={setUseCamera}
        />
        <MediaToggle
          label={t.customize.microphone}
          hint={t.customize.microphoneHint}
          checked={profile.useMicrophone}
          onChange={setUseMicrophone}
        />
      </div>

      {!profile.useCamera && (
        <div className="menu-preset-section">
          <div className="menu-preset-section__head">
            <span className="menu-field__label font-ui">{t.customize.avatarFaces}</span>
            <span className="menu-preset-section__count font-ui">
              {AVATAR_FACE_PRESETS.length}
            </span>
          </div>
          <p className="menu-avatar-faces-hint font-ui">{t.customize.avatarFacesHint}</p>
          <div className="menu-avatar-actions">
            <button
              type="button"
              className="menu-avatar-action-btn font-ui"
              onClick={pickRandomAvatar}
            >
              {t.customize.avatarRandom}
            </button>
            {profile.lastBattleAvatarFaceId && (
              <button
                type="button"
                className="menu-avatar-action-btn font-ui"
                onClick={() => pickAvatar(profile.lastBattleAvatarFaceId!)}
              >
                {t.customize.avatarLastBattle}
              </button>
            )}
          </div>
          <div className="menu-preset-scroll menu-preset-scroll--avatars" role="list">
            {AVATAR_FACE_PRESETS.map((face) => {
              const active = profile.avatarFaceId === face.id;
              return (
                <button
                  key={face.id}
                  type="button"
                  role="listitem"
                  className={[
                    "menu-preset-chip menu-preset-chip--avatar",
                    active ? "menu-preset-chip--active" : "",
                  ].join(" ")}
                  onClick={() => pickAvatar(face.id)}
                  title={face.label[lang]}
                >
                  <span className="menu-avatar-chip">
                    <AvatarFaceChipCanvas preset={face} />
                  </span>
                  <span className="menu-preset-chip__label font-ui">
                    {face.label[lang]}
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      )}

      <label className="menu-field">
        <span className="menu-field__label font-ui">{t.customize.name}</span>
        <input
          type="text"
          value={profile.name}
          maxLength={16}
          onChange={(e) => setName(e.target.value)}
          className="menu-field__input font-display"
        />
      </label>

      <div className="menu-preset-section">
        <div className="menu-preset-section__head">
          <span className="menu-field__label font-ui">{t.customize.presets}</span>
          <span className="menu-preset-section__count font-ui">
            {COLOR_PRESETS.length + 1}
          </span>
        </div>

        <div className="menu-preset-scroll" role="list">
          {COLOR_PRESETS.map((preset) => {
            const active = isPresetActive(preset, profile.colors);
            return (
              <button
                key={preset.id}
                type="button"
                role="listitem"
                className={[
                  "menu-preset-chip",
                  active ? "menu-preset-chip--active" : "",
                ].join(" ")}
                onClick={() => pickPreset(preset)}
                title={preset.label[lang]}
              >
                <span
                  className="menu-preset-chip__swatch"
                  style={{
                    background: `linear-gradient(145deg, ${preset.main} 50%, ${preset.secondary} 50%)`,
                  }}
                />
                <span className="menu-preset-chip__label font-ui">
                  {preset.label[lang]}
                </span>
              </button>
            );
          })}

          <button
            type="button"
            role="listitem"
            className={[
              "menu-preset-chip menu-preset-chip--custom",
              isCustom ? "menu-preset-chip--active" : "",
            ].join(" ")}
            onClick={() => {
              playMenuSound("panel");
              setCustomOpen(true);
            }}
          >
            <span
              className="menu-preset-chip__swatch menu-preset-chip__swatch--custom"
              style={
                isCustom
                  ? {
                      background: `linear-gradient(145deg, ${profile.colors.main} 50%, ${profile.colors.secondary} 50%)`,
                    }
                  : undefined
              }
            >
              +
            </span>
            <span className="menu-preset-chip__label font-ui">
              {t.customize.customPreset}
            </span>
          </button>
        </div>
      </div>

      <div className="menu-preset-section">
        <div className="menu-preset-section__head">
          <span className="menu-field__label font-ui">{t.customize.faceEffects}</span>
        </div>
        <div className="menu-preset-scroll menu-preset-scroll--effects" role="list">
          {FACE_OVERLAY_EFFECTS.map((effect) => {
            const active = profile.faceEffect === effect.id;
            return (
              <button
                key={effect.id}
                type="button"
                role="listitem"
                className={[
                  "menu-preset-chip menu-preset-chip--effect",
                  active ? "menu-preset-chip--active" : "",
                ].join(" ")}
                onClick={() => pickEffect(effect.id)}
                title={effect.label[lang]}
              >
                <span className="menu-preset-chip__swatch menu-preset-chip__swatch--effect">
                  <FaceEffectChipCanvas effectId={effect.id} />
                </span>
                <span className="menu-preset-chip__label font-ui">
                  {effect.label[lang]}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {onOpenAchievements && (
        <button
          type="button"
          className="menu-nav-btn menu-customize-achievements-btn"
          onClick={() => {
            playMenuSound("panel");
            onOpenAchievements();
          }}
        >
          <span className="menu-nav-btn__icon" aria-hidden>
            🏅
          </span>
          {t.customize.openAchievements}
        </button>
      )}

      <CustomPresetModal
        open={customOpen}
        colors={profile.colors}
        onApply={setColors}
        onClose={() => setCustomOpen(false)}
      />
    </>
  );

  if (embedded) return <div className="menu-customize-panel">{inner}</div>;

  return (
    <div className="w-full max-w-xs p-4 rounded-lg bg-dark-800/90 border border-gray-700 space-y-4">
      <h3 className="font-display text-lg uppercase text-white font-bold tracking-wide">
        {t.customize.title}
      </h3>
      {inner}
    </div>
  );
}
