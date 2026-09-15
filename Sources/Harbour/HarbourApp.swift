import SwiftUI

@main
struct HarbourApp: App {
    @StateObject private var manager = BlockManager()
    @AppStorage("harbour.didOnboard") private var didOnboard: Bool = false

    var body: some Scene {
        WindowGroup("Harbour Control") {
            Group {
                if didOnboard {
                    ContentView(manager: manager)
                } else {
                    OnboardingView(onFinish: { didOnboard = true })
                }
            }
            .frame(width: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/garrrikkotua/harbour-app/releases/latest")!)
                }
            }
        }
    }
}
