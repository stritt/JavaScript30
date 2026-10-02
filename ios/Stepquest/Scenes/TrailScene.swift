import SpriteKit
import StepquestKit
import UIKit

/// Isometric diorama of the trail: a winding path of floating tile blocks with elevation steps,
/// the chibi hero walking it, monsters, the zone's Step Gate guardian and floating damage numbers.
///
/// Visual only: it mirrors `GameState` (position, fights) and never changes it.
/// Two modes: `.idle` replays `FightLog`s from the simulator; `.live` is driven blow-by-blow by Stride Mode.
@MainActor
final class TrailScene: SKScene {
    enum Mode { case idle, live }

    var mode: Mode = .idle

    // Grid / layout (design units; the world node is scaled by SpriteFactory.pixelScale).
    private let tw = SpriteFactory.tileWidth
    private let th = SpriteFactory.tileHeight
    private let rowsBehind = 8
    private let rowsAhead = 16
    private let halfWidth = 3

    private let world = SKNode()
    private let cameraNode = SKCameraNode()
    private var rows: [Int: SKNode] = [:]
    private var factory: SpriteFactory!

    private var hero = SKSpriteNode()
    private var heroFrames: [SpriteFactory.Art] = []
    private var heroIsWalking = false
    private var monster: SKSpriteNode?
    private var guardian: SKNode?

    private var zone: ZoneDefinition?
    private var palette: ZonePalette = .meadow
    private var displayedTile: Double = 0
    private var targetTile: Double = 0
    private var atGate = false
    private var fightQueue: [FightLog] = []
    private var isAnimatingFight = false
    private var lastUpdate: TimeInterval = 0
    private var built = false

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = UIColor(red: 0.09, green: 0.07, blue: 0.06, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Setup

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        view.ignoresSiblingOrder = true
        factory = SpriteFactory(view: view)
        world.setScale(SpriteFactory.pixelScale)
        addChild(world)
        addChild(cameraNode)
        camera = cameraNode
        addBackdrop()

        heroFrames = factory.heroWalkFrames()
        let idle = factory.heroIdle()
        hero = idle.sprite()
        hero.name = "hero"
        world.addChild(hero)
        if let zone { rebuild(for: zone) }
    }

    /// Soft clouds parented to the camera so they stay put while the world scrolls.
    private func addBackdrop() {
        let glow = SKShapeNode(ellipseOf: CGSize(width: 900, height: 500))
        glow.fillColor = UIColor(red: 0.35, green: 0.27, blue: 0.18, alpha: 0.35)
        glow.strokeColor = .clear
        glow.zPosition = -1000
        cameraNode.addChild(glow)
        for i in 0..<5 {
            let cloud = SKShapeNode(ellipseOf: CGSize(width: 120 + CGFloat(i * 20), height: 26))
            cloud.fillColor = UIColor(white: 1, alpha: 0.06)
            cloud.strokeColor = .clear
            cloud.position = CGPoint(x: CGFloat(i * 90 - 200), y: CGFloat(140 - i * 70))
            cloud.zPosition = -999
            let drift = SKAction.sequence([
                .moveBy(x: 40, y: 0, duration: 9 + Double(i)),
                .moveBy(x: -40, y: 0, duration: 9 + Double(i)),
            ])
            cloud.run(.repeatForever(drift))
            cameraNode.addChild(cloud)
        }
    }

    // MARK: Public API (called from SwiftUI)

    /// Sets the zone and the hero's tile. Rebuilds the diorama when the zone changes.
    func sync(zone: ZoneDefinition, tile: Double, atGate: Bool) {
        let zoneChanged = self.zone?.id != zone.id
        self.zone = zone
        self.atGate = atGate
        targetTile = min(tile, Double(zone.lengthTiles))
        if zoneChanged {
            displayedTile = targetTile
            palette = zone.palette
            if built { rebuild(for: zone) }
        } else if abs(targetTile - displayedTile) > 40 || targetTile < displayedTile - 1 {
            // Big jumps (offline catch-up, looping grind trail): teleport.
            displayedTile = targetTile
            refreshRows()
        }
    }

    /// Queue idle fights from the simulator for replay.
    func play(fights: [FightLog]) {
        guard mode == .idle, !fights.isEmpty else { return }
        fightQueue.append(contentsOf: fights.suffix(3))
        if fightQueue.count > 3 { fightQueue.removeFirst(fightQueue.count - 3) }
        runNextFight()
    }

    // Live (Stride Mode) hooks.

    func liveEncounter(_ definition: MonsterDefinition) {
        removeMonster(animated: false)
        spawnMonster(definition)
    }

