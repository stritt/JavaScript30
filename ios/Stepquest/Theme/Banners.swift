import SwiftUI

/// Big banner-style "Level Up!" text that swoops in, holds, and fades.
struct LevelUpBanner: View {
    let level: Int
    var onFinished: () -> Void = {}
    @State private var appeared = false
    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 4) {
            BannerText(text: "Level Up!", size: 46)
            Text("Lv. \(level)")
                .font(ParchmentTheme.display(22))
                .foregroundStyle(ParchmentTheme.parchmentLight)
                .shadow(color: .black, radius: 0, x: 2, y: 2)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 30)
        .background(
            RibbonShape()
                .fill(LinearGradient(colors: [ParchmentTheme.crimson, Color(hex: 0x5E1A12)], startPoint: .top, endPoint: .bottom))
                .overlay(RibbonShape().stroke(ParchmentTheme.gold, lineWidth: 3))
                .scaleEffect(x: 1.25, y: 1)
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        )
        .scaleEffect(appeared ? 1 : 2.4)
        .opacity(appeared ? 1 : 0)
        .rotationEffect(.degrees(appeared ? 0 : -8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level up! Level \(level)")
        .task {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { appeared = true }
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeIn(duration: 0.35)) { appeared = false }
            try? await Task.sleep(for: .seconds(0.4))
            onFinished()
        }
    }
}

/// Gold-filled, ink-outlined banner lettering.
struct BannerText: View {
    let text: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            // Fake outline: offset copies in ink.
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi
                Text(text)
                    .font(ParchmentTheme.display(size, weight: .black))
                    .foregroundStyle(ParchmentTheme.ink)
                    .offset(x: cos(angle) * 2.5, y: sin(angle) * 2.5)
            }
            Text(text)
                .font(ParchmentTheme.display(size, weight: .black))
                .foregroundStyle(ParchmentTheme.goldGradient)
        }
        .fixedSize()
    }
}

/// Short toast-like ribbon (loot drops, gate damage, etc.).
struct ToastRibbon: View {
    let text: String
    var color: Color = ParchmentTheme.ink

    var body: some View {
        Text(text)
            .font(ParchmentTheme.display(15))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(ParchmentTheme.parchmentLight))
            .overlay(Capsule().stroke(ParchmentTheme.goldDeep, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

/// Labeled stat bar (HP / XP / gate HP) in the retro style.
struct StatBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    var color: Color = ParchmentTheme.hpRed
    var showsNumbers = true
    var height: CGFloat = 12

    private var fraction: Double { maxValue > 0 ? min(1, max(0, value / maxValue)) : 0 }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(ParchmentTheme.display(11))
                .foregroundStyle(ParchmentTheme.inkSoft)
                .frame(width: 26, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(ParchmentTheme.night.opacity(0.75))
                    Rectangle()
                        .fill(LinearGradient(colors: [color.opacity(0.85), color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeOut(duration: 0.3), value: fraction)
                    // Pixel highlight line.
                    Rectangle().fill(.white.opacity(0.25)).frame(height: 2).offset(y: -height / 2 + 2)
                }
                .overlay(Rectangle().stroke(ParchmentTheme.goldDeep, lineWidth: 1.5))
            }
            .frame(height: height)
            if showsNumbers {
                Text("\(Int(value.rounded(.down)).grouped)/\(Int(maxValue).grouped)")
                    .font(ParchmentTheme.numeric(11, weight: .bold))
                    .foregroundStyle(ParchmentTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 54, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value)) of \(Int(maxValue))")
    }
}
