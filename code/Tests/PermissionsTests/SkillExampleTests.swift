import FunctionalCore
import XCTest
import ProjectRegistry
@testable import Permissions

private enum ParseError: Error, Equatable { case notANumber, notPositive }

private func parse(_ s: String) -> Either<ParseError, Int> {
    Option.fromOptional(Int(s)).fold({ .left(.notANumber) }, { .right($0) })
}

private func requirePositive(_ n: Int) -> Either<ParseError, Int> {
    n > 0 ? .right(n) : .left(.notPositive)
}

/// Every claim the `swift-functional-programming` skill makes about Bow's API,
/// compiled and asserted here. The skill is only worth reading if it is true of
/// the library actually linked, and Bow 0.8.0 is unmaintained — this is what
/// catches the day a toolchain bump changes an answer.
///
/// If a snippet in `.claude/skills/swift-functional-programming/SKILL.md`
/// changes, change it here too.
final class SkillExampleTests: XCTestCase {

    // MARK: - "What Bow actually has"

    func testPipeForwardAppliesAValueToAFunction() {
        let double = { (x: Int) in x * 2 }
        XCTAssertEqual(5 |> double, 10)
    }

    func testPipeForwardAlsoPartiallyApplies() {
        let add: (Int, Int) -> Int = (+)
        let addThree = 3 |> add
        XCTAssertEqual(addThree(4), 7)
    }

    func testCompositionInBothDirections() {
        let double = { (x: Int) in x * 2 }
        let show = { (x: Int) in "\(x)" }

        XCTAssertEqual((double >>> show)(5), "10")
        XCTAssertEqual((show <<< double)(5), "10")
        XCTAssertEqual(try andThen(double, show)(5), "10")
    }

    /// Bow exports no free `map` over `Array`; `curry` applies to your own
    /// 2-ary functions. Writing `curry(map)` is `cannot find 'map' in scope`.
    func testCurryOverAnOwnFunction() {
        func clamp(_ upper: Int, _ x: Int) -> Int { min(upper, x) }
        let clampTo10 = curry(clamp)(10)

        XCTAssertEqual([1, 20, 3].map(clampTo10), [1, 10, 3])
    }

    func testOptionalRoundTripsThroughOption() {
        XCTAssertEqual(Option.fromOptional(7).toOptional(), 7)
        XCTAssertNil(Option<Int>.fromOptional(nil).toOptional())
    }

    /// `Option` has no `toEither`; fold is the conversion.
    func testOptionToEitherViaFold() {
        let present = Option.some(7)
            .fold({ Either<String, Int>.left("missing") }, { .right($0) })
        let absent = Option<Int>.none()
            .fold({ Either<String, Int>.left("missing") }, { .right($0) })

        XCTAssertEqual(present, .right(7))
        XCTAssertEqual(absent, .left("missing"))
    }

    func testSwiftResultConvertsToEither() {
        let ok: Swift.Result<Int, PermissionError> = .success(1)
        XCTAssertEqual(ok.toEither(), .right(1))
    }

    // MARK: - Designing with functions

    /// Rails held as data: adding a rule is adding an element, not editing a
    /// function. The `^` after `flatMap` is what makes the fold type-check.
    func testRailsHeldAsDataFoldIntoOneDecision() {
        let rules: [(String, (Int) -> Either<ParseError, Int>)] = [
            ("positive", requirePositive),
            ("small", { $0 < 100 ? .right($0) : .left(.notPositive) })
        ]
        func check(_ candidate: Int) -> Either<ParseError, Int> {
            rules.reduce(Either<ParseError, Int>.right(candidate)) { result, rule in
                result.flatMap(rule.1)^
            }
        }

        XCTAssertEqual(check(4), .right(4))
        XCTAssertEqual(check(400), .left(.notPositive))
        XCTAssertEqual(check(-1), .left(.notPositive))
    }

    /// One unwrap, at the end — not one per step.
    func testTheUnwrapIsTheLastStep() {
        func label(_ rawName: String?) -> String {
            Option.fromOptional(rawName)
                .map { $0.trimmingCharacters(in: .whitespaces) }^
                .filter { !$0.isEmpty }^
                .getOrElse("Untitled conversation")
        }

        XCTAssertEqual(label("  the vault "), "the vault")
        XCTAssertEqual(label("   "), "Untitled conversation")
        XCTAssertEqual(label(nil), "Untitled conversation")
    }

