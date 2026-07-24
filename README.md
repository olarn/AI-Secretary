# AI Secretary

A macOS desktop companion, built in the phases described in
`initial-implementation-prompt.md` and governed by `CLAUDE.md`.

**Phase 1 — Desktop companion shell (done).** A floating, transparent,
always-on-top character window that is draggable, opens a manga-style speech
bubble on click, and reflects a fully unit-tested assistant state machine.

**Phase 2 — Secretary and coding workflow (first slice done).** Typing a
request now drives real work: the Secretary classifies the intent, resolves an
explicitly registered project, asks for approval, and runs a fixed set of
read-only Git commands, reporting the result back in the transcript.

**Phase 3 — Chat with me (done).** Any message that isn't a Git command or a
slash command streams a real reply from the Claude API through the character.
The API key lives only in the macOS Keychain (set it in Settings); the default
model is `claude-sonnet-5` at `medium` effort, switchable in-chat with `/model`
and `/effort`. Chat is a conversation only — the model is not given tool access
to the Git adapter.

**Phase 4 — File & folder access (read-only, done).** The Secretary can now
list a directory or read a text file inside a registered project, through the
same approval-gated pipeline as Git. Paths are always project-relative and
verified to stay inside the project root — `..`, absolute paths, and symlinks
that point outside are refused before anything is read.

Not built yet: giving Claude tool-use access to run project tools, web search,
voice, MCP integrations, and any action that writes, deletes, installs, or
changes Git history.

### Chatting

