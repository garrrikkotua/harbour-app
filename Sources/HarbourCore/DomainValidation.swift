import Foundation

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
        return true
    }

    /// Returns true if `s` looks like an IPv4 or IPv6 address (rough check
    /// used to filter dig output before writing pfctl rules).
    public static func isValidIP(_ s: String) -> Bool {
        if s.isEmpty || s.contains(" ") || s.hasSuffix(".") { return false }
        // IPv4: four dot-separated numeric octets 0-255
        let dotParts = s.split(separator: ".")
        if dotParts.count == 4,
           dotParts.allSatisfy({ Int($0).map { $0 >= 0 && $0 <= 255 } ?? false }) {
            return true
        }
        // IPv6: rough check — at least one colon, no spaces
        if s.contains(":") { return true }
        return false
    }
}
