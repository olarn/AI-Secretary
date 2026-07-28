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

    func testSwitchingReportsTheNewProfileAndPersists() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, store) = makeLibrary(ProfileSelection(profiles: [.miku, kai], activeID: .some(SecretaryProfile.miku.id)))

        var announced: [String] = []
        library.onActiveChange = { announced.append($0.displayName) }

        library.activate(kai.id)

        XCTAssertEqual(announced, ["Kai"])
        XCTAssertEqual(store.load().map(\.activeID)^, .right(.some(kai.id)))
    }

    func testSwitchingToTheProfileAlreadyActiveDoesNothing() {
        let (library, _) = makeLibrary()
        var changes = 0
        library.onActiveChange = { _ in changes += 1 }

        library.activate(library.activeID)

        XCTAssertEqual(changes, 0)
    }

    /// Creating a profile you then have to go and select is a step nobody wants.
    func testANewProfileBecomesActive() {
        let (library, _) = makeLibrary()
        library.add(SecretaryProfile(name: "Kai"))
        XCTAssertEqual(library.active.displayName, "Kai")
        XCTAssertEqual(library.profiles.count, 2)
    }

    /// Renaming the active profile is a live change too — the transcript label
    /// and the system prompt both follow it.
    func testEditingTheActiveProfileReportsTheChange() {
        let (library, store) = makeLibrary()
        var announced: [String] = []
        library.onActiveChange = { announced.append($0.displayName) }

        var edited = library.active
        edited.name = "Mika"
        library.update(edited)

        XCTAssertEqual(announced, ["Mika"])
        XCTAssertEqual(store.load().map { $0.profiles.first?.name }^, .right("Mika"))
    }

    func testEditingAnInactiveProfileDoesNotReportAChange() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, _) = makeLibrary(
            ProfileSelection(profiles: [.miku, kai], activeID: .some(SecretaryProfile.miku.id))
        )
        var changes = 0
        library.onActiveChange = { _ in changes += 1 }

        var edited = kai
        edited.style = "like a friend"
        library.update(edited)

        XCTAssertEqual(changes, 0)
        XCTAssertEqual(library.profiles.last?.style, "like a friend")
    }

    /// The app can't be nobody, so the last profile isn't deletable.
    func testTheLastProfileCannotBeDeleted() {
        let (library, _) = makeLibrary()
        XCTAssertFalse(library.canDelete)

        library.delete(library.activeID)

        XCTAssertEqual(library.profiles.count, 1)
    }

    func testDeletingTheActiveProfileFallsBackToAnother() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, _) = makeLibrary(ProfileSelection(profiles: [.miku, kai], activeID: .some(kai.id)))
        var announced: [String] = []
        library.onActiveChange = { announced.append($0.displayName) }

        library.delete(kai.id)

        XCTAssertEqual(library.profiles.map(\.name), ["Miku"])
        XCTAssertEqual(announced, ["Miku"])
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
