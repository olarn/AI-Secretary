import FunctionalCore
import Foundation

public func claudeCodeAuthProbe(_ output: String) -> VendorProbe {
    guard let data = output.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return .refused("Couldn't read the sign-in status from Claude Code.")
    }
    guard object["loggedIn"] as? Bool == true else {
        return .refused(
            "Claude Code isn't signed in. Open Terminal, run `claude` and sign in with `/login`."
        )
    }
    return .signedIn(detail: planLabel(object["subscriptionType"] as? String))
}

func planLabel(_ subscriptionType: String?) -> String {
    Option.fromOptional(subscriptionType)
        .map { $0.trimmingCharacters(in: .whitespaces) }^
        .filter { !$0.isEmpty }^
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }^
        .getOrElse("")
}

public extension VendorRuntime {
    static func claudeCodeConnectionProbe(_ installation: AgentInstallation) async -> VendorProbe {
        let claude = ClaudeCodeInstallation(
            executableURL: installation.executableURL,
            version: installation.version
        )
        let answer = await PlanUsageProbe.readIdentity(installation: claude)
        return answer.fold(
            { error in
                let detail = error.errorDescription ?? "\(error)"
                return .refused(ClaudeCodeFailure.classify(detail).message(detail: detail))
            },
            claudeCodeAuthProbe
        )
    }
}
