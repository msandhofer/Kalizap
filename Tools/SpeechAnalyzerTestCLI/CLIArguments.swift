import Foundation

// MARK: - CLI Argument Types

struct TranscribeArgs {
    let audioPath: String
    let locale: String
}

struct BatchArgs {
    let directory: String
    let locale: String
    let json: Bool
}

struct StreamArgs {
    let audioPath: String
    let locale: String
    let json: Bool
}

// MARK: - Flag Parsing

func parseFlags(from startIndex: Int) -> [String: String] {
    var flags: [String: String] = [:]
    let args = CommandLine.arguments
    var i = startIndex
    while i < args.count {
        if args[i].hasPrefix("--") {
            let key = String(args[i].dropFirst(2))
            if key == "json" {
                flags[key] = "true"
                i += 1
            } else if i + 1 < args.count {
                flags[key] = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        } else {
            i += 1
        }
    }
    return flags
}

func parseTranscribeArgs() -> TranscribeArgs {
    let args = CommandLine.arguments
    let path = args.count > 2 ? args[2] : ""
    guard !path.isEmpty else {
        print("Fehler: Audio-Pfad erforderlich.")
        print("Usage: swift run SpeechAnalyzerTestCLI transcribe <audio-path> [--locale de_DE]")
        exit(1)
    }

    let flagStart: Int
    if args.count > 3, !args[3].hasPrefix("--") {
        flagStart = 4
    } else {
        flagStart = 3
    }
    let flags = parseFlags(from: flagStart)

    return TranscribeArgs(
        audioPath: path,
        locale: flags["locale"] ?? "de_DE"
    )
}

func parseBatchArgs() -> BatchArgs {
    let args = CommandLine.arguments
    let dir = args.count > 2 ? args[2] : ""
    guard !dir.isEmpty else {
        print("Fehler: Verzeichnis-Pfad erforderlich.")
        print("Usage: swift run SpeechAnalyzerTestCLI batch <directory> [--locale de_DE] [--json]")
        exit(1)
    }

    let flagStart: Int
    if args.count > 3, !args[3].hasPrefix("--") {
        flagStart = 4
    } else {
        flagStart = 3
    }
    let flags = parseFlags(from: flagStart)

    return BatchArgs(
        directory: dir,
        locale: flags["locale"] ?? "de_DE",
        json: flags["json"] != nil
    )
}

func parseStreamArgs() -> StreamArgs {
    let args = CommandLine.arguments
    let path = args.count > 2 ? args[2] : ""
    guard !path.isEmpty else {
        print("Fehler: Audio-Pfad erforderlich.")
        print("Usage: swift run SpeechAnalyzerTestCLI stream <audio-path> [--locale de_DE] [--json]")
        exit(1)
    }

    let flagStart: Int
    if args.count > 3, !args[3].hasPrefix("--") {
        flagStart = 4
    } else {
        flagStart = 3
    }
    let flags = parseFlags(from: flagStart)

    return StreamArgs(
        audioPath: path,
        locale: flags["locale"] ?? "de_DE",
        json: flags["json"] != nil
    )
}
