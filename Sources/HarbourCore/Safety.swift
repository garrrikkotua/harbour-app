import Foundation

public enum Safety {
    /// App paths we refuse to add to the block list. These are mirrored in
    /// the daemon's `neverKillPrefixes` for defence-in-depth. Covers:
    ///  - System Settings / Preferences (only way to fix broken state without CLI)
    ///  - Terminal (only way to run sudo if everything else breaks)
    ///  - Recovery / diagnostic tools (Activity Monitor, Console, Disk Utility,
    ///    System Information, Migration Assistant)
    ///  - Harbour.app itself — blocking it would be pointlessly confusing.
    public static let criticalAppPaths: Set<String> = [
        "/System/Applications/System Preferences.app",
        "/System/Applications/System Settings.app",
        "/System/Applications/Utilities/Terminal.app",
        "/Applications/Utilities/Terminal.app",
        "/System/Applications/Utilities/Activity Monitor.app",
        "/System/Applications/Utilities/Console.app",
        "/System/Applications/Utilities/Disk Utility.app",
        "/System/Applications/Utilities/System Information.app",
        "/System/Applications/Utilities/Migration Assistant.app",
        "/System/Applications/Utilities/Keychain Access.app",
        "/Applications/Harbour.app",
        "/Applications/Harbour Control.app",
    ]

    /// Also block anything living inside these system directories from
    /// entering the picker at all.
    public static let criticalAppPrefixes: [String] = [
        "/System/Library/CoreServices/",
        "/System/Library/PrivateFrameworks/",
        "/System/Library/Frameworks/",
        "/System/Library/LaunchDaemons/",
        "/System/Library/LaunchAgents/",
        "/usr/libexec/",
    ]

    public static func isCriticalApp(path: String) -> Bool {
        for candidate in Set([path, logicalSystemPath(path)]) {
            if criticalAppPaths.contains(candidate) { return true }
            for p in criticalAppPrefixes where candidate.hasPrefix(p) { return true }
        }
        return false
    }

    /// Since macOS 13 parts of the OS (Safari, WebKit, ...) live in cryptexes.
    /// The kernel reports their executables as
    /// `/System/Volumes/Preboot/Cryptexes/<Name>/System/...`, so critical-path
    /// checks must also look at the path with that prefix removed.
    public static func logicalSystemPath(_ path: String) -> String {
        for root in ["/System/Volumes/Preboot/Cryptexes/", "/System/Cryptexes/"] where path.hasPrefix(root) {
            let rest = path.dropFirst(root.count)
            guard let slash = rest.firstIndex(of: "/") else { return path }
            return String(rest[slash...])
        }
        return path
    }

    /// Only absolute, normalized app bundle paths may reach the root enforcer.
    public static func isBlockableAppPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), path.hasSuffix(".app"),
              !path.contains("\n"), !path.contains("\r"),
              (path as NSString).standardizingPath == path,
              !isCriticalApp(path: path) else { return false }
        return !criticalAppPaths.contains { path.hasPrefix($0 + "/") }
    }

    public static func matchesApp(executable: String, bundlePath: String) -> Bool {
        isBlockableAppPath(bundlePath) && executable.hasPrefix(bundlePath + "/")
    }

    /// Bundle paths the enforcer should match running executables against.
    /// The kernel reports fully resolved executable paths, so a bundle chosen
    /// through a symlink (e.g. `/Applications/Safari.app`, which points into
    /// the Safari cryptex since macOS 13) never matched and was never closed.
    /// `resolvedPath` is `realpath(bundlePath)`; it is only used when it is
    /// itself a blockable bundle, so a symlink cannot smuggle in a critical app.
    public static func enforcementTargets(bundlePath: String, resolvedPath: String?) -> [String] {
        guard isBlockableAppPath(bundlePath) else { return [] }
        guard let resolved = resolvedPath, resolved != bundlePath else { return [bundlePath] }
        return isBlockableAppPath(resolved) ? [bundlePath, resolved] : [bundlePath]
    }

    /// The enforcer runs as root and matches by path only. Never let it kill
    /// root-owned processes: those are never the distracting app itself (they
    /// are SMAppService helpers, MDM or security agents), and the runtime
    /// additions file is writable by the non-root user who started the block.
    public static func mayTerminate(processOwnerUID uid: uid_t) -> Bool {
        uid != 0
    }

    /// Domains that commonly break system functionality when blocked.
    /// Not forbidden — we just warn the user.
    public static let riskyDomains: Set<String> = [
        "apple.com",
        "icloud.com",
        "me.com",
        "mzstatic.com",
        "push.apple.com",
    ]

    /// Returns which entries in the list are risky.
    public static func riskyEntries(from domains: [String]) -> [String] {
        domains.filter { d in
            let host = d.lowercased()
            return riskyDomains.contains(host) || riskyDomains.contains(where: { host.hasSuffix(".\($0)") })
        }
    }

    /// A company whose services share server addresses, so blocking one of
    /// its sites at the IP level can also disrupt its others.
    public struct SharedNetwork: Equatable, Sendable {
        public let owner: String
        public let sideEffects: String
        public let suffixes: [String]
    }

    public static let sharedNetworks: [SharedNetwork] = [
        SharedNetwork(
            owner: "Google",
            sideEffects: "Google Search, Gmail, Docs, Drive and Meet",
            suffixes: ["google.com", "gmail.com", "googleapis.com", "googleusercontent.com",
                       "youtube.com", "youtu.be", "youtube-nocookie.com", "ytimg.com",
                       "googlevideo.com", "ggpht.com"]
        ),
        SharedNetwork(
            owner: "Meta",
            sideEffects: "Facebook, Instagram, Threads, WhatsApp and Messenger",
            suffixes: ["facebook.com", "instagram.com", "threads.net", "fb.com", "fbcdn.net",
                       "whatsapp.com", "whatsapp.net", "messenger.com"]
        ),
    ]

    /// Shared networks touched by the list, in declaration order.
    public static func sharedNetworks(in domains: [String]) -> [SharedNetwork] {
        let hosts = domains.map { $0.lowercased() }
        return sharedNetworks.filter { network in
            hosts.contains { host in
                network.suffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
            }
        }
    }
}
