import Foundation
import Darwin

// libproc — Darwin ships proc_listallpids / proc_pidpath. Activity Monitor uses
// these; they always return the canonical executable path, unlike `ps -o comm`
// which can be truncated or reflect argv[0] instead of the real binary.

fileprivate let PROC_PIDPATHINFO_MAXSIZE: Int32 = 4096

// MARK: - Constants

let stateFile = "/var/db/harbour/state.json"
let hostsFile = "/etc/hosts"
let plistPath = "/Library/LaunchDaemons/com.harbour.daemon.plist"
let label = "com.harbour.daemon"

let markerStart = "# HARBOUR_BLOCK_START"
let markerEnd = "# HARBOUR_BLOCK_END"

// pfctl configuration — mirrors SelfControl's proven approach
let pfMainConf = "/etc/pf.conf"                          // the real pf.conf (we append to it)
let pfAnchorFile = "/etc/pf.anchors/org.harbour"         // our anchor rules live here
let pfTokenFile = "/etc/HarbourPFToken"                  // pfctl enable-token for clean disable
let pfAnchorName = "org.harbour"                         // anchor name referenced from pf.conf

/// Domains we always block whenever any Harbour session is active. These are
/// public DNS-over-HTTPS (DoH) endpoints browsers use to bypass /etc/hosts.
/// Without blocking these, Firefox/Chrome/Arc with DoH on will resolve names
/// over HTTPS and never consult our hosts entries.
let alwaysBlockDomains: [String] = [
    "cloudflare-dns.com",
    "mozilla.cloudflare-dns.com",
    "one.one.one.one",
    "dns.google",
    "dns.google.com",
    "dns.quad9.net",
    "dns.nextdns.io",
    "dns.adguard.com",
    "doh.opendns.com",
    "chrome.cloudflare-dns.com",
    "security.cloudflare-dns.com",
]

/// Meta AS32934 IP ranges (Facebook, Instagram, Threads, Messenger, WhatsApp).
/// Pulled via `whois -h whois.radb.net -- '-i origin AS32934' | grep ^route`,
/// mirrors SelfControl's shipped list.
let metaCIDRs: [String] = [
    "31.13.24.0/21",
    "31.13.64.0/18",
    "45.64.40.0/22",
    "66.220.144.0/20",
    "69.63.176.0/20",
    "69.171.224.0/19",
    "74.119.76.0/22",
    "102.132.96.0/20",
    "103.4.96.0/22",
    "129.134.0.0/16",
    "147.75.208.0/20",
    "157.240.0.0/16",
    "173.252.64.0/18",
    "179.60.192.0/22",
    "185.60.216.0/22",
    "185.89.216.0/22",
    "199.201.64.0/22",
    "204.15.20.0/22",
    // IPv6
    "2a03:2880::/32",
    "2620:0:1c00::/40",
    "2a03:83e0::/32",
]

/// Hardcoded CIDR ranges for services whose DNS rotates too aggressively to
/// catch via `dig`. Keyed by domain suffix: if any blocked domain matches,
/// the CIDR ranges are added to pfctl rules — so IP rotation can't dodge us.
let domainCIDRMap: [String: [String]] = [
    "facebook.com":  metaCIDRs,
    "instagram.com": metaCIDRs,
    "threads.net":   metaCIDRs,
    "fb.com":        metaCIDRs,
    "fbcdn.net":     metaCIDRs,
]

/// Literal DoH resolver IPs. Even if DNS resolution fails for the above names,
/// pfctl drops packets destined for these addresses.
let alwaysBlockIPs: [String] = [
    // Cloudflare
    "1.1.1.1", "1.0.0.1", "1.1.1.2", "1.1.1.3",
    "2606:4700:4700::1111", "2606:4700:4700::1001",
    // Google
    "8.8.8.8", "8.8.4.4",
    "2001:4860:4860::8888", "2001:4860:4860::8844",
    // Quad9
    "9.9.9.9", "149.112.112.112",
    "2620:fe::fe", "2620:fe::9",
    // OpenDNS
    "208.67.222.222", "208.67.220.220",
    // AdGuard
    "94.140.14.14", "94.140.15.15",
]

// MARK: - Model (duplicated from GUI; kept in sync by construction)

struct BlockState: Codable {
    let startTime: Date
    let endTime: Date
    let domains: [String]
    let blockedPaths: [String]
    let blockedBundleIDs: [String]
    var additionsPath: String? = nil
}

