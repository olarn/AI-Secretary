import Foundation

/// A turn that has just come to rest, as the notifier sees it.
///
/// Assembled by `Secretary` at the moment the state machine settles, so it
/// carries what only she knows — who she is, what she ended up saying, and
/// whether anybody actually asked her. What she cannot know is whether the
/// person is looking at it; that arrives separately, from the windows.
public struct FinishedTurn: Equatable, Sendable {
    public let characterName: String
    /// The reply as it appears in the bubble — already stripped of the marker
    /// blocks, so a banner never shows a ```choices fence.
    public let text: String
    public let succeeded: Bool
    /// Whether this turn was another character's errand rather than the
    /// person's request.
    public let wasErrand: Bool

    public init(characterName: String, text: String, succeeded: Bool, wasErrand: Bool) {
        self.characterName = characterName
        self.text = text
        self.succeeded = succeeded
        self.wasErrand = wasErrand
    }
}

/// What a banner says.
public struct CompletionNotice: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Whether a finished turn is worth a notification, and what it should say.
///
/// Returns Swift's `Optional` rather than `Option` for the same reason
/// `dismissDecision` does: its only caller is `AppDelegate`, and importing
/// `FunctionalCore` there to fold one value would drag Bow's `State` into a
/// file that sits next to SwiftUI.
///
/// Three refusals, each for a different reason:
///
/// - **An errand.** One request from the person can finish twice — the
///   character she handed it to answers, then reports back, and the character
///   who asked finishes again. Notifying on both means two banners for one
///   piece of work, the first from somebody the person never spoke to.
/// - **They are already looking at it.** The app is frontmost *and* her chat is
///   open: the reply is on screen. A banner for a bubble you are watching fill
///   in is noise, and it would fire on every turn while typing.
/// - **Nothing to say.** A turn that ends with an empty bubble has no body, and
///   a banner with a title and no text reads as a bug.
///
/// A loop check passes all three on purpose. Something that reports every ten
/// minutes while nobody is watching is exactly what a notification is for.
public func completionNotice(
    for turn: FinishedTurn,
    isChatVisible: Bool,
    isAppActive: Bool
) -> CompletionNotice? {
    guard !turn.wasErrand else { return nil }
    guard !(isAppActive && isChatVisible) else { return nil }

    let body = noticeBody(turn.text)
    guard !body.isEmpty else { return nil }

    return CompletionNotice(
        title: turn.succeeded ? turn.characterName : "\(turn.characterName) couldn't finish",
        body: body
    )
}

/// The reply, flattened into something a banner can hold.
///
/// Newlines are collapsed because macOS renders a banner as at most a few lines
/// and folds them itself; a reply that opens with a heading and a blank line
/// would otherwise spend the whole banner on the heading.
///
/// - Parameter limit: how much survives. 180 is well past what a banner shows —
///   the cap is there so a thousand-word answer isn't handed to the system in
///   full, not to match a pixel width.
public func noticeBody(_ text: String, limit: Int = 180) -> String {
    let flattened = text
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    guard flattened.count > limit else { return flattened }
    return flattened.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
}
