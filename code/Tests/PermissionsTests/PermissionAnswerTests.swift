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

    // MARK: - What the card offers

    func testReadingInARegisteredProjectIsOfferedAllThree() {
        XCTAssertEqual(
            offeredAnswers(for: request(.readOnly), projectIsRegistered: true),
            [.once, .always, .deny]
        )
    }

    /// A folder dragged in from outside has no lasting identity to hang a grant
    /// on — the throwaway project the app builds for it is a new one every
    /// time, so Always would be a promise nothing could keep.
    func testAPathOutsideAnyProjectIsNeverOfferedAlways() {
        XCTAssertEqual(
            offeredAnswers(for: request(.readOnly), projectIsRegistered: false),
            [.once, .deny]
        )
    }

    /// `requireApproval` re-asks for anything outside the allowlist before it
    /// looks at grants, so remembering one would be a permission policy ignores.
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

    /// Deny is on every card, and Once is on every card. Only Always moves.
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

    // MARK: - What an answer keeps

    func testOnceKeepsTheSessionAndAlwaysKeepsTheFile() {
        XCTAssertEqual(PermissionAnswer.once.duration(for: .readOnly), .session)
        XCTAssertEqual(PermissionAnswer.always.duration(for: .readOnly), .always)
        XCTAssertNil(PermissionAnswer.deny.duration(for: .readOnly))
    }

    /// The class overrules the answer. Even Always keeps nothing for the work
    /// that must be asked about every time — otherwise the card would offer a
    /// button that quietly did more than the list it came from allows.
    func testNothingIsKeptForAClassThatMayNotBeRemembered() {
        for klass in ActionClass.allCases where !mayBeRemembered(klass) {
            for answer in PermissionAnswer.allCases {
                XCTAssertNil(answer.duration(for: klass), "\(answer) on \(klass)")
            }
        }
    }

    // MARK: - The two sets

    func testASessionGrantIsNeverWrittenOut() {
        let grants = PermissionGrants()
            .granting(projectID: project.id, toolID: "git.readOnly", actionClass: .readOnly, lasting: .session)

        XCTAssertTrue(grants.has(projectID: project.id, toolID: "git.readOnly", actionClass: .readOnly))
        XCTAssertTrue(grants.remembered.isEmpty, "a session grant must not reach the file")
    }

    func testAnAlwaysGrantIsBothInForceAndWrittenOut() {
        let grants = PermissionGrants()
            .granting(projectID: project.id, toolID: "git.readOnly", actionClass: .localWrite, lasting: .always)

        XCTAssertTrue(grants.has(projectID: project.id, toolID: "git.readOnly", actionClass: .localWrite))
        XCTAssertEqual(grants.remembered.count, 1)
        XCTAssertEqual(grants.remembered.first?.actionClass, .localWrite)
    }

    /// What comes back from disk is in force, and replaces rather than merges:
    /// a pair deleted from the file is a pair the person took back.
    func testAdoptingReplacesTheStandingHalfAndLeavesTheSessionAlone() {
        let session = PermissionGrants()
            .granting(projectID: project.id, toolID: "session.tool", actionClass: .readOnly)
        let old = session
            .granting(projectID: project.id, toolID: "old.tool", actionClass: .localWrite, lasting: .always)

        let reloaded = old.adopting(remembered: [
            StandingGrant(projectID: project.id, toolID: "new.tool", actionClass: .localWrite)
        ])

        XCTAssertTrue(reloaded.has(projectID: project.id, toolID: "new.tool", actionClass: .localWrite))
        XCTAssertFalse(reloaded.has(projectID: project.id, toolID: "old.tool", actionClass: .localWrite))
        XCTAssertTrue(reloaded.has(projectID: project.id, toolID: "session.tool", actionClass: .readOnly))
    }

    func testForgettingAProjectTakesBothHalves() {
        let other = UUID()
        let grants = PermissionGrants()
            .granting(projectID: project.id, toolID: "t", actionClass: .readOnly)
            .granting(projectID: project.id, toolID: "t", actionClass: .localWrite, lasting: .always)
            .granting(projectID: other, toolID: "t", actionClass: .localWrite, lasting: .always)
            .forgetting(projectID: project.id)

        XCTAssertFalse(grants.has(projectID: project.id, toolID: "t", actionClass: .readOnly))
        XCTAssertFalse(grants.has(projectID: project.id, toolID: "t", actionClass: .localWrite))
        XCTAssertTrue(grants.has(projectID: other, toolID: "t", actionClass: .localWrite))
        XCTAssertEqual(grants.remembered.count, 1)
    }

    /// The list is ordered, so the file it becomes does not change when nothing
    /// did — a store that rewrites itself on every launch is a store nobody can
    /// diff.
    func testWhatIsWrittenOutIsInAStableOrder() {
        let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let one = PermissionGrants()
            .granting(projectID: b, toolID: "z", actionClass: .localWrite, lasting: .always)
            .granting(projectID: a, toolID: "y", actionClass: .readOnly, lasting: .always)
        let other = PermissionGrants()
            .granting(projectID: a, toolID: "y", actionClass: .readOnly, lasting: .always)
            .granting(projectID: b, toolID: "z", actionClass: .localWrite, lasting: .always)

        XCTAssertEqual(one.remembered, other.remembered)
        XCTAssertEqual(one.remembered.first?.projectID, a)
    }
}
