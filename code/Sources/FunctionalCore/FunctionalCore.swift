@_exported import Bow
import Foundation

// Bow 0.8.0 predates `Sendable`, so none of its data types declare it. Storing
// an `Option` in a `Sendable` struct therefore warns today and fails to compile
// under the Swift 6 language mode.
//
// The conformances are sound rather than convenient: `Option`, `Either`, `Try`
// and `Validated` are plain enums over their type parameters with no shared
// mutable state, so a value is safe to hand across isolation domains exactly
// when its payload is. `@unchecked` is required only because the compiler
// cannot verify that for a type declared in another module.
//
// Every domain target depends on this module instead of Bow directly, so the
// conformances are declared once. Two modules each declaring them would be an
// ambiguity at every use site.

/// The Foundation edge in one function: run a throwing call and put whatever it
/// threw on the left rail.
///
/// `FileManager`, `JSONDecoder`, `Process` and friends keep throwing — that is
/// their API and it is not ours to change. Every domain module converts at its
/// own boundary by calling this, so `try` appears once per adapter instead of
/// spreading `do`/`catch` through the logic.
///
/// Callers should immediately `mapLeft` the untyped `Error` into their own
/// module's error enum, so the leaked `Error` never reaches a public signature.
public func attempt<A>(_ body: () throws -> A) -> Either<Error, A> {
    Try.invoke(body).toEither()
}

extension Option: @retroactive @unchecked Sendable where A: Sendable {}
extension Either: @retroactive @unchecked Sendable where A: Sendable, B: Sendable {}
extension Try: @retroactive @unchecked Sendable where A: Sendable {}
extension Validated: @retroactive @unchecked Sendable where E: Sendable, A: Sendable {}
