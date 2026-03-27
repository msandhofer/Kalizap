import AppKit

/// Handles the menu-bar-app → regular-app activation dance needed
/// to bring Settings or other windows to the foreground.
enum WindowActivation {
    static func activateTemporarily(perform action: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        action()
        DispatchQueue.main.async {
            NSApp.activate()
            for window in NSApp.windows where window.isVisible {
                window.orderFrontRegardless()
            }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
