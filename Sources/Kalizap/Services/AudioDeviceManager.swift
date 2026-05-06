import Foundation

public protocol AudioDeviceProviding: Sendable {
    func listDevices() -> [AudioDevice]
    func setInputDevice(_ device: AudioDevice) throws
    func defaultDevice() -> AudioDevice?
}

public final class AudioDeviceManager: @unchecked Sendable {
    private let provider: AudioDeviceProviding
    public private(set) var selectedDevice: AudioDevice?

    public init(provider: AudioDeviceProviding) {
        self.provider = provider
    }

    public func listDevices() -> [AudioDevice] {
        provider.listDevices()
    }

    public func selectDevice(_ device: AudioDevice) async throws {
        try provider.setInputDevice(device)
        selectedDevice = device
    }

    public func selectDefaultDevice() async throws {
        guard let device = provider.defaultDevice() else {
            return
        }
        try await selectDevice(device)
    }
}
