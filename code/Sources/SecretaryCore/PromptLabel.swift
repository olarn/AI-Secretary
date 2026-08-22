import Foundation

public func droppingTheLabelThatReadsBetterInAPrompt(
    _ label: String,
    from line: String
) -> String {
    line
        .replacingOccurrences(of: label, with: "", options: .caseInsensitive)
        .trimmingCharacters(in: .whitespaces)
}
