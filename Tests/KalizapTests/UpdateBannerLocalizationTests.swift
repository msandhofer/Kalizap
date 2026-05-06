import XCTest
@testable import Kalizap

final class UpdateBannerLocalizationTests: XCTestCase {

    func test_strings_german_containsVersionPlaceholder() {
        let s = UpdateBannerLocalization.strings(for: .german)
        XCTAssertTrue(s.titleTemplate.contains("{version}"), "Titel muss {version}-Platzhalter enthalten")
    }

    func test_strings_english_containsVersionPlaceholder() {
        let s = UpdateBannerLocalization.strings(for: .english)
        XCTAssertTrue(s.titleTemplate.contains("{version}"), "Title muss {version}-Platzhalter enthalten")
    }

    func test_strings_allFieldsNonEmpty_german() {
        let s = UpdateBannerLocalization.strings(for: .german)
        XCTAssertFalse(s.titleTemplate.isEmpty)
        XCTAssertFalse(s.homebrewInstructionLabel.isEmpty)
        XCTAssertFalse(s.directDownloadInstructionLabel.isEmpty)
        XCTAssertFalse(s.quarantineHint.isEmpty)
        XCTAssertFalse(s.copyButton.isEmpty)
        XCTAssertFalse(s.openReleaseButton.isEmpty)
        XCTAssertFalse(s.laterButton.isEmpty)
        XCTAssertFalse(s.checkForUpdatesButton.isEmpty)
    }

    func test_strings_allFieldsNonEmpty_english() {
        let s = UpdateBannerLocalization.strings(for: .english)
        XCTAssertFalse(s.titleTemplate.isEmpty)
        XCTAssertFalse(s.homebrewInstructionLabel.isEmpty)
        XCTAssertFalse(s.directDownloadInstructionLabel.isEmpty)
        XCTAssertFalse(s.quarantineHint.isEmpty)
        XCTAssertFalse(s.copyButton.isEmpty)
        XCTAssertFalse(s.openReleaseButton.isEmpty)
        XCTAssertFalse(s.laterButton.isEmpty)
        XCTAssertFalse(s.checkForUpdatesButton.isEmpty)
    }

    func test_language_fromLocaleIdentifier_en_returnsEnglish() {
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: "en"), .english)
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: "en-US"), .english)
    }

    func test_language_fromLocaleIdentifier_other_returnsGerman() {
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: "de"), .german)
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: "fr"), .german)
        XCTAssertEqual(UpdateBannerLocalization.Language.from(localeIdentifier: nil), .german)
    }
}
