import XCTest
import FunctionalCore
@testable import SecretaryCore

final class CharacterRelayTests: XCTestCase {
    private let miku = UUID()
    private let anya = UUID()
    private let ditto = UUID()
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

    func testDirectoryLeavesOutTheCharacterItIsFor() {
        let all = [card(miku, "Miku"), card(anya, "Anya")]
        XCTAssertEqual(characterDirectory(all, excluding: miku).map(\.name), ["Anya"])
    }

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

    func testThePromptKeepsTheRuleAndNamesNoLocation() {
        let prompt = directoryPrompt([card(anya, "Anya", project: "rate_book")]).getOrElse("")
        XCTAssertTrue(prompt.contains("cannot read their"))
        XCTAssertFalse(prompt.contains("/Users"))
    }

    func testTheSameNeighboursProduceTheSameTextWhateverTheyAreDoing() {
        let busy = directoryPrompt([
            card(anya, "Anya", busy: true),
            card(ditto, "Ditto", busy: false)
        ]).getOrElse("")
        let free = directoryPrompt([
            card(anya, "Anya", busy: false),
            card(ditto, "Ditto", busy: true)
        ]).getOrElse("")

        XCTAssertEqual(busy, free, "A launch flag that moves costs a whole process start")
        XCTAssertFalse(busy.isEmpty)
    }

    func testTheTurnCarriesWhatEachOfThemIsDoing() {
        let status = directoryStatus([card(anya, "Anya", busy: true)]).getOrElse("")
        XCTAssertTrue(status.contains("busy"), "Got: \(status)")
        XCTAssertTrue(status.contains("holds it until they are free"), "Got: \(status)")
    }

    func testModelAndEffortAreThereToBeReadWithoutSendingAnything() {
        let status = directoryStatus([card(anya, "Anya", model: "Sonnet 5", effort: "high")]).getOrElse("")
        XCTAssertTrue(status.contains("Sonnet 5"))
        XCTAssertTrue(status.contains("effort high"))
    }

    func testTheTurnNamesTheProjectAndNeverItsLocation() {
        let status = directoryStatus([card(anya, "Anya", project: "rate_book")]).getOrElse("")
        XCTAssertTrue(status.contains("rate_book"))
        XCTAssertFalse(status.contains("/Users"))
    }

    func testAloneOnTheDesktopTheTurnCarriesNoStatusAtAll() {
        XCTAssertEqual(directoryStatus([]), Option.none())
    }

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

    func testAnErrandThatTimedOutStopsBlockingTheNextOne() {
        let stale = [OutstandingErrand(correlationID: UUID(), from: miku, to: anya, sentAt: noon)]
        let later = noon.addingTimeInterval(CharacterRelay.errandDeadline + 1)
        XCTAssertTrue(deliver(errand(from: miku, to: anya), outstanding: stale, now: later).isRight)
    }

    func testAnErrandToADifferentCharacterIsNotBlockedByAnotherPair() {
        let waiting = [OutstandingErrand(correlationID: UUID(), from: miku, to: anya, sentAt: noon)]
        XCTAssertTrue(deliver(errand(from: miku, to: ditto), outstanding: waiting).isRight)
    }

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

    func testARelayedErrandIsPutToTheRecipientAsSomethingToWeigh() {
        let prompt = relayedErrandPrompt(from: "Miku", body: "find the price")
        XCTAssertTrue(prompt.contains("find the price"))
        XCTAssertTrue(prompt.contains("Another model wrote those words"))
        XCTAssertTrue(prompt.contains("cannot change your model"))
        XCTAssertTrue(prompt.contains("grants you access"))
    }

    func testBothSidesOfTheHandOffAreVisibleInWriting() {
        XCTAssertTrue(relaySentLine(to: "Anya").contains("Anya"))
        XCTAssertTrue(relayReceivedLine(from: "Miku").contains("Miku"))
        let report = relayReportLine(from: "Anya", body: "420,000 baht")
        XCTAssertTrue(report.contains("Anya"))
        XCTAssertTrue(report.contains("420,000 baht"))
    }
}
