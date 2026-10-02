import AuthenticationServices
import SwiftUI

/// Sign in with Apple (plus dev login in DEBUG builds) or play offline.
struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @State private var devName = "Tester"

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            BannerText(text: "Stepquest", size: 42)
            Text("Your steps are the hero's strength.")
                .font(ParchmentTheme.body(.headline))
                .foregroundStyle(ParchmentTheme.inkSoft)

            VStack(alignment: .leading, spacing: 10) {
                Label("Walk to march your hero down the trail", systemImage: "figure.walk")
                Label("Break Step Gates with real steps", systemImage: "door.left.hand.closed")
                Label("Climb friends, local and global boards", systemImage: "trophy")
            }
            .font(ParchmentTheme.body(.subheadline))
            .foregroundStyle(ParchmentTheme.ink)
            .parchmentPanel(title: "The Road Ahead")
            .padding(.horizontal)

            SignInWithAppleButton(.signIn) { request in
                auth.configure(request)
            } onCompletion: { result in
                Task { await auth.handleAppleCompletion(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ParchmentTheme.gold, lineWidth: 2))
            .padding(.horizontal, 32)
            .disabled(auth.isWorking)

            #if DEBUG
            VStack(spacing: 8) {
                Text("DEV LOGIN (backend DEV_AUTH=true)")
                    .font(ParchmentTheme.numeric(11))
                    .foregroundStyle(ParchmentTheme.inkSoft)
                HStack {
                    TextField("Display name", text: $devName)
                        .textFieldStyle(.roundedBorder)
                        .font(ParchmentTheme.body())
                    Button("Dev Login") { Task { await auth.devLogin(displayName: devName) } }
                        .buttonStyle(.retro)
                }
            }
            .padding(.horizontal, 32)
            #endif

            if auth.isWorking { ProgressView().tint(ParchmentTheme.crimson) }
            if let error = auth.lastError {
                Text(error)
                    .font(ParchmentTheme.body(.footnote))
                    .foregroundStyle(ParchmentTheme.crimson)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Play offline for now") { auth.playsOffline = true }
                .font(ParchmentTheme.body(.footnote, weight: .semibold))
                .foregroundStyle(ParchmentTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .parchmentBackground()
    }
}
