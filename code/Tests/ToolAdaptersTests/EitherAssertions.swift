import FunctionalCore
import XCTest
import ToolAdapters

// Adapters answer with `Either<ToolError, ToolResult>`, so a test either wants
// the result or the refusal. These say which, and fail with the other rail's
// contents when the answer is the wrong shape — a bare `XCTUnwrap` on an
// `Option` would just say "nil" and lose the error that explains why.

/// The result, failing the test if the adapter refused.
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

/// The refusal, failing the test if the adapter actually succeeded.
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
