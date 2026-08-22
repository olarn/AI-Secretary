public func handlesHideLocally(
    isOurWindowKey: Bool,
    keyCode: UInt16,
    hasOnlyCommand: Bool
) -> Bool {
    isOurWindowKey && hasOnlyCommand && keyCode == 4   // kVK_ANSI_H
}
