import Foundation

/// Where a skill was found — the user's own `~/.claude/skills`, or a
/// project's `.claude/skills`. Shown next to the name so two skills with the
/// same folder name in different scopes aren't mistaken for one.
public enum SkillScope: String, Equatable, Sendable {
    case user
    case project
}

/// One installed Claude Code skill, as read from its `SKILL.md` frontmatter.
///
/// `id` is the folder name — the thing that's actually stable and unique
/// within a scope — while `name`/`summary` are what a person reads, falling
/// back to the folder name when frontmatter is missing or unparsable, since a
/// skill with a broken header should still show up rather than vanish.
public struct SkillInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let scope: SkillScope

    public init(id: String, name: String, summary: String, scope: SkillScope) {
        self.id = id
        self.name = name
        self.summary = summary
        self.scope = scope
    }
}

/// Finds installed skills by reading directories directly, the same way
/// Claude Code itself resolves them — there is no `claude` subcommand that
/// lists skills (only `claude plugin list`, which only shows plugins
/// installed through the marketplace, not the skill folders sitting directly
/// under `~/.claude/skills`).
public enum SkillDiscovery {
    /// `~/.claude/skills`, plus `.claude/skills` under each given project
    /// path. A directory that doesn't exist yields no entries rather than an
    /// error — most projects simply have none.
    public static func discover(
        projectPaths: [String],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SkillInfo] {
        var found = scan(directory: homeDirectory.appendingPathComponent(".claude/skills"), scope: .user)
        for path in projectPaths {
            found += scan(
                directory: URL(fileURLWithPath: path).appendingPathComponent(".claude/skills"),
                scope: .project
            )
        }
        return found
    }

    private static func scan(directory: URL, scope: SkillScope) -> [SkillInfo] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .compactMap { folder -> SkillInfo? in
                let id = folder.lastPathComponent
                guard let text = try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8) else {
                    return nil
                }
                let frontmatter = parseFrontmatter(text)
                return SkillInfo(
                    id: id,
                    name: frontmatter["name"] ?? id,
                    summary: frontmatter["description"] ?? "",
                    scope: scope
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Just enough YAML to read `name:`/`description:` out of a `---` header —
    /// SKILL.md frontmatter is never more than flat string keys, so a real
    /// parser would be answering a question nobody's asking.
    private static func parseFrontmatter(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return [:] }

        var result: [String: String] = [:]
        for line in lines.dropFirst() {
            if line == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            guard key == "name" || key == "description" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }
}
