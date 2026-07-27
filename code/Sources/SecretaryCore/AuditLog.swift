import Foundation
import os

/// One recorded step in a task's life, correlated by `taskID`.
public struct AuditEntry: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case requestReceived
        case intentClassified
        case projectResolved
        case approvalRequested
        case approvalGranted
        case approvalDenied
        case executionStarted
        case executionFinished
        case failed
    }

    public let taskID: String
    public let kind: Kind
    public let detail: String
    public let timestamp: Date

    public init(taskID: String, kind: Kind, detail: String, timestamp: Date = Date()) {
        self.taskID = taskID
        self.kind = kind
        self.detail = detail
        self.timestamp = timestamp
    }
}

public protocol AuditLogging: AnyObject {
    func record(_ entry: AuditEntry)
    var entries: [AuditEntry] { get }
}

/// Keeps the trail in memory and mirrors it to the unified log. Command text
/// and paths are logged; message content beyond the classified intent is not.
public final class AuditLog: AuditLogging {
    public private(set) var entries: [AuditEntry] = []
    private let logger = Logger(subsystem: "com.aisecretary.app", category: "Audit")

    public init() {}

    public func record(_ entry: AuditEntry) {
        entries.append(entry)
        logger.info(
            "[\(entry.taskID, privacy: .public)] \(entry.kind.rawValue, privacy: .public): \(entry.detail, privacy: .public)"
        )
    }
}
