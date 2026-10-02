import SpriteKit
import StepquestKit
import SwiftUI

/// The trail: isometric diorama with the hero HUD, today's steps and gate progress.
struct HomeView: View {
    var openStride: () -> Void
    var openMap: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(GameStore.self) private var store
    @Environment(HealthKitService.self) private var health

    @State private var scene: TrailScene = MainActor.assumeIsolated {
        let s = TrailScene(size: CGSize(width: 390, height: 380))
        s.mode = .idle
        return s
    }
    @State private var showSettings = false
    @State private var showGate = false

    /// While the trail is on screen, idle time is simulated every few seconds so the hero visibly walks.
    private let tickInterval: Duration = .seconds(4)

    var body: some View {
        let formulas = store.formulas
        let state = store.state
        NavigationStack {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                        .frame(height: 340)
                        .overlay(alignment: .bottom) {
                            zoneBadge(state.activeZone(formulas), grinding: state.trail.isGrinding)
                                .padding(.bottom, 8)
                        }
                        .accessibilityLabel("Trail view. \(state.hero.name) walking \(state.activeZone(formulas).name).")
                    HeroHUD(hero: state.hero, formulas: formulas)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
                ScrollView {
                    VStack(spacing: 22) {
                        stepsPanel
                        progressPanel(state: state, formulas: formulas)
                        Button {
                            openStride()
                        } label: {
                            Label("Enter Stride Mode", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.retroCrimson)
                    }
                    .padding(.horizontal)
                    .padding(.top, 22)
                    .padding(.bottom, 30)
                }
                .refreshable { await model.sync(presentAway: false) }
            }
            .parchmentBackground()
            .navigationTitle("The Trail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if model.isSyncing { ProgressView().controlSize(.small) }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showGate) {
                GateView(openStride: {
                    showGate = false
                    openStride()
                })
            }
        }
        .onAppear { syncScene() }
        .onChange(of: store.state.trail) { _, _ in syncScene() }
        .onChange(of: store.state.gate) { _, _ in syncScene() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard !Task.isCancelled else { break }
                let summary = store.tick()
                scene.play(fights: summary.recentFights)
            }
        }
    }

    private func syncScene() {
        let state = store.state
        let formulas = store.formulas
        let zone = state.activeZone(formulas)
        let tile = state.trail.isGrinding ? state.trail.grindTile : state.trail.frontierTile
        scene.sync(zone: zone, tile: tile, atGate: state.isAtGate)
    }

    // MARK: Panels

    private var stepsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !health.authorizationRequested {
                Text("Connect Apple Health so your real steps power the hero.")
                    .font(ParchmentTheme.body(.subheadline))
                    .foregroundStyle(ParchmentTheme.ink)
                RetroButton("Connect Health", systemImage: "heart.fill") {
                    Task {
                        await health.requestAuthorization()
                        await model.sync(presentAway: false)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(health.todaySteps.grouped)
                            .font(ParchmentTheme.numeric(34))
                            .foregroundStyle(ParchmentTheme.ink)
                            .contentTransition(.numericText())
                        Text("steps today")
                            .font(ParchmentTheme.body(.caption))
                            .foregroundStyle(ParchmentTheme.inkSoft)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("\(health.weekSteps.grouped) this week", systemImage: "calendar")
                        Label("\(health.todayFlights) flights", systemImage: "stairs")
                        Label("\(Int(store.formulas.idle.energyPerBonusTile)) steps = 1 bonus tile", systemImage: "sparkles")
                    }
                    .font(ParchmentTheme.body(.caption))
                    .foregroundStyle(ParchmentTheme.inkSoft)
                }
            }
        }
        .parchmentPanel(title: "Today's March")
    }

    @ViewBuilder
    private func progressPanel(state: GameState, formulas: Formulas) -> some View {
        let frontier = state.frontierZone(formulas)
        VStack(alignment: .leading, spacing: 10) {
            if state.trail.isGrinding {
                Text("Patrolling \(state.activeZone(formulas).name) for loot and experience.")
                    .font(ParchmentTheme.body(.subheadline))
                RetroButton("Return to the Frontier", systemImage: "arrow.uturn.forward") { store.travel(to: nil) }
            }
            if let gate = state.gate, !gate.isBroken {
                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(ParchmentTheme.crimson)
                    Text(gate.name)
                        .font(ParchmentTheme.display(18))
                    Spacer()
                    Text("Step Gate")
                        .font(ParchmentTheme.body(.caption, weight: .bold))
                        .foregroundStyle(ParchmentTheme.crimson)
                }
                StatBar(label: "HP", value: Double(gate.remaining), maxValue: Double(gate.stepHP), color: ParchmentTheme.crimson, height: 14)
                Text("Walk \(gate.remaining.grouped) more steps to break it. Stride Mode steps count \(formatted(formulas.stride.gateStepMultiplier))×.")
                    .font(ParchmentTheme.body(.footnote))
                    .foregroundStyle(ParchmentTheme.inkSoft)
                RetroButton("Face the Guardian", systemImage: "figure.fencing") { showGate = true }
            } else if state.trail.allZonesCleared {
                Text("Every gate has fallen. The road loops on — keep marching for loot and glory.")
                    .font(ParchmentTheme.body(.subheadline))
            } else {
                HStack {
                    Text(frontier.name).font(ParchmentTheme.display(17))
                    Spacer()
                    Button("Map", action: openMap).font(ParchmentTheme.body(.caption, weight: .bold))
                }
                StatBar(label: "Road", value: state.trail.frontierTile, maxValue: Double(frontier.lengthTiles),
                        color: ParchmentTheme.stepGreen, height: 14)
                Text("\(state.tilesToGate(formulas).groupedInt) tiles to \(frontier.gate.name).")
                    .font(ParchmentTheme.body(.footnote))
                    .foregroundStyle(ParchmentTheme.inkSoft)
            }
        }
        .foregroundStyle(ParchmentTheme.ink)
        .parchmentPanel(title: "Chapter \(Roman.numeral(frontier.id))")
    }

    private func zoneBadge(_ zone: ZoneDefinition, grinding: Bool) -> some View {
        Text(grinding ? "\(zone.name) · Patrol" : zone.name)
            .font(ParchmentTheme.display(12))
            .tracking(1)
            .foregroundStyle(ParchmentTheme.parchmentLight)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(ParchmentTheme.sepiaDark.opacity(0.85)))
            .overlay(Capsule().stroke(ParchmentTheme.gold, lineWidth: 1))
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