    func liveHeroHit(damage: Int, crit: Bool) {
        guard let monster else { return }
        heroLunge()
        monster.run(Self.flash())
        floatNumber(crit ? "\(damage)!" : "\(damage)", at: monster.position, color: crit ? .gold : .white, big: crit)
    }

    func liveMonsterHit(damage: Int) {
        monster?.run(.sequence([.moveBy(x: -4, y: 2, duration: 0.06), .moveBy(x: 4, y: -2, duration: 0.1)]))
        hero.run(Self.flash())
        floatNumber("\(damage)", at: hero.position, color: .red, big: false)
    }

    func liveKill(xp: Int, gold: Int) {
        guard let monster else { return }
        floatNumber("+\(xp) XP", at: CGPoint(x: monster.position.x, y: monster.position.y + 14), color: .xp, big: false)
        removeMonster(animated: true)
    }

    func liveDefeat() {
        floatNumber("Retreat!", at: hero.position, color: .red, big: true)
        removeMonster(animated: true)
    }

    func liveGateHit(steps: Int) {
        guard let guardian else { return }
        guardian.run(Self.flash())
        floatNumber("-\(steps)", at: CGPoint(x: guardian.position.x, y: guardian.position.y + 30), color: .gold, big: false)
    }

    // MARK: Frame update

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(0.1, currentTime - lastUpdate)
        lastUpdate = currentTime
        guard built, zone != nil else { return }

        let fighting = monster != nil
        let gap = targetTile - displayedTile
        if !fighting, gap > 0.01 {
            // Ease toward the simulated position, at least a gentle walking pace.
            let speed = max(0.6, gap * 1.5)
            displayedTile = min(targetTile, displayedTile + speed * dt)
            setWalking(true)
        } else {
            setWalking(false)
        }

        let heroPos = position(forTile: displayedTile)
        hero.position = heroPos
        hero.zPosition = zFor(i: Int(displayedTile.rounded()), j: pathOffset(Int(displayedTile.rounded()))) + 5
        if let monster {
            monster.zPosition = hero.zPosition
        }
        refreshRows()

