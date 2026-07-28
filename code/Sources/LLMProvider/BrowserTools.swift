import Foundation

/// The browser tools Claude Code exposes when it is connected to the user's
/// Chrome, and which of them may run without asking.
///
/// Why this exists at all: `WebFetch` retrieves a URL from this app's own
/// process, with no cookies and no session. A page behind a login answers it
/// with the sign-in page, so the assistant reads something real and reports
/// something wrong. The Claude in Chrome extension doesn't fetch anything — it
/// reads the rendered tab in the browser the person is already signed into. The
/// password never comes near us; an open session is borrowed.
///
/// That is also precisely why the split below matters. The same connection that
/// can read an authenticated page can type into it, and the page text feeding
/// the model is untrusted input that may carry instructions of its own. Reading
/// is cheap and reversible; acting is neither.
public enum BrowserTools: Sendable {
    /// The MCP server Claude Code registers for the extension. Tools arrive
    /// named `mcp__<server>__<tool>`.
    public static let server = "claude-in-chrome"

    /// Tools that only observe: they report what is already on screen and leave
    /// the page as they found it. Pre-approved when browsing is on, so "what
    /// does this tab say?" is one question rather than a question plus a
    /// permission card.
    ///
    /// `tabs_context_mcp` is here for a practical reason: without it the model
    /// cannot find the tab the person is looking at, which is the whole point.
    /// Its `createIfEmpty` flag can open a blank tab — the one state change this
    /// list admits, and the mildest one available.
    public static let readOnly: [String] = [
        "read_page",
        "get_page_text",
        "find",
        "read_console_messages",
        "read_network_requests",
        "list_connected_browsers",
        "tabs_context_mcp"
    ]

    /// Permission rules for the read-only tools, in the syntax `--allowedTools`
    /// expects.
    public static var readOnlyRules: [String] {
        readOnly.map { rule(for: $0) }
    }

    public static func rule(for tool: String) -> String {
        "mcp__\(server)__\(tool)"
    }

    /// Whether a tool name belongs to the browser connection, however it is
    /// spelled — the CLI reports the full `mcp__…` name, callers often hold the
    /// bare one.
    public static func isBrowserTool(_ name: String) -> Bool {
        name.hasPrefix("mcp__\(server)__") || readOnly.contains(name)
    }

    /// Everything that is not on the read-only list changes something — it
    /// navigates, types, clicks, uploads, runs JavaScript, or moves tabs and
    /// windows around. Unknown names land here too: a browser tool this code has
    /// never heard of is asked about, not assumed harmless.
    public static func changesState(_ name: String) -> Bool {
        guard isBrowserTool(name) else { return false }
        let bare = name.hasPrefix("mcp__\(server)__")
            ? String(name.dropFirst("mcp__\(server)__".count))
            : name
        return !readOnly.contains(bare)
    }
}
