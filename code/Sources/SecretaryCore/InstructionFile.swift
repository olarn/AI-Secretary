import CryptoKit
import Foundation
import Permissions

public struct InstructionRequest: Equatable, Sendable {
    public let relativePath: String

    public init(relativePath: String) {
        self.relativePath = relativePath
    }

    public var actionClass: ActionClass { .externalNetwork }

    public var humanDescription: String {
        "Read \(relativePath) and send it to Claude to work out the steps it describes"
    }
}

public enum InstructionFingerprint {
    public static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct InstructionMemory: Equatable, Sendable {
    private var fingerprints: [String: String]

    public init(fingerprints: [String: String] = [:]) {
        self.fingerprints = fingerprints
    }

    public func hasChanged(path: String, fingerprint: String) -> Bool {
        guard let previous = fingerprints[path] else { return false }
        return previous != fingerprint
    }

    public func recording(path: String, fingerprint: String) -> InstructionMemory {
        var copy = self
        copy.fingerprints[path] = fingerprint
        return copy
    }
}
