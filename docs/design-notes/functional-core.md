# FunctionalCore

## Why the `@unchecked Sendable` conformances are sound

Bow 0.8.0 predates `Sendable`, so none of its data types declare it. Storing an
`Option` in a `Sendable` struct warns today and fails to compile under the
Swift 6 language mode.

The conformances declared here are sound rather than convenient: `Option`,
`Either`, `Try` and `Validated` are plain enums over their type parameters with
no shared mutable state, so a value is safe to hand across isolation domains
exactly when its payload is — which is what the `where` clauses say.
`@unchecked` is required only because the compiler cannot verify that for a type
declared in another module.

## Why every target imports this module and never Bow directly

The conformances are declared once. Two modules each declaring them would be an
ambiguity at every use site.

## What `attempt` is for

`FileManager`, `JSONDecoder`, `Process` and friends keep throwing — that is
their API and it is not ours to change. Every domain module converts at its own
boundary by calling `attempt`, so `try` appears once per adapter instead of
spreading `do`/`catch` through the logic. Callers should immediately `mapLeft`
the untyped `Error` into their own module's error enum, so the leaked `Error`
never reaches a public signature.
