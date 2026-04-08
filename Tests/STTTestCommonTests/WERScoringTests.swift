import Testing
@testable import STTTestCommon

@Suite("WERScoring")
struct WERScoringTests {

    // MARK: - Exact Matches

    @Test func identicalStrings_zeroWER() {
        let result = WERScoring.calculate(hypothesis: "Hallo Welt", reference: "Hallo Welt")
        #expect(result.wer == 0.0)
        #expect(result.substitutions == 0)
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
        #expect(result.referenceCount == 2)
    }

    @Test func caseInsensitive() {
        let result = WERScoring.calculate(hypothesis: "hallo welt", reference: "Hallo Welt")
        #expect(result.wer == 0.0)
    }

    @Test func punctuationIgnored() {
        let result = WERScoring.calculate(
            hypothesis: "Hallo, Welt! Wie geht es?",
            reference: "Hallo Welt Wie geht es"
        )
        #expect(result.wer == 0.0)
    }

    // MARK: - Substitutions

    @Test func singleSubstitution() {
        let result = WERScoring.calculate(hypothesis: "Halo Welt", reference: "Hallo Welt")
        #expect(result.substitutions == 1)
        #expect(result.insertions == 0)
        #expect(result.deletions == 0)
        #expect(result.wer == 0.5)
    }

    // MARK: - Insertions

    @Test func extraWordsInHypothesis() {
        let result = WERScoring.calculate(
            hypothesis: "Hallo schöne Welt",
            reference: "Hallo Welt"
        )
        #expect(result.insertions == 1)
        #expect(result.wer == 0.5)
    }

    // MARK: - Deletions

    @Test func missingWordsInHypothesis() {
        let result = WERScoring.calculate(hypothesis: "Hallo", reference: "Hallo Welt")
        #expect(result.deletions == 1)
        #expect(result.wer == 0.5)
    }

    // MARK: - Edge Cases

    @Test func emptyHypothesis() {
        let result = WERScoring.calculate(hypothesis: "", reference: "Hallo Welt")
        #expect(result.deletions == 2)
        #expect(result.wer == 1.0)
    }

    @Test func emptyReference() {
        let result = WERScoring.calculate(hypothesis: "Hallo Welt", reference: "")
        #expect(result.referenceCount == 0)
        #expect(result.insertions == 2)
        #expect(result.wer == 0.0)
    }

    @Test func bothEmpty() {
        let result = WERScoring.calculate(hypothesis: "", reference: "")
        #expect(result.wer == 0.0)
        #expect(result.referenceCount == 0)
    }

    // MARK: - Mixed Errors

    @Test func substitutionAndInsertion() {
        // ref:  "Die Katze sitzt"       (3 words)
        // hyp:  "Die Hund sitzt dort"   (4 words)
        // Katze→Hund = 1 sub, +dort = 1 ins
        let result = WERScoring.calculate(
            hypothesis: "Die Hund sitzt dort",
            reference: "Die Katze sitzt"
        )
        #expect(result.substitutions + result.insertions + result.deletions == 2)
        #expect(abs(result.wer - 2.0/3.0) < 0.01)
    }

    // MARK: - German-Specific

    @Test func umlauts() {
        let result = WERScoring.calculate(
            hypothesis: "Über die Brücke führt ein Weg",
            reference: "Über die Brücke führt ein Weg"
        )
        #expect(result.wer == 0.0)
    }

    @Test func hyphenatedWords() {
        let result = WERScoring.calculate(
            hypothesis: "Schritt-für-Schritt Anleitung",
            reference: "Schritt-für-Schritt Anleitung"
        )
        #expect(result.wer == 0.0)
    }

    // MARK: - Whitespace Normalization

    @Test func extraWhitespace() {
        let result = WERScoring.calculate(
            hypothesis: "  Hallo   Welt  ",
            reference: "Hallo Welt"
        )
        #expect(result.wer == 0.0)
    }
}

@Suite("TextNormalizer")
struct TextNormalizerTests {

    @Test func lowercasesText() {
        let words = TextNormalizer.normalizeForWER("HALLO Welt")
        #expect(words == ["hallo", "welt"])
    }

    @Test func removesPunctuation() {
        let words = TextNormalizer.normalizeForWER("Hallo, Welt! Test.")
        #expect(words == ["hallo", "welt", "test"])
    }

    @Test func preservesHyphens() {
        let words = TextNormalizer.normalizeForWER("Schritt-für-Schritt")
        #expect(words == ["schritt-für-schritt"])
    }

    @Test func preservesApostrophes() {
        let words = TextNormalizer.normalizeForWER("wie geht's")
        #expect(words == ["wie", "geht's"])
    }

    @Test func collapsesWhitespace() {
        let words = TextNormalizer.normalizeForWER("  Hallo    Welt  ")
        #expect(words == ["hallo", "welt"])
    }

    @Test func emptyString() {
        let words = TextNormalizer.normalizeForWER("")
        #expect(words.isEmpty)
    }

    @Test func onlyPunctuation() {
        let words = TextNormalizer.normalizeForWER("!!! ... ???")
        #expect(words.isEmpty)
    }
}
