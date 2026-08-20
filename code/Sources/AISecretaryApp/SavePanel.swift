import AppKit
import SecretaryCore

/// Hands a finished file to the person through the system save panel.
///
/// The mirror of `AttachmentPicker`, and the same rule read backwards: the file
/// goes exactly where an explicit human choice puts it, never to a path the app
/// picked. That is also what makes this safe without a permission card — the
/// panel *is* the consent, and a sandboxed build gets the write grant from it
/// rather than from anything we could grant ourselves.
enum SavePanel {
    /// Where the panel opens. Downloads is where a file that arrived from
    /// somewhere else belongs, and it is the one folder people empty without
    /// thinking about it — the Desktop, the other candidate, is somewhere
    /// things go to stay.
    private static var startingDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    /// Copies `file` wherever the person says. Returns where it landed, or
    /// nothing if they cancelled.
    ///
    /// **Copies rather than moves.** The conversation still refers to the file
    /// in the working folder — "add a column to that spreadsheet" has to keep
    /// working after they save it — and a save that quietly emptied the folder
    /// the assistant is standing in would break the next turn.
    @MainActor
    @discardableResult
    static func save(_ file: OfferedFile) -> URL? {
        guard let destination = ask(name: file.name, message: "Save “\(file.name)”") else { return nil }

        do {
            // The panel already asked about replacing, so an existing file here
            // is one the person chose to overwrite — but `copyItem` refuses
            // rather than replacing, so the old one goes first.
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

    /// Writes text the app made up itself — the command window's results
    /// strip — wherever the person says.
    ///
    /// A write, not the copy above: there is no file yet. The panel is still
    /// the consent, so this needs no permission card for the same reason.
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

    /// The panel itself, asked the same way for both kinds of save.
    @MainActor
    private static func ask(name: String, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.directoryURL = startingDirectory
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.message = message

        // A panel owned by an inactive app is not key and ignores clicks until
        // something activates the app — the same reason `AttachmentPicker`,
        // `ProjectPicker` and `ImagePicker` all do this. The character's window
        // never takes focus on its own, so this app is very often the inactive
        // one when a button in it is pressed.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Says so when the copy fails. Rare — the panel has already settled the
    /// permission and the folder — but a Save button that does nothing at all
    /// is the worst of the possible outcomes.
    @MainActor
    private static func present(_ error: Error, saving name: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't save “\(name)”"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
