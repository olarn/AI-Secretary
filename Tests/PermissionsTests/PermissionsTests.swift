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

final class DefaultPermissionPolicyTests: XCTestCase {
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
