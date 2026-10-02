import SwiftUI

/// Aged-paper panel with an ornate double gold border and corner studs.
struct ParchmentPanel: ViewModifier {
    var title: String?
    var padding: CGFloat = 14
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .padding(.top, title == nil ? 0 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(ParchmentTheme.parchmentGradient)
                    ParchmentGrain()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    // Burned edge vignette.
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(ParchmentTheme.sepia.opacity(0.35), lineWidth: 8)
                        .blur(radius: 6)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
            .overlay { OrnateBorder(cornerRadius: cornerRadius) }
            .overlay(alignment: .top) {
                if let title {
                    TitleRibbon(text: title).offset(y: -14)
                }
            }
            .shadow(color: ParchmentTheme.night.opacity(0.35), radius: 4, x: 0, y: 3)
    }
}

/// Outer dark-gold stroke, inner bright-gold hairline and diamond studs at the corners.
struct OrnateBorder: View {
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(ParchmentTheme.goldDeep, lineWidth: 3)
            RoundedRectangle(cornerRadius: max(0, cornerRadius - 4))
                .strokeBorder(ParchmentTheme.gold, lineWidth: 1)
                .padding(5)
            GeometryReader { geo in
                let inset: CGFloat = 5
                ForEach(0..<4, id: \.self) { i in
                    let x = i % 2 == 0 ? inset : geo.size.width - inset
                    let y = i < 2 ? inset : geo.size.height - inset
                    CornerStud().position(x: x, y: y)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct CornerStud: View {
    var body: some View {
        Rectangle()
            .fill(ParchmentTheme.goldGradient)
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(45))
            .overlay(Rectangle().stroke(ParchmentTheme.goldDeep, lineWidth: 1).rotationEffect(.degrees(45)))
    }
}

/// Small gold ribbon used as a panel title.
struct TitleRibbon: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(ParchmentTheme.display(13))
            .tracking(1.5)
            .foregroundStyle(ParchmentTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RibbonShape()
                    .fill(ParchmentTheme.goldGradient)
                    .overlay(RibbonShape().stroke(ParchmentTheme.goldDeep, lineWidth: 1.5))
            )
    }
}

struct RibbonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notch: CGFloat = 8
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + notch, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// Deterministic speckle texture so the paper doesn't look flat.
struct ParchmentGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x5EED
            func rand() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 11) / Double(1 << 53)
            }
            let count = Int(size.width * size.height / 180)
            for _ in 0..<count {
                let rect = CGRect(x: rand() * size.width, y: rand() * size.height, width: 1 + rand() * 2, height: 1 + rand() * 1.5)
                context.fill(Path(ellipseIn: rect), with: .color(ParchmentTheme.sepia.opacity(0.05 + rand() * 0.08)))
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func parchmentPanel(title: String? = nil, padding: CGFloat = 14) -> some View {
        modifier(ParchmentPanel(title: title, padding: padding))
    }

    /// Full-screen parchment backdrop for list/scroll screens.
    func parchmentBackground() -> some View {
        background {
            ZStack {
                ParchmentTheme.parchment
                ParchmentGrain()
            }
            .ignoresSafeArea()
        }
    }
}

/// Gold divider with a center diamond.
struct OrnamentDivider: View {
    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(ParchmentTheme.goldDeep).frame(height: 1)
            CornerStud().scaleEffect(0.8)
            Rectangle().fill(ParchmentTheme.goldDeep).frame(height: 1)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
