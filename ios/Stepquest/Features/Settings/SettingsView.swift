import CoreMotion
import StepquestKit
import SwiftUI
import UIKit

/// Health permissions, local leaderboard opt-in, account, and (DEBUG) backend URL + reset.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthService.self) private var auth
    @Environment(HealthKitService.self) private var health
    @Environment(GameStore.self) private var store
    @Environment(ConfigStore.self) private var config
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var displayName = ""
    @State private var localError: String?
    @State private var updatingLocal = false
    #if DEBUG
    @State private var baseURLOverride = UserDefaults.standard.string(forKey: AppConfig.overrideKey) ?? ""
    @State private var confirmReset = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Apple Health", value: health.authorizationRequested ? "Requested" : "Not connected")
                    Button(health.authorizationRequested ? "Re-check Health Access" : "Connect Apple Health") {
                        Task {
                            await health.requestAuthorization()
                            await model.sync(presentAway: false)
                        }
                    }
                    LabeledContent("Motion (Stride Mode)", value: motionStatus)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    if let last = model.lastSync {
                        LabeledContent("Last sync", value: last.formatted(date: .omitted, time: .shortened))
                    }
                    if let error = model.syncError {
                        Text(error).font(ParchmentTheme.body(.caption)).foregroundStyle(ParchmentTheme.crimson)
                    }
                } header: { header("Health") } footer: {
                    Text("Steps you type in by hand are ignored. Health only lets apps know they asked, not what you allowed — manage read access in the Health app › Sharing › Apps.")
                }

                Section {
                    if auth.isSignedIn {
                        LabeledContent("Signed in as", value: auth.player?.displayName ?? "…")
                        HStack {
                            TextField("Display name", text: $displayName)
                            Button("Save") {
                                Task {
                                    do { try await auth.update(PatchMeRequest(displayName: displayName)) } catch { localError = error.localizedDescription }
                                }
                            }
                            .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Toggle(isOn: Binding(get: { auth.player?.localOptIn ?? false }, set: { setLocal($0) })) {
                            VStack(alignment: .leading) {
                                Text("Local leaderboard")
                                Text(auth.player?.region ?? "Region from your network (city level)")
                                    .font(ParchmentTheme.body(.caption2))
                                    .foregroundStyle(ParchmentTheme.inkSoft)
                            }
                        }
                        .disabled(updatingLocal)
                        if let localError {
                            Text(localError).font(ParchmentTheme.body(.caption)).foregroundStyle(ParchmentTheme.crimson)
                        }
                        Button("Sign Out", role: .destructive) { auth.signOut() }
                    } else {
                        Text("Playing offline. Your hero still progresses.")
                        Button("Sign In") {
                            auth.playsOffline = false
                            dismiss()
                        }
                    }
                } header: { header("Account") }

                Section {
                    LabeledContent("Balance tables", value: "v\(config.formulas.version) (\(config.source.rawValue))")
                    LabeledContent("Server", value: model.api.baseURL.absoluteString)
                    LabeledContent("Lifetime foes", value: store.state.lifetime.kills.grouped)
                    LabeledContent("Gates broken", value: store.state.lifetime.gatesBroken.grouped)
                } header: { header("Chronicle") }

                #if DEBUG
                Section {
                    TextField("http://localhost:8787", text: $baseURLOverride)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Apply API URL (relaunch to fully apply)") {
                        let trimmed = baseURLOverride.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            UserDefaults.standard.removeObject(forKey: AppConfig.overrideKey)
                        } else {
                            UserDefaults.standard.set(trimmed, forKey: AppConfig.overrideKey)
                        }
                        model.api.baseURL = AppConfig.apiBaseURL
                    }
                    Button("Simulate 1 hour away") {
                        store.mutate { $0.lastSimulatedAt.addTimeInterval(-3600) }
                        Task { await model.sync(presentAway: true) }
                    }
                    Button("Reset Game", role: .destructive) { confirmReset = true }
                        .confirmationDialog("Erase this save?", isPresented: $confirmReset) {
                            Button("Erase Save", role: .destructive) { store.resetGame() }
                        }
                } header: { header("Debug") }
                #endif
            }
            .scrollContentBackground(.hidden)
            .parchmentBackground()
            .font(ParchmentTheme.body())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear { displayName = auth.player?.displayName ?? "" }
        }
    }

    private var motionStatus: String {
        switch CMPedometer.authorizationStatus() {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Asks on first Stride"
        @unknown default: "Unknown"
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(ParchmentTheme.display(12)).tracking(1.5).foregroundStyle(ParchmentTheme.goldDeep)
    }

    private func setLocal(_ on: Bool) {
        updatingLocal = true
        localError = nil
        Task {
            defer { updatingLocal = false }
            do {
                try await auth.update(PatchMeRequest(localOptIn: on))
            } catch {
                localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
