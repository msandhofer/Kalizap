import AppKit
import SwiftUI
import DerFluisterer

/// Schwebendes Overlay oben Mitte mit einem animierten Frequenz-Spektrum.
/// Wird durch DictationPipeline über das SpectrumOverlayPresenting-Protokoll
/// gesteuert: show(pipeline:) bei Aufnahme-Start, hide() bei Stop.
@MainActor
final class SpectrumOverlayWindow: SpectrumOverlayPresenting {
    static let shared = SpectrumOverlayWindow()

    private var window: NSPanel?

    private init() {}

    func show(pipeline: DictationPipeline) {
        if let existing = window {
            existing.close()
            window = nil
        }
        guard let screen = NSScreen.main else { return }

        let content = SpectrumOverlayContent(pipeline: pipeline)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame.size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - hostingView.fittingSize.width / 2
        let y = screenFrame.maxY - hostingView.fittingSize.height - 16
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.window = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = window else { return }
        self.window = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.close() }
        })
    }
}

private struct SpectrumOverlayContent: View {
    @Bindable var pipeline: DictationPipeline

    var body: some View {
        SpectrumView(bands: pipeline.spectrumBands)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.quaternary, lineWidth: 0.5))
    }
}
