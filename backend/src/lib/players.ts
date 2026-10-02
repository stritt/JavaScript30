import type { Env } from "../env";
import { apiError } from "./util";

export interface PlayerRow {
  id: string;
  apple_sub: string | null;
  dev_device_id: string | null;
  display_name: string;
  hero_level: number;
  zone: number;
  region: string | null;
  local_opt_in: number;
  flagged: number;
  created_at: string;
}

export interface Player {
  id: string;
  displayName: string;
  heroLevel: number;
  zone: number;
  region: string | null;
  localOptIn: boolean;
  flagged: boolean;
  createdAt: string;
}

export function toPlayer(row: PlayerRow): Player {
  return {
    id: row.id,
    displayName: row.display_name,
    heroLevel: row.hero_level,
    zone: row.zone,
    region: row.region,
    localOptIn: row.local_opt_in === 1,
    flagged: row.flagged === 1,
    createdAt: row.created_at,
  };
}

export async function getPlayer(env: Env, id: string): Promise<PlayerRow | null> {
  return env.DB.prepare("SELECT * FROM players WHERE id = ?").bind(id).first<PlayerRow>();
}

export async function requirePlayer(env: Env, id: string): Promise<PlayerRow> {
  const row = await getPlayer(env, id);
  if (!row) throw apiError(401, "unknown_player", "Player no longer exists");
  return row;
}

export async function weekSteps(env: Env, playerId: string, week: string): Promise<number> {
  const row = await env.DB.prepare(
    "SELECT COALESCE(SUM(steps), 0) AS total FROM step_days WHERE player_id = ? AND week = ?",
  )
    .bind(playerId, week)
    .first<{ total: number }>();
  return row?.total ?? 0;
}

export function cleanDisplayName(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const name = raw.replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 24);
  return name.length > 0 ? name : null;
}
