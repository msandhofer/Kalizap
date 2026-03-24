import XCTest
@testable import DerFluisterer

final class DictationEntryTests: XCTestCase {

    func testWordCountCalculation() {
        let entry = DictationEntry(
            id: UUID(),
            timestamp: Date(),
            rawTranscript: "das ist ein test",
            correctedText: "Das ist ein Test.",
            language: "de",
            contextMode: "neutral",
            targetApp: "com.apple.Notes",
            durationMs: 3000,
            processingTimeMs: 450
        )

        XCTAssertEqual(entry.wordCount, 4)
    }

    func testWordCountEmptyText() {
        let entry = DictationEntry(
            id: UUID(),
            timestamp: Date(),
            rawTranscript: "",
            correctedText: "",
            language: "de",
            contextMode: "neutral",
            targetApp: nil,
            durationMs: 0,
            processingTimeMs: 0
        )

        XCTAssertEqual(entry.wordCount, 0)
    }

    func testWordsPerMinuteCalculation() {
        let entry = DictationEntry(
            id: UUID(),
            timestamp: Date(),
            rawTranscript: "test",
            correctedText: "Hier sind sechs einzelne Wörter drin",
            language: "de",
            contextMode: "neutral",
            targetApp: nil,
            durationMs: 30_000, // 30 Sekunden = 0.5 Minuten
            processingTimeMs: 200
        )

        // 6 Wörter / 0.5 Minuten = 12 WPM
        XCTAssertEqual(entry.wordsPerMinute, 12.0, accuracy: 0.01)
    }

    func testWordsPerMinuteZeroDuration() {
        let entry = DictationEntry(
            id: UUID(),
            timestamp: Date(),
            rawTranscript: "test",
            correctedText: "Sollte null ergeben",
            language: "de",
            contextMode: "neutral",
            targetApp: nil,
            durationMs: 0,
            processingTimeMs: 0
        )

        XCTAssertEqual(entry.wordsPerMinute, 0)
    }
}
