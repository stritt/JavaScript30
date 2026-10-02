import StepquestKit
import SwiftUI

/// Sepia "chapter" card shown when entering a zone ("The Meadow Road").
struct ZoneTitleCard: View {
    let zone: ZoneDefinition
    var onFinished: () -> Void

    @State private var shown = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x8A6A44), ParchmentTheme.sepia, ParchmentTheme.sepiaDark],
                           startPoint: .top, endPoint: .bottom)
            ParchmentGrain().opacity(1.4).blendMode(.multiply)
            // Vignette.
            RadialGradient(colors: [.clear, .black.opacity(0.65)], center: .center, startRadius: 120, endRadius: 520)

            VStack(spacing: 14) {
                Text("Chapter \(Roman.numeral(zone.id))")
                    .font(ParchmentTheme.display(18, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(Color(hex: 0xF0DDB4).opacity(0.85))
                OrnamentDivider().frame(width: 200)
                Text(zone.name)
                    .font(ParchmentTheme.display(36, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(hex: 0xF7E8C6))
                    .shadow(color: .black.opacity(0.6), radius: 0, x: 2, y: 2)
                OrnamentDivider().frame(width: 200)
                Text("Guarded by \(zone.gate.name)")
                    .font(ParchmentTheme.body(.subheadline).italic())
                    .foregroundStyle(Color(hex: 0xF0DDB4).opacity(0.8))
            }
            .padding(30)
            .scaleEffect(shown ? 1 : 1.08)
            .opacity(shown ? 1 : 0)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onFinished() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .task {
            withAnimation(.easeOut(duration: 0.9)) { shown = true }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeIn(duration: 0.5)) { shown = false }
            try? await Task.sleep(for: .seconds(0.5))
            onFinished()
        }
    }
}
