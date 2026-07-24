# AI Secretary — Phase 1 (Desktop Companion Shell)

This is the Phase 1 vertical slice described in `initial-implementation-prompt.md`
and governed by `CLAUDE.md`: a floating, transparent, always-on-top macOS
character window with a placeholder representation, a draggable panel, a
mock chat/task console, and a fully unit-tested assistant state machine.

No real Secretary orchestration, project registry, permission policy, Claude
Code invocation, web search, or network access exists yet — those are Phase 2+
and are represented only as seams/module boundaries for now.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ / Xcode 15+ command line tools

## Build

```sh
swift build
```

## Run

```sh
swift run AISecretaryApp
```

A small floating circular character appears near the bottom-right of the
screen. It is draggable (drag anywhere on its background). Click it to toggle
a "Mock Console" panel that lets you manually walk the assistant through its
state machine:

```
IDLE -> LISTENING -> THINKING -> WORKING -> SUCCESS | ERROR -> IDLE
```

Each button in the console submits an event to `AssistantStateMachine`.
Invalid transitions (e.g. jumping straight from IDLE to WORKING) are rejected
and shown in red; valid transitions are appended to the visible history log
with their reason, timestamp, task ID, and tool status.

## Test

```sh
swift test
```

Covers the pure transition table (`AssistantStateReducer`) and the stateful
wrapper (`AssistantStateMachine`), including rejection of invalid transitions
and active-task-ID lifecycle.

## Module layout

```
Sources/
  AssistantState/        Pure, UI-agnostic state machine (library target)
  AISecretaryApp/         SwiftUI + AppKit app: FloatingPanel (NSPanel),
                          CharacterView, ChatPanelView, AppDelegate
Tests/
  AssistantStateTests/    Unit tests for the state machine module
```

`AssistantState` has no dependency on AppKit/SwiftUI or Foundation networking,
so it can be reused by a future Secretary orchestration layer without pulling
in UI code.

## Known limitations

- Character art is a placeholder (SF Symbol in a colored circle), not final
  production art.
- Chat panel exposes every transition as a manual button for demonstration;
  there is no real intent interpretation.
- No persistence — state and history reset when the app quits.
- No Secretary, project registry, permission policy, or tool adapters yet;
  these are intentionally out of scope for this slice per
  `initial-implementation-prompt.md`.

## Suggested next step

Phase 2: introduce the `Project` registry type, an approval-gated
`Permissions` module, and a `ClaudeCodeAdapter` protocol with a mock/no-op
implementation — wired into the same `AssistantStateMachine` so a real task
request drives THINKING → WORKING → SUCCESS/ERROR through an approval prompt
instead of manual buttons.
