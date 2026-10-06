import AppKit
import SwiftUI

/// Hosts ``PillView`` in a borderless, non-activating panel that floats above
/// every app near the mouse cursor.
@MainActor
final class PillController {
    private let panel: NSPanel
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: PillView().environmentObject(appState))
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func show(mode: DictationMode) {
        // Boss-key active: stay invisible until the next explicit run.
        if appState.stealthHidden { return }
        position()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
    }

    /// Re-render the SwiftUI content by nudging the environment object. State is
    /// already observed, so this only needs to reposition if the size changed.
    func update() {
        position()
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    /// Place the pill just below-right of the cursor, clamped to the screen.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 16, y: mouse.y - size.height - 16)

        origin.x = min(max(visible.minX + 8, origin.x), visible.maxX - size.width - 8)
        origin.y = min(max(visible.minY + 8, origin.y), visible.maxY - size.height - 8)

        panel.setFrameOrigin(origin)
    }
}
