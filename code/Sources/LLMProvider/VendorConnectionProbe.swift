import FunctionalCore
import Foundation

/// Reads what `claude auth status` answered into a maker-neutral probe result.
///
/// Pure, and separated from the process that produces the text, so the decision
/// can be tested against real output without a Claude Code on the machine.
///
/// **Warning — this reply carries the user's email, organisation id and
/// organisation name.** Only `loggedIn` and `subscriptionType` are ever taken
/// out of it, and nothing here may log or return the rest. Widening what is
/// read is how a support paste ends up carrying somebody's address.
public func claudeCodeAuthProbe(_ output: String) -> VendorProbe {
    guard let data = output.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        // Unreadable is not the same as signed out, and must not be worded as
        // if it were — telling someone to sign in when they already are sends
        // them somewhere that cannot fix it.
        return .refused("Couldn't read the sign-in status from Claude Code.")
    }
    guard object["loggedIn"] as? Bool == true else {
        return .refused(
            "Claude Code isn't signed in. Open Terminal, run `claude` and sign in with `/login`."
        )
    }
    return .signedIn(detail: planLabel(object["subscriptionType"] as? String))
}

/// `max` reads as a word rather than a plan next to a version number, so it is
/// capitalised the way the plan is written everywhere else. Absent when the
/// reply didn't say, which is fine — the summary just drops the part.
func planLabel(_ subscriptionType: String?) -> String {
    Option.fromOptional(subscriptionType)
        .map { $0.trimmingCharacters(in: .whitespaces) }^
        .filter { !$0.isEmpty }^
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }^
        .getOrElse("")
}

public extension VendorRuntime {
    /// Asks the user's own Claude Code who it is signed in as.
    ///
    /// Out of band on purpose, exactly as the usage probe is: this must never be
    /// able to hold up an answer, so it is its own short-lived process and not
    /// part of any turn.
    static func claudeCodeConnectionProbe(_ installation: AgentInstallation) async -> VendorProbe {
        let claude = ClaudeCodeInstallation(
            executableURL: installation.executableURL,
            version: installation.version
        )
        let answer = await PlanUsageProbe.readIdentity(installation: claude)
        return answer.fold(
            { error in
                // The maker's own vocabulary is translated here rather than in
                // the decision, which is what keeps `vendorConnection` free of
                // any one CLI's error strings.
                let detail = error.errorDescription ?? "\(error)"
                return .refused(ClaudeCodeFailure.classify(detail).message(detail: detail))
            },
            claudeCodeAuthProbe
        )
    }
}
