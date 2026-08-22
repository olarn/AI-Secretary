import AppKit
import ProjectRegistry
import ToolAdapters
import SecretaryCore

enum ProjectPicker {
    @MainActor
    static func promptForProject() -> Project? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a folder the assistant may work in."

        NSApp.activate(ignoringOtherApps: true)

        let response = GlobalHotKeys.whileSuspended { panel.runModal() }
        guard response == .OK, let url = panel.url else { return nil }

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
