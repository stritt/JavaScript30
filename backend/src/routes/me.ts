import { Hono } from "hono";
import type { AppEnv } from "../env";
import { leaveLocalBoards, syncPlayerBoards } from "../lib/boards";
import { cleanDisplayName, requirePlayer, toPlayer, weekSteps } from "../lib/players";
import { apiError, currentWeek, regionFromRequest } from "../lib/util";

export const me = new Hono<AppEnv>();

const MAX_LEVEL = 99;
const MAX_ZONE = 999;

me.get("/", async (c) => {
  const player = await requirePlayer(c.env, c.get("playerId"));
  const week = currentWeek();
  return c.json({ player: toPlayer(player), week, weekSteps: await weekSteps(c.env, player.id, week) });
});

me.patch("/", async (c) => {
  const playerId = c.get("playerId");
  const before = await requirePlayer(c.env, playerId);
  const body = await c.req
    .json<{ displayName?: unknown; localOptIn?: unknown; heroLevel?: unknown; zone?: unknown }>()
    .catch(() => null);
  if (!body || typeof body !== "object") throw apiError(400, "invalid_request", "JSON body required");

  let displayName = before.display_name;
  if (body.displayName !== undefined) {
    const cleaned = cleanDisplayName(body.displayName);
    if (!cleaned) throw apiError(400, "invalid_request", "displayName must be 1-24 visible characters");
    displayName = cleaned;
  }

  let localOptIn = before.local_opt_in;
  if (body.localOptIn !== undefined) {
    if (typeof body.localOptIn !== "boolean") throw apiError(400, "invalid_request", "localOptIn must be boolean");
    localOptIn = body.localOptIn ? 1 : 0;
  }

  // Progress only moves forward; a reinstall or stale client can't drag you down the board.
  const heroLevel = clampProgress(body.heroLevel, before.hero_level, MAX_LEVEL, "heroLevel");
  const zone = clampProgress(body.zone, before.zone, MAX_ZONE, "zone");
  const region = regionFromRequest(c.req.raw, c.env.DEV_AUTH === "true") ?? before.region;

  await c.env.DB.prepare(
    "UPDATE players SET display_name = ?, local_opt_in = ?, hero_level = ?, zone = ?, region = ? WHERE id = ?",
  )
    .bind(displayName, localOptIn, heroLevel, zone, region, playerId)
    .run();

  const after = await requirePlayer(c.env, playerId);
  const leftRegion = before.local_opt_in === 1 && before.region && (after.local_opt_in === 0 || after.region !== before.region);
  if (leftRegion) await leaveLocalBoards(c.env, playerId, before.region!);
  await syncPlayerBoards(c.env, after);

  c.env.ANALYTICS?.writeDataPoint({ blobs: ["progress", playerId], doubles: [heroLevel, zone], indexes: [playerId] });
  return c.json({ player: toPlayer(after) });
});

function clampProgress(input: unknown, current: number, max: number, field: string): number {
  if (input === undefined) return current;
  if (typeof input !== "number" || !Number.isInteger(input) || input < 1) {
    throw apiError(400, "invalid_request", `${field} must be a positive integer`);
  }
  return Math.max(current, Math.min(input, max));
}
