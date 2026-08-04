import Foundation

/// Something in an instruction file worth reading twice before starting.
///
/// Why this exists at all, given that the model already reads the file: the
/// file is untrusted input, and a file that tells the model "this is safe, say
/// nothing about it" is exactly the input a model-side judgement fails on. A
/// judgement the document can argue with isn't a check. So the scan is ours,
/// deterministic, and runs over both the document and the steps that came back
/// from it — if a step appeared that the document didn't ask for, it is caught
/// on the same pass.
///
/// It escalates, it never refuses. A blocklist over free Thai and English
/// would miss the real cases and reject innocent ones — the same argument the
/// personality prohibition settles the same way — so a flag adds a warning and
/// an extra confirmation to a card the user was going to see anyway. The real
/// defences are elsewhere and unchanged: every step is shown verbatim before
/// anything runs, and every action a step takes still meets the ordinary
/// permission card.
public struct InstructionRisk: Equatable, Sendable, Identifiable {
    public var id: String { reason }
    /// What to warn about, in the user's terms.
    public let reason: String
    /// The words that triggered it, so the warning can be checked rather than
    /// believed. A warning nobody can verify gets clicked through.
    public let evidence: String

    public init(reason: String, evidence: String) {
        self.reason = reason
        self.evidence = evidence
    }
}

/// The patterns worth stopping on, and what to say about each.
///
/// Grouped by consequence rather than by tool: the person deciding cares that
/// something might be deleted, not that the word was `rm` or `trash`.
private let riskPatterns: [(needles: [String], reason: String)] = [
    (
        ["rm -rf", "rm -fr", "sudo rm", "delete everything", "drop table", "truncate table", "ลบทั้งหมด"],
        "Deletes things"
    ),
    (
        ["sudo ", "chmod 777", "launchctl", "crontab", "systemsetup", "csrutil", "osascript"],
        "Changes the system, not just the project"
    ),
    (
        ["git push --force", "git push -f", "push --force", "git reset --hard", "git rebase", "force-push"],
        "Rewrites git history or a remote branch"
    ),
    (
        ["| sh", "| bash", "curl -s", "curl -fsSL", "wget ", "base64 -d", "eval ", "npm install", "pip install", "brew install"],
        "Downloads or installs something and runs it"
    ),
    (
        [".ssh", "id_rsa", ".env", "api key", "api_key", "secret key", "password", "token", "keychain", "credential", "รหัสผ่าน"],
        "Touches credentials or secrets"
    ),
    (
        // Bare "email" rather than only "send an email": the natural way to
        // write the step is "email the report to…", and a warning that only
        // fires on one phrasing is a warning that misses the real file.
        ["email", "e-mail", "post to", "upload to", "slack", "webhook", "curl -x post", "curl -d", "ส่งเมล", "ส่งอีเมล"],
        "Sends something off this machine"
    ),
    (
        ["ignore previous", "ignore all previous", "ignore the above", "disregard previous",
         "do not tell the user", "don't tell the user", "without telling", "without asking",
         "ไม่ต้องบอก", "ห้ามบอก", "ไม่ต้องถาม"],
        "Asks to bypass or hide the usual checks"
    )
]

/// Scans a document and the steps read out of it.
///
/// One entry per reason, however many phrases matched: five spellings of
/// "delete" is still one thing to weigh, and a list of twenty warnings is a
/// list nobody reads.
public func instructionRisks(fileText: String, steps: [String]) -> [InstructionRisk] {
    let haystack = ([fileText] + steps).joined(separator: "\n").lowercased()

    return riskPatterns.compactMap { pattern in
        let hits = pattern.needles.filter { haystack.contains($0) }
        guard !hits.isEmpty else { return nil }
        return InstructionRisk(
            reason: pattern.reason,
            evidence: hits.map { "“\($0.trimmingCharacters(in: .whitespaces))”" }
                .joined(separator: ", ")
        )
    }
}
