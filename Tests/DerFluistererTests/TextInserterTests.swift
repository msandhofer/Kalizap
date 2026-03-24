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

    // MARK: - Cycle 1: Happy path clipboard insertion

    func test_insert_happyPath_backupsClipboardPastesAndRestores() async {
        let (sut, clipboard, keystroke, _, _) = makeSUT()

        let result = await sut.insert("Hello World")

        XCTAssertEqual(result.outcome, .inserted(method: .clipboard))
        XCTAssertTrue(result.clipboardRestored)
        XCTAssertEqual(result.targetApp?.bundleIdentifier, "com.apple.TextEdit")
        XCTAssertTrue(clipboard.backedUp)
        XCTAssertEqual(clipboard.setText, "Hello World")
        XCTAssertTrue(keystroke.pasteSimulated)
        XCTAssertNotNil(clipboard.restoredSnapshot)
    }

    // MARK: - Cycle 2: Active app detection

    func test_insert_noFrontmostApp_targetAppIsNil() async {
        let (sut, _, _, _, _) = makeSUT(appDetector: MockAppDetector(app: nil))

        let result = await sut.insert("text")

        XCTAssertNil(result.targetApp)
    }

    // MARK: - Cycle 3: Accessibility fallback

    func test_insert_clipboardFails_fallsBackToAccessibility() async {
        let clipboard = MockClipboardManager()
        clipboard.setError = NSError(domain: "test", code: 1)
        let accessibility = MockAccessibilityInserter(hasTextField: true)
        let (sut, _, _, _, _) = makeSUT(clipboard: clipboard, accessibility: accessibility)

        let result = await sut.insert("fallback text")

        XCTAssertEqual(result.outcome, .inserted(method: .accessibility))
        XCTAssertEqual(accessibility.insertedText, "fallback text")
        XCTAssertFalse(result.clipboardRestored)
    }

    func test_insert_pasteFails_fallsBackToAccessibility() async {
        let keystroke = MockKeystrokeSimulator()
        keystroke.simulateError = NSError(domain: "test", code: 1)
        let accessibility = MockAccessibilityInserter(hasTextField: true)
        let (sut, _, _, _, _) = makeSUT(keystroke: keystroke, accessibility: accessibility)

        let result = await sut.insert("paste failed")

        XCTAssertEqual(result.outcome, .inserted(method: .accessibility))
        XCTAssertEqual(accessibility.insertedText, "paste failed")
    }

    // MARK: - Cycle 4: pendingInClipboard

    func test_insert_noTextFieldAndClipboardFails_pendingInClipboard() async {
        let clipboard = MockClipboardManager()
        clipboard.setError = NSError(domain: "test", code: 1)
        let accessibility = MockAccessibilityInserter(hasTextField: false)
        let (sut, _, _, _, _) = makeSUT(clipboard: clipboard, accessibility: accessibility)

        let result = await sut.insert("no target")

        XCTAssertEqual(result.outcome, .pendingInClipboard)
        XCTAssertFalse(result.clipboardRestored)
    }

    // MARK: - Cycle 5: Clipboard preserved after insertion

    func test_insert_clipboardSnapshotIsRestoredWithOriginalData() async {
        let (sut, clipboard, _, _, _) = makeSUT()

        _ = await sut.insert("some text")

        XCTAssertEqual(clipboard.restoredSnapshot?.data, Data("original".utf8))
    }
}
