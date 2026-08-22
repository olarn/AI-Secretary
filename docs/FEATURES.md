# What the app does today

**State of the product at v0.23.365** (`code/Sources/SecretaryCore/AppVersion.swift`),
2026-08-22, on `main` at `e1d4c95`.

This is the standing answer to "what can it do, and what happens when I use it" —
written from the code as it stands, with `PRODUCT_BACKLOG.md` used for the reasons
behind each decision. The backlog is a **changelog**: it records every round in the
order it happened, including rounds that were later replaced. This file records only
what is true now, so where the two disagree, this one is describing the product and
the backlog is describing its history. Superseded entries are listed at the end so
that a reader of the backlog knows which ones not to trust.

To re-derive it: read the version above, read `PRODUCT_BACKLOG.md` from the last
heading backwards, and check each claim against `code/Sources`. Version numbers in
brackets say when a behaviour landed, so any line here can be traced back.

- **Sprints 1–23 have shipped.** Sprint 24 (Codex) has not started.
- Ships as one `.app`, macOS 26+, built by `code/scripts/package-app.sh`.
- The app holds no credentials of its own. It drives an AI CLI that is already
  installed and signed in on the machine.

---

## 1. The desktop character

| | |
|---|---|
| Window | Transparent, always on top, borderless, draggable, may stand over the Dock |
| Sizes | Character size S / M / L, per character (0.13.216) |
| Position | Remembered across launches per character; falls back to the default spot if the screen it was on is gone, rather than being clamped to an edge (0.20.313) |
| State | A halo ring and a status badge; both pulse together while `thinking` / `working` and are completely still otherwise (0.14.259–260) |
| Picture | One image per profile, shown in the bubble; new characters start from the app icon (0.20.315) |

Clicking the character opens or closes her chat bubble — the first click counts, it
is not eaten as a window-focus click.

**Several characters at once.** Every profile in the library is a character standing
on the desktop, each with her own chat, her own projects, her own settings, her own
permission grants and her own AI session. `New Character…` creates one from the
default profile (named `Secretary 2`, `Secretary 3`, …), not a clone of whoever is
focused (0.20.313).

**Getting them out of the way.**

- `Esc` is a ladder decided in one place: pinned pane → chat → character (0.13.223,
  fixed 0.17.279). It is claimed system-wide only while something is actually on
  screen to dismiss.
- `⌘H` hides the whole app — every character, every chat, every pinned pane, the
  Token Usage window. Reopening restores exactly what `⌘H` took, not what `Esc`
  hid. It is matched on key *position*, so it works on a Thai keyboard layout
  (0.17.280).
- `Hide All` / `Show All` in the status menu, decided by what is actually on screen
  rather than by a remembered flag. `Show All` brings back the chats that were open
  when they were hidden, and only those (0.14.245–246).

---

## 2. Chat

**The conversation.** Streaming replies with continuous context. Markdown is
rendered: real tables (scrolling sideways inside the table only), code blocks
(monospace, no wrapping, scrolling sideways inside the block only), and clickable
links limited to `http`, `https` and `mailto` — every other scheme renders as inert
text, because model output is untrusted.

**The message box.** Word-wraps and grows from 1 to 10 lines, then scrolls. `Enter`
sends; `Shift+Enter` and `Option+Enter` break the line **at the caret** (0.14.264–265).
`↑` / `↓` recall what was sent earlier in the session, and going past the bottom
returns the draft that was being typed.

**Who owns the arrow keys** is decided in `ArrowKeyOwner`, in one place: an empty
box with a picker on screen gives them to the picker; typing anything hands them
back to history; a multi-line draft gives them to the caret and nobody may take
them. The hint under a picker says who owns them right now.

**Scrolling.** Auto-follows while at the bottom, stops following the moment the
reader scrolls up. Following is decided from the measured position of the end of the
content, not from a signature of the messages, so an activity box growing mid-turn
cannot push the latest reply off the bottom (0.13.225).

