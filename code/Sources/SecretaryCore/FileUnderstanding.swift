import Foundation
import Permissions

/// Reading a file *and asking the model about it*.
///
/// This is deliberately a separate concept from `FileOperation.readFile`, which
/// only shows you the bytes locally. Understanding a file sends its contents to
/// the Anthropic API, so it is classed `.externalNetwork`, not `.readOnly` — it
/// can never run unattended, and the user is asked every single time, with the
/// destination named in the prompt. Approving "read files in this project" must
/// not silently become permission to upload them.
public struct FileUnderstanding: Equatable, Sendable {
    /// What to ask about the file. A closed set, like every other operation the
    /// Secretary can plan — the user's words never become a free-form command.
    public enum Task: String, Equatable, Sendable, CaseIterable {
        case summarize
        case explain
        case analyze
        case review
        case describe

        /// The instruction appended after the file contents.
        var instruction: String {
            switch self {
            case .summarize:
                return "Summarise this file: what it is for, and its main parts."
            case .explain:
                return "Explain what this file does and how it works, for someone new to it."
            case .analyze:
                return "Analyse this file: structure, notable problems or risks, and anything surprising."
            case .review:
                return "Review this file and suggest concrete improvements, most important first."
            case .describe:
                return "Describe this file briefly: what it is and what it contains."
            }
        }
    }

    public let relativePath: String
    public let task: Task

    public init(relativePath: String, task: Task) {
        self.relativePath = relativePath
        self.task = task
    }

    /// Never `.readOnly`: the file leaves the machine.
    public var actionClass: ActionClass { .externalNetwork }

    public var humanDescription: String {
        "Read \(relativePath) and send its contents to Claude to \(task.rawValue) it"
    }
}
