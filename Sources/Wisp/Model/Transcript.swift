import Foundation

struct Transcript: Codable, Identifiable, Hashable {
    let id: UUID
    var text: String
    let createdAt: Date
    /// Length of the recording in seconds.
    let duration: TimeInterval
    /// The transcript before the AI cleanup, when the cleanup changed it.
    var rawText: String?

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), duration: TimeInterval, rawText: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.duration = duration
        self.rawText = rawText
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
