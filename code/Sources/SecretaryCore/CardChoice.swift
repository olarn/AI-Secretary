import Foundation

public enum CardChoice {
    public static let waitItsTurn = "Wait its turn"
    public static let replaceRunning = "Replace — drop what's running"
    public static let goAhead = "Go ahead"
    public static let notThisOne = "Not this one"
    public static let start = "Start"
    public static let cancel = "Cancel"

    public static let giveItToSomeone = "Give it to…"

    public static func giveItTo(_ name: String) -> String { "Give it to \(name)" }
}

public func chosenLine(_ title: String) -> String {
    "You chose “\(title)”"
}
