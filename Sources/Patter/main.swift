import AppKit

// Developer commands, run from the terminal against the app binary. See DevTools.swift.
let arguments = CommandLine.arguments
if arguments.dropFirst().contains(where: DevTools.flags.contains) {
    DevTools.run(arguments)
}

// Only one copy of Patter runs at a time: a second copy would fight over the shortcut and the menu bar.
let otherCopies = NSRunningApplication.runningApplications(withBundleIdentifier: "com.unculture.Patter")
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !otherCopies.isEmpty {
    exit(0)
}

WispMigration.run()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
