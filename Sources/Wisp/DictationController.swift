import AppKit
import os

/// The dictation cycle: record, transcribe, clean up, copy to the clipboard, save.
@MainActor
final class DictationController: ObservableObject {
    enum FailureAction: Equatable {
        case none
        case retry
        case openMicrophoneSettings
    }

    enum Phase: Equatable {
        case idle
        /// The microphone is starting. Speech is not captured yet.
        case starting
        case recording(startedAt: Date)
        case transcribing
        /// The AI cleanup is running.
        case polishing
        case finished(cleanupFailed: Bool)
        case failed(message: String, action: FailureAction)
    }

    @Published private(set) var phase: Phase = .idle

    let recorder = AudioRecorder()
    private let engine: SpeechEngine
    private let store: TranscriptStore
    private let preferences: Preferences
    private let apiKeys: APIKeyStore
    private let log = Logger(subsystem: "com.unculture.Wisp", category: "dictation")

    private var lastToggle = Date.distantPast
    private var dismissTask: Task<Void, Never>?
    private var cleanupTask: Task<String, Error>?
    private var cleanupSkipped = false
    /// The app that was in front when the dictation started. The AI cleanup uses its name.
    private var targetAppName: String?
    /// Changes on each stop or cancel, so that a late result from a cancelled cycle is dropped.
    private var cycle = 0
    /// A recording whose transcription failed, kept in memory so that the user can retry it.
    private var failedRecording: (samples: [Float], startedAt: Date)?

    /// Recordings shorter than this are discarded as accidental key presses.
    private let minimumDuration: TimeInterval = 0.3

    init(engine: SpeechEngine, store: TranscriptStore, preferences: Preferences, apiKeys: APIKeyStore) {
        self.engine = engine
        self.store = store
        self.preferences = preferences
        self.apiKeys = apiKeys
        recorder.onReady = { [weak self] _ in
            MainActor.assumeIsolated { self?.microphoneReady() }
        }
        recorder.onFailure = { [weak self] error in
            MainActor.assumeIsolated { self?.handleRecorderFailure(error) }
        }
    }

    var isRecording: Bool {
        switch phase {
        case .starting, .recording: true
        default: false
        }
    }

    var cleanupAvailable: Bool { preferences.cleanupEnabled && apiKeys.hasKey }

    func toggle() {
        // Ignore key repeat and accidental double presses.
        let now = Date()
        guard now.timeIntervalSince(lastToggle) > 0.25 else { return }
        lastToggle = now

        switch phase {
        case .starting: cancel()
        case .recording: stop()
        case .transcribing, .polishing: break
        case .idle, .finished, .failed: start()
        }
    }

    func start() {
        guard !isRecording else { return }
        switch Microphone.status {
        case .authorized:
            beginRecording()
        case .notDetermined:
            Task {
                if await Microphone.requestAccess() {
                    beginRecording()
                } else {
                    show(.failed(message: "Microphone access is off", action: .openMicrophoneSettings))
                }
            }
        default:
            show(.failed(message: "Microphone access is off", action: .openMicrophoneSettings))
        }
    }

    func stop() {
        switch phase {
        case .starting:
            cancel()
        case .recording(let startedAt):
            let samples = recorder.stop()
            Sounds.playStop()
            cycle += 1
            guard Double(samples.count) / AudioRecorder.sampleRate >= minimumDuration else {
                phase = .idle
                return
            }
            transcribe(samples, startedAt: startedAt)
        default:
            break
        }
    }

    func cancel() {
        cycle += 1
        if isRecording { _ = recorder.stop() }
        cleanupTask?.cancel()
        dismissTask?.cancel()
        phase = .idle
    }

    /// Copies the transcript without waiting for the AI cleanup.
    func skipCleanup() {
        guard phase == .polishing else { return }
        cleanupSkipped = true
        cleanupTask?.cancel()
    }

    func retryFailedRecording() {
        guard let failedRecording else { return }
        self.failedRecording = nil
        cycle += 1
        transcribe(failedRecording.samples, startedAt: failedRecording.startedAt)
    }

    func openMicrophoneSettings() {
        Microphone.openPrivacySettings()
        phase = .idle
    }

    private func beginRecording() {
        dismissTask?.cancel()
        let front = NSWorkspace.shared.frontmostApplication
        targetAppName = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front?.localizedName

        let (device, canFallBack) = preferences.microphone.resolve()
        phase = .starting
        recorder.start(device: device, canFallBack: canFallBack)
    }

    /// The start sound plays only now, so that it tells the user when to speak.
    private func microphoneReady() {
        guard phase == .starting else { return }
        Sounds.playStart()
        phase = .recording(startedAt: Date())
    }

    private func transcribe(_ samples: [Float], startedAt: Date) {
        let current = cycle
        let duration = Double(samples.count) / AudioRecorder.sampleRate
        phase = .transcribing

        Task {
            let raw: String
            do {
                raw = TextCleanup.clean(try await engine.transcribe(samples))
            } catch {
                guard current == cycle else { return }
                failedRecording = (samples, startedAt)
                show(.failed(message: "Transcription failed", action: .retry))
                log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard current == cycle else { return }
            guard !raw.isEmpty else {
                show(.failed(message: "No speech detected", action: .none))
                return
            }

            var text = raw
            var cleanupFailed = false
            if cleanupAvailable, let key = apiKeys.key {
                phase = .polishing
                (text, cleanupFailed) = await polish(raw, apiKey: key)
                guard current == cycle else { return }
            }

            Clipboard.copy(text)
            store.add(Transcript(
                text: text, createdAt: startedAt, duration: duration,
                rawText: text == raw ? nil : raw))
            show(.finished(cleanupFailed: cleanupFailed))
        }
    }

    /// Returns the cleaned text, or the original text and true if the cleanup failed.
    private func polish(_ raw: String, apiKey: String) async -> (String, Bool) {
        let cleaner = TextCleaner(client: OpenRouterClient(apiKey: apiKey), model: preferences.cleanupModel)
        let context = TextCleaner.Context(appName: targetAppName, glossary: preferences.glossary)
        cleanupSkipped = false
        let started = Date()
        let task = Task { try await cleaner.clean(raw, context: context) }
        cleanupTask = task
        defer { cleanupTask = nil }
        do {
            let cleaned = try await task.value
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            log.notice("Cleanup with \(self.preferences.cleanupModel, privacy: .public) took \(elapsed) ms")
            return (cleaned, false)
        } catch {
            if cleanupSkipped { return (raw, false) }
            log.error("Cleanup failed: \(error.localizedDescription, privacy: .public)")
            return (raw, true)
        }
    }

    private func handleRecorderFailure(_ error: Error) {
        switch phase {
        case .starting:
            _ = recorder.stop()
            cycle += 1
            show(.failed(message: error.localizedDescription, action: .none))
        case .recording(let startedAt):
            let samples = recorder.stop()
            cycle += 1
            if Double(samples.count) / AudioRecorder.sampleRate >= minimumDuration {
                transcribe(samples, startedAt: startedAt)
            } else {
                show(.failed(message: error.localizedDescription, action: .none))
            }
        default:
            break
        }
    }

    /// Shows a result in the indicator for a short time, then hides it.
    private func show(_ result: Phase) {
        phase = result
        dismissTask?.cancel()
        let seconds: Double
        switch result {
        case .failed(_, let action): seconds = action == .none ? 2.5 : 6
        case .finished(let cleanupFailed): seconds = cleanupFailed ? 2.5 : 1.4
        default: seconds = 1.4
        }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, phase == result else { return }
            phase = .idle
        }
    }
}
