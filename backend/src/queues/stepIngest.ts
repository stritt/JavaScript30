import type { Env, StepUploadMessage } from "../env";
import formulas from "../../../shared/formulas.json";
import { syncPlayerBoards } from "../lib/boards";
import { getPlayer } from "../lib/players";
import { isoWeek, nowIso, parseDay } from "../lib/util";

const { maxStepsPerDay, flagStepsPerDay } = formulas.integrity;

/**
 * Validates uploaded step totals, stores them, and refreshes the player's boards.
 * Days above `flagStepsPerDay` flag the player (they drop off public boards but keep playing).
 * Values are clamped to `maxStepsPerDay` so one bad upload can't poison stored history.
 */
export async function ingestSteps(env: Env, msg: StepUploadMessage): Promise<void> {
  const player = await getPlayer(env, msg.playerId);
  if (!player) return; // Deleted account; drop the message.

  const weeks = new Set<string>();
  let suspicious = false;
  const stmts: D1PreparedStatement[] = [];

  for (const { day, steps, flights } of msg.days) {
    const date = parseDay(day);
    if (!date) continue;
    if (steps > flagStepsPerDay) suspicious = true;
    const week = isoWeek(date);
    weeks.add(week);
    stmts.push(
      env.DB.prepare(
        `INSERT INTO step_days (player_id, day, week, steps, flights, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(player_id, day) DO UPDATE SET
           steps = MAX(steps, excluded.steps),
           flights = MAX(flights, excluded.flights),
           updated_at = excluded.updated_at`,
      ).bind(player.id, day, week, Math.min(steps, maxStepsPerDay), Math.min(flights, maxStepsPerDay), nowIso()),
    );
  }

  if (suspicious && player.flagged === 0) {
    stmts.push(env.DB.prepare("UPDATE players SET flagged = 1 WHERE id = ?").bind(player.id));
    player.flagged = 1;
  }
  if (stmts.length > 0) await env.DB.batch(stmts);

  await syncPlayerBoards(env, player, [...weeks]);

  const total = msg.days.reduce((sum, d) => sum + d.steps, 0);
  env.ANALYTICS?.writeDataPoint({
    blobs: ["steps", player.id, suspicious ? "flagged" : "ok"],
    doubles: [total, msg.days.length],
    indexes: [player.id],
  });
}

export async function handleStepBatch(batch: MessageBatch<StepUploadMessage>, env: Env): Promise<void> {
  for (const message of batch.messages) {
    try {
      await ingestSteps(env, message.body);
      message.ack();
    } catch (err) {
      console.error("step ingest failed", message.id, err);
      message.retry({ delaySeconds: 10 });
    }
  }
}
