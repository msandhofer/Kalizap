import Foundation

// MARK: - CLI Flag Parsing

struct BatchArgs {
    let directory: String
    let language: String?
    let modelName: String
    let coreml: Bool
}

struct StreamFileArgs {
    let audioPath: String
    let language: String?
    let modelName: String
    let minSegment: Float
    let maxSegment: Float
    let minSilence: Double
    let json: Bool
    let coreml: Bool
}

struct SweepArgs {
    let directory: String
    let language: String?
    let modelName: String
    let json: Bool
    let coreml: Bool
}

func parseFlags(from startIndex: Int) -> [String: String] {
    var flags: [String: String] = [:]
    let args = CommandLine.arguments
    var i = startIndex
    while i < args.count {
        if args[i].hasPrefix("--") {
            let key = String(args[i].dropFirst(2))
            if key == "json" || key == "coreml" {
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

func parseBatchArgs() -> BatchArgs {
    let args = CommandLine.arguments
    let dir = args.count > 2 ? args[2] : ""
    guard !dir.isEmpty else {
        print("Fehler: Verzeichnis-Pfad erforderlich.")
        print("Usage: swift run WhisperCppTestCLI batch <directory> [de|en|auto] [--model base]")
        exit(1)
    }

    let langArg: String
    if args.count > 3, !args[3].hasPrefix("--") {
        langArg = args[3]
    } else {
        langArg = "de"
    }
    let flagStart = args.count > 3 && !args[3].hasPrefix("--") ? 4 : 3
    let flags = parseFlags(from: flagStart)

    return BatchArgs(
        directory: dir,
        language: resolveLanguage(langArg),
        modelName: flags["model"] ?? "base",
        coreml: flags["coreml"] != nil
    )
}

func parseStreamFileArgs() -> StreamFileArgs {
    let args = CommandLine.arguments
    let path = args.count > 2 ? args[2] : ""
    guard !path.isEmpty else {
        print("Fehler: Audio-Pfad erforderlich.")
        print("Usage: swift run WhisperCppTestCLI stream-file <audio-path> [de|en|auto] [--model base] [--min-segment 3] [--max-segment 7] [--min-silence 0.4] [--json]")
        exit(1)
    }

    let langArg: String
    if args.count > 3, !args[3].hasPrefix("--") {
        langArg = args[3]
    } else {
        langArg = "de"
    }
    let flagStart = args.count > 3 && !args[3].hasPrefix("--") ? 4 : 3
    let flags = parseFlags(from: flagStart)

    return StreamFileArgs(
        audioPath: path,
        language: resolveLanguage(langArg),
        modelName: flags["model"] ?? "base",
        minSegment: Float(flags["min-segment"] ?? "") ?? 3.0,
        maxSegment: Float(flags["max-segment"] ?? "") ?? 7.0,
        minSilence: Double(flags["min-silence"] ?? "") ?? 0.4,
        json: flags["json"] != nil,
        coreml: flags["coreml"] != nil
    )
}

func parseSweepArgs() -> SweepArgs {
    let args = CommandLine.arguments
    let dir = args.count > 2 ? args[2] : ""
    guard !dir.isEmpty else {
        print("Fehler: Verzeichnis-Pfad erforderlich.")
        print("Usage: swift run WhisperCppTestCLI sweep <directory> [de|en|auto] [--model base] [--json]")
        exit(1)
    }

    let langArg: String
    if args.count > 3, !args[3].hasPrefix("--") {
        langArg = args[3]
    } else {
        langArg = "de"
    }
    let flagStart = args.count > 3 && !args[3].hasPrefix("--") ? 4 : 3
    let flags = parseFlags(from: flagStart)

    return SweepArgs(
        directory: dir,
        language: resolveLanguage(langArg),
        modelName: flags["model"] ?? "base",
        json: flags["json"] != nil,
        coreml: flags["coreml"] != nil
    )
}
