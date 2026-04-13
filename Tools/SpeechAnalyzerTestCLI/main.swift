import Foundation

// MARK: - SpeechAnalyzerTestCLI Entry Point

let usage = """
Usage:
  swift run SpeechAnalyzerTestCLI transcribe <audio-path> [--locale de_DE]
  swift run SpeechAnalyzerTestCLI batch <directory> [--locale de_DE] [--json]
  swift run SpeechAnalyzerTestCLI stream <audio-path> [--locale de_DE] [--json]
"""

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

guard !mode.isEmpty else {
    print(usage)
    exit(1)
}

guard #available(macOS 26, *) else {
    print("FEHLER: SpeechAnalyzer erfordert macOS 26 oder neuer.")
    exit(1)
}

Task {
    do {
        if #available(macOS 26, *) {
            switch mode {
            case "transcribe":
                let args = parseTranscribeArgs()
                try await runTranscribeMode(args: args)

            case "batch":
                let args = parseBatchArgs()
                try await runBatchMode(args: args)

            case "stream":
                let args = parseStreamArgs()
                try await runStreamMode(args: args)

            case "transcribe-raw":
                let args = parseTranscribeArgs()
                try await runTranscribeRawMode(args: args)

            default:
                print("Unbekannter Modus: \(mode)")
                print(usage)
                exit(1)
            }
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
