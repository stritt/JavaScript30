import StepquestKit
import SwiftUI

/// The Gate Guardian: a real-steps HP bar. Only steps taken after reaching it count;
/// Stride Mode steps count `gateStepMultiplier`×.
struct GateView: View {
    var openStride: () -> Void
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false

    var body: some View {
        let formulas = store.formulas
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let gate = store.state.gate, !gate.isBroken {
                        guardianArt(zoneId: gate.zoneId)
                        BannerText(text: gate.name, size: 28)
                        VStack(alignment: .leading, spacing: 10) {
                            StatBar(label: "HP", value: Double(gate.remaining), maxValue: Double(gate.stepHP),
                                    color: ParchmentTheme.crimson, height: 18)
                            HStack {
                                stat("Damage dealt", gate.damage.groupedInt)
                                Spacer()
                                stat("Steps to break", gate.stepsToBreak.grouped)
                                Spacer()
                                stat("…in Stride Mode", gate.strideStepsToBreak(formulas.stride).grouped)
                            }
                            Text("Reached \(gate.reachedAt.formatted(date: .abbreviated, time: .shortened)). Only steps taken since then count — idle walking can't harm a guardian.")
                                .font(ParchmentTheme.body(.footnote))
                                .foregroundStyle(ParchmentTheme.inkSoft)
                        }
                        .parchmentPanel(title: "Step Gate")

                        Button(action: openStride) {
                            Label("Charge in Stride Mode (\(multiplier(formulas))× damage)", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.retroCrimson)
                    } else {
                        BannerText(text: "The way is open", size: 28)
                        Text("No guardian bars your path right now. Keep walking!")
                            .font(ParchmentTheme.body())
                    }
                }
                .padding()
            }
            .parchmentBackground()
            .navigationTitle("Gate Guardian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
    }

    private func guardianArt(zoneId: Int) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [ParchmentTheme.crimson.opacity(0.5), .clear], center: .center, startRadius: 10, endRadius: 110))
                .frame(width: 220, height: 220)
                .scaleEffect(pulse ? 1.08 : 0.95)
            Image(systemName: zoneId == 2 ? "hare.fill" : zoneId == 3 ? "crown.fill" : "shield.lefthalf.filled")
                .font(.system(size: 90, weight: .black))
                .foregroundStyle(ParchmentTheme.goldGradient)
                .shadow(color: .black.opacity(0.6), radius: 0, x: 3, y: 3)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(ParchmentTheme.numeric(17)).foregroundStyle(ParchmentTheme.ink)
            Text(label).font(ParchmentTheme.body(.caption2)).foregroundStyle(ParchmentTheme.inkSoft)
        }
    }

    private func multiplier(_ formulas: Formulas) -> String {
        let m = formulas.stride.gateStepMultiplier
        return m == m.rounded() ? String(Int(m)) : String(format: "%.1f", m)
    }
}
