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
        case idle
        case downloading(Double)
        case preparing
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var kind: EngineKind = .english

    private var loadTask: Task<TranscriptionBackend, Error>?
    private var generation = 0

    var isReady: Bool { state == .ready }

    func load(_ kind: EngineKind) {
        self.kind = kind
        generation += 1
        let current = generation
        state = .downloading(0)

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
        case .compiling:
            state = .preparing
        case .listing, .downloading:
            state = .downloading(min(max(progress.fractionCompleted, 0), 1))
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
