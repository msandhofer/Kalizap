import AVFoundation

enum AudioLoader {
    /// Lädt eine Audio-Datei und konvertiert zu 16kHz Mono Float32.
    /// Unterstützt m4a, wav, mp3, caf und alle von AVAudioFile unterstützten Formate.
    static func loadSamples(from path: String) throws -> (samples: [Float], duration: Double) {
        let url = URL(fileURLWithPath: path)
        let file = try AVAudioFile(forReading: url)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat) else {
            throw AudioLoaderError.cannotCreateConverter
        }

        let frameCount = AVAudioFrameCount(
            Double(file.length) * 16000.0 / file.processingFormat.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else {
            throw AudioLoaderError.cannotCreateBuffer
        }

        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            let remaining = file.length - file.framePosition
            guard remaining > 0 else {
                outStatus.pointee = .endOfStream
                return nil
            }
            let count = AVAudioFrameCount(min(remaining, 4096))
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: count
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

        if let conversionError { throw conversionError }

        guard let channelData = outputBuffer.floatChannelData else {
            throw AudioLoaderError.noChannelData
        }

        let samples = Array(
            UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength))
        )
        let duration = Double(samples.count) / 16000.0
        return (samples, duration)
    }
}

enum AudioLoaderError: Error, CustomStringConvertible {
    case cannotCreateConverter
    case cannotCreateBuffer
    case noChannelData

    var description: String {
        switch self {
        case .cannotCreateConverter: "Audio-Converter konnte nicht erstellt werden"
        case .cannotCreateBuffer: "Audio-Buffer konnte nicht erstellt werden"
        case .noChannelData: "Keine Channel-Daten im Audio"
        }
    }
}
