---
name: swift-functional-programming
description: Use when writing or changing Swift logic outside SwiftUI views in this repo — any file under code/Sources/AssistantState, ProjectRegistry, Permissions, ToolAdapters, LLMProvider, Credentials, or SecretaryCore. Also use when adding a Codable model, an async provider call, a permission or validation check, or when a type would otherwise be optional or throwing.
---

# Swift Functional Programming (Bow)

## Overview

Domain logic in this repo is written in typed functional style on [Bow](https://github.com/bow-swift/bow) 0.8.0: `Option` instead of `nil`, `Either` instead of `throws`, pure functions composed into pipelines. SwiftUI views stay ordinary SwiftUI.

**Import `FunctionalCore`, never `Bow` directly.** It re-exports Bow and adds the `Sendable` conformances Bow predates, plus the `attempt` helper. Declaring those conformances in two modules would be ambiguous at every use site.

**Core principle: a result is a value, not a control-flow event.** A decision you can store in state, compare in a test, and pass to the next step beats one that unwinds the stack.

## Designing with functions

Six habits, each written as something to *do* and something to *look for*. They are the design half of this skill; everything below is the mechanics of getting it past the compiler.

### 1. Start from the function, not the type

Write the signature of the transformation before you write anything that holds it: `(ApprovalRequest) -> PermissionDecision`, `(URL) -> Option<String>`, `([TranscriptEntry]) -> String`. Introduce a type only when two functions have to agree on a shape.

- **Signal you skipped this:** a `class` or `struct` whose only job is to hold two dependencies and expose one method.
- **Do instead:** a free function taking the dependency as a curried first parameter — `requireApproval(grants)` returns `(ApprovalRequest) -> …`, so callers bind the dependency once and pass the rest around.
- **In this repo:** `decidePermission(_:)`, `conversationTitle(from:)`, `placeBubble`, `admitting(name:bytes:to:)`.

### 2. Never mutate — return a new value

Every stored property in a domain type is `let`. A change is a function from old value to new value, named with `-ing`.

- **Signal:** `var` in a domain `struct`; a method returning `Void` that changes something; `array.append` inside domain logic.
- **Do instead:** `granting`, `archiving`, `attaching` — build the new collection with `map`/`filter`/`reduce` and return it.
- **In this repo:** `PermissionGrants.granting`, `WebSiteGrants.granting(host:)`, `archiving(_:into:limit:)`.
- **Exception, stated once:** the single `@Observable` store (`Secretary`) holds `var`s because SwiftUI observes them. It holds values; it does not compute inside them.

### 3. A function is data — store it, list it, pass it

Functions go in properties, arrays, dictionaries, and return positions. A table of `(name, function)` beats a `switch` whose cases keep arriving.

- **Signal:** a one-method protocol that exists only so a test can substitute it; a `switch` over a string that grows a case per feature.
- **Do instead:** a stored closure (`@ObservationIgnored let discoverSkills: ([String]) -> [SkillInfo]`), or an array of rails folded together.
- **Keep the protocol** when the boundary has several methods, identity, or lifetime — `ChatProvider`, `ConversationStoring`. One function, one closure; a real collaborator, a protocol.

```swift
// Rails as data: adding a rule is adding an element, not editing a function.
let rules: [(String, (Int) -> Either<ParseError, Int>)] = [
    ("positive", requirePositive),
    ("small", { $0 < 100 ? .right($0) : .left(.notPositive) })
]
let checked = rules.reduce(Either<ParseError, Int>.right(candidate)) { result, rule in
    result.flatMap(rule.1)^
}
```

### 4. Solve by composing, not by adding parameters

A new requirement is a new small function joined to the chain — not a `Bool` on an existing one.

- **Signal:** a parameter that switches behaviour (`includeHidden:`, `strict:`), or a function whose body is two paragraphs separated by a blank line and a comment.
- **Do instead:** two functions and a caller that picks, or one more rail in the chain: `requireAllowlistedTool >>> { $0.flatMap(requireApproval(grants))^ }`.
- **Rule of thumb:** if you can't name a function without "and", it is two functions.

### 5. Stay inside the container; unwrap once, at the edge

`map`/`flatMap` on `Option` and `Either` all the way through the domain. The unwrap belongs at the boundary that has to *act* — the view bridge, or the caller that shows a message.

- **Signal:** `.toOptional()`, `if let`, or `getOrElse` in the middle of domain code, followed by more logic on the unwrapped value.
- **Do instead:** keep mapping, and let `fold` be the last step: `webSiteHost(of: url).fold({ … }, { … })`.
- **Reminder:** `^` after every `map`/`flatMap` on these types, or the result is `Kind<…>` and won't type-check.

```swift
// One unwrap, at the end — not one per step.
let label = Option.fromOptional(rawName)
    .map { $0.trimmingCharacters(in: .whitespaces) }^
    .filter { !$0.isEmpty }^
    .getOrElse("Untitled conversation")
```

### 6. Small functions, and free ones by default

- **Small:** one reason to fail, and short enough to read without scrolling. A comment that separates two halves of a body is a request to split it.
- **Free by default:** pure logic that doesn't need the type's own invariants is a free function in the module, not a method. Methods are for behaviour about the value's own data (`grants.allows(host:)`); free functions are for decisions about a *situation* (`admitting(name:bytes:to:)`, `worthArchiving(_:)`).
- **Naming, because `SecretaryCore` imports every domain module into one scope:** qualify a public free function with its domain noun — `decidePermission`, not `decide`. Names that are already specific (`requireAllowlistedTool`) need no prefix.
- **Test the function, not the class.** If something is hard to test, it is usually because a decision is trapped inside a type that also does I/O — pull the decision out as a function and the test needs no fake.

### 7. Loops and branches are the last resort

`for` and `if` describe *how*; `map`, `filter`, `reduce`, `flatMap` and `fold` describe *what*. Reach for the second set first — but see the boundary at the end of this section, which is part of the rule, not an apology for it.

| Instead of | Write |
|---|---|
| `for x in xs { out.append(f(x)) }` | `xs.map(f)` |
| `for x in xs where p(x)` | `xs.filter(p)` |
| `for x in xs { total += x.n }` | `xs.reduce(0) { $0 + $1.n }` |
| a loop that can fail partway | `xs.traverse { … }^` — every element, or the first failure |
| `if let a = x, let b = y { f(a, b) }` | `Option<A>.map(x, y, f)^` — two containers, one function |
| `if cond { .a } else { .b }` in a body | a `switch` *expression* assigned to a `let`, or `fold` on the value you already have |
| `if let v = opt { … } else { … }` | `opt.fold({ … }, { … })` |
| `guard let` chains down a function | one chain of `.flatMap(…)^`, or `binding` past three steps |

Verified shapes (compiled in `SkillExampleTests`): `Option<Int>.map(a, b) { $0 + $1 }^` and `Either<E, Int>.map(x, y) { … }^` are the applicative pair; `xs.traverse { … }^` is the fallible loop; `Option.filter` exists and needs `^`. Two gotchas measured while writing this: **`zip` on `Option` does not work in a usable shape in 0.8.0** — use the 2-ary `map` — and the arguments to `Either.map` must be typed `Either` values, since a bare `.right(1)` there infers `Kind<EitherPartial<E>, Int>` and fails with *has no member 'right'*.

**Recursion over accumulation.** When the shape is "keep going until", write a recursive function whose parameters *are* the state, rather than a `var` and a `while`. Swift does not guarantee tail-call elimination, so keep it to bounded work — a menu, a path, a retry budget — and use `reduce` for anything that walks a whole file or a long list.

**Where this stops — do not over-engineer.** These rules are for readability, not purity. Keep the plain thing when the functional one is longer or slower to read:

- `guard` for a precondition at the top of a function is clearer than a fold; keep it.
- A single `if` that returns early from otherwise-linear code is fine.
- Plain-collection code stays plain: `list.map(f)`, not Bow's `ArrayK` routing.
- Don't build a combinator, a custom operator, or a generic protocol to remove one `if`. If the functional version needs a paragraph of explanation, the `if` was better and this section does not apply.

### 8. Flatten with `guard` — without changing what the code means

Nesting is the other way a body becomes unreadable. A function whose closing braces march to the right is one `if` wrapped around everything; invert it and the work comes back to the left margin.

- **Signal:** more than two levels of indent in a domain function; an `if` (or `if let`) whose body *is* the whole function; a run of `}` at the end that you have to count.
- **Do instead:** `guard <the good case> else { return … }`, then keep going unindented. One guard per precondition, each with its own reason to leave — that is also what makes a failure easy to name.
- **This does not contradict §5 and §7.** Inside a domain chain, keep mapping and let `fold` be the last step. `guard` is for the *preconditions* of a function — the things that must be true before the chain starts — and for edge code (adapters, delegates, view bridges) that has to act rather than transform.

**Inverting a condition is a refactor with a correctness proof attached. Walk the list before you commit it:**

| Check | Why it bites |
|---|---|
| The guard condition is the exact negation | `if !(a && b)` inverts to `guard a \|\| b`, *not* `guard a && b`. De Morgan, every time. |
| The original `else` branch, if any | `if c { X } else { Y }` is `guard c else { Y; return }` then `X` — dropping `Y` silently deletes behaviour. |
| Code *after* the old `if` block | It used to run in both cases. After a guard-return it runs in neither. Move it, or the guard is wrong. |
| The return value | A non-`Void` function has to hand back what falling through used to produce, not a fresh default. |
| Loop bodies | Inside `for`, the exit is `continue`, not `return` — a `return` leaves the whole function. |
| Optional binding scope | `if let x = …` binds inside the braces; `guard let x = …` binds *after*. Check it doesn't now shadow an outer `x` for the rest of the function. |
| `defer` and cleanup | Still runs on the guard's return. If the old code did the cleanup at the bottom of the `if` instead, it is now skipped. |
| Async and `await` | An early return before an `await` changes what has been kicked off. Read the whole body, not the condition. |

**Prove it, don't eyeball it.** Run the tests that cover the branch before and after — and if the branch had no test, write one *before* inverting, because that is the only thing separating a refactor from a change. A flattened function that returns a different value on one input is worse than the arrow it replaced.

**And don't overdo it:** a two-line `if` is already flat. Inverting it buys nothing and costs a reader one more negation to hold.

### 9. Every domain function is deterministic

Same arguments in, same value out, every time, on any machine, at any hour. A function that reads the clock, mints an id, touches the disk or asks the environment is not one function — it is a different function every time you call it, and no test pins it down.

**The four ways it leaks in, and what to do about each:**

| Source | Instead of | Write |
|---|---|---|
| The clock | `Date()` inside the body | `now: Date = Date()` as the **last** parameter — the caller passes a fixed date in tests, nobody types it in production |
| Identity | `UUID()` inside a decision | take the id as a parameter, or let the impure caller mint it and hand it in |
| The world | `FileManager`, `Process`, `ProcessInfo.environment` | keep them in the adapter; the decision receives what was read, as a value |
| Randomness | `Int.random`, `shuffled()` | pass the choice in; a domain function should not be able to surprise you twice |

This repo's idiom is the defaulted parameter, and it is already everywhere: `conversationMenuLabel(title:savedAt:now:)`, `conversationMenuRows(_:current:now:)`, `historyRows(now:)`, `tickLoop(now:)`. Call sites stay short, tests pass `Date(timeIntervalSince1970: 1_800_000_000)` and assert an exact string.

**Signals you have lost it:**

- A test that passes in the morning and fails after midnight, or one that needed `XCTAssertTrue(x.contains(…))` because the exact value couldn't be predicted.
- A function you can't call twice in a test and compare the two results.
- A parameter list that looks pure while the body says `Date()` three lines down — this is the one that hides, because the signature lies.

**How to check, in one line:** call it twice with the same arguments and assert the results are equal. If that assertion can't be written, the function isn't deterministic yet.

**Where determinism stops.** The orchestrator (`Secretary`), the adapters and the stores are impure by design — they read the disk, spawn Claude Code, and stamp `Date()`. That is their job: they gather the inputs, call the pure function, and apply the answer. Don't thread a clock through six layers to keep a log line honest, and don't invent a `Clock` protocol for one `Date` — a defaulted parameter is the whole mechanism.

## The boundary rule

Bow types live in the domain core. Swift-native types live at three edges, with an explicit conversion function at each. **This is not stylistic — `Option` in a `Codable` struct does not compile.**

| Edge | What crosses it | Conversion |
|---|---|---|
| **Persistence** | `Codable` DTO with Swift `Optional` | `toDomain` / `toDTO` free functions |
| **View** | **A SwiftUI view file must not import `FunctionalCore`** — Bow exports its own `State`, which shadows SwiftUI's `@State` and breaks every `@State var` in the file | a non-view bridge file (`AISecretaryApp/DomainBridge.swift`) that hands views `String?` / `Bool` |
| **Foundation** | `FileManager`, `Process`, `JSONDecoder` keep `throws` | `attempt { try … }`, then `mapLeft` into your module's error, once per adapter |

`@Observable` holding `Option`/`Either` works. `async` returning `Either` consumed on `@MainActor` works. Conversion members (`Project(dto)`, `project.dto`) beat free `toDomain`/`toDTO` functions, which would collide across modules.

The view rule is the one that bites hardest: the error is nine copies of `'State' is ambiguous for type lookup in this context` pointing at property wrappers you never touched.

## What Bow actually has

Verified by compiling against 0.8.0 in this repo. Getting this wrong is the most common way to waste a build cycle.

| Want | Exists | Notes |
|---|---|---|
| pipe value into function | ✅ `x \|> f` | same operator also partially applies: `3 \|> add` → `(Int) -> Int` |
| compose functions | ✅ `f >>> g`, `g <<< f`, `andThen(f, g)` | |
| curry | ✅ `curry(f)` | over *your own* 2-ary function: `curry(clamp)(10)`. Bow exports **no free `map`** — `curry(map)` is `cannot find 'map' in scope` |
| Optional → Option | ✅ `Option.fromOptional(x)` | reverse: `opt.toOptional()` |
| Result → Either | ✅ `result.toEither()` | |
| accumulate many errors | ✅ `Validated`, `ValidatedNEA` | use for multi-field validation, not first-failure |
| wrap a throwing call | ✅ `attempt { try … }` | ours, in `FunctionalCore`, over Bow's `Try.invoke().toEither()` |
| `Sendable` on Bow types | ✅ via `FunctionalCore` | Bow itself declares none — that is why the module exists |
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
public func decidePermission(_ grants: PermissionGrants) -> (ApprovalRequest) -> PermissionDecision {
    requireAllowlistedTool >>> { $0.flatMap(requireApproval(grants))^ }
}
```

Live version: `code/Sources/Permissions/`. Every snippet in this file is compiled
by `code/Tests/PermissionsTests/SkillExampleTests.swift` — change one, change both.

Worked examples of each edge, all in the repo: persistence
(`ProjectRegistry/Project.swift`, `SecretaryCore/ProfileStore.swift`), Foundation
(`ToolAdapters/GitReadOnlyAdapter.swift`), view (`AISecretaryApp/DomainBridge.swift`),
async (`LLMProvider/ChatTypes.swift`'s `ChatStream`).

**Name public free functions so they stay unambiguous across modules.**
`SecretaryCore` imports all seven domain targets into one file scope, so a bare
`decide` or `validate` collides. Qualify with the domain noun:
`decidePermission`, not `decide`. Rails whose names are already specific
(`requireAllowlistedTool`) need no prefix.

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
| `cannot find 'map' in scope` | Bow has no free `map` over `Array` | use `list.map(f)`; `curry` only your own functions |
| `'State' is ambiguous for type lookup` | a SwiftUI view imported `FunctionalCore`; Bow's `State` shadows `@State` | drop the import, go through a bridge file |
| `stored property … has non-Sendable type 'Option<…>'` | imported `Bow` directly instead of `FunctionalCore` | import `FunctionalCore` |
| `type 'Void' cannot conform to 'Equatable'` | `XCTAssertEqual(x, .right(()))` on `Either<E, Void>` | assert `x.isRight` |
| `member '…' is a function that produces expected type` | pattern-matching a Bow `Either` case like a Swift enum | `fold`, or `getOrElse` |
| a test asserts nothing and fails with `"None"` | `XCTAssertNil` on an `Option` — it wraps the `Option` in an `Optional`, which is never nil | `XCTAssertEqual(x, Option.none())` |
| `value of type 'Option<A>' has no member 'forEach'` | Bow's `Option` is not a `Sequence` | `fold({ }, { … })`, or build a list: `opt.fold({ [] }, { [$0] })` |
| new `throws` in a domain function | Foundation call not wrapped | wrap in the adapter, return `Either` |

## Checklist before committing domain code

- Every new decision is a named function with a signature you could read aloud; nothing new is a class holding two dependencies and one method.
- No `var` in a domain type, and no method returning `Void` that changes something — changes are `-ing` functions returning a new value.
- No `.toOptional()` / `if let` / `getOrElse` in the middle of a domain chain; the unwrap is the last step.
- No new `Bool` parameter that switches behaviour — that is two functions.
- No `for` where `map`/`filter`/`reduce`/`traverse` says it; no `if let`/`guard let` chain where one `flatMap` chain or a `fold` says it.
- No `Date()`, `UUID()`, `FileManager` or `random` inside a domain function — the clock arrives as `now: Date = Date()`, everything else as a value the caller already read.
- No function body wrapped in one big `if` — invert it to a `guard` and return early, and check the negation, the old `else`, the code after the block, and the return value before calling it done.
- …and none of the above turned into a combinator nobody asked for: if the functional version is harder to read, the plain one wins.
- No `throws` in a domain function; failures are on the left of `Either`.
- No `?` in a domain type; absence is `Option`. Swift `Optional` only in DTOs and view projections.
- Error enum belongs to this module and is `Equatable, Sendable`.
- State-holding types are values with `-ing` methods, not classes with `var`.
- No `XCTAssertNil`/`XCTAssertNotNil` on an `Option` — they compile and assert nothing. Use `XCTAssertEqual(x, Option.none())`.
- `swift test` passes. If an API changed, the test changed with it — a deleted assertion is not a passing test.