    /// The applicative pair, which replaces `if let a = x, let b = y`. Bow
    /// 0.8.0 spells it as a static 2-ary `map`; `zip` on `Option` does not work
    /// in a usable shape, which is why the skill tells you not to reach for it.
    func testTwoContainersOneFunction() {
        XCTAssertEqual(Option<Int>.map(Option.some(1), Option.some(2)) { $0 + $1 }^, Option.some(3))
        XCTAssertEqual(Option<Int>.map(Option.some(1), Option.none()) { $0 + $1 }^, Option.none())
        XCTAssertEqual(
            Either<ParseError, Int>.map(
                Either<ParseError, Int>.right(1),
                Either<ParseError, Int>.right(2)
            ) { $0 + $1 }^,
            .right(3)
        )
    }

    /// The fallible loop: every element, or the first failure — no `for`, no
    /// partially-filled accumulator to reason about.
    func testTraverseIsTheLoopThatCanFail() {
        XCTAssertEqual(["1", "2"].traverse { Option.fromOptional(Int($0)) }^, Option.some([1, 2]))
        XCTAssertEqual(["1", "x"].traverse { Option.fromOptional(Int($0)) }^, Option.none())
    }

    /// §8: the nested form and the flattened one, asserted to agree.
    ///
    /// This is the shape of the proof the skill asks for — the inversion is
    /// only a refactor if something checks that both answer the same on the
    /// cases that mattered, including the one the `else` used to handle.
    func testGuardStyleMeansTheSameAsTheNestedForm() {
        func nested(_ raw: String?, allowEmpty: Bool) -> String {
            if let raw {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty && !allowEmpty {
                    return "Untitled"
                } else {
                    return trimmed
                }
            } else {
                return "Untitled"
            }
        }

        func flattened(_ raw: String?, allowEmpty: Bool) -> String {
            guard let raw else { return "Untitled" }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // The negation, spelled out: `!(empty && !allow)` is `!empty || allow`.
            guard !trimmed.isEmpty || allowEmpty else { return "Untitled" }
            return trimmed
        }

        for raw in [nil, "", "   ", " the vault "] as [String?] {
            for allowEmpty in [true, false] {
                XCTAssertEqual(
                    nested(raw, allowEmpty: allowEmpty),
                    flattened(raw, allowEmpty: allowEmpty),
                    "raw: \(String(describing: raw)), allowEmpty: \(allowEmpty)"
                )
            }
        }
    }

    // MARK: - The railway recipe

    /// `^` is required after `flatMap` — without it the result is
    /// `Kind<EitherPartial<E>, A>`, not `Either<E, A>`.
    func testRailwayChainWithFlatMap() {
        let run = parse >>> { $0.flatMap(requirePositive)^ }

        XCTAssertEqual(run("4"), .right(4))
        XCTAssertEqual(run("-4"), .left(.notPositive))
        XCTAssertEqual(run("x"), .left(.notANumber))
    }

    /// `binding` needs `BoundVar`s and a `yield:` label. Passing closures is
    /// "closure passed to parameter of type 'BindingExpression'".
    func testRailwayChainWithBinding() {
        func run(_ input: String) -> Either<ParseError, Int> {
            let n = Either<ParseError, Int>.var()
            let m = Either<ParseError, Int>.var()
            return binding(
                n <- parse(input),
                m <- requirePositive(n.get),
                yield: m.get
            )^
        }

        XCTAssertEqual(run("4"), .right(4))
        XCTAssertEqual(run("-4"), .left(.notPositive))
    }

    // MARK: - Boundary rule

    private struct ProfileDTO: Codable, Equatable {
        var name: String
        var nickname: String?
    }

    private struct Profile: Equatable {
        var name: String
        var nickname: Option<String>
    }

    /// `Option` in a `Codable` struct does not compile, so the persistence edge
    /// is a DTO with Swift `Optional` plus a pair of conversions.
    func testDTORoundTripsAcrossThePersistenceEdge() throws {
        func toDomain(_ d: ProfileDTO) -> Profile {
            Profile(name: d.name, nickname: Option.fromOptional(d.nickname))
        }
        func toDTO(_ p: Profile) -> ProfileDTO {
            ProfileDTO(name: p.name, nickname: p.nickname.toOptional())
        }

        let original = ProfileDTO(name: "Miku", nickname: nil)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProfileDTO.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(toDTO(toDomain(decoded)), original)
    }

    /// An `async` function may return `Either` and be consumed on `@MainActor`.
    @MainActor
    func testEitherCrossesAnAsyncMainActorBoundary() async {
        func load() async -> Either<ParseError, Int> { .right(42) }
        let loaded = await load()
        XCTAssertEqual(loaded, .right(42))
    }

    // MARK: - State is a value

    func testCurriedStaticComposesInAPipeline() {
        let projectID = UUID()
        let grants = PermissionGrants()
            |> PermissionGrants.granting(projectID: projectID, toolID: "git.readOnly")

        XCTAssertTrue(grants.has(projectID: projectID, toolID: "git.readOnly"))
    }
}
