import AVFoundation
import Foundation

enum AudioLoader {

    /// Loads an audio file, resamples to 16kHz mono Float32, returns (samples, durationSeconds).
    static func loadSamples(from path: String) throws -> ([Float], Double) {
        let url = URL(fileURLWithPath: path)
        let file = try AVAudioFile(forReading: url)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw NSError(
                domain: "WhisperCppTestCLI",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create audio converter"]
            )
        }

        let frameCount = AVAudioFrameCount(Double(file.length) * 16000.0 / file.processingFormat.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            throw NSError(
                domain: "WhisperCppTestCLI",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create output buffer"]
            )
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            let inputFrameCount = min(file.length - file.framePosition, Int64(4096))
            guard inputFrameCount > 0 else {
                outStatus.pointee = .endOfStream
                return nil
            }
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(inputFrameCount)
            ) else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: inputBuffer)
                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        if let error { throw error }

        guard let channelData = outputBuffer.floatChannelData else {
            throw NSError(
                domain: "WhisperCppTestCLI",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No channel data"]
            )
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        let duration = Double(samples.count) / 16000.0
        return (samples, duration)
    }
}
