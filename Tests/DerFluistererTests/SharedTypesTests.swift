import XCTest
@testable import DerFluisterer

final class SharedTypesTests: XCTestCase {

    func testCorrectionIntensityDefaults() {
        let intensity = CorrectionIntensity()
        XCTAssertFalse(intensity.allowRephrasing)
        XCTAssertFalse(intensity.allowShortening)
        XCTAssertFalse(intensity.allowRestructuring)
    }

    func testPipelineStateStartsIdle() {
        let state = PipelineState.idle
        XCTAssertEqual(state, .idle)
    }

    func testPipelineStateProcessingEquality() {
        let a = PipelineState.processing(stage: .transcribing)
        let b = PipelineState.processing(stage: .transcribing)
        let c = PipelineState.processing(stage: .correcting)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSupportedLanguageCases() {
        XCTAssertEqual(SupportedLanguage.allCases.count, 2)
        XCTAssertEqual(SupportedLanguage.de.rawValue, "de")
        XCTAssertEqual(SupportedLanguage.en.rawValue, "en")
    }

    func testContextModeCases() {
        XCTAssertEqual(ContextMode.allCases.count, 4)
    }
}
