import Foundation

public func hoverClaim<Box: Equatable>(
    current: Box?,
    box: Box,
    pointerIsInside: Bool
) -> Box? {
    guard !pointerIsInside else { return box }
    return current == box ? nil : current
}
