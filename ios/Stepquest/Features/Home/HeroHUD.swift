import StepquestKit
import SwiftUI

/// Stat panel: portrait, name, level, HP / XP bars, gold.
struct HeroHUD: View {
    let hero: Hero
    let formulas: Formulas

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HeroPortrait()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(hero.name)
                        .font(ParchmentTheme.display(16))
                        .foregroundStyle(ParchmentTheme.ink)
                    Spacer()
                    Text("Lv.\(hero.level)")
                        .font(ParchmentTheme.numeric(14))
                        .foregroundStyle(ParchmentTheme.crimson)
                    Label("\(hero.gold.grouped)", systemImage: "circle.hexagongrid.fill")
                        .font(ParchmentTheme.numeric(12, weight: .bold))
                        .foregroundStyle(ParchmentTheme.goldDeep)
                        .labelStyle(.titleAndIcon)
                }
                StatBar(label: "HP", value: Double(hero.currentHP), maxValue: Double(hero.maxHP(formulas)), color: ParchmentTheme.hpRed)
                if hero.isMaxLevel(formulas) {
                    StatBar(label: "XP", value: 1, maxValue: 1, color: ParchmentTheme.xpBlue, showsNumbers: false)
                } else {
                    StatBar(label: "XP", value: Double(hero.xp), maxValue: Double(hero.xpToNext(formulas)), color: ParchmentTheme.xpBlue)
                }
            }
        }
        .parchmentPanel(padding: 10)
    }
}

/// Framed chibi portrait drawn in SwiftUI (matches the SpriteKit hero's colors).
struct HeroPortrait: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [ParchmentTheme.royalBlue.opacity(0.6), ParchmentTheme.night],
                                                                   startPoint: .top, endPoint: .bottom))
            Canvas { ctx, size in
                let s = min(size.width, size.height) / 16
                func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                    ctx.fill(Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s)), with: .color(c))
                }
                let skin = Color(hex: 0xF2C9A0), hair = Color(hex: 0x6B3E1F), tunic = ParchmentTheme.royalBlue
                px(3, 12, 10, 4, tunic)
                px(3, 12, 10, 1, ParchmentTheme.gold)
                px(4, 3, 8, 9, skin)
                px(3, 2, 10, 3, hair)
                px(3, 5, 2, 3, hair)
                px(11, 5, 2, 3, hair)
                px(6, 7, 1, 2, ParchmentTheme.ink)
                px(9, 7, 1, 2, ParchmentTheme.ink)
                px(7, 10, 2, 1, Color(hex: 0xC27A5A))
            }
            .padding(2)
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(ParchmentTheme.goldDeep, lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(ParchmentTheme.gold, lineWidth: 1).padding(3))
        .accessibilityHidden(true)
    }
}
