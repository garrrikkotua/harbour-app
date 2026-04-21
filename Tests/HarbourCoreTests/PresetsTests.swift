import XCTest
@testable import HarbourCore

final class PresetsTests: XCTestCase {

    func test_everyPreset_hasAtLeastOneDomain() {
        for preset in DomainPreset.allCases {
            XCTAssertFalse(preset.domains.isEmpty, "\(preset.rawValue) has no domains")
        }
    }

    func test_everyPresetDomain_passesValidation() {
        for preset in DomainPreset.allCases {
            for d in preset.domains {
                XCTAssertTrue(
                    DomainValidation.isSafeDomain(d),
                    "Preset \(preset.rawValue) domain '\(d)' fails isSafeDomain"
                )
            }
        }
    }

    func test_noDuplicateDomainsWithinAnyPreset() {
        for preset in DomainPreset.allCases {
            let set = Set(preset.domains)
            XCTAssertEqual(
                set.count, preset.domains.count,
                "Preset \(preset.rawValue) has duplicates"
            )
        }
    }

    func test_eachPresetHasAStableId() {
        for preset in DomainPreset.allCases {
            XCTAssertFalse(preset.id.isEmpty)
            XCTAssertEqual(preset.id, preset.rawValue)
        }
    }

    func test_eachPresetHasAnSFSymbol() {
        for preset in DomainPreset.allCases {
            XCTAssertFalse(preset.symbol.isEmpty)
        }
    }

    func test_socialMediaIncludesCoreSites() {
        let social = DomainPreset.socialMedia.domains
        XCTAssertTrue(social.contains("twitter.com"))
        XCTAssertTrue(social.contains("x.com"))
        XCTAssertTrue(social.contains("facebook.com"))
        XCTAssertTrue(social.contains("instagram.com"))
    }

    func test_videoIncludesYouTubeCDN() {
        // Regression guard: YouTube's video stream actually lives on
        // *.googlevideo.com — if the preset loses it, blocking stops working.
        let video = DomainPreset.videoStreaming.domains
        XCTAssertTrue(video.contains("youtube.com"))
        XCTAssertTrue(video.contains("googlevideo.com"))
        XCTAssertTrue(video.contains("ytimg.com"))
    }
}
