/// The three panel buttons along the bottom of the chat.
public enum FooterButton: String, CaseIterable, Sendable {
    case projects
    case profile
    case settings

    public var title: String {
        switch self {
        case .projects: "Projects"
        case .profile: "Profile"
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

/// Left to right.
///
/// The row is not one cluster: Projects sits alone against one edge, and
/// Profile and Settings sit together against the other, with the window's width
/// between them.
///
/// ```text
/// | [Projects]                        [Profile] [Settings] |
/// ```
///
/// Mirrored, the whole sequence reverses — gap included — so the arrangement is
/// the mirror image of itself rather than a different layout:
///
/// ```text
/// | [Settings] [Profile]                        [Projects] |
/// ```
///
/// Reversing everything is what keeps each button the same distance from the
/// outer edge it was against before. Moving only the groups, and leaving each
/// group's own order alone, would put Profile where Settings had been.
public func footerSlots(mirrored: Bool) -> [FooterSlot] {
    let normal: [FooterSlot] = [
        .button(.projects),
        .gap,
        .button(.profile),
        .button(.settings)
    ]
    return mirrored ? normal.reversed() : normal
}
