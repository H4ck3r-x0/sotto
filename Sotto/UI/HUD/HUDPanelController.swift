import AppKit
import SwiftUI

/// A floating, non-activating panel pinned to the bottom-center of the
/// screen — visible above full-screen apps, never steals focus.
@MainActor
final class HUDPanelController {
    private let panel: NSPanel

    init(dictation: DictationController) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let host = NSHostingView(rootView: HUDView(dictation: dictation))
        panel.contentView = host
        panel.setContentSize(.init(width: 640, height: 210))
    }

    private var isShown = false

    func setVisible(_ visible: Bool) {
        guard visible != isShown else { return }
        isShown = visible

        if visible {
            position()
            let target = panel.frame.origin
            panel.alphaValue = 0
            panel.setFrameOrigin(.init(x: target.x, y: target.y - 16))
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrameOrigin(target)
            }
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                // Runs on the main thread; only hide if a new show hasn't
                // started during the fade.
                MainActor.assumeIsolated { [weak self] in
                    guard let self, !self.isShown else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }

    private func position() {
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        let x = screen.visibleFrame.midX - frame.width / 2
        let y = screen.visibleFrame.minY + 60
        panel.setFrameOrigin(.init(x: x, y: y))
    }
}
