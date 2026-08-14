import XCTest
import FunctionalCore
@testable import SecretaryCore

/// The rules behind one character handing something to another.
///
/// All of it is decided in pure functions for the reason the charter gives: the
/// app target is never linked into the test bundle, so a rule that lives in
/// `CharacterBus` or in a view is a rule no test has ever run.
final class CharacterRelayTests: XCTestCase {
    private let miku = UUID()
    private let anya = UUID()
    private let ditto = UUID()
    /// Fixed, so an assertion about an expiry means the same thing at midnight.
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(
        _ id: UUID,
        _ name: String,
        model: String = "Opus 5",
        effort: String = "Default",
        project: String? = nil,
        busy: Bool = false
    ) -> CharacterCard {
        CharacterCard(
            id: id,
            name: name,
            model: model,
            effort: effort,
            projectName: Option.fromOptional(project),
            isBusy: busy
        )
    }

    private func errand(
        from: UUID = UUID(),
        to: UUID,
        hops: Int = 0,
        correlation: UUID = UUID(),
        kind: CharacterMessage.Kind = .errand
    ) -> CharacterMessage {
        CharacterMessage(
            from: from, fromName: "Miku", to: to, kind: kind,
            body: "find the price", correlationID: correlation, hops: hops, sentAt: noon
        )
    }

    // MARK: - The directory

    func testDirectoryLeavesOutTheCharacterItIsFor() {
        let all = [card(miku, "Miku"), card(anya, "Anya")]
        XCTAssertEqual(characterDirectory(all, excluding: miku).map(\.name), ["Anya"])
    }

    /// Roster order must not reach the prompt, or the same desktop produces a
    /// different system prompt every turn.
    func testDirectoryIsOrderedByNameWhateverOrderItArrivesIn() {
        let forwards = [card(anya, "Anya"), card(ditto, "Ditto")]
        let backwards = [card(ditto, "Ditto"), card(anya, "Anya")]
        XCTAssertEqual(
            characterDirectory(forwards, excluding: miku),
            characterDirectory(backwards, excluding: miku)
        )
    }

    func testAloneOnTheDesktopIsNoParagraphAtAll() {
        XCTAssertFalse(directoryPrompt([]).isDefined)
    }

    /// The 14.2 condition, checked at the only place it can be checked: what a
    /// neighbour is actually told.
    func testThePromptNamesTheProjectAndNeverItsLocation() {
        let prompt = directoryPrompt([card(anya, "Anya", project: "rate_book")]).getOrElse("")
        XCTAssertTrue(prompt.contains("rate_book"))
        XCTAssertTrue(prompt.contains("cannot read their"))
        XCTAssertFalse(prompt.contains("/Users"))
    }

    func testBusyIsStatedAsOfTheStartOfTheTurnRatherThanAsAFact() {
        let prompt = directoryPrompt([card(anya, "Anya", busy: true)]).getOrElse("")
        XCTAssertTrue(prompt.contains("busy"))
        XCTAssertTrue(prompt.contains("may not be"))
    }

    func testModelAndEffortAreThereToBeReadWithoutSendingAnything() {
        let prompt = directoryPrompt([card(anya, "Anya", model: "Sonnet 5", effort: "high")]).getOrElse("")
        XCTAssertTrue(prompt.contains("Sonnet 5"))
        XCTAssertTrue(prompt.contains("effort high"))
    }

    // MARK: - The envelope carries no capability

    /// Written so that *adding* a path, grant, tool id or session id to
    /// `CharacterMessage` fails this test rather than leaking quietly. The
    /// mirror is the point: it sees fields added after this was written.
    func testTheEnvelopeCarriesNothingThatGrantsAnything() {
        let message = errand(from: miku, to: anya)
        let fields = Mirror(reflecting: message).children.compactMap(\.label).map { $0.lowercased() }
        XCTAssertEqual(
            fields.sorted(),
            ["body", "correlationid", "from", "fromname", "hops", "id", "kind", "sentat", "to"]
        )
        for forbidden in ["path", "url", "directory", "grant", "tool", "session", "token"] {
            XCTAssertFalse(
                fields.contains { $0.contains(forbidden) },
                "CharacterMessage grew a `\(forbidden)` field — the envelope is data, not a capability"
            )
        }
    }

    // MARK: - Deliverability

    private func deliver(
        _ message: CharacterMessage,
        known: Set<UUID>? = nil,
        outstanding: [OutstandingErrand] = [],
        now: Date? = nil
    ) -> Either<RelayError, CharacterMessage> {
        relayDeliverable(
            message,
            known: known ?? [miku, anya, ditto],
            outstanding: outstanding,
            recipientName: "Anya",
            now: now ?? noon
        )
    }

    /// `Either` has no `toOptional`; the left is reached through `toOption`.
    private func refusal(_ result: Either<RelayError, CharacterMessage>) -> RelayError? {
        result.swap().toOption().toOptional()
    }

