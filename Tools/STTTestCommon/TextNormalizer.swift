import Foundation

public enum TextNormalizer {

    /// Normalizes text for WER comparison: lowercase, strip punctuation, collapse whitespace.
    /// Returns an array of words.
    public static func normalizeForWER(_ text: String) -> [String] {
        let lowered = text.lowercased()

        // Remove punctuation but keep apostrophes within words and hyphens
        var cleaned = ""
        for char in lowered {
            if char.isLetter || char.isNumber || char.isWhitespace || char == "'" || char == "-" || char == "\u{00AD}" {
                cleaned.append(char)
            } else {
                cleaned.append(" ")
            }
        }

        // Collapse whitespace and split into words
        return cleaned.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }
}
