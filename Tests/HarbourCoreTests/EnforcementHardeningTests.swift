import XCTest
import Darwin
@testable import HarbourCore

final class NetworkSafetyTests: XCTestCase {

    func test_publicAddresses_areBlockable() {
        for ip in ["142.250.74.46", "157.240.0.35", "104.16.132.229", "2a03:2880:f10c:83:face:b00c:0:25de", "2606:4700::6810:84e5"] {
            XCTAssertTrue(NetworkSafety.isBlockableResolvedIP(ip), ip)
        }
    }

    func test_localAndSpecialAddresses_areNeverBlanketBlocked() {
        // Loopback / sinkhole answers, LAN gateways and DNS servers, link-local,
        // CGNAT, multicast and broadcast — blocking any of these cuts local
        // networking or DNS for the whole session.
        for ip in ["0.0.0.0", "127.0.0.1", "127.8.9.1", "10.0.0.1", "172.16.0.1", "172.31.255.254",
                   "192.168.1.1", "169.254.1.1", "100.64.0.1", "100.127.255.1", "224.0.0.251",
                   "239.255.255.250", "255.255.255.255", "::", "::1", "fe80::1", "fd00::1",
                   "fc00::1", "ff02::fb", "::ffff:127.0.0.1", "::ffff:192.168.0.1"] {
            XCTAssertFalse(NetworkSafety.isBlockableResolvedIP(ip), ip)
        }
    }

    func test_boundariesOfPrivateRanges_stayBlockable() {
        for ip in ["172.15.255.255", "172.32.0.1", "100.63.255.255", "100.128.0.1", "11.0.0.1", "::ffff:8.8.4.4"] {
            XCTAssertTrue(NetworkSafety.isBlockableResolvedIP(ip), ip)
        }
    }

    func test_garbage_isRejected() {
        for s in ["", "example.com", "1.2.3", "1.2.3.4/32", "1.2.3.4 "] {
            XCTAssertFalse(NetworkSafety.isBlockableResolvedIP(s), s)
        }
    }

    func test_blockableIPs_keepsResolverPortsReachable() {
        // Blocking the whole resolver address would kill ordinary DNS on
        // Macs configured to use 1.1.1.1 / 8.8.8.8.
        let result = NetworkSafety.blockableIPs(
            from: ["1.1.1.1", "157.240.0.35", "127.0.0.1"],
            keepReachable: ["1.1.1.1", "8.8.8.8"]
        )
        XCTAssertEqual(result, ["157.240.0.35"])
    }

    func test_blockableIPs_skipsSharedHosting() {
        // Vercel (revenuecat.com and app.octolens.com share 216.150.1.x),
        // Cloudflare, Fastly and CloudFront serve unrelated sites from one IP.
        let result = NetworkSafety.blockableIPs(
            from: ["216.150.1.1", "76.76.21.21", "104.16.132.229", "151.101.1.140",
                   "2606:4700::6810:84e5", "142.250.74.46"],
            keepReachable: []
        )
        XCTAssertEqual(result, ["142.250.74.46"])
    }
}

final class SharedHostingTests: XCTestCase {

    func test_prefixBoundaries() {
        XCTAssertTrue(SharedHosting.contains("104.16.0.0"))      // Cloudflare 104.16.0.0/13
        XCTAssertTrue(SharedHosting.contains("104.23.255.255"))
        XCTAssertFalse(SharedHosting.contains("104.15.255.255"))
        XCTAssertTrue(SharedHosting.contains("216.150.1.65"))    // Vercel 216.150.1.0/24
        XCTAssertFalse(SharedHosting.contains("216.150.2.1"))
        XCTAssertTrue(SharedHosting.contains("2606:4700::1"))    // Cloudflare IPv6
    }

    func test_ownNetworks_andGarbage_areNotShared() {
        // Google, Meta and X run their own networks; blocking them only
        // affects their own services, which the confirm sheet warns about.
        for ip in ["157.240.0.35", "142.250.74.46", "104.244.42.1", "192.168.1.1", "", "not-an-ip"] {
            XCTAssertFalse(SharedHosting.contains(ip), ip)
        }
    }
}

