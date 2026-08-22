import FunctionalCore
import Foundation

public struct WarmUpTarget: Hashable, Sendable {
    public let vendorID: String
    public let modelID: String?
    public let directory: String?

    public init(vendorID: String, modelID: String?, directory: String?) {
        self.vendorID = vendorID
        self.modelID = modelID
        self.directory = directory
    }
}

public func shouldWarmUp(
    _ target: WarmUpTarget,
    alreadyWarmed: Set<WarmUpTarget>,
    vendorWarmsUp: Bool,
    turnInFlight: Bool
) -> Bool {
    guard vendorWarmsUp, !turnInFlight else { return false }
    return !alreadyWarmed.contains(target)
}

public extension VendorRuntime {
    static func openCodeWarmUp(
        _ installation: AgentInstallation,
        directory: URL?,
        model: ChatModel?
    ) async {
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = openCodeArguments(
            model: Option.fromOptional(model),
            variant: .none(),
            session: .none(),
            workingDirectory: directory,
            prompt: warmUpPrompt
        )
        process.environment = openCodeEnvironment(for: installation)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }

    static let warmUpPrompt = "Reply with the single word: ready"
}
