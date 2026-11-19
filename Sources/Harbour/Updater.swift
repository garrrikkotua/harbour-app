import SwiftUI
import Sparkle

/// In-app updates through Sparkle. The feed is the `appcast.xml` attached to
/// the latest GitHub release (see `SUFeedURL` in Info.plist); every update is
/// verified against the EdDSA key in `SUPublicEDKey` and Apple's notarization.
///
/// Updating the app never touches a running block: enforcement lives in the
/// separately installed daemon, which keeps running while the app relaunches.
@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published var automaticallyInstalls: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyInstalls }
    }

    private let controller: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    init() {
        // Demo/QA launches never reach the network for updates.
        controller = SPUStandardUpdaterController(
            startingUpdater: DemoMode.current == nil && !DemoMode.forcesOnboarding,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyInstalls = controller.updater.automaticallyDownloadsUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// App menu items: Check for Updates… plus the automatic-update toggles.
struct UpdateCommands: Commands {
    @ObservedObject var updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
            Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecks)
            Toggle("Install Updates Automatically", isOn: $updater.automaticallyInstalls)
                .disabled(!updater.automaticallyChecks)
        }
    }
}
