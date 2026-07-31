import AppKit
import ProjectRegistry
import ToolAdapters
import SecretaryCore

/// Adds a project by having the user physically choose the folder in a system
/// panel. The path therefore always comes from an explicit human action — it is
/// never derived from typed text — which is also what a sandboxed build would
/// require later.
enum ProjectPicker {
    @MainActor
    static func promptForProject() -> Project? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a folder the assistant may work in."

        // `runModal()` shows the panel but does not bring the app forward, and
        // this app is usually not the active one when the button is pressed: the
        // chat is a non-activating panel, so clicking Projects → Add Project
        // never made it active. An open panel belonging to an inactive app is
        // not key — the folder list stops answering clicks, and the first click
        // is spent activating instead of selecting. That is the "sometimes":
        // it worked right after the chat opened, because opening it activates.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        return Project(
            name: url.lastPathComponent,
            path: url.path,
            allowedTools: [
                GitReadOnlyAdapter.toolIdentifier,
                FileReadOnlyAdapter.toolIdentifier,
                Secretary.claudeCodeToolID
            ],
            allowedActions: ["read"]
        )
    }
}
