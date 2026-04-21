import Foundation
import AppKit

@MainActor
final class BlockManager: ObservableObject {
    @Published var config = BlockConfig()
    @Published var currentState: BlockState?
    @Published var currentAdditions: BlockAdditions = BlockAdditions()
    @Published var remainingSeconds: Int = 0

    private let configURL: URL
    private let additionsURL: URL
    private let stateFile = "/var/db/harbour/state.json"
    private var timer: Timer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Harbour")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("config.json")
        self.additionsURL = dir.appendingPathComponent("additions.json")

        loadConfig()
        refreshState()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshState() }
        }
    }

    var isActive: Bool { currentState != nil }

    /// All domains currently being enforced: original state ∪ runtime additions.
    var effectiveDomains: [String] {
        guard let s = currentState else { return [] }
        var seen = Set<String>()
        return (s.domains + currentAdditions.domains).filter { seen.insert($0).inserted }
    }

    /// All app bundles currently being enforced (returned with display metadata
    /// where available).
    var effectiveApps: [BlockedApp] {
        guard let s = currentState else { return [] }
        // Reconstruct apps from the original paths — we don't have the original
        // BlockedApp metadata on disk, so build minimal records the active view
        // can render with the system icon lookup.
        let originals: [BlockedApp] = zip(s.blockedPaths, s.blockedBundleIDs).map { path, bid in
            let name = (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
            return BlockedApp(name: name, path: path, bundleID: bid)
        }
        var seen = Set<String>()
        return (originals + currentAdditions.apps).filter { seen.insert($0.path).inserted }
    }

    func loadConfig() {
        guard let data = try? Data(contentsOf: configURL) else { return }
        if let decoded = try? JSONDecoder().decode(BlockConfig.self, from: data) {
            self.config = decoded
        }
    }

    func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL)
    }

    func refreshState() {
        if let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)),
           let state = try? JSONDecoder().decode(BlockState.self, from: data),
           state.endTime > Date() {
            self.currentState = state
            self.remainingSeconds = max(0, Int(state.endTime.timeIntervalSinceNow))
            self.currentAdditions = loadAdditions()
        } else {
            self.currentState = nil
            self.remainingSeconds = 0
            self.currentAdditions = BlockAdditions()
            // Stale additions file from a previous block? Clean it up.
            try? FileManager.default.removeItem(at: additionsURL)
        }
    }

    func startBlock() throws {
        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(config.durationMinutes * 60))
        let state = BlockState(
            startTime: now,
            endTime: end,
            domains: config.domains,
            blockedPaths: config.apps.map(\.path),
            blockedBundleIDs: config.apps.map(\.bundleID),
            additionsPath: additionsURL.path
        )
        // Reset any stale additions from a prior block.
        try? FileManager.default.removeItem(at: additionsURL)
        try HelperInstaller.installAndStart(state: state)
        refreshState()
    }

    // MARK: - Runtime additions (can only grow the blocklist, never shrink)

    private func loadAdditions() -> BlockAdditions {
        guard let data = try? Data(contentsOf: additionsURL) else { return BlockAdditions() }
        return (try? JSONDecoder().decode(BlockAdditions.self, from: data)) ?? BlockAdditions()
    }

    private func writeAdditions(_ a: BlockAdditions) {
        guard let data = try? JSONEncoder().encode(a) else { return }
        try? data.write(to: additionsURL, options: .atomic)
        self.currentAdditions = a
    }

    /// Append a domain to the active blocklist. No-op if already covered.
    func addDomainLive(_ input: String) {
        guard currentState != nil else { return }
        var d = input.trimmingCharacters(in: .whitespaces).lowercased()
        d = d.replacingOccurrences(of: "https://", with: "")
        d = d.replacingOccurrences(of: "http://", with: "")
        d = d.components(separatedBy: "/").first ?? d
        guard !d.isEmpty else { return }

        let alreadyBlocked = (currentState?.domains.contains(d) ?? false)
            || currentAdditions.domains.contains(d)
        guard !alreadyBlocked else { return }

        var additions = currentAdditions
        additions.domains.append(d)
        writeAdditions(additions)
    }

    /// Append an app to the active blocklist. No-op if already covered.
    func addAppLive(_ app: BlockedApp) {
        guard let state = currentState else { return }
        let already = state.blockedPaths.contains(app.path)
            || currentAdditions.apps.contains(where: { $0.path == app.path })
        guard !already else { return }

        var additions = currentAdditions
        additions.apps.append(app)
        writeAdditions(additions)
    }
}
