import SwiftUI

@main
struct HarbourApp: App {
    @StateObject private var manager = BlockManager()
    @AppStorage("harbour.didOnboard") private var didOnboard: Bool = false

    var body: some Scene {
        WindowGroup("Harbour") {
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
    }
}
