import FunctionalCore
import XCTest
import ProjectRegistry
@testable import Permissions

final class ActionClassTests: XCTestCase {
    func testOnlyReadOnlyRunsUnattended() {
        XCTAssertTrue(ActionClass.readOnly.canRunUnattended)
        for klass in ActionClass.allCases where klass != .readOnly {
            XCTAssertFalse(klass.canRunUnattended, "\(klass) must require approval")
        }
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
        let after = before.granting(projectID: projectID, toolID: "git.readOnly")

        XCTAssertFalse(before.has(projectID: projectID, toolID: "git.readOnly"))
        XCTAssertTrue(after.has(projectID: projectID, toolID: "git.readOnly"))
        XCTAssertNotEqual(before, after)
    }

    func testGrantingTheSamePairTwiceIsTheSameValue() {
        let projectID = UUID()
        let once = PermissionGrants().granting(projectID: projectID, toolID: "git.readOnly")
        let twice = once.granting(projectID: projectID, toolID: "git.readOnly")
        XCTAssertEqual(once, twice)
    }

    func testCurriedGrantingComposesInAPipeline() {
        let projectID = UUID()
        let grants = PermissionGrants()
            |> PermissionGrants.granting(projectID: projectID, toolID: "git.readOnly")
            |> PermissionGrants.granting(projectID: projectID, toolID: "other.tool")

        XCTAssertTrue(grants.has(projectID: projectID, toolID: "git.readOnly"))
        XCTAssertTrue(grants.has(projectID: projectID, toolID: "other.tool"))
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
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly")
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
        let grants = PermissionGrants().granting(projectID: notAllowed.id, toolID: "git.readOnly")
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
        let grants = PermissionGrants().granting(projectID: notAllowed.id, toolID: "git.readOnly")
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
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly")
        XCTAssertEqual(decision(request(project: allowed), grants: grants), .right(.allowed))
    }

    func testApprovalIsScopedToTheProjectThatWasApproved() {
        let other = Project(name: "Other", path: "/tmp/c", allowedTools: ["git.readOnly"])
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly")
        let req = request(project: other)

        XCTAssertEqual(decision(req, grants: grants), .right(.needsApproval(req)))
    }

    func testApprovalIsScopedToTheToolThatWasApproved() {
        let multiTool = Project(name: "Multi", path: "/tmp/d", allowedTools: ["git.readOnly", "other.tool"])
        let grants = PermissionGrants().granting(projectID: multiTool.id, toolID: "git.readOnly")
        let req = request(project: multiTool, tool: "other.tool")

        XCTAssertEqual(decision(req, grants: grants), .right(.needsApproval(req)))
    }

    func testSideEffectingActionsAskEveryTimeEvenAfterApproval() {
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly")

        for klass in ActionClass.allCases where klass != .readOnly {
            let req = request(project: allowed, actionClass: klass)
            XCTAssertEqual(
                decision(req, grants: grants),
                .right(.needsApproval(req)),
                "\(klass) must re-prompt every time"
            )
        }
    }

    func testDecideIsPureSoTheSameInputsGiveTheSameAnswer() {
        let grants = PermissionGrants().granting(projectID: allowed.id, toolID: "git.readOnly")
        let evaluate = decidePermission(grants)
        let req = request(project: allowed)

        XCTAssertEqual(evaluate(req), evaluate(req))
    }
}
