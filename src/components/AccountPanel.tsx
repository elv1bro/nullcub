import { useAchievements } from "@/achievements/AchievementsContext";
import { useAuth, type AuthProviderId } from "@/cloud/AuthContext";
import { playMenuSound } from "@/audio";
import { computePlayerLevel } from "@/lib/achievements";
import { usePlayerProfile } from "@/player/PlayerProfileContext";
import { useSettings } from "@/settings/SettingsContext";

/** Вход Google/Discord + синк прогресса (если Supabase настроен). */
export function AccountPanel() {
  const { t } = useSettings();
  const { profile } = usePlayerProfile();
  const { stats } = useAchievements();
  const level = computePlayerLevel(stats);
  const { configured, loading, user, error, signIn, signOut, syncNow } =
    useAuth();

  if (!configured) {
    return (
      <div className="menu-account">
        <p className="menu-field__label font-ui">{t.account.title}</p>
        <p className="menu-account__hint font-ui">{t.account.notConfigured}</p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="menu-account">
        <p className="menu-field__label font-ui">{t.account.title}</p>
        <p className="menu-account__hint font-ui">{t.account.loading}</p>
      </div>
    );
  }

  const onProvider = (provider: AuthProviderId) => {
    playMenuSound("panel");
    void signIn(provider);
  };

  return (
    <div className="menu-account">
      <p className="menu-field__label font-ui">{t.account.title}</p>
      <p className="menu-account__hint font-ui">{t.account.hint}</p>

      {user ? (
        <div className="menu-account__signed">
          <p className="menu-account__fighter font-display">{profile.name}</p>
          <p className="menu-account__rank font-ui">
            {t.customize.characterLevel} {level.level} · {t.ranks[level.titleId]}
          </p>
          <p className="menu-account__email font-ui">
            {user.email ?? user.user_metadata?.full_name ?? user.id.slice(0, 8)}
          </p>
          <div className="menu-account__actions">
            <button
              type="button"
              className="menu-nav-btn"
              onClick={() => {
                playMenuSound("click");
                void syncNow();
              }}
            >
              {t.account.sync}
            </button>
            <button
              type="button"
              className="menu-nav-btn"
              onClick={() => {
                playMenuSound("click");
                void signOut();
              }}
            >
              {t.account.signOut}
            </button>
          </div>
        </div>
      ) : (
        <div className="menu-account__providers">
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
      )}

      {error && (
        <p className="menu-account__error font-ui">
          {error === "cloud_not_configured"
            ? t.account.notConfigured
            : error === "sync_failed"
              ? t.account.syncFailed
              : error}
        </p>
      )}
    </div>
  );
}
