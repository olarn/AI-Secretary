import FunctionalCore
import XCTest
import ProjectRegistry
@testable import Permissions

final class ActionClassTests: XCTestCase {
    /// Reading and writing *inside a registered project* may be remembered;
    /// nothing else may.
    ///
    /// `.localWrite` joined the list only when `.projectMemoryWrite` was split
    /// out of it. The rule being pinned is not "writes are fine now" — it is
    /// that a class may be kept exactly when the grant's key,
    /// `(project, tool, class)`, describes the whole of what was agreed. While
    /// the memory note shared this class, it did not: that write lands outside
    /// every registered project. Widening this list again needs the same
    /// argument made in the same place, not a case appended.
    func testOnlyWorkInsideARegisteredProjectMayBeRemembered() {
        XCTAssertTrue(mayBeRemembered(.readOnly))
        XCTAssertTrue(mayBeRemembered(.localWrite))
        for klass in ActionClass.allCases where klass != .readOnly && klass != .localWrite {
            XCTAssertFalse(mayBeRemembered(klass), "\(klass) must be asked every time")
        }
    }

    /// The note is the case this split exists for: it writes into the person's
    /// own Claude Code memory directory, which their terminal reads, and which
    /// no project-scoped grant can speak for.
    func testAMemoryNoteIsAskedEveryTime() {
        XCTAssertFalse(mayBeRemembered(.projectMemoryWrite))
        for answer in PermissionAnswer.allCases {
            XCTAssertNil(answer.duration(for: .projectMemoryWrite), "\(answer)")
        }
    }

    /// Every case is on one side or the other, so a case added later fails here
    /// rather than defaulting into whichever arm the switch happens to have.
    func testEveryClassIsAccountedFor() {
        XCTAssertEqual(Set(ActionClass.allCases.filter(mayBeRemembered)), [.readOnly, .localWrite])
        XCTAssertEqual(ActionClass.allCases.count, 8)
    }

    /// The sentence on the card and the buttons under it are decided by one
    /// value, so they cannot come apart the way they did when the widen card
    /// promised "this session only" beside an Always button.
    func testTheScopeSentenceFollowsTheButtons() {
        XCTAssertTrue(
            permissionScopeSentence([.once, .always, .deny]).contains("Always"),
            "a card offering Always must say what Always means"
        )
        XCTAssertFalse(
            permissionScopeSentence([.once, .deny]).contains("Always"),
            "a card without the button must not name it"
        )
        XCTAssertTrue(permissionScopeSentence([.once, .deny]).contains("session only"))
    }
}

// MARK: - Shared fixtures

private let allowed = Project(name: "Allowed", path: "/tmp/a", allowedTools: ["git.readOnly"])
private let notAllowed = Project(name: "NotAllowed", path: "/tmp/b", allowedTools: [])

private func request(
    project: Project,
    tool: String = "git.readOnly",
    actionClass: ActionClass = .readOnly
) -> ApprovalRequest {
    ApprovalRequest(
        taskID: "t1",
        toolID: tool,
        actionClass: actionClass,
        project: project,
        commandSummary: "git status",
        rationale: "check status"
    )
}

// MARK: - Grants are a value

final class PermissionGrantsTests: XCTestCase {
    func testGrantingReturnsANewValueAndLeavesTheOriginalAlone() {
        let projectID = UUID()
        let before = PermissionGrants()
        let after = before.granting(projectID: projectID, toolID: "git.readOnly", actionClass: .readOnly)

        XCTAssertFalse(before.has(projectID: projectID, toolID: "git.readOnly", actionClass: .readOnly))
        XCTAssertTrue(after.has(projectID: projectID, toolID: "git.readOnly", actionClass: .readOnly))
        XCTAssertNotEqual(before, after)
    }

    func testGrantingTheSamePairTwiceIsTheSameValue() {
        let projectID = UUID()
        let once = PermissionGrants().granting(projectID: projectID, toolID: "git.readOnly", actionClass: .readOnly)
        let twice = once.granting(projectID: projectID, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(once, twice)
    }

    func testCurriedGrantingComposesInAPipeline() {
        let projectID = UUID()
        let grants = PermissionGrants()
            |> PermissionGrants.granting(projectID: projectID, toolID: "git.readOnly", actionClass: .readOnly)
            |> PermissionGrants.granting(projectID: projectID, toolID: "other.tool", actionClass: .readOnly)

        XCTAssertTrue(grants.has(projectID: projectID, toolID: "git.readOnly", actionClass: .readOnly))
        XCTAssertTrue(grants.has(projectID: projectID, toolID: "other.tool", actionClass: .readOnly))
    }
}

// MARK: - The rails, tested one at a time

final class PermissionRailTests: XCTestCase {
    func testAllowlistRailLeavesAnAllowListedToolAlone() {
        let req = request(project: allowed)
        XCTAssertEqual(noteToolOutsideAllowlist(req), .right(req))
    }

    /// The miss is carried, not fatal. What used to be a refusal the person
    /// couldn't answer is now a mark on the request that forces a question.
    func testAllowlistRailMarksAMissInsteadOfRefusing() {
        XCTAssertEqual(
            noteToolOutsideAllowlist(request(project: notAllowed)),
            .right(request(project: notAllowed).steppingOutsideAllowlist())
        )
    }