**Attachments.** Drop a file **anywhere in the window** — a drop area appears above
the message box while dragging and says whether there is room (0.14.263). Or the
📎 button, or the model asking for one with an ` ```attach ` block. Files are
**copied**, not referenced, so the whole source folder is never opened to the
backend, and the copy is a snapshot. `.md`, `.csv`, JSON, key:value and text-bearing
images are understood; an unknown extension is accepted if its first 4KB is UTF-8
with no NUL, and refused with a reason otherwise.

**Pasted data reads as data.** Pipe tables, CSV, TSV and semicolon-delimited text are
rendered as tables — with guards so that "ไปตลาด, แล้วกลับบ้าน" and `total 1,250 THB`
are not mistaken for two-column data.

**Resizing.** Drag the grip, which sits at the corner the box actually grows from,
or step the width with the `←|→` / `→|←` buttons. The tail stays pinned to the
character; the box grows away from her and flips below her only when there is
genuinely room below.

**Header badges.** Model and effort beside her name (`Miku (Opus 5 | medium)`),
plus live badges for a running loop ⏱, a folder watch 👁, an instruction run, a
sub-agent, and the queue — each one clickable to stop what it reports.

**Panels.** One opens at a time, capped at a proportion of the window height and
scrolling inside itself, so adding a row can never make a panel overflow the window.

| Panel | Rows |
|---|---|
| Settings — *how the app looks* | Theme, Liquid Glass, Character size, Text size, Chat height, Font |
| Profile — *who is answering* | Name, Gender, Age, Personality, Picture, AI, CLI Path, Model, Effort |
| Projects — *what she may read* | Registered folders, Read my browser |
| Skills | The skills found on this machine, tickable per session |

Text size also moves with `⌘+` / `⌘−` and applies to the buttons and the message box,
not only the transcript. Font is one of four system designs (System / Rounded /
Serif / Mono) rather than a family list, because half of the installed families have
no Thai glyphs (0.13.228). Code blocks stay monospace whatever is chosen.

**Chat history.** Up to 10 past conversations in the status menu, named from the
first thing the person typed. Reopening one restores the transcript **and** resumes
the model's own session, so the conversation continues. If that session has been
deleted underneath, the app says so out loud rather than letting the screen and the
model's memory diverge silently.

**Pinned windows.** Any part of an answer can be lifted out into a floating window
with a ` ```window ` block — up to 10, cascaded, closable, hideable with `Esc`, and
all listed under `Pinned Messages` in the status menu with `Show All` and `Clear All`.
They wear the character's theme, including Liquid Glass (0.21.336–337).

---

## 3. Projects, permission and safety

**Projects are an allowlist, not a folder list.** A path is never guessed from a
name. Each project carries its own allowed tools, and the registry is **per
character** — approving a folder for Miku does not approve it for anyone else
(0.13.214–216). Adding or removing a project re-asks the last question out loud
("Workspace changed — asking again") rather than silently leaving a running session
pointed at the old directory.

**Approval happens at the point of impact**, and the card describes what will
actually happen rather than the name of the rule being granted. Action classes:

| Class | Remembered? |
|---|---|
| `readOnly` | Yes — Once / Always / Deny |
| `localWrite` | Yes, since 0.15.271 |
| `projectMemoryWrite` | Never — it writes outside every registered project |
| `directoryAccess` | Never — a grant cannot name *which* folder |
| `destructive`, `gitHistoryChanging`, `dependencyInstalling`, `externalNetwork`, `browserAction` | Never |

`Always` is only offered when the grant key `(project, tool, class)` would describe
the whole of what is being agreed to, when there is a registered project to hang it
on, and when policy would honour it. Those three conditions are a tested function,
not an `if` in a view. Only `Always` reaches disk, in
`AISecretary/permissions-<profileID>.json`, one file per character; session grants
cannot leak into it by construction.

