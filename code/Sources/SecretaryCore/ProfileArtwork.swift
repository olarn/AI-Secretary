import Foundation
import AssistantState

/// Where a profile's pictures live, and which one applies right now.
///
/// Kept to `URL`s and the filesystem — no `NSImage` — so the resolution rules
/// are testable without a display, and so the app layer stays the only place
/// that decodes an image.
///
/// Pictures are stored outside the repository, under Application Support, for
/// the same reason the existing placeholder is: art the user supplies must never
/// end up committed or distributed with the project.
public struct ProfileArtwork: Sendable {
    public static let defaultFileName = "default.png"

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

    /// `nil` state means the profile's one required default picture.
    public func url(for profile: UUID, state: AssistantState?) -> URL {
        directory(for: profile)
            .appendingPathComponent(state.map { "\($0.rawValue).png" } ?? Self.defaultFileName)
    }

    /// The picture to show while the assistant is in `state`: the one uploaded
    /// for that state if there is one, otherwise the profile's default. `nil`
    /// means neither exists and the caller should fall back to the built-in
    /// avatar — a profile is allowed to have no pictures at all, so this is a
    /// normal outcome, not an error.
    public func resolve(
        profile: UUID,
        state: AssistantState,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        let specific = url(for: profile, state: state)
        if exists(specific) { return specific }
        let fallback = url(for: profile, state: nil)
        return exists(fallback) ? fallback : nil
    }

    /// Stores an uploaded picture. Copied rather than referenced because the user
    /// will eventually move or rename the original, and the character would
    /// silently go blank.
    ///
    /// The caller passes PNG bytes: the app layer decodes whatever the user
    /// chose (JPEG, HEIC…) and re-encodes, so the file on disk always matches
    /// its name.
    @discardableResult
    public func install(
        pngData: Data,
        for profile: UUID,
        state: AssistantState?
    ) throws -> URL {
        let destination = url(for: profile, state: state)
        try FileManager.default.createDirectory(
            at: directory(for: profile),
            withIntermediateDirectories: true
        )
        try pngData.write(to: destination, options: .atomic)
        return destination
    }

    public func remove(for profile: UUID, state: AssistantState?) throws {
        let target = url(for: profile, state: state)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Called when a profile is deleted, so its pictures don't outlive it.
    public func removeAll(for profile: UUID) throws {
        let directory = directory(for: profile)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// Which states the user has uploaded a separate picture for — drives the
    /// checkmarks in the settings list.
    public func statesWithArtwork(
        for profile: UUID,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Set<AssistantState> {
        Set(Self.artworkStates.filter { exists(url(for: profile, state: $0)) })
    }

    public func hasDefaultArtwork(
        for profile: UUID,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Bool {
        exists(url(for: profile, state: nil))
    }

    /// The states worth a separate picture. All of them, in lifecycle order —
    /// the charter names Idle and Thinking as the ones that matter, and the rest
    /// fall back to the default anyway.
    public static let artworkStates: [AssistantState] = [
        .idle, .listening, .thinking, .working, .success, .error
    ]
}
