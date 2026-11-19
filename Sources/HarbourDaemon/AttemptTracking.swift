import Foundation
import Darwin
import HarbourCore

// MARK: - Attempt recorder

/// Thread-safe owner of the block owner's `/var/db/harbour/stats-<account UUID>.json`.
/// The sink threads and the kill loop record into memory; the main loop
/// flushes at most every few seconds.
///
/// Attempts are deliberately not written to the daemon log, which other
/// accounts on the Mac can read: the history file is the only record.
final class AttemptRecorder {
    /// Read limit. Writes are compacted to `maxWriteBytes`, comfortably below
    /// it, so the daemon can always load what it saved.
    private static let maxFileBytes = 4 << 20
    private static let maxWriteBytes = 3 << 20

    private let lock = NSLock()
    private var stats: AttemptStats
    private var dirty = false
    private var lastFlush = Date.distantPast
    private var siteBursts = AttemptDebouncer(window: 10)
    private var appBursts = AttemptDebouncer(window: 5)
    /// Visited hostname → blocked entry (BlockedHostMatcher.lookup).
    private var hostLookup: [String: String] = [:]
    private let sessionStart: Date
    /// The account that started the block: whose history this is, and the
    /// only one granted read access.
    private let ownerUID: uid_t?
    /// nil when the owner is unknown (a state from an older build): counts
    /// then stay in memory rather than landing in someone else's history.
    private let path: String?

    /// The block owner, or nil when unknown (then nothing is recorded).
    var ownerUIDValue: uid_t? { ownerUID }

    /// The owner's account UUID at startup. Every write re-checks that the UID
    /// still maps to it, so a deleted account's reassigned UID never gains
    /// access to the history.
    private let ownerUUID: String?

    /// `ownerUUID` is the account UUID the app recorded when the block
    /// started. If the UID now maps to a different account (deleted and
    /// reassigned before a resume), nothing is attributed or saved.
    init(sessionStart: Date, ownerUID: uid_t?, ownerUUID recorded: String?) {
        self.sessionStart = sessionStart
        let current = ownerUID.flatMap { $0 == 0 ? nil : AttemptStats.accountUUID($0) }
        if let recorded, current?.uppercased() != recorded.uppercased() {
            log("stats: the block owner's account changed since the block started; attempts are not saved")
            self.ownerUID = nil
            ownerUUID = nil
        } else {
            self.ownerUID = ownerUID
            ownerUUID = current
        }
        path = ownerUUID.map(AttemptStats.filePath(forAccountUUID:))
        if path == nil { log("stats: block owner unknown; attempts are not saved") }
        // Pre-release builds kept one shared, world-readable file.
        unlink("/var/db/harbour/stats.json")
        var loaded = path.map(Self.load) ?? AttemptStats()
        loaded.beginSession(sessionStart)
        loaded.prune(now: Date())
        stats = loaded
        dirty = true
    }

    /// Existing history, or empty when there is none. A file that exists but
    /// can't be read is moved aside rather than overwritten, so a bad read
    /// never erases months of history.
    private static func load(_ path: String) -> AttemptStats {
        guard FileManager.default.fileExists(atPath: path) else { return AttemptStats() }
        if let data = SecureFileRead.regularFile(atPath: path, maxBytes: maxFileBytes),
           let stats = try? AttemptStats.decoder.decode(AttemptStats.self, from: data) {
            return stats
        }
        let aside = path + ".unreadable-\(Int(Date().timeIntervalSince1970))"
        if rename(path, aside) == 0 {
            log("stats: could not read \(path); kept it as \(aside) and started a new history")
        } else {
            log("stats: could not read \(path) (errno \(errno)); starting a new history")
        }
        return AttemptStats()
    }

    func setBlockedDomains(_ domains: [String]) {
        let lookup = BlockedHostMatcher.lookup(blocked: domains)
        lock.lock(); hostLookup = lookup; lock.unlock()
    }

    /// The owner's processes that were already running when the block
    /// started or their app was added. Closing them isn't an attempt, however
    /// long setup takes; a later launch (a new PID) is.
    private var preexistingPIDs = Set<pid_t>()

    func excludePreexisting(_ pids: [pid_t]) {
        lock.lock(); preexistingPIDs.formUnion(pids); lock.unlock()
    }

