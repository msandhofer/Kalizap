import Foundation

// MARK: - Stream-File Result

public struct StreamFileParams: Codable, Sendable {
    public let minSegment: Double
    public let maxSegment: Double
    public let minSilence: Double

    public init(minSegment: Double, maxSegment: Double, minSilence: Double) {
        self.minSegment = minSegment
        self.maxSegment = maxSegment
        self.minSilence = minSilence
    }
}

public struct StreamFileResult: Codable, Sendable {
    public let file: String
    public let engine: String
    public let params: StreamFileParams
    public let segments: Int
    public let wer: Double?
    public let latency_after_stop_ms: Int
    public let total_stt_ms: Int
    public let text: String
    public let expected: String?

    public init(
        file: String,
        engine: String,
        params: StreamFileParams,
        segments: Int,
        wer: Double?,
        latency_after_stop_ms: Int,
        total_stt_ms: Int,
        text: String,
        expected: String?
    ) {
        self.file = file
        self.engine = engine
        self.params = params
        self.segments = segments
        self.wer = wer
        self.latency_after_stop_ms = latency_after_stop_ms
        self.total_stt_ms = total_stt_ms
        self.text = text
        self.expected = expected
    }
}

// MARK: - Sweep Result

public struct SweepEntry: Codable, Sendable {
    public let params: StreamFileParams
    public let avgWER: Double
    public let avgLatencyMs: Int
    public let fileCount: Int
    public let paretoOptimal: Bool

    public init(params: StreamFileParams, avgWER: Double, avgLatencyMs: Int, fileCount: Int, paretoOptimal: Bool) {
        self.params = params
        self.avgWER = avgWER
        self.avgLatencyMs = avgLatencyMs
        self.fileCount = fileCount
        self.paretoOptimal = paretoOptimal
    }
}

public struct SweepResult: Codable, Sendable {
    public let engine: String
    public let entries: [SweepEntry]
    public let details: [StreamFileResult]

    public init(engine: String, entries: [SweepEntry], details: [StreamFileResult]) {
        self.engine = engine
        self.entries = entries
        self.details = details
    }
}

// MARK: - Pareto Identification

public enum ParetoFilter {

    /// Identifies Pareto-optimal entries: no other entry has both better WER AND better latency.
    /// Only considers entries with latency < maxLatencyMs.
    public static func markPareto(_ entries: [(params: StreamFileParams, avgWER: Double, avgLatencyMs: Int, fileCount: Int)], maxLatencyMs: Int = 600) -> [SweepEntry] {
        let eligible = entries.filter { $0.avgLatencyMs < maxLatencyMs }

        return entries.map { entry in
            let isPareto: Bool
            if entry.avgLatencyMs >= maxLatencyMs {
                isPareto = false
            } else {
                // Pareto-optimal if no other eligible entry dominates it
                isPareto = !eligible.contains { other in
                    other.avgWER < entry.avgWER && other.avgLatencyMs < entry.avgLatencyMs
                        && !(other.avgWER == entry.avgWER && other.avgLatencyMs == entry.avgLatencyMs)
                }
            }
            return SweepEntry(
                params: entry.params,
                avgWER: entry.avgWER,
                avgLatencyMs: entry.avgLatencyMs,
                fileCount: entry.fileCount,
                paretoOptimal: isPareto
            )
        }
    }
}

// MARK: - JSON Encoding Helper

public enum TestResultJSON {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
