import Foundation

public enum PermissionAnswer: String, Equatable, Sendable, CaseIterable {
    case once
    case always
    case deny

    public var title: String {
        switch self {
        case .once: return "Once"
        case .always: return "Always"
        case .deny: return "Deny"
        }
    }
}

public enum GrantDuration: Equatable, Sendable {
    case session
    case always
}

extension PermissionAnswer {
    public func duration(for actionClass: ActionClass) -> GrantDuration? {
        guard mayBeRemembered(actionClass) else { return nil }
        switch self {
        case .once: return .session
        case .always: return .always
        case .deny: return nil
        }
    }
}

public func mayBeRemembered(_ actionClass: ActionClass) -> Bool {
    switch actionClass {
    case .readOnly, .localWrite:
        return true
    case .projectMemoryWrite, .externalNetwork, .browserAction,
         .destructive, .gitHistoryChanging, .dependencyInstalling,
         .directoryAccess:
        return false
    }
}

public func permissionScopeSentence(_ answers: [PermissionAnswer]) -> String {
    answers.contains(.always)
        ? """
          Once covers this conversation; Always covers reading and writing anywhere in \
          this project, and I'll still ask before deleting, installing, or anything that \
          leaves this Mac.
          """
        : "This allows it for the rest of this session only."
}

public func offeredAnswers(
    for request: ApprovalRequest,
    projectIsRegistered: Bool
) -> [PermissionAnswer] {
    let theGrantKeyWouldDescribeTheWholeOfWhatWasAgreed = mayBeRemembered(request.actionClass)
    let thereIsALastingProjectToHangTheGrantOn = projectIsRegistered
    let policyWouldHonourTheGrantRatherThanReAsk = !request.outsideAllowlist

    let alwaysIsOnOffer = theGrantKeyWouldDescribeTheWholeOfWhatWasAgreed
        && thereIsALastingProjectToHangTheGrantOn
        && policyWouldHonourTheGrantRatherThanReAsk

    return alwaysIsOnOffer ? [.once, .always, .deny] : [.once, .deny]
}
