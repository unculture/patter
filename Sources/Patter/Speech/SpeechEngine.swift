import FluidAudio
import Foundation

/// One local speech model. Both backends run on the Neural Engine through Core ML.
protocol TranscriptionBackend: Sendable {
    func load(progress: @escaping @Sendable (DownloadProgress) -> Void) async throws
    /// Transcribes 16 kHz mono samples.
    func transcribe(_ samples: [Float]) async throws -> String
}

/// Parakeet Unified 0.6B: English, with punctuation and capitalization.
final class EnglishBackend: TranscriptionBackend {
    private let manager = UnifiedAsrManager()

    func load(progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        try await manager.loadModels(progressHandler: progress)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await manager.transcribe(samples)
    }
}

/// Parakeet Ultra 0.6B: 25 European languages.
final class MultilingualBackend: TranscriptionBackend {
    private let manager = AsrManager(config: .default)

    func load(progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let models = try await AsrModels.downloadAndLoad(version: .ultra, progressHandler: progress)
        try await manager.loadModels(models)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(samples, decoderState: &state).text
    }
}

extension EngineKind {
    func makeBackend() -> TranscriptionBackend {
        switch self {
        case .english: EnglishBackend()
        case .multilingual: MultilingualBackend()
        }
    }

    var downloadSize: String {
        switch self {
        case .english: "about 600 MB"
        case .multilingual: "about 650 MB"
        }
    }
}

/// Downloads, loads and warms up the selected model, and transcribes with it.
@MainActor
final class SpeechEngine: ObservableObject {
    enum State: Equatable {
        /// Loading has started. The state changes to downloading only if the model is not on disk.
        case idle
        case downloading(Double)
        /// The files are on disk. Core ML loads the model and sets it up for the Neural Engine.
        case preparing
        case ready
        case failed(String)

        /// The model is not on disk yet, so a recording cannot be transcribed for minutes, or at all.
        var blocksDictation: Bool {
            switch self {
            case .downloading, .failed: true
            case .idle, .preparing, .ready: false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var kind: EngineKind = .english

    private var loadTask: Task<TranscriptionBackend, Error>?
    private var generation = 0

    var isReady: Bool { state == .ready }

    init() {}

    /// For the snapshots of the developer tools.
    init(snapshotState: State) {
        state = snapshotState
    }

    func load(_ kind: EngineKind) {
        self.kind = kind
        generation += 1
        let current = generation
        state = .idle

        let task = Task<TranscriptionBackend, Error> {
            let backend = kind.makeBackend()
            try await backend.load { [weak self] progress in
                Task { @MainActor in self?.report(progress, generation: current) }
            }
            // One short pass makes Core ML finish its Neural Engine setup now,
            // so that the first real dictation is fast.
            _ = try? await backend.transcribe([Float](repeating: 0, count: 16_000))
            return backend
        }
        loadTask = task

        Task {
            do {
                _ = try await task.value
                if current == generation { state = .ready }
            } catch {
                if current == generation { state = .failed(error.localizedDescription) }
            }
        }
    }

    func retry() {
        load(kind)
    }

    /// Waits for the model if it is still loading. If an earlier load failed, it tries again first.
    func transcribe(_ samples: [Float]) async throws -> String {
        if case .failed = state { load(kind) }
        guard let loadTask else {
            load(kind)
            return try await transcribe(samples)
        }
        let backend = try await loadTask.value
        return try await backend.transcribe(samples)
    }

    private func report(_ progress: DownloadProgress, generation: Int) {
        guard generation == self.generation, state != .ready else { return }
        switch progress.phase {
        case .listing:
            // FluidAudio lists the remote files only when it must download.
            state = .downloading(0)
        case .downloading(let completedFiles, let totalFiles) where completedFiles < totalFiles:
            // FluidAudio 0.17.4 reports a model download as the first half of the load, from 0 to 0.5,
            // and the Core ML compile as the second half. Patter shows the download from 0 to 100%.
            state = .downloading(min(max(progress.fractionCompleted * 2, 0), 1))
        case .downloading, .compiling:
            // All the files are on disk: the download finished, or the model was there already.
            state = .preparing
        }
    }
}

enum TextCleanup {
    /// Trims the model output and returns an empty string when it holds no words.
    static func clean(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLetterOrDigit = collapsed.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0)
        }
        return hasLetterOrDigit ? collapsed : ""
    }
}
