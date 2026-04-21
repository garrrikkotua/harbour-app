import XCTest
@testable import HarbourCore

final class HostsMarkerTests: XCTestCase {
    let start = "# HARBOUR_BLOCK_START"
    let end = "# HARBOUR_BLOCK_END"

    // MARK: removeBlockSection

    func test_removeBlockSection_noMarkersLeavesContentUnchanged() {
        let original = """
        127.0.0.1 localhost
        ::1 localhost
        """
        let cleaned = HostsMarker.removeBlockSection(from: original, start: start, end: end)
        XCTAssertTrue(cleaned.contains("127.0.0.1 localhost"))
        XCTAssertTrue(cleaned.contains("::1 localhost"))
    }

    func test_removeBlockSection_stripsCompletePairedBlock() {
        let input = """
        127.0.0.1 localhost

        \(start)
        0.0.0.0\ttwitter.com
        0.0.0.0\twww.twitter.com
        \(end)

        255.255.255.255 broadcasthost
        """
        let cleaned = HostsMarker.removeBlockSection(from: input, start: start, end: end)
        XCTAssertFalse(cleaned.contains("twitter.com"))
        XCTAssertFalse(cleaned.contains(start))
        XCTAssertFalse(cleaned.contains(end))
        XCTAssertTrue(cleaned.contains("127.0.0.1 localhost"))
        XCTAssertTrue(cleaned.contains("broadcasthost"))
    }

    func test_removeBlockSection_refusesWhenStartLacksEnd() {
        // If a previous cleanup crashed and left an orphan START, the stripper
        // must refuse to edit rather than truncating the file to EOF.
        let input = """
        127.0.0.1 localhost
        \(start)
        0.0.0.0\ttwitter.com
        (no end marker!)
        important-user-entry
        """
        let cleaned = HostsMarker.removeBlockSection(from: input, start: start, end: end)
        // Returns unchanged — we must not eat user content past the dangling START.
        XCTAssertEqual(cleaned, input)
        XCTAssertTrue(cleaned.contains("important-user-entry"))
    }

    func test_removeBlockSection_handlesMultiplePairedBlocks() {
        let input = """
        preamble
        \(start)
        block one
        \(end)
        middle
        \(start)
        block two
        \(end)
        end
        """
        let cleaned = HostsMarker.removeBlockSection(from: input, start: start, end: end)
        XCTAssertTrue(cleaned.contains("preamble"))
        XCTAssertTrue(cleaned.contains("middle"))
        XCTAssertTrue(cleaned.contains("end"))
        XCTAssertFalse(cleaned.contains("block one"))
        XCTAssertFalse(cleaned.contains("block two"))
    }

    func test_removeBlockSection_emptyInput() {
        XCTAssertEqual(
            HostsMarker.removeBlockSection(from: "", start: start, end: end),
            "\n"
        )
    }

    func test_removeBlockSection_trailingNewlineNormalized() {
        let cleaned = HostsMarker.removeBlockSection(
            from: "127.0.0.1 localhost",
            start: start, end: end
        )
        XCTAssertTrue(cleaned.hasSuffix("\n"))
    }

    // MARK: buildHostsBlock

    func test_buildHostsBlock_usesNullRouteSinks() {
        let out = HostsMarker.buildHostsBlock(
            domains: ["twitter.com"], start: start, end: end
        )
        // Must use 0.0.0.0 / :: (not 127.0.0.1 / ::1) — browsers otherwise fall
        // back to DoH.
        XCTAssertTrue(out.contains("0.0.0.0\ttwitter.com"))
        XCTAssertTrue(out.contains("::\ttwitter.com"))
        XCTAssertFalse(out.contains("127.0.0.1"))
        XCTAssertFalse(out.contains("::1"))
    }

    func test_buildHostsBlock_emitsWwwVariant() {
        let out = HostsMarker.buildHostsBlock(
            domains: ["example.com"], start: start, end: end
        )
        XCTAssertTrue(out.contains("0.0.0.0\texample.com"))
        XCTAssertTrue(out.contains("0.0.0.0\twww.example.com"))
    }

    func test_buildHostsBlock_stripsAnyWwwPrefix() {
        // If user entered "www.foo.com" we should block both "foo.com" AND
        // "www.foo.com" — same as if they'd entered bare "foo.com".
        let out = HostsMarker.buildHostsBlock(
            domains: ["www.foo.com"], start: start, end: end
        )
        XCTAssertTrue(out.contains("0.0.0.0\tfoo.com"))
        XCTAssertTrue(out.contains("0.0.0.0\twww.foo.com"))
    }

    func test_buildHostsBlock_skipsInvalidEntries() {
        let out = HostsMarker.buildHostsBlock(
            domains: ["good.com", "has spaces.com", "https://nope.com", "clean.com"],
            start: start, end: end
        )
        XCTAssertTrue(out.contains("good.com"))
        XCTAssertTrue(out.contains("clean.com"))
        XCTAssertFalse(out.contains("has spaces"))
        XCTAssertFalse(out.contains("https:"))
    }

    func test_buildHostsBlock_wrapsInMarkers() {
        let out = HostsMarker.buildHostsBlock(
            domains: ["foo.com"], start: start, end: end
        )
        XCTAssertTrue(out.contains(start))
        XCTAssertTrue(out.contains(end))
        // Start marker must appear before end marker in the output.
        let startIdx = out.range(of: start)!.lowerBound
        let endIdx = out.range(of: end)!.lowerBound
        XCTAssertLessThan(startIdx, endIdx)
    }

    // MARK: round-trip

    func test_roundTrip_buildThenRemoveLeavesOriginalIntact() {
        let original = """
        ##
        # Host Database
        ##
        127.0.0.1\tlocalhost
        255.255.255.255\tbroadcasthost
        ::1\tlocalhost
        """
        let addition = HostsMarker.buildHostsBlock(
            domains: ["twitter.com", "x.com"], start: start, end: end
        )
        let withBlock = original + addition
        let cleaned = HostsMarker.removeBlockSection(
            from: withBlock, start: start, end: end
        )
        XCTAssertTrue(cleaned.contains("127.0.0.1\tlocalhost"))
        XCTAssertTrue(cleaned.contains("255.255.255.255\tbroadcasthost"))
        XCTAssertFalse(cleaned.contains("twitter.com"))
        XCTAssertFalse(cleaned.contains("x.com"))
    }
}
