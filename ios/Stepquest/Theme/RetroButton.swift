import SwiftUI
import UIKit

/// Beveled gold "menu command" button.
struct RetroButtonStyle: ButtonStyle {
    enum Kind { case gold, crimson, plain }
    var kind: Kind = .gold
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(ParchmentTheme.display(large ? 22 : 16))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(kind == .crimson ? ParchmentTheme.parchmentLight : ParchmentTheme.ink)
            .padding(.horizontal, large ? 24 : 16)
            .padding(.vertical, large ? 16 : 10)
            .frame(maxWidth: large ? .infinity : nil)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(fill)
                    // Top highlight / bottom shade for the bevel.
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(pressed ? 0.1 : 0.55), .black.opacity(0.35)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 2)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ParchmentTheme.ink.opacity(0.8), lineWidth: 1.5))
            .offset(y: pressed ? 2 : 0)
            .shadow(color: .black.opacity(pressed ? 0.1 : 0.35), radius: 0, x: 0, y: pressed ? 0 : 3)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .onChange(of: pressed) { _, isPressed in
                if isPressed { Haptics.tap() }
            }
    }

    private var fill: AnyShapeStyle {
        switch kind {
        case .gold: AnyShapeStyle(ParchmentTheme.goldGradient)
        case .crimson: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xC2493A), ParchmentTheme.crimson, Color(hex: 0x5E1A12)],
                                                    startPoint: .top, endPoint: .bottom))
        case .plain: AnyShapeStyle(ParchmentTheme.parchmentLight)
        }
    }
}

extension ButtonStyle where Self == RetroButtonStyle {
    static var retro: RetroButtonStyle { RetroButtonStyle() }
    static var retroLarge: RetroButtonStyle { RetroButtonStyle(large: true) }
    static var retroCrimson: RetroButtonStyle { RetroButtonStyle(kind: .crimson, large: true) }
    static var retroPlain: RetroButtonStyle { RetroButtonStyle(kind: .plain) }
}

/// Menu-blip haptic. SwiftUI calls button callbacks on the main thread.
enum Haptics {
    static func tap() {
        MainActor.assumeIsolated {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        }
    }
}

/// Convenience wrapper.
struct RetroButton: View {
    let title: String
    var systemImage: String?
    var style: RetroButtonStyle = .init()
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, style: RetroButtonStyle = .init(), action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(style)
    }
}