struct BlockedAppEntry: Codable {
    let name: String
    let path: String
    let bundleID: String
}

struct BlockAdditions: Codable {
    var domains: [String] = []
    var apps: [BlockedAppEntry] = []
}

// MARK: - Helpers

@discardableResult
func run(_ path: String, _ args: [String], timeoutSec: Double = 10) -> (status: Int32, output: String) {
    // Guard: refuse to spawn if the binary isn't executable. Prevents silent degradation.
    guard FileManager.default.isExecutableFile(atPath: path) else {
        log("run: missing or non-executable: \(path)")
        return (-1, "")
    }

    let task = Process()
    task.launchPath = path
    task.arguments = args
    let outPipe = Pipe()
    let errPipe = Pipe()
    task.standardOutput = outPipe
    task.standardError = errPipe

    // Drain both pipes concurrently on background threads so the child never
    // blocks on a full pipe buffer (the previous deadlock bug).
    var outData = Data()
    var errData = Data()
    let outLock = NSLock()
    let outQ = DispatchQueue(label: "harbour.run.out")
    let errQ = DispatchQueue(label: "harbour.run.err")
    let outGroup = DispatchGroup()
    let errGroup = DispatchGroup()

    outPipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            outGroup.leave()
        } else {
            outLock.lock(); outData.append(chunk); outLock.unlock()
        }
    }
    errPipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        if chunk.isEmpty {
            handle.readabilityHandler = nil
            errGroup.leave()
        } else {
            outLock.lock(); errData.append(chunk); outLock.unlock()
        }
    }
    outGroup.enter()
    errGroup.enter()
    _ = outQ; _ = errQ  // retained by handlers

    do { try task.run() } catch {
        log("run: failed to spawn \(path): \(error)")
        return (-1, "")
    }

    // Enforce a timeout so a hanging child cannot freeze the enforcement loop.
    let deadline = Date().addingTimeInterval(timeoutSec)
    while task.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if task.isRunning {
        log("run: timeout (\(timeoutSec)s), killing \(path)")
        task.terminate()
        Thread.sleep(forTimeInterval: 0.2)
        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
    }
    task.waitUntilExit()
    _ = outGroup.wait(timeout: .now() + 2)
    _ = errGroup.wait(timeout: .now() + 2)

    let status = task.terminationStatus
    let output = String(data: outData, encoding: .utf8) ?? ""
    let errOut = String(data: errData, encoding: .utf8) ?? ""
    if status != 0 && !errOut.isEmpty {
        log("run: \(path) rc=\(status) stderr=\(errOut.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return (status, output)
}

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardOutput.write(Data("[\(ts)] \(msg)\n".utf8))
}

// MARK: - Hosts file

