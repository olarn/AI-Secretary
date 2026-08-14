import Foundation

/// Which build of the app this is, as `major.phase.change`.
///
/// The number lives here, in code, rather than only in the packaging script's
/// `Info.plist`: the app has to be able to answer the question itself — in the
/// About window, and in a bug report where the `.plist` isn't to hand. The
/// script reads this declaration when it assembles the bundle, so the two can't
/// drift apart. Bump it here and the bundle follows.
///
/// The three parts are not semantic versioning, and are named `major`,
/// `minor`, `patch` only because that is what the fields have always been
/// called:
///
/// - **major** — `0` until the app is published. The owner says when.
/// - **phase** — which phase of the charter the work belongs to. The digit
///   itself is written down once, in the charter's Versioning and packaging
///   section, and this comment deliberately doesn't repeat it: the copy that
///   used to live here said 9 long after the charter said 10. Moved by hand
///   when the work moves on, not derived — the backlog lists phases nobody has
///   started, so the highest heading is not the current one.
/// - **change** — one per completed change, five for five. It never resets, so
///   it only ever counts up and two builds can't share a number.
///
/// Because the middle part tracks a phase rather than progress, `<` is only
/// meaningful within one phase: 0.6.51 is newer code than 0.9.0, which was
/// numbered under the previous scheme.
public struct AppVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    /// The current version. Keep the literal on one line and in this shape —
    /// `scripts/package-app.sh` parses it to fill in `CFBundleShortVersionString`.
    public static let current = AppVersion(major: 0, minor: 14, patch: 247)

    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    /// Ordered the way versions are meant to be: major first, then minor, then
    /// patch — so `0.10.0` is newer than `0.9.9` rather than sorting as text.
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The app's own identity, in one place. The name is used by the status bar
/// menu, the About window, and the bundle, and a second spelling of it would
/// show up as two different apps to the user.
public enum AppInfo: Sendable {
    public static let name = "AI Secretary"
    public static let version = AppVersion.current

    /// The commit this bundle was built from, stamped in by
    /// `scripts/package-app.sh`. Absent when running straight from the SwiftPM
    /// build directory, where there is no bundle to stamp.
    public static var build: String? {
        Bundle.main.infoDictionary?["AISecretaryBuild"] as? String
    }

    public static var branch: String? {
        Bundle.main.infoDictionary?["AISecretaryBranch"] as? String
    }

    /// What the app says when asked what it is — the label at the top of the
    /// status bar menu.
    ///
    /// Name and version only. The commit used to ride along in brackets, on the
    /// grounds that two bundles can carry the same version and different code;
    /// that is still true and is still answered, in About, which builds its own
    /// line from `build` and `branch`. What it does not need to be is the first
    /// thing in the menu every time it is opened — a seven-character hash in
    /// the header is noise to everyone who is not chasing exactly that
    /// question.
    public static var summary: String {
        "\(name) \(version)"
    }

    public static let tagline = "A desktop companion that works through your own Claude Code."
}
