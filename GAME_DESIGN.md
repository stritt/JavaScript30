# Stepquest — Game Design (v0 draft)

An idle tactics RPG for iPhone where your real-world steps power your party.
It progresses without you, but slowly, and real steps are what get you past the walls.
It looks and feels like a lost 1997 tactics game, *Final Fantasy Tactics* by way of a pedometer.

No monetization for now. Everything below is designed for fun first; the "never sell steps or
gate skips" rule stands if money ever comes into it.

---

## 0. Look and feel: vintage tactics

The game should feel like something you'd find on a PS1 memory card.

- **Isometric diorama battles.** Small floating isometric maps (grass, stone, water, elevation)
  with chibi 16-bit-style sprites. The camera can rotate in 90° steps, and the board tilts slightly.
- **Parchment UI.** Menus are aged-paper panels with ornate borders, a serif display font, and
  gold/ink colors. Unit panels show portrait, HP/MP and a CT (charge time) gauge.
- **Narrated chapters.** Each zone is a chapter introduced by a sepia story card ("Chapter I: The
  Meadow Road"). Step Gates are the chapter's climactic battle.
- **World map.** A hand-drawn map with node towns and battle sites connected by roads. Your party
  marches node to node as steps come in.
- **Sound.** Chiptune/orchestral-MIDI style music with a classic "level up!" jingle and menu blips.
- **Retro touches.** A boot screen in the style of an old console, a "Brave/Faith" style personality stat,
  floating damage numbers, and "Job Level Up!" banners.

Everything is original art, names and story. It's *inspired by* the genre, and copies no Square Enix assets or names.

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
 Real steps (HealthKit) ──► Stride Energy ──► Party marches the World Map
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

### Party and Job system (the tactics heart)
You command a **party of up to 5 units** instead of one hero. Each unit has a **Job**. Units earn
**JP (Job Points)** to learn abilities, and leveling Jobs unlocks new ones on a job tree. Each Job is
fed by a different kind of real activity, so how you move shapes your party:

| Job | Fed by | Flavor |
|---|---|---|
| **Squire** (start) | Steps | Basic all-rounder. Unlocks Knight and Archer |
| **Wayfarer** (start) | Steps | Basic support. Unlocks Herbalist and Mage |
| **Archer** | Steps | Ranged damage. Gets range bonus from height |
| **Knight** | Exercise minutes | Tank. Break and guard skills |
| **Brawler** | Stride Mode cadence | Martial artist. Combo hits scale with spm |
| **Dragoon** | Flights climbed | "Leap" attacks. Climbs the Tower fastest |
| **Herbalist** | Steps | Items and healing |
| **White Mage** | Sleep (7h+) | Heals and buffs. Rested mages charge faster |
| **Black Mage** | Steps | AoE spells with long charge times |
| **Pilgrim** | Long walks (20+ min) | Endgame hybrid. Unlocks after mastering 3 Jobs |

- **Secondary ability slot.** Each unit equips one other Job's learned skill set, the classic
  tactics customization loop.
- **Recruits.** New units join after chapters and as rare battle drops.
- **Permadeath-lite.** A unit KO'd in a gate battle is "wounded" for a few hours of real time. Walking
  speeds up recovery.

### Battles
- **Grid battles with CT turn order.** Units act when their CT gauge fills, based on Speed.
- **Idle:** fully automatic. You set each unit's tactic (Aggressive, Defensive, Support).
- **Stride Mode:** your cadence fills *your* party's CT faster, so walking literally speeds up your
  turns. You can tap to queue abilities, but the AI handles everything else.
- Height, facing (back attacks) and elemental terrain matter, lightly. It's a phone game you play while walking.

---

## 4. Social and leaderboards

### Boards
| Scope | Source | Metrics |
|---|---|---|
| **Friends** | Our own friend graph: invite links/codes, plus optional Game Center friend import | Weekly steps, hero level, deepest zone |
| **Local** | Opt-in. Region comes from Cloudflare's `request.cf` (city/region) or a ~5 km geohash. Never exact location | Weekly steps, zone |
| **Global** | Everyone | Weekly steps, level, gate speed-run times |

All boards are served from our Cloudflare backend (see §6), not Game Center. That way friends, local and
global boards, leagues and guilds all share one data model.

- **Weekly Leagues.** Groups of 30 similar players, Bronze → Mythic, promotion and relegation.
  This keeps competition fair. A 4k-steps-a-day player isn't up against marathoners.
- Boards reset weekly. All-time is shown as a secondary tab.

### Co-op
- **Guilds** of up to 6 friends (named "guilds" so they don't clash with your unit party).
- **World Boss** every week: the guild's combined real steps fight it. Loot scales with contribution.
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
 step_days,   config,        GuildDO (guild +     consumer           avatars       balancing
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
| Guilds + World Boss | **Durable Objects** (`GuildDO`) with **WebSocket Hibernation** | Real-time boss HP. Friends see each other's hits live. Costs almost nothing when idle |
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
GET  /guild/:id/ws          WebSocket → GuildDO (World Boss live)
POST /guild/:id/hit         Stride Mode hits during a World Boss
GET  /config                Zone tables, drop rates, feature flags (KV)
```

### Repo layout (planned monorepo)
```
ios/Stepquest/
  App/            StepquestApp.swift, RootView
  Health/         HealthKitService, PedometerService
  Game/           GameState, Hero, Zone, Monster, Loot, OfflineSimulator, Formulas
  Scenes/         TrailScene (SpriteKit), BattleScene
  Features/       Home, StrideMode, Inventory, Leaderboards, Party (units & jobs), Guild, Settings
  Networking/     APIClient, AuthService, GuildSocket
  Widgets/        StepquestWidget
backend/
  wrangler.jsonc  Bindings: D1, KV, R2, Queues, DOs, cron, rate limit, AE
  src/index.ts    Hono router
  src/do/         BoardDO.ts, LeagueDO.ts, GuildDO.ts
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
2. Parchment UI shell, world map, chapters 1–3 with isometric auto-battles (CT turn order), offline catch-up
3. Party of 3 units, starter Jobs (Squire, Wayfarer, Archer, Herbalist), JP and ability learning
4. Step Gate battle at the end of each chapter
5. Stride Mode with live cadence tiers filling CT, plus haptics
6. Basic gear drops and an equipment screen
7. Cloudflare backend v1: Worker API, Sign in with Apple auth, D1 schema, step ingest Queue,
   `BoardDO` for Friends / Local / Global weekly-steps boards, weekly reset cron

**Milestone 2:** Leagues (`LeagueDO`), guilds and live World Boss (`GuildDO` + WebSockets), APNs push,
R2 zone packs, App Attest, Live Activity, widgets.
**Milestone 3:** Full job tree (Knight, Brawler, Dragoon, mages, Pilgrim), Tower (flights), recruits, pets, Watch app.

---

## 8. Decisions
- **Name:** Stepquest
- **Art direction:** vintage isometric tactics (see §0). Pixel sprites and parchment UI
- **Monetization:** none for now

## 9. Open questions
- Sprite pipeline: hand-made pixel art, a commissioned artist, or an open-licensed asset pack to start?
- Story tone: earnest high-fantasy drama (very FFT) or lighter and self-aware?
