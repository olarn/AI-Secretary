import Foundation

/// How tall the message box is allowed to get, and what Return means in it.
///
/// Kept away from AppKit so both rules can be tested without a window: the
/// height one has edges that are easy to get wrong by a line, and the Return one
/// decides whether a half-written message gets sent by accident.
public enum ChatInputMetrics {
    /// One line to start with, and no more than five. Past five the box starts
    /// eating the conversation above it, which is the thing being replied to.
    public static let minLines = 1
    public static let maxLines = 5

    /// The height to give the text, for content that currently needs
    /// `contentHeight`. Beyond five lines this stops growing and the caller
    /// scrolls instead.
    public static func height(forContent contentHeight: Double, lineHeight: Double) -> Double {
        guard lineHeight > 0 else { return 0 }
        let lines = (contentHeight / lineHeight).rounded(.up)
        let clamped = min(max(lines, Double(minLines)), Double(maxLines))
        return clamped * lineHeight
    }

    /// Whether the content no longer fits, and so needs scrolling rather than
    /// more room.
    public static func scrolls(contentHeight: Double, lineHeight: Double) -> Bool {
        guard lineHeight > 0 else { return false }
        return (contentHeight / lineHeight).rounded(.up) > Double(maxLines)
    }

    public enum ReturnAction: Equatable, Sendable {
        case send
        case newline
    }

    /// Return sends, because that's what it did when the box was one line tall
    /// and it's the common case. A held modifier is the way to get a line break
    /// instead — Shift is what people try first, and Option is what AppKit's own
    /// multi-line fields use, so both work.
    public static func returnAction(shift: Bool, option: Bool) -> ReturnAction {
        (shift || option) ? .newline : .send
    }
}
