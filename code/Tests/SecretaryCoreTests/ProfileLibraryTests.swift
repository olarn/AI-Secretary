import FunctionalCore
import XCTest
import AssistantState
@testable import SecretaryCore

/// The picture-resolution rules, exercised against a fake filesystem so no test
/// touches the user's Application Support directory.
final class ProfileArtworkTests: XCTestCase {
    private let artwork = ProfileArtwork(root: URL(fileURLWithPath: "/tmp/does-not-exist"))
    private let profile = UUID()

    private func exists(_ present: Set<String>) -> (URL) -> Bool {
        { present.contains($0.lastPathComponent) }
    }

    /// One picture per profile — there is nothing to resolve per state.
    func testTheProfilePictureIsUsedWhenPresent() {
        let resolved = artwork.resolve(profile: profile, exists: exists(["picture.png"]))
        XCTAssertEqual(resolved.map(\.lastPathComponent)^, .some("picture.png"))
        XCTAssertTrue(artwork.hasArtwork(for: profile, exists: exists(["picture.png"])))
    }

    /// A profile is allowed to have no picture at all — the caller then keeps
    /// the built-in avatar, so this must be nil rather than a missing-file URL.
    func testNoPictureResolvesToNothing() {
        XCTAssertEqual(artwork.resolve(profile: profile, exists: exists([])), Option.none())
        XCTAssertFalse(artwork.hasArtwork(for: profile, exists: exists([])))
    }

    /// A leftover file from the per-state scheme is not the picture; only the
    /// migration may promote one, and only into the single slot.
    func testALeftoverStateFileIsNotUsedDirectly() {
        XCTAssertEqual(artwork.resolve(profile: profile, exists: exists(["thinking.png"])), Option.none())
    }

    func testEachProfileGetsItsOwnDirectory() {
        let other = UUID()
        XCTAssertNotEqual(artwork.directory(for: profile), artwork.directory(for: other))
        XCTAssertTrue(artwork.directory(for: profile).path.contains(profile.uuidString))
    }

    /// Pictures must stay out of the repository — they're the user's own files
    /// and some of them will be licensed art.
    func testPicturesLiveUnderApplicationSupport() {
        XCTAssertTrue(ProfileArtwork.defaultRoot.path.contains("Application Support"))
        XCTAssertTrue(ProfileArtwork.defaultRoot.path.hasSuffix("AISecretary/Profiles"))
    }

    /// Round-trip through the real filesystem, in a temporary directory.
    func testInstallingWritesTheBytesAndRemovingDeletesThem() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileArtworkTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let artwork = ProfileArtwork(root: root)
        let data = Data("not really a png".utf8)

        let written = try XCTUnwrap(artwork.install(pngData: data, for: profile).toOption().toOptional())
        XCTAssertEqual(try Data(contentsOf: written), data)
        XCTAssertTrue(artwork.hasArtwork(for: profile))

        XCTAssertTrue(artwork.remove(for: profile).isRight)
        XCTAssertFalse(artwork.hasArtwork(for: profile))

        try artwork.install(pngData: data, for: profile)
        try artwork.removeAll(for: profile)
        XCTAssertFalse(artwork.hasArtwork(for: profile))
    }

    /// Choosing a second picture replaces the first rather than piling up.
    func testInstallingAgainReplacesThePicture() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileArtworkTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let artwork = ProfileArtwork(root: root)

        try artwork.install(pngData: Data("first".utf8), for: profile)
        try artwork.install(pngData: Data("second".utf8), for: profile)

        XCTAssertEqual(try Data(contentsOf: artwork.url(for: profile)), Data("second".utf8))
    }

    /// Removing something that isn't there is how "Clear" behaves after a
    /// failed upload; it must not throw.
    func testRemovingAMissingPictureIsNotAnError() {
        XCTAssertNoThrow(try artwork.remove(for: profile))
        XCTAssertNoThrow(try artwork.removeAll(for: profile))
    }

    // MARK: - Migration from per-state pictures

    /// Someone who uploaded a picture under the old per-state scheme keeps it,
    /// rather than opening the app to a blank character.
    func testALegacyStatePictureBecomesTheProfilePicture() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileArtworkTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let artwork = ProfileArtwork(root: root)
        let data = Data("legacy".utf8)

        try FileManager.default.createDirectory(
            at: artwork.directory(for: profile),
            withIntermediateDirectories: true
        )
        try data.write(to: artwork.directory(for: profile).appendingPathComponent("thinking.png"))

        artwork.migrateLegacyArtwork(for: profile)
        XCTAssertEqual(try Data(contentsOf: artwork.url(for: profile)), data)
    }

    /// The old default outranks a state picture, and the migration must never
    /// overwrite a picture that's already there — it runs on every launch.
    func testMigrationPrefersTheOldDefaultAndNeverOverwrites() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileArtworkTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let artwork = ProfileArtwork(root: root)
        let directory = artwork.directory(for: profile)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("old-default".utf8).write(to: directory.appendingPathComponent("default.png"))
        try Data("idle".utf8).write(to: directory.appendingPathComponent("idle.png"))

        artwork.migrateLegacyArtwork(for: profile)
        XCTAssertEqual(try Data(contentsOf: artwork.url(for: profile)), Data("old-default".utf8))

        artwork.migrateLegacyArtwork(for: profile)
        XCTAssertEqual(try Data(contentsOf: artwork.url(for: profile)), Data("old-default".utf8))
    }

    func testMigrationDoesNothingWithoutLegacyFiles() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileArtworkTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let artwork = ProfileArtwork(root: root)

        artwork.migrateLegacyArtwork(for: profile)
        XCTAssertFalse(artwork.hasArtwork(for: profile))
    }
}

