# AI Secretary

A macOS desktop companion, built in the sprints described in
`../initial-implementation-prompt.md` and governed by `../CLAUDE.md`.

The Swift package lives in this `code/` directory; the repository root holds
the project charter and documents. All commands below are run from here.

**Sprint 1 — Desktop companion shell (done).** A floating, transparent,
always-on-top character window that is draggable, opens a manga-style speech
bubble on click, and reflects a fully unit-tested assistant state machine.

**Sprint 2 — Secretary and coding workflow (first slice done).** Typing a
request now drives real work: the Secretary classifies the intent, resolves an
explicitly registered project, asks for approval, and runs a fixed set of
read-only Git commands, reporting the result back in the transcript.

**Sprint 3 — Chat with me (done).** Typing anything that isn't a command
streams a real reply through the character.

**Backend — your own Claude Code.** The app is a face over the Claude Code you
already have. On launch it looks for the `claude` binary; if it's there, work
runs through it on your own account and subscription, and no API key is
involved. That also means the assistant has Claude Code's real abilities —
editing files, running commands, web search, subagents, skills, MCP — instead
of the handful of tools this app could implement itself. If Claude Code isn't
installed, the panel explains how to set it up, and an Anthropic API key set in
Settings is used as a fallback.

**Sprint 4 — File & folder access (superseded).** The bundled Git and file
adapters still exist and still back the typed commands below, but Claude Code's
own tools now do this work in normal conversation.

### Who she is

The assistant ships as **Miku**, 17, and her name is what labels her replies in
the panel. The character is a value (`SecretaryPersona`), not literals sprinkled
through the prompt, and it's `Codable` — the plan is for the user to supply
their own: upload a picture, confirm the gender the app guesses, pick a name.
Only the built-in default exists today.

The personality is written to add warmth without costing usefulness: the prompt
still asks for the answer first and no padding. Asked "2+2", she answers "4".

### Chatting

Type anything that isn't a Git command, in your own words. The reply streams
token-by-token, and the character walks IDLE → THINKING (while the model
reasons) → WORKING (as text arrives) → SUCCESS/ERROR.

