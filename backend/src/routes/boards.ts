import { Hono } from "hono";
import type { AppEnv, Env } from "../env";
import { boardName, type Metric } from "../do/BoardDO";
import { boardStub, cachedTop, globalScope, localScope, METRICS } from "../lib/boards";
import { type PlayerRow, requirePlayer } from "../lib/players";
import { apiError, currentWeek } from "../lib/util";

export const boards = new Hono<AppEnv>();

interface Entry {
  rank: number;
  playerId: string;
  displayName: string;
  value: number;
  heroLevel: number;
  isMe: boolean;
}

boards.get("/:scope", async (c) => {
  const scope = c.req.param("scope");
  const metric = (c.req.query("metric") ?? "steps") as Metric;
  if (!METRICS.includes(metric)) throw apiError(400, "invalid_request", `metric must be one of ${METRICS.join(", ")}`);

  const me = await requirePlayer(c.env, c.get("playerId"));
  const week = currentWeek();

  if (scope === "friends") {
    const entries = await friendsBoard(c.env, me, metric, week);
    const mine = entries.find((e) => e.isMe);
    return c.json({
      scope, metric, week, region: null, entries,
      me: mine && mine.value > 0 && !me.flagged ? { rank: mine.rank, value: mine.value } : null,
    });
  }

  let boardScope: string;
  if (scope === "global") {
    boardScope = globalScope();
  } else if (scope === "local") {
    if (me.local_opt_in !== 1) throw apiError(409, "local_opt_in_required", "Opt in to local boards first");
    if (!me.region) throw apiError(409, "region_unknown", "We couldn't work out your region yet");
    boardScope = localScope(me.region);
  } else {
    throw apiError(404, "not_found", "scope must be friends, local or global");
  }

  const name = boardName(boardScope, metric, week);
  const [top, rank] = await Promise.all([cachedTop(c.env, name), boardStub(c.env, name).rankOf(me.id)]);
  return c.json({
    scope, metric, week,
    region: scope === "local" ? me.region : null,
    entries: top.map((e) => ({ ...e, isMe: e.playerId === me.id })),
    me: rank,
  });
});

/** Friends boards are small, so they're computed straight from D1 instead of a Durable Object. */
async function friendsBoard(env: Env, me: PlayerRow, metric: Metric, week: string): Promise<Entry[]> {
  const valueSql =
    metric === "steps"
      ? "(SELECT COALESCE(SUM(s.steps), 0) FROM step_days s WHERE s.player_id = p.id AND s.week = ?1)"
      : metric === "level"
        ? "p.hero_level"
        : "p.zone";
  const { results } = await env.DB.prepare(
    `SELECT p.id, p.display_name, p.hero_level, ${valueSql} AS value
     FROM players p
     WHERE (p.id = ?2 OR p.id IN (SELECT friend_id FROM friendships WHERE player_id = ?2))
       AND (p.flagged = 0 OR p.id = ?2)
     ORDER BY value DESC, p.display_name ASC`,
  )
    .bind(week, me.id)
    .all<{ id: string; display_name: string; hero_level: number; value: number }>();

  return results.map((r, i) => ({
    rank: i + 1,
    playerId: r.id,
    displayName: r.display_name,
    value: r.value,
    heroLevel: r.hero_level,
    isMe: r.id === me.id,
  }));
}
