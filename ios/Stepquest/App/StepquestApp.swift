import SwiftUI

@main
struct StepquestApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // App.init runs on the main thread; be explicit for SDKs where App isn't @MainActor.
        _model = State(initialValue: MainActor.assumeIsolated { AppModel() })
        MainActor.assumeIsolated { ParchmentTheme.applyGlobalAppearance() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.store)
                .environment(model.auth)
                .environment(model.health)
                .environment(model.pedometer)
                .environment(model.config)
                .preferredColorScheme(.light)
                .tint(ParchmentTheme.crimson)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.handleForeground() }
            case .background: model.handleBackground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AppModel.refreshTaskId)) {
            await model.backgroundRefresh()
        }
    }
}
