import Foundation
import Permissions

public struct FileUnderstanding: Equatable, Sendable {
    public enum Task: String, Equatable, Sendable, CaseIterable {
        case summarize
        case explain
        case analyze
        case review
        case describe

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

    public var actionClass: ActionClass { .externalNetwork }

    public var humanDescription: String {
        "Read \(relativePath) and send its contents to Claude to \(task.rawValue) it"
    }
}
