import StepquestKit
import SwiftUI

/// Boot screen → (sign in) → themed tab bar, with global game overlays
/// (Level Up! banner, sepia zone title card, "While you were away").
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(GameStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var booted = false
    @State private var tab: Tab = .trail

    enum Tab: Hashable { case trail, map, stride, gear, ranks }

    var body: some View {
        ZStack {
            if !booted {
                BootView {
                    withAnimation(.easeInOut(duration: 0.5)) { booted = true }
                }
                .transition(.opacity)
            } else if auth.needsOnboarding {
                SignInView()
                    .transition(.opacity)
            } else {
                mainTabs
                    .transition(.opacity)
                    .task { await model.bootstrap() }
            }
        }
        .overlay { overlays }
    }

    private var mainTabs: some View {
        TabView(selection: $tab) {
            HomeView(openStride: { tab = .stride }, openMap: { tab = .map })
                .tabItem { Label("Trail", systemImage: "figure.walk") }
                .tag(Tab.trail)
            WorldMapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(Tab.map)
            StrideModeView()
                .tabItem { Label("Stride", systemImage: "bolt.heart") }
                .tag(Tab.stride)
            InventoryView()
                .tabItem { Label("Gear", systemImage: "shield.lefthalf.filled") }
                .tag(Tab.gear)
            LeaderboardsView()
                .tabItem { Label("Ranks", systemImage: "trophy") }
                .tag(Tab.ranks)
        }
        .sheet(item: Binding(get: { store.awaySummary.map(AwayItem.init) }, set: { if $0 == nil { store.awaySummary = nil } })) { item in
            AwaySummaryView(summary: item.summary)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var overlays: some View {
        ZStack {
            if let zone = store.zoneCard, booted {
                ZoneTitleCard(zone: zone) { store.zoneCard = nil }
                    .transition(.opacity)
                    .zIndex(2)
            }
            if let level = store.levelUpBanner, booted, store.zoneCard == nil {
                LevelUpBanner(level: level) { store.levelUpBanner = nil }
                    .zIndex(3)
            }
            if let toast = store.toast, booted {
                VStack {
                    ToastRibbon(text: toast)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { store.toast = nil }
                }
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: store.zoneCard?.id)
        .animation(.easeInOut, value: store.toast)
    }
}

private struct AwayItem: Identifiable {
    let summary: OfflineSummary
    var id: Double { summary.elapsedSeconds + Double(summary.kills) }
}

/// "While you were away" report.
struct AwaySummaryView: View {
    let summary: OfflineSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            BannerText(text: "While You Were Away", size: 26)
                .padding(.top, 20)
            VStack(alignment: .leading, spacing: 8) {
                row("Time on the road", Self.duration(summary.simulatedSeconds) + (summary.wasCapped ? " (max)" : ""))
                row("Steps credited", summary.stepsApplied.grouped)
                row("Tiles walked", summary.tilesWalked.groupedInt)
                row("Foes defeated", summary.kills.grouped)
                if summary.defeats > 0 { row("Retreats", summary.defeats.grouped) }
                row("Experience", "+\(summary.xp.grouped)")
                row("Gold", "+\(summary.gold.grouped)")
                if summary.levelUps > 0 { row("Levels gained", "+\(summary.levelUps)") }
                if summary.gateDamage > 0 { row("Gate damage", summary.gateDamage.groupedInt) }
                if !summary.loot.isEmpty {
                    OrnamentDivider()
                    Text("Spoils").font(ParchmentTheme.display(14)).foregroundStyle(ParchmentTheme.inkSoft)
                    ForEach(summary.loot.prefix(5)) { item in
                        Text(item.name)
                            .font(ParchmentTheme.body(.subheadline, weight: .semibold))
                            .foregroundStyle(ParchmentTheme.rarityColor(item.rarityId))
                    }
                    if summary.loot.count > 5 {
                        Text("…and \(summary.loot.count - 5) more").font(ParchmentTheme.body(.caption))
                    }
                }
                if summary.reachedGate {
                    OrnamentDivider()
                    Text("You reached a Step Gate. Walk to break it!")
                        .font(ParchmentTheme.body(.subheadline, weight: .bold))
                        .foregroundStyle(ParchmentTheme.crimson)
                }
            }
            .parchmentPanel(title: "Chronicle")
            .padding(.horizontal)
            RetroButton("Onward") { dismiss() }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .parchmentBackground()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(ParchmentTheme.body(.subheadline))
            Spacer()
            Text(value).font(ParchmentTheme.numeric(15, weight: .bold))
        }
        .foregroundStyle(ParchmentTheme.ink)
    }

    static func duration(_ seconds: Double) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .abbreviated
        return f.string(from: seconds) ?? "\(Int(seconds / 60))m"
    }
}
