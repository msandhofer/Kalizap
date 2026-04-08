import Foundation

// MARK: - SpeechSwiftTestCLI Entry Point

let usage = """
Usage:
  swift run SpeechSwiftTestCLI file <audio-path> [de|en|auto]
  swift run SpeechSwiftTestCLI live [de|en|auto]
  swift run SpeechSwiftTestCLI stream [de|en|auto]
  swift run SpeechSwiftTestCLI batch <directory> [de|en|auto]
  swift run SpeechSwiftTestCLI stream-file <audio-path> [de|en|auto] [--min-segment 3] [--max-segment 7] [--min-silence 0.4] [--json]
  swift run SpeechSwiftTestCLI sweep <directory> [de|en|auto] [--json]
"""

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

guard !mode.isEmpty else {
    print(usage)
    exit(1)
}

Task {
    do {
        switch mode {
        case "file":
            let path = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
            guard !path.isEmpty else {
                print("Fehler: Audio-Pfad erforderlich.")
                print(usage)
                exit(1)
            }
            let lang = resolveLanguage(CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "de")
            try await runFileMode(path: path, language: lang)

        case "live":
            let lang = resolveLanguage(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "de")
            try await runLiveMode(language: lang)

        case "stream":
            let lang = resolveLanguage(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "de")
            try await runStreamMode(language: lang)

        case "batch":
            let dir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
            guard !dir.isEmpty else {
                print("Fehler: Verzeichnis-Pfad erforderlich.")
                print(usage)
                exit(1)
            }
            let lang = resolveLanguage(CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "de")
            try await runBatchMode(directory: dir, language: lang)

        case "stream-file":
            let args = parseStreamFileArgs()
            try await runStreamFileMode(args: args)

        case "sweep":
            let args = parseSweepArgs()
            try await runSweepMode(args: args)

        default:
            print("Unbekannter Modus: \(mode)")
            print(usage)
            exit(1)
        }
    } catch {
        print("\nFEHLER:")
        print("  Typ:  \(type(of: error))")
        print("  Desc: \(error)")
        exit(1)
    }

    exit(0)
}

RunLoop.main.run()
