import Foundation
import os.log

private let logger = Logger(subsystem: "com.derfluesterer", category: "GGMLModelManager")

public final class GGMLModelManager: Sendable {

    public static let shared = GGMLModelManager()

    private let baseURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseURL = appSupport.appendingPathComponent("DerFluisterer/Models/ggml")
    }

    // MARK: - Public API

    public func modelURL(for model: WhisperModel) -> URL {
        baseURL.appendingPathComponent(Self.ggmlFileName(for: model))
    }

    public func isModelDownloaded(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(for: model).path)
    }

    public func downloadModel(
        _ model: WhisperModel,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let destination = modelURL(for: model)

        if FileManager.default.fileExists(atPath: destination.path) {
            logger.info("GGML model already downloaded: \(Self.ggmlFileName(for: model))")
            onProgress(0.9)
            return destination
        }

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let remoteURL = Self.downloadURL(for: model)
        logger.info("Downloading GGML model: \(remoteURL.absoluteString)")

        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (tempURL, response) = try await session.download(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GGMLModelError.downloadFailed(statusCode: statusCode)
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)
        logger.info("GGML model saved: \(destination.path)")
        onProgress(0.9)

        return destination
    }

    // MARK: - VAD Model

    private static let vadFileName = "ggml-silero-v6.2.0.bin"
    private static let vadDownloadURL = URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/\(vadFileName)")!

    public var vadModelURL: URL {
        baseURL.appendingPathComponent("vad").appendingPathComponent(Self.vadFileName)
    }

    public func downloadVADModel(
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let destination = vadModelURL

        if FileManager.default.fileExists(atPath: destination.path) {
            logger.info("VAD model already downloaded")
            onProgress(0.9)
            return destination
        }

        let vadDir = baseURL.appendingPathComponent("vad")
        try FileManager.default.createDirectory(at: vadDir, withIntermediateDirectories: true)

        logger.info("Downloading VAD model: \(Self.vadDownloadURL.absoluteString)")

        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (tempURL, response) = try await session.download(from: Self.vadDownloadURL)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GGMLModelError.downloadFailed(statusCode: statusCode)
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)
        logger.info("VAD model saved: \(destination.path)")
        onProgress(0.9)

        return destination
    }

    public func deleteModel(_ model: WhisperModel) throws {
        let url = modelURL(for: model)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - CoreML Encoder

    /// Returns the encoder directory name that whisper.cpp expects.
    /// whisper.cpp strips quantization suffixes (-q5_0 etc.) before looking for the encoder.
    public static func coremlEncoderDirName(for model: WhisperModel) -> String {
        switch model {
        case .tiny: "ggml-tiny-encoder.mlmodelc"
        case .base: "ggml-base-encoder.mlmodelc"
        case .small: "ggml-small-encoder.mlmodelc"
        case .largeV3: "ggml-large-v3-encoder.mlmodelc"
        case .largeV3Turbo: "ggml-large-v3-turbo-encoder.mlmodelc"
        case .largeV3TurboQ5_0: "ggml-large-v3-turbo-encoder.mlmodelc" // shares encoder with F16
        case .germanTurbo: "ggml-large-v3-turbo-german-encoder.mlmodelc"
        }
    }

    public func coremlEncoderURL(for model: WhisperModel) -> URL {
        baseURL.appendingPathComponent(Self.coremlEncoderDirName(for: model))
    }

    private func coremlEncoderDisabledURL(for model: WhisperModel) -> URL {
        baseURL.appendingPathComponent(Self.coremlEncoderDirName(for: model) + ".disabled")
    }

    public func isCoreMLEncoderAvailable(for model: WhisperModel) -> Bool {
        let url = coremlEncoderURL(for: model)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Enables or disables the CoreML encoder by renaming the directory.
    /// Returns the active encoder URL if enabled, nil if disabled.
    @discardableResult
    public func setCoreMLEncoderEnabled(_ enabled: Bool, for model: WhisperModel) throws -> URL? {
        let activeURL = coremlEncoderURL(for: model)
        let disabledURL = coremlEncoderDisabledURL(for: model)
        let fm = FileManager.default

        if enabled {
            // Rename .disabled back to active
            if !fm.fileExists(atPath: activeURL.path), fm.fileExists(atPath: disabledURL.path) {
                try fm.moveItem(at: disabledURL, to: activeURL)
                logger.info("CoreML encoder enabled: \(activeURL.lastPathComponent)")
            }
            return fm.fileExists(atPath: activeURL.path) ? activeURL : nil
        } else {
            // Rename active to .disabled
            if fm.fileExists(atPath: activeURL.path) {
                try fm.moveItem(at: activeURL, to: disabledURL)
                logger.info("CoreML encoder disabled: \(disabledURL.lastPathComponent)")
            }
            return nil
        }
    }

    public func downloadCoreMLEncoder(
        for model: WhisperModel,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> URL {
        let destination = coremlEncoderURL(for: model)

        // Already downloaded (active or disabled)?
        if isCoreMLEncoderAvailable(for: model) {
            logger.info("CoreML encoder already present: \(destination.lastPathComponent)")
            onProgress(0.9)
            return destination
        }
        // Check if disabled copy exists — just re-enable it
        let disabledURL = coremlEncoderDisabledURL(for: model)
        if FileManager.default.fileExists(atPath: disabledURL.path) {
            try FileManager.default.moveItem(at: disabledURL, to: destination)
            logger.info("CoreML encoder re-enabled from disabled: \(destination.lastPathComponent)")
            onProgress(0.9)
            return destination
        }

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let remoteURL = Self.coremlDownloadURL(for: model)
        logger.info("Downloading CoreML encoder: \(remoteURL.absoluteString)")

        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (tempZipURL, response) = try await session.download(from: remoteURL)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GGMLModelError.downloadFailed(statusCode: statusCode)
        }

        // Unzip to temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", tempZipURL.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        // Clean up zip
        try? FileManager.default.removeItem(at: tempZipURL)

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempDir)
            throw GGMLModelError.coremlUnzipFailed
        }

        // Find the .mlmodelc directory in unzipped contents
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let mlmodelcDir = contents.first(where: { $0.pathExtension == "mlmodelc" }) else {
            try? FileManager.default.removeItem(at: tempDir)
            throw GGMLModelError.coremlModelNotFound
        }

        // Move to final destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: mlmodelcDir, to: destination)
        try? FileManager.default.removeItem(at: tempDir)

        logger.info("CoreML encoder saved: \(destination.path)")
        onProgress(0.9)
        return destination
    }

    public func deleteCoreMLEncoder(for model: WhisperModel) throws {
        let fm = FileManager.default
        let activeURL = coremlEncoderURL(for: model)
        let disabledURL = coremlEncoderDisabledURL(for: model)
        if fm.fileExists(atPath: activeURL.path) {
            try fm.removeItem(at: activeURL)
        }
        if fm.fileExists(atPath: disabledURL.path) {
            try fm.removeItem(at: disabledURL)
        }
    }

    public static func coremlDownloadURL(for model: WhisperModel) -> URL {
        let zipName: String
        switch model {
        case .tiny: zipName = "ggml-tiny-encoder.mlmodelc.zip"
        case .base: zipName = "ggml-base-encoder.mlmodelc.zip"
        case .small: zipName = "ggml-small-encoder.mlmodelc.zip"
        case .largeV3: zipName = "ggml-large-v3-encoder.mlmodelc.zip"
        case .largeV3Turbo: zipName = "ggml-large-v3-turbo-encoder.mlmodelc.zip"
        case .largeV3TurboQ5_0: zipName = "ggml-large-v3-turbo-encoder.mlmodelc.zip"
        case .germanTurbo: zipName = "ggml-large-v3-turbo-encoder.mlmodelc.zip" // same encoder architecture
        }
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(zipName)")!
    }

    // MARK: - Mapping

    public static func ggmlFileName(for model: WhisperModel) -> String {
        switch model {
        case .tiny: "ggml-tiny.bin"
        case .base: "ggml-base.bin"
        case .small: "ggml-small.bin"
        case .largeV3: "ggml-large-v3.bin"
        case .largeV3Turbo: "ggml-large-v3-turbo.bin"
        case .largeV3TurboQ5_0: "ggml-large-v3-turbo-q5_0.bin"
        case .germanTurbo: "ggml-large-v3-turbo-german.bin"
        }
    }

    public static func downloadURL(for model: WhisperModel) -> URL {
        switch model {
        case .germanTurbo:
            return URL(string: "https://huggingface.co/cstr/whisper-large-v3-turbo-german-ggml/resolve/main/ggml-model.bin")!
        default:
            let fileName = ggmlFileName(for: model)
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        }
    }
}

// MARK: - Error

public enum GGMLModelError: Error, LocalizedError {
    case downloadFailed(statusCode: Int)
    case coremlUnzipFailed
    case coremlModelNotFound

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let statusCode):
            "GGML model download failed (HTTP \(statusCode))"
        case .coremlUnzipFailed:
            "CoreML encoder zip could not be extracted"
        case .coremlModelNotFound:
            "CoreML encoder .mlmodelc not found in downloaded zip"
        }
    }
}

// MARK: - Download Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @Sendable @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(min(fraction * 0.9, 0.89))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // File handling done in downloadModel
    }
}
