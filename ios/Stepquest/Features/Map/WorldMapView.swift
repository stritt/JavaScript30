import StepquestKit
import SwiftUI

/// Hand-drawn style world map: zones as nodes connected by inked roads on parchment.
/// Tap a cleared zone to patrol it for loot/XP (the frontier gate keeps taking your steps).
struct WorldMapView: View {
    @Environment(GameStore.self) private var store
    @State private var selected: ZoneDefinition?

    var body: some View {
        let formulas = store.formulas
        let state = store.state
        let zones = formulas.zones.sorted { $0.id < $1.id }
        NavigationStack {
            GeometryReader { geo in
                let points = Self.nodePositions(count: zones.count, in: geo.size)
                ZStack {
                    MapCanvas(points: points, unlockedCount: zones.filter { state.isUnlocked(zoneId: $0.id) }.count)
                    ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                        ZoneNode(
                            zone: zone,
                            status: status(of: zone, state: state, formulas: formulas),
                            heroHere: state.trail.activeZoneId == zone.id)
                        .position(points[index])
                        .onTapGesture { selected = zone }
                    }
                }
            }
            .padding(.vertical, 8)
            .parchmentBackground()
            .navigationTitle("World Map")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { zone in
                ZoneDetailSheet(zone: zone)
                    .presentationDetents([.medium])
            }
        }
    }

    enum NodeStatus { case cleared, frontier, locked }

    private func status(of zone: ZoneDefinition, state: GameState, formulas: Formulas) -> NodeStatus {
        if state.clearedZoneIds(formulas).contains(zone.id) { return .cleared }
        if zone.id == state.trail.frontierZoneId { return .frontier }
        return .locked
    }

    /// Zig-zag from the bottom-left up to the top-right, like a road climbing the map.
    static func nodePositions(count: Int, in size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let t = count == 1 ? 0.5 : CGFloat(i) / CGFloat(count - 1)
            let x = size.width * (i % 2 == 0 ? 0.3 : 0.7) + CGFloat((i * 37) % 23) - 11
            let y = size.height * (0.85 - 0.7 * t)
            return CGPoint(x: x, y: y)
        }
    }
}

/// Parchment map art: wobbly coastline, hills, trees, inked roads and a compass rose.
private struct MapCanvas: View {
    let points: [CGPoint]
    let unlockedCount: Int

    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0xC0FFEE
            func rand() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(Double(seed >> 11) / Double(1 << 53))
            }
            let ink = ParchmentTheme.ink

            // Land mass with a hand-drawn wobble.
            var land = Path()
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let steps = 48
            for k in 0...steps {
                let a = CGFloat(k) / CGFloat(steps) * 2 * .pi
                let r = min(size.width, size.height) * (0.46 + 0.05 * sin(a * 3) + 0.02 * rand())
                let p = CGPoint(x: center.x + cos(a) * r * (size.width / min(size.width, size.height)) * 0.95,
                                y: center.y + sin(a) * r * (size.height / min(size.width, size.height)) * 0.9)
                if k == 0 { land.move(to: p) } else { land.addLine(to: p) }
            }
            land.closeSubpath()
            ctx.fill(land, with: .color(ParchmentTheme.parchmentDark.opacity(0.45)))
            ctx.stroke(land, with: .color(ink.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            // Scattered hills (^) and trees.
            for _ in 0..<26 {
                let p = CGPoint(x: size.width * (0.12 + rand() * 0.76), y: size.height * (0.1 + rand() * 0.8))
                if points.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 50 }) { continue }
                var mark = Path()
                if rand() > 0.5 {
                    mark.move(to: CGPoint(x: p.x - 9, y: p.y + 5))
                    mark.addLine(to: CGPoint(x: p.x, y: p.y - 7))
                    mark.addLine(to: CGPoint(x: p.x + 9, y: p.y + 5))
                } else {
                    mark.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 8, width: 10, height: 10))
                    mark.move(to: CGPoint(x: p.x, y: p.y + 2))
                    mark.addLine(to: CGPoint(x: p.x, y: p.y + 7))
                }
                ctx.stroke(mark, with: .color(ink.opacity(0.4)), lineWidth: 1.4)
            }

            // Roads between consecutive zones; locked roads are faint and dashed.
            for k in 0..<max(0, points.count - 1) {
                let a = points[k], b = points[k + 1]
                var road = Path()
                road.move(to: a)
                let mid = CGPoint(x: (a.x + b.x) / 2 + (k % 2 == 0 ? 40 : -40), y: (a.y + b.y) / 2)
                road.addQuadCurve(to: b, control: mid)
                let open = k + 1 < unlockedCount
                ctx.stroke(road, with: .color(ParchmentTheme.sepia.opacity(open ? 0.9 : 0.35)),
                           style: StrokeStyle(lineWidth: open ? 4 : 2.5, lineCap: .round, dash: [8, 6]))
            }

            // Compass rose.
            let c = CGPoint(x: size.width - 46, y: 54)
            var rose = Path()
            for k in 0..<4 {
                let a = CGFloat(k) * .pi / 2 - .pi / 2
                rose.move(to: c)
                rose.addLine(to: CGPoint(x: c.x + cos(a - 0.25) * 10, y: c.y + sin(a - 0.25) * 10))
                rose.addLine(to: CGPoint(x: c.x + cos(a) * 28, y: c.y + sin(a) * 28))
                rose.addLine(to: CGPoint(x: c.x + cos(a + 0.25) * 10, y: c.y + sin(a + 0.25) * 10))
                rose.closeSubpath()
            }
            ctx.fill(rose, with: .color(ParchmentTheme.gold.opacity(0.8)))
            ctx.stroke(rose, with: .color(ink.opacity(0.7)), lineWidth: 1)
            ctx.draw(Text("N").font(ParchmentTheme.display(12)).foregroundColor(ink), at: CGPoint(x: c.x, y: c.y - 38))
        }
        .allowsHitTesting(false)
    }
}