    /// A browser connected to the sink asking for `host`. `connectionOwner`
    /// finds the account that opened the connection: hosts entries apply to
    /// every user on the Mac, but only the block owner's attempts belong in
    /// the owner's history. When attribution fails nothing is counted.
    func recordHost(_ host: String, connectionOwner: () -> uid_t?) {
        guard let owner = ownerUID else { return }
        lock.lock()
        guard let domain = BlockedHostMatcher.match(host: host, in: hostLookup),
              siteBursts.wouldCount(domain, at: Date()) else { lock.unlock(); return }
        lock.unlock()
        // Outside the lock: looking up the socket's owner spawns lsof.
        guard connectionOwner() == owner else { return }
        lock.lock()
        // Sampled under the lock so concurrent connections are debounced in
        // the order they're recorded.
        let now = Date()
        if siteBursts.shouldCount(domain, at: now) {
            stats.record(.site, key: domain, at: now, sessionStart: sessionStart)
            dirty = true
        }
        lock.unlock()
    }

    /// The kill loop terminated the owner's process `pid` of the blocked
    /// bundle `path`.
    func recordApp(_ path: String, pid: pid_t) {
        lock.lock()
        let now = Date()
        // Only that process is excluded (its helpers were running too, so
        // they're in the set); an immediate relaunch is a new PID and counts.
        if preexistingPIDs.remove(pid) != nil {
            lock.unlock()
            return
        }
        guard appBursts.shouldCount(path, at: now) else { lock.unlock(); return }
        stats.record(.app, key: path, at: now, sessionStart: sessionStart)
        dirty = true
        lock.unlock()
    }

    /// Writes happen on this queue, never on the enforcement loop: encoding,
    /// fsync and the ACL subprocess can be slow.
    private let writer = DispatchQueue(label: "com.harbour.stats-writer")
    private var writeScheduled = false

    /// Periodic flushes are queued (and coalesced); `force` writes now and
    /// waits, for shutdown.
    func flush(force: Bool = false) {
        if force {
            writer.sync { writeNow(force: true) }
            return
        }
        lock.lock()
        let due = dirty && !writeScheduled && Date().timeIntervalSince(lastFlush) >= 5
        if due { writeScheduled = true }
        lock.unlock()
        guard due else { return }
        writer.async { [self] in
            writeNow(force: false)
            lock.lock(); writeScheduled = false; lock.unlock()
        }
    }

    private func writeNow(force: Bool) {
        guard let path else { return }
        lock.lock()
        let now = Date()
        guard dirty, force || now.timeIntervalSince(lastFlush) >= 5 else { lock.unlock(); return }
        var snapshot = stats
        dirty = false
        lastFlush = now
        lock.unlock()

        snapshot.compact(toFit: Self.maxWriteBytes)
        if let data = try? AttemptStats.encoder.encode(snapshot), write(data, to: path) { return }
        // Keep the counts pending so the next tick (or the final flush) retries.
        lock.lock(); dirty = true; lock.unlock()
    }

    /// Writes through a temporary file that already has its final permissions:
    /// 0600 root, plus a read-only ACL entry for the user who started the block.
    /// Other accounts on the Mac can't read the history.
    private func write(_ data: Data, to path: String) -> Bool {
        let tmp = path + ".tmp"
        unlink(tmp)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            log("stats: could not create \(tmp) (errno \(errno))")
            return false
        }
        let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        let synced = fsync(fd) == 0
        close(fd)
        guard written == data.count, synced else {
            log("stats: could not write \(tmp) (errno \(errno))")
            unlink(tmp)
            return false
        }
        // Without the owner's read access the app couldn't show the history;
        // keep the previous file and retry rather than replace it.
        guard let uid = ownerUID, AttemptStats.accountUUID(uid) == ownerUUID, ownerUUID != nil else {
            log("stats: the block owner's account changed; not saving")
            unlink(tmp)
            return false
        }
        guard let name = Self.userName(uid) else {
            log("stats: no account name for the block owner; not saving")
            unlink(tmp)
            return false
        }
        let (rc, out) = run("/bin/chmod", ["+a", "user:\(name) allow read", tmp], timeoutSec: 3)
        guard rc == 0 else {
            log("stats: could not grant the owner read access: \(out)")
            unlink(tmp)
            return false
        }
        guard rename(tmp, path) == 0 else {
            log("stats: could not replace \(path) (errno \(errno))")
            unlink(tmp)
            return false
        }
        return true
    }

    private static func userName(_ uid: uid_t) -> String? {
        guard let pw = getpwuid(uid), let name = pw.pointee.pw_name else { return nil }
        let value = String(cString: name)
        // Only plain account names reach chmod's ACL syntax.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !value.isEmpty, value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }
}

