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

    // MARK: - Mapping

    public static func ggmlFileName(for model: WhisperModel) -> String {
        switch model {
        case .tiny: "ggml-tiny.bin"
        case .base: "ggml-base.bin"
        case .small: "ggml-small.bin"
        case .largeV3: "ggml-large-v3.bin"
        case .largeV3Turbo: "ggml-large-v3-turbo.bin"
        }
    }

    public static func downloadURL(for model: WhisperModel) -> URL {
        let fileName = ggmlFileName(for: model)
        return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
}

// MARK: - Error

public enum GGMLModelError: Error, LocalizedError {
    case downloadFailed(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let statusCode):
            "GGML model download failed (HTTP \(statusCode))"
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
