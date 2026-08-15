import FunctionalCore
import Foundation

/// Which project/tool pairs a human has already approved.
///
/// This is a value, not a mutable store: `granting` returns a new set rather
/// than mutating in place. That is what lets grants live inside the single
/// observable state alongside everything else the UI renders — there is no
/// second copy hidden in a class that can drift out of sync with the view.
public struct PermissionGrants: Equatable, Sendable {
    private struct Key: Hashable, Sendable {
        let projectID: UUID
        let toolID: String
    }

    private let keys: Set<Key>

    public init() {
        self.keys = []
    }

    private init(keys: Set<Key>) {
        self.keys = keys
    }

    public func granting(projectID: UUID, toolID: String) -> PermissionGrants {
        PermissionGrants(keys: keys.union([Key(projectID: projectID, toolID: toolID)]))
    }

    public func has(projectID: UUID, toolID: String) -> Bool {
        keys.contains(Key(projectID: projectID, toolID: toolID))
    }
}

extension PermissionGrants {
    /// Curried form, so a grant can be applied down a pipeline:
    /// `grants |> PermissionGrants.granting(projectID: id, toolID: tool)`
    public static func granting(
        projectID: UUID,
        toolID: String
    ) -> (PermissionGrants) -> PermissionGrants {
        { grants in grants.granting(projectID: projectID, toolID: toolID) }
    }
}
