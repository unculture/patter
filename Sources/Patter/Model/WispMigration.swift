import Foundation

/// Patter was called Wisp until 1 October 2026. On the first launch, Patter copies the settings
/// and the transcripts of Wisp. APIKeyStore copies the OpenRouter key.
enum WispMigration {
    static let bundleIdentifier = "com.unculture.Wisp"

    /// The choices of the user. Patter does not copy the first-launch flags: it needs its own
    /// login item, microphone access, and Accessibility access.
    private static let settingKeys = [
        "engine", "playSounds", "microphone", "cleanupEnabled", "cleanupModel", "glossary", "autoPaste",
    ]

    /// Runs before anything reads the settings or the transcripts.
    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromWisp") else { return }
        defaults.set(true, forKey: "migratedFromWisp")

        if let old = defaults.persistentDomain(forName: bundleIdentifier) {
            for key in settingKeys {
                if let value = old[key] { defaults.set(value, forKey: key) }
            }
        }

        let files = FileManager.default
        let oldFile = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wisp", isDirectory: true)
            .appendingPathComponent("transcripts.json")
        let newFile = TranscriptStore.defaultFileURL
        guard files.fileExists(atPath: oldFile.path), !files.fileExists(atPath: newFile.path) else { return }
        do {
            try files.createDirectory(at: newFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.copyItem(at: oldFile, to: newFile)
        } catch {
            NSLog("Patter: could not copy the transcripts of Wisp: \(error)")
        }
    }
}
