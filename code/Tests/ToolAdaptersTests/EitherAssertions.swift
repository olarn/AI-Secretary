import FunctionalCore
import XCTest
import ToolAdapters

func expectSuccess(
    _ outcome: Either<ToolError, ToolResult>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> ToolResult {
    try XCTUnwrap(
        outcome.toOption().toOptional(),
        "Expected a result, got refusal: \(describeRefusal(outcome))",
        file: file,
        line: line
    )
}

func expectRefusal(
    _ outcome: Either<ToolError, ToolResult>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> ToolError {
    try XCTUnwrap(
        outcome.swap().toOption().toOptional(),
        "Expected a refusal, but the adapter succeeded",
        file: file,
        line: line
    )
}

private func describeRefusal(_ outcome: Either<ToolError, ToolResult>) -> String {
    outcome.swap().toOption().toOptional().map { "\($0)" } ?? "none"
}
