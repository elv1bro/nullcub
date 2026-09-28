import { useAchievements } from "@/achievements/AchievementsContext";
import { useAuth, type AuthProviderId } from "@/cloud/AuthContext";
import { playMenuSound } from "@/audio";
import { computePlayerLevel } from "@/lib/achievements";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";

interface Props {
  onOpenAccount: () => void;
}

/** Вход прямо на главном экране — иначе авторизацию никто не находит. */
export function MenuHomeAuth({ onOpenAccount }: Props) {
  const { t } = useSettings();
  const { profile } = usePlayerProfile();
  const { stats } = useAchievements();
  const level = computePlayerLevel(stats);
  const { configured, loading, user, signIn } = useAuth();

  if (!configured) return null;

  if (loading) {
    return (
      <p className="menu-home-auth__hint font-ui">{t.account.loading}</p>
    );
  }

  if (user) {
    return (
      <button
        type="button"
        className="menu-home-auth menu-home-auth--signed"
        onClick={() => {
          playMenuSound("panel");
          onOpenAccount();
        }}
      >
        <span className="menu-home-auth__name font-display">{profile.name}</span>
        <span className="menu-home-auth__meta font-ui">
          {t.customize.characterLevel} {level.level} · {t.ranks[level.titleId]} ·{" "}
          {t.account.signedIn}
        </span>
      </button>
    );
  }

  const onProvider = (provider: AuthProviderId) => {
    playMenuSound("panel");
    void signIn(provider);
  };

  return (
    <div className="menu-home-auth">
      <p className="menu-home-auth__hint font-ui">{t.account.hint}</p>
      <div className="menu-home-auth__actions">
        <button
          type="button"
          className="menu-nav-btn menu-nav-btn--primary"
          onClick={() => onProvider("google")}
        >
          {t.account.google}
        </button>
        <button
          type="button"
          className="menu-nav-btn"
          onClick={() => onProvider("discord")}
        >
          {t.account.discord}
        </button>
      </div>
    </div>
  );
}
