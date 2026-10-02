# Stepforge — Game Design (v0 draft)

*Working title.* An idle RPG for iPhone where your real-world steps power your hero.
It progresses without you, but slowly, and real steps are what get you past the walls.

---

## 1. The market: who's already doing this

The niche is real and crowded. You can't win by being "steps → XP" alone.

| App | What it does | Gap we can exploit |
|---|---|---|
| **PaceQuest** | Idle pedometer RPG. Steps become energy that levels the hero and fights enemies. Game Center leaderboard. | Solo only, single global board |
| **Fitness RPG: Hero Health Game** | Steps become energy for heroes. PvP arena. HealthKit. | Gacha/F2P heavy, dated feel |
| **WalkScape** | RuneScape-like. Walking progresses 15+ skills. | Deep but slow. No real-time play |
| **Pacecraft** (Jun 2026) | Step challenges, monthly leagues, city-builder | City-builder, not combat RPG |
| **Prado Traveler** | Steps make heroes stronger. Friends, monsters | No live mode |
| **Tough Talk** | Step leaderboards, rival battles | Mostly competitive tracker |
| **Steps & Beasts** | Hatch creatures from step goals | Collector, not RPG |

**What nobody does well (our pitch):**
1. **Live Stride Mode.** Open the app and walk. Your *cadence* drives combat in real time.
2. **Step Gates.** A hard "you're stuck" mechanic. Idle progress stalls until you physically walk.
3. **Local leaderboards** (your city or neighborhood). None of the competitors have them.
4. **Co-op raids.** Friends pool steps against a weekly World Boss.
5. **More than steps.** Flights climbed, exercise minutes and sleep each feed a different system.

---

## 2. Core loop

```
 Real steps (HealthKit) ──► Stride Energy ──► Hero walks the Trail
                                              │
                    ┌─────────────────────────┼──────────────────────┐
                    ▼                         ▼                      ▼
            Auto-battles monsters      Loot / gold / XP       Reaches a Step Gate
                    │                         │                      │
                    └──► Level up, gear up ◄──┘          Needs N real steps to break
                                                                    │
                                                    Walk ──► Unlock next Zone
```

### Idle (app closed)
- The hero always moves forward at a **base trickle** of 1 tile per minute, even with zero steps.
- Real steps add **Stride Energy**: 1 step = 1 energy. Energy is spent automatically to move faster and fight harder.
- Offline progress is simulated on launch: `elapsed time + steps since last sync`.
- Idle earnings cap at 12h so the app still wants to be opened.

### Step Gates ("you get stuck")
- Each zone ends in a **Gate Guardian** with a *real-steps* HP bar, e.g. "deal 25,000 steps of damage."
- Only steps taken *after the gate is reached* count. Idle trickle does 0 damage.
- Gates scale with zone, but always stay within ~1–3 days of normal walking. Hard, not punishing.
- Grinding earlier zones still gives loot and XP, so stuck players aren't bored.

### Stride Mode (active play, app open)
- Uses **CoreMotion `CMPedometer`** for live cadence (steps per minute).
- The hero's attack speed is tied to your cadence:
  - < 60 spm: Stroll, 1× damage
  - 60–100 spm: March, 2×
  - 100–130 spm: Rush, 3× plus combo meter
  - 130+ spm: Frenzy, 4× plus crits
- Tap-to-cast skills charge from steps. You can play one-handed while walking.
- Stride Mode steps count **1.5×** toward Gate damage, which rewards walks taken *with* the app.
- Haptics on hits, kills and level-ups. Optional audio callouts for eyes-free play.
- A **Live Activity / Dynamic Island** shows HP, cadence tier and the kill counter with the phone locked.
- Safety: a pause banner and a "look up!" nudge. Nothing requires constant screen attention.

---

## 3. Progression systems

| System | Fed by | Notes |
|---|---|---|
| **Hero level / XP** | Kills (idle + Stride) | Classic stat growth |
| **Gear** | Loot drops | 5 rarities. Set bonuses tied to walking habits |
| **Zones** | Breaking Step Gates | Meadow → Forest → Desert → Peaks → Abyss … |
| **Tower** | **Flights climbed** (HealthKit) | Side dungeon. 1 flight = 1 floor |
| **Training** | **Exercise minutes** | Permanent stat points |
| **Rest bonus** | **Sleep hours** | 7h+ gives +20% XP next day. Optional |
| **Companions/Pets** | Hatch eggs by distance walked | Passive buffs. Cosmetic flex |
| **Streaks** | Daily step goal hit | Streak freezes earned, never sold |
| **Daily / weekly quests** | "Walk 3k before noon", "Win 3 Rush combos" | Light structure |

