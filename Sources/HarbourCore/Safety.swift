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
        if criticalAppPaths.contains(path) { return true }
        for p in criticalAppPrefixes where path.hasPrefix(p) { return true }
        return false
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
}
