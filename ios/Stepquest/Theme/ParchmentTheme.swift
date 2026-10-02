import SwiftUI
import UIKit
import StepquestKit

/// Vintage-tactics look: aged parchment, ink, gold leaf, serif display type (GAME_DESIGN.md §0).
/// Visual only — nothing here affects gameplay.
enum ParchmentTheme {
    // MARK: Palette

    static let parchment = Color(hex: 0xEBDDB8)
    static let parchmentLight = Color(hex: 0xF5ECD4)
    static let parchmentDark = Color(hex: 0xD3BE8E)
    static let ink = Color(hex: 0x2B1D10)
    static let inkSoft = Color(hex: 0x5C4630)
    static let gold = Color(hex: 0xD4A82E)
    static let goldLight = Color(hex: 0xF3D77A)
    static let goldDeep = Color(hex: 0x8A6512)
    static let crimson = Color(hex: 0x9A2E22)
    static let forestGreen = Color(hex: 0x3F6B33)
    static let royalBlue = Color(hex: 0x2D4F8E)
    static let sepia = Color(hex: 0x6B4A2B)
    static let sepiaDark = Color(hex: 0x3A2614)
    static let night = Color(hex: 0x14100C)

    static let hpRed = Color(hex: 0xB8382A)
    static let xpBlue = Color(hex: 0x3B6CB5)
    static let stepGreen = Color(hex: 0x4E8A3A)

    static func rarityColor(_ rarityId: String) -> Color {
        switch rarityId {
        case "common": Color(hex: 0x6E6253)
        case "uncommon": Color(hex: 0x3E7D3A)
        case "rare": Color(hex: 0x2C5AA0)
        case "epic": Color(hex: 0x6E3A9E)
        case "legendary": Color(hex: 0xC2701A)
        default: inkSoft
        }
    }

    static func tierColor(_ tierId: String) -> Color {
        switch tierId {
        case "stroll": Color(hex: 0x6E6253)
        case "march": forestGreen
        case "rush": royalBlue
        case "frenzy": crimson
        default: ink
        }
    }

    // MARK: Type

    /// Display face. Uses a bundled "Cinzel" if one is ever added to the app, otherwise the system serif.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if UIFont(name: "Cinzel-Bold", size: size) != nil {
            return .custom("Cinzel-Bold", size: size)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    static func body(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }

    /// Retro digits for counters and damage.
    static func numeric(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let goldGradient = LinearGradient(
        colors: [goldLight, gold, goldDeep], startPoint: .top, endPoint: .bottom)

    static let parchmentGradient = LinearGradient(
        colors: [parchmentLight, parchment, parchmentDark.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: UIKit appearance (tab bar / navigation bar)

    @MainActor
    static func applyGlobalAppearance() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(parchmentDark)
        tab.shadowColor = UIColor(goldDeep)
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(inkSoft)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(inkSoft), .font: serifUIFont(10, bold: false)]
        item.selected.iconColor = UIColor(crimson)
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(crimson), .font: serifUIFont(10, bold: true)]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(parchment)
        nav.shadowColor = UIColor(goldDeep)
        nav.titleTextAttributes = [.foregroundColor: UIColor(ink), .font: serifUIFont(18, bold: true)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(ink), .font: serifUIFont(32, bold: true)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(crimson)

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(gold)
        UISegmentedControl.appearance().backgroundColor = UIColor(parchmentDark)
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(ink), .font: serifUIFont(13, bold: true)], for: .normal)
    }

    static func serifUIFont(_ size: CGFloat, bold: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

extension Int {
    /// "12,345"
    var grouped: String { formatted(.number.grouping(.automatic)) }
}

extension Double {
    var groupedInt: String { Int(self.rounded(.down)).grouped }
}

/// Roman numerals for chapter cards ("Chapter II").
enum Roman {
    static func numeral(_ n: Int) -> String {
        guard n > 0 else { return "" }
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n
        var out = ""
        for (value, symbol) in table {
            while n >= value { out += symbol; n -= value }
        }
        return out
    }
}
