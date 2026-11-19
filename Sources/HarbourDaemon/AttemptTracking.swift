import Foundation
import Darwin
import HarbourCore

// MARK: - Attempt recorder

/// Thread-safe owner of `/var/db/harbour/stats.json`. The sink threads and the
/// kill loop record into memory; the main loop flushes at most every few seconds.
final class AttemptRecorder {
    static let path = "/var/db/harbour/stats.json"
    private static let maxFileBytes = 4 << 20

    private let lock = NSLock()
    private var stats: AttemptStats
    private var dirty = false
    private var lastFlush = Date.distantPast
    private var siteBursts = AttemptDebouncer(window: 10)
    private var appBursts = AttemptDebouncer(window: 5)
    private var blockedDomains: [String] = []
    private let sessionStart: Date

    init(sessionStart: Date) {
        self.sessionStart = sessionStart
        var loaded = SecureFileRead.regularFile(atPath: Self.path, maxBytes: Self.maxFileBytes)
            .flatMap { try? Self.decoder.decode(AttemptStats.self, from: $0) } ?? AttemptStats()
        loaded.beginSession(sessionStart)
        loaded.prune(now: Date())
        stats = loaded
        dirty = true
    }

    func setBlockedDomains(_ domains: [String]) {
        lock.lock(); blockedDomains = domains; lock.unlock()
    }

    /// Paths that must not count until their window passes: apps that were
    /// already running when the block started or the app was added.
    func suppressApps(_ paths: [String], at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        for p in paths { appBursts.suppress(p, at: date) }
    }

    /// A browser connected to the sink asking for `host`.
    func recordHost(_ host: String, at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard let domain = BlockedHostMatcher.match(host: host, blocked: blockedDomains),
              siteBursts.shouldCount(domain, at: date) else { return }
        stats.record(.site, key: domain, at: date, sessionStart: sessionStart)
        dirty = true
        log("attempt: site \(domain)")
    }

    /// The kill loop terminated a process of the blocked bundle `path`.
    func recordApp(_ path: String, at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard appBursts.shouldCount(path, at: date) else { return }
        stats.record(.app, key: path, at: date, sessionStart: sessionStart)
        dirty = true
        log("attempt: app \(path)")
    }

    func flush(force: Bool = false) {
        lock.lock()
        let now = Date()
        guard dirty, force || now.timeIntervalSince(lastFlush) >= 5 else { lock.unlock(); return }
        let snapshot = stats
        dirty = false
        lastFlush = now
        lock.unlock()

        guard let data = try? Self.encoder.encode(snapshot) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: Self.path), options: .atomic)
            // Readable by the app running as the logged-in user.
            chmod(Self.path, 0o644)
        } catch {
            log("stats: could not write: \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Sink listener

/// Blocked websites resolve to a dedicated loopback address. This listener
/// accepts those connections, reads just enough to learn the requested
/// hostname (TLS SNI or HTTP Host), resets the connection, and reports the
/// hostname. Pages still fail to load exactly as before; they are only counted.
///
/// A separate address (not 127.0.0.1) keeps local development servers on
/// ports 80/443 untouched. If the alias or the ports are unavailable, the
/// daemon falls back to the 0.0.0.0 null route and simply does not count.
final class AttemptSink {
    static let address = "127.72.66.1"
    static let ports: [UInt16] = [443, 80]

    private var listeners: [Int32] = []
    private let onHost: (String) -> Void
    private let stateLock = NSLock()
    private var stopped = false
    private var thread: Thread?
    private let connections = DispatchQueue(label: "com.harbour.sink", attributes: .concurrent)
    /// Caps concurrent connections; extras are reset immediately.
    private let slots = DispatchSemaphore(value: 16)

    init(onHost: @escaping (String) -> Void) {
        self.onHost = onHost
    }

    /// True when at least the HTTPS port is listening.
    func start() -> Bool {
        let (rc, _) = run("/sbin/ifconfig", ["lo0", "alias", Self.address, "up"], timeoutSec: 3)
        guard rc == 0 else {
            log("sink: could not add loopback alias; attempts will not be counted")
            return false
        }
        for port in Self.ports {
            if let fd = Self.listen(on: port) {
                listeners.append(fd)
            } else {
                log("sink: port \(port) unavailable")
            }
        }
        guard !listeners.isEmpty else {
            Self.removeAlias()
            return false
        }
        let t = Thread { [weak self] in self?.acceptLoop() }
        t.name = "harbour-sink"
        thread = t
        t.start()
        log("sink: listening on \(Self.address)")
        return true
    }

    func stop() {
        stateLock.lock()
        let wasRunning = !stopped && !listeners.isEmpty
        stopped = true
        let fds = listeners
        listeners = []
        stateLock.unlock()
        for fd in fds { close(fd) }
        if wasRunning { Self.removeAlias() }
    }

    /// Removes the alias even if a crashed previous run left it behind.
    static func removeAlias() {
        run("/sbin/ifconfig", ["lo0", "-alias", address], timeoutSec: 3)
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
