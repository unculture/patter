import AppKit
import Carbon.HIToolbox

/// A key and its modifier keys, for a shortcut that works in every app.
struct Shortcut: Hashable {
    /// The virtual key code: the position of the key on the keyboard, not the character it types.
    let keyCode: Int
    /// Carbon modifier flags (controlKey, optionKey, shiftKey, cmdKey), because RegisterEventHotKey takes these.
    let modifiers: Int

    /// The default shortcut that starts and stops dictation: Control-Shift-R.
    static let defaultDictation = Shortcut(keyCode: kVK_ANSI_R, modifiers: controlKey | shiftKey)

    /// Pastes the last transcript again: Control-Command-V, the same shortcut as in Wispr Flow.
    static let pasteLast = Shortcut(keyCode: kVK_ANSI_V, modifiers: controlKey | cmdKey)

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (controlKey | optionKey | shiftKey | cmdKey)
    }

    /// The key and the modifier keys of a key press.
    init(event: NSEvent) {
        self.init(keyCode: Int(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        return modifiers
    }

    /// A shortcut must not take a key that the user types, so it needs Control or Command.
    /// A function key, for example F5, also works alone.
    var isUsable: Bool {
        modifiers & (controlKey | cmdKey) != 0 || Self.functionKeys.contains(keyCode)
    }

    /// The modifier keys as symbols, in the order that macOS shows them: ⌃⌥⇧⌘.
    static func modifierSymbols(_ modifiers: Int) -> [String] {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & $0.0 != 0 }
            .map(\.1)
    }

    /// The keys as they show on key caps, for example ["⌃", "⇧", "R"].
    @MainActor var symbols: [String] {
        Self.modifierSymbols(modifiers) + [Self.specialKeys[keyCode]?.symbol ?? typedCharacter]
    }

    /// For example "⌃⇧R".
    @MainActor var display: String { symbols.joined() }

    /// For VoiceOver, for example "Control Shift R".
    @MainActor var spokenName: String {
        let names = [(controlKey, "Control"), (optionKey, "Option"), (shiftKey, "Shift"), (cmdKey, "Command")]
            .filter { modifiers & $0.0 != 0 }
            .map(\.1)
        return (names + [Self.specialKeys[keyCode]?.name ?? typedCharacter]).joined(separator: " ")
    }

    /// The key equivalent of a menu item, so that the menu shows the shortcut.
    @MainActor var keyEquivalent: String {
        Self.specialKeys[keyCode]?.keyEquivalent ?? Keyboard.character(for: keyCode)?.lowercased() ?? ""
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    /// The character that the key types in the keyboard layout, for example "R" on QWERTY and "P" on Dvorak.
    @MainActor private var typedCharacter: String {
        Keyboard.character(for: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    // MARK: - Storage

    /// The form in which the settings store a shortcut.
    var storedValue: [String: Int] { ["keyCode": keyCode, "modifiers": modifiers] }

    init?(storedValue: [String: Int]) {
        guard let keyCode = storedValue["keyCode"], let modifiers = storedValue["modifiers"] else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Keys that do not type a character

    private struct SpecialKey {
        let symbol: String
        let name: String
        let keyEquivalent: String
    }

    private static let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// The key equivalents are the characters that NSMenuItem expects, for example NSF1FunctionKey for F1.
    private static let specialKeys: [Int: SpecialKey] = {
        var keys = [
            kVK_Space: SpecialKey(symbol: "Space", name: "Space", keyEquivalent: " "),
            kVK_Return: SpecialKey(symbol: "↩", name: "Return", keyEquivalent: "\r"),
            kVK_ANSI_KeypadEnter: SpecialKey(symbol: "⌤", name: "Enter", keyEquivalent: "\u{03}"),
            kVK_Tab: SpecialKey(symbol: "⇥", name: "Tab", keyEquivalent: "\t"),
            kVK_Delete: SpecialKey(symbol: "⌫", name: "Delete", keyEquivalent: "\u{08}"),
            kVK_ForwardDelete: SpecialKey(symbol: "⌦", name: "Forward Delete", keyEquivalent: "\u{F728}"),
            kVK_Escape: SpecialKey(symbol: "⎋", name: "Escape", keyEquivalent: "\u{1B}"),
            kVK_LeftArrow: SpecialKey(symbol: "←", name: "Left Arrow", keyEquivalent: "\u{F702}"),
            kVK_RightArrow: SpecialKey(symbol: "→", name: "Right Arrow", keyEquivalent: "\u{F703}"),
            kVK_UpArrow: SpecialKey(symbol: "↑", name: "Up Arrow", keyEquivalent: "\u{F700}"),
            kVK_DownArrow: SpecialKey(symbol: "↓", name: "Down Arrow", keyEquivalent: "\u{F701}"),
            kVK_Home: SpecialKey(symbol: "↖", name: "Home", keyEquivalent: "\u{F729}"),
            kVK_End: SpecialKey(symbol: "↘", name: "End", keyEquivalent: "\u{F72B}"),
            kVK_PageUp: SpecialKey(symbol: "⇞", name: "Page Up", keyEquivalent: "\u{F72C}"),
            kVK_PageDown: SpecialKey(symbol: "⇟", name: "Page Down", keyEquivalent: "\u{F72D}"),
        ]
        for (index, code) in functionKeys.enumerated() {
            let name = "F\(index + 1)"
            let keyEquivalent = String(Character(Unicode.Scalar(UInt32(0xF704 + index))!))
            keys[code] = SpecialKey(symbol: name, name: name, keyEquivalent: keyEquivalent)
        }
        return keys
    }()
}