        // Camera follows the hero (world coordinates are scaled).
        let target = CGPoint(x: heroPos.x * SpriteFactory.pixelScale + 40, y: heroPos.y * SpriteFactory.pixelScale + 30)
        cameraNode.position = CGPoint(
            x: cameraNode.position.x + (target.x - cameraNode.position.x) * min(1, dt * 4),
            y: cameraNode.position.y + (target.y - cameraNode.position.y) * min(1, dt * 4))
    }

    private func setWalking(_ walking: Bool) {
        guard walking != heroIsWalking else { return }
        heroIsWalking = walking
        hero.removeAction(forKey: "walk")
        if walking, heroFrames.count >= 2 {
            let frames = SKAction.animate(with: heroFrames.map(\.texture), timePerFrame: 0.18)
            hero.run(.repeatForever(frames), withKey: "walk")
        } else {
            hero.texture = factory.heroIdle().texture
        }
    }

    // MARK: Terrain

    private func rebuild(for zone: ZoneDefinition) {
        rows.values.forEach { $0.removeFromParent() }
        rows.removeAll()
        guardian?.removeFromParent()
        guardian = nil
        removeMonster(animated: false)
        backgroundColor = backdropColor(zone.palette)
        refreshRows()
        let pos = position(forTile: displayedTile)
        cameraNode.position = CGPoint(x: pos.x * SpriteFactory.pixelScale + 40, y: pos.y * SpriteFactory.pixelScale + 30)
    }

    private func backdropColor(_ palette: ZonePalette) -> UIColor {
        switch palette {
        case .meadow: UIColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1)
        case .forest: UIColor(red: 0.06, green: 0.09, blue: 0.07, alpha: 1)
        case .desert: UIColor(red: 0.20, green: 0.13, blue: 0.08, alpha: 1)
        case .unknown: UIColor(red: 0.09, green: 0.07, blue: 0.06, alpha: 1)
        }
    }

    private func refreshRows() {
        guard let zone else { return }
        let center = Int(displayedTile)
        let lower = center - rowsBehind
        let upper = min(zone.lengthTiles + 3, center + rowsAhead)
        for i in rows.keys where i < lower || i > upper {
            rows[i]?.removeFromParent()
            rows[i] = nil
        }
        for i in lower...max(lower, upper) where rows[i] == nil {
            let row = buildRow(i)
            rows[i] = row
            world.addChild(row)
        }
        updateGuardian(zone: zone)
    }

    /// One row across the trail: path tiles near the meandering center, raised ground/cliffs at the edges.
    private func buildRow(_ i: Int) -> SKNode {
        let row = SKNode()
        let offset = pathOffset(i)
        for j in -halfWidth...halfWidth {
            let distance = abs(j - offset)
            let kind: SpriteFactory.TileKind = distance == 0 ? .path : (distance >= 3 ? .cliff : .grass)
            let elevation = elevationFor(i: i, j: j, distance: distance)
            let variant = Int(hash(i, j) % 3)
            let tile = factory.tile(kind, palette: palette, elevation: elevation, variant: variant).sprite()
            tile.position = groundPoint(i: i, j: j)
            tile.zPosition = zFor(i: i, j: j)
            row.addChild(tile)

            if kind != .path, hash(i, j &+ 17) % 5 == 0 {
                let deco = factory.decoration(palette, variant: Int(hash(j, i) % 4)).sprite()
                deco.position = CGPoint(x: tile.position.x, y: tile.position.y + topHeight(elevation))
                deco.zPosition = tile.zPosition + 1
                row.addChild(deco)
            }
        }
        return row
    }

    /// Smoothly meandering path: -1, 0 or +1 across the row.
    private func pathOffset(_ i: Int) -> Int {
        Int((sin(Double(i) * 0.21) * 1.4).rounded())
    }

    /// Path height steps up/down every few tiles; edges rise into terraces.
    private func pathElevation(_ i: Int) -> Int {
        let wave = sin(Double(i) * 0.09) + 0.5 * sin(Double(i) * 0.23 + 1.3)
        return max(0, min(2, Int((wave + 0.6).rounded(.down))))
    }

    private func elevationFor(i: Int, j: Int, distance: Int) -> Int {
        let base = pathElevation(i)
        switch distance {
        case 0, 1: return base
        case 2: return base + Int(hash(i, j) % 2)
        default: return base + 1 + Int(hash(i, j) % 2)
        }
    }

    private func topHeight(_ elevation: Int) -> CGFloat {
        SpriteFactory.baseDepth + CGFloat(elevation) * SpriteFactory.elevationStep
    }

    private func groundPoint(i: Int, j: Int) -> CGPoint {
        CGPoint(x: CGFloat(i + j) * tw / 2, y: CGFloat(i - j) * th / 2)
    }

    /// Painter's order: rows further up the screen draw first.
    private func zFor(i: Int, j: Int) -> CGFloat {
        CGFloat(j - i) * 10
    }

    /// Where an actor stands at a (fractional) tile along the path.
    private func position(forTile t: Double) -> CGPoint {
        let i0 = Int(t.rounded(.down))
        let f = CGFloat(t - Double(i0))
        let a = actorPoint(i0)
        let b = actorPoint(i0 + 1)
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }

    private func actorPoint(_ i: Int) -> CGPoint {
        let j = pathOffset(i)
        let g = groundPoint(i: i, j: j)
        return CGPoint(x: g.x, y: g.y + topHeight(pathElevation(i)))
    }

    private func hash(_ a: Int, _ b: Int) -> UInt64 {
        var x = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663 ^ (zone?.id ?? 0) &* 83_492_791))
        x ^= x >> 33
        x = x &* 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        return x
    }

    // MARK: Gate guardian

    private func updateGuardian(zone: ZoneDefinition) {
        let gateTile = zone.lengthTiles
        let visible = Double(gateTile) - displayedTile < Double(rowsAhead)
        if visible, guardian == nil {
            let node = SKNode()
            let art = factory.gateGuardian(zone: zone).sprite()
            node.addChild(art)
            // Stone arch behind the guardian.
            let pillarL = SKShapeNode(rect: CGRect(x: -22, y: 0, width: 6, height: 44))
            let pillarR = SKShapeNode(rect: CGRect(x: 16, y: 0, width: 6, height: 44))
            let lintel = SKShapeNode(rect: CGRect(x: -24, y: 42, width: 48, height: 7))
            for part in [pillarL, pillarR, lintel] {
                part.fillColor = UIColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1)
                part.strokeColor = SpriteFactory.outline
                part.isAntialiased = false
                part.zPosition = -1
                node.addChild(part)
            }
            let p = actorPoint(gateTile)
            node.position = CGPoint(x: p.x + 6, y: p.y)
            node.zPosition = zFor(i: gateTile, j: pathOffset(gateTile)) + 4
            node.run(.repeatForever(.sequence([.moveBy(x: 0, y: 1.5, duration: 0.8), .moveBy(x: 0, y: -1.5, duration: 0.8)])))
            world.addChild(node)
            guardian = node
        } else if !visible, let g = guardian {
            g.removeFromParent()
            guardian = nil
        }
    }

    // MARK: Fights

    private func spawnMonster(_ definition: MonsterDefinition) {
        let sprite = factory.monster(definition).sprite()
        let p = position(forTile: displayedTile + 1.2)
        sprite.position = p
        sprite.zPosition = hero.zPosition
        sprite.alpha = 0
        sprite.setScale(0.6)
        sprite.run(.group([.fadeIn(withDuration: 0.2), .scale(to: 1, duration: 0.2)]))
        sprite.run(.repeatForever(.sequence([.scaleY(to: 0.92, duration: 0.3), .scaleY(to: 1, duration: 0.3)])), withKey: "breathe")
        world.addChild(sprite)
        monster = sprite
    }

    private func removeMonster(animated: Bool) {
        guard let m = monster else { return }
        monster = nil
        if animated {
            poof(at: m.position)
            m.run(.sequence([.group([.fadeOut(withDuration: 0.25), .scale(to: 1.4, duration: 0.25)]), .removeFromParent()]))
        } else {
            m.removeFromParent()
        }
    }

    private func runNextFight() {
        guard !isAnimatingFight, !fightQueue.isEmpty, built else { return }
        isAnimatingFight = true
        let fight = fightQueue.removeFirst()
        spawnMonster(fight.monster)

        var steps: [SKAction] = [.wait(forDuration: 0.35)]
        let swings = max(1, min(4, fight.heroHits))
        let counters = min(fight.monsterHits, swings)
        for k in 0..<swings {
            steps.append(.run { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let m = self.monster else { return }
                    self.heroLunge()
                    m.run(TrailScene.flash())
                    self.floatNumber("\(fight.heroDamagePerHit)", at: m.position, color: .white, big: false)
                }
            })
            steps.append(.wait(forDuration: 0.4))
            if k < counters {
                steps.append(.run { [weak self] in
                    MainActor.assumeIsolated { self?.liveMonsterHit(damage: fight.monsterDamagePerHit) }
                })
                steps.append(.wait(forDuration: 0.3))
            }
        }
        steps.append(.run { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if fight.heroWon {
                    self.liveKill(xp: fight.monster.xp, gold: fight.monster.gold)
                } else {
                    self.liveDefeat()
                }
            }
        })
        steps.append(.wait(forDuration: 0.5))
        steps.append(.run { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimatingFight = false
                self?.runNextFight()
            }
        })
        run(.sequence(steps), withKey: "fight")
    }

    private func heroLunge() {
        hero.run(.sequence([.moveBy(x: 5, y: 2.5, duration: 0.06), .moveBy(x: -5, y: -2.5, duration: 0.1)]))
    }

    private static func flash() -> SKAction {
        .sequence([
            .colorize(with: .white, colorBlendFactor: 0.9, duration: 0.03),
            .wait(forDuration: 0.06),
            .colorize(withColorBlendFactor: 0, duration: 0.1),
        ])
    }

    private func poof(at point: CGPoint) {
        for k in 0..<8 {
            let bit = SKSpriteNode(color: UIColor(white: 0.95, alpha: 1), size: CGSize(width: 2, height: 2))
            bit.position = CGPoint(x: point.x, y: point.y + 6)
            bit.zPosition = 9_000
            let angle = CGFloat(k) / 8 * .pi * 2
            bit.run(.sequence([
                .group([.moveBy(x: cos(angle) * 12, y: sin(angle) * 12, duration: 0.35), .fadeOut(withDuration: 0.35)]),
                .removeFromParent(),
            ]))
            world.addChild(bit)
        }
    }

    // MARK: Floating numbers

    enum NumberColor { case white, red, gold, xp }

    private func floatNumber(_ text: String, at point: CGPoint, color: NumberColor, big: Bool) {
        let fill: UIColor = switch color {
        case .white: .white
        case .red: UIColor(red: 1, green: 0.42, blue: 0.35, alpha: 1)
        case .gold: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        case .xp: UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 1)
        }
        let size: CGFloat = big ? 13 : 9
        let font = UIFont(name: "Courier-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .heavy)
        let label = SKLabelNode()
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: fill,
            .strokeColor: UIColor.black,
            .strokeWidth: -5,
        ])
        label.position = CGPoint(x: point.x + CGFloat.random(in: -3...3), y: point.y + 18)
        label.zPosition = 10_000
        label.setScale(big ? 1.4 : 1.1)
        label.run(.sequence([
            .group([
                .moveBy(x: 0, y: 16, duration: 0.8),
                .sequence([.scale(to: 1, duration: 0.12), .wait(forDuration: 0.45), .fadeOut(withDuration: 0.23)]),
            ]),
            .removeFromParent(),
        ]))
        world.addChild(label)
    }
}