private struct ZoneNode: View {
    let zone: ZoneDefinition
    let status: WorldMapView.NodeStatus
    let heroHere: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 58, height: 58)
                    .overlay(Circle().stroke(ParchmentTheme.goldDeep, lineWidth: 3))
                    .overlay(Circle().stroke(ParchmentTheme.gold, lineWidth: 1).padding(4))
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(status == .locked ? ParchmentTheme.inkSoft : ParchmentTheme.parchmentLight)
                if heroHere {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(ParchmentTheme.ink)
                        .padding(5)
                        .background(Circle().fill(ParchmentTheme.goldLight))
                        .overlay(Circle().stroke(ParchmentTheme.ink, lineWidth: 1))
                        .offset(x: 24, y: -24)
                }
            }
            Text(zone.name)
                .font(ParchmentTheme.display(13))
                .foregroundStyle(status == .locked ? ParchmentTheme.inkSoft : ParchmentTheme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(ParchmentTheme.parchmentLight.opacity(0.8), in: Capsule())
            Text(caption)
                .font(ParchmentTheme.body(.caption2, weight: .semibold))
                .foregroundStyle(status == .frontier ? ParchmentTheme.crimson : ParchmentTheme.inkSoft)
        }
        .opacity(status == .locked ? 0.7 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var fill: Color {
        switch (status, zone.palette) {
        case (.locked, _): Color(hex: 0xB9A988)
        case (_, .meadow): Color(hex: 0x5E8C3A)
        case (_, .forest): Color(hex: 0x2F5A2A)
        case (_, .desert): Color(hex: 0xC2903A)
        case (_, .unknown): ParchmentTheme.sepia
        }
    }

    private var icon: String {
        if status == .locked { return "lock.fill" }
        switch zone.palette {
        case .meadow: return "leaf.fill"
        case .forest: return "tree.fill"
        case .desert: return "sun.max.fill"
        case .unknown: return "mappin"
        }
    }

    private var caption: String {
        switch status {
        case .cleared: "Cleared"
        case .frontier: "Frontier"
        case .locked: "Sealed"
        }
    }
}

private struct ZoneDetailSheet: View {
    let zone: ZoneDefinition
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = store.state
        let formulas = store.formulas
        let cleared = state.clearedZoneIds(formulas).contains(zone.id)
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapter \(Roman.numeral(zone.id))")
                .font(ParchmentTheme.display(13))
                .foregroundStyle(ParchmentTheme.inkSoft)
            Text(zone.name).font(ParchmentTheme.display(26))
            Text("\(zone.lengthTiles) tiles · Gate: \(zone.gate.name) (\(zone.gate.stepHp.grouped) steps)")
                .font(ParchmentTheme.body(.subheadline))
            OrnamentDivider()
            Text("Denizens").font(ParchmentTheme.display(14))
            ForEach(zone.monsters) { m in
                HStack {
                    Text(m.name).font(ParchmentTheme.body(.subheadline, weight: .semibold))
                    Spacer()
                    Text("HP \(m.hp) · ATK \(m.atk) · DEF \(m.def)")
                        .font(ParchmentTheme.numeric(12, weight: .medium))
                        .foregroundStyle(ParchmentTheme.inkSoft)
                }
            }
            Spacer(minLength: 8)
            if state.trail.activeZoneId == zone.id {
                Text(state.trail.isGrinding ? "Your hero is patrolling here." : "Your hero walks this road.")
                    .font(ParchmentTheme.body(.footnote, weight: .bold))
                if state.trail.isGrinding {
                    RetroButton("Return to the Frontier") { store.travel(to: nil); dismiss() }
                }
            } else if cleared {
                RetroButton("Patrol This Zone", systemImage: "arrow.triangle.turn.up.right.diamond") {
                    store.travel(to: zone.id)
                    dismiss()
                }
                Text("Earn loot and XP here. Steps still strike your frontier gate.")
                    .font(ParchmentTheme.body(.caption))
                    .foregroundStyle(ParchmentTheme.inkSoft)
            } else if zone.id == state.trail.frontierZoneId {
                RetroButton("Return to the Frontier") { store.travel(to: nil); dismiss() }
            } else {
                Text("Break the previous Step Gate to unseal this road.")
                    .font(ParchmentTheme.body(.footnote, weight: .bold))
                    .foregroundStyle(ParchmentTheme.crimson)
            }
        }
        .foregroundStyle(ParchmentTheme.ink)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .parchmentBackground()
    }
}
