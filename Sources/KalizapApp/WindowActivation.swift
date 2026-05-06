import AppKit

/// Handles the menu-bar-app → regular-app activation dance needed
/// to bring Settings or other windows to the foreground.
///
/// Stays in `.regular` mode while any window is visible, then reverts
/// to `.accessory` (menu-bar-only) once all windows are closed.
@MainActor
enum WindowActivation {
    private static var observer: NSObjectProtocol?

    static func activateTemporarily(perform action: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        action()
        DispatchQueue.main.async {
            NSApp.activate()
            for window in NSApp.windows where window.isVisible {
                window.orderFrontRegardless()
            }
        }
        observeWindowClose()
    }

    private static func observeWindowClose() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && !$0.className.contains("StatusBar") }
                guard !hasVisibleWindows else { return }
                NSApp.setActivationPolicy(.accessory)
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                    observer = nil
                }
            }
        }
    }
}
