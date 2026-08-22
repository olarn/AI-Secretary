# AI Secretary — the Swift package

The package lives in this `code/` directory; the repository root holds the
charter and the documents. All commands below are run from here.

This file is the **developer's guide** — how it is put together, how to build it,
how to test it, and how to drive it. For what the app does from the outside, read
[`../docs/FEATURES.md`](../docs/FEATURES.md); for why any given decision was made,
read [`../PRODUCT_BACKLOG.md`](../PRODUCT_BACKLOG.md); for the rules a session has
to follow, read [`../CLAUDE.md`](../CLAUDE.md).

SwiftPM only — there is no checked-in Xcode project, and the package opens in
Xcode directly. `Package.swift` declares Swift tools 5.9. The version is stated
in the root README and nowhere else here, because a number written twice goes
stale on one side.

## Requirements

- macOS 26 or later (`Package.swift` declares `.macOS("26.0")`)
- Swift 6.3 / Xcode 26 command line tools
- Claude Code installed and signed in with `/login`, or OpenCode on the machine

## Build, test, run

```sh
swift build
swift test
swift run AISecretaryApp   # runs the code you are about to commit, no bundle needed
./scripts/package-app.sh   # the single .app
```

`swift run AISecretaryApp` is how a change is driven before it is committed. Four
things exist only in a bundle and cannot be checked that way: the About window's
build stamp, the icon, the `Info.plist` version, and reopening by double-click —
plus anything touching `UNUserNotificationCenter`, which raises an Objective-C
exception when there is no bundle identifier (every entry point in
`CompletionNotifier` guards on that and logs `would notify — …` instead).

**Never run `package-app.sh` from a worktree.** It deletes every other
`AISecretary.app` in the repository, so the single surviving bundle ends up inside
the worktree and the root `code/` is left with none.

## Module layout

Targets are layered so each depends only on the ones below it, and **no domain
layer imports AppKit or SwiftUI**.

```
Sources/
  FunctionalCore/    Re-exports Bow, adds Sendable conformances and `attempt`.
                     The only module that imports Bow; everything below the app
                     imports this instead
  AssistantState/    State machine: states, events, guarded transitions,
                     StatusPulse, SubagentLiveness
  ProjectRegistry/   Project type, per-character JSON persistence, name
                     resolution, the shared-file migration
  Permissions/       Action classes, approval requests, grants, policy decisions
  ToolAdapters/      CodeToolAdapter, GitReadOnlyAdapter, FileReadOnlyAdapter —
                     the fallback path, used only when the chosen maker has no
                     workspace tools of its own
  LLMProvider/       ChatProvider protocol; ChatBackend; AIVendor and
                     VendorRuntime (the seam that makes a second maker possible);
                     ClaudeCodeLocator/Detector/Provider, OpenCodeProvider;
                     WarmProcess and WarmProcessKey; AnthropicStreamDecoder and
                     OpenCodeEvents (both pure and testable)
  SecretaryCore/     Orchestration, intent, prompts, audit, and ~90 small pure
                     types — every rule the app has to decide
  AISecretaryApp/    SwiftUI + AppKit: FloatingPanel, CharacterView, ChatPanelView
                     and its five extensions, CommandWindow, InfoWindows,
                     StatusBarController, AppDelegate
```

`AISecretaryApp` is an executable target and **is never linked into the test
bundle** — measured at v0.6.60, not one of its files appeared in the coverage
report at all. The rule that follows is the one the charter states: any rule the
app has to *decide* is a pure function in a library target, and the view or
delegate only applies the answer. `placeBubble`, `GripCorner`, `claimedShortcuts`,
`completionNotice`, `offeredAnswers`, `vendorConnection` and their many neighbours
are all there for that reason, and are all at or near 100%.

Coverage for the rest:

```sh
swift test --enable-code-coverage
xcrun llvm-cov report \
  .build/debug/AISecretaryPackageTests.xctest/Contents/MacOS/AISecretaryPackageTests \
  -instr-profile .build/debug/codecov/default.profdata \
  -ignore-filename-regex='(Tests|\.build)/'
```

## Style

