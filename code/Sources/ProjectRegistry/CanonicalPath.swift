import Foundation

public struct CanonicalPath: Equatable, Hashable, Sendable, Codable {
    public let value: String

    public init(_ path: String) {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let withoutTrailingSlash = standardized.count > 1 && standardized.hasSuffix("/")
            ? String(standardized.dropLast())
            : standardized
        self.value = withoutTrailingSlash
    }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public func contains(_ other: CanonicalPath) -> Bool {
        other.value == value || other.value.hasPrefix(value + "/")
    }
}
