import FunctionalCore
import Foundation
import LLMProvider

/// Which maker a character works through, and where its tool is.
///
/// Per character rather than per app, like her model and her effort: the panel
/// that chooses it is her Profile, and two characters on the same desktop may
/// reasonably run through different makers — one on the user's Claude Code
/// subscription, one on a local model that costs nothing.
public struct VendorChoice: Equatable, Sendable {
    public let vendorID: String
    /// Only meaningful for a maker whose executable the user supplies. Absent
    /// means "look in the usual places", which is what the field being empty
    /// means on screen.
    public let cliPath: Option<String>

    public init(vendorID: String, cliPath: Option<String> = .none()) {
        self.vendorID = vendorID
        self.cliPath = cliPath
    }

    /// What a character runs through until somebody chooses otherwise.
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

/// The default, which deliberately reaches nowhere — a suite that forgot to
/// override it must not write into the person's own preferences.
public struct InMemoryVendorChoiceStore: VendorChoiceStoring {
    public init() {}
    public func load() -> VendorChoice { .claudeCode }
    public func save(_ choice: VendorChoice) {}
}

/// Hers, keyed by profile, like the model and effort beside it.
public final class UserDefaultsVendorChoiceStore: VendorChoiceStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let vendorKey: String
    private let pathKey: String

    public init(character: UUID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.vendorKey = "assistant.\(character.uuidString).vendor"
        self.pathKey = "assistant.\(character.uuidString).cliPath"
    }

    /// A stored id this build has never heard of reads as the default rather
    /// than as a failure — a settings file written by a later build must not
    /// leave a character unable to work.
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

    /// Clearing the path removes the key rather than storing an empty string:
    /// "look in the usual places" is a choice, and an empty string would later
    /// read as a path that happens to be blank.
    public func save(_ choice: VendorChoice) {
        defaults.set(choice.vendorID, forKey: vendorKey)
        choice.cliPath.fold(
            { self.defaults.removeObject(forKey: self.pathKey) },
            { self.defaults.set($0, forKey: self.pathKey) }
        )
    }
}
