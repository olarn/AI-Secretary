import FunctionalCore
import Foundation

public protocol SkillInstalling: AnyObject, Sendable {
    func installSkill(named plugin: String) async -> Either<String, String>
}

public func validSkillPluginName(_ name: String) -> Bool {
    guard !name.isEmpty, name.count <= 128, !name.hasPrefix("-") else { return false }
    let parts = name.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }

    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-@")
    return name.lowercased().unicodeScalars.allSatisfy(allowed.contains)
}

public func skillInstallArguments(plugin: String) -> [String] {
    ["plugin", "install", plugin, "--yes", "--scope", "user"]
}
