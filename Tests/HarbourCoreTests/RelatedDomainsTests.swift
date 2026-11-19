import XCTest
@testable import HarbourCore

final class RelatedDomainsTests: XCTestCase {
    func test_xCoversMobileApiAndMediaHosts() {
        let names = Set(RelatedDomains.hostnames(for: ["x.com"]))
        for host in ["x.com", "www.x.com", "m.x.com", "mobile.x.com", "api.x.com",
                     "twitter.com", "www.twitter.com", "abs.twimg.com", "pbs.twimg.com", "video.twimg.com"] {
            XCTAssertTrue(names.contains(host), host)
        }
        // t.co is a shortener for links to every site; never blocked implicitly.
        XCTAssertFalse(names.contains("t.co"))
    }

    func test_unknownDomainGetsWwwAndMobileForms() {
        XCTAssertEqual(RelatedDomains.hostnames(for: ["Example.com"]),
                       ["example.com", "m.example.com", "mobile.example.com", "www.example.com"])
    }

    func test_wwwInputIsNormalized() {
        XCTAssertEqual(RelatedDomains.hostnames(for: ["www.example.com"]),
                       RelatedDomains.hostnames(for: ["example.com"]))
    }

    func test_subdomainGetsNoMobileForms() {
        XCTAssertEqual(RelatedDomains.hostnames(for: ["news.ycombinator.com"]),
                       ["news.ycombinator.com", "www.news.ycombinator.com"])
    }

    func test_withoutRelatedOnlyBareAndWww() {
        XCTAssertEqual(RelatedDomains.hostnames(for: ["dns.google", "x.com"], includeRelated: false),
                       ["dns.google", "www.dns.google", "www.x.com", "x.com"])
    }

    func test_unsafeEntriesDropped() {
        XCTAssertEqual(RelatedDomains.hostnames(for: ["bad host.com", "https://x.com", ""]), [])
    }

    func test_companionsAreSafeAndNeverSharedCDNs() {
        let shared = ["fbcdn.net", "akamaihd.net", "cloudfront.net", "fastly.net", "googleusercontent.com"]
        for (key, hosts) in RelatedDomains.companions {
            for host in hosts {
                XCTAssertTrue(DomainValidation.isSafeDomain(host), "\(key): \(host)")
                XCTAssertFalse(shared.contains { host == $0 || host.hasSuffix("." + $0) }, "\(key): \(host)")
            }
        }
    }

    func test_hostnamesBlockWritesEachNameOnce() {
        let out = HostsMarker.buildHostsBlock(hostnames: ["a.com", "www.a.com", "bad host"],
                                              start: "#S", end: "#E", ipv4Sink: "127.72.66.1")
        XCTAssertEqual(out, "\n#S\n127.72.66.1\ta.com\n::\ta.com\n127.72.66.1\twww.a.com\n::\twww.a.com\n#E\n")
    }
}