// MARK: - Sink listener

/// Blocked websites resolve to a dedicated loopback address. This listener
/// accepts those connections, reads just enough to learn the requested
/// hostname (TLS SNI or HTTP Host), resets the connection, and reports the
/// hostname. Pages still fail to load exactly as before; they are only counted.
///
/// A separate address (not 127.0.0.1) keeps local development servers on
/// ports 80/443 untouched. If the alias or either port is unavailable, the
/// daemon falls back to the 0.0.0.0 null route and simply does not count.
final class AttemptSink {
    static let address = "127.72.66.1"
    static let ports: [UInt16] = [443, 80]
    /// Present while Harbour owns the alias, so a crashed run's leftover is
    /// recognised and an alias someone else configured is never touched.
    static let ownerMarker = "/var/db/harbour/sink-alias"

    private var listeners: [Int32] = []
    /// Listener descriptor → its port.
    private var listenerPorts: [Int32: UInt16] = [:]
    /// One accepted connection: the endpoints that identify it while it is
    /// open, and when it was accepted.
    struct Connection {
        let clientAddress: String
        let clientPort: UInt16
        let serverPort: UInt16
        let acceptedAt: Date
        /// lsof's spelling of the client end: "<ip>:<port>-><sink>:<port>".
        var lsofName: String { "\(clientAddress):\(clientPort)->\(AttemptSink.address):\(serverPort)" }
    }

    /// Called with the requested hostname while the connection is still
    /// open, so its owning process can be looked up.
    private let onHost: (String, Connection) -> Void
    private let stateLock = NSLock()
    private var stopped = false
    private var thread: Thread?
    private let acceptDone = DispatchSemaphore(value: 0)
    private let connections = DispatchQueue(label: "com.harbour.sink", attributes: .concurrent)
    /// In-flight connection handlers, drained (with a time limit) by stop().
    private let inFlight = DispatchGroup()
    /// Caps concurrent connections; extras are reset immediately.
    private let slots = DispatchSemaphore(value: 16)

    init(onHost: @escaping (String, Connection) -> Void) {
        self.onHost = onHost
    }

    /// True when the alias is Harbour's and both ports are listening. Any
    /// partial setup is undone, so blocked names never point at an address
    /// where another service could answer.
    func start() -> Bool {
        if Self.aliasPresent() {
            guard FileManager.default.fileExists(atPath: Self.ownerMarker) else {
                log("sink: \(Self.address) is already configured by something else; attempts will not be counted")
                return false
            }
            log("sink: reusing the alias left by an earlier run")
        } else {
            // Record ownership before adding, so a crash in between still
            // lets the next run clean up.
            guard FileManager.default.createFile(atPath: Self.ownerMarker, contents: Data(),
                                                 attributes: [.posixPermissions: 0o600]) else {
                log("sink: could not record alias ownership; attempts will not be counted")
                return false
            }
            let (rc, _) = run("/sbin/ifconfig", ["lo0", "alias", Self.address, "up"], timeoutSec: 3)
            guard rc == 0 else {
                try? FileManager.default.removeItem(atPath: Self.ownerMarker)
                log("sink: could not add loopback alias; attempts will not be counted")
                return false
            }
        }
        for port in Self.ports {
            guard let fd = Self.listen(on: port) else {
                log("sink: port \(port) unavailable; attempts will not be counted")
                listeners.forEach { close($0) }
                listeners = []
                Self.removeAliasIfOwned()
                return false
            }
            listeners.append(fd)
            listenerPorts[fd] = port
        }
        let t = Thread { [weak self] in
            self?.acceptLoop()
            self?.acceptDone.signal()
        }
        t.name = "harbour-sink"
        thread = t
        t.start()
        log("sink: listening on \(Self.address)")
        return true
    }

