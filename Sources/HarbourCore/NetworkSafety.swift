import Foundation
import Darwin

/// Rules for which resolved addresses may receive a blanket pf block.
///
/// pf rules are written as `block ... to <ip>` with no interface or port, and
/// the stock macOS pf.conf has no `set skip on lo0`. A blocked domain that
/// resolves to loopback, the LAN (router / DNS server), link-local or
/// multicast space would therefore cut local networking, or all DNS, for the
/// rest of a session that cannot be cancelled. Sinkhole resolvers (Pi-hole,
/// NextDNS, AdGuard) routinely answer 0.0.0.0 or 127.0.0.1, and split-horizon
/// DNS hands out private addresses, so this is not hypothetical.
public enum NetworkSafety {

    /// True when `ip` is a public unicast address that is safe to drop
    /// completely. Name-level blocking in /etc/hosts still covers the rest.
    public static func isBlockableResolvedIP(_ ip: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, ip, &v4) == 1 {
            return isPublicIPv4(withUnsafeBytes(of: &v4) { Array($0) })
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, ip, &v6) == 1 {
            return isPublicIPv6(withUnsafeBytes(of: &v6) { Array($0) })
        }
        return false
    }

    /// Filters resolver output down to addresses that may be fully blocked.
    /// `keepReachable` holds addresses that are only blocked on specific ports
    /// (the DoH resolvers, whose port 53 must keep working). Shared hosting and
    /// CDN addresses are left alone because they also serve unrelated sites.
    public static func blockableIPs<S: Sequence>(
        from candidates: S,
        keepReachable: Set<String>
    ) -> Set<String> where S.Element == String {
        Set(candidates.filter {
            isBlockableResolvedIP($0) && !keepReachable.contains($0) && !SharedHosting.contains($0)
        })
    }

    private static func isPublicIPv4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        switch (b[0], b[1]) {
        case (0, _), (10, _), (127, _): return false          // this-net, RFC 1918, loopback
        case (169, 254): return false                          // link-local
        case (172, 16...31): return false                      // RFC 1918
        case (192, 168): return false                          // RFC 1918
        case (100, 64...127): return false                     // CGNAT / Tailscale
        case (224..., _): return false                         // multicast, reserved, broadcast
        default: return true
        }
    }

    private static func isPublicIPv6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        if b[0..<15].allSatisfy({ $0 == 0 }) { return false }  // :: and ::1
        if b[0] == 0xff { return false }                       // multicast
        if b[0] & 0xfe == 0xfc { return false }                // fc00::/7 unique-local
        if b[0] == 0xfe && b[1] & 0xc0 == 0x80 { return false } // fe80::/10 link-local
        // ::ffff:a.b.c.d — judge the embedded IPv4 address.
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xff && b[11] == 0xff {
            return isPublicIPv4(Array(b[12..<16]))
        }
        return true
    }
}
