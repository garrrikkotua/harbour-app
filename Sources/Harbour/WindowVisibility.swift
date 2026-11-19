import SwiftUI
import AppKit

/// Whether the window hosting a view is on screen. Animated scenes (stars,
/// waves, the lighthouse beam) pause their `TimelineView`s when it's false:
/// the app keeps running in the menu bar with its windows closed or covered,
/// and SwiftUI keeps redrawing those blurred, software-rendered layers at
/// 30 fps even when nobody can see them.
private struct WindowVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var windowVisible: Bool {
        get { self[WindowVisibleKey.self] }
        set { self[WindowVisibleKey.self] = newValue }
    }
}

extension View {
    /// Publishes the hosting window's visibility to `\.windowVisible` for this
    /// view's subtree. Apply once at the root of each window or panel.
    func tracksWindowVisibility() -> some View {
        modifier(WindowVisibilityModifier())
    }
}

private struct WindowVisibilityModifier: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .environment(\.windowVisible, visible)
            .background(WindowVisibilityReader(visible: $visible))
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = { value in
            // Hop off the AppKit callback so SwiftUI state isn't mutated mid-update.
            DispatchQueue.main.async {
                if visible != value { visible = value }
            }
        }
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else {
                onChange?(false)
                return
            }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.willCloseNotification,
            ]
            for name in names {
                tokens.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] note in
                    self?.report(closing: note.name == NSWindow.willCloseNotification)
                })
            }
            report(closing: false)
        }

        private func report(closing: Bool) {
            guard let window, !closing else {
                onChange?(false)
                return
            }
            onChange?(window.occlusionState.contains(.visible) && !window.isMiniaturized)
        }

        deinit {
            tokens.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
