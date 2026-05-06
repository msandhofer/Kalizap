import XCTest
@testable import Kalizap

final class SharedTypesTests: XCTestCase {

    func testCorrectionIntensityDefaults() {
        let intensity = CorrectionIntensity()
        XCTAssertFalse(intensity.allowRephrasing)
        XCTAssertFalse(intensity.allowShortening)
        XCTAssertFalse(intensity.allowRestructuring)
    }

    func testCorrectionTasksDefaults() {
        let tasks = CorrectionTasks()
        XCTAssertTrue(tasks.grammar)
        XCTAssertTrue(tasks.fillerRemoval)
        XCTAssertTrue(tasks.writtenLanguage)
        XCTAssertTrue(tasks.punctuation)
        XCTAssertTrue(tasks.preventHallucination)
        XCTAssertFalse(tasks.isEmpty)
    }

    func testCorrectionTasksIsEmpty() {
        var tasks = CorrectionTasks(
            grammar: false,
            fillerRemoval: false,
            writtenLanguage: false,
            punctuation: false,
            preventHallucination: false
        )
        XCTAssertTrue(tasks.isEmpty)
        tasks.grammar = true
        XCTAssertFalse(tasks.isEmpty)
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