Domain modules are written in a typed functional style on
[Bow](https://github.com/bow-swift/bow), imported through `FunctionalCore`:
failures are the left of an `Either` rather than `throws`, and absence is
`Option` rather than `?`. The rules — and the Bow 0.8.0 APIs that do and do not
exist — are in the `swift-functional-programming` skill, which is invoked before
the first Swift edit of any session.

**SwiftUI views stay ordinary SwiftUI and must not import `FunctionalCore`.** Bow
exports its own `State`, which would shadow `@State`. The boundary is crossed in
`AISecretaryApp/DomainBridge.swift`.

**No `.swift` file in this repository carries a comment.** What the code does is
said by its names, why something broke is said by the name of the test that
reproduces it, and whatever neither can hold lives in
[`../docs/design-notes/`](../docs/design-notes/), one file per target. **Read the
note for a file before changing that file**, especially before simplifying
something a note records as already tried and failed. The single exception is
`// swift-tools-version: 5.9` on line 1 of `Package.swift`, which SwiftPM parses.

## Testing

Six test targets, one per domain module. `FunctionalCore` is re-exports, and
`AISecretaryApp` is exercised by driving the app rather than by the test bundle.
The suite is run in full on every commit; no count is quoted here, because a
number in prose is a number nothing keeps true.

Tests cover state transitions, intent routing, project resolution, permission
decisions, tool invocation policies, stream decoding, prompt assembly and every
pure rule the views apply. Adapter tests create a throwaway repository per test in
the temporary directory and never touch a real checkout. Stores default to
in-memory: only `AppDelegate` points them at real files, because a suite that
forgets to override one would otherwise write into the owner's own data.

Two conventions that are load-bearing:

- **A fixture from a CLI is a line that CLI really printed.** Every message in
  `DirectoryRefusalTests`, the sub-agent stream fixtures and the OpenCode event
  fixtures was captured from a live run — including the ones that must *not*
  match, so two different refusals cannot be conflated again.
- **A test that would pass both before and after a fix is not a test.** When a
  one-line fix goes in, the line is commented out and the suite re-run to watch
  it go red before committing.

**A UI feature is not done until it has been driven in the running app.** Unit
tests over the numbers behind a view are not evidence the view works: the message
box once shipped with eight passing tests about its height while the box itself
never grew past one line, because the measurement feeding those tests was always
zero.

### Driving it

`scripts/uidrive/` holds the tools for that, with its own
[README](scripts/uidrive/README.md). **Read it before writing a new one-liner** —
each script encodes a mistake already made once, and the ungated key-posting
variants were deleted on purpose.

Two rules that have each cost a round:

- **Capture using the real window bounds from `win.swift`.** A 720pt capture was
  once taken of a window 643 high and read as "it fits" when the overflow simply
  fell outside the frame.
- **Check which process is frontmost before posting synthetic keys.** They have
  leaked into a terminal twice.

Some things cannot be driven by script at all and are known to need real hands:
`Shift+Return` (SwiftUI's `onKeyPress(.return)` does not see the shift modifier on
a synthetic event) and the window shadow behind Liquid Glass (`screencapture`
records the window's own layer, not the shadow the system draws).

## How the process boundary is held

Three separate mechanisms, often confused with each other.

**The CLI's working directory** is the real boundary. A registered project *is*
the session's working directory, and anything outside it needs `--add-dir`,
which is a launch flag — so opening a new folder restarts the process. With no
project registered, work runs in a neutral scratch directory under Application
Support rather than wherever the app happened to launch from.

**`--allowedTools` is a pre-approval list, not a restriction.** A tool left off
it still exists; it just gets refused. That distinction cost a round: the model
reached for `SendMessage` to talk to other CLI sessions and reported success,
and no wording in a prompt makes a tool sitting in front of a model stop looking
like the answer. Those tools are shut off with `--disallowedTools` instead. The
default allowlist is read-only:

```
Read, Glob, Grep, WebSearch, WebFetch,
Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git branch *)
```

`WebSearch` and `WebFetch` are in that default. They do not touch the disk, but
they do reach the network with whatever context the model includes — take them
out of `ClaudeCodeProvider.readOnlyTools` if that is not the trade you want.

**Widening is always try → refused → ask → try again.** Claude Code's
`--permission-mode manual` does not consult the host app mid-turn, it simply
refuses, so being refused *is* how the question reaches the person. Bash rules
are narrowed to the command that was actually attempted, so approving one
`npm test` does not hand over the shell.

**MCP tools are not gated by the allowlist.** An `mcp__…` tool was observed
running without a prompt; configuring a server in Claude Code is itself the
grant. Servers are read from the person's own configuration, which is per
directory, and both stdio and `127.0.0.1` servers work because the child is not
sandboxed — the app passes neither `--bare` nor `--strict-mcp-config`. The child
gets the **login shell's `PATH`**, resolved once in the background: without it a
stdio server configured as `node …/index.js` fails to start from a
Finder-launched app, because launchd's environment has no `PATH` and nvm and
Homebrew are invisible.

### The fallback adapters

`ToolAdapters` is only reached when the chosen maker has no workspace tools of
its own, but it is still the only place in the package that launches an external
process, and it is constrained by construction rather than by checks:

- `git` is launched by absolute path (`/usr/bin/git`), never resolved via `PATH`.
- Arguments go to `Process` as an array, so no shell is involved and there is no
  quoting or injection surface.
- The argument vectors are hardcoded per operation. Typed text selects an
  operation; it never becomes part of a command line.
- The working directory comes only from a registered project, verified to exist
  and to contain a `.git` entry — which in a worktree is a *file*, not a folder.
- The subprocess gets a minimal environment
  (`environmentWithNothingInheritedThatCouldRedirectGit`), a 15-second timeout
  and a 128 KB output cap.

The file adapter runs no process at all: it resolves the requested path against
the project root, resolves symlinks, and refuses anything landing outside the
root before reading.

### One thread, and what stays in it

Commands and conversation share a single thread, so asking a follow-up about
something a command produced works. The provider sends only the latest user
message and lets the CLI hold the thread with `--resume`; the app's own
`conversation` array is its ledger, and anything the model needs to *see* has to
travel with a turn. Three bugs of exactly that shape have been fixed, the
plainest being a character answering "there's nothing to summarise yet" about
answers printed in her own chat.

A file read on the fallback path stays in the conversation and travels with
every later message, which is what makes "what does this mean?" work; the
approval prompt says so. The caps are all in bytes, declared together in
`Secretary.swift`: 4,000 for command output and listings, 16,000 for file
contents, 60,000 for a file sent to be understood, and the conversation itself
trimmed oldest-first past 200,000.

## Where things are stored

Outside the repository, in `~/Library/Application Support/AISecretary/`:

| File | What |
|---|---|
| `profiles.json` | The characters |
| `projects-<uuid>.json` | The registered folders, per character |
| `permissions-<uuid>.json` | Standing grants only — session grants cannot reach disk |
| `conversations-<uuid>.json` | Chat history, up to 10 per character |
| `Profiles/<uuid>/picture.png` | Her picture |
| `scratch/` | Where a turn with no project open runs |

`projects.json` without a uuid is the pre-Sprint-13 shared file; it is migrated
once, by rename, to whichever character is created first.

Appearance, model, effort and vendor live in `UserDefaults`, namespaced per
character (`appearance.<uuid>.*`, `assistant.<uuid>.*`), each key falling back to
the app-wide key one value at a time until she has one of her own. Note that the
dev binary and the packaged app use **different defaults domains**
(`AISecretaryApp` and `com.aisecretary.app`), so a position remembered while
driving does not carry into the bundle.

## Versioning and packaging

`major.sprint.change`, declared once in `SecretaryCore/AppVersion.swift`. The
About window and `package-app.sh` both read that value; `VersionInSyncTests` fails
if the root README's copy disagrees, and another test fails if the
`AppVersion(...)` declaration is wrapped across lines, because the script parses
it with a single-line `sed`.

`package-app.sh` deletes every other `AISecretary.app` in the repository, stamps
the bundle with the commit and branch it was built from (`AISecretaryBuild`, shown
in About), sets `CFBundleVersion` from the change digit — which only ever
increases, so macOS can tell one build from the next — and generates the icon from
the committed `../docs/Noti-Icon.png` (override with `ICON_SRC`).

## Known limitations

- OpenCode does not pass through the approval cards at all; the only boundary is
  the working directory it is given.
- `selectedSkills` is session-scoped and forgotten when the app closes.
- The header badge still shows an effort under OpenCode, which has none.
- `prefers-reduced-motion` is not read.
- The build is not sandboxed and is only ad-hoc signed; a distributable build
  would need a Developer ID, notarization and user-selected-file entitlements.
- A full build emits four `@Sendable`/`withLock` warnings, all of which predate
  the clean-code sweep.

The full list, with the ones that are deliberate, is in
[`../docs/FEATURES.md`](../docs/FEATURES.md).
