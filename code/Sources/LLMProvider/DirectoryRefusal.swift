import Foundation

/// A refusal that is about *where* a tool pointed, not about what the tool was.
///
/// Claude Code has two different walls and only one of them was ever noticed.
/// The familiar one is the permission wall — "requested permissions",
/// "requires approval" — which `isPermissionRefusal` matches and which a tool
/// rule opens. The other is the **working-directory** wall, and it is worded
/// nothing like the first:
///
/// ```
/// ls in '/Users/Olarn/Temp/ai-probe-watch' was blocked. For security, Claude
/// Code may only list files in the allowed working directories for this
/// session: '/Users/Olarn/Temp/ai-team-work'.
/// ```
///
/// Captured verbatim from a real refusal on 2026-08-20. It matched none of the
/// permission phrases, so no `toolDenied` event was ever emitted, `offerToWiden`
/// found nothing to offer, and **no card was ever put in front of anybody** —
/// the character said it had no permission and the work stopped. That is the
/// owner's report: commanding several characters at once, a write into a folder
/// asks for permission that never arrives. It bites hardest with several
/// characters because a character with no project open is standing in the
/// scratch directory, so *every* path into the shared folder is outside her
/// session.
///
/// A tool rule cannot open this wall. What is missing is the folder itself —
/// `--add-dir` — which is why this is a separate kind of refusal rather than
/// another phrase in the permission list.
public func isDirectoryRefusal(_ message: String) -> Bool {
    // The distinctive half of the sentence. "was blocked" alone is far too
    // broad — a tool can say that about plenty of things it *was* allowed to
    // attempt — and the phrase below is the one Claude Code uses to name this
    // wall specifically.
    message.localizedCaseInsensitiveContains("allowed working directories")
}

/// The folder that would unblock a directory refusal.
///
/// Read from the tool's own input where there is one, because that is the path
/// the model actually asked for; the prose is only a fallback for `Bash`, whose
/// input is a command line with no path field to read.
///
/// Returns nothing rather than guessing. A card offering a folder we are not
/// sure about is worse than no card: the person would be granting access to
/// somewhere they did not choose.
public func blockedDirectory(tool: String, input: [String: Any], message: String) -> String? {
    if let named = directoryFromInput(tool: tool, input: input) { return named }
    return firstQuotedAbsolutePath(in: message)
}

/// Tools that name a directory outright, against those that name a file inside
/// one. Getting this backwards would ask for `/Users/me/project/notes` when the
/// folder wanted is `/Users/me/project`, or the other way about.
private let directoryValuedTools: Set<String> = ["Glob", "Grep", "LS", "NotebookRead"]

private func directoryFromInput(tool: String, input: [String: Any]) -> String? {
    let raw = (input["file_path"] as? String)
        ?? (input["path"] as? String)
        ?? (input["notebook_path"] as? String)
    guard let raw, raw.hasPrefix("/") else { return nil }

    let url = URL(fileURLWithPath: raw).standardizedFileURL
    // A write names the file; the folder that has to be granted is the one it
    // would land in.
    return directoryValuedTools.contains(tool) ? url.path : url.deletingLastPathComponent().path
}

/// The first absolute path in single quotes — the one the refusal opens with,
/// which is the path that was refused rather than the ones it lists as allowed.
///
/// Order is the whole of it: the sentence names what was wanted first and what
/// is permitted afterwards, so taking the first is taking the right one.
private func firstQuotedAbsolutePath(in message: String) -> String? {
    let parts = message.components(separatedBy: "'")
    // Quotes split the string into alternating outside/inside pieces, so the
    // insides are the odd indices.
    for (index, part) in parts.enumerated() where index % 2 == 1 {
        guard part.hasPrefix("/") else { continue }
        let url = URL(fileURLWithPath: part).standardizedFileURL
        // `ls in '<dir>'` names a folder; anything with a file extension is a
        // file, and its folder is what would be granted.
        return url.pathExtension.isEmpty ? url.path : url.deletingLastPathComponent().path
    }
    return nil
}
