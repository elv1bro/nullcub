import { CLOUD_SYNC_EVENT } from "@/cloud/cloudEvents";
import { pullAndMergeCloudProgress } from "@/cloud/cloudProgress";
import { getSupabase, isCloudConfigured } from "@/cloud/supabaseClient";
import { platformSkipsWebAuthGate } from "@/platform/identity";
import type { Provider, Session, User } from "@supabase/supabase-js";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from "react";

export type AuthProviderId = "google" | "discord";

interface AuthContextValue {
  configured: boolean;
  loading: boolean;
  user: User | null;
  session: Session | null;
  error: string | null;
  /** Email OTP: код отправлен, ждём verify. */
  emailPending: string | null;
  signIn: (provider: AuthProviderId) => Promise<void>;
  /** Отправить 6-значный код на почту. */
  signInWithEmail: (email: string) => Promise<boolean>;
  /** Подтвердить код из письма. */
  verifyEmailOtp: (email: string, token: string) => Promise<boolean>;
  clearEmailPending: () => void;
  signOut: () => Promise<void>;
  syncNow: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: PropsWithChildren) {
  const configured = isCloudConfigured();
  const [loading, setLoading] = useState(configured);
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [emailPending, setEmailPending] = useState<string | null>(null);

  useEffect(() => {
    const sb = getSupabase();
    if (!sb) {
      setLoading(false);
      return;
    }

    let alive = true;
    void sb.auth.getSession().then(({ data }) => {
      if (!alive) return;
      setSession(data.session);
      setUser(data.session?.user ?? null);
      setLoading(false);
      if (data.session) void pullAndMergeCloudProgress();
    });

    const { data: sub } = sb.auth.onAuthStateChange((event, next) => {
      setSession(next);
      setUser(next?.user ?? null);
      if (event === "SIGNED_IN" || event === "TOKEN_REFRESHED") {
        void pullAndMergeCloudProgress();
      }
    });

    return () => {
      alive = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  const signIn = useCallback(async (provider: AuthProviderId) => {
    const sb = getSupabase();
    if (!sb) {
      setError("cloud_not_configured");
      return;
    }
    setError(null);
    const redirectTo = `${window.location.origin}${window.location.pathname}`;
    const { error: err } = await sb.auth.signInWithOAuth({
      provider: provider as Provider,
      options: { redirectTo },
    });
    if (err) setError(err.message);
  }, []);

  const signInWithEmail = useCallback(async (email: string) => {
    const sb = getSupabase();
    if (!sb) {
      setError("cloud_not_configured");
      return false;
    }
    const trimmed = email.trim().toLowerCase();
    if (!trimmed.includes("@")) {
      setError("invalid_email");
      return false;
    }
    setError(null);
    // Без emailRedirectTo Supabase подставляет Site URL (часто localhost:3000).
    const emailRedirectTo = `${window.location.origin}${window.location.pathname}`;
    const { error: err } = await sb.auth.signInWithOtp({
      email: trimmed,
      options: {
        shouldCreateUser: true,
        emailRedirectTo,
      },
    });
    if (err) {
      setError(err.message);
      return false;
    }
    setEmailPending(trimmed);
    return true;
  }, []);

  const verifyEmailOtp = useCallback(async (email: string, token: string) => {
    const sb = getSupabase();
    if (!sb) {
      setError("cloud_not_configured");
      return false;
    }
    setError(null);
    const { error: err } = await sb.auth.verifyOtp({
      email: email.trim().toLowerCase(),
      token: token.trim(),
      type: "email",
    });
    if (err) {
      setError(err.message);
      return false;
    }
    setEmailPending(null);
    return true;
  }, []);

  const clearEmailPending = useCallback(() => {
    setEmailPending(null);
    setError(null);
  }, []);

  const signOut = useCallback(async () => {
    const sb = getSupabase();
    if (!sb) return;
    setError(null);
    await sb.auth.signOut();
    setUser(null);
    setSession(null);
    setEmailPending(null);
  }, []);

  const syncNow = useCallback(async () => {
    setError(null);
    const result = await pullAndMergeCloudProgress();
    if (result === "error") setError("sync_failed");
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent(CLOUD_SYNC_EVENT));
    }
  }, []);

  const value = useMemo(
    () => ({
      configured,
      loading,
      user,
      session,
      error,
      emailPending,
      signIn,
      signInWithEmail,
      verifyEmailOtp,
      clearEmailPending,
      signOut,
      syncNow,
    }),
    [
      configured,
      loading,
      user,
      session,
      error,
      emailPending,
      signIn,
      signInWithEmail,
      verifyEmailOtp,
      clearEmailPending,
      signOut,
      syncNow,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

/** E2E / headless / стор / нет Supabase — гейт не блокирует игру. */
export function shouldBypassAuthGate(): boolean {
  if (typeof window === "undefined") return true;
  const e2e = new URLSearchParams(window.location.search).get("e2e");
  // Спецсценарий verify: показать UI гейта (даже без облака / под webdriver).
  if (e2e === "authGate") return false;
  if (e2e) return true;
  if (navigator.webdriver) return true;
  // Steam / Electron: платформа сама даёт identity; веб-OAuth — опциональный линк.
  if (platformSkipsWebAuthGate()) return true;
  if (!isCloudConfigured()) return true;
  return false;
}
