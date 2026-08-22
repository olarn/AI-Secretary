import Foundation

public enum MessageMarkdown {

    public static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

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

    private static func stripUnsafeLinks(_ attributed: inout AttributedString) {
        for run in attributed.runs where run.link != nil {
            if let url = run.link, !isAllowed(url) {
                attributed[run.range].link = nil
            }
        }
    }

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
            let anExistingLinkWinsOverWhatTheDetectorReadsOutOfItsLabel =
                !attributed[range].runs.allSatisfy { $0.link == nil }
            guard !anExistingLinkWinsOverWhatTheDetectorReadsOutOfItsLabel else { continue }
            attributed[range].link = url
        }
    }
}
