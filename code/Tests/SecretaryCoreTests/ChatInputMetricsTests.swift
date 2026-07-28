import XCTest
@testable import SecretaryCore

/// The message box's two rules: how tall it's allowed to get, and what Return
/// does once it's more than one line.
final class ChatInputMetricsTests: XCTestCase {
    private let line: Double = 16

    // MARK: - Growing

    func testAnEmptyBoxIsOneLineTall() {
        XCTAssertEqual(ChatInputMetrics.height(forContent: 0, lineHeight: line), line)
    }

    /// Asked for: a line at a time, 1 → 2 → 3 → 4 → 5.
    func testItGrowsALineAtATime() {
        for lines in 1...5 {
            XCTAssertEqual(
                ChatInputMetrics.height(forContent: line * Double(lines), lineHeight: line),
                line * Double(lines),
                "\(lines) lines of text should be \(lines) lines tall"
            )
        }
    }

    /// Asked for: past five it stops growing and scrolls instead.
    func testItStopsAtFiveLines() {
        XCTAssertEqual(ChatInputMetrics.height(forContent: line * 6, lineHeight: line), line * 5)
        XCTAssertEqual(ChatInputMetrics.height(forContent: line * 40, lineHeight: line), line * 5)
    }

    func testScrollingStartsOnlyPastTheFifthLine() {
        XCTAssertFalse(ChatInputMetrics.scrolls(contentHeight: line * 5, lineHeight: line))
        XCTAssertTrue(ChatInputMetrics.scrolls(contentHeight: line * 5.5, lineHeight: line))
        XCTAssertTrue(ChatInputMetrics.scrolls(contentHeight: line * 6, lineHeight: line))
    }

    /// A part-used line still needs a whole line of room, or its descenders are
    /// clipped.
    func testAPartLineRoundsUp() {
        XCTAssertEqual(ChatInputMetrics.height(forContent: line * 2.1, lineHeight: line), line * 3)
    }

    /// Before the text view has laid out, its line height can be zero; dividing
    /// by it would be a crash rather than a wrong size.
    func testAZeroLineHeightIsNotDividedBy() {
        XCTAssertEqual(ChatInputMetrics.height(forContent: 100, lineHeight: 0), 0)
        XCTAssertFalse(ChatInputMetrics.scrolls(contentHeight: 100, lineHeight: 0))
    }

    // MARK: - Return

    /// The box used to be one line, where Return sent the message. Growing it
    /// must not quietly take that away.
    func testReturnSends() {
        XCTAssertEqual(ChatInputMetrics.returnAction(shift: false, option: false), .send)
    }

    func testAModifierMakesANewLineInstead() {
        XCTAssertEqual(ChatInputMetrics.returnAction(shift: true, option: false), .newline)
        XCTAssertEqual(ChatInputMetrics.returnAction(shift: false, option: true), .newline)
    }
}
