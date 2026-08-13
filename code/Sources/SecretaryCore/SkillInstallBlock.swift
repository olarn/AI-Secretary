import Foundation
import LLMProvider

/// A plugin the assistant says it needs and is asking to install.
///
/// Same shape as `LoopBlock` and `MessageChoices`, for the same reason: a
/// sentence that *sounds* like "I could do this if I had the pptx skill" must
/// not put an install button on screen. The request is a marker or it is prose.
///
/// ```install-skill
/// canva
/// ```
///
/// Only the name goes in the block. Where it comes from is not the assistant's
/// to choose — see `validSkillPluginName` — and what it costs is on the card.
public struct SkillInstallBlock: Equatable, Sendable {
    /// The message with the block taken out, ready to render.
    public let body: String
    /// The plugin it asked for, if it asked for one it is allowed to name.
    public let plugin: String?

    static let fence = "```install-skill"

    public init(body: String, plugin: String?) {
        self.body = body
        self.plugin = plugin
    }

    /// Splits a message. Anything without a block comes back untouched, which
    /// is nearly every message.
    ///
    /// One plugin per turn on purpose: the card names what is about to be
    /// installed, and a list makes "yes" mean more than the person read.
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
