import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";

export function apiError(status: ContentfulStatusCode, error: string, message: string): HTTPException {
  return new HTTPException(status, {
    res: Response.json({ error, message }, { status }),
  });
}

const ID_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz";
// No 0/O/1/I/L so codes are easy to read aloud and type.
const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";

function randomString(alphabet: string, length: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  let out = "";
  for (const b of bytes) out += alphabet[b % alphabet.length];
  return out;
}

export const newPlayerId = () => `p_${randomString(ID_ALPHABET, 20)}`;
export const newInviteCode = () => randomString(CODE_ALPHABET, 6);

export const nowIso = () => new Date().toISOString();

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** Parses YYYY-MM-DD as a UTC date, or returns null if malformed or not a real date. */
export function parseDay(day: string): Date | null {
  if (!DAY_RE.test(day)) return null;
  const d = new Date(`${day}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== day) return null;
  return d;
}

/** ISO-8601 week key (e.g. "2026-W40") for a UTC date. Weeks start Monday. */
export function isoWeek(date: Date): string {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum); // Thursday of this week decides the year
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((d.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

export const currentWeek = (now = new Date()) => isoWeek(now);
export const previousWeek = (now = new Date()) => isoWeek(new Date(now.getTime() - 7 * 86_400_000));

/** Coarse location from Cloudflare's request.cf: "US-CA-San Francisco". Never finer than city. */
export function regionFromRequest(req: Request, allowDebugHeader: boolean): string | null {
  if (allowDebugHeader) {
    const debug = req.headers.get("X-Debug-Region");
    if (debug) return debug;
  }
  const cf = (req as Request & { cf?: IncomingRequestCfProperties }).cf;
  if (!cf?.country) return null;
  return [cf.country, cf.regionCode, cf.city].filter(Boolean).join("-");
}
