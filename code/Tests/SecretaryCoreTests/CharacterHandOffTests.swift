import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import LLMProvider
@testable import SecretaryCore

/// Two characters on one desktop, passing something between them.
///
/// The pure rules are covered next door in `CharacterRelayTests`; what is
/// checked here is the wiring — that a hand-off leaves one conversation, lands
/// in the other, and that the answer comes back to the conversation that asked.
@MainActor
final class CharacterHandOffTests: XCTestCase {
    private let mikuID = UUID()
    private let anyaID = UUID()

    private var mikuMachine = AssistantStateMachine()
    private var anyaMachine = AssistantStateMachine()
    private var mikuProvider = SpyWorkspaceProvider()
    private var anyaProvider = SpyWorkspaceProvider()
    private var miku: Secretary!
    private var anya: Secretary!

    override func setUp() {
        super.setUp()
        mikuMachine = AssistantStateMachine()
        anyaMachine = AssistantStateMachine()
        mikuProvider = SpyWorkspaceProvider()
        anyaProvider = SpyWorkspaceProvider()
        // No workspace tools: these turns are conversation, so nothing stops
        // for a project approval and the relay is what is left in view.
        mikuProvider.hasWorkspaceTools = false
        anyaProvider.hasWorkspaceTools = false

        miku = make(id: mikuID, name: "Miku", machine: mikuMachine, provider: mikuProvider)
        anya = make(id: anyaID, name: "Anya", machine: anyaMachine, provider: anyaProvider)
        connect()
    }

