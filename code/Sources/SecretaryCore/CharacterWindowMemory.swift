import CoreGraphics
import Foundation

public func characterOriginKey(_ character: UUID) -> String {
    "character.\(character.uuidString).origin"
}

public func savedCharacterOrigin(
    saved: String?,
    size: CGSize,
    screenFrame: CGRect,
    minimumVisible: Double = 24
) -> CGPoint? {
    let parsed = saved
        .map { $0.split(separator: ",").compactMap { Double($0) } }
        .flatMap { parts in parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil }
    guard let origin = parsed else { return nil }

    let frame = CGRect(origin: origin, size: size)
    let visible = frame.intersection(screenFrame)
    guard visible.width >= minimumVisible, visible.height >= minimumVisible else { return nil }
    return origin
}

public func characterOriginString(_ origin: CGPoint) -> String {
    commandWindowOriginString(origin)
}
