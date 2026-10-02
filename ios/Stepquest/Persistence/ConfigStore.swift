import Foundation
import Observation
import StepquestKit

/// Holds the active balance tables. Starts from the copy bundled in StepquestKit (shared/formulas.json),
/// then prefers a cached `GET /v1/config` response, and refreshes it when online.
@MainActor
@Observable
final class ConfigStore {
    private(set) var formulas: Formulas
    private(set) var source: Source
    private(set) var lastRefresh: Date?

    enum Source: String { case bundled, cached, remote }

    @ObservationIgnored private let cacheURL: URL

    init(directory: URL = FileLocations.appSupport) {
        cacheURL = directory.appendingPathComponent("formulas.json")
        let bundled = Formulas.bundled
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? Formulas.decode(from: data),
           cached.version >= bundled.version {
            formulas = cached
            source = .cached
        } else {
            formulas = bundled
            source = .bundled
        }
    }

    /// Fetches `/v1/config`; invalid or older configs are ignored. Returns true when formulas changed.
    @discardableResult
    func refresh(using api: APIClient) async -> Bool {
        do {
            let data = try await api.configData()
            let remote = try Formulas.decode(from: data)
            lastRefresh = .now
            guard remote.version >= Formulas.bundled.version else { return false }
            try? data.write(to: cacheURL, options: .atomic)
            let changed = remote != formulas
            formulas = remote
            source = .remote
            return changed
        } catch {
            return false
        }
    }
}

enum FileLocations {
    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Stepquest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
