# Stepquest for iOS

The iPhone client for Stepquest, an idle RPG powered by your real steps. The design lives in
[`../GAME_DESIGN.md`](../GAME_DESIGN.md), the balance numbers in [`../shared/formulas.json`](../shared/formulas.json)
and the backend contract in [`../docs/API.md`](../docs/API.md).

This folder covers milestone 1: HealthKit sync, the hero with zones 1–3 and offline catch-up, Step Gates,
Stride Mode with cadence tiers and haptics, gear drops with an inventory, and Friends, Local and Global
leaderboards.

## Layout

```
ios/
  project.yml              XcodeGen spec (the .xcodeproj is generated, not checked in)
  StepquestKit/            Swift package with the pure game logic (no UIKit/SpriteKit/HealthKit; builds on Linux)
    Sources/StepquestKit/  Formulas, Hero, Combat, Loot, StepGate, Cadence/Combo, StepLedger,
                           OfflineSimulator, StrideEngine, GameState, SplitMix64
    Sources/StepquestKit/Resources/formulas.json   bundled copy of shared/formulas.json
    Tests/StepquestKitTests/
  Stepquest/               the app target
    App/                   StepquestApp, AppModel (sync loop), RootView
    Health/                HealthKitService, PedometerService
    Networking/            APIClient, APIModels, AuthService, TokenStore (Keychain)
    Persistence/           GameStore (JSON save + simulation), ConfigStore (formulas refresh)
    Scenes/                TrailScene (SpriteKit isometric trail), SpriteFactory (procedural pixel art)
    Theme/                 ParchmentTheme, ParchmentPanel, RetroButton, banners and bars
    Features/              Boot, Auth, Home, Map (world map + zone title card), Gate, Stride,
                           Inventory, Leaderboards, Friends, Settings
    Resources/Assets.xcassets   AppIcon, colors, and an empty Sprites/ folder for real art
  StepquestTests/          app unit tests (API model decoding, persistence)
```

## Requirements

- macOS with **Xcode 16 or newer** (iOS 17 deployment target, Swift 5 language mode).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- To run on a device: an Apple Developer team. HealthKit and Sign in with Apple can't be signed with a
  free personal team.

## Generate and run

```sh
brew install xcodegen
cd ios
xcodegen generate          # run again whenever you add or remove files
open Stepquest.xcodeproj
```

1. Select the **Stepquest** target, open **Signing & Capabilities** and pick your team. Or set
   `DEVELOPMENT_TEAM` in `project.yml` and regenerate.
2. Run the **Stepquest** scheme on a simulator or a device.
3. To run the tests, press ⌘U. The scheme runs both `StepquestTests` and the package's `StepquestKitTests`.

You can also test the game logic on its own, with no Xcode needed. This works on macOS and Linux:

```sh
cd ios/StepquestKit
swift test
```

### Capabilities (already configured)

| Capability | Where |
|---|---|
| HealthKit (read steps and flights) with **background delivery** | `Stepquest/Stepquest.entitlements` |
| **Sign in with Apple** | `Stepquest/Stepquest.entitlements` |
| Background App Refresh (`fetch`, task id `app.stepquest.ios.refresh`) | `Info.plist` via `project.yml` |
| `NSHealthShareUsageDescription`, `NSMotionUsageDescription` | `Info.plist` via `project.yml` |
| Local networking over plain HTTP (`NSAllowsLocalNetworking`) | `Info.plist` via `project.yml` |

`Info.plist` and the entitlements file are regenerated from `project.yml`, so edit `project.yml` rather
than the generated files. After you change your team or bundle ID, enable HealthKit and Sign in with Apple
for the App ID in the developer portal. With automatic signing, Xcode does this for you.

## Pointing at a backend

The API base URL comes from the `STEPQUEST_API_BASE_URL` build setting, which is written into `Info.plist`
as `StepquestAPIBaseURL`.

- **Debug:** `http://localhost:8787`, which is `wrangler dev` in `../backend`.
- **Release:** `https://api.stepquest.app`.

Running a local backend:

```sh
cd backend
npm install
cp .dev.vars.example .dev.vars   # DEV_AUTH=true + a local JWT secret
npm run db:migrate:local
npm run dev                      # http://localhost:8787
```

