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
    /// Mirrors of Sparkle's own preferences. They're observed, not copied:
    /// Sparkle's update alert has its own "Automatically download and install"
    /// checkbox, and the menu must reflect a change made there.
    @Published var automaticallyChecks: Bool {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }
    @Published var automaticallyInstalls: Bool {
        didSet {
            if controller.updater.automaticallyDownloadsUpdates != automaticallyInstalls {
                controller.updater.automaticallyDownloadsUpdates = automaticallyInstalls
            }
        }
    }

    private let controller: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []

    init() {
        // Demo/QA launches never reach the network for updates.
        controller = SPUStandardUpdaterController(
            startingUpdater: DemoMode.current == nil && !DemoMode.forcesOnboarding,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let updater = controller.updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyInstalls = updater.automaticallyDownloadsUpdates
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] u, _ in
                let value = u.canCheckForUpdates
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] u, _ in
                let value = u.automaticallyChecksForUpdates
                Task { @MainActor in
                    if self?.automaticallyChecks != value { self?.automaticallyChecks = value }
                }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] u, _ in
                let value = u.automaticallyDownloadsUpdates
                Task { @MainActor in
                    if self?.automaticallyInstalls != value { self?.automaticallyInstalls = value }
                }
            },
        ]
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
