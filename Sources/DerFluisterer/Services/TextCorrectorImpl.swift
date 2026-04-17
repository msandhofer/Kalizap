import Foundation

public final class TextCorrectorImpl: TextCorrecting, @unchecked Sendable {
    private var config: CorrectionConfig
    private let transport: @Sendable (String, String, Int) async throws -> String
    private let apiKeyProvider: @Sendable () throws -> String
    private var _lastDebugSnapshot: DebugSnapshot?

    public var lastDebugSnapshot: DebugSnapshot? { _lastDebugSnapshot }

    public init(
        config: CorrectionConfig,
        transport: @escaping @Sendable (String, String, Int) async throws -> String,
        apiKeyProvider: @escaping @Sendable () throws -> String
    ) {
        self.config = config
        self.transport = transport
        self.apiKeyProvider = apiKeyProvider
    }

    public func correct(_ input: TranscriptionResult) async -> CorrectionOutcome {
        let rawText = extractText(from: input)
        let systemPrompt = buildSystemPrompt()
        let start = ContinuousClock.now
        var lastError: Error?
        let maxAttempts = 1 + config.maxRetries

        for attempt in 1...maxAttempts {
            do {
                let correctedText = try await callWithTimeout(systemPrompt: systemPrompt, userText: rawText)

                guard !correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    let outcome = CorrectionOutcome.fallbackRaw(text: rawText, reason: .emptyResponse)
                    _lastDebugSnapshot = DebugSnapshot(request: systemPrompt, response: correctedText, outcome: outcome, timestamp: Date())
                    return outcome
                }

                let elapsed = ContinuousClock.now - start
                let stats = CorrectionStats(
                    latencyMs: Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000),
                    tokensUsed: 0,
                    wasRetry: attempt > 1
                )
                let outcome = CorrectionOutcome.corrected(text: correctedText, stats: stats)
                _lastDebugSnapshot = DebugSnapshot(request: systemPrompt, response: correctedText, outcome: outcome, timestamp: Date())
                return outcome
            } catch is TimeoutError {
                let outcome = CorrectionOutcome.fallbackRaw(text: rawText, reason: .timeout)
                _lastDebugSnapshot = DebugSnapshot(request: systemPrompt, response: nil, outcome: outcome, timestamp: Date())
                return outcome
            } catch {
                lastError = error
            }
        }

        let reason: FallbackReason = maxAttempts > 1
            ? .retryExhausted
            : .apiError(underlying: lastError ?? NSError(domain: "TextCorrector", code: -1))
        let outcome = CorrectionOutcome.fallbackRaw(text: rawText, reason: reason)
        _lastDebugSnapshot = DebugSnapshot(request: systemPrompt, response: nil, outcome: outcome, timestamp: Date())
        return outcome
    }

    public func updateConfig(_ config: CorrectionConfig) {
        self.config = config
    }

    private func callWithTimeout(systemPrompt: String, userText: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.transport(systemPrompt, userText, self.config.timeoutMs)
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(self.config.timeoutMs))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }

    private func extractText(from input: TranscriptionResult) -> String {
        switch input {
        case .final(let transcription): transcription.text
        case .partial(let transcription): transcription.text
        }
    }

    func buildSystemPrompt() -> String {
        CorrectionPrompts.buildSystemPrompt(
            tasks: config.tasks,
            contextMode: config.contextMode,
            intensity: config.intensity,
            personalDictionary: config.personalDictionary
        )
    }
}

private struct TimeoutError: Error {}
