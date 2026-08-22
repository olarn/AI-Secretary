import XCTest
import AssistantState
import ProjectRegistry
@testable import SecretaryCore

final class WatchBlockTests: XCTestCase {
    func testProseAboutWatchingAsksForNothing() {
        for text in [
            "I'll keep an eye on that folder for you.",
            "You can watch it with /watch aaa if you like.",
            "เดี๋ยวอาเนียดูให้นะคะ"
        ] {
            let parsed = WatchBlock.parse(text)
            XCTAssertNil(parsed.request, "Started a watch from prose: \(text)")
            XCTAssertEqual(parsed.body, text)
        }
    }

    func testABlockAsksForThePathInIt() {
        let parsed = WatchBlock.parse("""
        ได้เลยค่ะ อาเนียจะคอยดูให้นะคะ

        ```watch
        aaa
        ```
        """)
        XCTAssertEqual(parsed.request, .start(path: "aaa"))
        XCTAssertEqual(parsed.body, "ได้เลยค่ะ อาเนียจะคอยดูให้นะคะ")
        XCTAssertFalse(parsed.body.contains("```"), "The marker must never reach the eye")
    }

    func testTheOptionalLabelIsDropped() {
        XCTAssertEqual(WatchBlock.parse("```watch\npath: docs\n```").request, .start(path: "docs"))
    }

    func testTheProjectFolderIsAValidTarget() {
        XCTAssertEqual(WatchBlock.parse("```watch\n.\n```").request, .start(path: "."))
    }

    func testItCanAskToStop() {
        XCTAssertEqual(WatchBlock.parse("Done.\n\n```watch\nstop\n```").request, .stop(path: nil))
    }

    func testItCanAskToStopJustOne() {
        XCTAssertEqual(WatchBlock.parse("```watch\nstop docs\n```").request, .stop(path: "docs"))
    }

    func testAnEmptyBlockIsLeftAlone() {
        let text = "```watch\n\n```"
        let parsed = WatchBlock.parse(text)
        XCTAssertNil(parsed.request)
        XCTAssertEqual(parsed.body, text)
    }
}

final class RunBlockTests: XCTestCase {
    func testProseAboutAFileAsksForNothing() {
        let text = "deploy.md has the steps — I can run it if you want."
        let parsed = RunBlock.parse(text)
        XCTAssertNil(parsed.request)
        XCTAssertEqual(parsed.body, text)
    }

    func testABlockAsksForTheFileInIt() {
        let parsed = RunBlock.parse("""
        That file is a release checklist.

        ```run
        deploy.md
        ```
        """)
        XCTAssertEqual(parsed.request, .start(path: "deploy.md"))
        XCTAssertEqual(parsed.body, "That file is a release checklist.")
    }

    func testTheOptionalLabelIsDropped() {
        XCTAssertEqual(RunBlock.parse("```run\nfile: steps.md\n```").request, .start(path: "steps.md"))
    }

    func testItCanAskToStop() {
        XCTAssertEqual(RunBlock.parse("```run\nstop\n```").request, .stop)
    }

    func testEachBlockOnlyReadsItsOwnFence() {
        XCTAssertNil(RunBlock.parse("```watch\naaa\n```").request)
        XCTAssertNil(WatchBlock.parse("```run\naaa\n```").request)
    }

    func testBothBlocksCanBeTakenOutOfOneReply() {
        let watched = WatchBlock.parse("""
        Starting both.

        ```watch
        aaa
        ```

        ```run
        steps.md
        ```
        """)
        XCTAssertEqual(watched.request, .start(path: "aaa"))
        let asked = RunBlock.parse(watched.body)
        XCTAssertEqual(asked.request, .start(path: "steps.md"))
        XCTAssertEqual(asked.body, "Starting both.")
    }
}

@MainActor
final class DroppedDecisionTests: XCTestCase {
    func testMovingOnWithoutAnsweringSaysSo() {
        let secretary = Secretary(
            stateMachine: AssistantStateMachine(),
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            profile: .miku,
            activityPreference: InMemoryActivityPreference(),
            chatProvider: SpyWorkspaceProvider()
        )
        let withNoProjectRegisteredNothingIsLeftPending = "watch something"
        secretary.submit(withNoProjectRegisteredNothingIsLeftPending)
        XCTAssertEqual(secretary.pendingDecision, .none())

        XCTAssertFalse(
            secretary.transcript.contains { $0.text.hasPrefix("(Didn't do") },
            "Announced a drop with nothing to drop"
        )
    }
}
