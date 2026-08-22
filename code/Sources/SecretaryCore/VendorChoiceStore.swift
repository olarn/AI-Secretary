import FunctionalCore
import Foundation
import LLMProvider

public struct VendorChoice: Equatable, Sendable {
    public let vendorID: String
    public let cliPath: Option<String>

    public init(vendorID: String, cliPath: Option<String> = .none()) {
        self.vendorID = vendorID
        self.cliPath = cliPath
    }

    public static let claudeCode = VendorChoice(vendorID: AIVendor.claudeCode.id)

    public func choosing(vendorID: String) -> VendorChoice {
        VendorChoice(vendorID: vendorID, cliPath: cliPath)
    }

    public func choosing(cliPath: Option<String>) -> VendorChoice {
        VendorChoice(vendorID: vendorID, cliPath: cliPath)
    }
}

public protocol VendorChoiceStoring: Sendable {
    func load() -> VendorChoice
    func save(_ choice: VendorChoice)
}

public struct InMemoryVendorChoiceStore: VendorChoiceStoring {
    public init() {}
    public func load() -> VendorChoice { .claudeCode }
    public func save(_ choice: VendorChoice) {}
}

public final class UserDefaultsVendorChoiceStore: VendorChoiceStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let vendorKey: String
    private let pathKey: String

    public init(character: UUID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.vendorKey = "assistant.\(character.uuidString).vendor"
        self.pathKey = "assistant.\(character.uuidString).cliPath"
    }

    public func load() -> VendorChoice {
        let vendor = Option.fromOptional(defaults.string(forKey: vendorKey))
            .flatMap(AIVendor.named)^
            .map(\.id)^
            .getOrElse(AIVendor.claudeCode.id)
        return VendorChoice(
            vendorID: vendor,
            cliPath: Option.fromOptional(defaults.string(forKey: pathKey))
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }^
        )
    }

    public func save(_ choice: VendorChoice) {
        defaults.set(choice.vendorID, forKey: vendorKey)
        choice.cliPath.fold(
            { self.defaults.removeObject(forKey: self.pathKey) },
            { self.defaults.set($0, forKey: self.pathKey) }
        )
    }
}