**`Always` covers the project, not a folder** (0.23.365). One yes on `Second-Brain`
covers writing to the vault root and every folder under it, for ever — a refused
folder that lies inside the approved project is not treated as another place to ask
about. A folder genuinely outside the project still asks, every time. And the class
is read from the command that was refused, not assumed: `rm`, `shred`, `dd`, `sudo`
come back as `destructive`, package managers as `dependencyInstalling`,
`git rebase`/`reset`/`push` as `gitHistoryChanging` — none of which a project grant
can answer for, so they ask even inside a project answered `Always`. `mkdir` and
`mv` stay `localWrite`, because renaming and creating folders is the ordinary work
of a vault.

**The grant is an input, not a rescue** (0.23.365). An approved project starts every
turn with the file-writing tools already allowed, so a new conversation never pays
the refused-then-widened round trip. Before this, the grant was only consulted
*after* a refusal, and behind a brake keyed to the whole conversation — which meant
the second and every later write of a conversation raised the card again with a
matching `Always` in hand.

**Every card leaves a trace.** Answering one writes a line into the conversation
— `You chose "Always" — I'll keep this for X.` — and it is written *before* the work
runs, not after (0.17.278).

**There are two walls, and both are handled.** Claude Code refuses a tool it lacks
permission for, and refuses a path outside its working directory in completely
different words. Both now raise their own card; a turn that hits both is asked about
the folder first and about the tool on the retry (0.21.338, 0.21.340). A folder that
has already been opened is never re-offered, and when there is nothing left to grant
the app says so rather than stopping silently.

**One rescue per refusal, and it never starts on top of a running turn** (0.23.365).
The refused-tool path and the ` ```blocked ` nudge answer the same question, so the
refusal path owns the turn whenever it parsed anything and the nudge fires only when
nothing was refused. A retry waits in a single slot until the stream it came from has
finished, rather than cancelling it — which is what used to leave two empty bubbles,
a character insisting she was waiting for approval, and no card at all.

**Known gap:** a `rm` refused by Claude Code's *sandbox* still matches none of the
phrases the app reads as a refusal, so no card is raised for it and the character
says in words that she is waiting. Driven and confirmed 2026-08-22.

**Asking in words is a dead end, and the app breaks it.** There is nobody to petition
— the only way a question reaches the person is a tool call that gets refused. A
reply that marks itself ` ```blocked ` for want of permission gets one turn back
saying exactly that, once per dead end, never while a card is up (0.21.331).

**Approval cards are reachable from the command window too**, capped at 320pt and
scrolling inside themselves, with the same buttons as inside her own chat.

**The audit trail** records every state transition, tool call, approval, and
execution with a task correlation ID.

---

## 4. Working through an AI CLI

The app drives a CLI that is already installed and signed in under the person's own
account. There is no API key: `ANTHROPIC_API_KEY` is stripped from the child
process environment so a stray export cannot bill API credit for work meant to run
on a subscription. **There is no second path — no CLI, no reply, and it says so.**

| Vendor | State |
|---|---|
| **Claude Code** | Full support: approval cards, browser, skills, effort, warm process |
| **OpenCode** | Runs, chosen per character, user-supplied CLI path, model list read from `opencode models` on the machine. **No approval cards** — `run` creates files without asking and emits nothing to catch. Shipped deliberately with a yellow warning strip in Profile and a connection line reading `runs · no approval cards` (0.23.348) |

The vendor is chosen per character in the Profile panel, so two characters on the
same desktop can be on different vendors. Switching vendors drops the session (a
session id belongs to the tool that issued it) and drops a model the new vendor does
not offer, saying so out loud. Rows the vendor does not support are hidden — Effort
disappears for OpenCode, CLI Path appears.

