import Foundation

/// Marker-delimited block editing for config files like `/etc/hosts` and
/// `/etc/pf.conf`. Pure functions — no filesystem access here, so they're
/// trivially unit-testable.
public enum HostsMarker {

    /// Remove every pair of START/END markers from `content`. If a START
    /// appears without a matching END, refuses to edit and returns the
    /// original content unchanged — prevents a corrupt markers state from
    /// truncating the file to EOF.
    public static func removeBlockSection(
        from content: String,
        start: String,
        end: String
    ) -> String {
        let lines = content.components(separatedBy: "\n")

        var skipRanges: [ClosedRange<Int>] = []
        var pendingStart: Int?
        for (i, line) in lines.enumerated() {
            if line.contains(start) {
                // Nested/duplicate start — treat new start as authoritative.
                pendingStart = i
            } else if line.contains(end), let s = pendingStart {
                skipRanges.append(s...i)
                pendingStart = nil
            }
        }
        if pendingStart != nil {
            // START without matching END — refuse to edit.
            return content
        }

        var result: [String] = []
        for (i, line) in lines.enumerated() {
            if skipRanges.contains(where: { $0.contains(i) }) { continue }
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n") + "\n"
    }

    /// Build an /etc/hosts block section for a list of domains, using the
    /// 0.0.0.0 / :: null-route sinks (more browser-friendly than 127.0.0.1).
    /// Each domain is emitted as both its bare form and `www.` variant.
    public static func buildHostsBlock(
        domains: [String],
        start: String,
        end: String
    ) -> String {
        var out = "\n\(start)\n"
        for d in domains where DomainValidation.isSafeDomain(d) {
            let stripped = d.hasPrefix("www.") ? String(d.dropFirst(4)) : d
            out += "0.0.0.0\t\(stripped)\n"
            out += "0.0.0.0\twww.\(stripped)\n"
            out += "::\t\(stripped)\n"
            out += "::\twww.\(stripped)\n"
        }
        out += "\(end)\n"
        return out
    }
}
