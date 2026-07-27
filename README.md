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

**Phase 4 — Access files and understand them (in progress).** The Secretary can
list a directory or read a text file inside a registered project, through the
same approval-gated pipeline as Git. Paths are always project-relative and
verified to stay inside the project root — `..`, absolute paths, and symlinks
that point outside are refused before anything is read.

It can also *understand* a file: `summarize`, `explain`, `analyze`, `review` or
`describe` a path, and the file's contents are sent to Claude for an answer.
Because that takes data off the machine it is classed `externalNetwork`, not
read-only: it asks every single time and names the destination model in the
prompt. Approving "read files here" never becomes permission to upload them.

Still open in Phase 4: pulling data from the internet to work alongside local
files. The file access is a native adapter rather than an MCP server — MCP would
add a process and protocol boundary around a capability the app already has, so
it is deferred until there is an integration that actually needs it.

Not built yet: giving Claude tool-use access to run project tools by itself, web
search, settings/appearance (Phase 5), voice, MCP integrations, and any action
that writes, deletes, installs, or changes Git history.

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

### Continuity between commands and chat

Commands and conversation share one thread. Running `list files in X` and then
asking "how many .md files?" works: the request and its output are written into
the conversation the model sees, so it can answer instead of asking again. Git
output and directory listings are carried in full (capped at 4 KB each, and the
whole conversation is trimmed oldest-first past 200 KB).

File **contents** are the exception. `read <path>` shows the file on screen and
leaves only a marker in the model's context — approving a local read must never
become an upload one turn later. To let the model reason about a file, use
`summarize <path>`, which asks first.

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
icon, and no visible menu bar — it lives in the floating character and a menu
bar item (✨) whose menu can open the chat, show/hide the character, and
**Quit**. Copy it to `/Applications` to keep it around.

An invisible main menu is still installed so the standard shortcuts work while
the app is active (i.e. with the chat bubble focused): **⌘Q** to quit, plus
⌘Z/⌘X/⌘C/⌘V/⌘A in the chat field. When only the character is on screen the app
is not the frontmost application — the character panel is deliberately
non-activating — so ⌘Q then belongs to whatever app *is* frontmost, exactly
like any other menu-bar utility. Quit from the ✨ menu always works.

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

And it can read a file and tell you about it. These **send the file's contents
to Claude**, so they ask permission every time — the prompt turns red and names
the model:

| Say | Does |
|---|---|
| `summarize <path>` | What the file is for and its main parts |
| `explain <path>` / `what does <path> do` | How it works, for someone new to it |
| `analyze <path>` | Structure, risks, anything surprising |
| `review <path>` | Concrete suggested improvements |
| `describe <path>` | A brief description of the contents |

These verbs only trigger on something that looks like a path, so "explain how
actors work" stays an ordinary conversation. Files are capped at 60 KB on this
path (lower than the local read cap — bytes on the wire cost money), the
contents are wrapped in `<file>` tags and declared untrusted data to the model,
and the bytes are sent once rather than being kept in the conversation history
and re-sent on every later turn.

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
after the project has been approved once. Understanding a file is deliberately
*not* read-only — it is `externalNetwork`, so it asks every time, and a prior
read-only approval for the same project and tool does not authorise it. The
remaining classes (local-write, destructive, Git-history-changing,
dependency-installing) are defined to require approval each time; none is
implemented yet.

## Known limitations

- Intent classification is keyword-based, not a model call; phrasings outside
  the table are reported as not understood.
- Approvals are remembered per run, not persisted across launches.
- Transcript, conversation and audit trail are in memory only — quitting the app
  starts a fresh thread.
- The build is not sandboxed yet; a distributable build would need
  user-selected-file entitlements.
- No Claude Code adapter, web search, voice, or MCP integrations yet.

## Suggested next step

Finish Phase 4 by adding the internet half: a fetch/search adapter in the same
`externalNetwork` class, so a page can be pulled and reasoned about alongside a
local file. After that, either Phase 5 (settings, font and window size, sticky
autoscroll) or giving Claude tool-use access so it can choose these operations
itself instead of relying on the keyword grammar.
