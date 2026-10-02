import type { Env } from "../env";
import { boardName } from "../do/BoardDO";
import { boardStub, globalScope, localScope } from "../lib/boards";
import { previousWeek } from "../lib/util";

const ARCHIVE_GLOBAL = 100;
const ARCHIVE_LOCAL = 10;

/**
 * Runs Monday 00:05 UTC. Archives last week's steps standings to D1 (`season_results`)
 * and empties those Durable Objects. New weeks start automatically because steps boards
 * are keyed by ISO week, so nothing has to be "reset" for play to continue.
 */
export async function archiveWeek(env: Env, week = previousWeek()): Promise<{ boards: number; rows: number }> {
  const { results: regions } = await env.DB.prepare(
    "SELECT DISTINCT region FROM players WHERE local_opt_in = 1 AND region IS NOT NULL",
  ).all<{ region: string }>();

  const targets = [
    { scope: globalScope(), keep: ARCHIVE_GLOBAL },
    ...regions.map((r) => ({ scope: localScope(r.region), keep: ARCHIVE_LOCAL })),
  ];

  let rows = 0;
  for (const { scope, keep } of targets) {
    const name = boardName(scope, "steps", week);
    const stub = boardStub(env, name);
    const top = await stub.top(keep);
    if (top.length > 0) {
      await env.DB.batch(
        top.map((e) =>
          env.DB.prepare(
            "INSERT OR REPLACE INTO season_results (week, board, player_id, rank, value) VALUES (?, ?, ?, ?, ?)",
          ).bind(week, `${scope}|steps`, e.playerId, e.rank, e.value),
        ),
      );
      rows += top.length;
    }
    await stub.clear();
    await env.BOARD_CACHE.delete(`top:${name}`);
  }
  return { boards: targets.length, rows };
}
