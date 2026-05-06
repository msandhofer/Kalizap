import Testing
import Foundation
@testable import Kalizap

// MARK: - Mock Device Provider

final class MockAudioDeviceProvider: AudioDeviceProviding, @unchecked Sendable {
    var mockDevices: [AudioDevice] = []
    var selectDeviceCalled: AudioDevice?
    var shouldThrowOnSelect = false

    func listDevices() -> [AudioDevice] {
        mockDevices
    }

    func setInputDevice(_ device: AudioDevice) throws {
        if shouldThrowOnSelect {
            throw AudioRecorderError.deviceNotFound(deviceID: device.id)
        }
        selectDeviceCalled = device
    }

    func defaultDevice() -> AudioDevice? {
        mockDevices.first { $0.isDefault }
    }
}

// MARK: - Device Manager Tests

@Suite("AudioDeviceManager")
struct AudioDeviceManagerTests {

    @Test("lists available devices from provider")
    func listDevices() {
        let provider = MockAudioDeviceProvider()
        provider.mockDevices = [
            AudioDevice(id: "mic1", name: "Built-in Microphone", isDefault: true),
            AudioDevice(id: "mic2", name: "USB Microphone", isDefault: false),
        ]
        let manager = AudioDeviceManager(provider: provider)
        let devices = manager.listDevices()
        #expect(devices.count == 2)
        #expect(devices[0].name == "Built-in Microphone")
    }

    @Test("selects a device")
    func selectDevice() async throws {
        let provider = MockAudioDeviceProvider()
        let mic = AudioDevice(id: "mic2", name: "USB Microphone", isDefault: false)
        provider.mockDevices = [mic]
        let manager = AudioDeviceManager(provider: provider)
        try await manager.selectDevice(mic)
        #expect(manager.selectedDevice?.id == "mic2")
        #expect(provider.selectDeviceCalled?.id == "mic2")
    }

    @Test("selectDefaultDevice picks the default")
    func selectDefault() async throws {
        let provider = MockAudioDeviceProvider()
        provider.mockDevices = [
            AudioDevice(id: "mic1", name: "Built-in", isDefault: true),
            AudioDevice(id: "mic2", name: "USB", isDefault: false),
        ]
        let manager = AudioDeviceManager(provider: provider)
        try await manager.selectDefaultDevice()
        #expect(manager.selectedDevice?.id == "mic1")
    }

    @Test("selectDevice throws for unknown device")
    func selectUnknown() async {
        let provider = MockAudioDeviceProvider()
        provider.shouldThrowOnSelect = true
        let mic = AudioDevice(id: "gone", name: "Gone", isDefault: false)
        let manager = AudioDeviceManager(provider: provider)
        do {
            try await manager.selectDevice(mic)
            Issue.record("Expected error")
        } catch {
            #expect(manager.selectedDevice == nil)
        }
    }
}
