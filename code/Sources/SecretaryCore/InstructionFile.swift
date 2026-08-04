import CryptoKit
import Foundation
import Permissions

/// Reading a file *and doing what it says*.
///
/// Kept apart from `FileUnderstanding` for the same reason that one is kept
/// apart from `FileOperation.readFile`: each is a wider grant than the last.
/// Reading shows you bytes; understanding sends them to the model; following
/// turns them into work. So this is `.externalNetwork` too — the contents leave
/// the machine before anything is planned — and the user is asked every time,
/// with the file named.
///
/// The user picks the file. Nothing here searches for one, and no filename is
/// ever inferred from a request: "run my deploy steps" resolves to a path the
/// person typed, or it doesn't resolve at all.
public struct InstructionRequest: Equatable, Sendable {
    public let relativePath: String

    public init(relativePath: String) {
        self.relativePath = relativePath
    }

    /// Never `.readOnly`. Approving "read files in this project" must not
    /// become permission to upload one, and it must certainly not become
    /// permission to act on what it says.
    public var actionClass: ActionClass { .externalNetwork }

    public var humanDescription: String {
        "Read \(relativePath) and send it to Claude to work out the steps it describes"
    }
}

/// What a file said, small enough to keep and compare.
///
/// Two questions need this and they are the same question at two scopes: has
/// the file changed *while a run is going* (stop, don't quietly switch to new
/// instructions mid-flight), and has it changed *since the last run this
/// session* (say so before starting again). Content, not modification date —
/// touching a file, or saving it unchanged, is not a change to what it asks
/// for.
public enum InstructionFingerprint {
    /// A short SHA-256 hex digest. Short because it is shown to nobody and
    /// compared against itself; 16 hex characters is 64 bits, which no accident
    /// will collide on.
    public static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Which instruction files have already been run, and what they said at the
/// time.
///
/// Session-scoped and never written to disk, like `selectedSkills` and
/// `activeLoop`: "have the steps changed since last time?" is a question about
/// this sitting, and a stale answer from last week would either nag about a
/// change the person already approved or stay silent about one they didn't.
public struct InstructionMemory: Equatable, Sendable {
    private var fingerprints: [String: String]

    public init(fingerprints: [String: String] = [:]) {
        self.fingerprints = fingerprints
    }

    /// False for a file never run here — a first run has nothing to have
    /// changed from, and saying "the steps changed" would be a lie.
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
