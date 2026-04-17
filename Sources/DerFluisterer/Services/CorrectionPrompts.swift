import Foundation

public enum CorrectionPrompts {

    public static let systemBase = "Du bist ein Textkorrektur-Assistent. Korrigiere den folgenden diktierten Text."

    public static let outputInstruction = "Antworte NUR mit dem korrigierten Text, ohne Erklärungen oder Kommentare."

    public static let noTasksFallback = "LLM-Korrektur deaktiviert — Diktat wird nur transkribiert."

    public enum Style {
        public static func instruction(for mode: ContextMode) -> String {
            switch mode {
            case .formal:
                "Stil: Formell. Verwende Höflichkeitsform und professionelle Sprache."
            case .informal:
                "Stil: Informell. Verwende lockere, umgangssprachliche Sprache."
            case .neutral, .auto:
                "Stil: Neutral. Behalte den ursprünglichen Tonfall bei."
            }
        }
    }

    public enum Intensity {
        public static let rephrasing = "Erlaubt: Sätze umformulieren für bessere Lesbarkeit."
        public static let shortening = "Erlaubt: Redundanzen kürzen."
        public static let restructuring = "Erlaubt: Satzstruktur ändern für besseren Textfluss."
    }

    public enum Tasks {
        public static let grammar = "- Korrigiere Grammatik und Rechtschreibung."
        public static let fillerRemoval = "- Entferne Füllwörter."
        public static let writtenLanguage = "- Wandle gesprochene Sprache in Schriftsprache um."
        public static let punctuation = "- Ergänze Zeichensetzung."
        public static let preventHallucination = "- Füge keine Informationen hinzu, die nicht im Input vorhanden sind."
    }

    public static func buildTasks(_ flags: CorrectionTasks) -> String? {
        var lines: [String] = []
        if flags.grammar { lines.append(Tasks.grammar) }
        if flags.fillerRemoval { lines.append(Tasks.fillerRemoval) }
        if flags.writtenLanguage { lines.append(Tasks.writtenLanguage) }
        if flags.punctuation { lines.append(Tasks.punctuation) }
        if flags.preventHallucination { lines.append(Tasks.preventHallucination) }
        guard !lines.isEmpty else { return nil }
        return (["Aufgaben:"] + lines).joined(separator: "\n")
    }

    public static func dictionaryInstruction(terms: [String]) -> String {
        "Persönliches Wörterbuch (diese Begriffe sind korrekt geschrieben und sollen beibehalten werden): \(terms.joined(separator: ", "))"
    }

    public static func buildSystemPrompt(
        tasks: CorrectionTasks,
        contextMode: ContextMode,
        intensity: CorrectionIntensity,
        personalDictionary: [String] = []
    ) -> String {
        guard !tasks.isEmpty else { return noTasksFallback }
        var parts: [String] = [systemBase]
        if let tasksBlock = buildTasks(tasks) {
            parts.append(tasksBlock)
        }
        parts.append(Style.instruction(for: contextMode))
        if intensity.allowRephrasing { parts.append(Intensity.rephrasing) }
        if intensity.allowShortening { parts.append(Intensity.shortening) }
        if intensity.allowRestructuring { parts.append(Intensity.restructuring) }
        if !personalDictionary.isEmpty {
            parts.append(dictionaryInstruction(terms: personalDictionary))
        }
        parts.append(outputInstruction)
        return parts.joined(separator: "\n")
    }
}
