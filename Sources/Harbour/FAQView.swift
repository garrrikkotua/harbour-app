import SwiftUI

struct FAQItem: Identifiable {
    let q: String
    let a: String
    var id: String { q }
}

struct FAQView: View {
    let onClose: () -> Void

    @State private var expanded: Set<String> = []

    private static let items: [FAQItem] = [
        FAQItem(
            q: "Can I cancel a block early?",
            a: """
            No. That's the whole point. Once you start a block, the only way out is to wait.

            Even if you quit the Harbour app, restart your Mac, or kill the background process, the block keeps running. Harbour installs a system-level daemon (`com.harbour.daemon`) that launchd automatically restarts.

            If you really know what you're doing, you can remove it manually with `sudo` — but that requires your admin password every time and is meant to be inconvenient.
            """
        ),
        FAQItem(
            q: "How does website blocking work?",
            a: """
            Harbour uses two layers:

            1. **/etc/hosts** — maps blocked domains to 127.0.0.1 so your DNS resolver drops them.
            2. **pfctl (Packet Filter)** — macOS's built-in firewall. Harbour resolves each blocked domain's IP addresses and adds `block drop` rules so packets can't leave your machine, even over a VPN.

            IPs are re-resolved every 5 minutes to keep up with services that rotate them.
            """
        ),
        FAQItem(
            q: "How does app blocking work?",
            a: """
            The Harbour daemon polls the running process list once per second. If any process's executable path lives inside a blocked `.app` bundle, the daemon sends it `SIGKILL`.

            So the app gets about one second of life, then dies. Launching it again just kills it again.
            """
        ),
        FAQItem(
            q: "Does it work with VPN?",
            a: """
            Yes. `/etc/hosts` alone can be bypassed by VPNs that use their own DNS, but the `pfctl` packet filter runs on your host's network stack and drops packets regardless of where your DNS resolution happens.

            If a site still loads, it's likely because the domain resolves to a new IP that Harbour hasn't seen yet. Harbour re-resolves every 5 minutes to catch this.
            """
        ),
        FAQItem(
            q: "What if I restart my Mac?",
            a: """
            The block keeps going. The daemon is registered with `launchd` as a LaunchDaemon, so it starts automatically at boot and resumes enforcement.

            If the timer expired while you were shut down, the daemon will immediately clean itself up on next boot.
            """
        ),
        FAQItem(
            q: "Is my admin password stored?",
            a: """
            No. Harbour asks for your password only once — to install the daemon — via macOS's built-in `osascript` admin prompt. The password goes straight to macOS's authorization service and is never seen by Harbour itself.

            After the daemon is running, it's already root and doesn't need your password again.
            """
        ),
        FAQItem(
            q: "Where is my data stored?",
            a: """
            - Block settings (domains, apps, default duration): `~/Library/Application Support/Harbour/config.json`
            - Active block state (start time, end time): `/var/db/harbour/state.json` (root-owned; removed when timer expires)
            - Daemon binary: `/usr/local/bin/harbour-daemon`
            - launchd plist: `/Library/LaunchDaemons/com.harbour.daemon.plist`
            - Daemon log: `/var/log/harbour-daemon.log`

            No data ever leaves your machine. Harbour doesn't phone home.
            """
        ),
        FAQItem(
            q: "A site isn't blocked. Why?",
            a: """
            Most likely one of:

            1. **Subdomain not listed.** Harbour blocks `example.com` and `www.example.com` automatically, but not `mail.example.com`. Add the specific subdomain.
            2. **IP rotation.** Big sites (Cloudflare, AWS) cycle IPs. Harbour re-resolves every 5 minutes, so wait a bit or re-add the domain.
            3. **DNS cache.** Open Terminal and run `sudo dscacheutil -flushcache` — the daemon does this, but browsers cache too. Try a different tab.
            """
        ),
        FAQItem(
            q: "How do I uninstall Harbour?",
            a: """
            When no block is active, simply drag `Harbour.app` to the Trash. The daemon only exists during a block and uninstalls itself automatically when the timer expires.

            If you want to nuke a stuck install (only possible with `sudo`):

            ```
            sudo launchctl bootout system/com.harbour.daemon
            sudo rm /Library/LaunchDaemons/com.harbour.daemon.plist
            sudo rm /usr/local/bin/harbour-daemon
            sudo rm -rf /var/db/harbour
            ```
            """
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How Harbour works")
                    .font(.title2.bold())
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.separator), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.items) { item in
                        FAQRow(
                            item: item,
                            isOpen: expanded.contains(item.id),
                            toggle: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if expanded.contains(item.id) {
                                        expanded.remove(item.id)
                                    } else {
                                        expanded.insert(item.id)
                                    }
                                }
                            }
                        )
                        Divider()
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 520, height: 560)
    }
}

struct FAQRow: View {
    let item: FAQItem
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(alignment: .top) {
                    Text(item.q)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(item.a)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