    /// Stops accepting, waits for the accept thread and in-flight connections
    /// to finish (so their attempts reach the final flush), then closes the
    /// listeners and removes the alias.
    /// Returns false when Harbour's alias is still present afterwards.
    @discardableResult
    func stop() -> Bool {
        stateLock.lock()
        let wasRunning = !stopped && thread != nil
        stopped = true
        stateLock.unlock()
        guard wasRunning else { return Self.removeAliasIfOwned() }
        // The accept loop polls with a 500 ms timeout and checks `stopped`;
        // descriptors are closed only after it exits, so none is reused under it.
        _ = acceptDone.wait(timeout: .now() + 2)
        // Handlers stop attributing once `stopped` is set (no new lsof
        // scans), so this is short; the limit keeps cleanup inside launchd's
        // termination grace period even if one is stuck.
        if inFlight.wait(timeout: .now() + 2) == .timedOut {
            log("sink: connections still in flight at shutdown; their attempts are dropped")
        }
        stateLock.lock()
        let fds = listeners
        listeners = []
        stateLock.unlock()
        for fd in fds { close(fd) }
        return Self.removeAliasIfOwned()
    }

    var isStopping: Bool { isStopped }

    /// Whether lo0 carries the alias; nil when ifconfig couldn't tell.
    static func aliasState() -> Bool? {
        let (rc, out) = run("/sbin/ifconfig", ["lo0"], timeoutSec: 3)
        guard rc == 0, out.contains("lo0:") else { return nil }
        return out.contains("inet \(address) ")
    }

    static func aliasPresent() -> Bool { aliasState() ?? true }

    /// Client end (lsof name) → owning UID for connections to the sink, from
    /// one lsof scan. Connections of one page load share a snapshot: callers
    /// wait for a scan in progress instead of each starting their own.
    private static let ownersLock = NSLock()
    private static var owners: [String: uid_t] = [:]
    private static var ownersTakenAt = Date.distantPast

    /// The account owning the client end of `connection`, or nil when it
    /// can't be determined. Only a snapshot taken after the connection was
    /// accepted is used: while the connection is open (it is reset only after
    /// this returns) its endpoints can't belong to another socket, so the
    /// entry is this connection's.
    func connectionOwnerUID(_ connection: Connection) -> uid_t? {
        guard !isStopped else { return nil }
        Self.ownersLock.lock(); defer { Self.ownersLock.unlock() }
        if Self.ownersTakenAt <= connection.acceptedAt {
            guard !isStopped else { return nil }
            Self.ownersTakenAt = Date()
            Self.owners = Self.scanOwners()
        }
        // Root clients are known but never the owner.
        return Self.owners[connection.lsofName].flatMap { $0 == 0 ? nil : $0 }
    }

    private static func scanOwners() -> [String: uid_t] {
        let (rc, out) = run("/usr/sbin/lsof", ["-nP", "-iTCP@\(address)", "-sTCP:ESTABLISHED", "-F", "pun"],
                            timeoutSec: 2)
        guard rc == 0 else { return [:] }
        // -F output: p<pid>, u<uid>, then one n<local>-><remote> per socket.
        var uid: uid_t?
        var found: [String: Set<uid_t>] = [:]
        let suffixes = ports.map { "->\(address):\($0)" }
        for line in out.split(separator: "\n") {
            switch line.first {
            case "p": uid = nil
            case "u": uid = uid_t(line.dropFirst())
            case "n":
                let name = String(line.dropFirst())
                // Client ends only: "<src>:<port>->127.72.66.1:443".
                if let u = uid, suffixes.contains(where: name.hasSuffix) { found[name, default: []].insert(u) }
            default: break
            }
        }
        // Exactly one owner per connection; ambiguous ones stay unattributed.
        return found.compactMapValues { $0.count == 1 ? $0.first : nil }
    }

