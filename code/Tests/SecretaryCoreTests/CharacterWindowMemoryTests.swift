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

    func testASpotOnADisplayThatIsGoneFallsBackToTheDefault() {
        XCTAssertNil(savedCharacterOrigin(saved: "2600,120", size: size, screenFrame: screen))
        XCTAssertNil(savedCharacterOrigin(saved: "300,-400", size: size, screenFrame: screen))
    }

    func testASliverDoesNotCountAsOnScreen() {
        XCTAssertNil(savedCharacterOrigin(saved: "1590,120", size: size, screenFrame: screen))
        XCTAssertEqual(
            savedCharacterOrigin(saved: "1570,120", size: size, screenFrame: screen),
            CGPoint(x: 1570, y: 120)
        )
    }

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
