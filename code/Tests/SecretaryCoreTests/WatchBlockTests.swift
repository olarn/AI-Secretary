import XCTest
import AssistantState
import ProjectRegistry
@testable import SecretaryCore

/// The assistant asking for a watch itself.
final class WatchBlockTests: XCTestCase {
    /// The case that matters most, because it is nearly every message: prose
    /// that talks about watching must not start one. The model says "I'll keep
    /// an eye on that" constantly.
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

    /// `path:` is the natural way to write it and reads better in the prompt,
    /// so it is accepted and dropped rather than becoming part of the path.
    func testTheOptionalLabelIsDropped() {
        XCTAssertEqual(WatchBlock.parse("```watch\npath: docs\n```").request, .start(path: "docs"))
    }

    func testTheProjectFolderIsAValidTarget() {
        XCTAssertEqual(WatchBlock.parse("```watch\n.\n```").request, .start(path: "."))
    }

    func testItCanAskToStop() {
        XCTAssertEqual(WatchBlock.parse("Done.\n\n```watch\nstop\n```").request, .stop)
    }

    /// An empty block asks for nothing, and must not leave a hole in the reply.
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

    /// The two blocks are independent markers and must not read each other's.
    func testEachBlockOnlyReadsItsOwnFence() {
        XCTAssertNil(RunBlock.parse("```watch\naaa\n```").request)
        XCTAssertNil(WatchBlock.parse("```run\naaa\n```").request)
    }

    /// A reply may carry both — "I'll follow the file and watch the folder" —
    /// and stripping one must leave the other findable rather than mangled.
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
    /// Typing instead of answering used to drop the card without a word, and
    /// the next reply would then claim the thing had been set up — the
    /// assistant asked for a watch, this message dropped the card, and it
    /// answered "เฝ้าอยู่เหมือนเดิมค่ะ" with nothing watching.
    func testMovingOnWithoutAnsweringSaysSo() {
        let secretary = Secretary(
            stateMachine: AssistantStateMachine(),
            registry: ProjectRegistry(store: InMemoryProjectStore(projects: [])),
            profile: .miku,
            activityPreference: InMemoryActivityPreference(),
            chatProvider: SpyWorkspaceProvider()
        )
        secretary.submit("watch something")   // no project registered → nothing pending
        XCTAssertNil(secretary.pendingDecision)

        // Nothing was waiting, so nothing is announced: the note must appear
        // only when a real decision is dropped, not on every message.
        XCTAssertFalse(
            secretary.transcript.contains { $0.text.hasPrefix("(Didn't do") },
            "Announced a drop with nothing to drop"
        )
    }
}
