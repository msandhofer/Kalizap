import Foundation
import CoreAudio

/// CoreAudio-backed implementation of `AudioActivityMonitoring`. Registers a
/// property listener on the default output device's
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` property so we observe every
/// transition system-wide (including foreign apps like YouTube/Spotify).
///
/// The listener maintains an `AudioActivityState` that answers "is the audio
/// subsystem currently warm?" — either because audio is running right now, or
/// because it was running within the warmth window (default 5 s).
///
/// See docs/audio-cold-start/ for the full design rationale.
public final class SystemAudioActivityMonitor: AudioActivityMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state: AudioActivityState
    private var deviceID: AudioDeviceID = 0
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private let listenerQueue = DispatchQueue.global(qos: .utility)

    public init(warmthWindow: Duration = .seconds(5)) {
        self.state = AudioActivityState(warmthWindow: warmthWindow)
        setupListener()
    }

    deinit {
        teardownListener()
    }

    public func isAudioWarm() -> Bool {
        // Self-healing: take a fresh CoreAudio snapshot on every query and feed
        // it into the state machine. This way the monitor works even if the
        // listener callback never fires (defensive against silent Listener-
        // registration failures). If the listener *is* working, the snapshot
        // simply reaffirms what we already know.
        let snapshotRunning = deviceID != 0 ? Self.queryIsRunning(deviceID: deviceID) : false
        lock.lock()
        state.onStateChange(nowRunning: snapshotRunning, at: .now)
        let warm = state.isWarm(at: .now)
        let lastActivity = state.lastActivityAt
        let currentlyRunning = state.isCurrentlyRunning
        lock.unlock()
        FileLog.log("isAudioWarm — snapshot=\(snapshotRunning), currentlyRunning=\(currentlyRunning), lastActivity=\(lastActivity.map { "\($0.millisecondsSinceNow())ms ago" } ?? "nil"), warm=\(warm)")
        return warm
    }

    // MARK: - Listener Lifecycle

    private func setupListener() {
        guard let device = Self.defaultOutputDevice() else {
            FileLog.log("SystemAudioActivityMonitor — no default output device, listener not installed")
            return
        }
        deviceID = device

        // Initial snapshot so isAudioWarm() has a meaningful answer even
        // before the first listener callback fires.
        let initialRunning = Self.queryIsRunning(deviceID: device)
        lock.lock()
        state.onStateChange(nowRunning: initialRunning, at: .now)
        lock.unlock()

        var address = Self.propertyAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleStateChange()
        }
        listenerBlock = block
        let status = AudioObjectAddPropertyListenerBlock(device, &address, listenerQueue, block)
        if status != noErr {
            FileLog.log("SystemAudioActivityMonitor — listener install failed, status=\(status)")
            listenerBlock = nil
        } else {
            FileLog.log("SystemAudioActivityMonitor — listener installed on deviceID=\(device), initialRunning=\(initialRunning)")
        }
    }

    private func teardownListener() {
        guard let block = listenerBlock, deviceID != 0 else { return }
        var address = Self.propertyAddress
        _ = AudioObjectRemovePropertyListenerBlock(deviceID, &address, listenerQueue, block)
        listenerBlock = nil
    }

    private func handleStateChange() {
        guard deviceID != 0 else { return }
        let nowRunning = Self.queryIsRunning(deviceID: deviceID)
        lock.lock()
        state.onStateChange(nowRunning: nowRunning, at: .now)
        lock.unlock()
        FileLog.log("SystemAudioActivityMonitor — listener callback: nowRunning=\(nowRunning)")
    }

    // MARK: - CoreAudio Helpers

    private static var propertyAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func queryIsRunning(deviceID: AudioDeviceID) -> Bool {
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = propertyAddress
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &isRunning
        )
        return status == noErr && isRunning == 1
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }
}
