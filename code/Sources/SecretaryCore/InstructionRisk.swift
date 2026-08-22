import Foundation

public struct InstructionRisk: Equatable, Sendable, Identifiable {
    public var id: String { reason }
    public let reason: String
    public let evidence: String

    public init(reason: String, evidence: String) {
        self.reason = reason
        self.evidence = evidence
    }
}

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
