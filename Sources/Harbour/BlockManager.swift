import Foundation
import AppKit

@MainActor
final class BlockManager: ObservableObject {
    @Published var config = BlockConfig()
    @Published var currentState: BlockState?
    @Published var remainingSeconds: Int = 0

    private let configURL: URL
    private let stateFile = "/var/db/harbour/state.json"
    private var timer: Timer?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Harbour")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("config.json")

        loadConfig()
        refreshState()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshState() }
        }
    }

    var isActive: Bool { currentState != nil }

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
        } else {
            self.currentState = nil
            self.remainingSeconds = 0
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
            blockedBundleIDs: config.apps.map(\.bundleID)
        )
        try HelperInstaller.installAndStart(state: state)
        refreshState()
    }
}
