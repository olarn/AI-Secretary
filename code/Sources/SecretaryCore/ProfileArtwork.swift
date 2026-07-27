import Foundation
import AssistantState

/// Where a profile's picture lives.
///
/// One picture per profile. Uploading a separate picture per state was more
/// work than it was worth — the state already reads from the halo colour, the
/// badge, and the label under the character — so there is a single slot.
///
/// Kept to `URL`s and the filesystem — no `NSImage` — so the resolution rules
/// are testable without a display, and so the app layer stays the only place
/// that decodes an image.
///
/// Pictures are stored outside the repository, under Application Support, for
/// the same reason the existing placeholder is: art the user supplies must never
/// end up committed or distributed with the project.
public struct ProfileArtwork: Sendable {
    public static let fileName = "picture.png"

    public let root: URL

    public init(root: URL = ProfileArtwork.defaultRoot) {
        self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    /// One directory per profile, keyed by id, so deleting a profile is a single
    /// directory removal and two profiles can't collide on a file name.
    public func directory(for profile: UUID) -> URL {
        root.appendingPathComponent(profile.uuidString, isDirectory: true)
    }

    public func url(for profile: UUID) -> URL {
        directory(for: profile).appendingPathComponent(Self.fileName)
    }

    /// The picture to show, or `nil` if there isn't one and the caller should
    /// fall back to the built-in avatar. A profile with no picture is normal, so
    /// this is an ordinary outcome rather than an error.
    public func resolve(
        profile: UUID,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        let picture = url(for: profile)
        return exists(picture) ? picture : nil
    }

    public func hasArtwork(
        for profile: UUID,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Bool {
        exists(url(for: profile))
    }

    /// Stores an uploaded picture. Copied rather than referenced because the user
    /// will eventually move or rename the original, and the character would
    /// silently go blank.
    ///
    /// The caller passes PNG bytes: the app layer decodes whatever the user
    /// chose (JPEG, HEIC…) and re-encodes, so the file on disk always matches
    /// its name.
    @discardableResult
    public func install(pngData: Data, for profile: UUID) throws -> URL {
        let destination = url(for: profile)
        try FileManager.default.createDirectory(
            at: directory(for: profile),
            withIntermediateDirectories: true
        )
        try pngData.write(to: destination, options: .atomic)
        return destination
    }

    public func remove(for profile: UUID) throws {
        let target = url(for: profile)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Called when a profile is deleted, so its picture doesn't outlive it.
    public func removeAll(for profile: UUID) throws {
        let directory = directory(for: profile)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Migration

    /// File names written back when pictures were per-state, in the order they
    /// should be preferred. Someone who uploaded only a `thinking` picture and
    /// no default would otherwise open the app to a blank character.
    static let legacyFileNames: [String] = ["default.png"]
        + [AssistantState.idle, .listening, .thinking, .working, .success, .error]
            .map { "\($0.rawValue).png" }

    /// Promotes the first picture from the old per-state layout into the single
    /// picture slot. Copies rather than moves, and leaves the other old files
    /// alone: they're a few KB of dead weight in Application Support, which is a
    /// better trade than deleting something the user uploaded.
    ///
    /// Does nothing once a picture exists, so it's safe to call on every launch.
    public func migrateLegacyArtwork(for profile: UUID) {
        let manager = FileManager.default
        let destination = url(for: profile)
        guard !manager.fileExists(atPath: destination.path) else { return }

        let directory = directory(for: profile)
        for name in Self.legacyFileNames {
            let candidate = directory.appendingPathComponent(name)
            guard manager.fileExists(atPath: candidate.path) else { continue }
            try? manager.copyItem(at: candidate, to: destination)
            return
        }
    }
}
