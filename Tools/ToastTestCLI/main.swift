import AppKit
import SwiftUI

// MARK: - Toast (self-contained copy for testing)

@MainActor
enum TestToast {
    private static var currentWindow: NSWindow?

    static func show(
        message: String,
        systemImage: String = "exclamationmark.triangle.fill",
        displayDuration: TimeInterval = 2.0,
        fadeDuration: TimeInterval = 2.0
    ) {
        currentWindow?.close()
        currentWindow = nil

        guard let screen = NSScreen.main else {
            print("ERROR: No main screen found")
            return
        }

        let hostingView = NSHostingView(rootView: ToastContent(message: message, systemImage: systemImage))
        hostingView.frame.size = hostingView.fittingSize
        print("Toast size: \(hostingView.fittingSize)")

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: hostingView.fittingSize.width, height: hostingView.fittingSize.height),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.contentView = hostingView
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - hostingView.fittingSize.width / 2
        let y = screenFrame.maxY - hostingView.fittingSize.height - 16
        window.setFrameOrigin(NSPoint(x: x, y: y))
        print("Toast position: x=\(x) y=\(y), screen=\(screenFrame)")

        window.alphaValue = 0
        window.orderFrontRegardless()
        currentWindow = window

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }

        print("Toast shown — waiting \(displayDuration)s then fading \(fadeDuration)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeDuration
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.close()
                if currentWindow === window {
                    currentWindow = nil
                }
                print("Toast dismissed")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
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

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.regular)

print("ToastTestCLI — showing toast in 1 second...")
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    TestToast.show(message: "API-Key fehlt — Text wird ohne Korrektur eingefügt.")
}

app.run()
