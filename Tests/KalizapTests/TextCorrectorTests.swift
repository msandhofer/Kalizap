import XCTest
@testable import Kalizap

final class TextCorrectorTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(
        config: CorrectionConfig = CorrectionConfig(),
        transport: @escaping @Sendable (String, String, Int, ClaudeModelFamily) async throws -> String = { _, _, _, _ in "corrected" },
        apiKeyProvider: @escaping @Sendable () throws -> String = { "test-key" }
    ) -> TextCorrectorImpl {
        TextCorrectorImpl(
            config: config,
            transport: transport,
            apiKeyProvider: apiKeyProvider
        )
    }

    // MARK: - Cycle 1: Happy path

    func test_correct_happyPath_returnsCorrectedText() async {
        let sut = makeSUT(transport: { _, _, _, _ in
            return "Korrigierter Text"
        })

        let outcome = await sut.correct(makeTestTranscriptionResult("rohes transkript"))

        if case .corrected(let text, let stats) = outcome {
            XCTAssertEqual(text, "Korrigierter Text")
            XCTAssertFalse(stats.wasRetry)
            XCTAssertGreaterThanOrEqual(stats.latencyMs, 0)
        } else {
            XCTFail("Expected .corrected, got \(outcome)")
        }
    }

    func test_correct_passesConfiguredModelFamilyToTransport() async {
        let captured = SendableBox<ClaudeModelFamily?>(nil)
        let sut = makeSUT(config: CorrectionConfig(modelFamily: .sonnet), transport: { _, _, _, family in
            captured.set(family)
            return "ok"
        })

        _ = await sut.correct(makeTestTranscriptionResult("x"))

        XCTAssertEqual(captured.value, .sonnet)
    }

    func test_correctionSettings_defaultToHaikuAndFlowIntoConfig() throws {
        XCTAssertEqual(CorrectionSettings().modelFamily, .haiku)
        let legacy = try JSONDecoder().decode(CorrectionSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.modelFamily, .haiku)

        var settings = CorrectionSettings()
        settings.modelFamily = .sonnet
        XCTAssertEqual(settings.buildCorrectionConfig(frontmostApp: nil).modelFamily, .sonnet)
    }

    // MARK: - Cycle 2: ContextMode in prompt

    func test_correct_formalMode_promptContainsFormal() async {
        let captured = SendableBox<String?>(nil)
        let config = CorrectionConfig(contextMode: .formal)
        let sut = makeSUT(config: config, transport: { systemPrompt, _, _, _ in
            captured.set(systemPrompt)
            return "text"
        })

        _ = await sut.correct(makeTestTranscriptionResult("test"))

        XCTAssertTrue(captured.value?.contains("Formell") == true)
    }

    func test_correct_informalMode_promptContainsInformal() async {
        let captured = SendableBox<String?>(nil)
        let config = CorrectionConfig(contextMode: .informal)
        let sut = makeSUT(config: config, transport: { systemPrompt, _, _, _ in
            captured.set(systemPrompt)
            return "text"
        })

        _ = await sut.correct(makeTestTranscriptionResult("test"))

        XCTAssertTrue(captured.value?.contains("Informell") == true)
    }

    // MARK: - Cycle 3: CorrectionIntensity toggles

    func test_correct_withRephrasing_promptContainsRephrasingPermission() async {
        let captured = SendableBox<String?>(nil)
        let config = CorrectionConfig(intensity: CorrectionIntensity(allowRephrasing: true))
        let sut = makeSUT(config: config, transport: { systemPrompt, _, _, _ in
            captured.set(systemPrompt)
            return "text"
        })

        _ = await sut.correct(makeTestTranscriptionResult("test"))

        XCTAssertTrue(captured.value?.contains("umformulieren") == true)
    }

    func test_correct_withoutRephrasing_promptOmitsRephrasingPermission() async {
        let captured = SendableBox<String?>(nil)
        let config = CorrectionConfig(intensity: CorrectionIntensity(allowRephrasing: false))
        let sut = makeSUT(config: config, transport: { systemPrompt, _, _, _ in
            captured.set(systemPrompt)
            return "text"
        })

        _ = await sut.correct(makeTestTranscriptionResult("test"))

        XCTAssertFalse(captured.value?.contains("umformulieren") == true)
    }

    // MARK: - Cycle 4: Personal dictionary

    func test_correct_withDictionary_promptContainsTerms() async {
        let captured = SendableBox<String?>(nil)
        let config = CorrectionConfig(personalDictionary: ["SwiftUI", "WhisperKit"])
        let sut = makeSUT(config: config, transport: { systemPrompt, _, _, _ in
            captured.set(systemPrompt)
            return "text"
        })

        _ = await sut.correct(makeTestTranscriptionResult("test"))

        XCTAssertTrue(captured.value?.contains("SwiftUI") == true)
        XCTAssertTrue(captured.value?.contains("WhisperKit") == true)
    }

    // MARK: - Cycle 5: Retry on failure

    func test_correct_firstCallFails_retriesAndSucceeds() async {
        let callCount = SendableBox(0)
        let sut = makeSUT(transport: { _, _, _, _ in
            callCount.set(callCount.value + 1)
            if callCount.value == 1 {
                throw NSError(domain: "test", code: 1)
            }
            return "retried result"
        })

        let outcome = await sut.correct(makeTestTranscriptionResult("test"))

        if case .corrected(let text, let stats) = outcome {
            XCTAssertEqual(text, "retried result")
            XCTAssertTrue(stats.wasRetry)
            XCTAssertEqual(callCount.value, 2)
        } else {
            XCTFail("Expected .corrected after retry, got \(outcome)")
        }
    }

    // MARK: - Cycle 6: Fallback after retry exhaustion

    func test_correct_allRetriesFail_returnsFallbackRaw() async {
        let sut = makeSUT(transport: { _, _, _, _ in
            throw NSError(domain: "test", code: 1)
        })

        let outcome = await sut.correct(makeTestTranscriptionResult("raw text"))

        if case .fallbackRaw(let text, let reason) = outcome {
            XCTAssertEqual(text, "raw text")
            if case .retryExhausted = reason {} else {
                XCTFail("Expected .retryExhausted, got \(reason)")
            }
        } else {
            XCTFail("Expected .fallbackRaw, got \(outcome)")
        }
    }

    // MARK: - Cycle 7: Timeout

    func test_correct_timeout_returnsFallbackWithTimeoutReason() async {
        let config = CorrectionConfig(timeoutMs: 50, maxRetries: 0)
        let sut = makeSUT(config: config, transport: { _, _, _, _ in
            try await Task.sleep(for: .milliseconds(200))
            return "too late"
        })

        let outcome = await sut.correct(makeTestTranscriptionResult("test"))

        if case .fallbackRaw(_, let reason) = outcome {
            if case .timeout = reason {} else {
                XCTFail("Expected .timeout, got \(reason)")
            }
        } else {
            XCTFail("Expected .fallbackRaw, got \(outcome)")
        }
    }

    // MARK: - Cycle 8: Empty response

    func test_correct_emptyResponse_returnsFallbackRaw() async {
        let sut = makeSUT(transport: { _, _, _, _ in "" })

        let outcome = await sut.correct(makeTestTranscriptionResult("test input"))

        if case .fallbackRaw(let text, let reason) = outcome {
            XCTAssertEqual(text, "test input")
            if case .emptyResponse = reason {} else {
                XCTFail("Expected .emptyResponse, got \(reason)")
            }
        } else {
            XCTFail("Expected .fallbackRaw, got \(outcome)")
        }
    }

    // MARK: - Cycle 9: DebugSnapshot

    func test_correct_setsLastDebugSnapshot() async {
        let sut = makeSUT(transport: { _, _, _, _ in "corrected" })

        _ = await sut.correct(makeTestTranscriptionResult("input"))

        let snapshot = sut.lastDebugSnapshot
        XCTAssertNotNil(snapshot)
        XCTAssertTrue(snapshot?.request.contains("Textkorrektur") == true)
        XCTAssertEqual(snapshot?.response, "corrected")
    }

    // MARK: - Cycle 10: updateConfig

    func test_updateConfig_affectsNextCall() async {
        let captured = SendableBox<String?>(nil)
        let sut = makeSUT(config: CorrectionConfig(contextMode: .neutral), transport: { systemPrompt, _, _, _ in
            captured.set(systemPrompt)
            return "text"
        })

        sut.updateConfig(CorrectionConfig(contextMode: .formal))
        _ = await sut.correct(makeTestTranscriptionResult("test"))

        XCTAssertTrue(captured.value?.contains("Formell") == true)
    }

    // MARK: - Cycle 11: User-Message wird in <diktat>-Tags gewrappt (Issue #50)

    func test_correct_wrapsUserTextInDiktatTags() async {
        let capturedUserText = SendableBox<String?>(nil)
        let sut = makeSUT(transport: { _, userText, _, _ in
            capturedUserText.set(userText)
            return "corrected"
        })

        _ = await sut.correct(makeTestTranscriptionResult("mein diktat"))

        guard let got = capturedUserText.value else {
            XCTFail("Transport wurde nicht aufgerufen")
            return
        }
        XCTAssertTrue(got.contains("<diktat>"), "User-Text muss in <diktat>-Tag eingeschlossen sein")
        XCTAssertTrue(got.contains("</diktat>"), "User-Text muss mit </diktat> schliessen")
        XCTAssertTrue(got.contains("mein diktat"), "Roh-Text muss im gewrappten User-Text erhalten bleiben")
    }
}
