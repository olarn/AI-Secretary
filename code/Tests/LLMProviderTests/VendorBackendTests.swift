import XCTest
import FunctionalCore
@testable import LLMProvider

final class VendorBackendTests: XCTestCase {
    private final class StubProvider: VendorProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var _installed: [String] = []
        var installed: [String] { lock.withLock { _installed } }

        var reportedModel: String? { "stub-model" }

        func stream(
            messages: [ChatMessage],
            model: Option<ChatModel>,
            effort: Option<Effort>,
            maxTokens: Int,
            system: Option<String>
        ) -> ChatStream {
            ChatStream { $0.finish() }
        }

        func installSkill(named plugin: String) async -> Either<String, String> {
            lock.withLock { _installed.append(plugin) }
            return .right("installed \(plugin)")
        }

        func prepare(workingDirectory: URL?, additionalDirectories: [URL], allowedTools: [String]?) {}
        func resetConversation() {}
        var currentSessionID: String? { nil }
        func adoptSession(_ id: String?) {}
        var hasWorkspaceTools: Bool { true }
    }

    private func locatorFindingClaude() -> ClaudeCodeLocator {
        ClaudeCodeLocator(
            isExecutable: { $0.hasSuffix("/.local/bin/claude") },
            probe: { _ in "2.1.234 (Claude Code)" }
        )
    }

    private func stubRuntime(_ vendor: AIVendor, provider: StubProvider) -> VendorRuntime {
        VendorRuntime(
            vendor: vendor,
            makeProvider: { _ in provider },
            probe: { _ in .signedIn(detail: "Max") }
        )
    }

    func testTheBackendBuildsWhicheverMakerItWasGiven() {
        let stub = StubProvider()
        let vendor = AIVendor(
            id: "stub",
            displayName: "Stub",
            models: [],
            supportsEffort: false,
            supportsBrowser: false,
            supportsSkills: true,
            executableIsUserSupplied: true
        )
        let backend = ChatBackend(
            detector: ClaudeCodeDetector(locator: locatorFindingClaude()),
            runtime: stubRuntime(vendor, provider: stub)
        )
        backend.resolveOffTheMainThread()
        XCTAssertEqual(backend.vendor, vendor)
        XCTAssertFalse(backend.hasWorkspaceTools)

        backend.use(
            runtime: stubRuntime(vendor, provider: stub),
            installation: AgentInstallation(
                vendorID: vendor.id,
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/stub")
            )
        )
        XCTAssertTrue(backend.hasWorkspaceTools)
        XCTAssertEqual(backend.vendor, vendor)
    }

    func testSwitchingMakerDropsTheThreadWithIt() {
        let backend = ChatBackend(
            detector: ClaudeCodeDetector(locator: locatorFindingClaude()),
            runtime: stubRuntime(.claudeCode, provider: StubProvider())
        )
        backend.adoptSession("ses_from_the_other_one")
        XCTAssertEqual(backend.currentSessionID, "ses_from_the_other_one")

        backend.use(runtime: .claudeCode, installation: nil)

        XCTAssertNil(backend.currentSessionID)
        XCTAssertFalse(backend.hasWorkspaceTools)
    }

    func testInstallingASkillReachesTheProvider() async {
        let stub = StubProvider()
        let backend = ChatBackend(
            detector: ClaudeCodeDetector(locator: locatorFindingClaude()),
            runtime: stubRuntime(.claudeCode, provider: stub)
        )
        backend.resolveOffTheMainThread()

        let outcome = await backend.installSkill(named: "some-plugin")

        XCTAssertEqual(stub.installed, ["some-plugin"])
        XCTAssertEqual(outcome.getOrElse(""), "installed some-plugin")
    }

    func testTheOrchestratorSeesTheBackendThroughTheProtocol() {
        let backend: ChatProvider = ChatBackend(
            detector: ClaudeCodeDetector(locator: locatorFindingClaude()),
            runtime: stubRuntime(.claudeCode, provider: StubProvider())
        )
        XCTAssertNotNil(backend as? VendorBackend)
        XCTAssertNotNil(backend as? SkillInstalling)
        XCTAssertEqual((backend as? VendorBackend)?.vendor, AIVendor.claudeCode)
    }

    func testAMakerWithNoSkillsRefusesInsteadOfPretending() async {
        let vendor = AIVendor(
            id: "stub",
            displayName: "Stub",
            models: [],
            supportsEffort: false,
            supportsBrowser: false,
            supportsSkills: false,
            executableIsUserSupplied: true
        )
        let stub = StubProvider()
        let backend = ChatBackend(
            detector: ClaudeCodeDetector(locator: locatorFindingClaude()),
            runtime: stubRuntime(vendor, provider: stub)
        )
        backend.resolveOffTheMainThread()

        let outcome = await backend.installSkill(named: "some-plugin")

        XCTAssertEqual(stub.installed, [])
        XCTAssertEqual(outcome.swap().getOrElse(""), "Stub can't install skills.")
    }

    func testABrowserlessMakerNeverClaimsABrowser() {
        let vendor = AIVendor(
            id: "stub",
            displayName: "Stub",
            models: [],
            supportsEffort: false,
            supportsBrowser: false,
            supportsSkills: false,
            executableIsUserSupplied: true
        )
        let backend = ChatBackend(
            detector: ClaudeCodeDetector(locator: locatorFindingClaude()),
            runtime: stubRuntime(vendor, provider: StubProvider())
        )
        backend.resolveOffTheMainThread()

        XCTAssertFalse(backend.supportsBrowser)
    }
}
