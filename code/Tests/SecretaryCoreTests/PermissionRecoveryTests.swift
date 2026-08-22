import FunctionalCore
import Foundation
import LLMProvider
import Permissions
import ProjectRegistry
import XCTest
@testable import SecretaryCore

final class PermissionRecoveryTests: XCTestCase {
    private let vault = Project(
        name: "Second-Brain",
        path: "/Users/someone/Second-Brain",
        allowedTools: [agentToolID]
    )

    private var approved: PermissionGrants {
        PermissionGrants().granting(
            project: vault,
            toolID: agentToolID,
            actionClass: .localWrite,
            lasting: .always
        )
    }

    private func write(_ path: String = "/Users/someone/Second-Brain/note.md") -> DeniedTool {
        DeniedTool(name: "Write", target: .some(path), rules: ["Write"])
    }

    private func recover(
        denied: [DeniedTool],
        subject: GrantSubject,
        grants: PermissionGrants = PermissionGrants(),
        widenedThisChain: Set<String> = [],
        sessionDirectories: Set<URL> = [],
        hasRequestToRetry: Bool = true
    ) -> PermissionRecovery {
        recoverFromRefusals(
            denied: denied,
            subject: subject,
            grants: grants,
            widenedThisChain: widenedThisChain,
            sessionDirectories: sessionDirectories,
            hasRequestToRetry: hasRequestToRetry
        )
    }

    func testNothingRefusedIsNothingToRecover() {
        XCTAssertEqual(recover(denied: [], subject: .registered(vault)), .nothingWasRefused)
    }

    func testAnApprovedProjectWidensWithoutACard() {
        XCTAssertEqual(
            recover(denied: [write()], subject: .registered(vault), grants: approved),
            .widenSilently(rules: ["Write"])
        )
    }

    func testTheSecondWriteOfAnApprovedProjectAlsoWidensWithoutACard() {
        let afterAnEarlierWriteInTheSameConversation = recover(
            denied: [write("/Users/someone/Second-Brain/lesson.md")],
            subject: .registered(vault),
            grants: approved
        )
        XCTAssertEqual(afterAnEarlierWriteInTheSameConversation, .widenSilently(rules: ["Write"]))
    }

    func testWithNoGrantItAsks() {
        XCTAssertEqual(
            recover(denied: [write()], subject: .registered(vault)),
            .askToWiden(rules: ["Write"], actionClass: .localWrite)
        )
    }

    func testWideningTheSameRuleTwiceInOneChainStopsInsteadOfAsking() {
        XCTAssertEqual(
            recover(
                denied: [write()],
                subject: .registered(vault),
                grants: approved,
                widenedThisChain: ["Write"]
            ),
            .cannotHelp(.wideningDidNotHelp(rules: ["Write"]))
        )
    }

    func testABrowserActionIsAlwaysAskedAboutEvenInAnApprovedProject() {
        let clicking = DeniedTool(
            name: BrowserTools.rule(for: "computer"),
            target: .none(),
            rules: [BrowserTools.rule(for: "computer")]
        )
        guard case .askToWiden(_, let asked) = recover(
            denied: [clicking],
            subject: .registered(vault),
            grants: approved
        ) else {
            return XCTFail("A browser action must never widen silently")
        }
        XCTAssertEqual(asked, .browserAction)
    }

    func testAFolderNobodyHasOpenedIsOfferedBeforeTheTools() {
        let outside = DeniedTool(
            name: "Write",
            target: .some("/Users/someone/Elsewhere/x.txt"),
            rules: ["Write"],
            directory: .some("/Users/someone/Elsewhere")
        )
        XCTAssertEqual(
            recover(denied: [outside], subject: .registered(vault), grants: approved),
            .openFolders(["/Users/someone/Elsewhere"])
        )
    }

