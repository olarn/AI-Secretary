import XCTest
@testable import SecretaryCore

final class CommandWindowTests: XCTestCase {
    private let mikuID = UUID()
    private let pikachuID = UUID()
    private let dittoID = UUID()

    private func card(_ id: UUID, _ name: String) -> CharacterCard {
        CharacterCard(id: id, name: name, model: "Opus 5", effort: "Default")
    }

    private var miku: CharacterCard { card(mikuID, "Miku") }
    private var pikachu: CharacterCard { card(pikachuID, "Pikachu") }
    private var ditto: CharacterCard { card(dittoID, "Ditto") }
    private var roster: [CharacterCard] { [miku, pikachu, ditto] }

    // MARK: - Who receives a command

    func testNobodyTickedIsRefusedBeforeAnythingIsRead() {
        XCTAssertEqual(
            commandRecipients(for: "Miku pin this", selected: [], roster: roster),
            .needSelection
        )
    }

    func testACommandNamingNobodyGoesToEveryoneTicked() {
        XCTAssertEqual(
            commandRecipients(for: "สรุปงานของวันนี้ให้หน่อย", selected: [miku, pikachu], roster: roster),
            .send(to: [miku, pikachu])
        )
    }

    /// The backlog's own example: three ticked, one named, one runs.
    func testNamingOneTickedCharacterNarrowsToHerAlone() {
        XCTAssertEqual(
            commandRecipients(
                for: "Miku pin คำตอบล่าสุดไว้",
                selected: roster,
                roster: roster
            ),
            .send(to: [miku])
        )
    }

    func testNamingSeveralTickedCharactersSendsToThoseNamed() {
        XCTAssertEqual(
            commandRecipients(
                for: "Miku ทำข้อแรก Ditto ทำข้อสอง",
                selected: roster,
                roster: roster
            ),
            .send(to: [miku, ditto])
        )
    }

    /// Named but not ticked is a refusal with the name, never a silent send to
    /// somebody else — the recipient rule the hand-off path already lives by.
    func testNamingOnlyAnUntickedCharacterIsRefusedWithHerName() {
        XCTAssertEqual(
            commandRecipients(for: "Miku pin this", selected: [pikachu], roster: roster),
            .namedNotSelected(["Miku"])
        )
    }

    /// One named ticked, one named unticked: the ticked one runs. The unticked
    /// name is not a reason to stop the part that can go.
    func testAMixOfTickedAndUntickedNamesSendsToTheTickedOne() {
        XCTAssertEqual(
            commandRecipients(
                for: "Miku กับ Ditto ช่วยกันสรุป",
                selected: [miku, pikachu],
                roster: roster
            ),
            .send(to: [miku])
        )
    }

    /// Matching is `namesFor`: case-insensitive, and never on a name too short
    /// to trust.
    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(
            commandRecipients(for: "miku ทำอันนี้", selected: roster, roster: roster),
            .send(to: [miku])
        )
    }

    // MARK: - What each recipient is told

    func testASingleRecipientGetsTheInstructionsUntouched() {
        XCTAssertEqual(
            commandMessage(for: miku, among: [miku], instructions: "pin the last answer"),
            "pin the last answer"
        )
    }

    func testABroadcastCopyNamesTheRecipientAndTheOthers() {
        let message = commandMessage(
            for: miku,
            among: [miku, pikachu, ditto],
            instructions: "แบ่งกันเก็บกวาด backlog"
        )
        XCTAssertTrue(message.contains("you (Miku)"))
        XCTAssertTrue(message.contains("Pikachu, Ditto"))
        XCTAssertTrue(message.hasSuffix("แบ่งกันเก็บกวาด backlog"))
        // The divide-it-yourselves rule rides on every broadcast copy, because
        // whether work is assigned is the instruction's business, not ours.
        XCTAssertTrue(message.contains("divide it among yourselves"))
        XCTAssertTrue(message.contains("roles"))
    }

    func testEachRecipientHearsHerOwnName() {
        let toPikachu = commandMessage(
            for: pikachu,
            among: [miku, pikachu],
            instructions: "x"
        )
        XCTAssertTrue(toPikachu.contains("you (Pikachu)"))
        XCTAssertTrue(toPikachu.contains("Miku"))
    }

    // MARK: - Instruction files

    func testFilesMergeInDropOrderWithTypedTextLast() {
        XCTAssertEqual(
            mergedInstructions(files: ["first file", "second file"], typed: "note"),
            "first file\n\nsecond file\n\nnote"
        )
    }

    func testEmptyPartsVanishInsteadOfLeavingBlankGaps() {
        XCTAssertEqual(mergedInstructions(files: ["  ", "do this"], typed: ""), "do this")
        XCTAssertEqual(mergedInstructions(files: [], typed: "  just typed  "), "just typed")
        XCTAssertEqual(mergedInstructions(files: [], typed: " "), "")
    }

    // MARK: - Where the window sits

    private let screen = CGRect(x: 0, y: 0, width: 1600, height: 900)
    private let size = CGSize(width: 600, height: 200)

    func testNothingSavedOpensInTheMiddleOfTheScreen() {
        XCTAssertEqual(
            commandWindowOrigin(saved: nil, size: size, visibleFrame: screen),
            CGPoint(x: 500, y: 350)
        )
    }

    func testASavedOriginRoundTripsExactly() {
        let saved = commandWindowOriginString(CGPoint(x: 123.5, y: 456))
        XCTAssertEqual(
            commandWindowOrigin(saved: saved, size: size, visibleFrame: screen),
            CGPoint(x: 123.5, y: 456)
        )
    }

    /// A position saved on a display that has gone must not open the window
    /// where no click can reach it.
    func testAnOffScreenSaveIsClampedBackIn() {
        let saved = commandWindowOriginString(CGPoint(x: 5000, y: -300))
        XCTAssertEqual(
            commandWindowOrigin(saved: saved, size: size, visibleFrame: screen),
            CGPoint(x: 1000, y: 0)
        )
    }

    func testGarbageInTheDefaultsFallsBackToTheMiddle() {
        XCTAssertEqual(
            commandWindowOrigin(saved: "not,a,point", size: size, visibleFrame: screen),
            CGPoint(x: 500, y: 350)
        )
    }

    // MARK: - How wide it is

    func testNothingSavedGetsTheDefaultWidth() {
        XCTAssertEqual(commandWindowWidth(saved: nil), 620)
        XCTAssertEqual(commandWindowWidth(saved: 0), 620)
    }

    func testASavedWidthRoundTripsWithinTheClamp() {
        XCTAssertEqual(commandWindowWidth(saved: 700), 700)
        XCTAssertEqual(commandWindowWidth(saved: 100), 380)
        XCTAssertEqual(commandWindowWidth(saved: 5000), 1000)
    }

    // MARK: - The menu row

    func testTheMenuRowWordsItselfFromWhatIsOnScreen() {
        XCTAssertEqual(commandWindowMenuTitle(isVisible: true), "Hide Command")
        XCTAssertEqual(commandWindowMenuTitle(isVisible: false), "Show Command")
    }
}
