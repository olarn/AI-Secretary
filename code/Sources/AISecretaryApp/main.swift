import AppKit

// Top-level startup runs on the main thread; assert that to the compiler so the
// @MainActor AppDelegate can be constructed here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // An agent app draws no menu bar, but NSApplication still dispatches
    // command-key equivalents through mainMenu — this is what makes ⌘Q (and the
    // editing shortcuts in the chat field) work. See AppMenu.
    // The delegate is the target for ⌘+/⌘−/⌘H and About, and is retained by
    // the application.
    app.mainMenu = AppMenu.make(commandTarget: delegate)
    app.run()
}
