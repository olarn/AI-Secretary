import FunctionalCore
import Foundation
import Observation
import AssistantState

/// The profiles the user has, and which one the app is wearing right now.
///
/// Holds the list, persists every change, and reports the active profile so the
/// character art, the chat header, and the system prompt all follow one source.
/// `onActiveChange` is a callback rather than observation because switching has
/// imperative consequences — the Secretary's prompt changes and the character
/// window has to reload its picture — that must happen once per change, not
/// during a view update.
@MainActor
@Observable
public final class ProfileLibrary {
    public private(set) var profiles: [SecretaryProfile]
    public private(set) var activeID: UUID
    /// Bumped whenever the picture on disk changes. The character's image is
    /// looked up from the filesystem, which SwiftUI can't observe, so this is
    /// what tells the view its picture is stale.
    public private(set) var artworkRevision = 0

    @ObservationIgnored private let store: ProfileStoring
    @ObservationIgnored private let artwork: ProfileArtwork
    @ObservationIgnored public var onActiveChange: ((SecretaryProfile) -> Void)?

    public init(
        store: ProfileStoring = FileProfileStore(),
        artwork: ProfileArtwork = ProfileArtwork()
    ) {
        self.store = store
        self.artwork = artwork

        // A profile file that cannot be read starts empty rather than blocking
        // launch; the seeding below then gives the app someone to be.
        let saved = store.load().getOrElse(ProfileSelection())
        // First launch, or a file that somehow lost its contents: the built-in
        // character is seeded so the app always has someone to be.
        let seeded = saved.profiles.isEmpty
        let profiles: [SecretaryProfile] = seeded ? [SecretaryProfile.miku] : saved.profiles
        self.profiles = profiles
        // A saved id that no longer names a profile is treated as unset.
        self.activeID = saved.activeID
            .filter { id in profiles.contains { $0.id == id } }^
            .getOrElse(profiles[0].id)

        // Written out immediately rather than on the first edit, so a fresh
        // install has a real default profile on disk — Miku, active — instead of
        // one that only exists in memory until something changes.
        if seeded || saved.activeID != Option.some(activeID) { persist() }

        // Pictures used to have a slot per state. Carry whichever one the user
        // had over to the single slot, so nobody loses their character.
        for profile in self.profiles { artwork.migrateLegacyArtwork(for: profile.id) }
    }

    public var active: SecretaryProfile {
        profiles.first { $0.id == activeID } ?? profiles[0]
    }

    /// Deleting the last profile is not offered: the app has to be someone.
    public var canDelete: Bool { profiles.count > 1 }

    // MARK: - Changes

    public func activate(_ id: UUID) {
        guard id != activeID, profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        persist()
        onActiveChange?(active)
    }

    /// Adds and switches to it, because creating a profile you then have to go
    /// and select is a step nobody wants.
    public func add(_ profile: SecretaryProfile) {
        guard !profiles.contains(where: { $0.id == profile.id }) else { return }
        profiles.append(profile)
        activeID = profile.id
        persist()
        onActiveChange?(active)
    }

    /// Edits in place. Renaming the active profile is a live change too — the
    /// name in the transcript and the prompt both follow it.
    public func update(_ profile: SecretaryProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        guard profiles[index] != profile else { return }
        profiles[index] = profile
        persist()
        if profile.id == activeID { onActiveChange?(active) }
    }

    /// Removes the profile and its picture. Refuses the last one.
    public func delete(_ id: UUID) {
        guard canDelete, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        artwork.removeAll(for: id)
        artworkRevision += 1
        let switched = id == activeID
        if switched { activeID = profiles[0].id }
        persist()
        if switched { onActiveChange?(active) }
    }

    // MARK: - Picture

    /// Copies a chosen image in and reports the change, so the character reloads
    /// without waiting for the next state transition.
    @discardableResult
    public func setArtwork(pngData: Data, for id: UUID) -> Either<ArtworkError, URL> {
        artwork.install(pngData: pngData, for: id)
            .map { installed in
                self.artworkRevision += 1
                if id == self.activeID { self.onActiveChange?(self.active) }
                return installed
            }^
    }

    @discardableResult
    public func clearArtwork(for id: UUID) -> Either<ArtworkError, Void> {
        artwork.remove(for: id)
            .map {
                self.artworkRevision += 1
                if id == self.activeID { self.onActiveChange?(self.active) }
            }^
    }

    /// The active profile's picture, absent when the built-in avatar should be
    /// used instead.
    public func artworkURL() -> Option<URL> {
        artwork.resolve(profile: activeID)
    }

    public func hasArtwork(for id: UUID) -> Bool {
        artwork.hasArtwork(for: id)
    }

    private func persist() {
        store.save(ProfileSelection(profiles: profiles, activeID: .some(activeID)))
    }
}
