import Foundation

public enum CorrectionPrompts {

    public static let systemBase = "Du bist ein Textkorrektur-Assistent. Korrigiere den folgenden diktierten Text."

    public static let tasks = "Aufgaben: Grammatik/Rechtschreibung korrigieren, Füllwörter entfernen, gesprochene Sprache in Schriftsprache umwandeln, Zeichensetzung ergänzen."

    public static let outputInstruction = "Antworte NUR mit dem korrigierten Text, ohne Erklärungen oder Kommentare."

    public enum Style {
        public static func instruction(for mode: ContextMode) -> String {
            switch mode {
            case .formal:
                "Stil: Formell. Verwende Höflichkeitsform und professionelle Sprache."
            case .informal:
                "Stil: Informell. Verwende lockere, umgangssprachliche Sprache."
            case .neutral:
                "Stil: Neutral. Korrigiere ohne den Stil zu verändern."
            case .auto:
                "Stil: Passe den Stil automatisch an den Kontext an."
            }
        }
    }

    public enum Intensity {
        public static let rephrasing = "Du darfst Sätze umformulieren, wenn es die Lesbarkeit verbessert."
        public static let shortening = "Du darfst den Text kürzen, wenn Redundanzen vorhanden sind."
        public static let restructuring = "Du darfst die Satzstruktur verändern, wenn es den Textfluss verbessert."
    }

    public static func dictionaryInstruction(terms: [String]) -> String {
        "Persönliches Wörterbuch (diese Begriffe sind korrekt geschrieben und sollen beibehalten werden): \(terms.joined(separator: ", "))"
    }
}
