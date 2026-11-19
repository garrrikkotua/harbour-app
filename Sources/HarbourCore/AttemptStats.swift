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
    /// Local Gregorian day ("yyyy-MM-dd") → counts.
    public var days: [String: Counts]
    /// Start time of the block `session` belongs to: the same `startTime`
    /// value as state.json, stored losslessly (see `encoder`).
    public var sessionStart: Date?
    public var session: Counts
    /// Every attempt ever counted. Unlike `days` it is never pruned, so the
    /// all-time total doesn't shrink as old days expire.
    public var lifetimeTotal: Int

    public init(days: [String: Counts] = [:], sessionStart: Date? = nil, session: Counts = Counts(),
                lifetimeTotal: Int? = nil) {
        self.version = 1
        self.days = days
        self.sessionStart = sessionStart
        self.session = session
        self.lifetimeTotal = lifetimeTotal ?? days.values.reduce(0) { $0 + $1.total }
    }

    private enum CodingKeys: String, CodingKey {
        case version, days, sessionStart, session, lifetimeTotal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        days = try c.decodeIfPresent([String: Counts].self, forKey: .days) ?? [:]
        sessionStart = try c.decodeIfPresent(Date.self, forKey: .sessionStart)
        session = try c.decodeIfPresent(Counts.self, forKey: .session) ?? Counts()
        let retained = days.values.reduce(0) { $0 + $1.total }
        lifetimeTotal = max(try c.decodeIfPresent(Int.self, forKey: .lifetimeTotal) ?? 0, retained)
    }

    /// Day keys are always Gregorian in the local time zone, for the root
    /// daemon and the app alike: a user's non-Gregorian calendar setting must
    /// not make the two compute different keys for the same day.
    public static var storageCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Dates are written as seconds since 2001 (Foundation's own encoding,
    /// the same as state.json), so `sessionStart` survives the round trip
    /// with its fractional seconds. ISO 8601 strings from earlier builds
    /// still decode.
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .deferredToDate
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let seconds = try? c.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let text = try c.decode(String.self)
            guard let date = ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognized date \(text)")
            }
            return date
        }
        return d
    }()

    /// Days older than this are dropped so the root-written file stays small.
    public static let retentionDays = 400
    /// Caps per-day keys; a misbehaving client can't grow the file without bound.
    public static let maxKeysPerDay = 500

    public static func dayKey(for date: Date, calendar: Calendar = storageCalendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Records one attempt. `sessionStart` identifies the running block; a new
    /// value resets the per-session counts.
    public mutating func record(_ kind: Kind, key: String, at date: Date,
                                sessionStart start: Date, calendar: Calendar = storageCalendar) {
        beginSession(start)
        let day = Self.dayKey(for: date, calendar: calendar)
        var counts = days[day] ?? Counts()
        switch kind {
        case .site:
            guard counts.sites[key] != nil || counts.sites.count < Self.maxKeysPerDay else { return }
            counts.sites[key, default: 0] += 1
            session.sites[key, default: 0] += 1
            lifetimeTotal += 1
        case .app:
            guard counts.apps[key] != nil || counts.apps.count < Self.maxKeysPerDay else { return }
            counts.apps[key, default: 0] += 1
            session.apps[key, default: 0] += 1
            lifetimeTotal += 1
        }
        days[day] = counts
    }

    /// Resets the session counts when a different block starts, without
    /// recording anything.
    public mutating func beginSession(_ start: Date) {
        if let current = sessionStart, Self.sameSession(current, start) { return }
        sessionStart = start
        session = Counts()
    }

    public mutating func prune(now: Date, calendar: Calendar = storageCalendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: now) else { return }
        let cutoffKey = Self.dayKey(for: cutoff, calendar: calendar)
        // Keys are zero-padded ISO dates, so string order is date order.
        days = days.filter { $0.key >= cutoffKey }
    }

    /// Drops the oldest days until the encoded file is at most `maxBytes`,
    /// so the daemon can always read back what it wrote. The newest day is
    /// always kept (its key caps bound it far below the limit).
    public mutating func compact(toFit maxBytes: Int, encoder: JSONEncoder = AttemptStats.encoder) {
        while days.count > 1, let size = try? encoder.encode(self).count, size > maxBytes {
            let sorted = days.keys.sorted()
            // Drop roughly a tenth at a time instead of re-encoding per day.
            for key in sorted.prefix(max(1, sorted.count / 10)) { days[key] = nil }
        }
    }

    /// Sum of the last `count` days ending today (today included).
    public func counts(lastDays count: Int, now: Date = Date(), calendar: Calendar = storageCalendar) -> Counts {
        var total = Counts()
        for key in dayKeys(lastDays: count, now: now, calendar: calendar) {
            if let c = days[key] { total.add(c) }
        }
        return total
    }

    /// Per-target counts over every retained day (up to `retentionDays`).
    public var retained: Counts {
        var total = Counts()
        for c in days.values { total.add(c) }
        return total
    }

    /// Day keys for the last `count` days, oldest first.
    public func dayKeys(lastDays count: Int, now: Date = Date(), calendar: Calendar = storageCalendar) -> [String] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { Self.dayKey(for: $0, calendar: calendar) }
        }
    }

    /// Session counts if they belong to the block that started at `start`.
    public func session(startingAt start: Date) -> Counts {
        guard let current = sessionStart, Self.sameSession(current, start) else { return Counts() }
        return session
    }

    /// Start times are compared with a millisecond tolerance, so a value that
    /// went through a lossy encoding elsewhere still identifies its block.
    static func sameSession(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 0.001
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
    /// Hostname → blocked entry for every name a visit can use: the entry's
    /// bare and `www.` forms, its mobile sites and its sibling sites
    /// (`RelatedDomains.siteHostnames`). Asset hosts such as `pbs.twimg.com`
    /// are left out, so a cached page fetching images never counts. A name an
    /// entry covers directly wins over one it only reaches through expansion.
    public static func lookup(blocked: [String]) -> [String: String] {
        var direct: [String: String] = [:]
        var expanded: [String: String] = [:]
        for domain in blocked {
            let d = normalize(domain)
            let bare = d.hasPrefix("www.") ? String(d.dropFirst(4)) : d
            for name in [bare, "www.\(bare)"] where direct[name] == nil { direct[name] = domain }
            for name in RelatedDomains.siteHostnames(for: [domain]) where expanded[name] == nil {
                expanded[name] = domain
            }
        }
        return direct.merging(expanded) { first, _ in first }
    }

    /// The blocked entry covering `host`, or nil.
    public static func match(host: String, in lookup: [String: String]) -> String? {
        let h = normalize(host)
        return h.isEmpty ? nil : lookup[h]
    }

    public static func match(host: String, blocked: [String]) -> String? {
        match(host: host, in: lookup(blocked: blocked))
    }

    private static func normalize(_ s: String) -> String {
        var v = s.lowercased()
        while v.hasSuffix(".") { v.removeLast() }
        return v
    }
}
