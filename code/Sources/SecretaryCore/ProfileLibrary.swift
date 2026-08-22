import FunctionalCore
import Foundation
import Observation
import AssistantState

@MainActor
@Observable
public final class ProfileLibrary {
    public private(set) var profiles: [SecretaryProfile]
    public private(set) var activeID: UUID
    public private(set) var artworkRevision = 0

    @ObservationIgnored private let store: ProfileStoring
    @ObservationIgnored private let artwork: ProfileArtwork
    @ObservationIgnored public var onRosterChange: (() -> Void)?
    @ObservationIgnored public var onProfileChange: ((SecretaryProfile) -> Void)?

    public init(
        store: ProfileStoring = FileProfileStore(),
        artwork: ProfileArtwork = ProfileArtwork()
    ) {
        self.store = store
        self.artwork = artwork

        let saved = store.load().getOrElse(ProfileSelection())
        let seeded = ProfileLibrary.thereIsNobodyForTheAppToBeYet(saved)
        let profiles: [SecretaryProfile] = seeded ? [SecretaryProfile.miku] : saved.profiles
        self.profiles = profiles
        self.activeID = saved.activeID
            .filter { id in profiles.contains { $0.id == id } }^
            .getOrElse(profiles[0].id)

        if seeded || saved.activeID != Option.some(activeID) { persist() }

        for profile in self.profiles { artwork.migrateLegacyArtwork(for: profile.id) }
    }

    private static func thereIsNobodyForTheAppToBeYet(_ saved: ProfileSelection) -> Bool {
        saved.profiles.isEmpty
    }

    public var active: SecretaryProfile {
        profiles.first { $0.id == activeID } ?? profiles[0]
    }

    public var canDelete: Bool { profiles.count > 1 }

    public func activate(_ id: UUID) {
        guard id != activeID, profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        persist()
    }

    public func add(_ profile: SecretaryProfile) {
        guard !profiles.contains(where: { $0.id == profile.id }) else { return }
        profiles.append(profile)
        activeID = profile.id
        persist()
        onRosterChange?()
    }

    public func update(_ profile: SecretaryProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        guard profiles[index] != profile else { return }
        profiles[index] = profile
        persist()
        onProfileChange?(profile)
    }

    public func delete(_ id: UUID) {
        guard canDelete, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles.remove(at: index)
        artwork.removeAll(for: id)
        artworkRevision += 1
        if id == activeID { activeID = profiles[0].id }
        persist()
        onRosterChange?()
    }

    @discardableResult
    public func setArtwork(pngData: Data, for id: UUID) -> Either<ArtworkError, URL> {
        artwork.install(pngData: pngData, for: id)
            .map { installed in
                self.artworkRevision += 1
                return installed
            }^
    }

    @discardableResult
    public func clearArtwork(for id: UUID) -> Either<ArtworkError, Void> {
        artwork.remove(for: id)
            .map {
                self.artworkRevision += 1
            }^
    }

    public func artworkURL() -> Option<URL> {
        artwork.resolve(profile: activeID)
    }

    public func artworkURL(for id: UUID) -> Option<URL> {
        artwork.resolve(profile: id)
    }

    public func profile(_ id: UUID) -> SecretaryProfile {
        profiles.first { $0.id == id } ?? active
    }

    public func hasArtwork(for id: UUID) -> Bool {
        artwork.hasArtwork(for: id)
    }

    @discardableResult
    private func persist() -> Either<ProfileStoreError, Void> {
        store.save(ProfileSelection(profiles: profiles, activeID: .some(activeID)))
    }
}
