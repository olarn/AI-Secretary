import FunctionalCore
import Foundation

public protocol VendorProvider: ChatProvider, WorkspaceScopedProvider, SkillInstalling {
    var reportedModel: String? { get }
}

extension ClaudeCodeProvider: VendorProvider {}

public struct VendorRuntime: Sendable {
    public let vendor: AIVendor
    public let makeProvider: @Sendable (AgentInstallation) -> VendorProvider
    public let probe: @Sendable (AgentInstallation) async -> VendorProbe
    private let discoverModels: (@Sendable (AgentInstallation) async -> [ChatModel])?
    private let warmUpTool: (@Sendable (AgentInstallation, URL?, ChatModel?) async -> Void)?

    public init(
        vendor: AIVendor,
        makeProvider: @escaping @Sendable (AgentInstallation) -> VendorProvider,
        probe: @escaping @Sendable (AgentInstallation) async -> VendorProbe,
        discoverModels: (@Sendable (AgentInstallation) async -> [ChatModel])? = nil,
        warmUpTool: (@Sendable (AgentInstallation, URL?, ChatModel?) async -> Void)? = nil
    ) {
        self.vendor = vendor
        self.makeProvider = makeProvider
        self.probe = probe
        self.discoverModels = discoverModels
        self.warmUpTool = warmUpTool
    }

    public var warmsUp: Bool { warmUpTool != nil }

    public func warmUp(_ installation: AgentInstallation, directory: URL?, model: ChatModel?) async {
        await warmUpTool?(installation, directory, model)
    }

    public func offeredModels(_ installation: AgentInstallation) async -> [ChatModel] {
        guard let discoverModels else { return vendor.models }
        let found = await discoverModels(installation)
        return found.isEmpty ? vendor.models : found
    }
}

public extension VendorRuntime {
    static let claudeCode = VendorRuntime(
        vendor: .claudeCode,
        makeProvider: { installation in
            ClaudeCodeProvider(
                installation: ClaudeCodeInstallation(
                    executableURL: installation.executableURL,
                    version: installation.version
                )
            )
        },
        probe: VendorRuntime.claudeCodeConnectionProbe
    )

    static func named(_ id: String) -> Option<VendorRuntime> {
        Option.fromOptional(all.first { $0.vendor.id == id })
    }

    static let all: [VendorRuntime] = [.claudeCode, .openCode]
}

public protocol VendorBackend: ChatProvider {
    var vendor: AIVendor { get }
    var inheritedDefaults: ClaudeCodeDefaults { get }
}
