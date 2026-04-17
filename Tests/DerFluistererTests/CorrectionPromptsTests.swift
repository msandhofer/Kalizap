import XCTest
@testable import DerFluisterer

final class CorrectionPromptsTests: XCTestCase {

    // MARK: - buildTasks

    func testBuildTasksWithAllFlagsOn() {
        let tasks = CorrectionTasks()
        let result = CorrectionPrompts.buildTasks(tasks)
        XCTAssertNotNil(result)
        let expected = """
        Aufgaben:
        - Korrigiere Grammatik und Rechtschreibung.
        - Entferne Füllwörter.
        - Wandle gesprochene Sprache in Schriftsprache um.
        - Ergänze Zeichensetzung.
        - Füge keine Informationen hinzu, die nicht im Input vorhanden sind.
        """
        XCTAssertEqual(result, expected)
    }

    func testBuildTasksWithOnlyGrammar() {
        let tasks = CorrectionTasks(
            grammar: true,
            fillerRemoval: false,
            writtenLanguage: false,
            punctuation: false,
            preventHallucination: false
        )
        let result = CorrectionPrompts.buildTasks(tasks)
        XCTAssertEqual(result, "Aufgaben:\n- Korrigiere Grammatik und Rechtschreibung.")
    }

    func testBuildTasksWithNoFlagsReturnsNil() {
        let tasks = CorrectionTasks(
            grammar: false,
            fillerRemoval: false,
            writtenLanguage: false,
            punctuation: false,
            preventHallucination: false
        )
        XCTAssertNil(CorrectionPrompts.buildTasks(tasks))
    }

    // MARK: - Style

    func testStyleNeutralUsesNewCopy() {
        XCTAssertEqual(
            CorrectionPrompts.Style.instruction(for: .neutral),
            "Stil: Neutral. Behalte den ursprünglichen Tonfall bei."
        )
    }

    func testStyleAutoFallsBackToNeutralText() {
        XCTAssertEqual(
            CorrectionPrompts.Style.instruction(for: .auto),
            CorrectionPrompts.Style.instruction(for: .neutral)
        )
    }

    // MARK: - buildSystemPrompt

    func testBuildSystemPromptDefaultsSnapshot() {
        let prompt = CorrectionPrompts.buildSystemPrompt(
            tasks: CorrectionTasks(),
            contextMode: .neutral,
            intensity: CorrectionIntensity()
        )
        let expected = """
        Du bist ein Textkorrektur-Assistent. Korrigiere den folgenden diktierten Text.
        Aufgaben:
        - Korrigiere Grammatik und Rechtschreibung.
        - Entferne Füllwörter.
        - Wandle gesprochene Sprache in Schriftsprache um.
        - Ergänze Zeichensetzung.
        - Füge keine Informationen hinzu, die nicht im Input vorhanden sind.
        Stil: Neutral. Behalte den ursprünglichen Tonfall bei.
        Antworte NUR mit dem korrigierten Text, ohne Erklärungen oder Kommentare.
        """
        XCTAssertEqual(prompt, expected)
    }

    func testBuildSystemPromptFormalAllIntensitiesOn() {
        let prompt = CorrectionPrompts.buildSystemPrompt(
            tasks: CorrectionTasks(),
            contextMode: .formal,
            intensity: CorrectionIntensity(
                allowRephrasing: true,
                allowShortening: true,
                allowRestructuring: true
            )
        )
        XCTAssertTrue(prompt.contains("Stil: Formell."))
        XCTAssertTrue(prompt.contains("Erlaubt: Sätze umformulieren für bessere Lesbarkeit."))
        XCTAssertTrue(prompt.contains("Erlaubt: Redundanzen kürzen."))
        XCTAssertTrue(prompt.contains("Erlaubt: Satzstruktur ändern für besseren Textfluss."))
    }

    func testBuildSystemPromptAutoUsesNeutralStyle() {
        let prompt = CorrectionPrompts.buildSystemPrompt(
            tasks: CorrectionTasks(),
            contextMode: .auto,
            intensity: CorrectionIntensity()
        )
        XCTAssertTrue(prompt.contains("Stil: Neutral. Behalte den ursprünglichen Tonfall bei."))
    }

    func testBuildSystemPromptWithNoTasksReturnsFallbackText() {
        let prompt = CorrectionPrompts.buildSystemPrompt(
            tasks: CorrectionTasks(
                grammar: false,
                fillerRemoval: false,
                writtenLanguage: false,
                punctuation: false,
                preventHallucination: false
            ),
            contextMode: .neutral,
            intensity: CorrectionIntensity()
        )
        XCTAssertEqual(prompt, CorrectionPrompts.noTasksFallback)
    }

    func testBuildSystemPromptDoesNotContainDictionaryLine() {
        let prompt = CorrectionPrompts.buildSystemPrompt(
            tasks: CorrectionTasks(),
            contextMode: .neutral,
            intensity: CorrectionIntensity()
        )
        XCTAssertFalse(prompt.contains("Persönliches Wörterbuch"))
    }
}
