import AppKit

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

        NSApp.activate(ignoringOtherApps: true)

        guard GlobalHotKeys.whileSuspended({ panel.runModal() }) == .OK else { return nil }
        return panel.url
    }
}
