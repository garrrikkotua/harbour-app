import SwiftUI

struct FAQItem: Identifiable {
    let symbol: String
    let q: String
    /// Inline Markdown (`code`, **bold**, links). Blank lines separate paragraphs.
    let a: String
    var id: String { q }
}

struct FAQGroup: Identifiable {
    let title: String
    let items: [FAQItem]
    var id: String { title }
}

struct FAQView: View {
    let onClose: () -> Void

    @State private var expanded: Set<String> = [FAQView.groups[0].items[0].id]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let recoveryGuide = URL(string: "https://github.com/garrrikkotua/harbour-app/blob/main/docs/RELEASING.md#recovery")!

    static let groups: [FAQGroup] = [
        FAQGroup(title: "The rules", items: [
            FAQItem(
                symbol: "lock.fill",
                q: "Can I cancel a block early?",
                a: """
                No. There is no cancel button anywhere in Harbour Control, by design. A block ends when its timer ends.

                Pick a duration you can live with. You can always start another block afterwards.

                If something breaks, an administrator can stop it from Terminal (see **Emergencies** below). That's a repair path, not an off switch.
                """
            ),
            FAQItem(
                symbol: "power",
                q: "What if I quit the app, restart or uninstall?",
                a: """
                The block keeps running. Enforcement lives in a small system daemon (`com.harbour.daemon`) that launchd starts at boot, so quitting Harbour Control, restarting your Mac or dragging the app to the Trash doesn't stop it.

                If the timer ran out while your Mac was off, the daemon cleans up as soon as it boots.
                """
            ),
            FAQItem(
                symbol: "plus.circle",
                q: "Can I change the blocklist during a session?",
                a: """
                Only by adding. Open **Manage blocklist** in the session window to add websites or apps; they are enforced within seconds. Nothing can be removed until the block ends.
                """
            ),
            FAQItem(
                symbol: "clock",
                q: "Where do I see how much time is left?",
                a: """
                The lighthouse in your menu bar shows the time left; click it for the full status. The main window shows the same countdown with the end time.
                """
            ),
        ]),
        FAQGroup(title: "What gets blocked", items: [
            FAQItem(
                symbol: "globe",
                q: "How does website blocking work?",
                a: """
                Two layers:

                **/etc/hosts** points each blocked domain and its `www.` version at 0.0.0.0, so it can't be looked up.

                **The macOS firewall (pf)** drops traffic to the addresses those domains resolve to. Addresses are refreshed every 5 minutes to keep up with sites that rotate them. Well-known secure DNS (DNS-over-HTTPS) endpoints are blocked too, so browsers can't quietly route around the list.
                """
            ),
            FAQItem(
                symbol: "point.3.connected.trianglepath.dotted",
                q: "Are subdomains blocked?",
                a: """
                `example.com` also covers `www.example.com`, but not other subdomains like `mail.example.com` or `m.example.com`. Add those as separate entries. The presets already include the usual extra hosts (YouTube's video servers, for example).
                """
            ),
            FAQItem(
                symbol: "square.grid.2x2",
                q: "How does app blocking work?",
                a: """
                The daemon checks running processes once a second. Anything launched from a blocked `.app` is closed immediately, and relaunching it just closes it again. Apps macOS needs to work, like Finder, can't be picked.
                """
            ),
            FAQItem(
                symbol: "questionmark.circle",
                q: "A site still loads. Why?",
                a: """
                Usually one of these:

                **A subdomain isn't listed.** Add the exact host you see in the address bar.

                **The site moved to new addresses.** Harbour Control catches up within 5 minutes.

                **Your browser cached it.** Close the tab or restart the browser.
                """
            ),
        ]),
        FAQGroup(title: "Limits", items: [
            FAQItem(
                symbol: "network",
                q: "Does it work with a VPN or proxy?",
                a: """
                It depends on the VPN. Proxies, some VPNs, Tor and custom encrypted DNS can route around both layers.

                Harbour Control is a focus tool, not a security boundary. It makes giving in inconvenient; it can't stop an administrator who is determined to get around it.
                """
            ),
        ]),
        FAQGroup(title: "Privacy", items: [
            FAQItem(
                symbol: "key",
                q: "Is my admin password stored?",
                a: """
                No. Starting a block uses the standard macOS administrator prompt. Your password goes to macOS, never to Harbour Control, and the daemon doesn't need it again for that session.
                """
            ),
            FAQItem(
                symbol: "internaldrive",
                q: "Where is my data stored?",
                a: """
                Settings: `~/Library/Application Support/Harbour/config.json`

                Active block: `/var/db/harbour/state.json` (removed when the timer ends)

                Daemon: `/Library/PrivilegedHelperTools/com.harbour.daemon` and `/Library/LaunchDaemons/com.harbour.daemon.plist`

                Log: `/var/log/harbour-daemon.log`

                There are no analytics. Website icons come from Google's favicon service, which sees the hostname.
                """
            ),
        ]),
        FAQGroup(title: "Emergencies", items: [
            FAQItem(
                symbol: "cross.case",
                q: "Something is broken. What now?",
                a: """
                The app itself never offers a way out. If a block malfunctions (for example it breaks a network you need), an administrator can unload the daemon in Terminal:

                `sudo launchctl bootout system/com.harbour.daemon`

                That lifts the rules until the next restart. Ending the block for good also needs its state removed, as the recovery guide explains. This is for malfunctions, not for ending a session early.
                """
            ),
            FAQItem(
                symbol: "trash",
                q: "How do I uninstall Harbour Control?",
                a: """
                Wait until your block ends, then drag Harbour Control to the Trash. The background job and network rules are removed when the timer ends; an inactive helper file and your settings may remain.
                """
            ),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Self.groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title.uppercased())
                                .font(Theme.sans(size: 10, weight: .semibold))
                                .tracking(1.1)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 4)

                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        Rectangle().fill(Theme.creamBorderSoft).frame(height: 1)
                                            .padding(.leading, 46)
                                    }
                                    FAQRow(item: item, isOpen: expanded.contains(item.id), toggle: { toggle(item.id) })
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .background(CardBackground(radius: 12))
                        }
                    }

                    Link(destination: Self.recoveryGuide) {
                        HStack(spacing: 6) {
                            Image(systemName: "book")
                            Text("Open the recovery guide")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(Theme.sans(size: 12, weight: .medium))
                        .foregroundStyle(Theme.navy)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.automatic)
        }
        // ~32 pt narrower than the window so the sheet reads as a sheet.
        .frame(width: 488, height: 580)
        .background(Theme.setupBackground)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.activeBackground)
                LighthouseIcon(size: 36, pulsing: false, animated: false)
                    .offset(y: 3)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("How Harbour Control works")
                    .font(Theme.serif(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("No early cancel. Add-only while a block runs.")
                    .font(Theme.sans(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            CircleIconButton(symbol: "xmark", tint: Theme.textSecondary, hoverFill: Theme.navySoft,
                             help: "Close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.parchmentWarm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.creamBorderSoft).frame(height: 1)
        }
    }

    private func toggle(_ id: String) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.9)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }
}

struct FAQRow: View {
    let item: FAQItem
    let isOpen: Bool
    let toggle: () -> Void

    @State private var hovering = false

    /// Paragraphs rendered as inline Markdown so `code` and **bold** show properly.
    private var paragraphs: [AttributedString] {
        item.a.components(separatedBy: "\n\n").map { para in
            (try? AttributedString(
                markdown: para,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(para)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isOpen ? Theme.parchmentWarm : Theme.amber)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(isOpen ? AnyShapeStyle(Theme.primaryButton) : AnyShapeStyle(Theme.amberSoft)))
                    Text(item.q)
                        .font(Theme.sans(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(hovering && !isOpen ? Theme.navySoft.opacity(0.45) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(isOpen ? .isSelected : [])

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                        Text(para)
                            .font(Theme.sans(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 48)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}
