import SwiftUI

struct SettingsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case cleanup = "AI Cleanup"
        var id: String { rawValue }
    }

    @ObservedObject var preferences: Preferences
    @ObservedObject var engine: SpeechEngine
    @ObservedObject var store: TranscriptStore
    @ObservedObject var apiKeys: APIKeyStore

    @State private var tab: Tab

    init(
        preferences: Preferences, engine: SpeechEngine, store: TranscriptStore, apiKeys: APIKeyStore,
        initialTab: Tab = .general
    ) {
        self.preferences = preferences
        self.engine = engine
        self.store = store
        self.apiKeys = apiKeys
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.top, 14)
            .padding(.bottom, 4)

            switch tab {
            case .general:
                GeneralSettings(preferences: preferences, store: store)
            case .cleanup:
                CleanupSettings(preferences: preferences, apiKeys: apiKeys)
            }
        }
        .frame(width: 520, height: 660)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: TranscriptStore

    @State private var devices: [AudioInputDevice] = []
    @State private var defaultDevice: AudioInputDevice?
    @State private var confirmingDeleteAll = false
    @State private var accessibilityTrusted = Accessibility.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Open Patter at login", isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.launchAtLogin = $0 }))
                Toggle("Play a sound when the microphone is ready, and when you stop", isOn: $preferences.playSounds)
            }

            Section {
                Toggle("Paste into the text field that has the cursor", isOn: $preferences.autoPaste)
                if preferences.autoPaste {
                    if accessibilityTrusted {
                        Label("Accessibility access is on", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                    } else {
                        HStack {
                            Label {
                                Text("Patter needs Accessibility access to paste")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            }
                            Spacer()
                            Button("Open Privacy Settings") { Accessibility.openPrivacySettings() }
                        }
                    }
                }
            } footer: {
                Text("Patter pastes the transcript, then puts your clipboard back after half a second. If the cursor is not in a text field, Patter copies the transcript to the clipboard. To paste the last transcript again, press \(Shortcut.pasteLastDisplay).")
                    .settingsFootnote()
            }

            Section {
                Picker("Microphone", selection: $preferences.microphone) {
                    Text("Automatic").tag(MicrophoneChoice.automatic)
                    Text("System default (\(defaultDevice?.name ?? "none"))").tag(MicrophoneChoice.systemDefault)
                    Divider()
                    ForEach(devices) { device in
                        Text(device.name).tag(MicrophoneChoice.device(uid: device.uid))
                    }
                    if case .device(let uid) = preferences.microphone, !devices.contains(where: { $0.uid == uid }) {
                        Text("Disconnected device (uses the system default)").tag(preferences.microphone)
                    }
                }
            } footer: {
                Text("Automatic uses the built-in microphone when your default microphone is Bluetooth, for example AirPods. A Bluetooth microphone takes about a second to start, and it lowers the sound quality of the headphones while it is in use. To use your AirPods anyway, choose them here or in the Microphone menu of the menu bar icon.")
                    .settingsFootnote()
            }

            Section {
                Picker("Speech model", selection: $preferences.engine) {
                    ForEach(EngineKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                            Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Both models run on this Mac. Your audio never leaves your computer.")
                    .settingsFootnote()
            }

            Section {
                HStack {
                    Text("\(store.transcripts.count) transcripts saved")
                    Spacer()
                    Button("Delete All…", role: .destructive) { confirmingDeleteAll = true }
                        .disabled(store.transcripts.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            reloadDevices()
            accessibilityTrusted = Accessibility.isTrusted
        }
        // The user turns on the access in System Settings, then comes back to Patter.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = Accessibility.isTrusted
        }
        .confirmationDialog(
            "Delete all \(store.transcripts.count) transcripts?",
            isPresented: $confirmingDeleteAll
        ) {
            Button("Delete All", role: .destructive) { store.deleteAll() }
        } message: {
            Text("You cannot undo this.")
        }
    }

    private func reloadDevices() {
        devices = AudioDevices.inputDevices()
        defaultDevice = AudioDevices.defaultInputDevice()
    }
}

// MARK: - AI cleanup

private struct CleanupSettings: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var apiKeys: APIKeyStore

    @State private var newKey = ""
    @State private var keyCheck: KeyCheck = .none
    @State private var customModel = ""

    private enum KeyCheck: Equatable {
        case none
        case checking
        case passed(String)
        case failed(String)
    }

    private var isCustomModel: Bool {
        !CleanupModel.presets.contains { $0.id == preferences.cleanupModel }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Clean up transcripts with AI", isOn: $preferences.cleanupEnabled)
                    .disabled(!apiKeys.hasKey)
            } footer: {
                Text("An AI model removes filler words, applies your corrections (\"Tuesday, no, Wednesday\"), fixes misheard words and names, sets sentences and paragraphs, and turns spoken lists into bullet points. Patter keeps the original transcript too.")
                    .settingsFootnote()
            }

            Section("OpenRouter API key") {
                if apiKeys.hasKey {
                    HStack {
                        Image(systemName: "key.fill").foregroundStyle(.secondary)
                        Text(apiKeys.maskedKey).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Test") { Task { await testKey() } }
                            .disabled(keyCheck == .checking)
                        Button("Remove", role: .destructive) {
                            apiKeys.delete()
                            preferences.cleanupEnabled = false
                            keyCheck = .none
                        }
                    }
                    keyCheckRow
                } else {
                    HStack {
                        SecureField("Key", text: $newKey, prompt: Text("Paste your key (sk-or-v1-…)"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onSubmit(saveKey)
                        Button("Save", action: saveKey)
                            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Link("Create a key at openrouter.ai/keys", destination: URL(string: "https://openrouter.ai/keys")!)
                        .font(.callout)
                }
            }

            Section {
                Picker("Model", selection: Binding(
                    get: { isCustomModel ? "custom" : preferences.cleanupModel },
                    set: { value in
                        if value == "custom" {
                            customModel = isCustomModel ? preferences.cleanupModel : ""
                            preferences.cleanupModel = customModel.isEmpty ? "custom/model" : customModel
                        } else {
                            preferences.cleanupModel = value
                        }
                    }
                )) {
                    ForEach(CleanupModel.presets) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title)
                            Text(model.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(model.id)
                    }
                    Text("Other OpenRouter model").tag("custom")
                }
                .pickerStyle(.radioGroup)

                if isCustomModel {
                    TextField("Model ID, for example google/gemini-3.5-flash-lite", text: Binding(
                        get: { preferences.cleanupModel == "custom/model" ? "" : preferences.cleanupModel },
                        set: { preferences.cleanupModel = $0.trimmingCharacters(in: .whitespaces) }))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if preferences.glossary.isEmpty {
                        Text("Northwind, OpenRouter, Patter, Sarah Jones…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $preferences.glossary)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                }
                .frame(height: 64)
            } header: {
                Text("Names and terms")
            } footer: {
                Text("Patter gives this list to the model, so that it spells your names, products and jargon correctly.")
                    .settingsFootnote()
            }

            Section {
                Text("Patter sends the transcript text, this list, and the name of the app you dictate into to OpenRouter. Your audio stays on this Mac. If the cleanup fails or takes longer than 8 seconds, Patter copies the transcript without cleanup.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var keyCheckRow: some View {
        switch keyCheck {
        case .none:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking the key").foregroundStyle(.secondary)
            }
        case .passed(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.stopRed)
        }
    }

    private func saveKey() {
        guard apiKeys.save(newKey) else { return }
        newKey = ""
        preferences.cleanupEnabled = true
        Task { await testKey() }
    }

    private func testKey() async {
        guard let key = apiKeys.key else { return }
        keyCheck = .checking
        do {
            let info = try await OpenRouterClient(apiKey: key).checkKey()
            var message = "The key works"
            if let usage = info.usage { message += String(format: ". It used $%.2f of credit so far.", usage) }
            keyCheck = .passed(message)
        } catch {
            keyCheck = .failed(error.localizedDescription)
        }
    }
}

private extension Text {
    func settingsFootnote() -> some View {
        self.font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
