---
name: swift-functional-programming
description: Use when writing or changing Swift logic outside SwiftUI views in this repo — any file under code/Sources/AssistantState, ProjectRegistry, Permissions, ToolAdapters, LLMProvider, Credentials, or SecretaryCore. Also use when adding a Codable model, an async provider call, a permission or validation check, or when a type would otherwise be optional or throwing.
---

# Swift Functional Programming (Bow)

## Overview

Domain logic in this repo is written in typed functional style on [Bow](https://github.com/bow-swift/bow) 0.8.0: `Option` instead of `nil`, `Either` instead of `throws`, pure functions composed into pipelines. SwiftUI views stay ordinary SwiftUI.

**Core principle: a result is a value, not a control-flow event.** A decision you can store in state, compare in a test, and pass to the next step beats one that unwinds the stack.

## The boundary rule

Bow types live in the domain core. Swift-native types live at three edges, with an explicit conversion function at each. **This is not stylistic — `Option` in a `Codable` struct does not compile.**

| Edge | What crosses it | Conversion |
|---|---|---|
| **Persistence** | `Codable` DTO with Swift `Optional` | `toDomain` / `toDTO` free functions |
| **View** | `@Observable` may hold `Option`/`Either`; anything feeding `Binding`/`TextField` exposes a computed Swift-native projection | computed property |
| **Foundation** | `FileManager`, `Process` keep `throws` | wrap once, in the adapter, into `Either` |

`@Observable` holding `Option`/`Either` works. `async` returning `Either` consumed on `@MainActor` works, with no Sendable warnings. Only `Codable` is hard-blocked.

## What Bow actually has

Verified by compiling against 0.8.0 in this repo. Getting this wrong is the most common way to waste a build cycle.

| Want | Exists | Notes |
|---|---|---|
| pipe value into function | ✅ `x \|> f` | same operator also partially applies: `3 \|> add` → `(Int) -> Int` |
| compose functions | ✅ `f >>> g`, `g <<< f`, `andThen(f, g)` | |
| curry | ✅ `curry(f)` | `curry(map)(double)([1,2,3])` |
| Optional → Option | ✅ `Option.fromOptional(x)` | reverse: `opt.toOptional()` |
| Result → Either | ✅ `result.toEither()` | |
| accumulate many errors | ✅ `Validated`, `ValidatedNEA` | use for multi-field validation, not first-failure |
| Kleisli composition `>=>` | ❌ **not in Bow** | use `.flatMap(f)^` or `binding` |
| `Option.toEither(_:)` | ❌ **does not exist** | use `fold({ .left(e) }, { .right($0) })` |
| `Codable` on `Option`/`Either` | ❌ **does not exist** | DTO at the persistence edge |

**`^` is required** after `map`/`flatMap` on `Either`/`Option` — those return `Kind<F, A>`, and `^` fixes it back to the concrete type. Omitting it is a type error, not a warning.

## The recipe for a decision

A function that can refuse produces `Either<ModuleError, Outcome>`. Write it as named rails plus one chain:

```swift
// 1. Per-module error enum. Permissions owns its failures and never
//    imports another module's error type.
public enum PermissionError: Error, Equatable, Sendable {
    case toolNotAllowlisted(toolID: String, projectName: String)
}

public typealias PermissionDecision = Either<PermissionError, PermissionOutcome>

// 2. One rail per rule. Each is pure, total, and testable alone.
public func requireAllowlistedTool(
    _ request: ApprovalRequest
) -> Either<PermissionError, ApprovalRequest> {
    request.project.allows(tool: request.toolID)
        ? .right(request)
        : .left(.toolNotAllowlisted(toolID: request.toolID, projectName: request.project.name))
}

// 3. Dependencies come in as a curried first parameter, not as stored
//    properties, so the rail stays a function of its inputs.
public func requireApproval(
    _ grants: PermissionGrants
) -> (ApprovalRequest) -> Either<PermissionError, PermissionOutcome> { ... }

// 4. The chain is one expression, point-free.
public func decide(_ grants: PermissionGrants) -> (ApprovalRequest) -> PermissionDecision {
    requireAllowlistedTool >>> { $0.flatMap(requireApproval(grants))^ }
}
```

Live version: `code/Sources/Permissions/`.

For a chain longer than three rails, `binding` reads better than nested `flatMap`. It needs `BoundVar`s and a `yield:` label — closures do not work:

```swift
let n = Either<AppError, Int>.var()
let m = Either<AppError, Int>.var()
return binding(
    n <- parse(input),
    m <- check(n.get),
    yield: m.get
)^
```

## State is a value

Mutable state in a class is a second copy that drifts from what the view renders. Model it as an immutable value with `-ing` methods returning a new one, then let the single `@Observable` store hold it:

```swift
public func granting(projectID: UUID, toolID: String) -> PermissionGrants  // returns a new value

// Curried static twin, so it composes in a pipeline:
grants = grants |> PermissionGrants.granting(projectID: id, toolID: tool)
```

Behaviour that is currently a protocol + class purely to be swapped in tests is usually better as a pure function taking its dependency as a parameter — the test passes a value instead of building a fake.

## Point-free, within reason

Use `|>`, `>>>`, and `curry` when they shorten the read. Readability wins over purity — this is an explicit exception, not a loophole:

- ✅ `decide(grants)` returning a reusable `(ApprovalRequest) -> PermissionDecision`
- ✅ `grants |> PermissionGrants.granting(...)`
- ❌ `map(f)(list)` on a plain `Array` — Bow routes that through `ArrayK` and `^`, which is louder than `list.map(f)`. Keep `list.map`.

Reach for point-free on `Option`/`Either` and on functions you want to pass around. Leave plain-collection code alone.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| `type 'X' does not conform to protocol 'Decodable'` | `Option` field in a `Codable` struct | Swift `Optional` in a DTO; convert at the edge |
| `cannot convert Kind<EitherPartial<E>, A> to Either<E, A>` | missing `^` after `map`/`flatMap` | append `^` |
| `cannot find operator '>=>' in scope` | Bow has no Kleisli operator | `.flatMap(f)^` or `binding` |
| `value of type 'Option<A>' has no member 'toEither'` | wrong API name | `fold({ .left(e) }, { .right($0) })` |
| `closure passed to parameter of type 'BindingExpression'` | `binding` called with closures | use `n <- expr` and `yield:` |
| new `throws` in a domain function | Foundation call not wrapped | wrap in the adapter, return `Either` |

## Checklist before committing domain code

- No `throws` in a domain function; failures are on the left of `Either`.
- No `?` in a domain type; absence is `Option`. Swift `Optional` only in DTOs and view projections.
- Error enum belongs to this module and is `Equatable, Sendable`.
- State-holding types are values with `-ing` methods, not classes with `var`.
- `swift test` passes. If an API changed, the test changed with it — a deleted assertion is not a passing test.
