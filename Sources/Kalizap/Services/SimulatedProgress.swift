import Foundation

/// Produces simulated progress values that follow a logarithmic curve,
/// approaching but never reaching a ceiling (default 0.95) until explicitly completed.
///
/// Usage:
/// ```swift
/// let sim = SimulatedProgress(estimatedDuration: 60)
/// for await progress in sim.values {
///     updateUI(progress)
/// }
/// // When real work finishes:
/// sim.complete()
/// ```
public final class SimulatedProgress: Sendable {
    private let estimatedDuration: Duration
    private let ceiling: Double
    private let interval: Duration
    private let _completed: _Atomic<Bool> = .init(false)

    public init(
        estimatedDuration: Duration,
        ceiling: Double = 0.95,
        interval: Duration = .milliseconds(200)
    ) {
        self.estimatedDuration = estimatedDuration
        self.ceiling = ceiling
        self.interval = interval
    }

    /// Signal that the real work has finished. The stream will emit 1.0 and end.
    public func complete() {
        _completed.store(true)
    }

    /// Async stream of progress values from 0.0 to 1.0.
    public var values: AsyncStream<Double> {
        let estimatedSeconds = Double(estimatedDuration.components.seconds)
            + Double(estimatedDuration.components.attoseconds) / 1e18
        let ceiling = self.ceiling
        let interval = self.interval
        let completed = self._completed

        return AsyncStream { continuation in
            let task = Task.detached {
                let start = ContinuousClock.now
                while !Task.isCancelled {
                    if completed.load() {
                        continuation.yield(1.0)
                        continuation.finish()
                        return
                    }

                    let elapsed = (ContinuousClock.now - start)
                    let elapsedSeconds = Double(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) / 1e18
                    // Logarithmic curve: progress = ceiling * (1 - e^(-3t/T))
                    // At t=T, progress ≈ ceiling * 0.95
                    let progress = ceiling * (1.0 - exp(-3.0 * elapsedSeconds / estimatedSeconds))
                    continuation.yield(min(progress, ceiling))

                    try? await Task.sleep(for: interval)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Minimal atomic boolean for Sendable conformance.
private final class _Atomic<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) { _value = value }

    func load() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func store(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        _value = value
    }
}
