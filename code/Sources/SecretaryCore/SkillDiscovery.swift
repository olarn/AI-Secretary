import Foundation

/// Where a skill was found. Shown next to the name so two skills with the
/// same folder name in different scopes aren't mistaken for one.
public enum SkillScope: Equatable, Sendable {
    /// A standalone folder under `~/.claude/skills`.
    case user
    /// A standalone folder under a registered project's `.claude/skills`.
    case project
    /// Provided by an installed, enabled plugin — `id` is the plugin's own
    /// identifier, `plugin@marketplace`, exactly as it appears as a key in
    /// `~/.claude/settings.json`'s `enabledPlugins`.
    case plugin(id: String)
}

/// One installed Claude Code skill, as read from its `SKILL.md` frontmatter.
///
/// `id` is stable and unique within a scope — the folder name for a
/// standalone skill, or `plugin@marketplace:folder name` for a plugin one,
/// since two enabled plugins could otherwise both contribute a folder called
/// the same thing — while `name`/`summary` are what a person reads, falling
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

/// What to tell the model about the skills someone checked in the Skills panel.
///
/// Two things this had wrong, and both came out as "I checked it and it never
/// gets used".
///
/// **It only ever subtracted.** The note used to say "only use these; don't
/// invoke any other" — which turns other skills off and does nothing at all to
/// turn the checked ones on. Whether a skill loads is decided inside Claude
/// Code by matching the request against the skill's own description, and
/// checking a box does not change that description. So the box could lose you
/// skills and never gain you one. It now asks for them to be preferred, which
/// is what checking something is understood to mean.
///
/// **It sent names only.** The panel shows each description; the prompt didn't
/// pass it on, leaving the model a bare `superpowers:brainstorming` with no way
/// to tell whether it fitted. The descriptions are the part it can actually
/// match against, so they go too.
///
/// What this still can't do is force a load — that happens in the child
/// process, out of reach. This makes the match likelier; naming a skill in the
/// message is still the only certainty.
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

/// Long enough to tell skills apart, short enough that checking twenty of them
/// doesn't quietly become the largest thing in the request.
let maxSkillSummaryLength = 160

func truncatedSkillSummary(_ summary: String) -> String {
    let collapsed = summary.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .joined(separator: " ")
    guard collapsed.count > maxSkillSummaryLength else { return collapsed }
    return collapsed.prefix(maxSkillSummaryLength).trimmingCharacters(in: .whitespaces) + "…"
}

/// Finds installed skills by reading directories directly, the same way
/// Claude Code itself resolves them — there is no `claude` subcommand that
/// lists skills (only `claude plugin list`, which only shows plugins
/// installed through the marketplace, not the skill folders sitting directly
/// under `~/.claude/skills`, and says nothing about the skills inside a
/// plugin either).
public enum SkillDiscovery {
    /// `~/.claude/skills`, `.claude/skills` under each given project path,
    /// and the skills bundled inside every plugin `~/.claude/settings.json`
    /// currently has enabled. A directory that doesn't exist yields no
    /// entries rather than an error — most projects simply have none.
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

    /// Plugins are read from `enabledPlugins` in `settings.json` — a disabled
    /// or never-installed plugin's cached files can still sit on disk, and
    /// only the enabled ones are actually available in a session.
    ///
    /// A plugin's skills can live in more than one layout depending on how it
    /// was installed (`plugins/cache/<marketplace>/<plugin>/<version>/skills`
    /// for one installed through the marketplace registry, or directly under
    /// `plugins/marketplaces/<marketplace>/skills` for a single-plugin
    /// marketplace cloned straight from its repo) — so each candidate root is
    /// tried in turn and the first one that actually has skills wins, rather
    /// than merging all of them, which would also pull in every *other*
    /// plugin a shared marketplace happens to host.
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
                // Points at the marketplace's own `skills/` folder directly,
                // not the marketplace root — a single-plugin marketplace
                // keeps its skills there, but the root also holds a
                // `plugins/` folder for any *other* plugins that marketplace
                // hosts, which must stay out of reach here.
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

    /// Depth-bounded rather than a plain recursive walk, so a plugin whose
    /// skills sit several directories deep (`<plugin>/<version>/skills/<name>`)
    /// is still found, without the search wandering off into unrelated
    /// content a real plugin checkout also carries (assets, evals, docs).
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