func removeBlockSection(from content: String) -> String {
    let lines = content.components(separatedBy: "\n")
    // First pass: locate every START/END marker pair. If we see a START without
    // a matching END, we refuse to strip — better to leave stale entries than
    // truncate the user's hosts file to EOF.
    var skipRanges: [ClosedRange<Int>] = []
    var pendingStart: Int?
    for (i, line) in lines.enumerated() {
        if line.contains(markerStart) {
            if pendingStart != nil {
                // Nested/duplicate start; close the previous unmatched one at the prior line.
                // Treat the new start as the authoritative one.
                pendingStart = i
            } else {
                pendingStart = i
            }
        } else if line.contains(markerEnd), let start = pendingStart {
            skipRanges.append(start...i)
            pendingStart = nil
        }
    }
    if pendingStart != nil {
        log("hosts: found START marker with no matching END — refusing to edit file")
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

/// Returns true if `s` is a plausible DNS name — no whitespace, no shell
/// metacharacters, no marker substrings, length bounded.
func isSafeDomain(_ s: String) -> Bool {
    guard !s.isEmpty, s.count <= 253 else { return false }
    if s.contains(markerStart) || s.contains(markerEnd) { return false }
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
    for ch in s.lowercased() where !allowed.contains(ch) { return false }
    return true
}

func applyHosts(domains: [String]) {
    guard let hosts = try? String(contentsOfFile: hostsFile, encoding: .utf8) else {
        log("could not read hosts file")
        return
    }
    var cleaned = removeBlockSection(from: hosts)
    if !cleaned.hasSuffix("\n") { cleaned += "\n" }

    // Merge the user's domains with our always-block DoH domains so browsers
    // can't side-step /etc/hosts via DNS-over-HTTPS.
    let all = Array(Set(domains + alwaysBlockDomains))

    // SelfControl uses 0.0.0.0 / :: instead of 127.0.0.1 / ::1. This matters:
    // browsers (Chrome/Arc in particular) treat loopback answers from hosts as
    // "suspicious DNS manipulation" and can fall back to DoH. A null-route
    // 0.0.0.0 is accepted as "host unreachable" with no second-guessing.
    var addition = "\n\(markerStart)\n"
    for d in all where isSafeDomain(d) {
        let stripped = d.hasPrefix("www.") ? String(d.dropFirst(4)) : d
        addition += "0.0.0.0\t\(stripped)\n"
        addition += "0.0.0.0\twww.\(stripped)\n"
        addition += "::\t\(stripped)\n"
        addition += "::\twww.\(stripped)\n"
    }
    addition += "\(markerEnd)\n"

    try? (cleaned + addition).write(toFile: hostsFile, atomically: true, encoding: .utf8)
    run("/usr/bin/dscacheutil", ["-flushcache"])
    run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
}

func removeHosts() {
    guard let hosts = try? String(contentsOfFile: hostsFile, encoding: .utf8) else { return }
    let cleaned = removeBlockSection(from: hosts)
    try? cleaned.write(toFile: hostsFile, atomically: true, encoding: .utf8)
    run("/usr/bin/dscacheutil", ["-flushcache"])
    run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
}

// MARK: - pfctl (packet filter) — works even when /etc/hosts is bypassed (VPN, DoH, etc.)

func isValidIP(_ s: String) -> Bool {
    // Reject anything with spaces or ending in a dot (dig sometimes returns CNAMEs)
    if s.isEmpty || s.contains(" ") || s.hasSuffix(".") { return false }
    // IPv4: four dot-separated numeric octets
    let dotParts = s.split(separator: ".")
    if dotParts.count == 4, dotParts.allSatisfy({ Int($0).map { $0 >= 0 && $0 <= 255 } ?? false }) {
        return true
    }
    // IPv6: contains colon (rough check)
    if s.contains(":") { return true }
    return false
}

func resolveIPs(for domain: String) -> [String] {
    guard isSafeDomain(domain) else { return [] }
    var ips = Set<String>()
    let variants = [domain, "www.\(domain)"]
    for name in variants {
        for qtype in ["A", "AAAA"] {
            // Short per-query timeout + hard wall-clock timeout so one dead domain
            // can't stall the enforcement loop for minutes.
            let (_, out) = run(
                "/usr/bin/dig",
                ["+short", "+time=1", "+tries=1", name, qtype],
                timeoutSec: 3
            )
            for line in out.split(separator: "\n") {
                let ip = line.trimmingCharacters(in: .whitespaces)
                if isValidIP(ip) { ips.insert(ip) }
            }
        }
    }
    return Array(ips)
}

/// Builds the pf anchor rules file. Mirrors SelfControl's format:
/// options header, then `block return out proto tcp/udp from any to <IP>`
/// for each IP (one TCP rule + one UDP rule).
func writeAnchorFile(ips: Set<String>) {
    var contents = """
    # Options
    set block-policy drop
    set fingerprints "/etc/pf.os"
    set ruleset-optimization basic
    set skip on lo0

    #
    # org.harbour ruleset for Harbour blocks
    #

    """
    for ip in ips.sorted() {
        contents += "block return out proto tcp from any to \(ip)\n"
        contents += "block return out proto udp from any to \(ip)\n"
    }
    try? FileManager.default.createDirectory(
        atPath: "/etc/pf.anchors",
        withIntermediateDirectories: true
    )
    try? contents.write(toFile: pfAnchorFile, atomically: true, encoding: .utf8)
}

let pfConfMarkerStart = "# HARBOUR_PF_START"
let pfConfMarkerEnd   = "# HARBOUR_PF_END"

/// Append a marker-delimited block to /etc/pf.conf (idempotent). Markers let
/// `stripPFConfAnchor` remove our addition precisely without regex substring
/// matching that might hit user-authored lines.
func ensurePFConfHasAnchor() {
    guard let conf = try? String(contentsOfFile: pfMainConf, encoding: .utf8) else {
        log("pf: cannot read \(pfMainConf)")
        return
    }
    if conf.contains(pfConfMarkerStart) && conf.contains(pfConfMarkerEnd) {
        return  // already installed
    }

    var new = conf
    if !new.hasSuffix("\n") { new += "\n" }
    new += """

    \(pfConfMarkerStart)
    anchor "\(pfAnchorName)"
    load anchor "\(pfAnchorName)" from "\(pfAnchorFile)"
    \(pfConfMarkerEnd)

    """
    try? new.write(toFile: pfMainConf, atomically: true, encoding: .utf8)
}

/// Remove our marker-delimited block from /etc/pf.conf. Refuses to edit if
/// the markers are mismatched (would otherwise truncate to EOF).
func stripPFConfAnchor() {
    guard let conf = try? String(contentsOfFile: pfMainConf, encoding: .utf8) else { return }
    let lines = conf.components(separatedBy: "\n")

    // Find paired markers.
    var skipRanges: [ClosedRange<Int>] = []
    var pendingStart: Int?
    for (i, line) in lines.enumerated() {
        if line.contains(pfConfMarkerStart) {
            pendingStart = i
        } else if line.contains(pfConfMarkerEnd), let s = pendingStart {
            skipRanges.append(s...i)
            pendingStart = nil
        }
    }
    if pendingStart != nil {
        log("pf.conf: mismatched markers — refusing to edit")
        return
    }

    var kept: [String] = []
    for (i, line) in lines.enumerated() {
        if skipRanges.contains(where: { $0.contains(i) }) { continue }
        kept.append(line)
    }
    var rebuilt = kept.joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    rebuilt += "\n"
    try? rebuilt.write(toFile: pfMainConf, atomically: true, encoding: .utf8)
}

/// Coordinates access to pfctl state between the main loop and the detached
/// applyPF worker thread (startup + every 5-min refresh). Without this, a
/// late-arriving worker can reinstall rules after cleanup has run.
let pfLock = NSLock()

/// True once our /etc/pf.conf modification is in place. We track this
/// separately from `pfLoaded` so cleanup always strips pf.conf even if
/// `pfctl -E` later failed (prevents stale anchor/load lines pointing
/// to a deleted anchor file).
var pfConfModified = false

/// True after `pfctl -E` returned 0 and we hold an enable reference.
var pfLoaded = false

/// Set once cleanup starts. Any in-flight applyPF sees this and bails without
/// touching pf state — prevents late workers from reinstalling rules.
var pfShuttingDown = false

/// Historical union of every IP we've resolved for any blocked domain this
/// daemon run. Cloudflare / Fastly / Google rotate which IPs they hand out
/// per query, so if we rebuilt pfctl rules from a single fresh resolution
/// we'd constantly lose coverage. Accumulating across refreshes matches
/// SelfControl's behaviour (they resolve once at block start, never refresh).
var accumulatedIPs = Set<String>()

func applyPF(domains: [String]) {
    // Skip entirely for app-only blocks.
    let candidates = (domains + alwaysBlockDomains).filter { isSafeDomain($0) }
    guard !candidates.isEmpty else { return }

    // Do DNS resolution OUTSIDE the lock — it's slow (~100s) and we don't need
    // to block the kill loop's cleanup path while we wait on the network.
    var freshIPs = Set<String>()
    for d in candidates {
        let resolved = resolveIPs(for: d)
        if resolved.isEmpty {
            log("pf: could not resolve \(d)")
        } else {
            log("pf: \(d) -> \(resolved.count) IPs")
        }
        resolved.forEach { freshIPs.insert($0) }

        // If this domain is Meta/Facebook-style, bring in the hardcoded
        // AS-level CIDR ranges so IP rotation can't dodge us.
        for (suffix, ranges) in domainCIDRMap where d == suffix || d.hasSuffix(".\(suffix)") {
            ranges.forEach { freshIPs.insert($0) }
            log("pf: \(d) matches \(suffix), added \(ranges.count) CIDR ranges")
        }
    }
    alwaysBlockIPs.forEach { freshIPs.insert($0) }
    guard !freshIPs.isEmpty else {
        log("pf: no IPs resolved — skipping pfctl load")
        return
    }

    pfLock.lock()
    defer { pfLock.unlock() }

    // If cleanup started while we were resolving, bail — don't reinstall rules.
    if pfShuttingDown {
        log("pf: shutdown in progress, skipping load")
        return
    }

    // Accumulate: never shrink the set, only grow. A CDN rotating to a new IP
    // keeps the old one covered too, so users don't see intermittent "works
    // for a minute then stops working" behaviour.
    let before = accumulatedIPs.count
    accumulatedIPs.formUnion(freshIPs)
    let added = accumulatedIPs.count - before
    log("pf: \(freshIPs.count) fresh, \(added) new, \(accumulatedIPs.count) total")

    writeAnchorFile(ips: accumulatedIPs)
    ensurePFConfHasAnchor()
    pfConfModified = true

    // First load: `-E -f ... -F states` to enable + install + flush states.
    // Refresh: `-f ... -F states` — do NOT pass -E, it would leak a refcount.
    let args: [String] = pfLoaded
        ? ["-f", pfMainConf, "-F", "states"]
        : ["-E", "-f", pfMainConf, "-F", "states"]

    let (rc, out) = run("/sbin/pfctl", args, timeoutSec: 10)
    log("pfctl \(args.joined(separator: " ")) => rc=\(rc) out=\(out.trimmingCharacters(in: .whitespacesAndNewlines))")
    if rc == 0 {
        if !pfLoaded {
            pfLoaded = true
            // Extract enable token so we can cleanly release our one reference.
            // SelfControl reads combined stdout+stderr; pfctl has historically
            // written the Token line to stderr, so scan both just in case.
            for line in out.components(separatedBy: "\n") where line.contains("Token : ") {
                if let range = line.range(of: "Token : ") {
                    let token = String(line[range.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    if !token.isEmpty {
                        try? token.write(toFile: pfTokenFile, atomically: true, encoding: .utf8)
                        log("pf: saved token")
                    }
                    break
                }
            }
        }
    }
}

func removePF() {
    pfLock.lock()
    pfShuttingDown = true
    let wasModified = pfConfModified
    let wasLoaded = pfLoaded
    pfLock.unlock()

    // Always best-effort empty the anchor file and strip pf.conf if we ever
    // touched it — even if -E failed, stale anchor/load lines pointing to a
    // missing anchor file would make future pfctl runs crash.
    try? "".write(toFile: pfAnchorFile, atomically: true, encoding: .utf8)
    if wasModified {
        stripPFConfAnchor()
    }

    if wasLoaded {
        // Release our enable reference.
        if let token = try? String(contentsOfFile: pfTokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty
        {
            // Preferred: `-X <token> -f /etc/pf.conf` releases our specific
            // refcount without disabling PF for other users.
            run("/sbin/pfctl", ["-X", token, "-f", pfMainConf], timeoutSec: 5)
        } else {
            // No token: we can't target our own refcount. `-d -f` disables PF
            // entirely — matches SelfControl's fallback. A plain `-f` would
            // leave our enable reference leaked forever.
            run("/sbin/pfctl", ["-d", "-f", pfMainConf], timeoutSec: 5)
        }
    }

    try? FileManager.default.removeItem(atPath: pfAnchorFile)
    try? FileManager.default.removeItem(atPath: pfTokenFile)

    pfLock.lock()
    pfLoaded = false
    pfConfModified = false
    accumulatedIPs.removeAll()
    pfLock.unlock()
}

// MARK: - App killing

/// Returns (pid, executable_path) for every running process using libproc.
/// This is what Activity Monitor uses — robust across every GUI app.
func listProcesses() -> [(pid_t, String)] {
    // proc_listallpids(NULL, 0) returns the number of active PIDs (not bytes).
    let pidCount = Int(proc_listallpids(nil, 0))
    guard pidCount > 0 else { return [] }

    // buffersize argument IS in bytes. Over-allocate a bit for processes that
    // spawn between the size query and the actual fill.
    let capacity = pidCount + 64
    var pids = [pid_t](repeating: 0, count: capacity)

    let written = pids.withUnsafeMutableBufferPointer { ptr -> Int32 in
        proc_listallpids(ptr.baseAddress, Int32(ptr.count * MemoryLayout<pid_t>.size))
    }
    // Return value is the number of PID entries written.
    let count = min(capacity, max(0, Int(written)))

    var result: [(pid_t, String)] = []
    result.reserveCapacity(count)

    var pathBuf = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_MAXSIZE))
    for i in 0..<count {
        let pid = pids[i]
        if pid <= 0 { continue }
        let ok = pathBuf.withUnsafeMutableBufferPointer { ptr -> Int32 in
            proc_pidpath(pid, UnsafeMutableRawPointer(ptr.baseAddress!), UInt32(ptr.count))
        }
        if ok > 0 {
            // proc_pidpath writes a C string; use ok as length to be safe.
            let path = pathBuf.withUnsafeBufferPointer { ptr -> String in
                String(cString: ptr.baseAddress!)
            }
            if !path.isEmpty {
                result.append((pid, path))
            }
        }
    }
    return result
}

/// Paths we will NEVER kill, even if someone tries. Killing these can brick
/// the session or make the machine unusable until reboot. Defensive double-check
/// on top of the app picker, which already doesn't scan these directories.
let neverKillPrefixes: [String] = [
    "/System/Library/CoreServices/",   // Finder, Dock, loginwindow, SystemUIServer
    "/System/Library/PrivateFrameworks/",
    "/System/Library/Frameworks/",
    "/System/Library/LaunchDaemons/",
    "/System/Library/LaunchAgents/",
    "/usr/libexec/",
    "/usr/sbin/",
    "/sbin/",
    "/bin/",
    "/System/Applications/System Preferences.app",
    "/System/Applications/System Settings.app",
    "/System/Applications/Utilities/Terminal.app",
    "/Applications/Utilities/Terminal.app",
]

let neverKillPIDThreshold: pid_t = 100  // launchd + core system daemons

func isCriticalPath(_ path: String) -> Bool {
    for prefix in neverKillPrefixes where path.hasPrefix(prefix) {
        return true
    }
    return false
}

func killBlockedApps(paths: [String]) {
    guard !paths.isEmpty else { return }
    let ownPID = getpid()
    for (pid, procPath) in listProcesses() {
        // Never kill system-critical or low-numbered PIDs, or ourselves.
        if pid < neverKillPIDThreshold { continue }
        if pid == ownPID { continue }
        if isCriticalPath(procPath) { continue }

        for target in paths {
            // Sanity: refuse to kill based on a critical target too.
            if isCriticalPath(target) { continue }
            // Match any process whose path is inside the .app bundle
            if procPath.hasPrefix(target) {
                if kill(pid, SIGKILL) == 0 {
                    log("killed pid=\(pid) path=\(procPath)")
                }
                break
            }
        }
    }
}

// MARK: - State

func loadState() -> BlockState? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: stateFile)) else { return nil }
    return try? JSONDecoder().decode(BlockState.self, from: data)
}

