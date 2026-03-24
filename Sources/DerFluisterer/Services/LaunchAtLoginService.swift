import ServiceManagement

public struct LaunchAtLoginService: LaunchAtLoginProtocol {
    public init() {}

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
