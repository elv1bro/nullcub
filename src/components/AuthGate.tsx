import { playMenuSound } from "@/audio";
import {
  shouldBypassAuthGate,
  useAuth,
  type AuthProviderId,
} from "@/cloud/AuthContext";
import { e2eMatches, e2eOk, e2eSetPhase } from "@/dev/e2eHarness";
import { useTranslation } from "@/settings/SettingsContext";
import { useEffect, useState } from "react";

/**
 * Первая страница: без сессии заставка и меню недоступны.
 * После входа — BootSplash → игра. Обходы: e2e / webdriver / Steam|Electron / нет облака.
 */
export function AuthGate({ children }: { children: React.ReactNode }) {
  const t = useTranslation();
  const {
    configured,
    loading,
    user,
    error,
    emailPending,
    signIn,
    signInWithEmail,
    verifyEmailOtp,
    clearEmailPending,
  } = useAuth();
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const forceGatePreview = e2eMatches("authGate");

  useEffect(() => {
    if (!forceGatePreview) return;
    e2eSetPhase("running");
    const timer = setTimeout(
      () => e2eOk({ screen: "authGate", providers: ["google", "discord", "email"] }),
      400,
    );
    return () => clearTimeout(timer);
  }, [forceGatePreview]);

  if (!forceGatePreview && (shouldBypassAuthGate() || user)) {
    return <>{children}</>;
  }

  if (!forceGatePreview && loading) {
    return (
      <div className="auth-gate">
        <p className="auth-gate__hint font-ui">{t.account.loading}</p>
      </div>
    );
  }

  if (!forceGatePreview && !configured) {
    return <>{children}</>;
  }

  const onProvider = (provider: AuthProviderId) => {
    playMenuSound("panel");
    void signIn(provider);
  };

  const onSendEmail = async () => {
    playMenuSound("panel");
    setBusy(true);
    await signInWithEmail(email);
    setBusy(false);
  };

  const onVerify = async () => {
    playMenuSound("panel");
    if (!emailPending) return;
    setBusy(true);
    await verifyEmailOtp(emailPending, code);
    setBusy(false);
  };

  const errText =
    error === "sync_failed"
      ? t.account.syncFailed
      : error === "cloud_not_configured"
        ? t.account.notConfigured
        : error === "invalid_email"
          ? t.account.emailInvalid
          : error;

  return (
    <div className="auth-gate">
      <div className="auth-gate__card">
        <h1 className="auth-gate__title font-display">
          <span className="text-white">{t.game.title}</span>{" "}
          <span className="menu-title-accent">{t.game.titleAccent}</span>
        </h1>
        <p className="auth-gate__hint font-ui">{t.account.gateHint}</p>

        <div className="auth-gate__providers">
          <button
            type="button"
            className="menu-nav-btn menu-nav-btn--primary"
            onClick={() => onProvider("google")}
            disabled={busy}
          >
            {t.account.google}
          </button>
          <button
            type="button"
            className="menu-nav-btn"
            onClick={() => onProvider("discord")}
            disabled={busy}
          >
            {t.account.discord}
          </button>
        </div>

        <div className="auth-gate__divider font-ui">{t.account.orEmail}</div>

        {!emailPending ? (
          <form
            className="auth-gate__email"
            onSubmit={(e) => {
              e.preventDefault();
              void onSendEmail();
            }}
          >
            <input
              type="email"
              className="auth-gate__input font-ui"
              placeholder={t.account.emailPlaceholder}
              value={email}
              autoComplete="email"
              onChange={(e) => setEmail(e.target.value)}
              disabled={busy}
            />
            <button
              type="submit"
              className="menu-nav-btn"
              disabled={busy || !email.trim()}
            >
              {t.account.emailSend}
            </button>
          </form>
        ) : (
          <form
            className="auth-gate__email"
            onSubmit={(e) => {
              e.preventDefault();
              void onVerify();
            }}
          >
            <p className="auth-gate__hint font-ui">
              {t.account.emailCodeSent.replace("{email}", emailPending)}
            </p>
            <input
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              className="auth-gate__input font-ui"
              placeholder={t.account.emailCodePlaceholder}
              value={code}
              maxLength={8}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              disabled={busy}
            />
            <button
              type="submit"
              className="menu-nav-btn menu-nav-btn--primary"
              disabled={busy || code.length < 6}
            >
              {t.account.emailVerify}
            </button>
            <button
              type="button"
              className="menu-nav-btn"
              onClick={() => {
                clearEmailPending();
                setCode("");
              }}
              disabled={busy}
            >
              {t.menu.back}
            </button>
          </form>
        )}

        {errText ? (
          <p className="auth-gate__error font-ui" role="alert">
            {errText}
          </p>
        ) : null}
      </div>
    </div>
  );
}
