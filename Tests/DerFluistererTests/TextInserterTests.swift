import XCTest
@testable import DerFluisterer

final class TextInserterTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(
        clipboard: MockClipboardManager = MockClipboardManager(),
        keystroke: MockKeystrokeSimulator = MockKeystrokeSimulator(),
        accessibility: MockAccessibilityInserter = MockAccessibilityInserter(),
        appDetector: MockAppDetector = MockAppDetector(
            app: ActiveApp(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        )
    ) -> (TextInserterImpl, MockClipboardManager, MockKeystrokeSimulator, MockAccessibilityInserter, MockAppDetector) {
        let sut = TextInserterImpl(
            clipboard: clipboard,
            keystroke: keystroke,
            accessibility: accessibility,
            appDetector: appDetector,
            restoreDelay: .zero
        )
        return (sut, clipboard, keystroke, accessibility, appDetector)
    }

    // MARK: - AX insertion (preferred path)

    func test_insert_axSucceeds_usesAccessibilityMethod() async {
        let accessibility = MockAccessibilityInserter(hasTextField: true)
        let (sut, clipboard, keystroke, _, _) = makeSUT(accessibility: accessibility)

        let result = await sut.insert("Hello World")

        XCTAssertEqual(result.outcome, .inserted(method: .accessibility))
        XCTAssertEqual(accessibility.insertedText, "Hello World")
        XCTAssertFalse(result.clipboardRestored)
        // Clipboard should not be touched
        XCTAssertFalse(clipboard.backedUp)
        XCTAssertFalse(keystroke.pasteSimulated)
    }

    // MARK: - AX fails → clipboard fallback

    func test_insert_axVerificationFails_fallsBackToClipboard() async {
        let accessibility = MockAccessibilityInserter(hasTextField: true)
        accessibility.insertError = AccessibilityInsertionError.verificationFailed
        let (sut, clipboard, keystroke, _, _) = makeSUT(accessibility: accessibility)

        let result = await sut.insert("verified text")

        XCTAssertEqual(result.outcome, .inserted(method: .clipboard))
        XCTAssertTrue(result.clipboardRestored)
        XCTAssertTrue(clipboard.backedUp)
        XCTAssertEqual(clipboard.setText, "verified text")
        XCTAssertTrue(keystroke.pasteSimulated)
        XCTAssertNotNil(clipboard.restoredSnapshot)
    }

    func test_insert_noTextFieldFocus_usesClipboard() async {
        let accessibility = MockAccessibilityInserter(hasTextField: false)
        let (sut, clipboard, keystroke, _, _) = makeSUT(accessibility: accessibility)

        let result = await sut.insert("clipboard text")

        XCTAssertEqual(result.outcome, .inserted(method: .clipboard))
        XCTAssertTrue(result.clipboardRestored)
        XCTAssertTrue(clipboard.backedUp)
        XCTAssertEqual(clipboard.setText, "clipboard text")
        XCTAssertTrue(keystroke.pasteSimulated)
    }

    // MARK: - pendingInClipboard

    func test_insert_noTextFieldAndClipboardFails_pendingInClipboard() async {
        let clipboard = MockClipboardManager()
        clipboard.setError = NSError(domain: "test", code: 1)
        let accessibility = MockAccessibilityInserter(hasTextField: false)
        let (sut, _, _, _, _) = makeSUT(clipboard: clipboard, accessibility: accessibility)

        let result = await sut.insert("no target")

        XCTAssertEqual(result.outcome, .pendingInClipboard)
        XCTAssertFalse(result.clipboardRestored)
    }

    func test_insert_axFailsAndClipboardFails_pendingInClipboard() async {
        let clipboard = MockClipboardManager()
        clipboard.backupError = NSError(domain: "test", code: 1)
        let accessibility = MockAccessibilityInserter(hasTextField: true)
        accessibility.insertError = AccessibilityInsertionError.verificationFailed
        let (sut, _, _, _, _) = makeSUT(clipboard: clipboard, accessibility: accessibility)

        let result = await sut.insert("both fail")

        XCTAssertEqual(result.outcome, .pendingInClipboard)
        XCTAssertFalse(result.clipboardRestored)
    }

    // MARK: - Active app detection

    func test_insert_noFrontmostApp_targetAppIsNil() async {
        let (sut, _, _, _, _) = makeSUT(
            accessibility: MockAccessibilityInserter(hasTextField: false),
            appDetector: MockAppDetector(app: nil)
        )

        let result = await sut.insert("text")

        XCTAssertNil(result.targetApp)
    }

    // MARK: - Clipboard restore

    func test_insert_clipboardSnapshotIsRestoredWithOriginalData() async {
        let accessibility = MockAccessibilityInserter(hasTextField: false)
        let (sut, clipboard, _, _, _) = makeSUT(accessibility: accessibility)

        _ = await sut.insert("some text")

        XCTAssertEqual(clipboard.restoredSnapshot?.data, Data("original".utf8))
    }
}
