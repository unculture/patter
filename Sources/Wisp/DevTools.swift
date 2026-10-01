import AppKit
import FluidAudio
import ServiceManagement
import SwiftUI

/// Terminal commands for testing the speech models and for rendering the UI to images.
enum DevTools {
    static let flags: Set<String> = [
        "--transcribe", "--snapshot", "--cleanup-test", "--mic-test", "--paste-test", "--unregister-login-item",
        "--help",
    ]

    static func run(_ arguments: [String]) -> Never {
        if arguments.contains("--unregister-login-item") {
            // Removes the login item of this binary, for example one left by a build that ran outside the app bundle.
            do {
                try SMAppService.mainApp.unregister()
                print("Removed the login item for \(Bundle.main.bundlePath)")
            } catch {
                print("Could not remove the login item: \(error.localizedDescription)")
            }
            exit(0)
        }
        if let path = value(after: "--transcribe", in: arguments) {
            let kind = value(after: "--engine", in: arguments).flatMap(EngineKind.init(rawValue:)) ?? .english
            Task {
                await transcribe(URL(fileURLWithPath: path), kind: kind)
                exit(0)
            }
            dispatchMain()
        }
        if let folder = value(after: "--snapshot", in: arguments) {
            MainActor.assumeIsolated {
                snapshot(into: URL(fileURLWithPath: folder))
            }
            exit(0)
        }
        if arguments.contains("--cleanup-test") {
            let models = value(after: "--model", in: arguments).map { [$0] } ?? CleanupModel.presets.map(\.id)
            let glossary = value(after: "--glossary", in: arguments)
            Task { @MainActor in
                await cleanupTest(models: models, glossary: glossary)
                exit(0)
            }
            dispatchMain()
        }
        if arguments.contains("--paste-test") {
            MainActor.assumeIsolated { pasteTest() }
            exit(0)
        }
        if let choice = value(after: "--mic-test", in: arguments) {
            MainActor.assumeIsolated {
                micTest(choice)
            }
            dispatchMain()
        }
        print("""
        Usage:
          Wisp --unregister-login-item
          Wisp --transcribe <audio file> [--engine english|multilingual]
          Wisp --snapshot <folder>
          Wisp --cleanup-test [--model <OpenRouter model ID>] [--glossary <names and terms>]
                              (the key comes from OPENROUTER_API_KEY or the keychain)
          Wisp --mic-test list|auto|system|<device UID>
          Wisp --paste-test
        """)
        exit(2)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func transcribe(_ url: URL, kind: EngineKind) async {
        do {
            let backend = kind.makeBackend()
            let loadStart = Date()
            try await backend.load { _ in }
            print("Loaded \(kind.title) model in \(String(format: "%.1f", Date().timeIntervalSince(loadStart))) s")

            let samples = try AudioConverter().resampleAudioFile(url)
            let audioSeconds = Double(samples.count) / AudioRecorder.sampleRate
            // The first pass includes the one-time Neural Engine setup, so time the second pass.
            _ = try await backend.transcribe(samples)
            let start = Date()
            let text = TextCleanup.clean(try await backend.transcribe(samples))
            let elapsed = Date().timeIntervalSince(start)
            print(String(format: "Audio %.1f s, transcribed in %.2f s (%.0fx real time)", audioSeconds, elapsed, audioSeconds / elapsed))
            print("---")
            print(text)
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }

    @MainActor
    private static func snapshot(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared
        APIKeyStore.readsKeychain = false

        let meter = AudioLevelMeter()
        meter.update(0.85)
        let now = Date()
        let pills: [(String, DictationController.Phase, SpeechEngine.State)] = [
            ("pill-starting", .starting, .ready),
            ("pill-recording", .recording(startedAt: now.addingTimeInterval(-7)), .ready),
            ("pill-polishing", .polishing, .ready),
            ("pill-finished-without-cleanup", .finished(.copied, cleanupFailed: true), .ready),
            ("pill-pasted", .finished(.pasted, cleanupFailed: false), .ready),
            ("pill-no-text-field", .finished(.noTextField, cleanupFailed: false), .ready),
            ("pill-needs-access", .finished(.needsAccess, cleanupFailed: false), .ready),
            ("pill-transcribing", .transcribing, .ready),
            ("pill-downloading", .transcribing, .downloading(0.42)),
            ("pill-finished", .finished(.copied, cleanupFailed: false), .ready),
            ("pill-failed", .failed(message: "Transcription failed", action: .retry), .ready),
            ("pill-microphone", .failed(message: "Microphone access is off", action: .openMicrophoneSettings), .ready),
        ]

        for (name, phase, state) in pills {
            let view = PillView(phase: phase, engineState: state, meter: meter)
                .padding(30)
                .background(Color(white: 0.55))
            // The live waveform smooths its level over time, so render a few frames first.
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            for _ in 0..<30 { _ = renderer.nsImage; RunLoop.main.run(until: Date().addingTimeInterval(0.016)) }
            write(renderer.nsImage, to: folder.appendingPathComponent("\(name).png"))
        }

        let store = TranscriptStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("wisp-snapshot-\(UUID().uuidString).json"))
        for sample in sampleTranscripts(now: now) { store.add(sample) }
        let emptyStore = TranscriptStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("wisp-snapshot-empty-\(UUID().uuidString).json"))
        let engine = SpeechEngine()

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for (suffix, source) in [("", store), ("-empty", emptyStore)] {
                let view = HistoryView(store: source, engine: engine, preferences: .shared)
                    .frame(width: 760, height: 640)
                write(windowImage(of: view, appearance: appearance), to: folder.appendingPathComponent("history-\(name)\(suffix).png"))
            }
        }
        for tab in SettingsView.Tab.allCases {
            let view = SettingsView(
                preferences: .shared, engine: engine, store: store, apiKeys: .shared, initialTab: tab)
            let name = tab == .general ? "settings-general" : "settings-cleanup"
            write(windowImage(of: view, appearance: .aqua, size: NSSize(width: 520, height: 660)),
                  to: folder.appendingPathComponent("\(name).png"))
        }
        print("Wrote snapshots to \(folder.path)")
    }

    @MainActor
    private static func windowImage(
        of view: some View, appearance: NSAppearance.Name, size: NSSize = NSSize(width: 760, height: 640)
    ) -> NSImage? {
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static func write(_ image: NSImage?, to url: URL) {
        guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("Could not render \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }

    private static func sampleTranscripts(now: Date) -> [Transcript] {
        let hour: TimeInterval = 3600
        return [
            Transcript(text: "Can you send me the latest numbers for the Q3 board deck before Thursday? I want to check the churn figures against the forecast.", createdAt: now.addingTimeInterval(-0.3 * hour), duration: 9),
            Transcript(text: "Note to self: the onboarding flow drops people at the payment step.\n\n- Try a shorter form.\n- Move the plan picker earlier.\n- Test it with five users next week.", createdAt: now.addingTimeInterval(-2 * hour), duration: 14, rawText: "Um, note to self, the onboarding flow drops people at the payment step. So try a shorter form, uh, move the plan picker earlier, and test it with, uh, five users next week."),
            Transcript(text: "Thanks for the update. That works for me.", createdAt: now.addingTimeInterval(-26 * hour), duration: 3),
            Transcript(text: "Here is the plan for the launch. First, we freeze the scope on Monday. Second, the design team finishes the marketing pages by Wednesday. Third, we run a full end-to-end test on Thursday with the support team, so that they know the new flows before customers see them. If anything breaks, we move the launch by one week rather than cut corners.", createdAt: now.addingTimeInterval(-28 * hour), duration: 31),
        ]
    }

    // MARK: - Cleanup test

    /// Sample transcripts with the problems that the cleanup must fix.
    static let cleanupSamples: [(label: String, text: String)] = [
        ("self-correction", "Um, so I was thinking we could meet on Tuesday, no wait, Wednesday at, uh, three PM to go over the the launch plan."),
        ("list", "Okay, so for the release we need three things. First, update the change log. Second, uh, bump the version number. And third, send the announcement to the team on slack."),
        ("names", "Can you ask super tab's finance team whether the open router invoice was paid? I think it was sent to the wrong address, sorry, the wrong email."),
        ("misheard", "We should probably put this in the get hub repo and open a poll request so that Kate can review the cold changes before Friday."),
        ("bullets", "Bullet points. Buy milk, call the dentist, renew the passport, book the flights to Lisbon."),
        ("request", "Write an email to Sam saying that the meeting is moved to Friday."),
        ("question", "What do you think about moving the offsite to May? Let me know by Monday."),
    ]

    @MainActor
    private static func cleanupTest(models: [String], glossary: String?) async {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? APIKeyStore.shared.key else {
            print("No key. Save one in Wisp Settings > AI Cleanup, or set OPENROUTER_API_KEY.")
            exit(1)
        }
        let context = TextCleaner.Context(appName: nil, glossary: glossary ?? Preferences.shared.glossary)
        for model in models {
            print("=== \(model)")
            var times: [Double] = []
            for sample in cleanupSamples {
                let cleaner = TextCleaner(client: OpenRouterClient(apiKey: key), model: model)
                let start = Date()
                do {
                    let output = try await cleaner.clean(sample.text, context: context)
                    let elapsed = Date().timeIntervalSince(start)
                    times.append(elapsed)
                    print(String(format: "[%@ %.2f s]\n%@\n", sample.label, elapsed, output))
                } catch {
                    print("[\(sample.label)] failed: \(error.localizedDescription)\n")
                }
            }
            if !times.isEmpty {
                let sorted = times.sorted()
                print(String(format: "Median %.2f s, slowest %.2f s\n", sorted[sorted.count / 2], sorted.last!))
            }
        }
    }

    // MARK: - Paste test

    /// Checks the parts of auto-paste that work without a paste: the access, the V key of the
    /// keyboard layout, the clipboard copy, and the focus check in each open app. Run it through
    /// `open -n Wisp.app --args`, so that macOS uses Wisp's Accessibility access.
    @MainActor
    private static func pasteTest() {
        print("Accessibility access: \(Accessibility.isTrusted ? "on" : "off")")
        print("Key for Command-V: \(Keyboard.keyCode(for: "v").map(String.init) ?? "not found, uses the ANSI V key")")

        // A private pasteboard, so that the test does not change the user's clipboard.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.unculture.Wisp.paste-test"))
        let first = NSPasteboardItem()
        first.setString("plain", forType: .string)
        first.setString("<b>rich</b>", forType: .html)
        let second = NSPasteboardItem()
        second.setString("https://example.com", forType: .URL)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])
        let snapshot = ClipboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("transcript", forType: .string)
        snapshot.restore(to: pasteboard)
        let items = pasteboard.pasteboardItems ?? []
        let restored = items.count == 2
            && items[0].string(forType: .string) == "plain"
            && items[0].string(forType: .html) == "<b>rich</b>"
            && items[1].string(forType: .URL) == "https://example.com"
        print("Clipboard copy and restore: \(restored ? "passed" : "FAILED")")
        pasteboard.releaseGlobally()

        guard Accessibility.isTrusted else { return }
        print("Focused element in each open app:")
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let focus = FocusedElement.inspect(pid: app.processIdentifier)
            let verdict = switch focus.kind {
            case .text: "paste"
            case .unknown: "paste (unknown)"
            case .notText: "copy only"
            }
            print("  \(app.localizedName ?? "?"): \(focus.role) -> \(verdict)")
        }
    }

    // MARK: - Microphone test

    /// Records for two seconds and prints how long the microphone took to deliver audio.
    /// Run it through `open -n Wisp.app --args`, so that macOS uses Wisp's microphone permission.
    private static let testRecorder = AudioRecorder()

    @MainActor
    private static func micTest(_ argument: String) {
        let devices = AudioDevices.inputDevices()
        let systemDefault = AudioDevices.defaultInputDevice()
        for device in devices {
            let kind = device.isBluetooth ? "Bluetooth" : device.isBuiltIn ? "built-in" : "other"
            print("\(device.id == systemDefault?.id ? "*" : " ") \(device.name) [\(kind)] \(device.uid)")
        }
        guard argument != "list" else { exit(0) }

        let (device, canFallBack) = MicrophoneChoice(storedValue: argument).resolve()
        print("Recording from \(device?.name ?? "the system default") for 2 s…")
        let start = Date()
        testRecorder.onReady = { name in
            print(String(format: "Audio arrived after %.0f ms from %@", Date().timeIntervalSince(start) * 1000, name))
        }
        testRecorder.onFailure = { error in print("Failed: \(error.localizedDescription)") }
        testRecorder.start(device: device, canFallBack: canFallBack)
        // The main queue must run freely, because the recorder reports on it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let samples = testRecorder.stop()
            print(String(format: "Captured %.2f s of audio", Double(samples.count) / AudioRecorder.sampleRate))
            exit(0)
        }
    }
}