    func testASubFolderOfTheApprovedProjectIsNotAnotherPlaceToAskAbout() {
        let deepInside = DeniedTool(
            name: "Write",
            target: .some("/Users/someone/Second-Brain/11-Experiments/note.md"),
            rules: ["Write"],
            directory: .some("/Users/someone/Second-Brain/11-Experiments")
        )
        XCTAssertEqual(
            recover(denied: [deepInside], subject: .registered(vault), grants: approved),
            .widenSilently(rules: ["Write"]),
            "One Always on the project covers every folder under it, or it is a per-folder grant wearing a project's name"
        )
    }

    func testTheProjectRootItselfIsInsideTheProject() {
        XCTAssertTrue(isInside(vault.path, vault))
    }

    func testAFolderMerelySharingAPrefixIsNotInsideTheProject() {
        XCTAssertFalse(
            isInside("/Users/someone/Second-Brain-Archive", vault),
            "A sibling whose name starts the same way is a different place"
        )
    }

    func testAFolderOutsideTheProjectIsStillAskedAbout() {
        let outside = DeniedTool(
            name: "Write",
            target: .some("/Users/someone/Elsewhere/x.txt"),
            rules: ["Write"],
            directory: .some("/Users/someone/Elsewhere")
        )
        XCTAssertEqual(
            recover(denied: [outside], subject: .registered(vault), grants: approved),
            .openFolders(["/Users/someone/Elsewhere"])
        )
    }

    func testAFolderAlreadyOpenedAndStillRefusedSaysSoRatherThanNothing() {
        let outside = DeniedTool(
            name: "Bash",
            target: .some("ls"),
            rules: [],
            directory: .some("/Users/someone/Elsewhere")
        )
        XCTAssertEqual(
            recover(
                denied: [outside],
                subject: .registered(vault),
                sessionDirectories: [URL(fileURLWithPath: "/Users/someone/Elsewhere")]
            ),
            .cannotHelp(.foldersAlreadyOpen(["/Users/someone/Elsewhere"]))
        )
    }

    func testARefusalWithNothingToWidenSaysSoRatherThanNothing() {
        let shapeless = DeniedTool(name: "Bash", target: .some("ls"), rules: [])
        XCTAssertEqual(
            recover(denied: [shapeless], subject: .registered(vault)),
            .cannotHelp(.nothingLeftToOpen)
        )
    }

    func testWithNothingLeftOfTheRequestItSaysSoRatherThanNothing() {
        XCTAssertEqual(
            recover(denied: [write()], subject: .registered(vault), hasRequestToRetry: false),
            .cannotHelp(.noRequestToRetry)
        )
    }

    func testNoProjectOpenIsNeverAnsweredByAGrant() {
        let placeholder = Project(name: "no project", path: "/tmp/scratch", allowedTools: [agentToolID])
        let grantsForThePlaceholder = PermissionGrants().granting(
            project: placeholder,
            toolID: agentToolID,
            actionClass: .localWrite,
            lasting: .always
        )
        XCTAssertEqual(
            recover(
                denied: [write()],
                subject: .noProjectOpen(standingIn: placeholder),
                grants: grantsForThePlaceholder
            ),
            .askToWiden(rules: ["Write"], actionClass: .localWrite)
        )
    }

    func testTheSameSituationDecidesTheSameWayTwice() {
        let placeholder = Project(name: "no project", path: "/tmp/scratch", allowedTools: [agentToolID])
        let subject = GrantSubject.noProjectOpen(standingIn: placeholder)
        XCTAssertEqual(
            recover(denied: [write()], subject: subject),
            recover(denied: [write()], subject: subject),
            "A decision that changes between two identical calls cannot be reasoned about"
        )
    }

    func testADeleteIsAskedAboutEvenInAnApprovedProject() {
        let removing = DeniedTool(
            name: "Bash",
            target: .some("rm -f note.md"),
            rules: ["Bash(rm -f *)"]
        )
        XCTAssertEqual(
            recover(denied: [removing], subject: .registered(vault), grants: approved),
            .askToWiden(rules: ["Bash(rm -f *)"], actionClass: .destructive),
            "The project grant covers reading and writing, and deleting is neither"
        )
    }

