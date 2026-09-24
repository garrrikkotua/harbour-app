import Foundation
import AppKit
import HarbourCore

// MARK: - Demo mode (screenshots / QA)
//
// Launch the GUI binary directly with one of these environment variables:
//
//   HARBOUR_DEMO=active        Fake a running block (started 45 min ago, ends in
//                              1h14m32s, a dozen Social + Video domains, a few
//                              real apps). Never reads /var/db or touches the
//                              daemon; live additions stay in memory.
//   HARBOUR_DEMO=idle          Force the idle state. "Start block" fakes a block
//                              in memory instead of installing the helper.
//   HARBOUR_DEMO_ONBOARDING=1  Show onboarding regardless of the stored
//                              `harbour.didOnboard` flag (the flag is not changed).
//   HARBOUR_DEMO_STEP=1…4      With HARBOUR_DEMO_ONBOARDING=1: skip the intro and
//                              open that onboarding step directly.
//   HARBOUR_DEMO_SHEET=confirm|faq|apps
//                              With HARBOUR_DEMO set: open that sheet over the
//                              setup (faq/apps also over the active) screen.
//
// e.g. HARBOUR_DEMO=active "build/Harbour Control.app/Contents/MacOS/Harbour"
enum DemoMode: Equatable {
    case active
    case idle

    static let current: DemoMode? = {
        switch ProcessInfo.processInfo.environment["HARBOUR_DEMO"]?.lowercased() {
        case "active": return .active
        case "idle": return .idle
        default: return nil
        }
    }()

    static let forcesOnboarding: Bool =
        ProcessInfo.processInfo.environment["HARBOUR_DEMO_ONBOARDING"] == "1"

    /// Zero-based onboarding step to jump straight to, skipping the intro.
    static let onboardingStep: Int? = {
        guard forcesOnboarding,
              let raw = ProcessInfo.processInfo.environment["HARBOUR_DEMO_STEP"],
              let n = Int(raw), (1...4).contains(n) else { return nil }
        return n - 1
    }()

    /// Freezes the intro at this many seconds (QA screenshots only).
    static let introTime: Double? = {
        guard forcesOnboarding,
              let raw = ProcessInfo.processInfo.environment["HARBOUR_DEMO_INTRO_T"] else { return nil }
        return Double(raw)
    }()

    /// Shows the menu bar popover's content in the main window (QA
    /// screenshots only; the real popover can't be captured on its own).
    static let showsPopover: Bool =
        current != nil && ProcessInfo.processInfo.environment["HARBOUR_DEMO_POPOVER"] == "1"

    enum Sheet: String { case confirm, faq, apps }

    /// Sheet to present on appear — demo mode only, so a real install can
    /// never be nudged towards the confirmation dialog.
    static let sheet: Sheet? = {
        guard current != nil,
              let raw = ProcessInfo.processInfo.environment["HARBOUR_DEMO_SHEET"] else { return nil }
        return Sheet(rawValue: raw.lowercased())
    }()
}

@MainActor
final class BlockManager: ObservableObject {
    @Published var isStarting = false
    @Published var config = BlockConfig()
    @Published var currentState: BlockState?
    @Published var currentAdditions: BlockAdditions = BlockAdditions()
    @Published var remainingSeconds: Int = 0

    private let configURL: URL
    private let additionsURL: URL
    private let stateFile = "/var/db/harbour/state.json"
    private var timer: Timer?

    /// Demo-only in-memory block; nil outside demo mode or when demo-idle.
    private let demo: DemoMode? = DemoMode.current
    private var demoState: BlockState?
    private var demoAdditions = BlockAdditions()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Harbour")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("config.json")
        self.additionsURL = dir.appendingPathComponent("additions.json")