@MainActor
final class ProfileLibraryTests: XCTestCase {
    private func makeLibrary(_ selection: ProfileSelection = ProfileSelection()) -> (ProfileLibrary, InMemoryProfileStore) {
        let store = InMemoryProfileStore(selection: selection)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProfileLibraryTests-\(UUID().uuidString)")
        return (ProfileLibrary(store: store, artwork: ProfileArtwork(root: root)), store)
    }

    /// The app has to be someone on a first run.
    func testAFirstRunSeedsTheBuiltInCharacter() {
        let (library, _) = makeLibrary()
        XCTAssertEqual(library.profiles.count, 1)
        XCTAssertEqual(library.active.name, "Miku")
    }

    /// A fresh install must have a real default profile on disk, not one that
    /// exists only in memory until the user changes something.
    func testTheSeededDefaultIsWrittenOutOnAFirstRun() throws {
        let (_, store) = makeLibrary()
        let saved = try XCTUnwrap(store.load().toOption().toOptional())
        XCTAssertEqual(saved.profiles.map(\.name), ["Miku"])
        XCTAssertEqual(saved.activeID, .some(SecretaryProfile.miku.id), "and it's the active one")
    }

    /// Seeding twice would multiply the built-in character, so its id is fixed.
    func testRelaunchingDoesNotSeedASecondMiku() throws {
        let (first, store) = makeLibrary()
        _ = first
        let reopened = ProfileLibrary(store: store, artwork: ProfileArtwork(root: URL(fileURLWithPath: "/tmp/none")))
        XCTAssertEqual(reopened.profiles.count, 1)
        XCTAssertEqual(reopened.active.id, SecretaryProfile.miku.id)
    }

