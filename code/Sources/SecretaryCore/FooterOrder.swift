/// The three panel buttons along the bottom of the chat, in the order they are
/// drawn.
///
/// A value with a rule rather than a literal array in the view, because the row
/// has to reverse when the bubble mirrors and "did the order come out right on
/// the other side?" is not a question anyone should have to answer by squinting
/// at a screenshot.
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

/// Left to right, for a row hugging the given edge.
///
/// The default bubble puts this row on the left, and there the order reads
/// Projects, Profile, Settings — Projects on the outside, Settings nearest the
/// middle of the window. Mirrored, the row moves to the right edge and the
/// sequence reverses, which keeps each button the same distance from the outer
/// edge it was before. The alternative — holding the literal order and letting
/// Projects end up innermost — would move every button under a different finger
/// depending on which way the bubble happened to flip.
///
/// This is the same rule the window buttons already follow, where reversing is
/// what keeps Close on the outside.
public func footerOrder(alignedTrailing: Bool) -> [FooterButton] {
    let leadingOrder: [FooterButton] = [.projects, .profile, .settings]
    return alignedTrailing ? leadingOrder.reversed() : leadingOrder
}
