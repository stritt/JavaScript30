import { DurableObject } from "cloudflare:workers";
import type { Env } from "../env";

export interface BoardEntryInput {
  playerId: string;
  displayName: string;
  value: number;
  heroLevel: number;
}

export interface BoardEntry {
  rank: number;
  playerId: string;
  displayName: string;
  value: number;
  heroLevel: number;
}

export type Metric = "steps" | "level" | "zone";

/**
 * Durable Object name for a leaderboard.
 * Weekly steps boards are per ISO week; level/zone boards are all-time.
 *   global|steps|2026-W40   local:US-CA-San Francisco|level|all
 */
export function boardName(scope: string, metric: Metric, week: string): string {
  return `${scope}|${metric}|${metric === "steps" ? week : "all"}`;
}

/**
 * One leaderboard. Keeps entries in the DO's SQLite storage with an index on value,
 * so upserts and rank lookups are O(log n) and strongly consistent.
 */
export class BoardDO extends DurableObject<Env> {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS entries (
        player_id    TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        value        INTEGER NOT NULL,
        hero_level   INTEGER NOT NULL,
        updated_at   INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_entries_value ON entries(value DESC, updated_at ASC);
    `);
  }

  upsert(e: BoardEntryInput): void {
    this.sql.exec(
      `INSERT INTO entries (player_id, display_name, value, hero_level, updated_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(player_id) DO UPDATE SET
         display_name = excluded.display_name,
         hero_level   = excluded.hero_level,
         -- Ties are broken by who got there first, so only bump the timestamp when the value changes.
         updated_at   = CASE WHEN value != excluded.value THEN excluded.updated_at ELSE updated_at END,
         value        = excluded.value`,
      e.playerId,
      e.displayName,
      Math.max(0, Math.floor(e.value)),
      e.heroLevel,
      Date.now(),
    );
  }

  remove(playerId: string): void {
    this.sql.exec("DELETE FROM entries WHERE player_id = ?", playerId);
  }

  top(limit: number): BoardEntry[] {
    const rows = this.sql
      .exec<{ player_id: string; display_name: string; value: number; hero_level: number }>(
        `SELECT player_id, display_name, value, hero_level FROM entries
         WHERE value > 0 ORDER BY value DESC, updated_at ASC LIMIT ?`,
        limit,
      )
      .toArray();
    return rows.map((r, i) => ({
      rank: i + 1,
      playerId: r.player_id,
      displayName: r.display_name,
      value: r.value,
      heroLevel: r.hero_level,
    }));
  }

  rankOf(playerId: string): { rank: number; value: number } | null {
    const me = this.sql
      .exec<{ value: number; updated_at: number }>(
        "SELECT value, updated_at FROM entries WHERE player_id = ?",
        playerId,
      )
      .toArray()[0];
    if (!me || me.value <= 0) return null;
    const ahead = this.sql
      .exec<{ n: number }>(
        "SELECT COUNT(*) AS n FROM entries WHERE value > ? OR (value = ? AND updated_at < ?)",
        me.value,
        me.value,
        me.updated_at,
      )
      .one().n;
    return { rank: ahead + 1, value: me.value };
  }

  size(): number {
    return this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM entries").one().n;
  }

  /** Drops all data. Used by the weekly cron after archiving a finished week. */
  clear(): void {
    this.sql.exec("DELETE FROM entries");
  }
}
