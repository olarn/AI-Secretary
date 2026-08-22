import Foundation
import LLMProvider

public struct SkillInstallBlock: Equatable, Sendable {
    public let body: String
    public let plugin: String?

    static let fence = "```install-skill"

    public init(body: String, plugin: String?) {
        self.body = body
        self.plugin = plugin
    }

    public static func parse(_ text: String) -> SkillInstallBlock {
        guard text.contains(fence) else { return SkillInstallBlock(body: text, plugin: nil) }

        var body: [String] = []
        var block: [String] = []
        var insideBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !insideBlock, trimmed == fence {
                insideBlock = true
                continue
            }
            if insideBlock {
                if trimmed.hasPrefix("```") {
                    insideBlock = false
                    continue
                }
                block.append(trimmed)
                continue
            }
            body.append(line)
        }

        let named = block.first { !$0.isEmpty }
        return SkillInstallBlock(
            body: body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            plugin: named.flatMap { validSkillPluginName($0) ? $0 : nil }
        )
    }
}