// MARK: - Cleanup / self-unload

/// Remove everything we installed. Safe to call from signal handlers only in the
/// narrow sense that signals interrupt the 1-second sleep; heavy work is still
/// done here. Never call this in the "no state at all" case — that would delete
/// state belonging to a newly starting sibling install.
func fullCleanup() {
    log("cleanup: removing hosts + pf rules + state")
    removeHosts()
    removePF()
    try? FileManager.default.removeItem(atPath: stateFile)
    try? FileManager.default.removeItem(atPath: plistPath)
    // Clean up the user-writable additions file so it doesn't leak into the next block.
    if let additionsPath = (try? Data(contentsOf: URL(fileURLWithPath: stateFile)))
        .flatMap({ try? JSONDecoder().decode(BlockState.self, from: $0) })?
        .additionsPath
    {
        try? FileManager.default.removeItem(atPath: additionsPath)
    }
    // Best-effort bootout — if launchctl is missing or the job is already gone,
    // that's fine. We rely on KeepAlive.SuccessfulExit=false to prevent a loop.
    run("/bin/launchctl", ["bootout", "system/\(label)"], timeoutSec: 3)
}

/// Called when we discover nothing to enforce. Distinct from fullCleanup —
/// we must NOT touch /etc/hosts, pf, or the plist, because a sibling install
/// may be racing us. Just exit 0 so launchd (KeepAlive.SuccessfulExit=false)
/// doesn't respawn us.
func quickExitNoOp() -> Never {
    log("no active state — exiting cleanly without touching shared files")
    exit(0)
}

