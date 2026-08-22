import XCTest
import ProjectRegistry
@testable import Permissions

final class PermissionAnswerTests: XCTestCase {
    private let project = Project(
        name: "Allowed",
        path: "/tmp/a",
        allowedTools: ["git.readOnly"]
    )

    private func request(
        _ actionClass: ActionClass = .localWrite,
        outsideAllowlist: Bool = false
    ) -> ApprovalRequest {
        ApprovalRequest(
            taskID: "t1",
            toolID: "git.readOnly",
            actionClass: actionClass,
            project: project,
            commandSummary: "write a file",
            rationale: "asked for",
            outsideAllowlist: outsideAllowlist
        )
    }

    func testReadingInARegisteredProjectIsOfferedAllThree() {
        XCTAssertEqual(
            offeredAnswers(for: request(.readOnly), projectIsRegistered: true),
            [.once, .always, .deny]
        )
    }

    func testAPathOutsideAnyProjectIsNeverOfferedAlways() {
        XCTAssertEqual(
            offeredAnswers(for: request(.readOnly), projectIsRegistered: false),
            [.once, .deny]
        )
    }

    func testAToolOutsideTheAllowlistIsNeverOfferedAlways() {
        XCTAssertEqual(
            offeredAnswers(for: request(.readOnly, outsideAllowlist: true), projectIsRegistered: true),
            [.once, .deny]
        )
    }

    func testTheClassesThatMustAlwaysAskAreNeverOfferedAlways() {
        for klass in ActionClass.allCases where !mayBeRemembered(klass) {
            XCTAssertEqual(
                offeredAnswers(for: request(klass), projectIsRegistered: true),
                [.once, .deny],
                "\(klass) must not be offered Always"
            )
        }
    }

    func testOnceAndDenyAreAlwaysThere() {
        for klass in ActionClass.allCases {
            for registered in [true, false] {
                let offered = offeredAnswers(for: request(klass), projectIsRegistered: registered)
                XCTAssertTrue(offered.contains(.once), "\(klass)/\(registered)")
                XCTAssertTrue(offered.contains(.deny), "\(klass)/\(registered)")
                XCTAssertEqual(offered.last, .deny, "Deny is drawn last")
            }
        }
    }

    func testOnceKeepsTheSessionAndAlwaysKeepsTheFile() {
        XCTAssertEqual(PermissionAnswer.once.duration(for: .readOnly), .session)
        XCTAssertEqual(PermissionAnswer.always.duration(for: .readOnly), .always)
        XCTAssertNil(PermissionAnswer.deny.duration(for: .readOnly))
    }

    func testNothingIsKeptForAClassThatMayNotBeRemembered() {
        for klass in ActionClass.allCases where !mayBeRemembered(klass) {
            for answer in PermissionAnswer.allCases {
                XCTAssertNil(answer.duration(for: klass), "\(answer) on \(klass)")
            }
        }
    }

    func testASessionGrantIsNeverWrittenOut() {
        let grants = PermissionGrants()
            .granting(project: project, toolID: "git.readOnly", actionClass: .readOnly, lasting: .session)

        XCTAssertTrue(grants.has(project: project, toolID: "git.readOnly", actionClass: .readOnly))
        XCTAssertTrue(grants.remembered.isEmpty, "a session grant must not reach the file")
    }

    func testAnAlwaysGrantIsBothInForceAndWrittenOut() {
        let grants = PermissionGrants()
            .granting(project: project, toolID: "git.readOnly", actionClass: .localWrite, lasting: .always)

        XCTAssertTrue(grants.has(project: project, toolID: "git.readOnly", actionClass: .localWrite))
        XCTAssertEqual(grants.remembered.count, 1)
        XCTAssertEqual(grants.remembered.first?.projectPath, CanonicalPath(project.path))
    }

    func testAdoptingReplacesTheStandingHalfAndLeavesTheSessionAlone() {
        let session = PermissionGrants()
            .granting(project: project, toolID: "session.tool", actionClass: .readOnly)
        let old = session
            .granting(project: project, toolID: "old.tool", actionClass: .localWrite, lasting: .always)

        let elsewhere = Project(name: "Elsewhere", path: "/tmp/elsewhere", allowedTools: ["t"])
        let reloaded = old.adopting(remembered: [StandingGrant(project: elsewhere)])

        XCTAssertTrue(reloaded.has(project: elsewhere, toolID: "any", actionClass: .localWrite))
        XCTAssertFalse(reloaded.has(project: project, toolID: "old.tool", actionClass: .localWrite))
        XCTAssertTrue(reloaded.has(project: project, toolID: "session.tool", actionClass: .readOnly))
    }

    func testForgettingAProjectTakesBothHalves() {
        let other = Project(name: "Other", path: "/tmp/other", allowedTools: ["t"])
        let grants = PermissionGrants()
            .granting(project: project, toolID: "t", actionClass: .readOnly)
            .granting(project: project, toolID: "t", actionClass: .localWrite, lasting: .always)
            .granting(project: other, toolID: "t", actionClass: .localWrite, lasting: .always)
            .forgetting(project: project)

        XCTAssertFalse(grants.has(project: project, toolID: "t", actionClass: .readOnly))
        XCTAssertFalse(grants.has(project: project, toolID: "t", actionClass: .localWrite))
        XCTAssertTrue(grants.has(project: other, toolID: "t", actionClass: .localWrite))
        XCTAssertEqual(grants.remembered.count, 1)
    }

    func testWhatIsWrittenOutIsInAStableOrder() {
        let a = Project(name: "A", path: "/tmp/aaa", allowedTools: ["y"])
        let b = Project(name: "B", path: "/tmp/bbb", allowedTools: ["z"])
        let one = PermissionGrants()
            .granting(project: b, toolID: "z", actionClass: .localWrite, lasting: .always)
            .granting(project: a, toolID: "y", actionClass: .readOnly, lasting: .always)
        let other = PermissionGrants()
            .granting(project: a, toolID: "y", actionClass: .readOnly, lasting: .always)
            .granting(project: b, toolID: "z", actionClass: .localWrite, lasting: .always)

        XCTAssertEqual(one.remembered, other.remembered)
        XCTAssertEqual(one.remembered.first?.projectPath, CanonicalPath(a.path))
    }
}
