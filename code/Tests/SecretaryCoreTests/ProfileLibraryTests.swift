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

    func testAStateWithItsOwnPictureUsesIt() {
        let resolved = artwork.resolve(
            profile: profile,
            state: .thinking,
            exists: exists(["thinking.png", "default.png"])
        )
        XCTAssertEqual(resolved?.lastPathComponent, "thinking.png")
    }

    /// Asked for: only one picture is required, and the rest fall back to it.
    func testAStateWithoutAPictureFallsBackToTheDefault() {
        let resolved = artwork.resolve(
            profile: profile,
            state: .working,
            exists: exists(["default.png"])
        )
        XCTAssertEqual(resolved?.lastPathComponent, "default.png")
    }

    /// A profile is allowed to have no pictures at all — the caller then keeps
    /// the built-in avatar, so this must be nil rather than a missing-file URL.
    func testNoPicturesAtAllResolvesToNothing() {
        XCTAssertNil(artwork.resolve(profile: profile, state: .idle, exists: exists([])))
    }

    func testEachProfileGetsItsOwnDirectory() {
        let other = UUID()
        XCTAssertNotEqual(artwork.directory(for: profile), artwork.directory(for: other))
        XCTAssertTrue(artwork.directory(for: profile).path.contains(profile.uuidString))
    }

    func testUploadedStatesAreReported() {
        let states = artwork.statesWithArtwork(
            for: profile,
            exists: exists(["idle.png", "thinking.png"])
        )
        XCTAssertEqual(states, [.idle, .thinking])
        XCTAssertFalse(artwork.hasDefaultArtwork(for: profile, exists: exists(["idle.png"])))
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

        let written = try artwork.install(pngData: data, for: profile, state: .thinking)
        XCTAssertEqual(try Data(contentsOf: written), data)
        XCTAssertEqual(artwork.statesWithArtwork(for: profile), [.thinking])

        try artwork.remove(for: profile, state: .thinking)
        XCTAssertTrue(artwork.statesWithArtwork(for: profile).isEmpty)

        try artwork.install(pngData: data, for: profile, state: nil)
        try artwork.removeAll(for: profile)
        XCTAssertFalse(artwork.hasDefaultArtwork(for: profile))
    }

    /// Removing something that isn't there is how "Clear" behaves after a
    /// failed upload; it must not throw.
    func testRemovingAMissingPictureIsNotAnError() {
        XCTAssertNoThrow(try artwork.remove(for: profile, state: .idle))
        XCTAssertNoThrow(try artwork.removeAll(for: profile))
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

    func testTheActiveProfileIsRemembered() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, _) = makeLibrary(
            ProfileSelection(profiles: [.miku, kai], activeID: kai.id)
        )
        XCTAssertEqual(library.active.name, "Kai")
    }

    /// A saved id that no longer matches a profile — deleted by an older build,
    /// or a hand-edited file — must not leave the app with nobody active.
    func testAnUnknownSavedIDFallsBackToTheFirstProfile() {
        let (library, _) = makeLibrary(
            ProfileSelection(profiles: [.miku], activeID: UUID())
        )
        XCTAssertEqual(library.active.name, "Miku")
    }

    func testSwitchingReportsTheNewProfileAndPersists() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, store) = makeLibrary(ProfileSelection(profiles: [.miku, kai], activeID: SecretaryProfile.miku.id))

        var announced: [String] = []
        library.onActiveChange = { announced.append($0.displayName) }

        library.activate(kai.id)

        XCTAssertEqual(announced, ["Kai"])
        XCTAssertEqual(try? store.load().activeID, kai.id)
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
        XCTAssertEqual(try? store.load().profiles.first?.name, "Mika")
    }

    func testEditingAnInactiveProfileDoesNotReportAChange() {
        let kai = SecretaryProfile(name: "Kai")
        let (library, _) = makeLibrary(
            ProfileSelection(profiles: [.miku, kai], activeID: SecretaryProfile.miku.id)
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
        let (library, _) = makeLibrary(ProfileSelection(profiles: [.miku, kai], activeID: kai.id))
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

        try library.setArtwork(pngData: Data("x".utf8), state: .thinking, for: library.activeID)

        XCTAssertGreaterThan(library.artworkRevision, before)
        XCTAssertNotNil(library.artworkURL(for: .thinking))
        XCTAssertNil(library.artworkURL(for: .idle), "No default picture yet, so idle has none")
    }
}
