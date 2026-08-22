import AppKit
import SecretaryCore
import UniformTypeIdentifiers

enum AttachmentPicker {
    @MainActor
    static func promptForFiles(message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .plainText, .text, .sourceCode, .script, .shellScript, .propertyList,
            .commaSeparatedText, .tabSeparatedText, .json, .yaml, .xml, .html, .log,
            .pdf, .png, .jpeg, .heic, .gif, .webP, .tiff,
            UTType(filenameExtension: "md") ?? .plainText,
            .data
        ]
        panel.prompt = "Attach"
        panel.message = "Choose \(message)"

        NSApp.activate(ignoringOtherApps: true)

        guard GlobalHotKeys.whileSuspended({ panel.runModal() }) == .OK else { return [] }
        return panel.urls
    }
}
