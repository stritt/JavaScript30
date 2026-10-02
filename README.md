# Stepquest

An idle RPG for iOS powered by your real-world steps, presented like a vintage isometric tactics game.

- [GAME_DESIGN.md](GAME_DESIGN.md): the design
- [docs/API.md](docs/API.md): backend API contract
- [shared/formulas.json](shared/formulas.json): balance tables shared by app and server
- [backend/](backend/): Cloudflare Workers API (D1, Durable Objects, Queues, KV, Cron)
- [ios/](ios/): SwiftUI + SpriteKit app and the StepquestKit game-logic package
