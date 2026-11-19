import Foundation

/// Counts of blocked open attempts, written by the root daemon to
/// `/var/db/harbour/stats.json` and read by the app. The file outlives single
/// blocks, so the app can show history across sessions.
public struct AttemptStats: Codable, Equatable {
    public struct Counts: Codable, Equatable {
        /// Blocked domain (as the user entered it) → attempts.
        public var sites: [String: Int]
        /// Blocked app bundle path → attempts.
        public var apps: [String: Int]

        public init(sites: [String: Int] = [:], apps: [String: Int] = [:]) {
            self.sites = sites
            self.apps = apps
        }

        public var total: Int { sites.values.reduce(0, +) + apps.values.reduce(0, +) }

        public mutating func add(_ other: Counts) {
            for (k, v) in other.sites { sites[k, default: 0] += v }
            for (k, v) in other.apps { apps[k, default: 0] += v }
        }
    }

    public enum Kind { case site, app }

    public var version: Int
    /// Local calendar day ("yyyy-MM-dd") → counts.
    public var days: [String: Counts]
    /// Start time of the block `session` belongs to.
    public var sessionStart: Date?
    public var session: Counts

    public init(days: [String: Counts] = [:], sessionStart: Date? = nil, session: Counts = Counts()) {
        self.version = 1
        self.days = days
        self.sessionStart = sessionStart
        self.session = session
    }

    /// Days older than this are dropped so the root-written file stays small.
    public static let retentionDays = 400
    /// Caps per-day keys; a misbehaving client can't grow the file without bound.
    public static let maxKeysPerDay = 500

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Records one attempt. `sessionStart` identifies the running block; a new
    /// value resets the per-session counts.
    public mutating func record(_ kind: Kind, key: String, at date: Date,
                                sessionStart start: Date, calendar: Calendar = .current) {
        if sessionStart != start {
            sessionStart = start
            session = Counts()
        }
        let day = Self.dayKey(for: date, calendar: calendar)
        var counts = days[day] ?? Counts()
        switch kind {
        case .site:
            guard counts.sites[key] != nil || counts.sites.count < Self.maxKeysPerDay else { return }
            counts.sites[key, default: 0] += 1
            session.sites[key, default: 0] += 1
        case .app:
            guard counts.apps[key] != nil || counts.apps.count < Self.maxKeysPerDay else { return }
            counts.apps[key, default: 0] += 1
            session.apps[key, default: 0] += 1
        }
        days[day] = counts
    }

    /// Resets the session counts when a different block starts, without
    /// recording anything.
    public mutating func beginSession(_ start: Date) {
        guard sessionStart != start else { return }
        sessionStart = start
        session = Counts()
    }

    public mutating func prune(now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }
        let cutoffKey = Self.dayKey(for: cutoff, calendar: calendar)
        // Keys are zero-padded ISO dates, so string order is date order.
        days = days.filter { $0.key >= cutoffKey }
    }

    /// Sum of the last `count` days ending today (today included).
    public func counts(lastDays count: Int, now: Date = Date(), calendar: Calendar = .current) -> Counts {
        var total = Counts()
        for key in dayKeys(lastDays: count, now: now, calendar: calendar) {
            if let c = days[key] { total.add(c) }
        }
        return total
    }

    public var allTime: Counts {
        var total = Counts()
        for c in days.values { total.add(c) }
        return total
    }

    /// Day keys for the last `count` days, oldest first.
    public func dayKeys(lastDays count: Int, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { Self.dayKey(for: $0, calendar: calendar) }
        }
    }

    /// Session counts if they belong to the block that started at `start`.
    public func session(startingAt start: Date) -> Counts {
        sessionStart == start ? session : Counts()
    }
}

/// Collapses bursts into single attempts. One page load opens several
/// connections and one app launch can spawn several processes; each burst
/// should count once.
public struct AttemptDebouncer {
    public let window: TimeInterval
    private var lastSeen: [String: Date] = [:]

    public init(window: TimeInterval) {
        self.window = window
    }

    /// True when `key` was last counted at least `window` before `date`.
    /// A clock that moved backwards starts a new burst.
    public mutating func shouldCount(_ key: String, at date: Date) -> Bool {
        if let last = lastSeen[key], date >= last, date.timeIntervalSince(last) < window {
            return false
        }
        lastSeen[key] = date
        return true
    }

    /// Marks `key` as seen without counting (e.g. apps already running when
    /// the block started).
    public mutating func suppress(_ key: String, at date: Date) {
        lastSeen[key] = date
    }
}

/// Matches a requested hostname to the blocked domain it belongs to.
public enum BlockedHostMatcher {
    /// The blocked entry covering `host` (exact or `www.` variant, the same
    /// coverage the hosts file gives), or nil.
    public static func match(host: String, blocked: [String]) -> String? {
        let h = normalize(host)
        guard !h.isEmpty else { return nil }
        for domain in blocked {
            let d = normalize(domain)
            let bare = d.hasPrefix("www.") ? String(d.dropFirst(4)) : d
            if h == bare || h == "www.\(bare)" { return domain }
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        var v = s.lowercased()
        while v.hasSuffix(".") { v.removeLast() }
        return v
    }
}
