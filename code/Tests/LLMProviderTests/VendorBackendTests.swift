import XCTest
import FunctionalCore
@testable import LLMProvider

/// That `ChatBackend` builds whatever maker it was given, and forwards to it.
///
/// The forwarding half is a bug this pins rather than a feature it describes:
/// `ClaudeCodeProvider` has always conformed to `SkillInstalling`, but the
/// object the orchestrator holds is `ChatBackend`, which did not — so
/// `chatProvider as? SkillInstalling` failed every time and the character
/// answered "I can't install skills without Claude Code" with Claude Code found
/// and working. A plausible refusal is the kind nobody reports.
final class VendorBackendTests: XCTestCase {
    /// Stands in for a maker's tool. Records what it was asked to install.
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
        backend.resolve()

        XCTAssertEqual(backend.vendor, vendor)
        // No branch inside the backend chose this — the runtime did.
        XCTAssertTrue(backend.hasWorkspaceTools)
    }

    func testInstallingASkillReachesTheProvider() async {
        let stub = StubProvider()
        let backend = ChatBackend(
            detector: ClaudeCodeDetector(locator: locatorFindingClaude()),
            runtime: stubRuntime(.claudeCode, provider: stub)
        )
        backend.resolve()

        let outcome = await backend.installSkill(named: "some-plugin")

        XCTAssertEqual(stub.installed, ["some-plugin"])
        XCTAssertEqual(outcome.getOrElse(""), "installed some-plugin")
    }

    func testTheOrchestratorSeesTheBackendThroughTheProtocol() {
        // The downcast used to name `ChatBackend` itself, which tied the
        // orchestrator to one class for the sake of two read-only questions.
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
        backend.resolve()

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
        backend.resolve()

        XCTAssertFalse(backend.supportsBrowser)
    }
}
