import { Hono } from "hono";
import type { AppEnv, Env } from "../env";
import { issueSession, verifyAppleIdentityToken } from "../lib/auth";
import { cleanDisplayName, type PlayerRow, toPlayer } from "../lib/players";
import { apiError, newPlayerId, nowIso, regionFromRequest } from "../lib/util";

export const auth = new Hono<AppEnv>();

type IdentityColumn = "apple_sub" | "dev_device_id";

async function findOrCreatePlayer(
  env: Env,
  column: IdentityColumn,
  identity: string,
  displayName: string | null,
  region: string | null,
): Promise<PlayerRow> {
  const existing = await env.DB.prepare(`SELECT * FROM players WHERE ${column} = ?`)
    .bind(identity)
    .first<PlayerRow>();
  if (existing) return existing;

  // INSERT OR IGNORE + reselect handles two first-time sign-ins racing each other.
  await env.DB.prepare(
    `INSERT OR IGNORE INTO players (id, ${column}, display_name, region, created_at) VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(newPlayerId(), identity, displayName ?? "Wanderer", region, nowIso())
    .run();
  return (await env.DB.prepare(`SELECT * FROM players WHERE ${column} = ?`)
    .bind(identity)
    .first<PlayerRow>())!;
}

auth.post("/apple", async (c) => {
  const body: { identityToken?: unknown; displayName?: unknown } = await c.req.json().catch(() => ({}));
  if (typeof body.identityToken !== "string") {
    throw apiError(400, "invalid_request", "identityToken is required");
  }
  const sub = await verifyAppleIdentityToken(c.env, body.identityToken);
  const region = regionFromRequest(c.req.raw, c.env.DEV_AUTH === "true");
  const player = await findOrCreatePlayer(c.env, "apple_sub", sub, cleanDisplayName(body.displayName), region);
  return c.json({ token: await issueSession(c.env, player.id), player: toPlayer(player) });
});

auth.post("/dev", async (c) => {
  if (c.env.DEV_AUTH !== "true") throw apiError(404, "not_found", "Not found");
  const body: { deviceId?: unknown; displayName?: unknown } = await c.req.json().catch(() => ({}));
  if (typeof body.deviceId !== "string" || body.deviceId.length < 4 || body.deviceId.length > 128) {
    throw apiError(400, "invalid_request", "deviceId (4-128 chars) is required");
  }
  const region = regionFromRequest(c.req.raw, true);
  const player = await findOrCreatePlayer(c.env, "dev_device_id", body.deviceId, cleanDisplayName(body.displayName), region);
  return c.json({ token: await issueSession(c.env, player.id), player: toPlayer(player) });
});
