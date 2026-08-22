import Foundation

public struct AppVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    public static let current = AppVersion(major: 0, minor: 23, patch: 359)

    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum AppInfo: Sendable {
    public static let name = "AI Secretary"
    public static let version = AppVersion.current

    public static var build: String? {
        Bundle.main.infoDictionary?["AISecretaryBuild"] as? String
    }

    public static var branch: String? {
        Bundle.main.infoDictionary?["AISecretaryBranch"] as? String
    }

    public static var statusMenuHeader: String {
        "\(name) \(version)"
    }

    public static let tagline = "A desktop companion that works through your own Claude Code."
}
