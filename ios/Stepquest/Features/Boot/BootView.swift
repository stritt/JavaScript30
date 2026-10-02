import SwiftUI

/// Retro console-style boot sequence: black screen, a spinning gold crest, the logo
/// shimmering in, a fake "studio" line and a blinking prompt. Tap to skip.
struct BootView: View {
    var onFinished: () -> Void

    @State private var phase = 0
    @State private var spin = false
    @State private var blink = false
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [ParchmentTheme.sepia.opacity(phase >= 2 ? 0.55 : 0), .clear],
                           center: .center, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeIn(duration: 1.2), value: phase)

            VStack(spacing: 22) {
                Crest()
                    .frame(width: 92, height: 92)
                    .rotation3DEffect(.degrees(spin ? 360 : 0), axis: (x: 0, y: 1, z: 0))
                    .opacity(phase >= 1 ? 1 : 0)
                    .scaleEffect(phase >= 1 ? 1 : 0.3)

                BannerText(text: "STEPQUEST", size: 44)
                    .opacity(phase >= 2 ? 1 : 0)
                    .blur(radius: phase >= 2 ? 0 : 8)

                Text("A WALKING CHRONICLE")
                    .font(ParchmentTheme.display(13))
                    .tracking(5)
                    .foregroundStyle(ParchmentTheme.goldLight.opacity(0.85))
                    .opacity(phase >= 3 ? 1 : 0)
            }

            VStack {
                Spacer()
                Text("PRESS ANYWHERE")
                    .font(ParchmentTheme.numeric(14, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(blink ? 0.9 : 0.15))
                    .opacity(phase >= 3 ? 1 : 0)
                Text("© Stepquest. Original work, all rights reserved.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .opacity(phase >= 2 ? 1 : 0)
            }

            Scanlines().ignoresSafeArea().allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stepquest. Tap to start.")
        .accessibilityAddTraits(.isButton)
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { phase = 1 }
            withAnimation(.easeInOut(duration: 1.2)) { spin = true }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.8)) { phase = 2 }
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeOut(duration: 0.5)) { phase = 3 }
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { blink = true }
            try? await Task.sleep(for: .milliseconds(1600))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}

/// Gold diamond crest with an inset boot-print glyph.
private struct Crest: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(ParchmentTheme.goldGradient)
                .rotationEffect(.degrees(45))
                .overlay(Rectangle().stroke(ParchmentTheme.goldLight, lineWidth: 2).rotationEffect(.degrees(45)))
                .padding(12)
            Rectangle()
                .stroke(ParchmentTheme.goldDeep, lineWidth: 2)
                .rotationEffect(.degrees(45))
                .padding(20)
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(ParchmentTheme.ink)
        }
        .shadow(color: ParchmentTheme.gold.opacity(0.6), radius: 12)
    }
}

/// CRT scanline overlay.
struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                y += 3
            }
        }
    }
}
