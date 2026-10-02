import SpriteKit
import StepquestKit
import SwiftUI

/// Active play while walking: cadence tier drives damage (Stroll 1× … Frenzy 4×), combo meter,
/// live fights on the trail, haptics. Big type so it can be glanced at, plus a "Look up!" nudge.
struct StrideModeView: View {
    @Environment(GameStore.self) private var store
    @Environment(PedometerService.self) private var pedometer
    @State private var controller: StrideController?
    @State private var scene: TrailScene = MainActor.assumeIsolated {
        let s = TrailScene(size: CGSize(width: 390, height: 260))
        s.mode = .live
        return s
    }

    var body: some View {
        NavigationStack {
            Group {
                if let controller, controller.isActive {
                    activeSession(controller)
                } else {
                    intro
                }
            }
            .parchmentBackground()
            .navigationTitle("Stride Mode")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if controller == nil {
                let c = StrideController(store: store, pedometer: pedometer)
                c.scene = scene
                controller = c
            }
            syncScene()
        }
        .onChange(of: store.state.trail) { _, _ in syncScene() }
        .onDisappear { controller?.stop() }
    }

    private func syncScene() {
        let state = store.state
        let tile = state.trail.isGrinding ? state.trail.grindTile : state.trail.frontierTile
        scene.sync(zone: state.activeZone(store.formulas), tile: tile, atGate: state.isAtGate)
    }

    // MARK: Intro

    private var intro: some View {
        let tiers = store.formulas.stride.tiers
        return ScrollView {
            VStack(spacing: 20) {
                BannerText(text: "Walk to Fight", size: 32)
                    .padding(.top, 10)
                Text("Your cadence is your sword arm. The faster you walk, the harder your hero strikes.")
                    .font(ParchmentTheme.body(.body))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(ParchmentTheme.ink)
                VStack(spacing: 8) {
                    ForEach(tiers) { tier in
                        HStack {
                            Text(tier.name)
                                .font(ParchmentTheme.display(18))
                                .foregroundStyle(ParchmentTheme.tierColor(tier.id))
                            Spacer()
                            Text("\(Int(tier.minSpm))+ spm")
                                .font(ParchmentTheme.numeric(13, weight: .semibold))
                            Text("\(Int(tier.damageMultiplier))×")
                                .font(ParchmentTheme.numeric(18))
                                .frame(width: 44, alignment: .trailing)
                        }
                        .foregroundStyle(ParchmentTheme.ink)
                        if tier.id != tiers.last?.id { Divider().overlay(ParchmentTheme.goldDeep.opacity(0.4)) }
                    }
                    Text("Combo builds in \(tiers.filter(\.combo).map(\.name).joined(separator: " & ")). Stride steps strike Step Gates for \(gateMultiplier)× damage.")
                        .font(ParchmentTheme.body(.footnote))
                        .foregroundStyle(ParchmentTheme.inkSoft)
                        .padding(.top, 4)
                }
                .parchmentPanel(title: "Cadence Tiers")

                Label("Keep your eyes on the path. Nothing here needs constant attention.", systemImage: "eye")
                    .font(ParchmentTheme.body(.footnote, weight: .semibold))
                    .foregroundStyle(ParchmentTheme.crimson)

                Button {
                    controller?.start()
                } label: {
                    Label("Begin the March", systemImage: "figure.walk.motion")
                }
                .buttonStyle(.retroCrimson)

                if pedometer.authorizationDenied {
                    Text("Motion access is off. Enable it in Settings › Privacy › Motion & Fitness.")
                        .font(ParchmentTheme.body(.footnote))
                        .foregroundStyle(ParchmentTheme.crimson)
                }
                #if DEBUG
                debugCadence
                #endif
            }
            .padding()
        }
    }

    private var gateMultiplier: String {
        let m = store.formulas.stride.gateStepMultiplier
        return m == m.rounded() ? String(Int(m)) : String(format: "%.1f", m)
    }

    // MARK: Active session

