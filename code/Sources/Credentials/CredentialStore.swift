import Foundation
import Security

/// Persistence boundary for the Claude API key. The key never touches the repo,
/// the project registry, logs, or chat history — only this store.
public protocol CredentialStore: AnyObject, Sendable {
    func apiKey() -> String?
    func setAPIKey(_ key: String?) throws
    var hasAPIKey: Bool { get }
}

public extension CredentialStore {
    var hasAPIKey: Bool { !(apiKey() ?? "").isEmpty }
}

public enum CredentialError: Error, LocalizedError {
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

    public func apiKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    public func setAPIKey(_ key: String?) throws {
        // Clearing removes the item entirely.
        guard let key, !key.isEmpty else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw CredentialError.keychain(status)
            }
            return
        }

        let data = Data(key.utf8)
        if apiKey() != nil {
            let attributes: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            if status != errSecSuccess { throw CredentialError.keychain(status) }
        } else {
            var attributes = baseQuery
            attributes[kSecValueData as String] = data
            let status = SecItemAdd(attributes as CFDictionary, nil)
            if status != errSecSuccess { throw CredentialError.keychain(status) }
        }
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
    private var stored: String?

    public init(apiKey: String? = nil) {
        self.stored = apiKey
    }

    public func apiKey() -> String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func setAPIKey(_ key: String?) throws {
        lock.lock(); defer { lock.unlock() }
        stored = (key?.isEmpty ?? true) ? nil : key
    }
}
