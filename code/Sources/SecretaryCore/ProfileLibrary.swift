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
    /// Bumped whenever the pictures on disk change. The character's image is
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

        let saved = (try? store.load()) ?? ProfileSelection()
        // First launch, or a file that somehow lost its contents: the built-in
        // character is seeded so the app always has someone to be.
        let profiles = saved.profiles.isEmpty ? [.miku] : saved.profiles
        self.profiles = profiles
        self.activeID = saved.activeID.flatMap { id in
            profiles.contains(where: { $0.id == id }) ? id : nil
        } ?? profiles[0].id
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

    /// Removes the profile and its pictures. Refuses the last one.
    public func delete(_ id: UUID) {
        guard canDelete, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        try? artwork.removeAll(for: id)
        artworkRevision += 1
        let switched = id == activeID
        if switched { activeID = profiles[0].id }
        persist()
        if switched { onActiveChange?(active) }
    }

    // MARK: - Pictures

    /// Copies a chosen image in and reports the change, so the character reloads
    /// without waiting for the next state transition.
    public func setArtwork(pngData: Data, state: AssistantState?, for id: UUID) throws {
        try artwork.install(pngData: pngData, for: id, state: state)
        artworkRevision += 1
        if id == activeID { onActiveChange?(active) }
    }

    public func clearArtwork(state: AssistantState?, for id: UUID) {
        try? artwork.remove(for: id, state: state)
        artworkRevision += 1
        if id == activeID { onActiveChange?(active) }
    }

    /// The picture for the active profile in this state, or `nil` to fall back
    /// to the built-in avatar.
    public func artworkURL(for state: AssistantState) -> URL? {
        artwork.resolve(profile: activeID, state: state)
    }

    public func hasDefaultArtwork(for id: UUID) -> Bool {
        artwork.hasDefaultArtwork(for: id)
    }

    public func statesWithArtwork(for id: UUID) -> Set<AssistantState> {
        artwork.statesWithArtwork(for: id)
    }

    private func persist() {
        try? store.save(ProfileSelection(profiles: profiles, activeID: activeID))
    }
}