**The connection is checked, not assumed.** The `AI` row asks the CLI whether it is
actually signed in (`claude auth status`, reading only `loggedIn` and
`subscriptionType` — never the email or org id in the same reply) and shows a green
tick with version and plan, or a red cross saying what is wrong and what to do. A
found binary that has not been asked yet is **not** a tick (0.22.343).

**Speed.** For Claude Code the app keeps one warm process per character and feeds
messages down its stdin — roughly 3.7× faster per turn than respawning. Whether a
turn can reuse it is `WarmProcessKey`, a pure function over every launch flag.
**Nothing that changes between turns may go in the system prompt**: when the
neighbours block carried each character's live state, four characters were killing
each other's warm process every turn (0.21.333). For OpenCode the cost is measured
and elsewhere — 0.3s of process startup against ~116s of cold prefill — so there is
no warm process, only an optional background warm-up turn (0.23.353).

**MCP works with no code.** The app drives the person's own CLI, which loads their
own MCP servers from their own config — calendar, Slack, email, knowledge bases,
all of it. Nothing is configured twice.

**Sub-agents are visible.** While one runs, the header says what it is doing, the
last tool it reached for, and how long it has been quiet — and it never claims the
sub-agent is broken, because a slow tool and a dead session look identical from
here. Its steps are drawn indented with hollow marks (`◈` / `▹`) so a `Bash` it ran
can never read as one the character ran herself. It speaks when the sub-agent
finishes, including when there is nothing to report (0.18.281–282).

**Token usage.** `/usage` answers as a table in the chat; `⌘U` opens a live window
that keeps updating with the chat closed. All four token buckets are counted
separately (cache reads and writes cost very different amounts); context is the
latest turn's figure, not a running total. Subscription quota — session, weekly,
per-model, with reset times — is read from the CLI's own `/usage`, and the parser
either understands the line or says nothing. Any dollar figure carries the caveat
that a subscription is not billed per token.

---

## 5. What she can be asked to do

**Anything, in any language.** With a vendor that has its own file tools, every
message goes to the agent — the old keyword classifier stands aside entirely
(0.16.275). Prose is not parsed for commands, so a paragraph containing the word
"status" cannot be read as a git request.

**The app acts only on markers it defined**, never on prose. The model writes lists
and promises all the time; guessing would build features around sentences that were
not requests.

| Block | What it does |
|---|---|
| ` ```choices ` | A picker under the answer — arrow keys and Enter, or click. Sends the **full text** of the choice, not the letter |
| ` ```window ` | Lifts content into a pinned floating window |
| ` ```loop ` | Starts a recurring check |
| ` ```watch ` | Starts a folder or file watch |
| ` ```run ` | Offers to run an instruction file |
| ` ```to ` | Hands work to one or more other characters |
| ` ```remember ` | Asks to write a note into the project's memory |
| ` ```install-skill ` | Asks to install a skill |
| ` ```save-file ` | Offers a file made in the scratch folder for saving |
| ` ```attach ` | Asks the person for a file |
| ` ```blocked ` | Declares itself stuck, with what is missing |

**Typed commands:** `/model`, `/effort`, `/usage` (`/tokens`), `/loop` (`/track`),
`/run` (`/follow`), `/watch`, `/new` (`/reset`), `/history` (`/chats`). They are
handled locally and never reach the network or the state machine.

### Following things over time — `/loop`

`/loop 10m <what to report>` and she asks herself that question every N minutes and
answers into the chat. Accepts `10`, `10m`, `10 min`, `10 นาที`, `1h`, `90s`. Every
prompt carries the real clock time, because the model has no clock and is not
running between messages.

The guards are the feature: it announces itself when it starts and says how to stop
it; a ⏱ badge stops it in one click; every round inserts an activity box **whatever
the activity toggle says**, because this is the reason an unrequested message
appeared; bounds are 1 minute to 2 hours with a hard stop at 12 hours; it is
session-only and never reaches disk; and it never fires over a reply being read —
if she is busy the round is postponed, not dropped.

### Watching files and folders — `/watch`

Up to 5 at once, polled every 4 seconds off the main actor, reporting what was
added, removed or changed. Folders are compared by size and modification date, a
single file by a digest of its **contents** — because ⌘S with no edit moves the
mtime, and reporting that is crying wolf. Ceilings are deliberate (500 entries, 4
levels deep, skipping `.git`, `.build`, `node_modules`) and **it says when it hits
one**, because "watching this folder" and "watching the first 500 files in it" are
different promises. `/watch stop [path]`, or the × on the 👁 badge.

A watch started as part of a real request carries that request's instruction, so a
file landing in the folder is acted on, not merely announced (0.21.329). A `/watch`
typed by hand asks for nothing — being told *is* the whole request.

### Following an instruction file — `/run`

Reads the file and walks it one step at a time, each step an ordinary turn, so every
permission card still applies. The person types the path; no filename is ever
guessed, and reading the file is classed `externalNetwork` because its contents
leave the machine.

- **No format parsers.** Natural language, step-by-step, diagrams and LangGraph are
  all handled by asking the model to answer with a ` ```plan ` block. The app sees
  one shape.
