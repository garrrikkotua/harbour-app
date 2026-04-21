import XCTest
@testable import HarbourCore

final class SafetyTests: XCTestCase {

    // MARK: isCriticalApp

    func test_criticalApps_areRejected() {
        XCTAssertTrue(Safety.isCriticalApp(path: "/Applications/Utilities/Terminal.app"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Applications/Utilities/Terminal.app"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Applications/Utilities/Activity Monitor.app"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Applications/System Settings.app"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Applications/Utilities/Disk Utility.app"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Applications/Utilities/Keychain Access.app"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/Applications/Harbour.app"))
    }

    func test_systemLibraryPaths_areRejected() {
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Library/CoreServices/Finder.app"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Library/CoreServices/Dock.app"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Library/PrivateFrameworks/anything"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/System/Library/LaunchDaemons/com.apple.foo"))
        XCTAssertTrue(Safety.isCriticalApp(path: "/usr/libexec/foo"))
    }

    func test_userApps_arePermitted() {
        XCTAssertFalse(Safety.isCriticalApp(path: "/Applications/Telegram.app"))
        XCTAssertFalse(Safety.isCriticalApp(path: "/Applications/Safari.app"))
        XCTAssertFalse(Safety.isCriticalApp(path: "/Applications/Slack.app"))
        XCTAssertFalse(Safety.isCriticalApp(path: "/Users/me/Applications/MyApp.app"))
    }

    // MARK: riskyEntries

    func test_riskyEntries_flagsAppleDomains() {
        let entered = ["twitter.com", "apple.com", "example.com"]
        let risky = Safety.riskyEntries(from: entered)
        XCTAssertEqual(risky, ["apple.com"])
    }

    func test_riskyEntries_matchesAppleSubdomains() {
        let entered = ["mail.apple.com", "id.icloud.com", "push.apple.com"]
        let risky = Safety.riskyEntries(from: entered)
        XCTAssertTrue(risky.contains("mail.apple.com"))
        XCTAssertTrue(risky.contains("id.icloud.com"))
        XCTAssertTrue(risky.contains("push.apple.com"))
    }

    func test_riskyEntries_doesNotMatchLookalikes() {
        let entered = ["notapple.com", "fakeapple.com", "example.com"]
        let risky = Safety.riskyEntries(from: entered)
        XCTAssertTrue(risky.isEmpty)
    }

    func test_riskyEntries_caseInsensitive() {
        let entered = ["APPLE.COM", "iCloud.com"]
        let risky = Safety.riskyEntries(from: entered)
        XCTAssertEqual(risky.count, 2)
    }

    func test_riskyEntries_emptyListReturnsEmpty() {
        XCTAssertTrue(Safety.riskyEntries(from: []).isEmpty)
    }
}
