import Foundation

/// Turns a reply into displayable rich text: inline markdown, plus bare URLs
/// made clickable.
///
/// Links arrive from the model, from pages it fetched, and from tool output —
/// all untrusted. So the link attribute is only ever attached to schemes that
/// are safe to hand to the browser; anything else is left as plain text the
/// person can read but not click by accident.
public enum MessageMarkdown {

    /// Schemes a link may use. Deliberately short: `file:` would open local
    /// content, and custom schemes can drive other apps, neither of which
    /// should be one click away from a sentence the model wrote.
    public static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    /// Inline markdown only — `**bold**`, `` `code` ``, `[label](url)` — so a
    /// stray character can't restructure the message, and newlines survive.
    public static func attributed(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        stripUnsafeLinks(&attributed)
        linkifyBareURLs(&attributed)
        return attributed
    }

    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }

    /// `[click me](file:///etc/passwd)` renders as text, not as a link.
    private static func stripUnsafeLinks(_ attributed: inout AttributedString) {
        for run in attributed.runs where run.link != nil {
            if let url = run.link, !isAllowed(url) {
                attributed[run.range].link = nil
            }
        }
    }

    /// Most replies contain plain `https://…` rather than markdown links, and
    /// the markdown parser leaves those as text.
    private static func linkifyBareURLs(_ attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        guard !plain.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return }

        let matches = detector.matches(
            in: plain,
            range: NSRange(plain.startIndex..., in: plain)
        )

        for match in matches {
            guard let url = match.url, isAllowed(url),
                  let range = Range(match.range, in: attributed)
            else { continue }
            // An existing link wins: a markdown label shouldn't be re-pointed at
            // whatever the detector reads out of its own text.
            guard attributed[range].runs.allSatisfy({ $0.link == nil }) else { continue }
            attributed[range].link = url
        }
    }
}
