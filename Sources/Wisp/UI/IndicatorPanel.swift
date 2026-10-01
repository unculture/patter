import AppKit
import Combine
import SwiftUI

/// A borderless panel that floats above all windows and Spaces and never takes keyboard focus,
/// so that the app you dictate into stays active.
private final class IndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on the stop button work even though the panel is never the key window.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class IndicatorController {
    private let panel: IndicatorPanel
    private let dictation: DictationController
    private var subscription: AnyCancellable?
    private var hideWork: DispatchWorkItem?

    init(dictation: DictationController, engine: SpeechEngine) {
        self.dictation = dictation
        panel = IndicatorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = FirstClickHostingView(
            rootView: IndicatorView(dictation: dictation, engine: engine))

        subscription = dictation.$phase
            .map { $0 != .idle }
            .removeDuplicates()
            .sink { [weak self] visible in self?.setVisible(visible) }
    }

    private func setVisible(_ visible: Bool) {
        hideWork?.cancel()
        if visible {
            if !panel.isVisible { placeOnActiveScreen() }
            panel.orderFrontRegardless()
        } else {
            // Wait for the SwiftUI exit animation before the panel goes away.
            let work = DispatchWorkItem { [weak self] in
                guard let self, dictation.phase == .idle else { return }
                panel.orderOut(nil)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    /// Bottom center of the screen that has the mouse pointer, just above the Dock.
    private func placeOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.minY + 8))
    }
}
