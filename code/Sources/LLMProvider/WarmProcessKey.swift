import Foundation

public struct WarmProcessKey: Equatable, Sendable {
    public let workingDirectory: URL?
    public let additionalDirectories: [URL]
    public let allowedTools: [String]
    public let permissionMode: String
    public let browserEnabled: Bool
    public let model: String?
    public let effort: String?
    public let system: String?
    public let session: String?

    public init(
        workingDirectory: URL?,
        additionalDirectories: [URL],
        allowedTools: [String],
        permissionMode: String,
        browserEnabled: Bool,
        model: String?,
        effort: String?,
        system: String?,
        session: String?
    ) {
        self.workingDirectory = workingDirectory
        self.additionalDirectories = additionalDirectories
        self.allowedTools = allowedTools
        self.permissionMode = permissionMode
        self.browserEnabled = browserEnabled
        self.model = model
        self.effort = effort
        self.system = system
        self.session = session
    }

    public func canBeServed(by running: WarmProcessKey) -> Bool {
        self == running
    }
}

public func warmTurnInputLine(prompt: String) -> String? {
    let payload: [String: Any] = [
        "type": "user",
        "message": ["role": "user", "content": [["type": "text", "text": prompt]]],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
    let newlineIsWhatTellsTheCLITheMessageIsComplete = "\n"
    return String(decoding: data, as: UTF8.self) + newlineIsWhatTellsTheCLITheMessageIsComplete
}