Type anything that isn't a Git command. The reply streams token-by-token, and
the character walks IDLE → THINKING (while the model reasons) → WORKING (as text
arrives) → SUCCESS/ERROR. Set your Anthropic **API** key (billed separately from
any Claude subscription, at [console.anthropic.com](https://console.anthropic.com))
in **Settings** first. Slash commands, handled locally with no network call:

| Command | Effect |
|---|---|
| `/model <id>` | Switch chat model (allowlisted IDs only) |
| `/effort <low\|medium\|high\|xhigh\|max>` | Adjust reasoning depth |

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

### Run from Finder (no Terminal window)

`swift run` keeps a Terminal window open. To get a normal double-clickable app
instead, package it into a proper `.app` bundle:

```sh
./scripts/package-app.sh        # produces ./AISecretary.app (release build)
open AISecretary.app            # or just double-click it in Finder
```

The bundle is marked `LSUIElement`, so it launches with no Terminal, no Dock
icon, and no main menu — it lives in the floating character and a menu bar
item (✨) whose menu can open the chat, show/hide the character, and **Quit**.
Copy it to `/Applications` to keep it around.

Its Finder icon is generated at package time from your local character image
(`~/Library/Application Support/AISecretary/character.png`), aspect-fit onto a
transparent square — so the licensed art is never committed to the repo. Point
it elsewhere with `ICON_SRC=/path/to/image.png ./scripts/package-app.sh`; if no
image is found it simply builds without a custom icon.

A floating character appears near the bottom-right of the screen. It is
draggable, and clicking it toggles a speech bubble containing the conversation
panel. The bubble follows the character and flips horizontally or vertically so
it never runs off a screen edge.

### Asking for something

Type a request into the field. The Secretary understands a small, fixed set of
read-only Git operations:

| Say | Runs |
|---|---|
| `status` | `git status --porcelain=v1 --branch` |
| `diff` | `git diff --stat` |
| `branch` | `git branch --show-current` |
| `log` | `git log --oneline -n 20` |

It also reads files in a registered project (read-only):

| Say | Does |
|---|---|
| `list [path]` | List a directory (root if no path), e.g. `list src in AI-Secretary` |
| `read <path>` | Show a UTF-8 text file, e.g. `read README.md in AI-Secretary` |

Paths are project-relative and bound-checked: anything resolving outside the
project root (via `..`, an absolute path, or a symlink) is refused, binary
files are declined rather than dumped, and reads are size-capped.

Add `in <project>` to choose a project, e.g. `status in AI-Secretary`. Type
`help` for the same summary in-app. Anything not clearly matching an operation
is reported as not understood — the assistant never invents a command.

### Projects and approval

Work only ever runs inside a project you registered, via **Projects → Add
project…**, which opens a folder picker. A path is never inferred from typed
text: an unregistered name is reported as not found, and an ambiguous one asks
you to pick.

The first time a project is used, the assistant asks before running anything
and shows the exact command. Approving remembers that project/tool pair for the
session; anything that is not read-only would ask every time.

The registry lives outside the repo, next to the character image:

```
~/Library/Application Support/AISecretary/projects.json
```

### Debug panel

**Debug** reveals the original buttons that drive the state machine directly,
independent of the Secretary, for exercising transitions by hand:

```
IDLE -> LISTENING -> THINKING -> WORKING -> SUCCESS | ERROR -> IDLE
```

Invalid transitions (e.g. IDLE straight to WORKING) are rejected and shown in
red rather than silently applied.

## Custom character art

The built-in avatar is original placeholder vector art (no licensed
characters). To use your own image locally, drop a PNG at:

```
~/Library/Application Support/AISecretary/character.png
```

`CharacterView` loads it automatically if present, otherwise falls back to
the placeholder. This path is outside the repo and never committed — it's
the intended way to use a personal/licensed asset (e.g. official character
art you own) without distributing it via version control.

## Test

```sh
swift test
```

Covers state transitions, project resolution, permission decisions, intent
routing, Secretary orchestration, and the Git adapter's allowlist. The adapter
tests create a throwaway repository per test in the temporary directory and
never touch your own checkouts.

## Module layout

Targets are layered so each depends only on the ones below it, and none of the
domain layers import AppKit or SwiftUI:

```
Sources/
  AssistantState/    State machine: states, events, guarded transitions
  ProjectRegistry/   Project type, JSON persistence, name resolution
  Permissions/       Action classes, approval requests, policy decisions
  ToolAdapters/      CodeToolAdapter + GitReadOnlyAdapter,
                     FileToolAdapter + FileReadOnlyAdapter (bound-checked)
  LLMProvider/       ChatProvider protocol, ClaudeChatProvider (SSE),
                     AnthropicStreamDecoder (pure, testable)
  Credentials/       CredentialStore + Keychain-backed API-key storage
  SecretaryCore/     Intent classification, chat routing, orchestration, audit
  AISecretaryApp/    SwiftUI + AppKit: FloatingPanel, CharacterView,
                     ChatPanelView, ProjectPicker, AppDelegate
```

## Security model

The Git adapter is the only place that runs an external process, and it is
constrained by construction:

- `git` is launched by absolute path (`/usr/bin/git`), never resolved via `PATH`.
- Arguments are passed to `Process` as an array; no shell is involved, so there
  is no quoting or injection surface.
- Argument vectors are hardcoded per operation. Typed text selects an
  operation — it never becomes part of a command line.
- The working directory comes only from a registered project, verified to exist
  and to contain a `.git` entry before launching.
- The subprocess gets a minimal environment, a 15s timeout, and an output cap.
- Every step is recorded in an audit trail correlated by task ID: request,
  intent, project, approval decision, execution, and result.

The file adapter runs no external process at all: it resolves the requested
path against the project root, resolves symlinks, and refuses anything landing
outside the root before reading. Note that once `file.readOnly` is approved for
a project, any text file in it (including `.env` or checked-in secrets) can be
read without re-prompting — the same approve-once model as Git, applied to a
higher-stakes capability.

Read-only work is the only class that can run without re-prompting, and only
after the project has been approved once. Every other action class
(local-write, destructive, Git-history-changing, dependency-installing,
external-network) is defined to require approval each time; none is implemented
yet.

## Known limitations

- Intent classification is keyword-based, not a model call; phrasings outside
  the table are reported as not understood.
- Approvals are remembered per run, not persisted across launches.
- Transcript and audit trail are in memory only.
- The build is not sandboxed yet; a distributable build would need
  user-selected-file entitlements.
- No Claude Code adapter, web search, voice, or MCP integrations yet.

## Suggested next step

Extend the same approval-gated pipeline to a `ClaudeCodeAdapter` for genuine
coding tasks, starting read-only (inspect and summarise a codebase) before any
operation that writes files, so the permission model is exercised end-to-end
before anything can modify a project.
