public enum FooterButton: String, CaseIterable, Sendable {
    case projects
    case profile
    case skills
    case settings

    public var title: String {
        switch self {
        case .projects: "Projects"
        case .profile: "Profile"
        case .skills: "Skills"
        case .settings: "Settings"
        }
    }
}

public enum FooterSlot: Equatable, Sendable {
    case button(FooterButton)
    case gap
}

public func footerSlots() -> [FooterSlot] {
    [
        .button(.projects),
        .gap,
        .button(.profile),
        .button(.skills),
        .button(.settings)
    ]
}
