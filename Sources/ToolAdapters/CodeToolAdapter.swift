import Foundation
import ProjectRegistry
import Permissions

/// What a tool was asked to do. Deliberately a closed enum rather than free
/// text: user input selects a case, it never becomes part of a command line.
public enum CodeToolOperation: String, Equatable, Sendable {
    case status
    case diffStat
    case currentBranch
    case recentLog

    public var actionClass: ActionClass { .readOnly }

    public var humanDescription: String {
        switch self {
        case .status: return "Show working tree status"
        case .diffStat: return "Show a summary of uncommitted changes"
        case .currentBranch: return "Show the current branch"
        case .recentLog: return "List the 20 most recent commits"
        }
    }
}

public struct ToolResult: Equatable, Sendable {
    public let output: String
    public let exitCode: Int32
    public let commandSummary: String

    public init(output: String, exitCode: Int32, commandSummary: String) {
        self.output = output
        self.exitCode = exitCode
        self.commandSummary = commandSummary
    }

    public var succeeded: Bool { exitCode == 0 }
}

public enum ToolError: Error, Equatable, LocalizedError {
    case operationNotAllowed(CodeToolOperation)
    case projectPathMissing(String)
    case notAGitRepository(String)
    case executableMissing(String)
    case timedOut(seconds: Int)
    case launchFailed(String)
    // File adapter cases:
    case pathEscapesProject(String)
    case fileNotFound(String)
    case notADirectory(String)
    case notAFile(String)
    case fileTooLarge(path: String, limit: Int)
    case notReadableText(String)

    public var errorDescription: String? {
        switch self {
        case .operationNotAllowed(let op):
            return "Operation '\(op.rawValue)' is not in this adapter's allowlist."
        case .projectPathMissing(let path):
            return "Project directory does not exist: \(path)"
        case .notAGitRepository(let path):
            return "Not a Git repository: \(path)"
        case .executableMissing(let path):
            return "Required executable not found: \(path)"
        case .timedOut(let seconds):
            return "Command exceeded its \(seconds)s timeout and was terminated."
        case .launchFailed(let message):
            return "Failed to launch command: \(message)"
        case .pathEscapesProject(let path):
            return "That path is outside the project and won't be accessed: \(path)"
        case .fileNotFound(let path):
            return "No such file or directory: \(path)"
        case .notADirectory(let path):
            return "Not a directory: \(path)"
        case .notAFile(let path):
            return "Not a readable file: \(path)"
        case .fileTooLarge(let path, let limit):
            return "File exceeds the \(limit)-byte read limit: \(path)"
        case .notReadableText(let path):
            return "File is not UTF-8 text and won't be shown: \(path)"
        }
    }
}

/// Boundary the Secretary talks to, so orchestration can be tested without
/// running any real process.
public protocol CodeToolAdapter: AnyObject {
    var toolID: String { get }
    func summary(for operation: CodeToolOperation) -> String
    func run(_ operation: CodeToolOperation, in project: Project) throws -> ToolResult
}
