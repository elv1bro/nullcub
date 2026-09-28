import { BOUNCER_CAMPAIGN_ID } from "@/campaign/bouncer";
import {
  getMaxUnlockedOrder,
  replaceCampaignProgress,
} from "@/campaign/progress";
import {
  loadPlayerStats,
  replacePlayerStats,
  type PlayerStats,
} from "@/lib/achievements/store";
import {
  DEFAULT_PLAYER_PROFILE,
  loadPlayerProfile,
  replacePlayerProfile,
  type PlayerProfile,
} from "@/player/PlayerProfileContext";
import { CLOUD_SYNC_EVENT } from "./cloudEvents";
import { mergeCampaignOrder, mergePlayerStats } from "./mergeProgress";
import {
  getSupabase,
  type CampaignProgressRow,
  type PlayerStatsRow,
  type ProfileRow,
} from "./supabaseClient";

export { CLOUD_SYNC_EVENT } from "./cloudEvents";

function notifyLocalReload(): void {
  if (typeof window === "undefined") return;
  window.dispatchEvent(new CustomEvent(CLOUD_SYNC_EVENT));
}

function profileToRow(userId: string, p: PlayerProfile) {
  return {
    user_id: userId,
    display_name: p.name,
    colors: p.colors,
    use_camera: p.useCamera,
    use_microphone: p.useMicrophone,
    face_effect: p.faceEffect,
    avatar_face_id: p.avatarFaceId,
    last_battle_avatar_face_id: p.lastBattleAvatarFaceId,
    last_battle_medal_id: p.lastBattleMedalId,
    updated_at: new Date().toISOString(),
  };
}

function rowToProfile(row: {
  display_name: string;
  colors: { main: string; secondary: string };
  use_camera: boolean;
  use_microphone: boolean;
  face_effect: string;
  avatar_face_id: string;
  last_battle_avatar_face_id: string | null;
  last_battle_medal_id: string | null;
}): PlayerProfile {
  return {
    ...DEFAULT_PLAYER_PROFILE,
    name: row.display_name || DEFAULT_PLAYER_PROFILE.name,
    colors: {
      main: row.colors?.main || DEFAULT_PLAYER_PROFILE.colors.main,
      secondary: row.colors?.secondary || DEFAULT_PLAYER_PROFILE.colors.secondary,
    },
    useCamera: Boolean(row.use_camera),
    useMicrophone: Boolean(row.use_microphone),
    faceEffect: (row.face_effect as PlayerProfile["faceEffect"]) || "none",
    avatarFaceId: row.avatar_face_id || DEFAULT_PLAYER_PROFILE.avatarFaceId,
    lastBattleAvatarFaceId: row.last_battle_avatar_face_id,
    lastBattleMedalId:
      row.last_battle_medal_id as PlayerProfile["lastBattleMedalId"],
  };
}

function statsToRow(userId: string, s: PlayerStats) {
  return {
    user_id: userId,
    battles: s.battles,
    wins: s.wins,
    losses: s.losses,
    loss_streak: s.lossStreak,
    medals: s.medals as Record<string, number>,
    updated_at: new Date().toISOString(),
  };
}

function rowToStats(row: {
  battles: number;
  wins: number;
  losses: number;
  loss_streak: number;
  medals: Record<string, number>;
}): PlayerStats {
  return {
    battles: row.battles ?? 0,
    wins: row.wins ?? 0,
    losses: row.losses ?? 0,
    lossStreak: row.loss_streak ?? 0,
    medals: (row.medals ?? {}) as PlayerStats["medals"],
  };
}

/** Стянуть облако → смержить с локальным → записать localStorage → уведомить UI. */
export async function pullAndMergeCloudProgress(): Promise<
  "ok" | "skipped" | "error"
> {
  const sb = getSupabase();
  if (!sb) return "skipped";
  const {
    data: { session },
  } = await sb.auth.getSession();
  if (!session?.user) return "skipped";
  const userId = session.user.id;

  try {
    const [profileRes, statsRes, campaignRes] = await Promise.all([
      sb.from("profiles").select("*").eq("user_id", userId).maybeSingle(),
      sb.from("player_stats").select("*").eq("user_id", userId).maybeSingle(),
      sb
        .from("campaign_progress")
        .select("*")
        .eq("user_id", userId)
        .eq("campaign_id", BOUNCER_CAMPAIGN_ID)
        .maybeSingle(),
    ]);

    if (profileRes.error || statsRes.error || campaignRes.error) {
      console.warn(
        "[cloud] pull error",
        profileRes.error || statsRes.error || campaignRes.error,
      );
      return "error";
    }

    const localProfile = loadPlayerProfile();
    const localStats = loadPlayerStats();
    const localCampaign = getMaxUnlockedOrder();

    if (profileRes.data) {
      const remote = rowToProfile(profileRes.data as ProfileRow);
      // Первый логин: если remote почти дефолт, а local богаче — оставим local (push потом).
      const remoteIsThin =
        remote.name === "YOU" &&
        remote.avatarFaceId === DEFAULT_PLAYER_PROFILE.avatarFaceId;
      const localIsRich =
        localProfile.name !== "YOU" ||
        localProfile.avatarFaceId !== DEFAULT_PLAYER_PROFILE.avatarFaceId;
      replacePlayerProfile(
        remoteIsThin && localIsRich ? localProfile : remote,
      );
    }

    if (statsRes.data) {
      replacePlayerStats(
        mergePlayerStats(localStats, rowToStats(statsRes.data as PlayerStatsRow)),
      );
    }

    const remoteCampaign =
      (campaignRes.data as CampaignProgressRow | null)?.max_unlocked_order ?? 0;
    replaceCampaignProgress({
      [BOUNCER_CAMPAIGN_ID]: mergeCampaignOrder(localCampaign, remoteCampaign),
    });

    notifyLocalReload();
    // После merge сразу пушим — чтобы локальные «богатые» данные уехали в облако.
    await pushCloudProgress();
    return "ok";
  } catch (err) {
    console.warn("[cloud] pull failed", err);
    return "error";
  }
}

export async function pushCloudProgress(): Promise<"ok" | "skipped" | "error"> {
  const sb = getSupabase();
  if (!sb) return "skipped";
  const {
    data: { session },
  } = await sb.auth.getSession();
  if (!session?.user) return "skipped";
  const userId = session.user.id;

  try {
    const profile = loadPlayerProfile();
    const stats = loadPlayerStats();
    const campaignOrder = getMaxUnlockedOrder();

    const [p, s, c] = await Promise.all([
      sb.from("profiles").upsert(profileToRow(userId, profile)),
      sb.from("player_stats").upsert(statsToRow(userId, stats)),
      sb.from("campaign_progress").upsert({
        user_id: userId,
        campaign_id: BOUNCER_CAMPAIGN_ID,
        max_unlocked_order: campaignOrder,
        updated_at: new Date().toISOString(),
      }),
    ]);

    if (p.error || s.error || c.error) {
      console.warn("[cloud] push error", p.error || s.error || c.error);
      return "error";
    }
    return "ok";
  } catch (err) {
    console.warn("[cloud] push failed", err);
    return "error";
  }
}

export { scheduleCloudPush } from "./schedulePush";