    /// Whether PF really rejects other ports on the sink address: listens on
    /// a probe port there and tries to connect to it. A connection that gets
    /// through means a local service on that port could too.
    static func guardIsEffective() -> Bool {
        let server = socket(AF_INET, SOCK_STREAM, 0)
        guard server >= 0 else { return false }
        defer { close(server) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        inet_pton(AF_INET, address, &addr.sin_addr)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ready = withUnsafeMutablePointer(to: &addr) { ptr -> Bool in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, length) == 0 && Darwin.listen(server, 1) == 0
                    && getsockname(server, $0, &length) == 0
            }
        }
        guard ready, addr.sin_port != 0 else { return false }

        let client = socket(AF_INET, SOCK_STREAM, 0)
        guard client >= 0 else { return false }
        defer { close(client) }
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) | O_NONBLOCK)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return false }  // connected: not filtered
        if errno == ECONNREFUSED { return true }
        guard errno == EINPROGRESS else { return false }
        var pfd = pollfd(fd: client, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, 1000) > 0 else { return false }  // undecided: stay safe
        var err: Int32 = 0
        var errLength = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(client, SOL_SOCKET, SO_ERROR, &err, &errLength)
        // Reset by PF's "block return" counts as rejected; success or any
        // other outcome does not.
        return err == ECONNREFUSED || err == ECONNRESET
    }

    /// Removes the alias only if Harbour added it, including one a crashed
    /// earlier run left behind. The ownership marker goes only once the alias
    /// is confirmed gone, so a failed removal is retried by the next cleanup.
    /// True when no Harbour-owned alias remains.
    @discardableResult
    static func removeAliasIfOwned() -> Bool {
        guard FileManager.default.fileExists(atPath: ownerMarker) else { return true }
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.3) }
            if aliasState() != false {
                run("/sbin/ifconfig", ["lo0", "-alias", address], timeoutSec: 3)
            }
            if aliasState() == false {
                try? FileManager.default.removeItem(atPath: ownerMarker)
                return true
            }
        }
        log("sink: could not confirm \(address) was removed; will retry at next cleanup")
        return false
    }

    private var isStopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return stopped
    }

    private static func listen(on port: UInt16) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, address, &addr.sin_addr)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 64) == 0 else {
            close(fd)
            return nil
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    private func acceptLoop() {
        while !isStopped {
            stateLock.lock()
            let ports = listenerPorts
            var pfds = listeners.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            stateLock.unlock()
            guard !pfds.isEmpty else { return }
            let ready = poll(&pfds, nfds_t(pfds.count), 500)
            if ready <= 0 { continue }
            for p in pfds where p.revents & Int16(POLLIN) != 0 {
                var peer = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let client = withUnsafeMutablePointer(to: &peer) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(p.fd, $0, &length) }
                }
                guard client >= 0 else { continue }
                var ip = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &peer.sin_addr, &ip, socklen_t(INET_ADDRSTRLEN))
                handle(client, Connection(clientAddress: String(cString: ip),
                                          clientPort: UInt16(bigEndian: peer.sin_port),
                                          serverPort: ports[p.fd] ?? 0,
                                          acceptedAt: Date()))
            }
        }
    }

    private func handle(_ fd: Int32, _ connection: Connection) {
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        // accept() inherits O_NONBLOCK; reads below rely on a receive timeout.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        guard slots.wait(timeout: .now()) == .success else {
            Self.reset(fd)
            return
        }
        inFlight.enter()
        connections.async { [self] in
            defer { slots.signal(); inFlight.leave() }
            if let host = Self.readHost(fd), !isStopped { onHost(host, connection) }
            Self.reset(fd)
        }
    }

    private static func readHost(_ fd: Int32) -> String? {
        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let deadline = Date().addingTimeInterval(2)
        var data: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < RequestHostParser.maxBytes && Date() < deadline {
            let want = min(buffer.count, RequestHostParser.maxBytes - data.count)
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, want) }
            if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
            switch RequestHostParser.parse(data) {
            case .needMore: continue
            case .host(let h): return h
            case .unrecognized: return nil
            }
        }
        return nil
    }

    /// Close with RST so the browser fails fast, as with the null route.
    private static func reset(_ fd: Int32) {
        var l = linger(l_onoff: 1, l_linger: 0)
        setsockopt(fd, SOL_SOCKET, SO_LINGER, &l, socklen_t(MemoryLayout<linger>.size))
        close(fd)
    }
}
