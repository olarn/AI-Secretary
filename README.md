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
  ToolAdapters/      CodeToolAdapter protocol, GitReadOnlyAdapter
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
