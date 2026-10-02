# Stepquest API (Cloudflare Workers)

The game's backend: auth, step sync, anti-cheat, and Friends / Local / Global leaderboards.
The API contract is in [`../docs/API.md`](../docs/API.md). Balance tables are in
[`../shared/formulas.json`](../shared/formulas.json), served at `GET /v1/config`.

## Cloudflare primitives used

| Binding | Primitive | Used for |
|---|---|---|
| `DB` | D1 | Players, daily steps, friendships, invites, archived weekly results |
| `BOARD` | Durable Object (`BoardDO`, SQLite-backed) | One per leaderboard: `global\|steps\|2026-W40`, `local:US-CA-San Francisco\|level\|all`, … |
| `BOARD_CACHE` | KV | Top-100 snapshot per board, 60 s TTL |
| `STEP_QUEUE` | Queues | `POST /v1/steps` enqueues; the consumer validates, stores, flags, and updates boards |
| cron `5 0 * * 1` | Cron Triggers | Monday archive of last week's boards into `season_results` |
| `RATE_LIMITER` | Rate Limiting | 120 req/min per player |
| `ANALYTICS` | Analytics Engine | Step uploads, progress events |
| `request.cf` | — | Region for local boards (country-region-city), so no GPS permission is needed |

Friends boards are computed straight from D1 because they're small.

## Develop

```bash
npm install                     # .npmrc sets legacy-peer-deps (works around an npm peer-dep bug)
cp .dev.vars.example .dev.vars  # DEV_AUTH=true + a local JWT secret
npm run db:migrate:local
npm run dev                     # http://localhost:8787
npm test                        # Vitest inside workerd (D1, DOs, KV, Queues all local)
npm run typecheck
```

With `DEV_AUTH=true` you can log in without Apple, and fake a region with a header:
```bash
curl -X POST localhost:8787/v1/auth/dev -H 'content-type: application/json' \
  -H 'X-Debug-Region: US-CA-San Francisco' -d '{"deviceId":"my-sim","displayName":"Me"}'
```

## Deploy

```bash
npx wrangler login
npx wrangler d1 create stepquest            # paste database_id into wrangler.jsonc
npx wrangler kv namespace create BOARD_CACHE # paste id into wrangler.jsonc
npx wrangler queues create stepquest-steps
npx wrangler queues create stepquest-steps-dlq
npx wrangler secret put JWT_SECRET           # e.g. openssl rand -base64 48
npm run db:migrate:remote
npm run deploy
```
Then set `APPLE_BUNDLE_ID` to your app's bundle id and make sure `DEV_AUTH` stays `"false"`.

## Layout

```
src/index.ts             Hono app + queue + scheduled handlers
src/routes/              auth, me, steps, boards, friends
src/do/BoardDO.ts        Leaderboard Durable Object
src/queues/stepIngest.ts Step validation, anti-cheat, board updates
src/cron/weeklyReset.ts  Weekly archive
src/lib/                 auth (Apple JWKS + session JWT), boards, players, util (ISO weeks, region)
migrations/              D1 schema
test/                    Vitest (runs in workerd)
```

## Not yet built (milestone 2)
Leagues (`LeagueDO`), parties and the live World Boss (DO + WebSocket hibernation), APNs push via a
queue, R2 zone packs, App Attest verification, Workflows for season rollover.
