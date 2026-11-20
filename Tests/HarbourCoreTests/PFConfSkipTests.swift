import XCTest
@testable import HarbourCore

final class PFConfSkipTests: XCTestCase {
    func test_detectsLoopbackSkips() {
        XCTAssertTrue(NetworkSafety.pfConfSkipsLoopback("set skip on lo0\n"))
        XCTAssertTrue(NetworkSafety.pfConfSkipsLoopback("  set skip on { en0 lo0 }"))
        XCTAssertTrue(NetworkSafety.pfConfSkipsLoopback("set skip on lo # all loopback"))
    }

    func test_ignoresOtherInterfacesAndComments() {
        XCTAssertFalse(NetworkSafety.pfConfSkipsLoopback("set skip on en0 # local Wi-Fi, not lo0"))
        XCTAssertFalse(NetworkSafety.pfConfSkipsLoopback("# set skip on lo0"))
        XCTAssertFalse(NetworkSafety.pfConfSkipsLoopback("set skip on lookback0"))
        XCTAssertFalse(NetworkSafety.pfConfSkipsLoopback("anchor \"com.apple/*\"\nload anchor \"com.apple\" from \"/etc/pf.anchors/com.apple\""))
    }
}