- **The plan is confirmed before anything runs** — every step shown in order,
  nothing abbreviated, nothing started until `Start`.
- **The file is pinned by SHA-256 of its contents**, checked before every step. Edit
  it mid-run and the run stops and says why.
- **Changed since last time?** A session-scoped fingerprint per path makes the card
  say "changed since you last ran it".
- **Prompt injection is scanned for deterministically** — not delegated to the model
  that is being deceived. A hit **escalates rather than blocks**: the wording that
  triggered it is shown and a checkbox must be ticked before `Start`.

### Working in the browser

Off by default, per project. With the Claude in Chrome extension it reads pages in
the person's own Chrome — including sites they are signed into, because it borrows
the open session rather than fetching anonymously. Read-only tools are pre-approved;
navigate, click, type, upload and JavaScript ask first, and the card says plainly
that one grant covers all three. Web content is untrusted input: the prompt frames
it as something being *reported*, never as instructions to follow.

Two limits worth knowing: the extension's own site permissions are a second layer
the app cannot reach, and a new conversation means a new session, which means a new
Chrome tab group.

### Project memory

Reading has worked since the backend was first pointed at a project folder — Claude
Code loads the project's `CLAUDE.md` and `~/.claude/projects/<slug>/memory/MEMORY.md`
by itself. Writing back is the part that was added: she asks with a ` ```remember `
block, and **the app writes it, not the model**, so no tool grant is widened. Three
doors, each a spoken refusal rather than silence: no project open, a note that reads
as an instruction, and the `projectMemoryWrite` card that asks every single time.

It is written to the same place the person's own terminal reads. That is the feature
and the reason it always asks.

### Saving a file made in the scratch folder

Work with no project open runs in a scratch folder under Application Support, where
nobody would go looking. A ` ```save-file ` block turns into a Save button that
opens the system panel at Downloads. The path check is the security half: symlinks
resolved on both sides, a trailing `/` on the comparison so `/scratchings/x` is not
read as inside `/scratch`, and names starting with `/` or `~` refused outright. A
missing file draws no button. The file is **copied**, not moved, because the
conversation still refers to it.

---

## 6. Characters working together

**They know about each other.** A character can see who else is on the desktop, what
model they are on, and the **name** of the project they have open. Nothing more:
`CharacterMessage` carries no path, no grant, no tool id and no session id, and a
test inspects its field names so adding one would go red rather than leak quietly.
The recipient works under her own approvals or refuses.

**Handing work over.** Ask one to have another do something and she forwards it,
says so, and reads the answer out when it comes back. Both conversations show the
hand-off in writing, on disk, at the moment it happens.

