import AppKit
import AVFoundation

enum Clipboard {
    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

enum Microphone {
    static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}

@MainActor
enum Sounds {
    static func playStart() { play("Tink") }
    static func playStop() { play("Pop") }

    private static func play(_ name: String) {
        guard Preferences.shared.playSounds, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.3
        sound.stop()
        sound.play()
    }
}

enum Shortcut {
    /// The dictation shortcut: Control-Shift-R.
    static let keyCode = 0x0F  // kVK_ANSI_R
    static let symbols = ["⌃", "⇧", "R"]
    static let display = symbols.joined()
}
