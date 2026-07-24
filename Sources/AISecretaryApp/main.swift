import AppKit

// Top-level startup runs on the main thread; assert that to the compiler so the
// @MainActor AppDelegate can be constructed here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