    func testInstallingAndRewritingHistoryAreNeverCoveredByTheProjectGrant() {
        for (rule, expected) in [
            ("Bash(npm install *)", ActionClass.dependencyInstalling),
            ("Bash(git rebase *)", .gitHistoryChanging),
            ("Bash(rm *)", .destructive)
        ] {
            let refused = DeniedTool(name: "Bash", target: .some(rule), rules: [rule])
            XCTAssertEqual(
                recover(denied: [refused], subject: .registered(vault), grants: approved),
                .askToWiden(rules: [rule], actionClass: expected),
                rule
            )
            XCTAssertFalse(mayBeRemembered(expected), "\(rule) must never be answerable by an Always")
        }
    }

    func testAnOrdinaryShellCommandStillCountsAsWriting() {
        XCTAssertEqual(classOf("Bash(mkdir -p *)"), .localWrite)
        XCTAssertEqual(classOf("Write"), .localWrite)
    }

    func testTheStrictestClassInTheBatchDecides() {
        XCTAssertEqual(strictestClass(of: ["Write", "Bash(rm *)"]), .destructive)
        XCTAssertEqual(strictestClass(of: ["Write", "Bash(mkdir *)"]), .localWrite)
    }

    func testRemovingAndReAddingTheProjectKeepsTheAlways() {
        let reAdded = Project(name: vault.name, path: vault.path, allowedTools: vault.allowedTools)
        XCTAssertNotEqual(reAdded.id, vault.id, "a re-added folder is a new registry entry")
        XCTAssertEqual(
            recover(denied: [write()], subject: .registered(reAdded), grants: approved),
            .widenSilently(rules: ["Write"]),
            "the key is the folder, so re-adding it does not throw the answer away"
        )
    }

    func testTwoSpellingsOfOneFolderAreOneKey() {
        let spelledWithADot = Project(
            name: vault.name,
            path: "/Users/someone/./Second-Brain/",
            allowedTools: vault.allowedTools
        )
        XCTAssertEqual(
            recover(denied: [write()], subject: .registered(spelledWithADot), grants: approved),
            .widenSilently(rules: ["Write"])
        )
    }

    func testOneYesCoversEveryToolAndBothRememberableClassesInThatProject() {
        for klass in ActionClass.allCases where mayBeRemembered(klass) {
            XCTAssertTrue(
                approved.has(project: vault, toolID: "any.tool", actionClass: klass),
                "one key per project, so \(klass) is covered too"
            )
        }
    }

    func testOneYesStillCoversNothingInAnotherProject() {
        let elsewhere = Project(name: "Other", path: "/Users/someone/Other", allowedTools: [agentToolID])
        XCTAssertFalse(approved.has(project: elsewhere, toolID: agentToolID, actionClass: .localWrite))
    }

    func testAnApprovedProjectOffersTheWriteToolsUpFront() {
        let surface = agentToolSurface(
            baseline: ["Read"],
            browser: [],
            subject: .registered(vault),
            grants: approved,
            sessionTools: []
        )
        XCTAssertEqual(surface, ["Read"] + fileWritingTools)
    }

    func testAnUnapprovedProjectOffersOnlyWhatWasAgreedThisSession() {
        let surface = agentToolSurface(
            baseline: ["Read"],
            browser: [],
            subject: .registered(vault),
            grants: PermissionGrants(),
            sessionTools: ["Bash(mkdir *)"]
        )
        XCTAssertEqual(surface, ["Read", "Bash(mkdir *)"])
    }

    func testAToolIsNeverOfferedTwice() {
        let surface = agentToolSurface(
            baseline: ["Read"],
            browser: [],
            subject: .registered(vault),
            grants: approved,
            sessionTools: ["Write"]
        )
        XCTAssertEqual(surface, ["Read"] + fileWritingTools)
    }
}
