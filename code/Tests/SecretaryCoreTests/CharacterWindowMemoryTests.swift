import XCTest
@testable import SecretaryCore

final class CharacterWindowMemoryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
    private let size = CGSize(width: 90, height: 105)

    func testTheKeyIsBuiltFromTheCharacterInOnePlace() {
        let id = UUID()
        XCTAssertEqual(characterOriginKey(id), "character.\(id.uuidString).origin")
    }

    func testASavedSpotStillOnScreenComesBack() {
        XCTAssertEqual(
            savedCharacterOrigin(saved: "300,120", size: size, screenFrame: screen),
            CGPoint(x: 300, y: 120)
        )
    }

    /// The owner's rule: off the screen means the default position, not a
    /// clamp to the nearest edge.
    func testASpotOnADisplayThatIsGoneFallsBackToTheDefault() {
        XCTAssertNil(savedCharacterOrigin(saved: "2600,120", size: size, screenFrame: screen))
        XCTAssertNil(savedCharacterOrigin(saved: "300,-400", size: size, screenFrame: screen))
    }

    /// Mostly off is as unusable as fully off — a 5pt sliver cannot be
    /// grabbed. The threshold is what the default parameter says.
    func testASliverDoesNotCountAsOnScreen() {
        XCTAssertNil(savedCharacterOrigin(saved: "1590,120", size: size, screenFrame: screen))
        XCTAssertEqual(
            savedCharacterOrigin(saved: "1570,120", size: size, screenFrame: screen),
            CGPoint(x: 1570, y: 120)
        )
    }

    /// Standing on the Dock is normal — measured against the whole screen, so
    /// a character at the very bottom is still "on screen".
    func testStandingOnTheDockStillCounts() {
        XCTAssertEqual(
            savedCharacterOrigin(saved: "300,0", size: size, screenFrame: screen),
            CGPoint(x: 300, y: 0)
        )
    }

    func testGarbageAndNothingBothFallBack() {
        XCTAssertNil(savedCharacterOrigin(saved: nil, size: size, screenFrame: screen))
        XCTAssertNil(savedCharacterOrigin(saved: "not,a,point", size: size, screenFrame: screen))
    }

    func testTheEncodingRoundTrips() {
        XCTAssertEqual(
            savedCharacterOrigin(
                saved: characterOriginString(CGPoint(x: 421.5, y: 77)),
                size: size,
                screenFrame: screen
            ),
            CGPoint(x: 421.5, y: 77)
        )
    }
}
