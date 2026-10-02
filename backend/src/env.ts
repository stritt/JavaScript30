import type { BoardDO } from "./do/BoardDO";

export interface StepUploadMessage {
  playerId: string;
  days: { day: string; steps: number; flights: number }[];
  receivedAt: string;
}

export interface Env {
  DB: D1Database;
  BOARD_CACHE: KVNamespace;
  BOARD: DurableObjectNamespace<BoardDO>;
  STEP_QUEUE: Queue<StepUploadMessage>;
  RATE_LIMITER?: RateLimit;
  ANALYTICS?: AnalyticsEngineDataset;

  APPLE_BUNDLE_ID: string;
  INVITE_BASE_URL: string;
  DEV_AUTH: string;
  JWT_SECRET: string;
}

export interface Variables {
  playerId: string;
}

export type AppEnv = { Bindings: Env; Variables: Variables };