- **Simulator:** `localhost` reaches your Mac directly.
- **Device:** set the URL to your Mac's LAN address, for example `http://192.168.1.20:8787`. Do this in
  **Settings → Debug → API URL** inside the app (DEBUG builds only) or in `project.yml`. Plain HTTP to
  local addresses is allowed by `NSAllowsLocalNetworking`.
- **Dev login:** Sign in with Apple needs a deployed backend with `APPLE_BUNDLE_ID` set to
  `app.stepquest.ios`. DEBUG builds also show a **Dev Login** on the sign-in screen, which calls
  `POST /v1/auth/dev`. This needs `DEV_AUTH=true` on the Worker.
- **Local board:** the region comes from `request.cf`, which `wrangler dev` doesn't fill in. The local
  board then answers `409 region_unknown`, and the app shows that as a plain message. The backend README
  describes an `X-Debug-Region` header for faking a region with curl.
- **Offline play:** "Play offline for now" skips the account entirely. The hero still progresses, and
  leaderboards and friends stay hidden until you sign in.

## How the client works

- **Balance tables.** `Formulas` decodes `formulas.json`. The app ships the copy bundled in StepquestKit.
  On launch it fetches `GET /v1/config`, validates it, caches it in Application Support and uses it if its
  `version` isn't older than the bundled one. `FormulasTests.testBundledCopyMatchesSharedSourceOfTruth`
  fails if the bundled copy drifts from `shared/formulas.json`. To fix it, run
  `cp shared/formulas.json ios/StepquestKit/Sources/StepquestKit/Resources/`.
- **Sync loop** (`AppModel.sync`). It runs on launch, on foreground, on HealthKit observer wakeups and on
  background refresh:
  1. Read the HealthKit daily totals for the last `integrity.maxPastDays` days. This uses
     `HKStatisticsCollectionQuery` and excludes samples marked `HKMetadataKeyWasUserEntered`.
  2. Pass the totals to `StepLedger`, which turns them into *new* steps. Steps from days before the save
     existed are ignored, and steps already applied live in Stride Mode are subtracted.
  3. Run `OfflineSimulator` over the elapsed time and the new steps. It is deterministic and uses a
     seeded SplitMix64 stored in the save.
  4. `POST /v1/steps` the daily totals, then `PATCH /v1/me` with `heroLevel` and the frontier `zone`.
- **Save.** `GameState` is Codable and stored as JSON at `Application Support/Stepquest/save.json` with an
  atomic write. A corrupt file is moved aside rather than overwritten. While the trail is on screen the
  game simulates every 4 seconds, so the hero visibly walks.
- **Stride Mode.** `PedometerService` (CMPedometer) passes cumulative steps to `CadenceTracker`, a rolling
  cadence in steps per minute over `cadenceWindowSeconds`. Every 0.25 s `StrideController` passes the new
  steps and the cadence to `StrideEngine`. The engine applies tier damage multipliers, combo and crits,
  and stride steps count `gateStepMultiplier`× against gates. The controller also fires haptics, keeps
  the screen awake and shows a "Look up!" nudge every 45 s. The Simulator has no pedometer, so DEBUG
  builds have buttons that simulate walking at a given cadence.
- **Art.** Everything is drawn in code and pixelated with nearest-neighbour filtering: tiles, the chibi
  hero, monsters and gate guardians. To use real sprites, drop images named `hero_walk_0`, `hero_walk_1`,
  `hero_idle`, `monster_<id>`, `gate_<zoneId>`, `tile_<palette>_<path|grass|cliff>` or
  `deco_<palette>_<n>` into `Assets.xcassets/Sprites` or a `.spriteatlas`. They override the procedural
  versions automatically (see `SpriteFactory`). The serif display font uses a bundled `Cinzel-Bold` if
  you add one, and falls back to the system serif otherwise.

## Not in milestone 1

Leagues, parties and the World Boss, APNs push, App Attest, Live Activity, widgets, the Tower (flights),
pets and the Watch app are planned for milestones 2 and 3 (GAME_DESIGN.md §7). Flights are already read
from HealthKit and uploaded.
