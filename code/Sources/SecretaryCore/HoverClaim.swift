import Foundation

/// Which box in the transcript shows its pin and copy buttons, after one
/// pointer event.
///
/// One value for the whole thread rather than a flag per box: the pointer is
/// only ever in one place, and a flag each is a set of them that can all be
/// true at once after a fast drag.
///
/// The clause that earns this a function of its own is the second one. A box
/// being left may **not** clear the claim unless it still holds it: moving from
/// one box to the next delivers the new box's enter before the old box's leave,
/// so a leave that cleared unconditionally would wipe a claim that has already
/// moved on.
///
/// **Only the box reports.** The buttons hang off its corner, but they sit in
/// the box's overlay, and a view's hover region includes its overlay — measured
/// in the running app: gliding from the middle of a box onto its copy button
/// produces enters and no leave. The buttons used to report as well, on the
/// theory that reaching them meant leaving the box, and that extra reporting is
/// what broke them: moving from copy to pin fired copy's *leave*, which
/// released the claim and unmounted both buttons out from under the pointer.
/// The pin button was unclickable. Nothing but the box may report, or that
/// comes back.
public func hoverClaim<Box: Equatable>(
    current: Box?,
    box: Box,
    pointerIsInside: Bool
) -> Box? {
    guard !pointerIsInside else { return box }
    return current == box ? nil : current
}
