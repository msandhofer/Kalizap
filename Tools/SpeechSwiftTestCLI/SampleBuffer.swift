import Foundation

/// Thread-safe Audio-Sample-Collector für Mic-Capture.
/// Sammelt Float-Samples aus dem Audio-Thread und gibt sie gesammelt zurück.
final class SampleBuffer: @unchecked Sendable {
    private var storage: [Float] = []
    private let lock = NSLock()

    func append(_ samples: [Float]) {
        lock.lock()
        storage.append(contentsOf: samples)
        lock.unlock()
    }

    var samples: [Float] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    func samples(from offset: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard offset < storage.count else { return [] }
        return Array(storage[offset...])
    }

    func reset() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}
