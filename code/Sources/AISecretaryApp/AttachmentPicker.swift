import AppKit
import SecretaryCore
import UniformTypeIdentifiers

/// Picks a file to hand to the assistant through a system panel.
///
/// Same rule as the project and profile pickers: the file always comes from an
/// explicit human choice rather than a path the app derived. The allowed types
/// are the ones the assistant can actually read, so a file it would refuse is
/// greyed out in the panel rather than refused afterwards.
enum AttachmentPicker {
    @MainActor
    static func promptForFile(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .plainText, .commaSeparatedText, .tabSeparatedText, .json, .yaml, .log,
            .png, .jpeg, .heic, .gif, .webP, .tiff,
            UTType(filenameExtension: "md") ?? .plainText
        ]
        panel.prompt = "Attach"
        panel.message = "Choose \(message)"

        // An open panel owned by an inactive app is not key, and its file list
        // ignores clicks until something activates the app — the same reason
        // `ProjectPicker` and `ImagePicker` do this.
        NSApp.activate(ignoringOtherApps: true)

        // Esc has to cancel this dialog, not the chat window behind it.
        guard GlobalHotKeys.whileSuspended({ panel.runModal() }) == .OK else { return nil }
        return panel.url
    }
}