        loadConfig()
        if demo == .active { demoState = Self.makeDemoState() }
        refreshState()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Timer fires on the RunLoop it was scheduled on (main). Our
            // init is @MainActor, so we're already on the right isolation —
            // explicitly hop to silence Swift 6's concurrency checker.
            Task { @MainActor [self] in
                self.refreshState()
            }
        }
    }

    var isActive: Bool { currentState != nil }

    /// Full length of the current block in seconds (0 when idle).
    var totalSeconds: Int {
        guard let s = currentState else { return 0 }
        return max(0, Int(s.endTime.timeIntervalSince(s.startTime).rounded()))
    }

    /// Elapsed fraction of the current block, 0...1 (0 when idle).
    var progress: Double {
        let total = totalSeconds
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(remainingSeconds) / Double(total)))
    }

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
        // Demo sessions start from an empty list so recordings show it filling up.
        guard demo == nil else { return }
        guard let data = try? Data(contentsOf: configURL) else { return }
        if let decoded = try? JSONDecoder().decode(BlockConfig.self, from: data) {
            self.config = decoded
        }
    }

    func saveConfig() {
        // Demo sessions edit the list freely without touching the real config.
        guard demo == nil else { return }
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    func refreshState() {
        // Only publish when something actually changed — this runs every
        // second and every assignment to a @Published property re-renders
        // the window and the menu bar label.
        let state = readState()
        if let state, state.endTime > Date() {
            if !Self.sameBlock(currentState, state) { self.currentState = state }
            let remaining = max(0, Int(state.endTime.timeIntervalSinceNow))
            if remaining != remainingSeconds { self.remainingSeconds = remaining }
            let additions = loadAdditions()
            if !Self.sameAdditions(additions, currentAdditions) { self.currentAdditions = additions }
        } else {
            if currentState != nil { self.currentState = nil }
            if remainingSeconds != 0 { self.remainingSeconds = 0 }
            if !Self.sameAdditions(currentAdditions, BlockAdditions()) {
                self.currentAdditions = BlockAdditions()
            }
            if demo != nil {
                demoState = nil
                demoAdditions = BlockAdditions()
            } else if state != nil || !FileManager.default.fileExists(atPath: stateFile) {
                // Stale additions file from a previous block? Clean it up —
                // but only once the saved state is known to be over (decoded
                // and expired, or removed). A transient read or decode failure
                // of a live state.json must not wipe the runtime additions.
                try? FileManager.default.removeItem(at: additionsURL)
            }
        }
    }

    private func readState() -> BlockState? {
        if demo != nil { return demoState }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)) else { return nil }
        return try? JSONDecoder().decode(BlockState.self, from: data)
    }

    private static func sameBlock(_ a: BlockState?, _ b: BlockState) -> Bool {
        guard let a else { return false }
        return a.startTime == b.startTime && a.endTime == b.endTime
            && a.domains == b.domains && a.blockedPaths == b.blockedPaths
    }

    private static func sameAdditions(_ a: BlockAdditions, _ b: BlockAdditions) -> Bool {
        a.domains == b.domains && a.apps.map(\.path) == b.apps.map(\.path)
    }

    func startBlock() async throws {
        guard !isStarting else { return }
        refreshState()
        guard !isActive else { throw HarbourError.installFailed("A block is already running") }
        guard (1...1440).contains(config.durationMinutes),
              !(config.domains.isEmpty && config.apps.isEmpty),
              config.domains.allSatisfy(DomainValidation.isSafeDomain),
              config.apps.allSatisfy({ Safety.isBlockableAppPath($0.path) }) else {
            throw HarbourError.installFailed("Choose valid websites and apps, and a duration between 1 minute and 24 hours")
        }
        isStarting = true
        defer { isStarting = false }
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
        if demo != nil {
            // Demo: pretend the helper installed; nothing leaves this process.
            try? await Task.sleep(nanoseconds: 600_000_000)
            demoAdditions = BlockAdditions()
            demoState = state
            refreshState()
            return
        }
        // Reset any stale additions from a prior block.
        try? FileManager.default.removeItem(at: additionsURL)
        try await Task.detached(priority: .userInitiated) {
            try HelperInstaller.installAndStart(state: state)
        }.value
        refreshState()
    }

    // MARK: - Runtime additions (can only grow the blocklist, never shrink)

    private func loadAdditions() -> BlockAdditions {
        if demo != nil { return demoAdditions }
        guard let data = try? Data(contentsOf: additionsURL) else { return BlockAdditions() }
        return (try? JSONDecoder().decode(BlockAdditions.self, from: data)) ?? BlockAdditions()
    }

    private func writeAdditions(_ a: BlockAdditions) {
        if demo != nil {
            demoAdditions = a
            self.currentAdditions = a
            return
        }
        guard let data = try? JSONEncoder().encode(a) else { return }
        try? data.write(to: additionsURL, options: .atomic)
        self.currentAdditions = a
    }

    /// Append a domain to the active blocklist. No-op if already covered.
    func addDomainLive(_ input: String) {
        guard currentState != nil else { return }
        guard let d = DomainValidation.normalizedDomain(input) else { return }
        guard DomainValidation.isSafeDomain(d) else { return }

        let alreadyBlocked = (currentState?.domains.contains(d) ?? false)
            || currentAdditions.domains.contains(d)
        guard !alreadyBlocked else { return }

        var additions = currentAdditions
        additions.domains.append(d)
        writeAdditions(additions)
    }

    /// Append an app to the active blocklist. No-op if already covered.
    func addAppLive(_ app: BlockedApp) {
        guard let state = currentState, Safety.isBlockableAppPath(app.path) else { return }
        let already = state.blockedPaths.contains(app.path)
            || currentAdditions.apps.contains(where: { $0.path == app.path })
        guard !already else { return }

        var additions = currentAdditions
        additions.apps.append(app)
        writeAdditions(additions)
    }

    // MARK: - Demo fixtures

    private static func makeDemoState() -> BlockState {
        let now = Date()
        let social = DomainPreset.socialMedia.domains.prefix(7)
        let video = ["youtube.com", "youtu.be", "netflix.com", "twitch.tv", "primevideo.com"]
        let candidates = [
            "/Applications/Telegram.app",
            "/Applications/Slack.app",
            "/Applications/Discord.app",
            "/System/Applications/Music.app",
            "/System/Applications/News.app",
            "/System/Applications/TV.app",
        ]
        let apps = candidates
            .filter { FileManager.default.fileExists(atPath: $0) }
            .prefix(3)
        return BlockState(
            startTime: now.addingTimeInterval(-45 * 60),
            endTime: now.addingTimeInterval(1 * 3600 + 14 * 60 + 32),
            domains: Array(social) + video,
            blockedPaths: Array(apps),
            blockedBundleIDs: apps.map { Bundle(path: $0)?.bundleIdentifier ?? "" },
            additionsPath: nil
        )
    }
}
