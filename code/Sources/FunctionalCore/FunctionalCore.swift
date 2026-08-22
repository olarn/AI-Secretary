@_exported import Bow
import Foundation

public func attempt<A>(_ body: () throws -> A) -> Either<Error, A> {
    Try.invoke(body).toEither()
}

extension Option: @retroactive @unchecked Sendable where A: Sendable {}
extension Either: @retroactive @unchecked Sendable where A: Sendable, B: Sendable {}
extension Try: @retroactive @unchecked Sendable where A: Sendable {}
extension Validated: @retroactive @unchecked Sendable where E: Sendable, A: Sendable {}