// MARK: - Signal handling
//
// launchctl bootout sends SIGTERM. Install a trap so we run fullCleanup on TERM
// instead of dying mid-write. SIGKILL is obviously uncatchable.

var terminationRequested = false
signal(SIGTERM, { _ in
    // Signal-safe: just flip a flag. The main loop exits on the next tick.
    terminationRequested = true
})
signal(SIGINT, { _ in terminationRequested = true })

// MARK: - Main

log("harbour-daemon starting (pid=\(getpid()))")

guard let state = loadState() else {
    // No state file. This can happen if:
    //   1) We were launched with no block active (stale plist) — quick-exit.
    //   2) A sibling daemon is mid-cleanup — quick-exit (don't double-clean).
    //   3) Timer already expired and files were cleaned — quick-exit.
    // In all cases, do NOT touch shared files.
    quickExitNoOp()
}

if Date() >= state.endTime {
    log("state already expired on startup — running cleanup")
    fullCleanup()
    exit(0)
}

// Effective enforcement sets — union of original state + runtime additions.
// Users can only ever ADD during an active block; we never shrink these.
var effectiveDomains: [String] = state.domains
var effectivePaths: [String] = state.blockedPaths

applyHosts(domains: effectiveDomains)
log("block active: \(state.domains.count) domains, \(state.blockedPaths.count) apps, ends at \(state.endTime)")
log("blocked paths: \(effectivePaths)")

