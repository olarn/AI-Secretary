import AppKit

/// Picks a picture for a profile through a system panel, so the file always
/// comes from an explicit human choice rather than a path the app derived — the
/// same rule the project picker follows, and what a sandboxed build would need.
enum ImagePicker {
    @MainActor
    static func promptForImage(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .webP]
        panel.prompt = "Use Picture"
        panel.message = message

        // Same reason as `ProjectPicker`: an open panel owned by an inactive app
        // is not key, and its file list ignores clicks until something activates
        // the app. This one is reached from the Profile panel, which is inside
        // the same non-activating chat window.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
