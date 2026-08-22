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

final class SkillExampleTests: XCTestCase {

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

    func testCurryAppliesToYourOwnTwoArityFunctionBecauseBowExportsNoFreeMapOverArray() {
        func clamp(_ upper: Int, _ x: Int) -> Int { min(upper, x) }
        let clampTo10 = curry(clamp)(10)

        XCTAssertEqual([1, 20, 3].map(clampTo10), [1, 10, 3])
    }

    func testOptionalRoundTripsThroughOption() {
        XCTAssertEqual(Option.fromOptional(7).toOptional(), 7)
        XCTAssertNil(Option<Int>.fromOptional(nil).toOptional())
    }

    func testOptionHasNoToEitherSoFoldIsTheConversion() {
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

    func testTheApplicativePairIsAStaticTwoArityMapBecauseZipOnOptionHasNoUsableShapeInBow080() {
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

    func testTraverseIsTheLoopThatCanFailWithNoPartiallyFilledAccumulatorToReasonAbout() {
        XCTAssertEqual(["1", "2"].traverse { Option.fromOptional(Int($0)) }^, Option.some([1, 2]))
        XCTAssertEqual(["1", "x"].traverse { Option.fromOptional(Int($0)) }^, Option.none())
    }

    func testTheFlattenedGuardFormAnswersTheSameAsTheNestedFormIncludingTheCaseTheElseUsedToHandle() {
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

    func testTheClockArrivesAsADefaultedLastParameterSoTheSameArgumentsNameTheAnswerExactly() {
        func age(of moment: Date, now: Date = Date()) -> String {
            let days = Calendar.current.dateComponents([.day], from: moment, to: now).day ?? 0
            return switch days {
            case ..<1: "today"
            case 1: "yesterday"
            default: "\(days) days ago"
            }
        }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let threeDaysBefore = now.addingTimeInterval(-3 * 24 * 60 * 60)

        XCTAssertEqual(age(of: threeDaysBefore, now: now), "3 days ago")
        XCTAssertEqual(age(of: threeDaysBefore, now: now), age(of: threeDaysBefore, now: now))
    }

    func testRailwayChainWithFlatMap() {
        let run = parse >>> { $0.flatMap(requirePositive)^ }

        XCTAssertEqual(run("4"), .right(4))
        XCTAssertEqual(run("-4"), .left(.notPositive))
        XCTAssertEqual(run("x"), .left(.notANumber))
    }

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

    private struct ProfileDTO: Codable, Equatable {
        var name: String
        var nickname: String?
    }

    private struct Profile: Equatable {
        var name: String
        var nickname: Option<String>
    }

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

    @MainActor
    func testEitherCrossesAnAsyncMainActorBoundary() async {
        func load() async -> Either<ParseError, Int> { .right(42) }
        let loaded = await load()
        XCTAssertEqual(loaded, .right(42))
    }

    func testCurriedStaticComposesInAPipeline() {
        let project = Project(name: "P", path: "/tmp/skill", allowedTools: ["git.readOnly"])
        let grants = PermissionGrants()
            |> PermissionGrants.granting(project: project, toolID: "git.readOnly", actionClass: .readOnly)

        XCTAssertTrue(grants.has(project: project, toolID: "git.readOnly", actionClass: .readOnly))
    }
}
