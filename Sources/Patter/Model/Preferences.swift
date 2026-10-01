import Foundation
import ServiceManagement

enum EngineKind: String, CaseIterable, Identifiable {
    case english
    case multilingual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .multilingual: "Multilingual"
        }
    }

    var detail: String {
        switch self {
        case .english: "Parakeet Unified 0.6B. Most accurate for English."
        case .multilingual: "Parakeet Ultra 0.6B. 25 European languages, detected automatically."
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let engine = "engine"
        static let playSounds = "playSounds"
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let microphone = "microphone"
        static let cleanupEnabled = "cleanupEnabled"
        static let cleanupModel = "cleanupModel"
        static let glossary = "glossary"
        static let autoPaste = "autoPaste"
        static let askedForAccessibility = "askedForAccessibility"
    }

    private let defaults = UserDefaults.standard

    @Published var engine: EngineKind {
        didSet { defaults.set(engine.rawValue, forKey: Key.engine) }
    }

    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Key.playSounds) }
    }

    @Published var microphone: MicrophoneChoice {
        didSet { defaults.set(microphone.storedValue, forKey: Key.microphone) }
    }

    @Published var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Key.cleanupEnabled) }
    }

    /// An OpenRouter model ID, for example "openai/gpt-5.6-luna".
    @Published var cleanupModel: String {
        didSet { defaults.set(cleanupModel, forKey: Key.cleanupModel) }
    }

    /// Names and terms that the AI cleanup must spell correctly, as the user typed them.
    @Published var glossary: String {
        didSet { defaults.set(glossary, forKey: Key.glossary) }
    }

    /// Paste each transcript into the focused text field of the app in front, as Wispr Flow does.
    @Published var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Key.autoPaste) }
    }

    /// Whether Patter showed the system dialog that asks for Accessibility access.
    var askedForAccessibility: Bool {
        get { defaults.bool(forKey: Key.askedForAccessibility) }
        set { defaults.set(newValue, forKey: Key.askedForAccessibility) }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore) }
    }

    /// Login item state lives in the system (System Settings > General > Login Items), not in defaults.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Patter: could not change the login item: \(error)")
            }
        }
    }

    private init() {
        engine = EngineKind(rawValue: defaults.string(forKey: Key.engine) ?? "") ?? .english
        playSounds = defaults.object(forKey: Key.playSounds) as? Bool ?? true
        microphone = MicrophoneChoice(storedValue: defaults.string(forKey: Key.microphone))
        cleanupEnabled = defaults.bool(forKey: Key.cleanupEnabled)
        cleanupModel = defaults.string(forKey: Key.cleanupModel) ?? CleanupModel.presets[0].id
        glossary = defaults.string(forKey: Key.glossary) ?? ""
        autoPaste = defaults.object(forKey: Key.autoPaste) as? Bool ?? true
    }
}