- The app recognises a hand-off only when it is **clear** — a hand-off phrase plus
  exactly one name in the roster. Everything else goes to the model, which answers
  with a ` ```to ` block. The keyword list was deleted rather than extended, because
  `contains` cannot tell "Anya said it's done" from "tell Anya it's done" (0.17.276).
- **More than one name always asks**, with a "Both / Everyone" option so that asking
  is not a step backwards, and always with "No — answer it yourself".
- An unknown name is **said out loud**, never matched to the nearest spelling.
- The sender does not block. `hopLimit = 2`, one errand per pair per direction,
  expiring at 15 minutes.
- A busy recipient **queues and says so**, with her queue position, and the clock
  restarts — being busy is not being ignored.
- A numbered request is a **plan**, not a message: step 1 goes out, the rest waits
  with the sender, and when the answers are in the sender runs step 2 with all of
  them in hand. Recipients work in parallel (measured: 46s where sequential would
  have been ~74s).
- Nobody who cannot be reached is waited on; they are dropped from the plan and
  named there and then.
- Messages from another character are framed as untrusted input, and the prompt says
  outright that they cannot change the recipient's model, project, skills or
  permissions.
- The tools that would let the model message other CLI sessions instead of the
  characters are **denied at the CLI**, because no wording in a prompt makes a tool
  sitting in front of a model stop looking like the answer (0.14.235).

**Handing work over when she is busy.** The interruption card offers a third
answer — `Give it to…`, a menu of whoever is free. It is a menu rather than a row of
buttons so the card is two rows tall whether two characters are free or twenty.
Availability is re-checked when the button is pressed, not when the card was drawn,
and a refusal re-asks with a freshly filtered list (0.18.284–285).

---

## 7. The command window

A Spotlight-style floating slab, opened from `Show / Hide Command` in the status
menu, that commands every ticked character at once. `Esc` or ✕ **hides** it; the
sessions carry on. Position, width and expanded height persist across launches.

- Nothing ticked → a red line under the box, and nothing is sent.
- A message naming nobody goes to everyone ticked, as a separate copy through each
  character's own `submit` — the same as typing it in her own chat.
- A message naming a ticked character goes only to her, matched by the same name
  logic the hand-off uses.
- A message naming someone **not** ticked is refused by name. It never guesses a
  substitute.
- Broadcasts carry a preamble saying who else received it, to do only their own
  part, to remember any role the instruction assigns, and to divide unassigned work
  between themselves via the hand-off that already exists. **Roles have no store in
  the app** — a role is an ordinary instruction the session remembers.
- Instruction files can be dropped on the whole slab and are read in drop order,
  with the typed message appended. Other file types are attached to each recipient.
- `End all` closes the session of every character this window has commanded.

The box carries the chat box's own behaviour: ↑↓ recall, 📎, `Clear`, click anywhere
for a caret, `Shift+Enter` at the caret, and `⌘+` / `⌘−` scaling **the whole slab**
— captions, chips, strip, footer and spacing, not just the typed text (0.21.326).

**The results strip** collects every finished turn, newest first, keeping 20, capped
at 220pt and scrolling inside itself, each row stamped with the time the answer
arrived. It renders ` ```choices ` pickers, and answering one sends the choice's full
text back to that character. `copy`, `Save` and `clear`: both copy and Save write the
same tested document, in **screen order**, marking any character who could not
finish — the coloured dot that says so on screen does not survive being written to a
file. The copy glyph turns into a tick for 1.2 seconds, because a copy that changes
nothing on screen is indistinguishable from a dead button.

**The approvals strip** shows a row per waiting card, the words verbatim and the
buttons drawn from the same list her own chat would use, so the two can never
disagree. Capped at 320pt and scrolling — four cards uncapped once grew the window
to 921pt on a 1030pt screen, and a card nobody can reach is the bug this exists to
fix (0.21.340).

---

## 8. Notification, version, packaging

