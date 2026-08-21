import FunctionalCore
import Foundation

public extension AIVendor {
    /// The user's own OpenCode.
    ///
    /// `models` is empty on purpose, and it is not an oversight: opencode's
    /// model list is whatever *that machine* has configured — `opencode models`
    /// on this one answers two local servers and a handful of hosted ids, and
    /// another machine answers something else entirely. A fixed list here would
    /// be wrong for almost everybody, so the list is discovered at runtime and
    /// the panel shows what came back.
    ///
    /// `supportsEffort` is false. opencode does have `--variant`, but its own
    /// help calls it "provider-specific reasoning effort", and a local model
    /// generally ignores it — offering this app's five fixed levels would be
    /// inventing a setting that mostly does nothing. Hidden rather than shown
    /// and inert, which is what the backlog asked for.
    ///
    /// `supportsSkills` is false: opencode has plugins, but they are not this
    /// app's skills.
    static let openCode = AIVendor(
        id: "opencode",
        displayName: "OpenCode",
        models: [],
        supportsEffort: false,
        supportsBrowser: false,
        supportsSkills: false,
        executableIsUserSupplied: true
    )
}

/// Where opencode might be, when the user hasn't said.
///
/// Separate from `ClaudeCodeLocator` rather than a generalisation of it: that
/// one exists to *search*, because Claude Code is expected to be findable. This
/// one exists to *check what the user typed*, and only falls back to a search
/// so the path field can be filled in with something sensible on first use.
public struct OpenCodeLocator: Sendable {
    /// The usual places, in the order a Mac is likely to have them. Homebrew
    /// first because that is how this machine had it on 2026-08-21.
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

    /// Checks the path the user gave. Absent means "nothing there" — which the
    /// panel words as a path problem rather than as "not installed", because
    /// the user typed it and the fix is to correct it.
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

    /// `opencode --version` answers the bare number — `1.18.15`, no product
    /// name after it, unlike Claude Code.
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

/// Reads `opencode models`, which prints one `provider/model` per line.
///
/// Pure, so the real output can be replayed in a test. Lines without a slash
/// are skipped rather than guessed at: everything opencode has printed here is
/// `provider/model`, and a line that isn't one is something this reader has
/// never seen and should not invent a meaning for.
public func openCodeModels(_ output: String) -> [ChatModel] {
    output
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.contains("/") && !$0.isEmpty }
        .map { line in
            // The id keeps the provider prefix because that is exactly what
            // `--model` wants back. Only the label drops it, so a menu of eight
            // ollama entries doesn't read as eight repetitions of "ollama".
            ChatModel(id: line, displayName: String(line.split(separator: "/").dropFirst().joined(separator: "/")))
        }
}

public extension VendorRuntime {
    static let openCode = VendorRuntime(
        vendor: .openCode,
        makeProvider: { installation in OpenCodeProvider(installation: installation) },
        probe: VendorRuntime.openCodeConnectionProbe,
        discoverModels: VendorRuntime.openCodeModelDiscovery
    )

    /// Asks the installed opencode what this machine can run. Cheap and local —
    /// it reads its own configuration, it does not call a provider.
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

    /// Whether the binary at that path really is an opencode that runs.
    ///
    /// There is no sign-in to ask about — opencode keeps its own credentials,
    /// and with none configured it still answers on a local model, which is the
    /// case this machine is in. So the question this can honestly answer is
    /// "does it start and say what it is", and that is what it asks. Claiming
    /// to have checked an account would be claiming more than was measured.
    static func openCodeConnectionProbe(_ installation: AgentInstallation) async -> VendorProbe {
        Option.fromOptional(installation.version)
            .map { _ in VendorProbe.signedIn(detail: openCodeReadyDetail) }^
            .getOrElse(
                .refused("That file didn't answer `opencode --version`. Check the CLI path.")
            )
    }

    /// Said on the row beside the tick, because a green tick that means less
    /// than the Claude one must not look identical to it.
    static let openCodeReadyDetail = "runs · no approval cards"
}