    private func activeSession(_ controller: StrideController) -> some View {
        let formulas = store.formulas
        let tier = pedometer.tier
        let engine = controller.engine
        return VStack(spacing: 12) {
            // Tier + cadence: the glanceable part.
            VStack(spacing: 2) {
                Text(tier.name.uppercased())
                    .font(ParchmentTheme.display(46, weight: .black))
                    .foregroundStyle(ParchmentTheme.tierColor(tier.id))
                    .contentTransition(.interpolate)
                    .animation(.spring(response: 0.3), value: tier.id)
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    VStack(spacing: 0) {
                        Text("\(Int(pedometer.spm.rounded()))")
                            .font(ParchmentTheme.numeric(54))
                            .contentTransition(.numericText())
                        Text("steps / min").font(ParchmentTheme.body(.caption))
                    }
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f×", engine.currentMultiplier))
                            .font(ParchmentTheme.numeric(54))
                            .foregroundStyle(ParchmentTheme.crimson)
                        Text("damage").font(ParchmentTheme.body(.caption))
                    }
                }
                .foregroundStyle(ParchmentTheme.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tier.name), \(Int(pedometer.spm)) steps per minute, \(String(format: "%.1f", engine.currentMultiplier)) times damage")

            comboMeter(engine: engine, tier: tier, formulas: formulas)

            SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(OrnateBorder(cornerRadius: 8))
                .overlay(alignment: .top) {
                    if let monster = controller.monster {
                        StatBar(label: "", value: Double(monster.currentHP), maxValue: Double(monster.maxHP),
                                color: ParchmentTheme.hpRed, showsNumbers: false, height: 8)
                            .frame(width: 160)
                            .overlay(alignment: .top) {
                                Text(monster.definition.name)
                                    .font(ParchmentTheme.display(12))
                                    .foregroundStyle(ParchmentTheme.parchmentLight)
                                    .offset(y: -16)
                            }
                            .padding(.top, 24)
                    }
                }
                .overlay { if controller.showLookUp { lookUpNudge(controller) } }
                .overlay { if controller.isPaused { pausedOverlay } }

            HStack {
                sessionStat("Steps", engine.sessionSteps.grouped)
                sessionStat("Foes", engine.sessionKills.grouped)
                sessionStat("Gate dmg", engine.sessionGateDamage.groupedInt)
                sessionStat("HP", "\(store.state.hero.currentHP)")
            }
            .parchmentPanel(padding: 8)

            HStack(spacing: 12) {
                Button(controller.isPaused ? "Resume" : "Pause") { controller.togglePause() }
                    .buttonStyle(.retro)
                Button("End March") { controller.stop() }
                    .buttonStyle(RetroButtonStyle(kind: .crimson))
            }
            #if DEBUG
            debugCadence
            #endif
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func comboMeter(engine: StrideEngine, tier: CadenceTier, formulas: Formulas) -> some View {
        let combo = engine.combo
        let level = combo.level(formulas.stride)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tier.combo ? "COMBO ×\(level)" : "COMBO (Rush+)")
                    .font(ParchmentTheme.display(15))
                    .foregroundStyle(tier.combo ? ParchmentTheme.crimson : ParchmentTheme.inkSoft)
                Spacer()
                Text("+\(Int((combo.bonus(formulas.stride) * 100).rounded()))%")
                    .font(ParchmentTheme.numeric(15))
                if tier.critChance > 0 {
                    Text("Crit \(Int(tier.critChance * 100))%")
                        .font(ParchmentTheme.numeric(13, weight: .semibold))
                        .foregroundStyle(ParchmentTheme.goldDeep)
                }
            }
            StatBar(label: "", value: combo.isMaxed(formulas.stride) ? 1 : combo.progressToNextLevel(formulas.stride), maxValue: 1,
                    color: combo.isMaxed(formulas.stride) ? ParchmentTheme.gold : ParchmentTheme.royalBlue, showsNumbers: false, height: 10)
        }
        .foregroundStyle(ParchmentTheme.ink)
        .parchmentPanel(padding: 10)
        .opacity(tier.combo ? 1 : 0.6)
    }

    private func sessionStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(ParchmentTheme.numeric(20)).foregroundStyle(ParchmentTheme.ink)
            Text(label).font(ParchmentTheme.body(.caption2)).foregroundStyle(ParchmentTheme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private func lookUpNudge(_ controller: StrideController) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.fill").font(.system(size: 34, weight: .bold))
            Text("Look up!").font(ParchmentTheme.display(34, weight: .black))
            Text("Eyes on the path — your hero fights on.").font(ParchmentTheme.body(.subheadline, weight: .semibold))
        }
        .foregroundStyle(ParchmentTheme.parchmentLight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ParchmentTheme.night.opacity(0.82))
        .onTapGesture { controller.dismissLookUp() }
        .transition(.opacity)
        .accessibilityAddTraits(.isButton)
    }

    private var pausedOverlay: some View {
        VStack(spacing: 6) {
            Text("PAUSED").font(ParchmentTheme.display(32, weight: .black))
            Text("Your steps still count toward gates.").font(ParchmentTheme.body(.footnote))
        }
        .foregroundStyle(ParchmentTheme.parchmentLight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ParchmentTheme.night.opacity(0.7))
    }

    #if DEBUG
    private var debugCadence: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG: simulate walking (Simulator has no pedometer)")
                .font(ParchmentTheme.numeric(10))
            HStack {
                ForEach([nil, 40.0, 80.0, 115.0, 145.0] as [Double?], id: \.self) { spm in
                    Button(spm.map { "\(Int($0))" } ?? "Off") { pedometer.setSimulatedCadence(spm) }
                        .buttonStyle(.bordered)
                        .tint(pedometer.simulatedSpm == spm ? ParchmentTheme.crimson : ParchmentTheme.inkSoft)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).stroke(ParchmentTheme.inkSoft, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
    #endif
}
