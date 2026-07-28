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
    func testAllowlistRailPassesAnAllowListedTool() {
        let req = request(project: allowed)
        XCTAssertEqual(requireAllowlistedTool(req), .right(req))
    }

    func testAllowlistRailFailsWithATypedError() {
        XCTAssertEqual(
            requireAllowlistedTool(request(project: notAllowed)),
            .left(.toolNotAllowlisted(toolID: "git.readOnly", projectName: "NotAllowed"))
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
}

// MARK: - The whole decision

final class PermissionDecisionTests: XCTestCase {
    private func decision(
        _ req: ApprovalRequest,
        grants: PermissionGrants = PermissionGrants()
    ) -> PermissionDecision {
        decidePermission(grants)(req)
    }

    func testToolMissingFromProjectAllowlistIsDeniedNotPrompted() {
        XCTAssertEqual(
            decision(request(project: notAllowed)),
            .left(.toolNotAllowlisted(toolID: "git.readOnly", projectName: "NotAllowed"))
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

// MARK: - Imperative edge

final class DefaultPermissionPolicyTests: XCTestCase {
    func testToolMissingFromProjectAllowlistIsDeniedNotPrompted() {
        let policy = DefaultPermissionPolicy()
        guard case .denied = policy.evaluate(request(project: notAllowed)) else {
            return XCTFail("Expected denial when tool is not allow-listed")
        }
    }

    func testFirstUseOfAProjectAlwaysAsks() {
        let policy = DefaultPermissionPolicy()
        guard case .needsApproval = policy.evaluate(request(project: allowed)) else {
            return XCTFail("First use must ask for approval")
        }
    }

    func testReadOnlyIsAllowedOnceTheProjectToolPairIsApproved() {
        let policy = DefaultPermissionPolicy()
        policy.recordApproval(projectID: allowed.id, toolID: "git.readOnly")
        XCTAssertEqual(policy.evaluate(request(project: allowed)), .allowed)
    }

    func testApprovalIsScopedToTheProjectThatWasApproved() {
        let policy = DefaultPermissionPolicy()
        let other = Project(name: "Other", path: "/tmp/c", allowedTools: ["git.readOnly"])
        policy.recordApproval(projectID: allowed.id, toolID: "git.readOnly")

        guard case .needsApproval = policy.evaluate(request(project: other)) else {
            return XCTFail("Approving one project must not approve another")
        }
    }

    func testApprovalIsScopedToTheToolThatWasApproved() {
        let policy = DefaultPermissionPolicy()
        let multiTool = Project(name: "Multi", path: "/tmp/d", allowedTools: ["git.readOnly", "other.tool"])
        policy.recordApproval(projectID: multiTool.id, toolID: "git.readOnly")

        guard case .needsApproval = policy.evaluate(request(project: multiTool, tool: "other.tool")) else {
            return XCTFail("Approving one tool must not approve another")
        }
    }

    func testSideEffectingActionsAskEveryTimeEvenAfterApproval() {
        let policy = DefaultPermissionPolicy()
        policy.recordApproval(projectID: allowed.id, toolID: "git.readOnly")

        for klass in ActionClass.allCases where klass != .readOnly {
            let decision = policy.evaluate(request(project: allowed, actionClass: klass))
            guard case .needsApproval = decision else {
                return XCTFail("\(klass) must re-prompt every time, got \(decision)")
            }
        }
    }
}
