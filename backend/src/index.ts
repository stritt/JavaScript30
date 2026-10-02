import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import type { AppEnv, Env, StepUploadMessage } from "./env";
import formulas from "../../shared/formulas.json";
import { requireAuth } from "./lib/auth";
import { auth } from "./routes/auth";
import { boards } from "./routes/boards";
import { friends } from "./routes/friends";
import { me } from "./routes/me";
import { steps } from "./routes/steps";
import { handleStepBatch } from "./queues/stepIngest";
import { archiveWeek } from "./cron/weeklyReset";

export { BoardDO } from "./do/BoardDO";

const app = new Hono<AppEnv>();

app.get("/", (c) => c.json({ name: "stepquest-api", ok: true }));

app.get("/v1/config", (c) => {
  c.header("Cache-Control", "public, max-age=300");
  return c.json(formulas);
});

app.route("/v1/auth", auth);

app.use("/v1/me/*", requireAuth);
app.use("/v1/me", requireAuth);
app.use("/v1/steps/*", requireAuth);
app.use("/v1/steps", requireAuth);
app.use("/v1/boards/*", requireAuth);
app.use("/v1/friends/*", requireAuth);
app.use("/v1/friends", requireAuth);

app.route("/v1/me", me);
app.route("/v1/steps", steps);
app.route("/v1/boards", boards);
app.route("/v1/friends", friends);

app.notFound((c) => c.json({ error: "not_found", message: "Not found" }, 404));

app.onError((err, c) => {
  if (err instanceof HTTPException) return err.getResponse();
  console.error(err);
  return c.json({ error: "internal", message: "Something went wrong" }, 500);
});

export default {
  fetch: app.fetch,
  queue: (batch: MessageBatch<StepUploadMessage>, env: Env) => handleStepBatch(batch, env),
  scheduled: (_controller: ScheduledController, env: Env, ctx: ExecutionContext) => {
    ctx.waitUntil(archiveWeek(env).then((r) => console.log("archived week", r)));
  },
} satisfies ExportedHandler<Env, StepUploadMessage>;
