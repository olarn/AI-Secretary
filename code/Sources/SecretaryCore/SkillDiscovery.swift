import Foundation

public enum SkillScope: Equatable, Sendable {
    case user
    case project
    case plugin(id: String)
}

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

public func skillsPrompt(for skills: [SkillInfo]) -> String {
    guard !skills.isEmpty else { return "" }
    let lines = skills.map { skill -> String in
        let summary = skill.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty
            ? "- \(skill.name)"
            : "- \(skill.name) — \(truncatedSkillSummary(summary))"
    }
    return """

    The user has picked these skills for this session. Prefer them: when one \
    fits what is being asked, use it rather than working without it.

    \(lines.joined(separator: "\n"))

    Other installed skills are still there if none of these fit — this is a \
    preference, not a wall.
    """
}

let maxSkillSummaryLength = 160

func truncatedSkillSummary(_ summary: String) -> String {
    let collapsed = summary.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .joined(separator: " ")
    guard collapsed.count > maxSkillSummaryLength else { return collapsed }
    return collapsed.prefix(maxSkillSummaryLength).trimmingCharacters(in: .whitespaces) + "…"
}

public enum SkillDiscovery {
    public static func discover(
        projectPaths: [String],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SkillInfo] {
        let claudeHome = homeDirectory.appendingPathComponent(".claude")
        var found = scan(directory: claudeHome.appendingPathComponent("skills"), scope: .user)
        for path in projectPaths {
            found += scan(
                directory: URL(fileURLWithPath: path).appendingPathComponent(".claude/skills"),
                scope: .project
            )
        }
        found += discoverPluginSkills(claudeHome: claudeHome)
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
            .compactMap { folder in skillInfo(at: folder, id: folder.lastPathComponent, name: nil, scope: scope) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func discoverPluginSkills(claudeHome: URL) -> [SkillInfo] {
        guard let data = try? Data(contentsOf: claudeHome.appendingPathComponent("settings.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabledPlugins = json["enabledPlugins"] as? [String: Bool]
        else {
            return []
        }

        var seenIDs = Set<String>()
        var result: [SkillInfo] = []

        for (pluginKey, isEnabled) in enabledPlugins.sorted(by: { $0.key < $1.key }) where isEnabled {
            let parts = pluginKey.split(separator: "@", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let (plugin, marketplace) = (parts[0], parts[1])

            let candidateRoots = [
                claudeHome.appendingPathComponent("plugins/cache/\(marketplace)/\(plugin)"),
                claudeHome.appendingPathComponent("plugins/marketplaces/\(marketplace)/plugins/\(plugin)"),
                claudeHome.appendingPathComponent("plugins/marketplaces/\(marketplace)/skills")
            ]

            let folders = candidateRoots.lazy
                .map { findSkillFolders(under: $0, maxDepth: 4) }
                .first { !$0.isEmpty } ?? []

            for folder in folders {
                let id = "\(pluginKey):\(folder.lastPathComponent)"
                guard !seenIDs.contains(id) else { continue }
                guard let info = skillInfo(
                    at: folder,
                    id: id,
                    name: "\(plugin):\(folder.lastPathComponent)",
                    scope: .plugin(id: pluginKey)
                ) else { continue }
                seenIDs.insert(id)
                result.append(info)
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func findSkillFolders(under root: URL, maxDepth: Int) -> [URL] {
        guard maxDepth > 0,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey]
              )
        else {
            return []
        }

        var result: [URL] = []
        for entry in entries {
            guard !entry.lastPathComponent.hasPrefix("."),
                  (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }

            if FileManager.default.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path) {
                result.append(entry)
            } else {
                result += findSkillFolders(under: entry, maxDepth: maxDepth - 1)
            }
        }
        return result
    }

    private static func skillInfo(at folder: URL, id: String, name: String?, scope: SkillScope) -> SkillInfo? {
        guard let text = try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8) else {
            return nil
        }
        let frontmatter = parseFrontmatter(text)
        return SkillInfo(
            id: id,
            name: name ?? frontmatter["name"] ?? id,
            summary: frontmatter["description"] ?? "",
            scope: scope
        )
    }

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