**Notification on completion**, using the macOS settings — there is no second switch
in the app. It is **not** sent in three cases, each for its own reason: a turn that
was an errand for another character (one request would otherwise produce two boxes),
a turn whose chat panel is on screen (the answer is already visible, wherever that
window is), and a turn with nothing to say. A loop check passes all three
deliberately — reporting to an empty desk is what notifications are for.

Clicking one opens the app and the chat of the character who sent it, carrying her
uuid in `userInfo` so the click that *launches* the app works too. Her portrait is
attached on the right; the small icon on the left is the bundle's and macOS gives no
per-notification control over it.

**Versioning** is `major.sprint.change`, declared once in `AppVersion.swift`; the
About window and `package-app.sh` both read that value, and a test fails if the
README's copy disagrees. `CFBundleVersion` uses the change digit, which only ever
increases.

**One `.app`, always.** `package-app.sh` deletes every other `AISecretary.app` in
the repository and stamps the bundle with the commit and branch it was built from,
shown in About. The bundle is ad-hoc signed and not notarized, so moving it to
another Mac trips Gatekeeper — see the root `README.md`.

---

## 9. Scenarios, end to end

**Ask a question about a project.**
Click the character → type → she answers through the CLI, streaming, with an
activity box if the toggle is on. First time she needs to read the folder a card
appears; answering `Always` means it is not asked again in that project, across
restarts. The reply lands in the bubble; the conversation continues with `--resume`,
so follow-ups know what was read.

**Something she is not allowed to do.**
She attempts it. The CLI refuses. The refusal becomes a card naming the file or the
folder. Once / Always / Deny, with `Always` present only when the grant would
describe the whole of what was agreed. Pressing a button writes a line into the
conversation saying what was chosen, then the request is run again — with the tool
rule widened, or with the folder added to `--add-dir` and the backend restarted,
because `--add-dir` is a launch flag.

**Hand work to someone else.**
"ขอให้อาเนียช่วยดูไฟล์นี้หน่อย" → recognised, or the model answers with a ` ```to `
block, or a picker appears if more than one name is in play. `→ Passed this on to
อาเนีย. I'll say when there's an answer.` appears in the sender's chat and
`← … passed this on from you` in the recipient's. The sender is not blocked. The
answer arrives as `← อาเนีย answered: …`, is saved on both sides, and rides along
with the next message so the sender can actually talk about it.

**Command four characters into a shared folder.**
Open the command window, tick four, drop the instruction file, send. Each gets her
own copy with a preamble. The ones with no project open are standing in scratch, so
the shared folder is outside their session and each raises a **directory** card in
the command window; approving one adds the folder and re-runs. Answers land in the
results strip as they finish, stamped with the time, and `Save` writes the strip as
it is read on screen.

**Watch a folder and act on what lands.**
"watch this folder and follow whatever instruction arrives" → a card if the folder
is outside every project, then the 👁 badge. Dropping a file produces both the app's
own `👁 1 change in …` line and a real turn carrying the standing instruction quoted
back, so she does the work rather than only announcing it. One follow-up in flight
at a time, since acting inside a watched folder is itself a change.

**Follow an instruction file.**
`/run plan.md` → a card asking to send the contents → the model returns a
` ```plan ` → every step shown, unabbreviated, plus a warning and a checkbox if the
injection scan matched anything → `Start` → one step per turn, each still passing
every permission card, the file's hash checked before each step, a header badge
showing the current step and stopping it in one click.

**Track something while you cannot type.**
`/loop 10m บอกหน่อยว่าถึงหัวข้อไหนแล้ว` → announced with how to stop it, ⏱ badge on the
header → every ten minutes an activity box and an answer, whatever the activity
toggle says → `/loop stop` or one click. It keeps running with the chat closed,
because the person who started it is watching a room, not a screen.

