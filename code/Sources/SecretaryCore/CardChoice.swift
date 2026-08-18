import Foundation

/// The words on the buttons of every card that waits for an answer.
///
/// Here rather than in the view because the transcript now repeats them back:
/// a record that reads "You chose “Go ahead”" while the button said "Yes" is
/// worse than no record, and `AISecretaryApp` is never linked into the test
/// bundle, so a literal typed twice there is a drift no test could see.
///
/// `PermissionAnswer.title` is the fourth member of this set and stays where it
/// is — it is owned by the type whose cases the buttons are.
public enum CardChoice {
    public static let waitItsTurn = "Wait its turn"
    public static let replaceRunning = "Replace — drop what's running"
    public static let goAhead = "Go ahead"
    public static let notThisOne = "Not this one"
    public static let start = "Start"
    public static let cancel = "Cancel"

    /// The control that opens the list of everyone free.
    ///
    /// One control rather than one button per character. Buttons were the first
    /// shape and they do not survive a roster: four characters already filled
    /// three rows under the other two answers, and the card grows a row per
    /// character with nothing to stop it — the same unbounded growth the charter
    /// forbids in the settings panels. A menu is the same height whether two
    /// characters are free or twenty, and the list inside it is AppKit's problem
    /// rather than ours.
    public static let giveItToSomeone = "Give it to…"

    /// How the choice is named once it has been made — the menu's words and the
    /// item's words together, which is what the person actually read.
    public static func giveItTo(_ name: String) -> String { "Give it to \(name)" }
}

/// How an answered card is written into the conversation.
///
/// The card itself disappears the moment it is answered, so without this the
/// only trace of a decision is whatever happened next — and for approving, for
/// picking a project, and for replacing a running turn, nothing happened that
/// said so. The person is left reading a conversation in which they apparently
/// never answered anything.
///
/// Deliberately just the opening clause: each caller adds what followed from
/// the answer, so there is one rule for how a choice is named and no table of
/// near-identical sentences to keep in step.
public func chosenLine(_ title: String) -> String {
    "You chose “\(title)”"
}
