import FunctionalCore
import Foundation
import Security

/// Persistence boundary for the Claude API key. The key never touches the repo,
/// the project registry, logs, or chat history — only this store.
///
/// Absence is `Option`, not `nil`: "no key configured" is a normal state the
/// caller must handle, and it reads differently from a lookup that failed.
public protocol CredentialStore: AnyObject, Sendable {
    func apiKey() -> Option<String>
    func setAPIKey(_ key: Option<String>) -> Either<CredentialError, Void>
    var hasAPIKey: Bool { get }
}

public extension CredentialStore {
    var hasAPIKey: Bool {
        apiKey().filter { !$0.isEmpty }^.isDefined
    }

    /// Convenience for the view edge, where a cleared text field is `""`.
    @discardableResult
    func setAPIKey(text: String) -> Either<CredentialError, Void> {
        setAPIKey(nonEmpty(text))
    }
}

/// A trimmed, non-empty string, or nothing. The single place blank input is
/// turned into absence, so no caller has to remember the `isEmpty` check.
public func nonEmpty(_ text: String) -> Option<String> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? .none() : .some(trimmed)
}

public enum CredentialError: Error, Equatable, Sendable, LocalizedError {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain error (\(status))."
        }
    }
}

/// Stores the API key in the login keychain as a generic password. On an
/// unsigned `swift run` binary macOS may prompt to allow access on first use —
/// that is expected, not a failure.
public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.aisecretary.app", account: String = "anthropic.apiKey") {
        self.service = service
        self.account = account
    }

    public func apiKey() -> Option<String> {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return .none() }

        return Option.fromOptional(item as? Data)
            .flatMap { data in Option.fromOptional(String(data: data, encoding: .utf8)) }^
    }

    public func setAPIKey(_ key: Option<String>) -> Either<CredentialError, Void> {
        key.filter { !$0.isEmpty }^
            .fold(clear, store)
    }

    /// Clearing removes the item entirely. "Nothing to delete" is success —
    /// the postcondition the caller asked for already holds.
    private func clear() -> Either<CredentialError, Void> {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
            ? .right(())
            : .left(.keychain(status))
    }

    private func store(_ key: String) -> Either<CredentialError, Void> {
        let data = Data(key.utf8)
        let status = apiKey().isDefined
            ? SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            : SecItemAdd(added(data) as CFDictionary, nil)

        return status == errSecSuccess ? .right(()) : .left(.keychain(status))
    }

    private func added(_ data: Data) -> [String: Any] {
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        return attributes
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// In-memory store for tests and previews — never touches the keychain.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Option<String>

    public init(apiKey: Option<String> = .none()) {
        self.stored = apiKey
    }

    public func apiKey() -> Option<String> {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func setAPIKey(_ key: Option<String>) -> Either<CredentialError, Void> {
        lock.lock(); defer { lock.unlock() }
        stored = key.filter { !$0.isEmpty }^
        return .right(())
    }
}
