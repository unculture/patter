import AppKit
import Combine

/// The menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let dictation: DictationController
    private let engine: SpeechEngine
    private let store: TranscriptStore
    private let preferences: Preferences
    private let apiKeys: APIKeyStore
    private let openHistory: () -> Void
    private let openSettings: () -> Void
    private var subscriptions = Set<AnyCancellable>()

    init(
        dictation: DictationController,
        engine: SpeechEngine,
        store: TranscriptStore,
        preferences: Preferences,
        apiKeys: APIKeyStore,
        openHistory: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.dictation = dictation
        self.engine = engine
        self.store = store
        self.preferences = preferences
        self.apiKeys = apiKeys
        self.openHistory = openHistory
        self.openSettings = openSettings
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        dictation.$phase
            .sink { [weak self] phase in self?.updateIcon(for: phase) }
            .store(in: &subscriptions)
    }

    private func updateIcon(for phase: DictationController.Phase) {
        guard let button = statusItem.button else { return }
        let symbol: String
        let tint: NSColor?
        switch phase {
        case .starting, .recording:
            symbol = "waveform.circle.fill"
            tint = .systemRed
        case .transcribing, .polishing:
            symbol = "waveform.circle"
            tint = nil
        case .idle, .finished, .failed:
            symbol = "waveform"
            tint = nil
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Patter")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tint
    }

    // The menu is built each time it opens, so that it always shows the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let dictateTitle: String
        let busy = dictation.phase == .transcribing || dictation.phase == .polishing
        if dictation.isRecording {
            dictateTitle = "Stop Dictation"
        } else if busy {
            dictateTitle = "Transcribing…"
        } else {
            dictateTitle = "Start Dictation"
        }
        let dictate = item(dictateTitle, action: #selector(toggleDictation))
        dictate.keyEquivalent = "r"
        dictate.keyEquivalentModifierMask = [.control, .shift]
        dictate.isEnabled = !busy
        menu.addItem(dictate)

        let copyLast = item("Copy Last Transcript", action: #selector(copyLastTranscript))
        copyLast.isEnabled = store.latest != nil
        menu.addItem(copyLast)
        if preferences.autoPaste {
            let pasteLast = item("Paste Last Transcript", action: #selector(pasteLastTranscript))
            pasteLast.keyEquivalent = "v"
            pasteLast.keyEquivalentModifierMask = [.control, .command]
            pasteLast.isEnabled = store.latest != nil
            menu.addItem(pasteLast)
        }

        let recent = Array(store.transcripts.prefix(3))
        if !recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Recent"))
            for transcript in recent {
                let entry = item(Self.preview(of: transcript.text), action: #selector(copyTranscript(_:)))
                entry.representedObject = transcript.id
                entry.toolTip = "Click to copy"
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Open Patter…", action: #selector(showHistory), key: "o"))

        menu.addItem(.separator())
        let cleanup = item(
            apiKeys.hasKey ? "AI Cleanup" : "AI Cleanup (add a key in Settings)",
            action: #selector(toggleCleanup))
        cleanup.state = dictation.cleanupAvailable ? .on : .off
        cleanup.isEnabled = apiKeys.hasKey
        menu.addItem(cleanup)

        let autoPaste = item(
            preferences.autoPaste && !Accessibility.isTrusted ? "Auto-Paste (allow access in Settings)" : "Auto-Paste",
            action: #selector(toggleAutoPaste))
        autoPaste.state = preferences.autoPaste ? .on : .off
        autoPaste.toolTip = "Paste each transcript into the text field that has the cursor"
        menu.addItem(autoPaste)

        let microphone = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        microphone.submenu = microphoneMenu()
        menu.addItem(microphone)
        menu.addItem(item("Settings…", action: #selector(showSettings), key: ","))

        menu.addItem(.separator())
        let status = NSMenuItem(title: engine.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if case .failed = engine.state {
            menu.addItem(item("Retry Model Download", action: #selector(retryModel)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit Patter", action: #selector(quit), key: "q"))
    }

    private func microphoneMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let current = preferences.microphone
        let systemDefault = AudioDevices.defaultInputDevice()

        let automatic = item("Automatic", action: #selector(selectMicrophone(_:)))
        automatic.representedObject = MicrophoneChoice.automatic.storedValue
        automatic.state = current == .automatic ? .on : .off
        automatic.toolTip = "The built-in microphone when your default microphone is Bluetooth"
        menu.addItem(automatic)

        let followSystem = item(
            "System Default (\(systemDefault?.name ?? "none"))", action: #selector(selectMicrophone(_:)))
        followSystem.representedObject = MicrophoneChoice.systemDefault.storedValue
        followSystem.state = current == .systemDefault ? .on : .off
        menu.addItem(followSystem)

        menu.addItem(.separator())
        for device in AudioDevices.inputDevices() {
            let choice = MicrophoneChoice.device(uid: device.uid)
            let entry = item(device.name, action: #selector(selectMicrophone(_:)))
            entry.representedObject = choice.storedValue
            entry.state = current == choice ? .on : .off
            if device.isBluetooth { entry.toolTip = "Bluetooth: takes about a second to start" }
            menu.addItem(entry)
        }
        return menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private static func preview(of text: String) -> String {
        let limit = 48
        return text.count > limit ? text.prefix(limit).trimmingCharacters(in: .whitespaces) + "…" : text
    }

    @objc private func toggleDictation() { dictation.toggle() }
    @objc private func showHistory() { openHistory() }
    @objc private func retryModel() { engine.retry() }
    @objc private func showSettings() { openSettings() }
    @objc private func toggleCleanup() { preferences.cleanupEnabled.toggle() }
    @objc private func toggleAutoPaste() { preferences.autoPaste.toggle() }
    @objc private func pasteLastTranscript() { dictation.pasteLastTranscript() }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let stored = sender.representedObject as? String else { return }
        preferences.microphone = MicrophoneChoice(storedValue: stored)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func copyLastTranscript() {
        if let latest = store.latest { Clipboard.copy(latest.text) }
    }

    @objc private func copyTranscript(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let transcript = store.transcripts.first(where: { $0.id == id })
        else { return }
        Clipboard.copy(transcript.text)
    }
}
