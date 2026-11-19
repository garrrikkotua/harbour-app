import XCTest
@testable import HarbourCore

final class AttemptStatsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Belgrade")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func test_record_countsPerDayAndSession() {
        var stats = AttemptStats()
        let start = date("2026-11-19T08:00:00Z")
        stats.record(.site, key: "x.com", at: date("2026-11-19T09:00:00Z"), sessionStart: start, calendar: calendar)
        stats.record(.site, key: "x.com", at: date("2026-11-19T09:05:00Z"), sessionStart: start, calendar: calendar)
        stats.record(.app, key: "/Applications/Slack.app", at: date("2026-11-19T09:06:00Z"), sessionStart: start, calendar: calendar)

        XCTAssertEqual(stats.days["2026-11-19"]?.sites["x.com"], 2)
        XCTAssertEqual(stats.days["2026-11-19"]?.apps["/Applications/Slack.app"], 1)
        XCTAssertEqual(stats.session(startingAt: start).total, 3)
        XCTAssertEqual(stats.allTime.total, 3)
    }

    func test_record_newSessionResetsSessionButKeepsHistory() {
        var stats = AttemptStats()
        let first = date("2026-11-18T08:00:00Z")
        let second = date("2026-11-19T08:00:00Z")
        stats.record(.site, key: "x.com", at: date("2026-11-18T09:00:00Z"), sessionStart: first, calendar: calendar)
        stats.record(.site, key: "x.com", at: date("2026-11-19T09:00:00Z"), sessionStart: second, calendar: calendar)

        XCTAssertEqual(stats.session(startingAt: second).total, 1)
        XCTAssertEqual(stats.session(startingAt: first).total, 0)
        XCTAssertEqual(stats.allTime.sites["x.com"], 2)
    }

    func test_dayKey_usesLocalCalendar() {
        // 23:30 UTC is already the next day in Belgrade.
        XCTAssertEqual(AttemptStats.dayKey(for: date("2026-11-19T23:30:00Z"), calendar: calendar), "2026-11-20")
    }

    func test_countsLastDays_includesTodayOnly() {
        var stats = AttemptStats()
        let start = date("2026-11-01T08:00:00Z")
        stats.record(.site, key: "a.com", at: date("2026-11-10T09:00:00Z"), sessionStart: start, calendar: calendar)
        stats.record(.site, key: "a.com", at: date("2026-11-17T09:00:00Z"), sessionStart: start, calendar: calendar)
        stats.record(.site, key: "a.com", at: date("2026-11-19T09:00:00Z"), sessionStart: start, calendar: calendar)
        let now = date("2026-11-19T12:00:00Z")

        XCTAssertEqual(stats.counts(lastDays: 1, now: now, calendar: calendar).total, 1)
        XCTAssertEqual(stats.counts(lastDays: 7, now: now, calendar: calendar).total, 2)
        XCTAssertEqual(stats.dayKeys(lastDays: 3, now: now, calendar: calendar),
                       ["2026-11-17", "2026-11-18", "2026-11-19"])
    }

    func test_prune_dropsOldDays() {
        var stats = AttemptStats(days: [
            "2024-01-01": .init(sites: ["a.com": 1]),
            "2026-11-01": .init(sites: ["a.com": 1]),
        ])
        stats.prune(now: date("2026-11-19T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(Array(stats.days.keys), ["2026-11-01"])
    }

    func test_record_capsKeysPerDay() {
        var stats = AttemptStats()
        let start = date("2026-11-19T08:00:00Z")
        let at = date("2026-11-19T09:00:00Z")
        for i in 0..<(AttemptStats.maxKeysPerDay + 10) {
            stats.record(.site, key: "s\(i).com", at: at, sessionStart: start, calendar: calendar)
        }
        XCTAssertEqual(stats.days["2026-11-19"]?.sites.count, AttemptStats.maxKeysPerDay)
    }

    func test_codableRoundTrip() throws {
        var stats = AttemptStats()
        stats.record(.app, key: "/Applications/Slack.app", at: Date(), sessionStart: Date(timeIntervalSince1970: 1000))
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try d.decode(AttemptStats.self, from: e.encode(stats)), stats)
    }

    // MARK: Debouncer

    func test_debouncer_collapsesBursts() {
        var d = AttemptDebouncer(window: 10)
        let t = date("2026-11-19T09:00:00Z")
        XCTAssertTrue(d.shouldCount("x.com", at: t))
        XCTAssertFalse(d.shouldCount("x.com", at: t.addingTimeInterval(3)))
        XCTAssertTrue(d.shouldCount("y.com", at: t.addingTimeInterval(3)))
        XCTAssertTrue(d.shouldCount("x.com", at: t.addingTimeInterval(10)))
    }

    func test_debouncer_suppressSkipsWindow() {
        var d = AttemptDebouncer(window: 5)
        let t = date("2026-11-19T09:00:00Z")
        d.suppress("/Applications/Slack.app", at: t)
        XCTAssertFalse(d.shouldCount("/Applications/Slack.app", at: t.addingTimeInterval(1)))
        XCTAssertTrue(d.shouldCount("/Applications/Slack.app", at: t.addingTimeInterval(6)))
    }

    func test_debouncer_clockGoingBackwardsCounts() {
        var d = AttemptDebouncer(window: 10)
        let t = date("2026-11-19T09:00:00Z")
        XCTAssertTrue(d.shouldCount("x.com", at: t))
        XCTAssertTrue(d.shouldCount("x.com", at: t.addingTimeInterval(-60)))
    }

    // MARK: Host matching

    func test_matcher_coversBareAndWWW() {
        let blocked = ["youtube.com", "www.reddit.com"]
        XCTAssertEqual(BlockedHostMatcher.match(host: "www.youtube.com", blocked: blocked), "youtube.com")
        XCTAssertEqual(BlockedHostMatcher.match(host: "YOUTUBE.com.", blocked: blocked), "youtube.com")
        XCTAssertEqual(BlockedHostMatcher.match(host: "reddit.com", blocked: blocked), "www.reddit.com")
        XCTAssertNil(BlockedHostMatcher.match(host: "m.youtube.com", blocked: blocked))
        XCTAssertNil(BlockedHostMatcher.match(host: "notyoutube.com", blocked: blocked))
        XCTAssertNil(BlockedHostMatcher.match(host: "dns.google", blocked: blocked))
    }
}

