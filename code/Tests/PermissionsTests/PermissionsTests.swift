import FunctionalCore
import XCTest
import ProjectRegistry
@testable import Permissions

final class ActionClassTests: XCTestCase {
    func testOnlyWorkInsideARegisteredProjectMayBeRemembered() {
        XCTAssertTrue(mayBeRemembered(.readOnly))
        XCTAssertTrue(mayBeRemembered(.localWrite))
        for klass in ActionClass.allCases where klass != .readOnly && klass != .localWrite {
            XCTAssertFalse(mayBeRemembered(klass), "\(klass) must be asked every time")
        }
    }

    func testAMemoryNoteIsAskedEveryTime() {
        XCTAssertFalse(mayBeRemembered(.projectMemoryWrite))
        for answer in PermissionAnswer.allCases {
            XCTAssertNil(answer.duration(for: .projectMemoryWrite), "\(answer)")
        }
    }

    func testEveryClassIsAccountedFor() {
        XCTAssertEqual(Set(ActionClass.allCases.filter(mayBeRemembered)), [.readOnly, .localWrite])
        XCTAssertEqual(ActionClass.allCases.count, 9)
    }

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

final class PermissionGrantsTests: XCTestCase {
    func testGrantingReturnsANewValueAndLeavesTheOriginalAlone() {
        let subject = Project(name: "P", path: "/tmp/p", allowedTools: ["git.readOnly", "other.tool"])
        let before = PermissionGrants()
        let after = before.granting(project: subject, toolID: "git.readOnly", actionClass: .readOnly)

        XCTAssertFalse(before.has(project: subject, toolID: "git.readOnly", actionClass: .readOnly))
        XCTAssertTrue(after.has(project: subject, toolID: "git.readOnly", actionClass: .readOnly))
        XCTAssertNotEqual(before, after)
    }

    func testGrantingTheSamePairTwiceIsTheSameValue() {
        let subject = Project(name: "P", path: "/tmp/p", allowedTools: ["git.readOnly", "other.tool"])
        let once = PermissionGrants().granting(project: subject, toolID: "git.readOnly", actionClass: .readOnly)
        let twice = once.granting(project: subject, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(once, twice)
    }

    func testCurriedGrantingComposesInAPipeline() {
        let subject = Project(name: "P", path: "/tmp/p", allowedTools: ["git.readOnly", "other.tool"])
        let grants = PermissionGrants()
            |> PermissionGrants.granting(project: subject, toolID: "git.readOnly", actionClass: .readOnly)
            |> PermissionGrants.granting(project: subject, toolID: "other.tool", actionClass: .readOnly)

        XCTAssertTrue(grants.has(project: subject, toolID: "git.readOnly", actionClass: .readOnly))
        XCTAssertTrue(grants.has(project: subject, toolID: "other.tool", actionClass: .readOnly))
    }
}

final class PermissionRailTests: XCTestCase {
    func testAllowlistRailLeavesAnAllowListedToolAlone() {
        let req = request(project: allowed)
        XCTAssertEqual(noteToolOutsideAllowlist(req), .right(req))
    }

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
        let grants = PermissionGrants().granting(project: allowed, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(requireApproval(grants)(req), .right(.allowed))
    }

    func testAGrantCannotStandInForTheAllowlist() {
        let req = request(project: notAllowed).steppingOutsideAllowlist()
        XCTAssertEqual(req.actionClass, .readOnly, "the risky combination is the unattended one")
        let grants = PermissionGrants().granting(project: notAllowed, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(requireApproval(grants)(req), .right(.needsApproval(req)))
    }
}

final class PermissionDecisionTests: XCTestCase {
    private func decision(
        _ req: ApprovalRequest,
        grants: PermissionGrants = PermissionGrants()
    ) -> PermissionDecision {
        decidePermission(grants)(req)
    }

    func testToolMissingFromProjectAllowlistIsPromptedNotDenied() {
        let asked = decision(request(project: notAllowed))
        XCTAssertEqual(
            asked,
            .right(.needsApproval(request(project: notAllowed).steppingOutsideAllowlist()))
        )
        XCTAssertFalse(asked.isLeft, "a refusal the person can't answer is what this replaced")
    }

    func testSayingYesOnceDoesNotSettleIt() {
        let grants = PermissionGrants().granting(project: notAllowed, toolID: "git.readOnly", actionClass: .readOnly)
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
        let grants = PermissionGrants().granting(project: allowed, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(decision(request(project: allowed), grants: grants), .right(.allowed))
    }

    func testApprovalIsScopedToTheProjectThatWasApproved() {
        let other = Project(name: "Other", path: "/tmp/c", allowedTools: ["git.readOnly"])
        let grants = PermissionGrants().granting(project: allowed, toolID: "git.readOnly", actionClass: .readOnly)
        let req = request(project: other)

        XCTAssertEqual(decision(req, grants: grants), .right(.needsApproval(req)))
    }

    func testApprovalIsScopedToTheToolThatWasApproved() {
        let multiTool = Project(name: "Multi", path: "/tmp/d", allowedTools: ["git.readOnly", "other.tool"])
        let grants = PermissionGrants().granting(project: multiTool, toolID: "git.readOnly", actionClass: .readOnly)
        let req = request(project: multiTool, tool: "other.tool")

        XCTAssertEqual(decision(req, grants: grants), .right(.needsApproval(req)))
    }

    func testAGrantForOneClassDoesNotCoverAnother() {
        let grants = PermissionGrants().granting(project: allowed, toolID: "git.readOnly", actionClass: .readOnly)

        for klass in ActionClass.allCases where klass != .readOnly {
            let req = request(project: allowed, actionClass: klass)
            XCTAssertEqual(
                decision(req, grants: grants),
                .right(.needsApproval(req)),
                "\(klass) must not ride on a read-only grant"
            )
        }
    }

    func testWhatMayNotBeRememberedAsksEvenWithItsOwnGrant() {
        for klass in ActionClass.allCases where !mayBeRemembered(klass) {
            let grants = PermissionGrants()
                .granting(project: allowed, toolID: "git.readOnly", actionClass: klass)
            let req = request(project: allowed, actionClass: klass)
            XCTAssertEqual(
                decision(req, grants: grants),
                .right(.needsApproval(req)),
                "\(klass) must re-prompt every time"
            )
        }
    }

    func testReadingInTheProjectStopsAskingOnceAgreed() {
        let grants = PermissionGrants()
            .granting(project: allowed, toolID: "git.readOnly", actionClass: .readOnly)
        XCTAssertEqual(
            decision(request(project: allowed, actionClass: .readOnly), grants: grants),
            .right(.allowed)
        )
    }

    func testDecideIsPureSoTheSameInputsGiveTheSameAnswer() {
        let grants = PermissionGrants().granting(project: allowed, toolID: "git.readOnly", actionClass: .readOnly)
        let evaluate = decidePermission(grants)
        let req = request(project: allowed)

        XCTAssertEqual(evaluate(req), evaluate(req))
    }
}