    func testApprovalRailAsksWhenNoGrantIsRecorded() {
        let req = request(project: allowed)
        XCTAssertEqual(requireApproval(PermissionGrants())(req), .right(.needsApproval(req)))
    }

    func testApprovalRailAllowsOnceGranted() {
        let req = request(project: allowed)
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(requireApproval(grants)(req), .right(.allowed))
    }

    /// The one assertion the whole change turns on.
    ///
    /// A grant is remembered per project and tool for read-only work. If the
    /// allowlist mark were checked after the grants, a tool the list never
    /// covered would run unattended on the strength of one earlier yes — the
    /// hole that opens the moment an allowlist miss stops being fatal.
    func testAGrantCannotStandInForTheAllowlist() {
        let req = request(project: notAllowed).steppingOutsideAllowlist()
        XCTAssertEqual(req.actionClass, .readOnly, "the risky combination is the unattended one")
        let grants = PermissionGrants().granting(projectID: notAllowed.id, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(requireApproval(grants)(req), .right(.needsApproval(req)))
    }
}

// MARK: - The whole decision

final class PermissionDecisionTests: XCTestCase {
    private func decision(
        _ req: ApprovalRequest,
        grants: PermissionGrants = PermissionGrants()
    ) -> PermissionDecision {
        decidePermission(grants)(req)
    }

    /// Nothing is refused outright any more: a tool the project never listed is
    /// a question, and the request says so, so the card can too.
    func testToolMissingFromProjectAllowlistIsPromptedNotDenied() {
        let asked = decision(request(project: notAllowed))
        XCTAssertEqual(
            asked,
            .right(.needsApproval(request(project: notAllowed).steppingOutsideAllowlist()))
        )
        XCTAssertFalse(asked.isLeft, "a refusal the person can't answer is what this replaced")
    }

    /// And answering it doesn't quietly become a standing permission: the same
    /// request a second time, with the read-only grant that a yes would record,
    /// still asks.
    func testSayingYesOnceDoesNotSettleIt() {
        let grants = PermissionGrants().granting(projectID: notAllowed.id, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(
            decision(request(project: notAllowed), grants: grants),
            .right(.needsApproval(request(project: notAllowed).steppingOutsideAllowlist()))
        )
    }

    func testFirstUseOfAProjectAlwaysAsks() {
        let req = request(project: allowed)
        XCTAssertEqual(decision(req), .right(.needsApproval(req)))
    }

    func testReadOnlyIsAllowedOnceTheProjectToolPairIsApproved() {
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(decision(request(project: allowed), grants: grants), .right(.allowed))
    }

    func testApprovalIsScopedToTheProjectThatWasApproved() {
        let other = Project(name: "Other", path: "/tmp/c", allowedTools: ["git.readOnly"])
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly", actionClass: .readOnly)
        let req = request(project: other)

        XCTAssertEqual(decision(req, grants: grants), .right(.needsApproval(req)))
    }

    func testApprovalIsScopedToTheToolThatWasApproved() {
        let multiTool = Project(name: "Multi", path: "/tmp/d", allowedTools: ["git.readOnly", "other.tool"])
        let grants = PermissionGrants().granting(projectID: multiTool.id, toolID: "git.readOnly", actionClass: .readOnly)
        let req = request(project: multiTool, tool: "other.tool")

        XCTAssertEqual(decision(req, grants: grants), .right(.needsApproval(req)))
    }

    /// A grant is keyed on the class as well as the tool, so agreeing to read a
    /// file is not agreeing to send it — `file.readOnly` is the tool id of
    /// both. Sprint 15 widened what may be remembered and this is the property
    /// that had to survive it.
    func testAGrantForOneClassDoesNotCoverAnother() {
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly", actionClass: .readOnly)

        for klass in ActionClass.allCases where klass != .readOnly {
            let req = request(project: allowed, actionClass: klass)
            XCTAssertEqual(
                decision(req, grants: grants),
                .right(.needsApproval(req)),
                "\(klass) must not ride on a read-only grant"
            )
        }
    }

    /// The classes that leave this Mac, or that cannot be undone, ask every
    /// time even with a grant of their own kind on file. This is the line
    /// Sprint 15's Once and Always may not cross.
    func testWhatMayNotBeRememberedAsksEvenWithItsOwnGrant() {
        for klass in ActionClass.allCases where !mayBeRemembered(klass) {
            let grants = PermissionGrants()
                .granting(projectID: allowed.id, toolID: "git.readOnly", actionClass: klass)
            let req = request(project: allowed, actionClass: klass)
            XCTAssertEqual(
                decision(req, grants: grants),
                .right(.needsApproval(req)),
                "\(klass) must re-prompt every time"
            )
        }
    }

    /// And the one that may: reading in a project stops asking once agreed,
    /// which is what "let Claude Code work here" is and what was reported as
    /// being asked on every new session.
    func testReadingInTheProjectStopsAskingOnceAgreed() {
        let grants = PermissionGrants()
            .granting(projectID: allowed.id, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(
            decision(request(project: allowed, actionClass: .readOnly), grants: grants),
            .right(.allowed)
        )
    }

    func testDecideIsPureSoTheSameInputsGiveTheSameAnswer() {
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly", actionClass: .readOnly)
        let evaluate = decidePermission(grants)
        let req = request(project: allowed)

        XCTAssertEqual(evaluate(req), evaluate(req))
    }
}
