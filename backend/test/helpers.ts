import { createExecutionContext, createMessageBatch, env, getQueueResult, SELF } from "cloudflare:test";
import worker from "../src/index";
import type { StepUploadMessage } from "../src/env";

export const BASE = "https://api.test";

export async function api(
  method: string,
  path: string,
  opts: { token?: string; body?: unknown; region?: string } = {},
): Promise<Response> {
  const headers: Record<string, string> = {};
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  if (opts.body !== undefined) headers["Content-Type"] = "application/json";
  if (opts.region) headers["X-Debug-Region"] = opts.region;
  return SELF.fetch(`${BASE}${path}`, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
}

export async function signUp(name: string, region?: string) {
  const res = await api("POST", "/v1/auth/dev", {
    body: { deviceId: `device-${name}-${crypto.randomUUID()}`, displayName: name },
    region,
  });
  if (res.status !== 200) throw new Error(`signup failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { token: string; player: { id: string } };
  return { token: json.token, id: json.player.id };
}

/** Runs the queue consumer directly so tests don't wait on real queue batching. */
export async function deliverSteps(msg: StepUploadMessage) {
  const batch = createMessageBatch<StepUploadMessage>("stepquest-steps", [
    { id: crypto.randomUUID(), timestamp: new Date(), attempts: 1, body: msg },
  ]);
  const ctx = createExecutionContext();
  await worker.queue(batch, env);
  return getQueueResult(batch, ctx);
}

export const today = () => new Date().toISOString().slice(0, 10);
export const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString().slice(0, 10);
