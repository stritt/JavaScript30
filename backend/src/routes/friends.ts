import { Hono } from "hono";
import type { AppEnv } from "../env";
import { requirePlayer } from "../lib/players";
import { apiError, currentWeek, newInviteCode, nowIso } from "../lib/util";

export const friends = new Hono<AppEnv>();

const INVITE_TTL_MS = 7 * 86_400_000;
const MAX_FRIENDS = 200;

friends.get("/", async (c) => {
  const playerId = c.get("playerId");
  const { results } = await c.env.DB.prepare(
    `SELECT p.id, p.display_name AS displayName, p.hero_level AS heroLevel, p.zone,
            (SELECT COALESCE(SUM(s.steps), 0) FROM step_days s WHERE s.player_id = p.id AND s.week = ?2) AS weekSteps
     FROM friendships f JOIN players p ON p.id = f.friend_id
     WHERE f.player_id = ?1
     ORDER BY weekSteps DESC`,
  )
    .bind(playerId, currentWeek())
    .all();
  return c.json({ friends: results });
});

friends.post("/invite", async (c) => {
  const playerId = c.get("playerId");
  await requirePlayer(c.env, playerId);
  const expiresAt = new Date(Date.now() + INVITE_TTL_MS).toISOString();

  // Retry on the (unlikely) code collision.
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newInviteCode();
    const res = await c.env.DB.prepare("INSERT OR IGNORE INTO invites (code, player_id, expires_at) VALUES (?, ?, ?)")
      .bind(code, playerId, expiresAt)
      .run();
    if (res.meta.changes === 1) {
      return c.json({ code, url: `${c.env.INVITE_BASE_URL}${code}`, expiresAt });
    }
  }
  throw apiError(503, "try_again", "Could not create an invite, try again");
});

friends.post("/accept", async (c) => {
  const playerId = c.get("playerId");
  const body: { code?: unknown } = await c.req.json().catch(() => ({}));
  const code = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";
  if (!code) throw apiError(400, "invalid_request", "code is required");

  const invite = await c.env.DB.prepare("SELECT player_id, expires_at FROM invites WHERE code = ?")
    .bind(code)
    .first<{ player_id: string; expires_at: string }>();
  if (!invite || invite.expires_at < nowIso()) throw apiError(404, "invite_not_found", "That invite is invalid or expired");
  if (invite.player_id === playerId) throw apiError(400, "own_invite", "You can't befriend yourself (nice try)");

  const count = await c.env.DB.prepare("SELECT COUNT(*) AS n FROM friendships WHERE player_id = ?")
    .bind(playerId)
    .first<{ n: number }>();
  if ((count?.n ?? 0) >= MAX_FRIENDS) throw apiError(409, "friend_limit", `Friend limit is ${MAX_FRIENDS}`);

  const now = nowIso();
  await c.env.DB.batch([
    c.env.DB.prepare("INSERT OR IGNORE INTO friendships (player_id, friend_id, created_at) VALUES (?, ?, ?)").bind(playerId, invite.player_id, now),
    c.env.DB.prepare("INSERT OR IGNORE INTO friendships (player_id, friend_id, created_at) VALUES (?, ?, ?)").bind(invite.player_id, playerId, now),
  ]);

  const friend = await c.env.DB.prepare(
    `SELECT p.id, p.display_name AS displayName, p.hero_level AS heroLevel, p.zone,
            (SELECT COALESCE(SUM(s.steps), 0) FROM step_days s WHERE s.player_id = p.id AND s.week = ?2) AS weekSteps
     FROM players p WHERE p.id = ?1`,
  )
    .bind(invite.player_id, currentWeek())
    .first();
  return c.json({ friend });
});

friends.delete("/:friendId", async (c) => {
  const playerId = c.get("playerId");
  const friendId = c.req.param("friendId");
  await c.env.DB.batch([
    c.env.DB.prepare("DELETE FROM friendships WHERE player_id = ? AND friend_id = ?").bind(playerId, friendId),
    c.env.DB.prepare("DELETE FROM friendships WHERE player_id = ? AND friend_id = ?").bind(friendId, playerId),
  ]);
  return c.body(null, 204);
});
