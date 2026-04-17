import XCTest
@testable import DerFluisterer

final class AudioRecorderImplTests: XCTestCase {

    // MARK: - Init

    func test_init_createsInstanceWithDefaultSpectrumHandler() {
        let sut = AudioRecorderImpl(deviceProvider: StubDeviceProvider())

        XCTAssertNotNil(sut.audioStream)
        XCTAssertNotNil(sut.levelStream)
        XCTAssertNotNil(sut.availableDevices)
    }

    // MARK: - Device Provider Delegation

    func test_listDevices_returnsDevicesFromProvider() {
        let provider = StubDeviceProvider()
        provider.stubbedDevices = [
            AudioDevice(id: "a", name: "Alpha", isDefault: true),
            AudioDevice(id: "b", name: "Beta", isDefault: false)
        ]
        let sut = AudioRecorderImpl(deviceProvider: provider)

        let devices = sut.listDevices()

        XCTAssertEqual(devices.map(\.id), ["a", "b"])
        XCTAssertEqual(devices.first?.name, "Alpha")
    }

    func test_listDevices_returnsEmptyArrayWhenProviderHasNone() {
        let provider = StubDeviceProvider()
        provider.stubbedDevices = []
        let sut = AudioRecorderImpl(deviceProvider: provider)

        XCTAssertEqual(sut.listDevices(), [])
    }

    // MARK: - Metering No-Ops

    func test_startMetering_isNoOp() async {
        let sut = AudioRecorderImpl(deviceProvider: StubDeviceProvider())
        await sut.startMetering()
        // No assertion — just verify no crash / no exception
    }

    func test_stopMetering_isNoOp() async {
        let sut = AudioRecorderImpl(deviceProvider: StubDeviceProvider())
        await sut.stopMetering()
    }
}

// MARK: - SpectrumHandlerBox Tests

final class SpectrumHandlerBoxTests: XCTestCase {

    func test_set_thenDispatch_callsHandlerWithBands() {
        let box = SpectrumHandlerBox()
        nonisolated(unsafe) var received: [Float] = []
        let lock = NSLock()

        box.set { bands in
            lock.lock()
            received = bands
            lock.unlock()
        }

        box.dispatch([0.1, 0.5, 0.9])

        lock.lock()
        XCTAssertEqual(received, [0.1, 0.5, 0.9])
        lock.unlock()
    }

    func test_setNil_afterPreviousHandler_suppressesDispatch() {
        let box = SpectrumHandlerBox()
        nonisolated(unsafe) var callCount = 0
        let lock = NSLock()

        box.set { _ in
            lock.lock()
            callCount += 1
            lock.unlock()
        }
        box.dispatch([1.0])
        box.set(nil)
        box.dispatch([2.0])

        lock.lock()
        XCTAssertEqual(callCount, 1, "Nach set(nil) darf der zuvor gesetzte Handler nicht mehr aufgerufen werden")
        lock.unlock()
    }

    func test_dispatchWithoutHandler_doesNotCrash() {
        let box = SpectrumHandlerBox()
        box.dispatch([0.3])
        // Just verify no crash
    }

    func test_concurrentSetAndDispatch_doesNotCrash() async {
        let box = SpectrumHandlerBox()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    for _ in 0..<100 {
                        box.set { _ in }
                    }
                }
                group.addTask {
                    for _ in 0..<100 {
                        box.dispatch([0.1, 0.2])
                    }
                }
                group.addTask {
                    for _ in 0..<100 {
                        box.set(nil)
                    }
                }
            }
        }
        // Just verify no data race / crash — protected by NSLock
    }
}

// MARK: - Stubs

private final class StubDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    var stubbedDevices: [AudioDevice] = []

    func listDevices() -> [AudioDevice] { stubbedDevices }
    func setInputDevice(_ device: AudioDevice) throws {}
    func defaultDevice() -> AudioDevice? { stubbedDevices.first(where: \.isDefault) }
}
