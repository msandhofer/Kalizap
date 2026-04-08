import Foundation

// MARK: - WhisperCppTestCLI Entry Point

let usage = """
Usage:
  swift run WhisperCppTestCLI transcribe [model] [audio-path]
  swift run WhisperCppTestCLI batch <directory> [de|en|auto] [--model base] [--coreml]
  swift run WhisperCppTestCLI stream-file <audio-path> [de|en|auto] [--model base] [--min-segment 3] [--max-segment 7] [--min-silence 0.4] [--json] [--coreml]
  swift run WhisperCppTestCLI sweep <directory> [de|en|auto] [--model base] [--json] [--coreml]

Models: tiny, base, small, large-v3, large-v3_turbo, large-v3_turbo-q5_0, german-turbo
"""

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

guard !mode.isEmpty else {
    print(usage)
    exit(1)
}

Task {
    do {
        switch mode {
        case "transcribe":
            let modelName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "tiny"
            let audioPath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "TestAudio.m4a"
            try await runTranscribeMode(modelName: modelName, audioPath: audioPath)

        case "batch":
            let args = parseBatchArgs()
            try await runBatchMode(directory: args.directory, modelName: args.modelName, language: args.language, coreml: args.coreml)

        case "stream-file":
            let args = parseStreamFileArgs()
            try await runStreamFileMode(args: args)

        case "sweep":
            let args = parseSweepArgs()
            try await runSweepMode(args: args)

        default:
            // Legacy: no mode keyword → treat args as (model, audio) for transcribe
            let modelName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tiny"
            let audioPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "TestAudio.m4a"
            try await runTranscribeMode(modelName: modelName, audioPath: audioPath)
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
