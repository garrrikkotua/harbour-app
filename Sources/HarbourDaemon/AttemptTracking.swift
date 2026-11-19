import Foundation
import Darwin
import HarbourCore

// MARK: - Attempt recorder

/// Thread-safe owner of `/var/db/harbour/stats.json`. The sink threads and the
/// kill loop record into memory; the main loop flushes at most every few seconds.
final class AttemptRecorder {
    static let path = "/var/db/harbour/stats.json"
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
    /// The account that started the block; the only one granted read access.
    private let readerUID: uid_t?

    init(sessionStart: Date, readerUID: uid_t?) {
        self.sessionStart = sessionStart
        self.readerUID = readerUID
        var loaded = Self.load()
        loaded.beginSession(sessionStart)
        loaded.prune(now: Date())
        stats = loaded
        dirty = true
    }

    /// Existing history, or empty when there is none. A file that exists but
    /// can't be read is moved aside rather than overwritten, so a bad read
    /// never erases months of history.
    private static func load() -> AttemptStats {
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

    /// Paths that must not count until their window passes: apps that were
    /// already running when the block started or the app was added.
    func suppressApps(_ paths: [String]) {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        for p in paths { appBursts.suppress(p, at: now) }
    }

    /// A browser connected to the sink asking for `host`.
    func recordHost(_ host: String) {
        lock.lock()
        // Sampled under the lock so concurrent connections are debounced in
        // the order they're recorded.
        let now = Date()
        guard let domain = BlockedHostMatcher.match(host: host, in: hostLookup),
              siteBursts.shouldCount(domain, at: now) else { lock.unlock(); return }
        stats.record(.site, key: domain, at: now, sessionStart: sessionStart)
        dirty = true
        lock.unlock()
        log("attempt: site \(domain)")
    }

    /// The kill loop terminated a process of the blocked bundle `path`.
    func recordApp(_ path: String) {
        lock.lock()
        let now = Date()
        guard appBursts.shouldCount(path, at: now) else { lock.unlock(); return }
        stats.record(.app, key: path, at: now, sessionStart: sessionStart)
        dirty = true
        lock.unlock()
        log("attempt: app \(path)")
    }

    func flush(force: Bool = false) {
        lock.lock()
        let now = Date()
        guard dirty, force || now.timeIntervalSince(lastFlush) >= 5 else { lock.unlock(); return }
        var snapshot = stats
        dirty = false
        lastFlush = now
        lock.unlock()

        snapshot.compact(toFit: Self.maxWriteBytes)
        if let data = try? AttemptStats.encoder.encode(snapshot), write(data) { return }
        // Keep the counts pending so the next tick (or the final flush) retries.
        lock.lock(); dirty = true; lock.unlock()
    }

    /// Writes through a temporary file that already has its final permissions:
    /// 0600 root, plus a read-only ACL entry for the user who started the block.
    /// Other accounts on the Mac can't read the history.
    private func write(_ data: Data) -> Bool {
        let tmp = Self.path + ".tmp"
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
        if let uid = readerUID, uid != 0, let name = Self.userName(uid) {
            let (rc, out) = run("/bin/chmod", ["+a", "user:\(name) allow read", tmp], timeoutSec: 3)
            if rc != 0 { log("stats: could not grant \(name) read access: \(out)") }
        }
        guard rename(tmp, Self.path) == 0 else {
            log("stats: could not replace \(Self.path) (errno \(errno))")
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
    private let onHost: (String) -> Void
    private let stateLock = NSLock()
    private var stopped = false
    private var thread: Thread?
    private let acceptDone = DispatchSemaphore(value: 0)
    private let connections = DispatchQueue(label: "com.harbour.sink", attributes: .concurrent)
    /// Caps concurrent connections; extras are reset immediately.
    private let slots = DispatchSemaphore(value: 16)

    init(onHost: @escaping (String) -> Void) {
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
            FileManager.default.createFile(atPath: Self.ownerMarker, contents: Data(),
                                           attributes: [.posixPermissions: 0o600])
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
    func stop() {
        stateLock.lock()
        let wasRunning = !stopped && thread != nil
        stopped = true
        stateLock.unlock()
        guard wasRunning else { return }
        // The accept loop polls with a 500 ms timeout and checks `stopped`;
        // descriptors are closed only after it exits, so none is reused under it.
        _ = acceptDone.wait(timeout: .now() + 3)
        connections.sync(flags: .barrier) {}
        stateLock.lock()
        let fds = listeners
        listeners = []
        stateLock.unlock()
        for fd in fds { close(fd) }
        Self.removeAliasIfOwned()
    }

    static func aliasPresent() -> Bool {
        run("/sbin/ifconfig", ["lo0"], timeoutSec: 3).output.contains("inet \(address) ")
    }

    /// Removes the alias only if Harbour added it, including one a crashed
    /// earlier run left behind.
    static func removeAliasIfOwned() {
        guard FileManager.default.fileExists(atPath: ownerMarker) else { return }
        if aliasPresent() {
            run("/sbin/ifconfig", ["lo0", "-alias", address], timeoutSec: 3)
        }
        try? FileManager.default.removeItem(atPath: ownerMarker)
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
            var pfds = listeners.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            stateLock.unlock()
            guard !pfds.isEmpty else { return }
            let ready = poll(&pfds, nfds_t(pfds.count), 500)
            if ready <= 0 { continue }
            for p in pfds where p.revents & Int16(POLLIN) != 0 {
                let client = accept(p.fd, nil, nil)
                guard client >= 0 else { continue }
                handle(client)
            }
        }
    }

    private func handle(_ fd: Int32) {
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        // accept() inherits O_NONBLOCK; reads below rely on a receive timeout.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        guard slots.wait(timeout: .now()) == .success else {
            Self.reset(fd)
            return
        }
        connections.async { [self] in
            defer { slots.signal() }
            let host = Self.readHost(fd)
            Self.reset(fd)
            if let host { onHost(host) }
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
