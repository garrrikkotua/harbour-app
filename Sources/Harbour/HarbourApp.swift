import SwiftUI
import AppKit

@main
struct HarbourApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = BlockManager()
    @AppStorage("harbour.didOnboard") private var didOnboard: Bool = false
    /// HARBOUR_DEMO_ONBOARDING=1 shows onboarding without touching the stored
    /// flag; finishing it only dismisses it for this launch.
    @State private var demoOnboardingDone = false

    private var showsOnboarding: Bool {
        DemoMode.forcesOnboarding ? !demoOnboardingDone : !didOnboard
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Cross-fades from the night sky to the setup screen instead of cutting.
    private func finishOnboarding() {
        withAnimation(.easeInOut(duration: Self.reduceMotion ? 0.3 : 0.7)) {
            if DemoMode.forcesOnboarding {
                demoOnboardingDone = true
            } else {
                didOnboard = true
            }
        }
    }

    var body: some Scene {
        // Single main window — the menu bar popover reopens/focuses it by id.
        Window("Harbour Control", id: MainWindow.id) {
            ZStack {
                if DemoMode.showsPopover {
                    MenuBarExtraView(manager: manager)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(.regularMaterial)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if showsOnboarding {
                    OnboardingView(onFinish: finishOnboarding)
                        .transition(.opacity)
                } else {
                    ContentView(manager: manager)
                        // The parchment settles in as the night sky fades out.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: Self.reduceMotion ? 1 : 0.98)),
                            removal: .opacity
                        ))
                }
            }
            .frame(width: 520)
            .background(WindowChromeConfigurator())
        }
        // No title bar strip: the night intro, onboarding sky and active
        // session run edge to edge, with the traffic lights floating on top.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/garrrikkotua/harbour-app/releases/latest")!)
                }
            }
        }

        // Status item: a small lighthouse that lights up (with a countdown)
        // while a block is running.
        MenuBarExtra {
            MenuBarExtraView(manager: manager)
        } label: {
            MenuBarLabel(manager: manager)
        }
        .menuBarExtraStyle(.window)
    }
}

enum MainWindow {
    static let id = "main"
}

/// The window can't be resized (`.contentSize`), so the zoom button would only
/// ever show disabled — a stray dark dot on the night screens. Hide it.
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
}

/// Keeps the app alive in the menu bar after the main window is closed —
/// quitting is an explicit choice from the popover or ⌘Q.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
