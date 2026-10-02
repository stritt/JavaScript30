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
| **Friends** | Game Center friends + invite links | Weekly steps, hero level, deepest zone |
| **Local** | Opt-in, coarse location (city or ~5 km geohash, never exact) | Weekly steps, zone |
| **Global** | Everyone | Weekly steps, level, gate speed-run times |

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

---

## 6. Tech plan (iOS)

| Concern | Choice |
|---|---|
| UI | **SwiftUI**, iOS 17+ |
| Game scene | **SpriteKit** inside SwiftUI (`SpriteView`) for the trail and battles |
| Steps (history) | **HealthKit** `HKStatisticsCollectionQuery` with `HKObserverQuery` and background delivery |
| Steps (live) | **CoreMotion** `CMPedometer` for real-time cadence in Stride Mode |
| Persistence | **SwiftData** on device |
| Friends + Global boards | **Game Center** (`GKLeaderboard`, friends API) at no backend cost |
| Local boards, leagues, parties, World Boss | Small backend: **Supabase** (Postgres + Auth via Sign in with Apple + Edge Functions) |
| Widgets | WidgetKit: today's steps, hero, gate progress |
| Live play | ActivityKit Live Activity during Stride Mode |
| Later | Apple Watch companion (Stride Mode from the wrist) |

### Project layout (planned)
```
Stepforge/
  App/            StepforgeApp.swift, RootView
  Health/         HealthKitService, PedometerService
  Game/           GameState, Hero, Zone, Monster, Loot, OfflineSimulator, Formulas
  Scenes/         TrailScene (SpriteKit), BattleScene
  Features/       Home, StrideMode, Inventory, Leaderboards, Party, Settings
  Social/         GameCenterService, BackendClient
  Widgets/        StepforgeWidget
```

---

## 7. MVP scope (milestone 1)

1. HealthKit permission and today/weekly step sync
2. Hero, zones 1–3, auto-battle idle loop, offline catch-up
3. Step Gate at the end of each zone
4. Stride Mode with live cadence tiers and haptics
5. Basic gear drops and an inventory screen
6. Game Center: Friends and Global weekly-steps boards

**Milestone 2:** Local boards, leagues and parties (backend), World Boss, Live Activity, widgets.
**Milestone 3:** Tower (flights), pets, classes, Watch app.

---

## 8. Open questions
- Art direction: pixel art (cheap, charming, fits idle RPG) or flat vector?
- Monetization: one-time purchase, cosmetic-only IAP, or subscription? (Recommendation: free plus cosmetics, **never sell steps or gate skips**.)
- Name: Stepforge / Stridebound / Wanderforge / Trailborn?
