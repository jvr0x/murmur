import AppKit
import MurmurKit

// Murmur runs as a menu-bar (accessory) app: no Dock icon, no main window.
// The AppDelegate wires up every subsystem in `applicationDidFinishLaunching`.
//
// main.swift's top-level code is nonisolated, but `AppDelegate` and the AppKit setup are
// main-actor isolated. We are already on the main thread at process start, so assume
// main-actor isolation explicitly to satisfy the compiler without a detached hop.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
