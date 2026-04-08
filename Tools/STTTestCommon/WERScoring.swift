import Foundation

public struct WERResult: Codable, Sendable {
    public let substitutions: Int
    public let insertions: Int
    public let deletions: Int
    public let referenceCount: Int
    public let wer: Double

    public init(substitutions: Int, insertions: Int, deletions: Int, referenceCount: Int) {
        self.substitutions = substitutions
        self.insertions = insertions
        self.deletions = deletions
        self.referenceCount = referenceCount
        self.wer = referenceCount > 0
            ? Double(substitutions + insertions + deletions) / Double(referenceCount)
            : 0.0
    }
}

public enum WERScoring {

    /// Calculates Word Error Rate using Levenshtein distance on word arrays.
    /// Both strings are normalized (lowercase, no punctuation) before comparison.
    public static func calculate(hypothesis: String, reference: String) -> WERResult {
        let hypWords = TextNormalizer.normalizeForWER(hypothesis)
        let refWords = TextNormalizer.normalizeForWER(reference)
        return calculateOnWords(hypothesis: hypWords, reference: refWords)
    }

    /// Calculates WER directly on pre-normalized word arrays.
    public static func calculateOnWords(hypothesis: [String], reference: [String]) -> WERResult {
        let n = reference.count
        let m = hypothesis.count

        guard n > 0 else {
            return WERResult(substitutions: 0, insertions: m, deletions: 0, referenceCount: 0)
        }
        guard m > 0 else {
            return WERResult(substitutions: 0, insertions: 0, deletions: n, referenceCount: n)
        }

        // Dynamic programming matrix: dp[i][j] = edit distance between ref[0..<i] and hyp[0..<j]
        // To save memory, we only keep two rows.
        var prev = Array(0...m)
        var curr = Array(repeating: 0, count: m + 1)

        // Track operations via backtracking matrix
        // 0 = match/sub, 1 = insertion (hyp has extra), 2 = deletion (ref has extra)
        var ops = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for j in 1...m { ops[0][j] = 1 }
        for i in 1...n { ops[i][0] = 2 }

        for i in 1...n {
            curr[0] = i
            for j in 1...m {
                let sub = prev[j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1)
                let ins = curr[j - 1] + 1
                let del = prev[j] + 1

                let minVal = min(sub, ins, del)
                curr[j] = minVal

                if minVal == sub {
                    ops[i][j] = 0
                } else if minVal == ins {
                    ops[i][j] = 1
                } else {
                    ops[i][j] = 2
                }
            }
            prev = curr
        }

        // Backtrack to count S, I, D
        var subs = 0, ins = 0, dels = 0
        var i = n, j = m
        while i > 0 || j > 0 {
            switch ops[i][j] {
            case 0: // substitution or match
                if reference[i - 1] != hypothesis[j - 1] { subs += 1 }
                i -= 1; j -= 1
            case 1: // insertion
                ins += 1; j -= 1
            case 2: // deletion
                dels += 1; i -= 1
            default:
                break
            }
        }

        return WERResult(substitutions: subs, insertions: ins, deletions: dels, referenceCount: n)
    }
}
