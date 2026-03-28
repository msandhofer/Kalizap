import AppKit
import SwiftUI

/// A floating toast notification at the top of the screen.
/// Appears for `displayDuration`, then fades out over `fadeDuration`.
@MainActor
enum ToastWindow {
    private static var currentWindow: NSWindow?

    static func show(
        message: String,
        systemImage: String = "exclamationmark.triangle.fill",
        displayDuration: TimeInterval = 2.0,
        fadeDuration: TimeInterval = 2.0
    ) {
        // Dismiss any existing toast
        currentWindow?.close()
        currentWindow = nil

        guard let screen = NSScreen.main else { return }

        let hostingView = NSHostingView(rootView: ToastContent(message: message, systemImage: systemImage))
        hostingView.frame.size = hostingView.fittingSize

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: hostingView.fittingSize.width, height: hostingView.fittingSize.height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = true
        window.contentView = hostingView
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Position: top center of screen
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - hostingView.fittingSize.width / 2
        let y = screenFrame.maxY - hostingView.fittingSize.height - 16
        window.setFrameOrigin(NSPoint(x: x, y: y))

        window.alphaValue = 0
        window.orderFrontRegardless()
        currentWindow = window

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }

        // After displayDuration, fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeDuration
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.close()
                if currentWindow === window {
                    currentWindow = nil
                }
            })
        }
    }
}

private struct ToastContent: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(.body, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 0.5))
    }
}
