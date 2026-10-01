import AppKit
import SwiftUI

/// Shows a SwiftUI view in a standard window. While any Patter window is open, Patter shows in the
/// Dock and the app switcher. When the last one closes, Patter goes back to the menu bar only.
@MainActor
class AppWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeContent: () -> AnyView
    private let title: String
    private let size: NSSize
    private let resizable: Bool

    init(title: String, size: NSSize, resizable: Bool, content: @escaping () -> AnyView) {
        self.title = title
        self.size = size
        self.resizable = resizable
        self.makeContent = content
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let othersOpen = NSApp.windows.contains {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
        }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
    }

    private func makeWindow() -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: makeContent())
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("Patter\(title.replacingOccurrences(of: " ", with: ""))Window")
        return window
    }
}

@MainActor
final class HistoryWindowController: AppWindowController {
    init(store: TranscriptStore, engine: SpeechEngine, preferences: Preferences, openSettings: @escaping () -> Void) {
        super.init(title: "Patter", size: NSSize(width: 760, height: 640), resizable: true) {
            AnyView(HistoryView(
                store: store, engine: engine, preferences: preferences, openSettings: openSettings)
                .frame(minWidth: 560, minHeight: 440))
        }
    }
}

@MainActor
final class SettingsWindowController: AppWindowController {
    init(preferences: Preferences, engine: SpeechEngine, store: TranscriptStore, apiKeys: APIKeyStore) {
        super.init(title: "Patter Settings", size: NSSize(width: 520, height: 660), resizable: false) {
            AnyView(SettingsView(preferences: preferences, engine: engine, store: store, apiKeys: apiKeys))
        }
    }
}