### Classes (pick at start, respec later)
- **Ranger**: bonus from total steps. The generalist.
- **Monk**: bonus from Stride Mode cadence. For active players.
- **Climber**: bonus from flights climbed.
- **Pilgrim**: bonus from long continuous walks (20+ min sessions).

---

## 4. Social and leaderboards

### Boards
| Scope | Source | Metrics |
|---|---|---|
| **Friends** | Our own friend graph: invite links/codes, plus optional Game Center friend import | Weekly steps, hero level, deepest zone |
| **Local** | Opt-in. Region comes from Cloudflare's `request.cf` (city/region) or a ~5 km geohash. Never exact location | Weekly steps, zone |
| **Global** | Everyone | Weekly steps, level, gate speed-run times |

All boards are served from our Cloudflare backend (see §6), not Game Center. That way friends, local and
global boards, leagues and parties all share one data model.

- **Weekly Leagues.** Groups of 30 similar players, Bronze → Mythic, promotion and relegation.
  This keeps competition fair. A 4k-steps-a-day player isn't up against marathoners.
- Boards reset weekly. All-time is shown as a secondary tab.

### Co-op
- **Parties** of up to 6 friends.
- **World Boss** every week: the party's combined real steps fight it. Loot scales with contribution.
- **Nudge / cheer.** Send a friend a "cheer" that gives them +5% energy for an hour.

---

## 5. Integrity (anti-cheat)

Leaderboards are meaningless if people shake their phones or type in 100k steps.
- Ignore HealthKit samples with `HKMetadataKeyWasUserEntered`.
- Prefer steps from iPhone or Apple Watch sources and flag third-party sources.
- Cap plausible rate (e.g., >250 spm sustained gets flagged) and use a daily sanity ceiling.
- Server validates weekly totals. Outliers go to a "verified-only" board instead of being banned.
- **Apple App Attest** proves requests come from a genuine app install. A Worker verifies the attestation.
- Step uploads go through a **Cloudflare Queue** consumer that runs the plausibility checks before
  anything reaches a leaderboard. Rate limiting uses the **Workers Rate Limiting** binding.

---

## 6. Tech plan

The rule is **Cloudflare for everything server-side**. Apple frameworks are used only where they're the
only way to reach the device: HealthKit, CoreMotion, push notifications and App Attest.

### 6a. iOS client

| Concern | Choice |
|---|---|
| UI | **SwiftUI**, iOS 17+ |
| Game scene | **SpriteKit** inside SwiftUI (`SpriteView`) for the trail and battles |
| Steps (history) | **HealthKit** `HKStatisticsCollectionQuery` with `HKObserverQuery` and background delivery |
| Steps (live) | **CoreMotion** `CMPedometer` for real-time cadence in Stride Mode |
| Local persistence | **SwiftData**. The game simulates offline, and the server is the source of truth for anything competitive |
| Auth | **Sign in with Apple**. The identity token is exchanged with our Worker for a session JWT |
| Widgets / live play | WidgetKit, plus an ActivityKit Live Activity during Stride Mode |
| Assets | Sprite atlases and zone packs downloaded from **R2** behind the CDN, so new zones ship without an App Store release |
| Later | Apple Watch companion |

### 6b. Cloudflare backend

```
 iOS app ──HTTPS / WebSocket──►  Worker: api (Hono router)
                                   │
   ┌──────────────┬────────────────┼──────────────────┬─────────────────┬───────────────┐
   ▼              ▼                ▼                  ▼                 ▼               ▼
  D1            KV            Durable Objects       Queues             R2         Analytics Engine
 players,     hot board      LeagueDO (30 ppl,    step-ingest ──►    sprites,      step / session
 friends,     snapshots,     live ranks)          anti-cheat         zone packs,   telemetry,
 step_days,   config,        PartyDO (party +     consumer           avatars       balancing
 inventory,   feature flags  World Boss HP,       push-fanout ──►
 leagues                     WebSocket fan-out)   APNs sender
                             BoardDO (per region/
                             global sorted set)
                                   ▲
                       Cron Triggers: weekly reset, league
                       promotion/relegation, World Boss spawn
```

