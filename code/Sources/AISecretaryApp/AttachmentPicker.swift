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
    static func promptForFiles(message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // Several at once: the data for one form is often several files — the
        // rows in one, the attachment to upload in another — and making that
        // three trips through a dialog is three chances to send the wrong one.
        // The list has its own cap and says so when it is reached.
        panel.allowsMultipleSelection = true
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
        guard GlobalHotKeys.whileSuspended({ panel.runModal() }) == .OK else { return [] }
        return panel.urls
    }
}
