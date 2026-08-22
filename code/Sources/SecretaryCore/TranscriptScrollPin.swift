import Foundation

public struct TranscriptScrollPin: Equatable, Sendable {
    public private(set) var isFollowing = true

    public init() {}

    public mutating func readerScrolledUp() {
        isFollowing = false
    }

    public mutating func update(distanceBelowFold: Double) {
        guard distanceBelowFold <= Self.settled else { return }
        isFollowing = true
    }

    public mutating func follow() {
        isFollowing = true
    }

    public static let settled: Double = 0.5

    public func isBehind(distanceBelowFold: Double) -> Bool {
        isFollowing && distanceBelowFold > Self.settled
    }
}

public func readerIsScrollingBack(scrollingDeltaY: Double) -> Bool {
    scrollingDeltaY > 0
}
