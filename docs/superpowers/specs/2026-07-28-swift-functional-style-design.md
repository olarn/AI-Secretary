# Functional style for the non-SwiftUI layers

Date: 2026-07-28

## Goal

Rewrite the domain layers of AI Secretary in typed functional style: `Option`
instead of `nil`, `Either` instead of `throws`, pure functions composed into
pipelines, on [Bow](https://github.com/bow-swift/bow) 0.8.0. SwiftUI views stay
ordinary SwiftUI. Every unit test keeps passing; tests change only where an API
changed under them.

In scope: `AssistantState`, `ProjectRegistry`, `Permissions`, `ToolAdapters`,
`LLMProvider`, `Credentials`, `SecretaryCore`. Out of scope: `AISecretaryApp`.

## What the probes established

Before designing, each risky boundary was compiled rather than guessed.

| Probe | Result |
|---|---|
| Bow 0.8.0 against swift-tools 5.9 / macOS 14 | builds |
| `Codable` struct with an `Option` field | **fails to compile** |
| `@Observable` class holding `Option`/`Either` | works |
| `async` returning `Either`, consumed on `@MainActor` | works |
| `x \|> f` pipe-forward and partial application | both, built in |
| `f >>> g`, `curry` over an own 2-ary function | work |
| `binding(n <- …, yield: …)` | works; needs `BoundVar`, not closures |
| `Result.toEither()`, `Validated` | available |
| `>=>` Kleisli operator | **absent from Bow** |
| free `map` over `Array` | **absent from Bow** — `curry(map)` does not resolve |
| `Sendable` on any Bow type | **absent** — found later, in phase 2, not by the probes |

Bow 0.8.0 is the newest release (May 2020) and the library is not actively
maintained. It compiles cleanly here and is the library the project chose, so it
stays; the staleness is recorded as a known risk, not worked around.

## Decisions

**Bow is the only new dependency.** SwiftPipeline was considered for the
operation-chain requirement and rejected: 12 commits, no tagged release, and
Bow's own `|>`, `>>>`, and `curry` already cover pipe-forward, composition, and
partial application. One stale dependency is a smaller risk than two.

**The boundary rule is the architecture.** Bow types in the domain core; Swift
native types at three edges, each with an explicit conversion:

- *Persistence* — `Codable` DTOs with Swift `Optional`, plus `toDomain`/`toDTO`.
  Forced by the probe, and it keeps the on-disk format stable so existing user
  profiles and project registries still load.
- *View* — `@Observable` may hold `Option`/`Either`, but a SwiftUI view file
  must not import Bow at all: Bow exports its own `State`, which shadows
  `@State`. The conversion lives in a bridge file that contains no views.
- *Foundation* — `FileManager` and `Process` keep `throws`; adapters convert to
  `Either` once, at the boundary.

**Per-module error enums.** Each target owns its failures (`PermissionError`,
and so on) and never imports another module's error type. Cross-layer callers
map at the boundary. The cost is explicit mapping; the benefit is that a leaf
target stays independent and `switch` sites stay exhaustive and small.

**State is a value.** Types that hold state become immutable values with `-ing`
methods returning a new value, so the single `@Observable` store owns the only
copy. This is the Single-Source-of-Truth requirement: no mutable state hidden in
a class that can drift from what the view renders.

**Point-free within reason.** `Option` and `Either` get full Bow treatment.
Plain collections keep `list.map(f)` — `map(f)(list)` on an `Array` routes
through `ArrayK` and `^`, which reads worse than the method. This is the
readability exception the requirement allows, stated once so it is not
rediscovered per file.

## Sequencing

Leaf-first up the dependency graph, `swift test` green at every commit. All five
phases are complete, each its own commit so any of them can be reverted alone:

1. `Permissions` — pilot.
2. `AssistantState`, `ProjectRegistry`, `Credentials`.
3. `ToolAdapters`, `LLMProvider`.
4. `SecretaryCore` excluding `Secretary.swift`.
5. `Secretary.swift`; grants moved into its observable state and the
   `DefaultPermissionPolicy` shim deleted.

A single big-bang commit cannot satisfy "all tests keep passing", so it was not
attempted.

## What the conversion turned up

Four constraints only appeared once real code was compiled, and each is now
recorded in the skill:

- **Bow declares no `Sendable` conformances.** Storing an `Option` in a
  `Sendable` struct warns today and fails under the Swift 6 language mode. That
  is why `FunctionalCore` exists: it re-exports Bow and declares the
  conformances once, since two modules declaring them would be ambiguous
  everywhere.
- **Bow exports its own `State`.** Importing it into a SwiftUI view shadows
  `@State` and breaks every property wrapper in the file. Views therefore never
  import it; `AISecretaryApp/DomainBridge.swift` does the conversion and holds
  no views.
- **`XCTAssertNil` on an `Option` asserts nothing** — it wraps the `Option` in
  an `Optional`, which is never nil. Four assertions in the existing suite were
  silently vacuous and were caught only because the types changed under them.
- **Conversion members beat free functions.** `Project(dto)` / `project.dto`
  rather than free `toDomain`/`toDTO`, which would collide once seven modules
  each defined a pair.

## Result

- No `throws` in any domain target's public API. The only remaining `throws` are
  `attempt` itself and one private `async` helper inside `ClaudeCodeProvider`
  whose error is converted at the stream boundary.
- No domain public API returns a Swift `Optional`.
- On-disk formats are unchanged: `projects.json` and `profiles.json` keep their
  keys, so existing installs load without migration.
- `swift build` and `swift test` are clean — zero warnings, zero failures.

## The permission path, end to end

`PermissionGrants` is an immutable value; `decidePermission(grants)(request)` is
a pure curried function; refusal sits on the left rail as `PermissionError`. Two
named rails (`requireAllowlistedTool`, `requireApproval`) compose into one
expression, each testable alone.

Phase 1 kept `DefaultPermissionPolicy` as a labelled adapter so `SecretaryCore`
compiled unchanged. Phase 5 moved `Secretary` onto the pure core and deleted the
adapter, the `PermissionPolicy` protocol and `PolicyDecision` with it. Grants now
live in `Secretary`'s observable state, which is the Single-Source-of-Truth
requirement met concretely: no second copy in a policy object.

## Known risks

- **Bow is unmaintained.** No fix will arrive from upstream. If a future Swift
  release breaks it, the exit is `FunctionalCore` — it already isolates the
  dependency, so it can supply the handful of types actually used (`Option`,
  `Either`, `|>`, `>>>`, `curry`) without touching a domain file.
- **Swift 6 language mode is untested.** The package is on tools 5.9 / language
  mode 5. The `Sendable` conformances in `FunctionalCore` are what a bump would
  need, but the bump itself is a separate exercise and may surface more.
- **`@retroactive @unchecked Sendable`** is a promise the compiler cannot check.
  It is sound for Bow's plain enums, and it would break loudly rather than
  silently if upstream ever declared its own conformances — but upstream is
  dormant, so that is theoretical.
