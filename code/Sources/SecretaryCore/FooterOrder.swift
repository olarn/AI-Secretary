/// The panel buttons along the bottom of the chat.
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

/// One position in the footer row — a button, or the gap that pushes the rest
/// of the row to the far edge.
///
/// The gap is part of the sequence rather than something the view adds, because
/// it is what makes the row two groups instead of one, and mirroring has to move
/// it along with everything else.
public enum FooterSlot: Equatable, Sendable {
    case button(FooterButton)
    case gap
}

/// Left to right. The same row wherever the bubble is.
///
/// The row is not one cluster: Projects sits alone against the left edge, and
/// Profile, Skills and Settings sit together against the right, with the
/// window's width between them.
///
/// ```text
/// | [Projects]                [Profile] [Skills] [Settings] |
/// ```
///
/// This used to reverse — gap included — when the bubble mirrored, on the
/// reasoning that each button then kept its distance from the outer edge it had
/// been against. That reasoning was about the box; the person is aiming at
/// Settings, and Settings moving to the far end because the character wandered
/// too near the right of the screen costs a hunt every time. A row that reads
/// the same in both placements is worth more than one that mirrors tidily, so
/// the placement is no longer an input here at all.
public func footerSlots() -> [FooterSlot] {
    [
        .button(.projects),
        .gap,
        .button(.profile),
        .button(.skills),
        .button(.settings)
    ]
}
