private let kVK_ANSI_H: UInt16 = 4

public func handlesHideLocally(
    isOurWindowKey: Bool,
    keyCode: UInt16,
    hasOnlyCommand: Bool
) -> Bool {
    isOurWindowKey && hasOnlyCommand && keyCode == kVK_ANSI_H
}
