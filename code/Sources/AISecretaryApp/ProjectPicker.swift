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

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        return Project(
            name: url.lastPathComponent,
            path: url.path,
            description: nil,
            allowedTools: [
                GitReadOnlyAdapter.toolIdentifier,
                FileReadOnlyAdapter.toolIdentifier,
                Secretary.claudeCodeToolID
            ],
            allowedActions: ["read"]
        )
    }
}