    private func make(
        id: UUID,
        name: String,
        machine: AssistantStateMachine,
        provider: SpyWorkspaceProvider
    ) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            profile: SecretaryProfile(id: id, name: name),
            chatProvider: provider
        )
    }

    /// The whole of `CharacterBus`, in four lines — which is the point of
    /// keeping every decision out of it.
    private func connect() {
        let cards = [self.card(mikuID, "Miku", miku), self.card(anyaID, "Anya", anya)]
        miku.directorySnapshot = { cards.filter { $0.id != self.mikuID } }
        anya.directorySnapshot = { cards.filter { $0.id != self.anyaID } }
        miku.onSend = { [weak self] in self?.anya.receive($0) }
        anya.onSend = { [weak self] in self?.miku.receive($0) }
    }

    private func card(_ id: UUID, _ name: String, _ secretary: Secretary) -> CharacterCard {
        CharacterCard(id: id, name: name, model: "Opus 5", effort: "Default")
    }

    private func waitUntilIdle(_ machine: AssistantStateMachine, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while machine.state != .idle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func said(_ secretary: Secretary) -> [String] {
        secretary.transcript.map(\.text)
    }

    private func saidAnything(_ secretary: Secretary, containing needle: String) -> Bool {
        said(secretary).contains { $0.contains(needle) }
    }

    /// Waits for something to become true rather than for a guessed number of
    /// milliseconds. A relayed answer takes as long as the other character's
    /// whole turn, which is not a duration a test should be predicting.
    private func waitUntil(
        _ timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - The model's own block, which is where plurals live now

    /// Sprint 17 left the several-recipients case to the model, so the block
    /// has to carry it: named twice, delivered twice, and a name that is not on
    /// the desktop is said out loud rather than matched to the nearest
    /// spelling. Guessing there would send the person's work to whoever
    /// happened to sort first.
    func testABlockNamingSomebodyWhoIsNotHereStillDeliversToTheOneWhoIs() async {
        mikuProvider.replyForNextTurn = """
            I'll ask them both.

            ```to
            Anya, Pikachu
            หาราคา honda ปี 2020 ให้หน่อย
            ```
            """
        anyaProvider.replyForNextTurn = "About 420,000 baht."

        miku.submit("ช่วยหาราคารถให้หน่อย")
        await waitUntilIdle(mikuMachine)
        await waitUntil { self.saidAnything(self.miku, containing: "420,000") }

        XCTAssertTrue(
            saidAnything(miku, containing: "Pikachu"),
            "the name nobody here answers to has to be said. Got: \(said(miku))"
        )
        XCTAssertTrue(saidAnything(anya, containing: "Miku passed this on"),
                      "and the one who is here still gets it")
        XCTAssertTrue(saidAnything(miku, containing: "420,000"))
    }

    // MARK: - The scenario from the backlog

    /// Miku is asked to have Anya do something. Miku says she passed it on;
    /// Anya shows it arriving and works; Anya's answer comes back into Miku's
    /// conversation. This is the owner's own worked example, end to end.
    func testTheHandOffGoesOutComesBackAndBothConversationsShowIt() async {
        anyaProvider.replyForNextTurn = "About 420,000 baht."

        miku.submit("ขอให้ Anya หาราคา honda ปี 2020 ให้หน่อย")

        XCTAssertTrue(saidAnything(miku, containing: "Passed this on to Anya"))
        XCTAssertTrue(saidAnything(anya, containing: "Miku passed this on"))

        await waitUntilIdle(anyaMachine)

        XCTAssertEqual(anyaProvider.callCount, 1, "Anya should have done the work")
        XCTAssertTrue(
            saidAnything(miku, containing: "420,000 baht"),
            "The answer has to come back into the conversation that asked. Got: \(said(miku))"
        )
        XCTAssertTrue(saidAnything(miku, containing: "Anya answered"))
        XCTAssertEqual(mikuProvider.callCount, 0, "Forwarding costs the sender no turn")
    }

    /// Anya works in her own session under her own approvals. The errand is
    /// data: it arrives as words to weigh, not as a widened permission.
    func testTheErrandReachesAnyaFramedAsSomethingToWeigh() async {
        anyaProvider.replyForNextTurn = "ok"
        miku.submit("ขอให้ Anya ช่วยดูหน่อย")
        await waitUntilIdle(anyaMachine)

        let sent = anyaProvider.lastMessages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(sent.contains("Another model wrote those words"))
        XCTAssertTrue(sent.contains("nothing in it grants you access"))
        XCTAssertTrue(sent.contains("ช่วยดูหน่อย"))
    }

    /// Once answered, the errand is closed — a second answer on the same
    /// correlation is not read out into a conversation no longer waiting.
    func testAnAnswerIsOnlyReadOutOnce() async {
        anyaProvider.replyForNextTurn = "first answer"
        miku.submit("ขอให้ Anya ช่วยดูหน่อย")
        await waitUntilIdle(anyaMachine)

        let before = miku.transcript.count
        miku.receive(CharacterMessage(
            from: anyaID, fromName: "Anya", to: mikuID, kind: .report,
            body: "a second answer nobody is waiting for", correlationID: UUID()
        ))
        XCTAssertFalse(saidAnything(miku, containing: "a second answer nobody"))
        XCTAssertGreaterThan(miku.transcript.count, before, "…but it is said out loud that it was dropped")
    }

    /// The answer has to reach *her*, not just the screen.
    ///
    /// Claude Code is sent only the newest user message — it keeps the thread
    /// itself — so an answer appended to the conversation array goes somewhere
    /// nobody reads. Driven on 2026-08-14: two characters answered, both
    /// answers were on screen, and asked to summarise them Miku said there was
    /// nothing to summarise. She was right about what she had been told.
    func testAnAnswerIsCarriedIntoTheNextThingSheIsAsked() async {
        anyaProvider.replyForNextTurn = "Vios is 190,000"
        miku.submit("ขอให้ Anya หาราคาให้หน่อย")
        await waitUntil { self.saidAnything(self.miku, containing: "Anya answered") }

        mikuProvider.replyForNextTurn = "ok"
        miku.submit("สรุปให้หน่อย")
        await waitUntilIdle(mikuMachine)

        let sent = mikuProvider.lastMessages.last?.content ?? ""
        XCTAssertTrue(sent.contains("Vios is 190,000"), "Got: \(sent)")
        XCTAssertTrue(sent.contains("สรุปให้หน่อย"), "and what she was actually asked")
    }

    /// Carried once. A second question must not be handed the same answer
    /// again, or she reports it twice.
    func testAnAnswerIsOnlyCarriedOnce() async {
        anyaProvider.replyForNextTurn = "Vios is 190,000"
        miku.submit("ขอให้ Anya หาราคาให้หน่อย")
        await waitUntil { self.saidAnything(self.miku, containing: "Anya answered") }

        mikuProvider.replyForNextTurn = "ok"
        miku.submit("สรุปให้หน่อย")
        await waitUntilIdle(mikuMachine)
        mikuProvider.replyForNextTurn = "ok"
        miku.submit("แล้วอย่างอื่นล่ะ")
        await waitUntilIdle(mikuMachine)

        XCTAssertFalse((mikuProvider.lastMessages.last?.content ?? "").contains("Vios is 190,000"))
    }

    // MARK: - Asking when unsure

    /// The owner's own scenario writes "อาเนีย" for a character named "Anya".
    /// Nothing may be sent on that guess — and nothing may be silently
    /// answered as if the request had been meant for Miku either.
    func testAnUnrecognisedNameAsksWhoRatherThanSendingOrAnswering() {
        miku.submit("ช่วยขอให้อาเนีย หาราคา honda ให้หน่อย")

        let asked = miku.transcript.last?.text ?? ""
        XCTAssertEqual(MessageChoices.parse(asked).options, ["Anya", answerItYourselfChoice])
        XCTAssertEqual(mikuProvider.callCount, 0)
        XCTAssertEqual(anyaProvider.callCount, 0)
        XCTAssertTrue(anya.transcript.isEmpty, "Nothing may reach Anya on a guess")
    }

    func testPickingTheNameSendsTheOriginalRequestAndNotTheName() async {
        anyaProvider.replyForNextTurn = "ok"
        miku.submit("ช่วยขอให้อาเนีย หาราคา honda ให้หน่อย")
        miku.submit("Anya")
        await waitUntilIdle(anyaMachine)

        let sent = anyaProvider.lastMessages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(sent.contains("หาราคา honda"), "The whole request travels, not the name picked")
    }

    /// The way out of a false positive. `ขอให้` turns up in sentences that have
    /// nothing to do with anyone else, so there has to be a way to say no — and
    /// saying no must run what was originally asked.
    func testAnsweringItYourselfRunsTheOriginalRequestHere() async {
        mikuProvider.replyForNextTurn = "ok"
        miku.submit("ช่วยขอให้อาเนีย หาราคา honda ให้หน่อย")
        miku.submit(answerItYourselfChoice)
        await waitUntilIdle(mikuMachine)

        XCTAssertEqual(mikuProvider.callCount, 1)
        XCTAssertEqual(anyaProvider.callCount, 0)
        let sent = mikuProvider.lastMessages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(sent.contains("หาราคา honda"))
    }

    /// Typing something else instead of picking drops the hand-off — but says
    /// so, because a request that quietly evaporates is indistinguishable from
    /// one that was carried out.
    func testTypingSomethingElseDropsTheHandOffOutLoud() async {
        mikuProvider.replyForNextTurn = "ok"
        miku.submit("ช่วยขอให้อาเนีย หาราคา honda ให้หน่อย")
        miku.submit("never mind, what time is it")
        await waitUntilIdle(mikuMachine)

        XCTAssertTrue(saidAnything(miku, containing: "kept that one rather than passing it on"))
        XCTAssertEqual(anyaProvider.callCount, 0)
    }

    // MARK: - Not trampling the person's own turn

    /// An errand arriving while Anya is mid-conversation waits its turn. The
    /// person talking to her did not ask to be pushed aside.
    func testAnErrandArrivingMidTurnWaitsRatherThanInterrupting() async {
        anyaProvider.replyForNextTurn = "answering the person"
        anya.submit("hello, are you there?")

        anya.receive(CharacterMessage(
            from: mikuID, fromName: "Miku", to: anyaID, kind: .errand, body: "look up the price"
        ))
        XCTAssertEqual(anya.queuedMessages.count, 1, "It waits: \(anya.queuedMessages)")

        await waitUntilIdle(anyaMachine)
        XCTAssertTrue(saidAnything(anya, containing: "Miku passed this on"))
    }

    // MARK: - One request, several people, then a step of her own

    /// The owner's own two-step example: ask two characters, then merge what
    /// they send back. Ditto is a third Secretary wired into the same bus.
    func testOneRequestGoesToTwoAndTheFollowUpRunsOnBothAnswers() async {
        let dittoID = UUID()
        let dittoMachine = AssistantStateMachine()
        let dittoProvider = SpyWorkspaceProvider()
        dittoProvider.hasWorkspaceTools = false
        let ditto = make(id: dittoID, name: "Ditto", machine: dittoMachine, provider: dittoProvider)

        let cards = [
            CharacterCard(id: anyaID, name: "Anya", model: "Opus 5", effort: "Default"),
            CharacterCard(id: dittoID, name: "Ditto", model: "Opus 5", effort: "Default"),
        ]
        miku.directorySnapshot = { cards }
        miku.onSend = { m in
            if m.to == self.anyaID { self.anya.receive(m) } else { ditto.receive(m) }
        }
        anya.onSend = { [weak self] in self?.miku.receive($0) }
        ditto.onSend = { [weak self] in self?.miku.receive($0) }

        anyaProvider.replyForNextTurn = "Vios 190,000"
        dittoProvider.replyForNextTurn = "City 195,000"
        mikuProvider.replyForNextTurn = "Merged and saved."

        // Two names is a question now (Sprint 17) — and the question carries
        // "both", so the fan-out this test is about is one tap away rather than
        // a guess about what joined the names.
        miku.submit("""
            1. ขอให้ Anya และ Ditto ช่วยหาข้อมูลราคารถมือสอง
            2. เมื่อได้ข้อมูลทั้ง 2 ชุด ให้รวมข้อมูล แล้วบันทึกลง file ใน project
            """)
        XCTAssertTrue(saidAnything(miku, containing: "Who should take this?"))
        miku.submit(everyoneChoice)

        XCTAssertTrue(saidAnything(miku, containing: "Passed this on to Anya and Ditto"))
        await waitUntilIdle(anyaMachine)
        await waitUntilIdle(dittoMachine)
        await waitUntilIdle(mikuMachine)

        // Step 2 ran on the sender, with both answers in front of it — and the
        // characters answering step 1 were never handed step 2.
        XCTAssertEqual(mikuProvider.callCount, 1, "the follow-up is the sender's only turn")
        let followUp = mikuProvider.lastMessages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(followUp.contains("Vios 190,000"), "Got: \(followUp)")
        XCTAssertTrue(followUp.contains("City 195,000"))
        XCTAssertTrue(followUp.contains("บันทึกลง file"))

        let toAnya = anyaProvider.lastMessages.map(\.content).joined(separator: "\n")
        XCTAssertFalse(toAnya.contains("บันทึกลง file"), "step 2 is not theirs to do")
    }

    /// Asked for two and only one ever answers: carry on with the one, and say
    /// which is missing rather than passing off one answer as two.
    func testASilentCharacterDoesNotHoldUpTheFollowUpForever() async {
        miku.errandPatience = 1.5
        let goneID = UUID()
        let cards = [
            CharacterCard(id: anyaID, name: "Anya", model: "Opus 5", effort: "Default"),
            CharacterCard(id: goneID, name: "Ditto", model: "Opus 5", effort: "Default"),
        ]
        miku.directorySnapshot = { cards }
        // Only Anya is actually wired up; Ditto is on the roster and nowhere else.
        miku.onSend = { [weak self] m in if m.to == self?.anyaID { self?.anya.receive(m) } }
        anya.onSend = { [weak self] in self?.miku.receive($0) }

        anyaProvider.replyForNextTurn = "Vios 190,000"
        mikuProvider.replyForNextTurn = "Merged what there was."

        miku.submit("1. ขอให้ Anya และ Ditto ช่วยหาข้อมูล\n2. รวมข้อมูล แล้วบันทึกลง file")
        miku.submit(everyoneChoice)
        // Anya's answer, however long her turn takes — then Ditto's silence
        // running out of patience.
        await waitUntil { self.saidAnything(self.miku, containing: "Anya answered") }
        await waitUntil { self.mikuProvider.callCount == 1 }
        await waitUntilIdle(mikuMachine)

        XCTAssertEqual(mikuProvider.callCount, 1, "one answer is enough to carry on with")
        let followUp = mikuProvider.lastMessages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(followUp.contains("Vios 190,000"), "Got: \(followUp)")
        XCTAssertTrue(followUp.contains("Ditto did not answer"), "Got: \(followUp)")
        XCTAssertFalse(followUp.contains("Anya did not answer"), "she did answer")
    }

    /// Being busy is not being ignored — but it looks exactly like it from the
    /// other end unless somebody says so.
    func testAnErrandThatHasToWaitIsAcknowledgedBackToTheSender() async {
        anyaProvider.replyForNextTurn = "answering the person"
        anya.submit("hello, are you there?")

        miku.submit("ขอให้ Anya ช่วยดูหน่อย")

        XCTAssertTrue(saidAnything(anya, containing: "I'm on something else"))
        XCTAssertTrue(
            saidAnything(miku, containing: "Anya has it"),
            "the sender has to be told it is queued. Got: \(said(miku))"
        )
        XCTAssertTrue(saidAnything(miku, containing: "Still waiting"))

        await waitUntilIdle(anyaMachine)
        XCTAssertEqual(anya.queuedMessages.count, 0, "and it runs when she is free")
    }

    /// A character can spend a whole conversation on somebody else's errand
    /// without the person typing a word into it — every line is hers. Filing
    /// used to require a `.user` turn, so that entire exchange was dropped:
    /// measured on 2026-08-14, both characters who answered a relayed request
    /// showed it on screen and neither conversation file was touched.
    func testAConversationThatWasOnlyAnErrandIsStillFiled() async {
        let store = InMemoryConversationStore()
        let machine = AssistantStateMachine()
        let provider = SpyWorkspaceProvider()
        provider.hasWorkspaceTools = false
        provider.replyForNextTurn = "About 420,000 baht."
        let pikachu = Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            profile: SecretaryProfile(id: UUID(), name: "Pikachu"),
            chatProvider: provider,
            conversationStore: store
        )

        pikachu.receive(CharacterMessage(
            from: mikuID, fromName: "Miku", to: pikachu.profile.id,
            kind: .errand, body: "find the price"
        ))
        await waitUntilIdle(machine)

        XCTAssertFalse(
            pikachu.history.isEmpty,
            "an errand she answered is a conversation she had"
        )
        let filed = pikachu.history[0].entries.map(\.text).joined(separator: "\n")
        XCTAssertTrue(filed.contains("Miku passed this on"))
        XCTAssertTrue(filed.contains("420,000 baht"))
    }

    // MARK: - The assistant's own hand-off block

    /// The path that did not exist when Ditto went looking for one.
    func testAssistantCanAskForSomethingToBePassedOn() async {
        mikuProvider.replyForNextTurn = "I'll ask her.\n\n```to\nAnya\nfind the price of a 2015 Civic\n```"
        anyaProvider.replyForNextTurn = "About 420,000 baht."

        miku.submit("get me a price comparison")
        await waitUntilIdle(mikuMachine)
        await waitUntilIdle(anyaMachine)

        XCTAssertTrue(saidAnything(miku, containing: "Passed this on to Anya"))
        XCTAssertTrue(saidAnything(anya, containing: "Miku passed this on"))
        let sent = anyaProvider.lastMessages.map(\.content).joined(separator: "\n")
        XCTAssertTrue(sent.contains("2015 Civic"))
    }

    /// Whichever route it takes — the person's prose or the assistant's own
    /// block — asking two people has to reach two people.
    func testTheAssistantsBlockCanNameSeveralAtOnce() async {
        let dittoID = UUID()
        let dittoMachine = AssistantStateMachine()
        let dittoProvider = SpyWorkspaceProvider()
        dittoProvider.hasWorkspaceTools = false
        let ditto = make(id: dittoID, name: "Ditto", machine: dittoMachine, provider: dittoProvider)

        let cards = [
            CharacterCard(id: anyaID, name: "Anya", model: "Opus 5", effort: "Default"),
            CharacterCard(id: dittoID, name: "Ditto", model: "Opus 5", effort: "Default"),
        ]
        miku.directorySnapshot = { cards }
        miku.onSend = { m in
            if m.to == self.anyaID { self.anya.receive(m) } else { ditto.receive(m) }
        }

        mikuProvider.replyForNextTurn = "Asking both.\n\n```to\nAnya และ Ditto\nfind the price of a 2020 City\n```"
        anyaProvider.replyForNextTurn = "ok"
        dittoProvider.replyForNextTurn = "ok"

        miku.submit("what do those two say about prices?")
        await waitUntilIdle(mikuMachine)
        await waitUntilIdle(anyaMachine)
        await waitUntilIdle(dittoMachine)

        XCTAssertEqual(anyaProvider.callCount, 1, "Anya should have been asked")
        XCTAssertEqual(dittoProvider.callCount, 1, "and so should Ditto")
        XCTAssertTrue(saidAnything(miku, containing: "Passed this on to Anya and Ditto"))
    }

    /// One wrong name must not lose the errand for the person who was named
    /// correctly.
    func testAWrongNameAlongsideARightOneStillSendsToTheRightOne() async {
        mikuProvider.replyForNextTurn = "```to\nAnya, Pikachu\ncheck the price\n```"
        anyaProvider.replyForNextTurn = "ok"

        miku.submit("what's the price?")
        await waitUntilIdle(mikuMachine)
        await waitUntilIdle(anyaMachine)

        XCTAssertEqual(anyaProvider.callCount, 1)
        XCTAssertTrue(saidAnything(miku, containing: "don't know anyone here called"))
        XCTAssertTrue(saidAnything(miku, containing: "Passed this on to Anya"))
    }

    /// The block must not survive into the bubble as literal typing.
    func testTheBlockDoesNotAppearOnScreen() async {
        mikuProvider.replyForNextTurn = "I'll ask her.\n\n```to\nAnya\ncheck the price\n```"
        anyaProvider.replyForNextTurn = "ok"
        miku.submit("get me a price")
        await waitUntilIdle(mikuMachine)

        XCTAssertFalse(saidAnything(miku, containing: "```to"))
    }

    /// A name that is not on the desktop is answered, not guessed at — sending
    /// to whoever sorts first would put the person's work somewhere they never
    /// asked for.
    func testAnUnknownNameIsSaidOutLoudRatherThanGuessedAt() async {
        mikuProvider.replyForNextTurn = "```to\nPikachu\ncheck the price\n```"
        miku.submit("what's the price?")
        await waitUntilIdle(mikuMachine)

        XCTAssertTrue(
            saidAnything(miku, containing: "don't know anyone here called"),
            "Got: \(said(miku))"
        )
        XCTAssertEqual(anyaProvider.callCount, 0)
    }

    /// The prompt has to say plainly that her own tools cannot reach anyone.
    /// Without it she finds one that looks like it can and reports success.
    func testThePromptSaysHerOwnToolsCannotReachThem() async {
        mikuProvider.replyForNextTurn = "ok"
        miku.submit("hello")
        await waitUntilIdle(mikuMachine)

        let system = mikuProvider.lastSystem ?? ""
        XCTAssertTrue(system.contains("```to"), "She needs to be told the way. Got: \(system)")
        XCTAssertTrue(system.contains("None of your own tools can reach these characters"))
        XCTAssertTrue(system.contains("Never tell the person you have contacted"))
    }

    // MARK: - The roster reaches the prompt

    /// 14.1's first item, answered without a message being sent at all.
    func testWhoElseIsHereIsInThePromptWithTheirModel() async {
        mikuProvider.replyForNextTurn = "ok"
        miku.submit("who else is around?")
        await waitUntilIdle(mikuMachine)

        let system = mikuProvider.lastSystem ?? ""
        XCTAssertTrue(system.contains("Anya"), "Got: \(system)")
        XCTAssertTrue(system.contains("Opus 5"))
        XCTAssertFalse(system.contains("Miku — "), "She is not her own neighbour")
    }

    func testAloneOnTheDesktopThePromptSaysNothingAboutAnybody() async {
        miku.directorySnapshot = { [] }
        mikuProvider.replyForNextTurn = "ok"
        miku.submit("hello")
        await waitUntilIdle(mikuMachine)

        XCTAssertFalse((mikuProvider.lastSystem ?? "").contains("Other characters"))
    }

    // MARK: - Ending a conversation ends what was in flight

    func testStartingAFreshConversationDropsAnErrandNobodyCanAnswerInto() async {
        anyaProvider.replyForNextTurn = "ok"
        miku.submit("ขอให้ Anya ช่วยดูหน่อย")
        miku.newConversation()

        miku.receive(CharacterMessage(
            from: anyaID, fromName: "Anya", to: mikuID, kind: .report,
            body: "an answer to the old conversation", correlationID: UUID()
        ))
        XCTAssertFalse(saidAnything(miku, containing: "an answer to the old conversation"))
    }
}