final class RequestHostParserTests: XCTestCase {
    /// A real ClientHello generated by Python's ssl module for www.YouTube.com.
    private let clientHello: [UInt8] = {
        let hex = "16030100c7010000c30303ab4f5d326158641c5c014309740395d96e91c94e920706c0ba29c1dad12143cf00004ccca9cca8ccaac030c02cc028c024c014c00a009f006b0039ff8500c400880081009d003d003500c00084c02fc02bc027c023c013c009009e0067003300be0045009c003c002f00ba004100ff0100004e00000014001200000f7777772e596f75547562652e636f6d000b00020100000a00080006001d0017001800230000000d001c001a06010603efef0501050304010403eeeeeded0301030302010203"
        var bytes: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            bytes.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return bytes
    }()

    func test_tls_extractsSNI() {
        XCTAssertEqual(RequestHostParser.parse(clientHello), .host("www.youtube.com"))
    }

    func test_tls_partialRecordNeedsMore() {
        XCTAssertEqual(RequestHostParser.parse(Array(clientHello.prefix(3))), .needMore)
        XCTAssertEqual(RequestHostParser.parse(Array(clientHello.prefix(100))), .needMore)
    }

    func test_tls_truncatedLengthsAreRejectedNotCrashed() {
        // Corrupt every length byte in turn; parsing must never trap.
        for i in 5..<clientHello.count {
            var mutated = clientHello
            mutated[i] = 0xFF
            _ = RequestHostParser.parse(mutated)
        }
        var noSNI = clientHello
        noSNI[0] = 0x16
        noSNI[5] = 0x02  // ServerHello, not ClientHello
        XCTAssertEqual(RequestHostParser.parse(noSNI), .unrecognized)
    }

    func test_http_extractsHostWithoutPort() {
        let req = Array("GET / HTTP/1.1\r\nUser-Agent: x\r\nHost: Reddit.com:80\r\n\r\n".utf8)
        XCTAssertEqual(RequestHostParser.parse(req), .host("reddit.com"))
    }

    func test_http_incompleteHeadersNeedMore() {
        XCTAssertEqual(RequestHostParser.parse(Array("GET / HTTP/1.1\r\nHost: a.com".utf8)), .needMore)
    }

    func test_http_rejectsInvalidHost() {
        let req = Array("GET / HTTP/1.1\r\nHost: a b/../c\r\n\r\n".utf8)
        XCTAssertEqual(RequestHostParser.parse(req), .unrecognized)
    }

    func test_garbageIsUnrecognized() {
        XCTAssertEqual(RequestHostParser.parse([0x00, 0x01, 0x02]), .unrecognized)
        XCTAssertEqual(RequestHostParser.parse([]), .needMore)
    }
}