    func testTheActiveProfileIsRemembered() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, _) = makeLibrary(
            ProfileSelection(profiles: [.miku, kai], activeID: .some(kai.id))
        )
        XCTAssertEqual(library.active.name, "Kai")
    }

    /// A saved id that no longer matches a profile — deleted by an older build,
    /// or a hand-edited file — must not leave the app with nobody active.
    func testAnUnknownSavedIDFallsBackToTheFirstProfile() {
        let (library, _) = makeLibrary(
            ProfileSelection(profiles: [.miku], activeID: .some(UUID()))
        )
        XCTAssertEqual(library.active.name, "Miku")
    }

    /// `activeID` stopped meaning "the one you can see" when every profile
    /// became a character on the desktop. It now names who a new character is
    /// cloned from, and who the app falls back to — so switching persists, and
    /// announces nothing, because nothing on screen changes.
    func testSwitchingPersistsTheChoice() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, store) = makeLibrary(ProfileSelection(profiles: [.miku, kai], activeID: .some(SecretaryProfile.miku.id)))
        var rosterChanges = 0
        library.onRosterChange = { rosterChanges += 1 }

        library.activate(kai.id)

        XCTAssertEqual(library.active.displayName, "Kai")
        XCTAssertEqual(store.load().map(\.activeID)^, .right(.some(kai.id)))
        // Nobody arrived or left, so the roster is not rebuilt.
        XCTAssertEqual(rosterChanges, 0)
    }

    func testSwitchingToTheProfileAlreadyActiveDoesNothing() {
        let (library, store) = makeLibrary()
        let before = library.activeID

        library.activate(library.activeID)

        XCTAssertEqual(library.activeID, before)
        XCTAssertEqual(store.load().map(\.activeID)^, .right(.some(before)))
    }

    /// Creating a profile you then have to go and select is a step nobody wants.
    func testANewProfileBecomesActive() {
        let (library, _) = makeLibrary()
        library.add(SecretaryProfile(name: "Kai"))
        XCTAssertEqual(library.active.displayName, "Kai")
        XCTAssertEqual(library.profiles.count, 2)
    }

    /// Renaming a profile is a live change — the transcript label and the
    /// system prompt both follow it.
    func testEditingAProfileReportsTheChange() {
        let (library, store) = makeLibrary()
        var announced: [String] = []
        library.onProfileChange = { (profile: SecretaryProfile) in announced.append(profile.displayName) }

        var edited = library.active
        edited.name = "Mika"
        library.update(edited)

        XCTAssertEqual(announced, ["Mika"])
        XCTAssertEqual(store.load().map { $0.profiles.first?.name }^, .right("Mika"))
    }

    /// This used to stay silent, and had to stop: an edit only reached the
    /// active profile's prompt, which was right while one profile was on screen
    /// and wrong the moment every profile is a character with a prompt of her
    /// own. The character being edited is now always told, active or not.
    func testEditingAnyProfileReachesThatProfile() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, _) = makeLibrary(
            ProfileSelection(profiles: [.miku, kai], activeID: .some(SecretaryProfile.miku.id))
        )
        var announced: [String] = []
        library.onProfileChange = { (profile: SecretaryProfile) in announced.append(profile.displayName) }

        var edited = kai
        edited.personality = "like a friend"
        library.update(edited)

        XCTAssertEqual(announced, ["Kai"])
        XCTAssertEqual(library.profiles.last?.personality, "like a friend")
    }

    /// The app can't be nobody, so the last profile isn't deletable.
    func testTheLastProfileCannotBeDeleted() {
        let (library, _) = makeLibrary()
        XCTAssertFalse(library.canDelete)

        library.delete(library.activeID)

        XCTAssertEqual(library.profiles.count, 1)
    }

    /// Deleting a profile is taking a character off the desktop, so the roster
    /// has to hear about it whether or not she was the active one — the app
    /// rebuilds its characters from this.
    func testDeletingAProfileTellsTheRoster() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, _) = makeLibrary(ProfileSelection(profiles: [.miku, kai], activeID: .some(kai.id)))
        var rosterChanges = 0
        library.onRosterChange = { rosterChanges += 1 }

        library.delete(kai.id)

        XCTAssertEqual(library.profiles.map(\.name), ["Miku"])
        XCTAssertEqual(rosterChanges, 1)
        // The fallback still happens: `activeID` names who a new character is
        // cloned from, and it must not point at somebody who has gone.
        XCTAssertEqual(library.activeID, SecretaryProfile.miku.id)
    }

    func testAddingAProfileTellsTheRoster() {
        let (library, _) = makeLibrary()
        var rosterChanges = 0
        library.onRosterChange = { rosterChanges += 1 }

        library.add(SecretaryProfile(name: "Anya"))

        XCTAssertEqual(rosterChanges, 1)
    }

    /// Renaming reaches the prompt, not just the label — and it says which
    /// character, since several are live at once.
    func testEditingAProfileAnnouncesWhichOneChanged() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, _) = makeLibrary(
            ProfileSelection(profiles: [.miku, kai], activeID: .some(SecretaryProfile.miku.id))
        )
        var announced: [String] = []
        library.onProfileChange = { (profile: SecretaryProfile) in announced.append(profile.displayName) }

        var renamed = kai
        renamed.name = "Kai the second"
        library.update(renamed)

        XCTAssertEqual(announced, ["Kai the second"])
    }

    /// The character's picture is read from disk, which SwiftUI can't observe.
    func testUploadingAPictureBumpsTheRevisionSoTheViewReloads() throws {
        let (library, _) = makeLibrary()
        let before = library.artworkRevision

        try library.setArtwork(pngData: Data("x".utf8), for: library.activeID)

        XCTAssertGreaterThan(library.artworkRevision, before)
        XCTAssertTrue(library.artworkURL().isDefined)

        library.clearArtwork(for: library.activeID)
        XCTAssertEqual(library.artworkURL(), Option.none())
    }
}
