import Foundation
import IOKit

public protocol HardwareIdentityProviding: Sendable {
    /// Stabile Geräte-Identität. Auf macOS: IOPlatformUUID.
    func deviceIdentifier() throws -> String

    /// User-Account-Name auf diesem Gerät.
    func userName() -> String
}

public enum HardwareIdentityError: Error, LocalizedError {
    case platformUUIDUnavailable

    public var errorDescription: String? {
        switch self {
        case .platformUUIDUnavailable:
            return "IOPlatformUUID konnte nicht gelesen werden."
        }
    }
}

public final class ProductionHardwareIdentity: HardwareIdentityProviding {
    public init() {}

    public func deviceIdentifier() throws -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else {
            throw HardwareIdentityError.platformUUIDUnavailable
        }
        defer { IOObjectRelease(service) }

        guard let uuidCF = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            throw HardwareIdentityError.platformUUIDUnavailable
        }
        return uuidCF
    }

    public func userName() -> String {
        NSUserName()
    }
}
