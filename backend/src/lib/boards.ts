import type { Env } from "../env";
import { boardName, type BoardEntry, type Metric } from "../do/BoardDO";
import { type PlayerRow, weekSteps } from "./players";
import { currentWeek } from "./util";

export const METRICS: Metric[] = ["steps", "level", "zone"];
export const TOP_N = 100;
const CACHE_TTL_SECONDS = 60; // KV minimum

export const globalScope = () => "global";
export const localScope = (region: string) => `local:${region}`;

export const boardStub = (env: Env, name: string) => env.BOARD.get(env.BOARD.idFromName(name));

/** Scopes a player belongs to right now. */
function scopesFor(player: PlayerRow): string[] {
  const scopes = [globalScope()];
  if (player.local_opt_in === 1 && player.region) scopes.push(localScope(player.region));
  return scopes;
}

/**
 * Writes the player's current values onto every board they belong to.
 * Flagged players are removed instead. `weeks` lists the step weeks touched by an upload.
 */
export async function syncPlayerBoards(env: Env, player: PlayerRow, weeks: string[] = [currentWeek()]) {
  const scopes = scopesFor(player);
  const ops: Promise<unknown>[] = [];

  if (player.flagged === 1) {
    for (const scope of scopes) for (const name of boardNames(scope, weeks)) {
      ops.push(boardStub(env, name).remove(player.id));
    }
    await Promise.all(ops);
    return;
  }

  const base = { playerId: player.id, displayName: player.display_name, heroLevel: player.hero_level };
  const stepTotals = await Promise.all(weeks.map((w) => weekSteps(env, player.id, w)));

  for (const scope of scopes) {
    weeks.forEach((week, i) => {
      ops.push(boardStub(env, boardName(scope, "steps", week)).upsert({ ...base, value: stepTotals[i] }));
    });
    ops.push(boardStub(env, boardName(scope, "level", "all")).upsert({ ...base, value: player.hero_level }));
    ops.push(boardStub(env, boardName(scope, "zone", "all")).upsert({ ...base, value: player.zone }));
  }
  await Promise.all(ops);
}

/** Removes a player from one region's local boards (used on opt-out or when they move). */
export async function leaveLocalBoards(env: Env, playerId: string, region: string) {
  await Promise.all(
    boardNames(localScope(region), [currentWeek()]).map((name) => boardStub(env, name).remove(playerId)),
  );
}

function boardNames(scope: string, weeks: string[]): string[] {
  return [
    ...weeks.map((w) => boardName(scope, "steps", w)),
    boardName(scope, "level", "all"),
    boardName(scope, "zone", "all"),
  ];
}

/** Top-N for a board, cached in KV for a minute so hot boards don't hammer one Durable Object. */
export async function cachedTop(env: Env, name: string): Promise<BoardEntry[]> {
  const key = `top:${name}`;
  const cached = await env.BOARD_CACHE.get<BoardEntry[]>(key, "json");
  if (cached) return cached;
  const entries = await boardStub(env, name).top(TOP_N);
  await env.BOARD_CACHE.put(key, JSON.stringify(entries), { expirationTtl: CACHE_TTL_SECONDS });
  return entries;
}
