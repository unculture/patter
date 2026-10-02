import AppKit
import Carbon.HIToolbox
import Combine

/// What a shortcut in the settings does.
enum ShortcutAction: CaseIterable, Identifiable {
    /// Press the shortcut to start dictation, and press it again to stop.
    case dictation

    var id: Self { self }

    var title: String {
        switch self {
        case .dictation: "Start and stop dictation"
        }
    }

    /// For messages, for example "⌃⇧R is already the dictation shortcut".
    var shortName: String {
        switch self {
        case .dictation: "dictation shortcut"
        }
    }
}

/// Registers the shortcuts from the settings with the system, and records new shortcuts in the
/// settings window.
@MainActor
final class ShortcutController: ObservableObject {
    /// The actions whose shortcut the system refused, for example because another app uses it.
    @Published private(set) var unavailable: Set<ShortcutAction> = []
    /// The action that gets the next key press in the settings window as its new shortcut.
    @Published private(set) var recording: ShortcutAction?
    /// The modifier keys (Carbon flags) that the user holds down while Patter records.
    @Published private(set) var heldModifiers = 0
    /// Why Patter did not take the last key press as the new shortcut.
    @Published private(set) var rejection: String?

    private let preferences: Preferences
    private weak var dictation: DictationController?
    private var hotKeys: [ShortcutAction: HotKey] = [:]
    private var pasteHotKey: HotKey?
    private var keyMonitor: Any?
    private var subscriptions = Set<AnyCancellable>()

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Registers the shortcuts, and registers them again each time the settings change.
    func start(dictation: DictationController) {
        self.dictation = dictation
        // A @Published publisher sends the new value before the property changes: use the value it sends.
        preferences.$dictationShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in self?.register(.dictation, shortcut) }
            .store(in: &subscriptions)
        preferences.$autoPaste
            .removeDuplicates()
            .sink { [weak self] enabled in self?.registerPasteLast(enabled) }
            .store(in: &subscriptions)
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        switch action {
        case .dictation: preferences.dictationShortcut
        }
    }

    /// Nil removes the shortcut.
    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        switch action {
        case .dictation: preferences.dictationShortcut = shortcut
        }
    }

    // MARK: - Recording

    /// Takes the next key press in Patter as the new shortcut for the action. While Patter records,
    /// it turns off its shortcuts, so that the current shortcut does not start a dictation.
    func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        hotKeys.removeAll()
        pasteHotKey = nil
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard recording != nil else { return }
        recording = nil
        heldModifiers = 0
        rejection = nil
        registerAll()
    }

    /// Returns true if the key press belongs to the recording, so that the window does not get it.
    private func handle(_ event: NSEvent) -> Bool {
        guard let action = recording else { return false }
        let candidate = Shortcut(event: event)
        if event.type == .flagsChanged {
            heldModifiers = candidate.modifiers
            return false
        }
        if event.isARepeat { return true }
        if candidate.keyCode == kVK_Escape && candidate.modifiers == 0 {
            stopRecording()
            return true
        }
        if let problem = problem(with: candidate, for: action) {
            rejection = problem
            NSSound.beep()
            return true
        }
        // Change the setting first: its publisher does not register the shortcut while Patter records.
        setShortcut(candidate, for: action)
        stopRecording()
        return true
    }

    private func problem(with candidate: Shortcut, for action: ShortcutAction) -> String? {
        if !candidate.isUsable {
            return "Add Control or Command, or use a function key such as F5."
        }
        if candidate == .pasteLast {
            return "\(candidate.display) pastes the last transcript. Type a different shortcut."
        }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && shortcut(for: $0) == candidate }) {
            return "\(candidate.display) is already the \(other.shortName)."
        }
        return nil
    }

    // MARK: - Registration

    private func registerAll() {
        guard dictation != nil else { return }
        for action in ShortcutAction.allCases { register(action, shortcut(for: action)) }
        registerPasteLast(preferences.autoPaste)
    }

    private func register(_ action: ShortcutAction, _ shortcut: Shortcut?) {
        // Unregister the old shortcut first, so that the system accepts the same keys again.
        hotKeys[action] = nil
        guard recording == nil else { return }
        guard let shortcut else {
            unavailable.remove(action)
            return
        }
        let hotKey: HotKey?
        switch action {
        case .dictation:
            hotKey = HotKey(shortcut) { [weak self] in
                MainActor.assumeIsolated { self?.dictation?.toggle() }
            }
        }
        hotKeys[action] = hotKey
        if hotKey == nil {
            unavailable.insert(action)
        } else {
            unavailable.remove(action)
        }
    }

    /// ⌃⌘V pastes the last transcript. Patter holds this shortcut only while auto-paste is on.
    private func registerPasteLast(_ enabled: Bool) {
        pasteHotKey = nil
        guard enabled, recording == nil else { return }
        pasteHotKey = HotKey(.pasteLast) { [weak self] in
            MainActor.assumeIsolated { self?.dictation?.pasteLastTranscript() }
        }
        if pasteHotKey == nil { NSLog("Patter: another app uses \(Shortcut.pasteLast.display)") }
    }
}
