import Foundation

public enum ArrowKeyOwner: Equatable, Sendable {
    case choiceList
    case history
    case textCaret

    public static func owner(hasChoices: Bool, draft: String, hasHistory: Bool) -> ArrowKeyOwner {
        let aVisiblePickerWithNothingTypedOwnsThemAsEscapeDoes = hasChoices && draft.isEmpty
        if aVisiblePickerWithNothingTypedOwnsThemAsEscapeDoes { return .choiceList }

        let aMultiLineDraftNeedsThemToMoveBetweenItsLines = draft.contains("\n")
        if aMultiLineDraftNeedsThemToMoveBetweenItsLines { return .textCaret }

        return hasHistory ? .history : .textCaret
    }
}
