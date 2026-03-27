import AppKit
import SwiftUI

@MainActor
class ClipboardPanel {
    private var panel: NSPanel?
    var onDismiss: (() -> Void)?
    private var clickMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(content: some View) {
        if isVisible {
            dismiss()
        } else {
            show(content: content)
        }
    }

    func show(content: some View) {
        dismiss()

        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 420
        let height: CGFloat = 500
        let x = screen.frame.midX - width / 2
        let y = screen.frame.midY - height / 2 + 100 // Slightly above center

        let rect = NSRect(x: x, y: y, width: width, height: height)

        let p = NSPanel(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = false

        // Hide traffic lights
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true

        let hostView = NSHostingView(rootView:
            content
                .ignoresSafeArea()
                .frame(width: width, height: height)
        )
        p.contentView = hostView

        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }

        panel = p

        // Click-outside dismissal
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismiss()
        }
    }

    func dismiss() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        guard let p = panel else { return }
        panel = nil
        let action = onDismiss
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            p.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                p.orderOut(nil)
                action?()
            }
        })
    }
}