**Finish something in scratch and keep it.**
No project open, she writes a file, the reply carries ` ```save-file ` → a Save
button (only if the file exists and its path really is inside scratch) → the system
panel opens at Downloads → the file is copied out, and the original stays where the
conversation can still refer to it.

---

## 10. Not there

| | |
|---|---|
| **Codex** | Sprint 24, not started |
| **Gemini CLI** | Sprint 25, not started |
| **Discord-style notification** | Sprint 26. **Blocked on code signing, not on code.** It needs the restricted `com.apple.developer.usernotifications.communication` entitlement, which must come from a provisioning profile; `package-app.sh` signs ad-hoc, and this machine reports `0 valid identities`. Everything else about it is understood |
| **Voice** | Sprint 99, not started |

Smaller things known to be missing, each recorded where it was found:

- No UI for reading or deleting project memory — edit the files, or use the terminal.
- `selectedSkills` is session-scoped and forgotten when the app closes.
- The header badge still shows `| medium` under OpenCode, which has no effort.
- `prefers-reduced-motion` is not read; it should cover every animation at once.
- Nothing on screen says how many characters an errand went to, or who has answered.
- `` `inline code` `` is still unstyled.
- Mono has no Thai bold face, so `**ตัวหนา**` looks the same in that font.
- A new conversation means a new Chrome tab group; this cannot be fixed from here.
- Making the icon larger in Finder needs `.icon` (Icon Composer) rather than `.icns`.
- `New Character` clicked immediately after first launch occasionally does nothing;
  clicking again works, cause not yet found.

---

## 11. Superseded — do not read these forward from the backlog

The backlog records these as they were at the time. They are no longer how the app
works.

| Backlog says | Now |
|---|---|
| Sprint 2 — intent classification routes commands to local adapters | Removed for any vendor with its own file tools (0.16.275). The classifier survives only in the fallback path, and during the second or two before the CLI is found |
| Sprints 14–15 — `addressPhrases` keyword list for hand-off detection | Deleted entirely, not shortened, and frozen against being re-added (0.17.276) |
| Sprint 14 — two names joined by "และ" / "and" send to both | Any number of names greater than one always asks, with a "Both" option (0.17.276) |
| v0.14.262 — comments are kept when they are "why" or a warning | Replaced by 0.23.354–360: **no `.swift` file carries a comment**; explanations live in names, test names, or `docs/design-notes/` |
| Sprint 5.6 — `⌘H` hides one character | Hides the whole app since 0.13.223, and the per-character row moved (0.17.280) |
| Sprint 5 — one uploaded picture per activity | One picture per profile since 0.5.5; activity is shown by halo colour, badge and label |
| Sprint 12 — Model and Effort are not stored | Stored per character since 0.18.286, and still take effect immediately without a Save |
| Sprint 5.7 / charter — a message starting with `-` must go after `--` | Still true for OpenCode. For Claude Code the message travels as JSON down stdin and never appears in argv at all (0.13.224) |
| Sprint 13-3 — the build hash is in the status-bar menu | Removed from the menu at 0.13.209; About only |
| Sprint 21 — panels stay solid under Liquid Glass | Reversed at 0.21.321 on the owner's instruction; all four panels take glass |
| Sprint 20 — `New Character` clones the focused profile | Starts from the default profile since 0.20.313 |
| README — "Sprints 1–15 of the charter are done" | Sprints 1–23 have shipped |

---

## Where to read more

| | |
|---|---|
| `CLAUDE.md` | The charter: vision, permission model, engineering rules, Definition of done |
| `PRODUCT_BACKLOG.md` | What shipped, round by round, with the reasoning and the measurements |
| `SPRINT_BACKLOG.md` | The sprint being worked on now |
| `PRODUCT_BACKLOG_NEXT_SPRINTS.md` | Sprints 24, 25, 26 and 99 |
| `docs/design-notes/` | One file per source target: platform constraints, measured numbers, and the reasons the code cannot state itself |
| `docs/diagrams/` | Excalidraw: app start, and one reply end to end |
| `code/README.md` | Architecture, every module, how to run things |
