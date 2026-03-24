import XCTest
@testable import DerFluisterer

final class DictationRecordTests: XCTestCase {

    func testWordCountCalculation() {
        let record = DictationRecord(
            rawTranscript: "das ist ein test",
            correctedText: "Das ist ein Test.",
            language: "de",
            contextMode: "neutral",
            targetApp: "com.apple.Notes",
            durationMs: 3000,
            processingTimeMs: 450
        )

        XCTAssertEqual(record.wordCount, 4)
    }

    func testWordCountEmptyText() {
        let record = DictationRecord(
            rawTranscript: "",
            correctedText: "",
            language: "de",
            contextMode: "neutral",
            targetApp: nil,
            durationMs: 0,
            processingTimeMs: 0
        )

        XCTAssertEqual(record.wordCount, 0)
    }

    func testWordsPerMinuteCalculation() {
        let record = DictationRecord(
            rawTranscript: "test",
            correctedText: "Hier sind sechs einzelne Wörter drin",
            language: "de",
            contextMode: "neutral",
            targetApp: nil,
            durationMs: 30_000, // 30 Sekunden = 0.5 Minuten
            processingTimeMs: 200
        )

        // 6 Wörter / 0.5 Minuten = 12 WPM
        XCTAssertEqual(record.wordsPerMinute, 12.0, accuracy: 0.01)
    }

    func testWordsPerMinuteZeroDuration() {
        let record = DictationRecord(
            rawTranscript: "test",
            correctedText: "Sollte null ergeben",
            language: "de",
            contextMode: "neutral",
            targetApp: nil,
            durationMs: 0,
            processingTimeMs: 0
        )

        XCTAssertEqual(record.wordsPerMinute, 0)
    }
}