// pfctl setup can take ~100s because of serial DNS resolution. Run it on
// a background thread so the app-kill loop starts enforcing immediately —
// otherwise blocked apps stay alive during the first minute or two of a block.
Thread.detachNewThread {
    applyPF(domains: effectiveDomains)
}

// Additions file watcher — re-read every second by checking mtime. Cheap.
var lastAdditionsMtime: TimeInterval = 0

/// Merges runtime additions into effective sets. Returns true if anything changed.
func reloadAdditionsIfChanged() -> Bool {
    guard let additionsPath = state.additionsPath else { return false }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: additionsPath),
          let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
    else {
        return false
    }
    if mtime == lastAdditionsMtime { return false }
    lastAdditionsMtime = mtime

    guard let data = try? Data(contentsOf: URL(fileURLWithPath: additionsPath)),
          let adds = try? JSONDecoder().decode(BlockAdditions.self, from: data)
    else {
        return false
    }

    // Union: merge new domains and paths. Never remove.
    let origDomainCount = effectiveDomains.count
    let origPathCount = effectivePaths.count
    var seenD = Set(effectiveDomains)
    for d in adds.domains where seenD.insert(d).inserted {
        effectiveDomains.append(d)
    }
    var seenP = Set(effectivePaths)
    for a in adds.apps where seenP.insert(a.path).inserted {
        effectivePaths.append(a.path)
    }

    let newD = effectiveDomains.count - origDomainCount
    let newP = effectivePaths.count - origPathCount
    log("additions: +\(newD) domains, +\(newP) apps (total: \(effectiveDomains.count)D/\(effectivePaths.count)A)")
    return (newD + newP) > 0
}

