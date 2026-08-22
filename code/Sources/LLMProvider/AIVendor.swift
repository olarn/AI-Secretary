import FunctionalCore
import Foundation

public struct AIVendor: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String

    public let models: [ChatModel]

    public let supportsEffort: Bool

    public let supportsBrowser: Bool

    public let supportsSkills: Bool

    public let executableIsUserSupplied: Bool

    public let caution: String?

    public init(
        id: String,
        displayName: String,
        models: [ChatModel],
        supportsEffort: Bool,
        supportsBrowser: Bool,
        supportsSkills: Bool,
        executableIsUserSupplied: Bool,
        caution: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.models = models
        self.supportsEffort = supportsEffort
        self.supportsBrowser = supportsBrowser
        self.supportsSkills = supportsSkills
        self.executableIsUserSupplied = executableIsUserSupplied
        self.caution = caution
    }
}

public extension AIVendor {
    static let claudeCode = AIVendor(
        id: "claude-code",
        displayName: "Claude Code",
        models: ChatModel.known,
        supportsEffort: true,
        supportsBrowser: true,
        supportsSkills: true,
        executableIsUserSupplied: false
    )

    static let known: [AIVendor] = [.claudeCode, .openCode]

    static func named(_ id: String) -> Option<AIVendor> {
        Option.fromOptional(known.first { $0.id == id })
    }

    func offers(model: ChatModel) -> Bool {
        models.contains(model)
    }
}

public func modelSurviving(_ model: Option<ChatModel>, switchingTo vendor: AIVendor) -> Option<ChatModel> {
    model.filter(vendor.offers(model:))^
}

public struct AgentInstallation: Equatable, Sendable {
    public let vendorID: String
    public let executableURL: URL
    public let version: String?

    public init(vendorID: String, executableURL: URL, version: String? = nil) {
        self.vendorID = vendorID
        self.executableURL = executableURL
        self.version = version
    }
}

public extension ClaudeCodeInstallation {
    var agent: AgentInstallation {
        AgentInstallation(
            vendorID: AIVendor.claudeCode.id,
            executableURL: executableURL,
            version: version
        )
    }
}
