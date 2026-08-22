public enum GlobalShortcut: String, CaseIterable, Sendable {
    case closeChat

    public var keyCode: UInt32 {
        switch self {
        case .closeChat: 53   // kVK_Escape
        }
    }

    public var modifiers: UInt32 {
        switch self {
        case .closeChat: 0
        }
    }
}

public func claimedShortcuts(hasDismissableWindow: Bool) -> Set<GlobalShortcut> {
    hasDismissableWindow ? [.closeChat] : []
}