| Need | Cloudflare primitive | Notes |
|---|---|---|
| API | **Workers** (TypeScript + Hono) | One `api` Worker. Stateless |
| Relational data | **D1** | Players, friendships, daily step totals, inventory, league membership |
| Live leaderboards | **Durable Objects** | One `BoardDO` per scope (`global`, `region:<code>`, `friends:<player>` computed on read). Keeps an in-memory sorted top-N and persists to DO SQLite storage. Strongly consistent rank reads |
| Leagues | **Durable Objects** (`LeagueDO`) | One per 30-player bracket. Ranks, promotion and relegation state |
| Parties + World Boss | **Durable Objects** (`PartyDO`) with **WebSocket Hibernation** | Real-time boss HP. Friends see each other's hits live. Costs almost nothing when idle |
| Board read caching | **KV** | Top-100 snapshots per board, refreshed every minute, for cheap reads at scale |
| Step ingestion + anti-cheat | **Queues** | `POST /steps` enqueues. The consumer validates and then writes D1 and BoardDOs |
| Scheduled jobs | **Cron Triggers** | Monday weekly reset, league reshuffle, World Boss spawn, streak checks |
| Long multi-step jobs | **Workflows** | Weekly season rollover: snapshot, award rewards, reshuffle, notify |
| Push notifications | Worker → APNs (HTTP/2 + JWT signed with **Secrets Store** key) via a `push` Queue | "Gate breached!", "Friend passed you", World Boss alerts |
| Assets / CDN | **R2** + custom domain cache | Sprite sheets, zone packs, avatars |
| Secrets | **Secrets Store** / Worker secrets | APNs key, Apple client secret, JWT signing key |
| Abuse protection | **Rate Limiting binding**, WAF rules, App Attest check in Worker | |
| Region for local boards | `request.cf.city` / `region` / `country` | No GPS permission needed. Optional finer geohash if the user opts in |
| Analytics / balancing | **Workers Analytics Engine** | Steps per session, gate clear times, Stride Mode usage |
| Logs / tracing | **Workers Logs** + Tail Workers | |
| Optional AI flavor | **Workers AI** | Generated quest text, boss taunts and weekly recap blurbs. Later |

**What stays off Cloudflare (no alternative exists):** HealthKit and CoreMotion run on the device, APNs is
Apple's delivery network (Cloudflare sends to it), and App Attest/Sign in with Apple are Apple identity
(Cloudflare verifies them).

**Game Center:** optional. It's used only for importing the friends list and for achievements. No
leaderboard data lives there.

### 6c. Key API surface (v1)
```
POST /auth/apple            Sign in with Apple token → session JWT (+ App Attest)
POST /steps                 Batch of { day, steps, flights, source } → Queue
GET  /boards/:scope         scope = friends | local | global | league  (?metric=steps|level|zone)
POST /friends/invite        → invite code / universal link
POST /friends/accept
GET  /party/:id/ws          WebSocket → PartyDO (World Boss live)
POST /party/:id/hit         Stride Mode hits during a World Boss
GET  /config                Zone tables, drop rates, feature flags (KV)
```

### Repo layout (planned monorepo)
```
ios/Stepforge/
  App/            StepforgeApp.swift, RootView
  Health/         HealthKitService, PedometerService
  Game/           GameState, Hero, Zone, Monster, Loot, OfflineSimulator, Formulas
  Scenes/         TrailScene (SpriteKit), BattleScene
  Features/       Home, StrideMode, Inventory, Leaderboards, Party, Settings
  Networking/     APIClient, AuthService, PartySocket
  Widgets/        StepforgeWidget
backend/
  wrangler.jsonc  Bindings: D1, KV, R2, Queues, DOs, cron, rate limit, AE
  src/index.ts    Hono router
  src/do/         BoardDO.ts, LeagueDO.ts, PartyDO.ts
  src/queues/     stepIngest.ts, pushFanout.ts
  src/cron/       weeklyReset.ts
  migrations/     D1 SQL
shared/
  formulas.json   Game balance tables shared by client + server
```

One benefit of having the backend on Workers: it *can* be built and tested here (`wrangler dev`,
Vitest with `@cloudflare/vitest-pool-workers`). The iOS side still needs Xcode on a Mac.

---

## 7. MVP scope (milestone 1)

1. HealthKit permission and today/weekly step sync
2. Hero, zones 1–3, auto-battle idle loop, offline catch-up
3. Step Gate at the end of each zone
4. Stride Mode with live cadence tiers and haptics
5. Basic gear drops and an inventory screen
6. Cloudflare backend v1: Worker API, Sign in with Apple auth, D1 schema, step ingest Queue,
   `BoardDO` for Friends / Local / Global weekly-steps boards, weekly reset cron

**Milestone 2:** Leagues (`LeagueDO`), parties and live World Boss (`PartyDO` + WebSockets), APNs push,
R2 zone packs, App Attest, Live Activity, widgets.
**Milestone 3:** Tower (flights), pets, classes, Watch app.

---

## 8. Open questions
- Art direction: pixel art (cheap, charming, fits idle RPG) or flat vector?
- Monetization: one-time purchase, cosmetic-only IAP, or subscription? (Recommendation: free plus cosmetics, **never sell steps or gate skips**.)
- Name: Stepforge / Stridebound / Wanderforge / Trailborn?
