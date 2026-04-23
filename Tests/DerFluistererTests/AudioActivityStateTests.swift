import Testing
import Foundation
@testable import DerFluisterer

@Suite("AudioActivityState")
struct AudioActivityStateTests {

    @Test("initial state: not running, not warm")
    func initialState() {
        let state = AudioActivityState()
        #expect(!state.isCurrentlyRunning)
        #expect(state.lastActivityAt == nil)
        #expect(!state.isWarm(at: .now))
    }

    @Test("starts warm immediately when audio becomes running")
    func runningIsWarm() {
        var state = AudioActivityState(warmthWindow: .seconds(5))
        let t = ContinuousClock.now
        state.onStateChange(nowRunning: true, at: t)
        #expect(state.isCurrentlyRunning)
        #expect(state.isWarm(at: t))
        // And still warm a moment later while running
        #expect(state.isWarm(at: t.advanced(by: .seconds(10))))
    }

    @Test("warm for warmthWindow after stop, cold after")
    func warmAfterStopThenCold() {
        var state = AudioActivityState(warmthWindow: .seconds(5))
        let t0 = ContinuousClock.now
        state.onStateChange(nowRunning: true, at: t0)
        let t1 = t0.advanced(by: .seconds(1))
        state.onStateChange(nowRunning: false, at: t1)

        #expect(!state.isCurrentlyRunning)
        #expect(state.lastActivityAt == t1)

        // Within window: warm
        #expect(state.isWarm(at: t1.advanced(by: .seconds(3))))
        #expect(state.isWarm(at: t1.advanced(by: .milliseconds(4999))))

        // Beyond window: cold
        #expect(!state.isWarm(at: t1.advanced(by: .seconds(6))))
        #expect(!state.isWarm(at: t1.advanced(by: .seconds(60))))
    }

    @Test("stop without prior running: still cold")
    func stopWithoutRunIsCold() {
        var state = AudioActivityState(warmthWindow: .seconds(5))
        let t = ContinuousClock.now
        state.onStateChange(nowRunning: false, at: t)
        #expect(!state.isCurrentlyRunning)
        #expect(state.lastActivityAt == nil)
        #expect(!state.isWarm(at: t))
    }

    @Test("custom warmthWindow is respected")
    func customWindow() {
        var state = AudioActivityState(warmthWindow: .seconds(3))
        let t0 = ContinuousClock.now
        state.onStateChange(nowRunning: true, at: t0)
        state.onStateChange(nowRunning: false, at: t0)

        #expect(state.isWarm(at: t0.advanced(by: .seconds(2))))
        #expect(!state.isWarm(at: t0.advanced(by: .seconds(4))))
    }

    @Test("repeated running updates lastActivityAt so window resets")
    func windowResetsWhileRunning() {
        var state = AudioActivityState(warmthWindow: .seconds(5))
        let t0 = ContinuousClock.now
        state.onStateChange(nowRunning: true, at: t0)
        // Another running-notification later; lastActivityAt should track the latest
        let t1 = t0.advanced(by: .seconds(10))
        state.onStateChange(nowRunning: true, at: t1)
        #expect(state.lastActivityAt == t1)
        state.onStateChange(nowRunning: false, at: t1)
        // 4s after stop at t1 → still warm
        #expect(state.isWarm(at: t1.advanced(by: .seconds(4))))
    }
}
