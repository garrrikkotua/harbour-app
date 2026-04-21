import XCTest
@testable import HarbourCore

final class DomainValidationTests: XCTestCase {

    // MARK: isSafeDomain

    func test_isSafeDomain_acceptsTypicalDomains() {
        XCTAssertTrue(DomainValidation.isSafeDomain("twitter.com"))
        XCTAssertTrue(DomainValidation.isSafeDomain("x.com"))
        XCTAssertTrue(DomainValidation.isSafeDomain("mail.google.com"))
        XCTAssertTrue(DomainValidation.isSafeDomain("news.ycombinator.com"))
        XCTAssertTrue(DomainValidation.isSafeDomain("i.ytimg.com"))
    }

    func test_isSafeDomain_acceptsUppercaseViaLowercase() {
        XCTAssertTrue(DomainValidation.isSafeDomain("TWITTER.com"))
        XCTAssertTrue(DomainValidation.isSafeDomain("Twitter.Com"))
    }

    func test_isSafeDomain_acceptsHyphensAndDigits() {
        XCTAssertTrue(DomainValidation.isSafeDomain("cloudflare-dns.com"))
        XCTAssertTrue(DomainValidation.isSafeDomain("1.1.1.1"))
        XCTAssertTrue(DomainValidation.isSafeDomain("site123.example.com"))
    }

    func test_isSafeDomain_rejectsEmpty() {
        XCTAssertFalse(DomainValidation.isSafeDomain(""))
    }

    func test_isSafeDomain_rejectsWhitespace() {
        XCTAssertFalse(DomainValidation.isSafeDomain("has space.com"))
        XCTAssertFalse(DomainValidation.isSafeDomain(" leading.com"))
        XCTAssertFalse(DomainValidation.isSafeDomain("trailing.com "))
        XCTAssertFalse(DomainValidation.isSafeDomain("tab\tnews.com"))
    }

    func test_isSafeDomain_rejectsShellMetacharacters() {
        XCTAssertFalse(DomainValidation.isSafeDomain("example.com;rm -rf"))
        XCTAssertFalse(DomainValidation.isSafeDomain("example.com|cat"))
        XCTAssertFalse(DomainValidation.isSafeDomain("example.com`whoami`"))
        XCTAssertFalse(DomainValidation.isSafeDomain("example.com$(ls)"))
        XCTAssertFalse(DomainValidation.isSafeDomain("example.com/path"))
        XCTAssertFalse(DomainValidation.isSafeDomain("example.com?query"))
    }

    func test_isSafeDomain_rejectsProtocolPrefix() {
        // The GUI strips these before calling; validator refuses them raw.
        XCTAssertFalse(DomainValidation.isSafeDomain("https://example.com"))
        XCTAssertFalse(DomainValidation.isSafeDomain("http://example.com"))
    }

    func test_isSafeDomain_rejectsMarkerInjection() {
        // Must not allow a user input that would forge the hosts block boundary.
        XCTAssertFalse(DomainValidation.isSafeDomain(
            "good.com\n\(DomainValidation.hostsMarkerStart)"))
        XCTAssertFalse(DomainValidation.isSafeDomain(
            "\(DomainValidation.hostsMarkerEnd)\nevil"))
    }

    func test_isSafeDomain_rejectsOver253Chars() {
        let tooLong = String(repeating: "a", count: 254)
        XCTAssertFalse(DomainValidation.isSafeDomain(tooLong))
    }

    func test_isSafeDomain_accepts253Chars() {
        // RFC 1035 says total name ≤ 253 chars
        let at253 = String(repeating: "a", count: 253)
        XCTAssertTrue(DomainValidation.isSafeDomain(at253))
    }

    // MARK: isValidIP

    func test_isValidIP_acceptsIPv4() {
        XCTAssertTrue(DomainValidation.isValidIP("1.1.1.1"))
        XCTAssertTrue(DomainValidation.isValidIP("192.168.1.1"))
        XCTAssertTrue(DomainValidation.isValidIP("255.255.255.255"))
        XCTAssertTrue(DomainValidation.isValidIP("0.0.0.0"))
    }

    func test_isValidIP_rejectsIPv4OutOfRange() {
        XCTAssertFalse(DomainValidation.isValidIP("256.0.0.1"))
        XCTAssertFalse(DomainValidation.isValidIP("1.1.1.999"))
    }

    func test_isValidIP_rejectsIPv4Malformed() {
        XCTAssertFalse(DomainValidation.isValidIP("1.1.1"))
        XCTAssertFalse(DomainValidation.isValidIP("1.1.1."))
        XCTAssertFalse(DomainValidation.isValidIP("1.1.1.1.1"))
        XCTAssertFalse(DomainValidation.isValidIP("a.b.c.d"))
    }

    func test_isValidIP_acceptsIPv6() {
        XCTAssertTrue(DomainValidation.isValidIP("2606:4700:4700::1111"))
        XCTAssertTrue(DomainValidation.isValidIP("::1"))
        XCTAssertTrue(DomainValidation.isValidIP("fe80::1"))
        XCTAssertTrue(DomainValidation.isValidIP("2001:4860:4860::8888"))
    }

    func test_isValidIP_rejectsEmpty() {
        XCTAssertFalse(DomainValidation.isValidIP(""))
    }

    func test_isValidIP_rejectsWhitespace() {
        XCTAssertFalse(DomainValidation.isValidIP("1.1.1.1 "))
        XCTAssertFalse(DomainValidation.isValidIP(" 1.1.1.1"))
        XCTAssertFalse(DomainValidation.isValidIP("1.1.1.1\t"))
    }
}
