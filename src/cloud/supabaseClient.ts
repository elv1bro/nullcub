import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/** Минимальные типы строк — полный codegen не нужен для v1. */
export type ProfileRow = {
  user_id: string;
  display_name: string;
  colors: { main: string; secondary: string };
  use_camera: boolean;
  use_microphone: boolean;
  face_effect: string;
  avatar_face_id: string;
  last_battle_avatar_face_id: string | null;
  last_battle_medal_id: string | null;
  updated_at: string;
};

export type PlayerStatsRow = {
  user_id: string;
  battles: number;
  wins: number;
  losses: number;
  loss_streak: number;
  medals: Record<string, number>;
  updated_at: string;
};

export type CampaignProgressRow = {
  user_id: string;
  campaign_id: string;
  max_unlocked_order: number;
  updated_at: string;
};

let client: SupabaseClient | null = null;

export function isCloudConfigured(): boolean {
  const url = import.meta.env.VITE_SUPABASE_URL;
  const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
  if (!url || !key || !String(url).includes("http")) return false;
  // Accept new publishable keys and legacy JWT anon keys.
  const k = String(key);
  return (
    k.startsWith("sb_publishable_") ||
    k.startsWith("eyJ") ||
    k.length > 20
  );
}

/** null если облако не настроено — игра работает полностью офлайн. */
export function getSupabase(): SupabaseClient | null {
  if (!isCloudConfigured()) return null;
  if (!client) {
    client = createClient(
      String(import.meta.env.VITE_SUPABASE_URL),
      String(import.meta.env.VITE_SUPABASE_ANON_KEY),
      {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
          flowType: "pkce",
        },
      },
    );
  }
  return client;
}