final class SecureFileReadTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("harbour-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func test_readsRegularFile() throws {
        let file = dir.appendingPathComponent("additions.json")
        try Data("{\"domains\":[],\"apps\":[]}".utf8).write(to: file)
        let data = SecureFileRead.regularFile(atPath: file.path, maxBytes: 1024)
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, "{\"domains\":[],\"apps\":[]}")
    }

    func test_readsEmptyFile() throws {
        let file = dir.appendingPathComponent("empty.json")
        try Data().write(to: file)
        XCTAssertEqual(SecureFileRead.regularFile(atPath: file.path, maxBytes: 1024), Data())
    }

    func test_rejectsSymlink() throws {
        let target = dir.appendingPathComponent("real.json")
        try Data("{}".utf8).write(to: target)
        let link = dir.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertNil(SecureFileRead.regularFile(atPath: link.path, maxBytes: 1024))
    }

    func test_rejectsSymlinkToDevice() throws {
        // /dev/zero would otherwise be read forever by the root daemon.
        let link = dir.appendingPathComponent("zero.json")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/dev/zero")
        XCTAssertNil(SecureFileRead.regularFile(atPath: link.path, maxBytes: 1024))
    }

    func test_rejectsFIFOWithoutBlocking() throws {
        // A FIFO with no writer used to block the daemon's main loop forever,
        // so the timer never expired. Must return immediately.
        let fifo = dir.appendingPathComponent("fifo.json")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let started = Date()
        XCTAssertNil(SecureFileRead.regularFile(atPath: fifo.path, maxBytes: 1024))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func test_rejectsOversizedFile() throws {
        let file = dir.appendingPathComponent("big.json")
        try Data(repeating: 0x20, count: 2048).write(to: file)
        XCTAssertNil(SecureFileRead.regularFile(atPath: file.path, maxBytes: 1024))
        XCTAssertNotNil(SecureFileRead.regularFile(atPath: file.path, maxBytes: 2048))
    }

    func test_rejectsDirectoryAndMissingFile() {
        XCTAssertNil(SecureFileRead.regularFile(atPath: dir.path, maxBytes: 1024))
        XCTAssertNil(SecureFileRead.regularFile(atPath: dir.appendingPathComponent("missing").path, maxBytes: 1024))
    }
}

final class AppTargetResolutionTests: XCTestCase {

    func test_symlinkedBundle_isAlsoMatchedAtItsResolvedPath() {
        // /Applications/Safari.app is a symlink into the Safari cryptex since
        // macOS 13; the kernel reports the resolved executable path.
        let resolved = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        let targets = Safety.enforcementTargets(bundlePath: "/Applications/Safari.app", resolvedPath: resolved)
        XCTAssertEqual(targets, ["/Applications/Safari.app", resolved])
        XCTAssertTrue(targets.contains {
            Safety.matchesApp(executable: resolved + "/Contents/MacOS/Safari", bundlePath: $0)
        })
    }

    func test_plainBundle_hasSingleTarget() {
        XCTAssertEqual(
            Safety.enforcementTargets(bundlePath: "/Applications/Slack.app", resolvedPath: "/Applications/Slack.app"),
            ["/Applications/Slack.app"])
        XCTAssertEqual(
            Safety.enforcementTargets(bundlePath: "/Applications/Slack.app", resolvedPath: nil),
            ["/Applications/Slack.app"])
    }

    func test_symlinkToCriticalApp_isNotFollowed() {
        for critical in ["/System/Applications/Utilities/Terminal.app",
                         "/System/Applications/Utilities/Activity Monitor.app",
                         "/System/Library/CoreServices/Finder.app",
                         "/Applications/Harbour Control.app",
                         "/"] {
            XCTAssertEqual(
                Safety.enforcementTargets(bundlePath: "/Users/me/Innocent.app", resolvedPath: critical),
                ["/Users/me/Innocent.app"], critical)
        }
    }

    func test_invalidBundle_hasNoTargets() {
        XCTAssertEqual(Safety.enforcementTargets(bundlePath: "/Applications", resolvedPath: nil), [])
        XCTAssertEqual(Safety.enforcementTargets(
            bundlePath: "/System/Applications/Utilities/Terminal.app", resolvedPath: nil), [])
    }

    func test_logicalSystemPath_stripsCryptexPrefix() {
        XCTAssertEqual(
            Safety.logicalSystemPath("/System/Volumes/Preboot/Cryptexes/OS/System/Library/CoreServices/Foo.app"),
            "/System/Library/CoreServices/Foo.app")
        XCTAssertEqual(
            Safety.logicalSystemPath("/System/Cryptexes/App/System/Applications/Safari.app"),
            "/System/Applications/Safari.app")
        XCTAssertEqual(Safety.logicalSystemPath("/Applications/Slack.app"), "/Applications/Slack.app")
    }

    func test_criticalApps_areRecognisedInsideCryptexes() {
        XCTAssertTrue(Safety.isCriticalApp(
            path: "/System/Volumes/Preboot/Cryptexes/OS/System/Library/CoreServices/Foo.app"))
        XCTAssertFalse(Safety.isCriticalApp(
            path: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"))
    }

    func test_rootOwnedProcesses_areNeverTerminated() {
        XCTAssertFalse(Safety.mayTerminate(processOwnerUID: 0))
        XCTAssertTrue(Safety.mayTerminate(processOwnerUID: 501))
        XCTAssertTrue(Safety.mayTerminate(processOwnerUID: 201))  // Guest
    }
}
