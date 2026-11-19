import Foundation

/// Extracts the hostname a browser asked for from the first bytes of a
/// connection to the block sink: the SNI of a TLS ClientHello, or the Host
/// header of plain HTTP. The input is untrusted, so every read is bounds-checked
/// and nothing beyond the hostname is interpreted.
public enum RequestHostParser {
    /// Never buffer more than this from one connection.
    public static let maxBytes = 16 * 1024 + 5

    public enum Progress: Equatable {
        case needMore
        case host(String)
        case unrecognized
    }

    public static func parse(_ data: [UInt8]) -> Progress {
        guard let first = data.first else { return .needMore }
        if first == 0x16 { return parseTLS(data) }
        if first >= 0x41 && first <= 0x5A { return parseHTTP(data) }  // "GET", "POST", ...
        return .unrecognized
    }

    // MARK: TLS

    private static func parseTLS(_ data: [UInt8]) -> Progress {
        guard data.count >= 5 else { return .needMore }
        let recordLength = Int(data[3]) << 8 | Int(data[4])
        guard recordLength > 0, recordLength <= 16 * 1024 else { return .unrecognized }
        guard data.count >= 5 + recordLength else { return .needMore }

        var r = Reader(bytes: data, start: 5, end: 5 + recordLength)
        guard r.u8() == 0x01 else { return .unrecognized }               // ClientHello
        guard let hsLength = r.u24() else { return .unrecognized }
        // A ClientHello spanning several records is rare; skip counting it.
        guard hsLength <= r.remaining else { return .unrecognized }
        r.end = r.position + hsLength

        guard r.skip(2 + 32),                                           // version + random
              let sessionLen = r.u8(), r.skip(sessionLen),
              let suitesLen = r.u16(), r.skip(suitesLen),
              let compLen = r.u8(), r.skip(compLen)
        else { return .unrecognized }
        guard r.remaining > 0 else { return .unrecognized }             // no extensions
        guard let extTotal = r.u16(), extTotal <= r.remaining else { return .unrecognized }
        r.end = r.position + extTotal

        while r.remaining >= 4 {
            guard let type = r.u16(), let length = r.u16(), length <= r.remaining else {
                return .unrecognized
            }
            if type != 0x0000 {
                _ = r.skip(length)
                continue
            }
            var s = Reader(bytes: data, start: r.position, end: r.position + length)
            guard let listLen = s.u16(), listLen <= s.remaining else { return .unrecognized }
            s.end = s.position + listLen
            while s.remaining >= 3 {
                guard let nameType = s.u8(), let nameLen = s.u16(), nameLen <= s.remaining else {
                    return .unrecognized
                }
                if nameType == 0, let name = s.ascii(nameLen) {
                    return validHost(name).map(Progress.host) ?? .unrecognized
                }
                _ = s.skip(nameLen)
            }
            return .unrecognized
        }
        return .unrecognized
    }

    // MARK: HTTP

    private static let httpLimit = 8 * 1024

    private static func parseHTTP(_ data: [UInt8]) -> Progress {
        let window = data.prefix(httpLimit)
        guard let text = String(bytes: window, encoding: .isoLatin1) else { return .unrecognized }
        guard let headerEnd = text.range(of: "\r\n\r\n") ?? text.range(of: "\n\n") else {
            return data.count >= httpLimit ? .unrecognized : .needMore
        }
        let lines = text[..<headerEnd.lowerBound].split(omittingEmptySubsequences: true) {
            $0 == "\r\n" || $0 == "\n" || $0 == "\r"
        }
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            guard line[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "host" else { continue }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let portColon = value.lastIndex(of: ":"), !value.hasPrefix("[") {
                value = String(value[..<portColon])
            }
            return validHost(value).map(Progress.host) ?? .unrecognized
        }
        return .unrecognized
    }

    // MARK: Helpers

    private static func validHost(_ raw: String) -> String? {
        var host = raw.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, host.count <= 253 else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard host.allSatisfy({ allowed.contains($0) }) else { return nil }
        return host
    }

    private struct Reader {
        let bytes: [UInt8]
        var position: Int
        var end: Int

        init(bytes: [UInt8], start: Int, end: Int) {
            self.bytes = bytes
            self.position = start
            self.end = min(end, bytes.count)
        }

        var remaining: Int { max(0, end - position) }

        mutating func u8() -> Int? {
            guard remaining >= 1 else { return nil }
            defer { position += 1 }
            return Int(bytes[position])
        }

        mutating func u16() -> Int? {
            guard remaining >= 2 else { return nil }
            defer { position += 2 }
            return Int(bytes[position]) << 8 | Int(bytes[position + 1])
        }

        mutating func u24() -> Int? {
            guard remaining >= 3 else { return nil }
            defer { position += 3 }
            return Int(bytes[position]) << 16 | Int(bytes[position + 1]) << 8 | Int(bytes[position + 2])
        }

        mutating func skip(_ n: Int) -> Bool {
            guard n >= 0, remaining >= n else { return false }
            position += n
            return true
        }

        mutating func ascii(_ n: Int) -> String? {
            guard n >= 0, remaining >= n else { return nil }
            defer { position += n }
            return String(bytes: bytes[position..<(position + n)], encoding: .ascii)
        }
    }
}