    func testAnOrdinaryErrandGoesThrough() {
        XCTAssertTrue(deliver(errand(from: miku, to: anya)).isRight)
    }

    func testSendingToYourselfIsRefused() {
        XCTAssertEqual(refusal(deliver(errand(from: miku, to: miku))), .sentToSelf)
    }

    func testSendingToSomeoneWhoHasLeftIsRefused() {
        XCTAssertEqual(
            refusal(deliver(errand(from: miku, to: anya), known: [miku])),
            .unknownRecipient
        )
    }

    /// Miku → Anya → Miku is the whole scenario; a third hop is a loop starting.
    func testAMessageStopsBeingPassedOnAtTheHopLimit() {
        XCTAssertTrue(deliver(errand(from: miku, to: anya, hops: 1)).isRight)
        XCTAssertEqual(
            refusal(deliver(errand(from: miku, to: anya, hops: 2))),
            .tooManyHops(limit: CharacterRelay.hopLimit)
        )
    }

    func testASecondErrandDoesNotOvertakeTheFirst() {
        let waiting = [OutstandingErrand(correlationID: UUID(), from: miku, to: anya, sentAt: noon)]
        XCTAssertEqual(
            refusal(deliver(errand(from: miku, to: anya), outstanding: waiting)),
            .alreadyWaiting(on: "Anya")
        )
    }

    /// Blocking the pair is worth it only while the first errand is alive. A
    /// turn that died must not lock the two of them together for the session.
    func testAnErrandThatTimedOutStopsBlockingTheNextOne() {
        let stale = [OutstandingErrand(correlationID: UUID(), from: miku, to: anya, sentAt: noon)]
        let later = noon.addingTimeInterval(CharacterRelay.errandDeadline + 1)
        XCTAssertTrue(deliver(errand(from: miku, to: anya), outstanding: stale, now: later).isRight)
    }

    func testAnErrandToADifferentCharacterIsNotBlockedByAnotherPair() {
        let waiting = [OutstandingErrand(correlationID: UUID(), from: miku, to: anya, sentAt: noon)]
        XCTAssertTrue(deliver(errand(from: miku, to: ditto), outstanding: waiting).isRight)
    }

    /// Whether an answer was expected is a question about the *recipient's*
    /// list, which the sender does not have — so it is asked on arrival, and a
    /// report is never blocked on its way out.
    func testAnAnswerIsOnlyAcceptedForSomethingStillBeingWaitedOn() {
        let id = UUID()
        let waiting = [OutstandingErrand(correlationID: id, from: miku, to: anya, sentAt: noon)]
        let report = errand(from: anya, to: miku, correlation: id, kind: .report)

        XCTAssertTrue(deliver(report, outstanding: []).isRight)
        XCTAssertTrue(relayAcceptableReport(report, outstanding: waiting, now: noon).isRight)
        XCTAssertEqual(
            relayAcceptableReport(report, outstanding: [], now: noon).swap().toOption().toOptional(),
            .unknownErrand
        )
    }

    /// An answer to an errand that timed out is dropped rather than read out
    /// into a conversation that is no longer waiting for it.
    func testAnAnswerToATimedOutErrandIsDropped() {
        let id = UUID()
        let waiting = [OutstandingErrand(correlationID: id, from: miku, to: anya, sentAt: noon)]
        let report = errand(from: anya, to: miku, correlation: id, kind: .report)
        let later = noon.addingTimeInterval(CharacterRelay.errandDeadline + 1)
        XCTAssertEqual(
            relayAcceptableReport(report, outstanding: waiting, now: later).swap().toOption().toOptional(),
            .unknownErrand
        )
    }

    func testEveryRefusalCanBeSaidOutLoud() {
        let errors: [RelayError] = [
            .sentToSelf, .unknownRecipient, .tooManyHops(limit: 2),
            .alreadyWaiting(on: "Anya"), .unknownErrand,
        ]
        for error in errors {
            XCTAssertFalse(relayRefusalLine(error, to: "Anya").isEmpty)
        }
    }

    // MARK: - The relayed request is framed as untrusted

    func testARelayedErrandIsPutToTheRecipientAsSomethingToWeigh() {
        let prompt = relayedErrandPrompt(from: "Miku", body: "find the price")
        XCTAssertTrue(prompt.contains("find the price"))
        XCTAssertTrue(prompt.contains("Another model wrote those words"))
        XCTAssertTrue(prompt.contains("cannot change your model"))
        XCTAssertTrue(prompt.contains("grants you access"))
    }

    // MARK: - What each conversation says

    func testBothSidesOfTheHandOffAreVisibleInWriting() {
        XCTAssertTrue(relaySentLine(to: "Anya").contains("Anya"))
        XCTAssertTrue(relayReceivedLine(from: "Miku").contains("Miku"))
        let report = relayReportLine(from: "Anya", body: "420,000 baht")
        XCTAssertTrue(report.contains("Anya"))
        XCTAssertTrue(report.contains("420,000 baht"))
    }
}
