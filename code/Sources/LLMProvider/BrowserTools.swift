import FunctionalCore
import Foundation

public enum BrowserTools: Sendable {
    public static let server = "claude-in-chrome"

    public static let readOnly: [String] = [
        "read_page",
        "get_page_text",
        "find",
        "read_console_messages",
        "read_network_requests",
        "list_connected_browsers",
        "tabs_context_mcp"
    ]

    public static var readOnlyRules: [String] {
        readOnly.map { rule(for: $0) }
    }

    public static func rule(for tool: String) -> String {
        "mcp__\(server)__\(tool)"
    }

    public static func isBrowserTool(_ name: String) -> Bool {
        name.hasPrefix("mcp__\(server)__") || readOnly.contains(name)
    }

    public static func humanDescription(for name: String) -> Option<String> {
        guard isBrowserTool(name) else { return .none() }
        let bare = name.hasPrefix("mcp__\(server)__")
            ? String(name.dropFirst("mcp__\(server)__".count))
            : name
        switch bare {
        case "computer":
            return .some("scroll, click and type in the page")
        case "navigate":
            return .some("open a web page")
        case "form_input":
            return .some("fill in fields on the page")
        case "javascript_tool":
            return .some("run JavaScript in the page")
        case "file_upload", "upload_image":
            return .some("upload a file from this Mac to the page")
        case "tabs_create_mcp", "tabs_close_mcp":
            return .some("open and close tabs")
        case "gif_creator":
            return .some("record the browser as a GIF")
        default:
            return .some("act in the browser (\(bare))")
        }
    }

    public static func changesState(_ name: String) -> Bool {
        guard isBrowserTool(name) else { return false }
        let bare = name.hasPrefix("mcp__\(server)__")
            ? String(name.dropFirst("mcp__\(server)__".count))
            : name
        return !readOnly.contains(bare)
    }
}
