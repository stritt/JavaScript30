import { Hono } from "hono";
import type { AppEnv, StepUploadMessage } from "../env";
import formulas from "../../../shared/formulas.json";
import { apiError, nowIso, parseDay } from "../lib/util";

export const steps = new Hono<AppEnv>();

const MAX_DAYS_PER_REQUEST = 31;
const DAY_MS = 86_400_000;

steps.post("/", async (c) => {
  const body = await c.req.json<{ days?: unknown }>().catch(() => null);
  if (!body || !Array.isArray(body.days) || body.days.length === 0) {
    throw apiError(400, "invalid_request", "days must be a non-empty array");
  }
  if (body.days.length > MAX_DAYS_PER_REQUEST) {
    throw apiError(400, "invalid_request", `At most ${MAX_DAYS_PER_REQUEST} days per request`);
  }

  const now = Date.now();
  // Local dates can be up to a day ahead of UTC (UTC+14), hence the +1 day allowance.
  const latest = now + DAY_MS;
  const earliest = now - (formulas.integrity.maxPastDays + 1) * DAY_MS;

  const days: StepUploadMessage["days"] = [];
  const seen = new Set<string>();
  for (const raw of body.days as unknown[]) {
    const d = raw as { day?: unknown; steps?: unknown; flights?: unknown };
    const date = typeof d.day === "string" ? parseDay(d.day) : null;
    if (!date) throw apiError(400, "invalid_request", "day must be YYYY-MM-DD");
    if (date.getTime() > latest) throw apiError(400, "invalid_request", `${d.day} is in the future`);
    if (date.getTime() < earliest) throw apiError(400, "invalid_request", `${d.day} is too old`);
    if (!isCount(d.steps)) throw apiError(400, "invalid_request", "steps must be a non-negative integer");
    if (d.flights !== undefined && !isCount(d.flights)) {
      throw apiError(400, "invalid_request", "flights must be a non-negative integer");
    }
    if (seen.has(d.day as string)) throw apiError(400, "invalid_request", `Duplicate day ${d.day}`);
    seen.add(d.day as string);
    days.push({ day: d.day as string, steps: d.steps as number, flights: (d.flights as number | undefined) ?? 0 });
  }

  await c.env.STEP_QUEUE.send({ playerId: c.get("playerId"), days, receivedAt: nowIso() });
  return c.json({ accepted: days.length }, 202);
});

const isCount = (v: unknown): v is number => typeof v === "number" && Number.isInteger(v) && v >= 0;