With Claude Code installed there is nothing to configure — it runs on the
account you already signed in to. Without it, set an Anthropic **API** key
(billed separately from any Claude subscription, at
[console.anthropic.com](https://console.anthropic.com)) in **Settings**.

Slash commands, handled locally with no network call:

| Command | Effect |
|---|---|
| `/model <id>` | Switch model — full IDs, or `opus`/`sonnet`/`fable`/`haiku` |
| `/model default` | Go back to your own Claude Code setting |
| `/effort <low\|medium\|high\|xhigh\|max>` | Adjust reasoning depth |
| `/effort default` | Go back to your own Claude Code setting |

**Model and effort are inherited, not imposed.** Out of the box the app passes
neither `--model` nor `--effort`, so a turn runs on whatever your Claude Code is
already configured to use — if your `~/.claude/settings.json` says `opus`, you
get Opus. Pick one here only if you want to override it for this app.

**Settings** shows the model and effort by name either way — the inherited value
is read from your Claude Code settings and confirmed by what a live session
reports, so it says "Claude Opus 5", not "your default". A dashed dot marks a
value the app didn't choose. Click either one for a picker; choosing takes
effect immediately and is announced in the conversation, the same as the slash
commands.

### Seeing what it's doing

While a turn is running, what the assistant is doing appears **in the
conversation**, in order, just before the answer it led to — `◇ Thinking`,
`▸ Read: about.md`, `▸ WebSearch: …`, `▸ Bash: git status`. It's drawn as a
dashed, dimmer box so it never reads as part of the reply, and each turn keeps
its own box, so scrolling back shows how an earlier answer was reached.

**Hidden until you ask for it.** Click the status badge on the character to
show it, and again to hide it; the choice is remembered across launches. The
change is announced in the conversation, and switching it off clears the boxes
already there.

This is activity, not reasoning. Claude Code streams thinking blocks whose text
is **empty**: `thinking.display` defaults to `omitted` on the Opus 5 family, the
raw chain of thought is never returned for those models, and no CLI flag
changes it. So the thought itself cannot be shown — which tool it reached for,
and with what, can.

### Tables in replies

Pipe tables are laid out as a grid rather than shown as raw pipes, with
`**bold**` and `` `code` `` rendered inside the cells. A table wider than the
bubble **scrolls sideways on its own** — the conversation doesn't move with it,
so a wide answer can't drag the whole thread off-screen.

Detection requires a separator row (`|---|---|`), so ordinary prose containing a
pipe — `ls | grep foo` — is left as prose. Rows that don't match the header are
padded or trimmed rather than dropped: generated markdown is often ragged and
losing a cell is worse than an empty one.

### Scrolling while it types

The transcript follows new output only while you're already at the bottom.
Scroll up to read something and it stops following, so a streaming reply can't
yank the view out from under you; scroll back down and it picks up again.
Sending a message always brings you back to the bottom. It follows streamed
text, not just new messages, so a long answer stays in view as it arrives.

Position measurements are ignored for a moment after the app scrolls itself. A
scroll view can't tell who moved it, and an app-driven scroll reads as
"at the bottom" the whole way down — without that pause, scrolling up during a
reply would be undone by the next token.

### Continuity between commands and chat

Commands and conversation share one thread. Running `list files in X` and then
asking "how many .md files?" works: the request and its output are written into
the conversation the model sees, so it can answer instead of asking again. Git
output and listings are capped at 4 KB each, file contents at 16 KB, and the
whole conversation is trimmed oldest-first past 200 KB.

**This includes file contents.** A file you `read` stays in the conversation and
travels with every later message in the session, which is what makes "what does
this mean?" work. The approval prompt for a read says so explicitly. If you want
a file analysed without it joining the history, use `summarize <path>` — that
sends it once, for that answer only.

The Secretary also remembers the last project it worked in, so follow-up
commands don't need `in <project>` repeated. An explicit name that matches
nothing is still an error, never silently redirected to the remembered project.

## Requirements

- macOS 26 or later (`Package.swift` declares `.macOS("26.0")`)
- Swift 6.3 / Xcode 26 command line tools
- Claude Code, installed and signed in with `/login`

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

### MCP servers

Nothing to configure here. MCP servers are read from your own Claude Code
configuration, and that configuration is per directory — a server set up for a
folder is available whenever the app is working in that folder, because the
registered project *is* the session's working directory.

Local and localhost servers work: the child process isn't sandboxed, so a stdio
server or one listening on `127.0.0.1` behaves exactly as it does in your
terminal. The app passes neither `--bare` nor `--strict-mcp-config`, so
discovery is left alone.

Two things worth knowing:

- The child gets your **login shell's `PATH`**, resolved once in the background.
  Without it a stdio server configured as `node …/index.js` fails to start from
  a Finder-launched app, because launchd's environment has no `PATH` and nvm,
  Homebrew and friends are invisible.
- **MCP tools are not gated by the read-only allowlist.** Observed: an
  `mcp__…` tool ran without prompting. Configuring a server in Claude Code is
  itself the grant; if you want a confirmation step for those, they'd have to be
  denied by default and routed through the same widen prompt as `Write`.

### Projects and approval

Work only ever runs inside a project you registered, via **Projects → Add
project…**, which opens a folder picker. A path is never inferred from typed
text: an unregistered name is reported as not found, and an ambiguous one asks
you to pick.

The registered folder is the Claude Code process's working directory, which is
what actually bounds what it can reach. The first message in each project asks
before anything runs, naming the project and saying that work happens on your
own Claude Code account. Approving is **remembered for that project** and
persisted — asking before every message would make the assistant unusable — so
the prompt is explicit about what the grant covers.

With no project registered (or several registered and none chosen yet), work
runs in a neutral scratch directory under Application Support rather than
wherever the app happened to launch from.

The first time a project is used for the built-in Git/file commands, the
assistant still asks and shows the exact command.

#### What Claude Code is allowed to do

Tools are pre-approved per turn with `--allowedTools`. The default set is
read-only: `Read`, `Glob`, `Grep`, `WebSearch`, `WebFetch`, and `Bash` limited
to `git status`/`diff`/`log`/`branch`. Anything outside that — writing a file,
running an arbitrary command — is refused by Claude Code, which reports the
refusal rather than doing it.

When Claude Code is refused something, the assistant notices and offers to
allow it: it says what was blocked (`Write: /path/to/file`, `Bash: npm test`),
and approving retries the same request with that rule added. This is the only
loop available — Claude Code's `--permission-mode manual` does not ask the host
app mid-turn, it just refuses — so widening is always try → refused → ask → try
again.

A widening grant lasts for **the session only** and is never written to disk.
Read access to a project persists across launches; permission to change files
starts closed every time you open the app. Bash rules are narrowed to the
command that was actually attempted, so approving one `npm test` does not hand
over the shell.

One honest caveat:

- **`WebSearch`/`WebFetch` are in the read-only default.** They don't touch
  your disk, but they do reach the network with whatever context the model
  includes. Remove them from `ClaudeCodeProvider.readOnlyTools` if that's not
  the trade you want.

Observed on this machine, a `permissions.allow` rule in the user's own
`~/.claude/settings.local.json` did **not** grant a tool we left out of
`--allowedTools` — the launch-time allowlist governed. That was one test with
one configuration, not a guarantee about every Claude Code setup.

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
  FunctionalCore/    Re-exports Bow, adds Sendable conformances + `attempt`.
                     The only module that imports Bow; everything below the
                     app imports this instead
  AssistantState/    State machine: states, events, guarded transitions
  ProjectRegistry/   Project type, JSON persistence, name resolution
  Permissions/       Action classes, approval requests, policy decisions
  ToolAdapters/      CodeToolAdapter + GitReadOnlyAdapter,
                     FileToolAdapter + FileReadOnlyAdapter (bound-checked)
  LLMProvider/       ChatProvider protocol; ChatBackend (picks a backend),
                     ClaudeCodeLocator + ClaudeCodeProvider (drives the user's
                     own Claude Code — the app has no API-key path of its own),
                     AnthropicStreamDecoder (pure, testable)
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
outside the root before reading.

Two consequences of the approve-once model are worth stating plainly, because
they are chosen rather than accidental:

- Once `file.readOnly` is approved for a project, any text file in it can be
  read without re-prompting — the same model as Git, applied to a
  higher-stakes capability.
- A file you read joins the conversation, so it is sent to Claude with your
  next chat message. That is what makes follow-up questions work, and the read
  approval prompt discloses it. Don't `read` a file you wouldn't send; use
  `list` to look around, and `summarize` when you want an answer about a file
  without keeping it in history.

The model is told which projects are registered — names only. Paths, tool
allowlists and approval state never enter chat history.

Read-only work is the only class that can run without re-prompting, and only
after the project has been approved once. `summarize`/`explain`/`analyze` are
deliberately *not* read-only — it is `externalNetwork`, so it asks every time, and a prior
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

Finish Sprint 4 by adding the internet half: a fetch/search adapter in the same
`externalNetwork` class, so a page can be pulled and reasoned about alongside a
local file. After that, either Sprint 5 (settings, font and window size, sticky
autoscroll) or giving Claude tool-use access so it can choose these operations
itself instead of relying on the keyword grammar.
