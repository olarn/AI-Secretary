import FunctionalCore
import Foundation
import LLMProvider
import Permissions
import ProjectRegistry

public enum GrantSubject: Equatable, Sendable {
    case registered(Project)
    case noProjectOpen(standingIn: Project)

    public var project: Project {
        switch self {
        case .registered(let project): return project
        case .noProjectOpen(let placeholder): return placeholder
        }
    }

    public var isRegistered: Bool {
        switch self {
        case .registered: return true
        case .noProjectOpen: return false
        }
    }

    public var grantable: Option<Project> {
        switch self {
        case .registered(let project): return .some(project)
        case .noProjectOpen: return .none()
        }
    }
}

public enum RecoveryObstacle: Equatable, Sendable {
    case noRequestToRetry
    case foldersAlreadyOpen([String])
    case nothingLeftToOpen
    case wideningDidNotHelp(rules: [String])
}

public enum PermissionRecovery: Equatable, Sendable {
    case nothingWasRefused
    case openFolders([String])
    case widenSilently(rules: [String])
    case askToWiden(rules: [String], actionClass: ActionClass)
    case cannotHelp(RecoveryObstacle)
}

public let agentToolID = "claude.code"

public let fileWritingTools = ["Write", "Edit", "NotebookEdit"]

public func recoverFromRefusals(
    denied: [DeniedTool],
    subject: GrantSubject,
    grants: PermissionGrants,
    widenedThisChain: Set<String>,
    sessionDirectories: Set<URL>,
    hasRequestToRetry: Bool
) -> PermissionRecovery {
    guard !denied.isEmpty else { return .nothingWasRefused }
    guard hasRequestToRetry else { return .cannotHelp(.noRequestToRetry) }

    let folders = denied
        .compactMap { $0.directory.toOptional() }
        .filter { !isInside($0, subject.project) }
        .reduced()
    let unopened = folders.filter { !sessionDirectories.contains(URL(fileURLWithPath: $0)) }
    guard unopened.isEmpty else { return .openFolders(unopened) }

    let rules = denied.flatMap(\.rules).reduced()
    guard !rules.isEmpty else {
        return .cannotHelp(folders.isEmpty ? .nothingLeftToOpen : .foldersAlreadyOpen(folders))
    }

    let wideningWasAlreadyTriedForAllOfThese = rules.allSatisfy(widenedThisChain.contains)
    guard !wideningWasAlreadyTriedForAllOfThese else {
        return .cannotHelp(.wideningDidNotHelp(rules: rules))
    }

    let inBrowser = denied.contains { BrowserTools.changesState($0.name) }
    let asked = inBrowser ? .browserAction : strictestClass(of: rules)
    let theProjectGrantSaysNothingAboutThis = !mayBeRemembered(asked)
    return !theProjectGrantSaysNothingAboutThis && mayWriteHere(subject, grants)
        ? .widenSilently(rules: rules)
        : .askToWiden(rules: rules, actionClass: asked)
}

public func strictestClass(of rules: [String]) -> ActionClass {
    let classes = rules.map(classOf)
    return [ActionClass.destructive, .gitHistoryChanging, .dependencyInstalling]
        .first(where: classes.contains) ?? .localWrite
}

private let commandsThatDestroyData = ["rm", "rmdir", "shred", "dd", "truncate", "mkfs", "sudo"]

private let commandsThatRewriteGitHistory = ["rebase", "reset", "push", "filter-branch", "gc"]

private let commandsThatInstallThings = [
    "brew", "npm", "pnpm", "yarn", "pip", "pip3", "gem", "cargo", "apt", "apt-get", "port"
]

public func classOf(_ rule: String) -> ActionClass {
    let bashPrefix = "Bash("
    guard rule.hasPrefix(bashPrefix) else { return .localWrite }
    let inside = rule.dropFirst(bashPrefix.count).drop(while: { $0 == " " })
    let words = inside
        .split(whereSeparator: { $0 == " " || $0 == ")" })
        .map(String.init)
        .filter { $0 != "*" && !$0.hasPrefix("-") }
    guard let head = words.first else { return .localWrite }
    if commandsThatDestroyData.contains(head) { return .destructive }
    if commandsThatInstallThings.contains(head) { return .dependencyInstalling }
    let second = words.dropFirst().first ?? ""
    if head == "git", commandsThatRewriteGitHistory.contains(second) { return .gitHistoryChanging }
    return .localWrite
}

public func agentToolSurface(
    baseline: [String],
    browser: [String],
    subject: GrantSubject,
    grants: PermissionGrants,
    sessionTools: Set<String>
) -> [String] {
    let upFront = mayWriteHere(subject, grants) ? fileWritingTools : []
    return baseline + browser + upFront + sessionTools.subtracting(upFront).sorted()
}

public func isInside(_ path: String, _ project: Project) -> Bool {
    let folder = URL(fileURLWithPath: path).standardizedFileURL.path
    let root = project.url.standardizedFileURL.path
    return folder == root || folder.hasPrefix(root.hasSuffix("/") ? root : root + "/")
}

private func mayWriteHere(_ subject: GrantSubject, _ grants: PermissionGrants) -> Bool {
    subject.grantable
        .map { project in
            grants.has(projectID: project.id, toolID: agentToolID, actionClass: .localWrite)
        }^
        .getOrElse(false)
}
