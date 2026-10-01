import Foundation

/// Keeps every transcript, newest first, in a JSON file in Application Support.
@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var transcripts: [Transcript] = []

    private let fileURL: URL

    init(fileURL: URL = TranscriptStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wisp", isDirectory: true)
            .appendingPathComponent("transcripts.json")
    }

    var latest: Transcript? { transcripts.first }

    func add(_ transcript: Transcript) {
        insertSorted(transcript)
        save()
    }

    func delete(_ transcript: Transcript) {
        transcripts.removeAll { $0.id == transcript.id }
        save()
    }

    /// Puts back a transcript that the user deleted, for undo.
    func restore(_ transcript: Transcript) {
        guard !transcripts.contains(where: { $0.id == transcript.id }) else { return }
        insertSorted(transcript)
        save()
    }

    func deleteAll() {
        transcripts.removeAll()
        save()
    }

    private func insertSorted(_ transcript: Transcript) {
        let index = transcripts.firstIndex { $0.createdAt < transcript.createdAt } ?? transcripts.endIndex
        transcripts.insert(transcript, at: index)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            transcripts = try decoder.decode([Transcript].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            // Keep the unreadable file, so that the next save does not destroy the history.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("transcripts.unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            NSLog("Wisp: could not read transcripts (\(error)). Saved a copy at \(backup.path).")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(transcripts).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Wisp: could not save transcripts: \(error)")
        }
    }
}
