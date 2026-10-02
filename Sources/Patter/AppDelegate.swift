import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences.shared
    private let store = TranscriptStore()
    private let engine = SpeechEngine()
    private let apiKeys = APIKeyStore.shared
    private lazy var dictation = DictationController(
        engine: engine, store: store, preferences: preferences, apiKeys: apiKeys)
    private lazy var history = HistoryWindowController(
        store: store, engine: engine, preferences: preferences,
        openSettings: { [weak self] in self?.settings.show() })
    private lazy var settings = SettingsWindowController(
        preferences: preferences, engine: engine, store: store, apiKeys: apiKeys, shortcuts: shortcuts)
    private lazy var shortcuts = ShortcutController(preferences: preferences)
    private var indicator: IndicatorController?
    private var statusItem: StatusItemController?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()

        engine.load(preferences.engine)
        preferences.$engine
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] kind in self?.engine.load(kind) }
            .store(in: &subscriptions)

        indicator = IndicatorController(dictation: dictation, engine: engine)
        statusItem = StatusItemController(
            dictation: dictation, engine: engine, store: store, preferences: preferences, apiKeys: apiKeys,
            openHistory: { [weak self] in self?.history.show() },
            openSettings: { [weak self] in self?.settings.show() })
        Task { await ReasoningCatalog.shared.preload() }

        shortcuts.start(dictation: dictation)
        if !shortcuts.unavailable.isEmpty { warnShortcutsUnavailable() }

        NSLog("Patter: Accessibility access is \(Accessibility.isTrusted ? "on" : "off")")
        if preferences.autoPaste && !preferences.askedForAccessibility { askForAccessibility() }
        preferences.$autoPaste
            .dropFirst()
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.askForAccessibility() }
            .store(in: &subscriptions)

        if !preferences.hasLaunchedBefore {
            preferences.hasLaunchedBefore = true
            preferences.launchAtLogin = true
            history.show()
            if Microphone.status == .notDetermined {
                Task { _ = await Microphone.requestAccess() }
            }
        }
    }

    /// Opening Patter again from Finder or Spotlight while it runs shows the transcripts window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        history.show()
        return true
    }

    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    private func askForAccessibility() {
        guard !Accessibility.isTrusted else { return }
        preferences.askedForAccessibility = true
        Accessibility.requestAccess()
    }

    private func warnShortcutsUnavailable() {
        let taken = ShortcutAction.allCases
            .filter(shortcuts.unavailable.contains)
            .compactMap(shortcuts.shortcut(for:))
            .map(\.display)
        guard !taken.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = taken.count == 1
            ? "The shortcut \(taken[0]) is not available"
            : "The shortcuts \(taken.joined(separator: " and ")) are not available"
        alert.informativeText = (taken.count == 1 ? "Another app uses it." : "Other apps use them.")
            + " Choose a different shortcut in Settings, or quit the other app and open Patter again. You can also start dictation from the Patter menu bar icon."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn { settings.show() }
    }
}

/// The menu bar menus for when the transcripts window is open. Without them, ⌘C, ⌘W and ⌘Q do not work.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Patter", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Patter", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Patter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Patter")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu: editMenu, title: "Edit")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
