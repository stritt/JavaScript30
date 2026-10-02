# Stepquest API v1

Base URL: `https://api.stepquest.app` (dev: `http://localhost:8787`). All bodies are JSON.
Authenticated routes need `Authorization: Bearer <session token>`.

Errors use `{ "error": "<code>", "message": "<human text>" }` with a matching HTTP status.

## Auth

### `POST /v1/auth/apple`
Exchange a Sign in with Apple identity token for a session.
```json
{ "identityToken": "<JWT from ASAuthorizationAppleIDCredential>", "displayName": "Brandon" }
```
→ `200`
```json
{ "token": "<session JWT, 30 days>", "player": Player }
```

### `POST /v1/auth/dev`
Dev/test only (enabled when `DEV_AUTH=true`). Same response as `/auth/apple`.
```json
{ "deviceId": "any-stable-string", "displayName": "Tester" }
```

## Player

`Player`:
```json
{
  "id": "p_…",
  "displayName": "Brandon",
  "heroLevel": 7,
  "zone": 2,
  "region": "US-CA-San Francisco",
  "localOptIn": true,
  "flagged": false,
  "createdAt": "2026-10-02T12:00:00Z"
}
```

### `GET /v1/me` → `{ "player": Player, "week": "2026-W40", "weekSteps": 41234 }`

### `PATCH /v1/me`
Update profile and report game progress. All fields optional.
```json
{ "displayName": "Bran", "localOptIn": true, "heroLevel": 8, "zone": 2 }
```
→ `{ "player": Player }`. `heroLevel` is clamped to 1–99 and `zone` to 1 or more. Neither may decrease.
The region is refreshed from Cloudflare's `request.cf` (country, region, city) on every call.

## Steps

### `POST /v1/steps`
Upload daily totals from HealthKit. Re-uploading a day is safe: the server keeps the max per day.
Exclude user-entered samples (`HKMetadataKeyWasUserEntered`) on device before summing.
```json
{
  "days": [
    { "day": "2026-10-01", "steps": 8123, "flights": 4 },
    { "day": "2026-10-02", "steps": 3011, "flights": 1 }
  ]
}
```
→ `202 { "accepted": 2 }`. Validation and leaderboard updates happen asynchronously (Queue).
Rejects: `day` not `YYYY-MM-DD`, more than 1 day in the future, older than 7 days, `steps` < 0,
or more than 31 days in one request.

## Leaderboards

### `GET /v1/boards/:scope?metric=steps`
`scope` = `global` | `local` | `friends`. `metric` = `steps` (weekly) | `level` | `zone`.
```json
{
  "scope": "local",
  "metric": "steps",
  "week": "2026-W40",
  "region": "US-CA-San Francisco",
  "entries": [
    { "rank": 1, "playerId": "p_…", "displayName": "Ava", "value": 70211, "heroLevel": 14, "isMe": false }
  ],
  "me": { "rank": 12, "value": 41234 }
}
```
`local` requires `localOptIn` and returns `409 local_opt_in_required` otherwise.
`me` is `null` when the player isn't ranked (no steps yet, or flagged).
Weeks are ISO weeks (Monday 00:00 UTC).

## Friends

### `POST /v1/friends/invite` → `{ "code": "K7QF2M", "url": "https://stepquest.app/i/K7QF2M", "expiresAt": "…" }`
### `POST /v1/friends/accept` `{ "code": "K7QF2M" }` → `{ "friend": FriendSummary }`
### `GET /v1/friends` → `{ "friends": [FriendSummary] }`
### `DELETE /v1/friends/:playerId` → `204`

`FriendSummary`: `{ "id", "displayName", "heroLevel", "zone", "weekSteps" }`

## Config

### `GET /v1/config` → contents of `shared/formulas.json` (public, cacheable)
