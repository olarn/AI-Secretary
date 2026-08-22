import AppKit
import SecretaryCore

enum SavePanel {
    private static var startingDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    @MainActor
    @discardableResult
    static func save(_ file: OfferedFile) -> URL? {
        guard let destination = ask(name: file.name, message: "Save “\(file.name)”") else { return nil }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: file.url, to: destination)
            return destination
        } catch {
            present(error, saving: file.name)
            return nil
        }
    }

    @MainActor
    @discardableResult
    static func saveText(_ text: String, named name: String) -> URL? {
        guard let destination = ask(name: name, message: "Save “\(name)”") else { return nil }
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            return destination
        } catch {
            present(error, saving: name)
            return nil
        }
    }

    @MainActor
    private static func ask(name: String, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.directoryURL = startingDirectory
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.message = message

        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    private static func present(_ error: Error, saving name: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't save “\(name)”"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
