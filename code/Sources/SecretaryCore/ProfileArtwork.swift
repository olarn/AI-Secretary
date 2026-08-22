import FunctionalCore
import Foundation
import AssistantState

public struct ProfileArtwork: Sendable {
    public static let fileName = "picture.png"

    public let root: URL

    public init(root: URL = ProfileArtwork.defaultRoot) {
        self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AISecretary", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    public func directory(for profile: UUID) -> URL {
        root.appendingPathComponent(profile.uuidString, isDirectory: true)
    }

    public func url(for profile: UUID) -> URL {
        directory(for: profile).appendingPathComponent(Self.fileName)
    }

    public func resolve(
        profile: UUID,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Option<URL> {
        let picture = url(for: profile)
        return exists(picture) ? .some(picture) : .none()
    }

    public func hasArtwork(
        for profile: UUID,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Bool {
        exists(url(for: profile))
    }

    @discardableResult
    public func install(pngData: Data, for profile: UUID) -> Either<ArtworkError, URL> {
        let destination = url(for: profile)
        return attempt {
            try FileManager.default.createDirectory(
                at: directory(for: profile),
                withIntermediateDirectories: true
            )
            try pngData.write(to: destination, options: .atomic)
            return destination
        }
        .mapLeft { .installFailed(path: destination.path, message: $0.localizedDescription) }^
    }

    @discardableResult
    public func remove(for profile: UUID) -> Either<ArtworkError, Void> {
        removeIfPresent(at: url(for: profile))
    }

    @discardableResult
    public func removeAll(for profile: UUID) -> Either<ArtworkError, Void> {
        removeIfPresent(at: directory(for: profile))
    }

    private func removeIfPresent(at target: URL) -> Either<ArtworkError, Void> {
        guard FileManager.default.fileExists(atPath: target.path) else { return .right(()) }
        return attempt { try FileManager.default.removeItem(at: target) }
            .mapLeft { .removeFailed(path: target.path, message: $0.localizedDescription) }^
    }

    static let legacyFileNames: [String] = ["default.png"]
        + [AssistantState.idle, .listening, .thinking, .working, .success, .error]
            .map { "\($0.rawValue).png" }

    public func migrateLegacyArtwork(for profile: UUID) {
        let manager = FileManager.default
        let destination = url(for: profile)
        guard !manager.fileExists(atPath: destination.path) else { return }

        let directory = directory(for: profile)
        for name in Self.legacyFileNames {
            let candidate = directory.appendingPathComponent(name)
            guard manager.fileExists(atPath: candidate.path) else { continue }
            try? manager.copyItem(at: candidate, to: destination)
            return
        }
    }
}

public enum ArtworkError: Error, Equatable, Sendable {
    case installFailed(path: String, message: String)
    case removeFailed(path: String, message: String)

    public var reason: String {
        switch self {
        case let .installFailed(path, message):
            return "Couldn't save the picture to \(path): \(message)"
        case let .removeFailed(path, message):
            return "Couldn't remove the picture at \(path): \(message)"
        }
    }
}
