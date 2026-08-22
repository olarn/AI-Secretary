import FunctionalCore
import XCTest
import AssistantState
import ProjectRegistry
import ToolAdapters
import LLMProvider
@testable import SecretaryCore

@MainActor
final class LoopBehaviourTests: XCTestCase {
    private let machine = AssistantStateMachine()

    private func makeSecretary(
        chat: FakeChatProvider = FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
    ) -> Secretary {
        Secretary(
            stateMachine: machine,
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            adapter: SpyAdapter(),
            classify: RuleBasedIntentClassifier().classify,
            audit: AuditLog(),
            chatProvider: chat
        )
    }

    private func waitUntilIdle(timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while machine.state != .idle && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testStartingALoopAnnouncesItselfAndHowToStop() {
        let secretary = makeSecretary()
        secretary.startLoop(interval: 600, note: "where are we", now: Date())

        XCTAssertTrue(secretary.activeLoop.isDefined)
        let said = secretary.transcript.last?.text ?? ""
        XCTAssertTrue(said.contains("10m"), "Got: \(said)")
        XCTAssertTrue(said.contains("/loop stop"), "Must say how to stop it. Got: \(said)")
        XCTAssertTrue(said.contains("where are we"), "Must say what it will report. Got: \(said)")
    }

    func testStoppingReportsHowManyChecksHappened() {
        let secretary = makeSecretary()
        let start = Date()
        secretary.startLoop(interval: 600, note: "", now: start)
        secretary.stopLoop()

        XCTAssertEqual(secretary.activeLoop, .none())
        XCTAssertTrue(secretary.transcript.last?.text.contains("0 checks") == true,
                      "Got: \(secretary.transcript.last?.text ?? "")")
    }

    func testStoppingWhenNothingRunsSaysSoRatherThanCrashing() {
        let secretary = makeSecretary()
        secretary.stopLoop()
        XCTAssertEqual(secretary.activeLoop, .none())
        XCTAssertTrue(secretary.transcript.last?.text.contains("No loop") == true)
    }

    func testTheSlashCommandStartsStopsAndReports() {
        let secretary = makeSecretary()
        secretary.submit("/loop")
        XCTAssertTrue(secretary.transcript.last?.text.contains("No loop is running") == true)

        secretary.submit("/loop 10m ถึงหัวข้อไหนแล้ว")
        XCTAssertEqual(secretary.activeLoop.toOptional()?.interval, 600)
        XCTAssertEqual(secretary.activeLoop.toOptional()?.note, "ถึงหัวข้อไหนแล้ว")

        secretary.submit("/loop")
        XCTAssertTrue(secretary.transcript.last?.text.contains("next at") == true)

        secretary.submit("/loop stop")
        XCTAssertEqual(secretary.activeLoop, .none())
    }

    func testARefusedIntervalStartsNothing() {
        let secretary = makeSecretary()
        secretary.submit("/loop 5s")
        XCTAssertEqual(secretary.activeLoop, .none())
        XCTAssertTrue(secretary.transcript.last?.text.contains("too often") == true,
                      "Got: \(secretary.transcript.last?.text ?? "")")
    }

    func testLoopIsAKnownCommand() {
        let secretary = makeSecretary()
        secretary.submit("/loop")
        XCTAssertFalse(
            secretary.transcript.contains { $0.text.contains("Unknown command") },
            "/loop must be a real command"
        )
    }

    func testACheckIsNotSentBeforeItIsDue() {
        let chat = FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
        let secretary = makeSecretary(chat: chat)
        let start = Date()
        secretary.startLoop(interval: 600, note: "", now: start)

        secretary.tickLoop(now: start.addingTimeInterval(599))
        XCTAssertEqual(chat.callCount, 0)
        XCTAssertEqual(secretary.activeLoop.toOptional()?.firedCount, 0)
    }

    func testADueCheckAsksTheModelAndSaysWhyItSpoke() async {
        let chat = FakeChatProvider(.events([
            .textDelta("ตอนนี้อยู่ที่ WIP Limit"),
            .completed(stopReason: .none(), usage: .none())
        ]))
        let secretary = makeSecretary(chat: chat)
        let start = Date()
        secretary.startLoop(interval: 600, note: "ถึงหัวข้อไหนแล้ว", now: start)

        secretary.tickLoop(now: start.addingTimeInterval(600))
        await waitUntilIdle()

        XCTAssertEqual(chat.callCount, 1, "The check must reach the model")
        XCTAssertEqual(secretary.activeLoop.toOptional()?.firedCount, 1)
        let sent = chat.lastMessages.last?.content ?? ""
        XCTAssertTrue(sent.contains("Loop check"), "Got: \(sent)")
        XCTAssertTrue(sent.contains("ถึงหัวข้อไหนแล้ว"), "Got: \(sent)")
        XCTAssertTrue(
            secretary.transcript.contains { $0.kind == .activity && $0.text.contains("Loop check") },
            "A reply out of nowhere needs a visible cause"
        )
        XCTAssertTrue(secretary.transcript.last?.text.contains("WIP Limit") == true)
    }

    func testACheckDueMidReplyWaitsInsteadOfInterrupting() async {
        let chat = FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
        let secretary = makeSecretary(chat: chat)
        let start = Date()
        secretary.startLoop(interval: 600, note: "", now: start)
        let callsBefore = chat.callCount

        machine.send(.userBeganInput, reason: "test", taskID: .none())
        secretary.tickLoop(now: start.addingTimeInterval(600))

        XCTAssertEqual(chat.callCount, callsBefore, "Nothing may be sent while busy")
        XCTAssertEqual(secretary.activeLoop.toOptional()?.firedCount, 0, "A postponed check is not a delivered one")
        XCTAssertTrue(secretary.activeLoop.isDefined, "Being busy must not cancel the loop")
    }

    func testALoopLeftRunningForHoursStopsItself() {
        let chat = FakeChatProvider(.events([.completed(stopReason: .none(), usage: .none())]))
        let secretary = makeSecretary(chat: chat)
        let start = Date()
        secretary.startLoop(interval: 600, note: "", now: start)

        secretary.tickLoop(now: start.addingTimeInterval(LoopSchedule.maximumDuration))

        XCTAssertEqual(secretary.activeLoop, .none())
        XCTAssertEqual(chat.callCount, 0, "It must stop rather than fire one more")
        XCTAssertTrue(secretary.transcript.last?.text.contains("Loop stopped") == true)
    }

    func testALoopTheAssistantAsksForStartsAndIsNotShownAsText() async {
        let chat = FakeChatProvider(.events([
            .textDelta("ได้เลย จะบอกทุก 10 นาที\n\n```loop\nevery: 10m\nถึงหัวข้อไหนแล้ว\n```"),
            .completed(stopReason: .none(), usage: .none())
        ]))
        let secretary = makeSecretary(chat: chat)
        secretary.submit("ช่วย track ให้หน่อยว่าถึงหัวข้อไหนแล้ว ตามเวลาจริง")
        await waitUntilIdle()

        XCTAssertEqual(secretary.activeLoop.toOptional()?.interval, 600)
        XCTAssertEqual(secretary.activeLoop.toOptional()?.note, "ถึงหัวข้อไหนแล้ว")
        XCTAssertFalse(
            secretary.transcript.contains { $0.text.contains("```loop") },
            "The block must never reach the screen as text"
        )
        XCTAssertTrue(
            secretary.transcript.contains { $0.text.contains("/loop stop") },
            "A loop the assistant started must still be announced"
        )
    }
}
