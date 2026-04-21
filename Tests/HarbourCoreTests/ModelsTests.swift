import XCTest
@testable import HarbourCore

final class ModelsTests: XCTestCase {

    // MARK: BlockedApp

    func test_blockedApp_roundTrip() throws {
        let original = BlockedApp(
            name: "Telegram",
            path: "/Applications/Telegram.app",
            bundleID: "com.tdesktop.Telegram"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlockedApp.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_blockedApp_idIsPath() {
        let app = BlockedApp(name: "X", path: "/p", bundleID: "com.x")
        XCTAssertEqual(app.id, "/p")
    }

    func test_blockedApp_hashableByPath() {
        let a = BlockedApp(name: "X", path: "/p", bundleID: "com.x")
        let b = BlockedApp(name: "Y", path: "/p", bundleID: "com.y")
        // Two instances with different metadata but the same path should
        // still hash the same (path is the identity).
        XCTAssertEqual(a, b)
    }

    // MARK: BlockConfig

    func test_blockConfig_defaults() {
        let c = BlockConfig()
        XCTAssertTrue(c.domains.isEmpty)
        XCTAssertTrue(c.apps.isEmpty)
        XCTAssertEqual(c.durationMinutes, 60)
    }

    func test_blockConfig_roundTrip() throws {
        let original = BlockConfig(
            domains: ["twitter.com", "x.com"],
            apps: [BlockedApp(name: "App", path: "/a", bundleID: "com.a")],
            durationMinutes: 120
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlockConfig.self, from: data)
        XCTAssertEqual(decoded.domains, original.domains)
        XCTAssertEqual(decoded.apps, original.apps)
        XCTAssertEqual(decoded.durationMinutes, original.durationMinutes)
    }

    // MARK: BlockState

    func test_blockState_roundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3_600)
        let original = BlockState(
            startTime: start,
            endTime: end,
            domains: ["a.com"],
            blockedPaths: ["/Applications/X.app"],
            blockedBundleIDs: ["com.x"],
            additionsPath: "/Users/me/additions.json"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlockState.self, from: data)
        XCTAssertEqual(decoded.startTime, original.startTime)
        XCTAssertEqual(decoded.endTime, original.endTime)
        XCTAssertEqual(decoded.domains, original.domains)
        XCTAssertEqual(decoded.blockedPaths, original.blockedPaths)
        XCTAssertEqual(decoded.blockedBundleIDs, original.blockedBundleIDs)
        XCTAssertEqual(decoded.additionsPath, original.additionsPath)
    }

    func test_blockState_additionsPathOptional() throws {
        // Older state files without additionsPath should still decode.
        let json = #"""
        {
          "startTime": 0,
          "endTime": 60,
          "domains": [],
          "blockedPaths": [],
          "blockedBundleIDs": []
        }
        """#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BlockState.self, from: data)
        XCTAssertNil(decoded.additionsPath)
    }

    // MARK: BlockAdditions

    func test_blockAdditions_defaults() {
        let a = BlockAdditions()
        XCTAssertTrue(a.domains.isEmpty)
        XCTAssertTrue(a.apps.isEmpty)
    }

    func test_blockAdditions_roundTrip() throws {
        let original = BlockAdditions(
            domains: ["late.com"],
            apps: [BlockedApp(name: "Extra", path: "/e", bundleID: "com.e")]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BlockAdditions.self, from: data)
        XCTAssertEqual(decoded.domains, original.domains)
        XCTAssertEqual(decoded.apps.first?.path, "/e")
    }
}
