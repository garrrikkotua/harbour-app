import Foundation
import Darwin

public enum DomainValidation {
    /// Host file marker strings. Kept here so domain validation can refuse to
    /// accept user input that would forge a block-section boundary.
    public static let hostsMarkerStart = "# HARBOUR_BLOCK_START"
    public static let hostsMarkerEnd   = "# HARBOUR_BLOCK_END"

    /// Returns true if `s` is a plausible DNS name — no whitespace, no shell
    /// metacharacters, no marker substrings, length bounded. Used on every
    /// domain before it reaches `/etc/hosts` or pfctl rules.
    public static func isSafeDomain(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 253 else { return false }
        if s.contains(hostsMarkerStart) || s.contains(hostsMarkerEnd) { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        for ch in s.lowercased() where !allowed.contains(ch) { return false }
        return s.split(separator: ".", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0.count <= 63 && $0.first != "-" && $0.last != "-"
        }
    }

    /// Accept a hostname or web URL, and consistently store only its hostname.
    public static func normalizedDomain(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        let url = text.contains("://") ? text : "https://" + text
        guard let parts = URLComponents(string: url),
              ["http", "https"].contains(parts.scheme ?? ""),
              parts.user == nil, parts.password == nil,
              let host = parts.host, isSafeDomain(host) else { return nil }
        return host
    }

    /// Parse addresses before inserting DNS output into firewall rules.
    public static func isValidIP(_ s: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return s.withCString {
            inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1
        }
    }
}