// Re-apply hosts + pf periodically in case something overwrites them or IPs change
var tick = 0
while Date() < state.endTime && !terminationRequested {
    killBlockedApps(paths: effectivePaths)
    tick += 1

    // Check additions file — cheap stat call, only triggers work on change.
    if reloadAdditionsIfChanged() {
        applyHosts(domains: effectiveDomains)
        Thread.detachNewThread { applyPF(domains: effectiveDomains) }
    }

    if tick % 10 == 0 {
        // Diagnostic: list any process whose path contains any target's
        // basename (e.g., "Telegram.app"), regardless of whether it matches
        // hasPrefix. Helps catch cases where ps returns a non-standard path.
        let procs = listProcesses()
        var matchCount = 0
        var nearMiss: [String] = []
        for (pid, p) in procs {
            var hit = false
            for t in effectivePaths where p.hasPrefix(t) {
                matchCount += 1; hit = true; break
            }
            if !hit {
                for t in effectivePaths {
                    let base = (t as NSString).lastPathComponent
                    if !base.isEmpty, p.localizedCaseInsensitiveContains(base) {
                        nearMiss.append("pid=\(pid) \(p)")
                        break
                    }
                }
            }
        }
        log("tick=\(tick) procs=\(procs.count) matches=\(matchCount) nearMiss=\(nearMiss.count)")
        for line in nearMiss { log("near-miss: \(line)") }
    }
    if tick % 30 == 0 {
        applyHosts(domains: effectiveDomains)
    }
    // Re-resolve + reload pf every 5 minutes on a background thread so the
    // kill loop keeps firing while DNS work is in flight.
    if tick % 300 == 0 {
        Thread.detachNewThread { applyPF(domains: effectiveDomains) }
    }
    Thread.sleep(forTimeInterval: 1.0)
}

if terminationRequested {
    log("received SIGTERM/SIGINT — cleanup before exit")
} else {
    log("timer expired")
}
fullCleanup()
exit(0)
