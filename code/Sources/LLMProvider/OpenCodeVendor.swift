import FunctionalCore
import Foundation

public extension AIVendor {
    static let openCode = AIVendor(
        id: "opencode",
        displayName: "OpenCode",
        models: [],
        supportsEffort: false,
        supportsBrowser: false,
        supportsSkills: false,
        executableIsUserSupplied: true,
        caution: """
        OpenCode works inside the project folder without asking first — \
        it can create and change files there with no approval card. \
        Claude Code stops and asks; this doesn't.
        """
    )
}

public struct OpenCodeLocator: Sendable {
    public static let knownPaths = [
        "/opt/homebrew/bin/opencode",
        "/usr/local/bin/opencode",
        NSHomeDirectory() + "/.opencode/bin/opencode",
        NSHomeDirectory() + "/.local/bin/opencode"
    ]

    private let isExecutable: @Sendable (String) -> Bool
    private let probe: @Sendable (URL) -> String?

    public init(
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        probe: @escaping @Sendable (URL) -> String? = { OpenCodeLocator.readVersion(of: $0) }
    ) {
        self.isExecutable = isExecutable
        self.probe = probe
    }

    public func locate(userPath: String?) -> Option<AgentInstallation> {
        let candidates = Option.fromOptional(userPath)
            .map { $0.trimmingCharacters(in: .whitespaces) }^
            .filter { !$0.isEmpty }^
            .fold({ Self.knownPaths }, { [$0] })
        return Option.fromOptional(candidates.first(where: isExecutable))
            .map { path in
                let url = URL(fileURLWithPath: path)
                return AgentInstallation(
                    vendorID: AIVendor.openCode.id,
                    executableURL: url,
                    version: self.probe(url)
                )
            }^
    }

    public static func readVersion(of executable: URL) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

public func openCodeModels(_ output: String) -> [ChatModel] {
    output
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.contains("/") && !$0.isEmpty }
        .map { line in
            ChatModel(id: line, displayName: String(line.split(separator: "/").dropFirst().joined(separator: "/")))
        }
}

public extension VendorRuntime {
    static let openCode = VendorRuntime(
        vendor: .openCode,
        makeProvider: { installation in OpenCodeProvider(installation: installation) },
        probe: VendorRuntime.openCodeConnectionProbe,
        discoverModels: VendorRuntime.openCodeModelDiscovery,
        warmUpTool: VendorRuntime.openCodeWarmUp
    )

    static func openCodeModelDiscovery(_ installation: AgentInstallation) async -> [ChatModel] {
        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = ["models"]
        process.environment = openCodeEnvironment(for: installation)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        return openCodeModels(String(decoding: data, as: UTF8.self))
    }

    static func openCodeConnectionProbe(_ installation: AgentInstallation) async -> VendorProbe {
        Option.fromOptional(installation.version)
            .map { _ in VendorProbe.signedIn(detail: openCodeReadyDetail) }^
            .getOrElse(
                .refused("That file didn't answer `opencode --version`. Check the CLI path.")
            )
    }

    static let openCodeReadyDetail = "runs · no approval cards"
}
