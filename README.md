# AI Secretary

A macOS desktop companion: a floating animated character that lives on your
desktop, talks to you in chat, and gets work done through an AI coding CLI you
already have installed.

Version 0.23.364. macOS 26+. Not shipped — this is a working repository.

## What it actually is

The character is the face. Behind it sits an orchestration layer that reads
your intent, resolves context, asks permission at the point of impact, and then
picks a tool. **The CLI is one of those tools, not the assistant itself.**

That distinction is the whole design. The app drives a binary on your own
machine, under your own account and subscription — so there is no API key to
manage at all, and the assistant inherits everything that tool can already do:
reading files, searching, running approved commands, your MCP servers, and your
browser. There is no second path: no CLI, no reply, and it says so.

Two makers are supported today, chosen per character:

| | |
| --- | --- |
| **Claude Code** | The full experience — approval cards, browser, skills, effort, and a warm process kept per character so a turn does not pay for a fresh boot. |
| **OpenCode** | Runs, with a CLI path you supply and a model list read off your own machine. **It does not go through the approval cards** — `run` creates and changes files in the project folder without asking, and emits nothing the app could catch. Shipped deliberately on that footing, and the Profile panel says so in a warning strip. |

## What it can do today

- **Live on the desktop.** Transparent always-on-top character window, three
  sizes, draggable, remembering where you put it, click to open a speech-bubble
  chat that you can resize by dragging or in steps.
- **Hold a conversation.** Streaming replies with continuous context, markdown
  tables, code blocks, clickable links, files dropped anywhere in the window,
  chat history you can reopen and carry on, and an optional running commentary
  of which tool it reached for.
- **Work in your projects.** Explicitly registered folders only — a path is
  never guessed from a name, and the registry is per character. Read-only by
  default; anything that writes stops and asks, and you choose there whether the
  answer lasts the conversation or the project.
- **Read your browser.** Optional, off by default. With the
  [Claude in Chrome](https://claude.com/claude-for-chrome) extension it reads
  pages in your own Chrome — including sites you're signed into, because it
  borrows the session that is already open rather than fetching the page
  anonymously. Reading is pre-approved; scrolling, clicking and typing ask
  first, and the card says plainly that one grant covers all three.
- **Be several people.** Profiles with their own name, picture and manner —
  each one a character on the desktop with her own projects, settings, model,
  maker and session.
- **Pass work between them.** Ask one to have another do something and she
  forwards it, says so, and reads out the answer when it comes back. Both
  conversations show the hand-off in writing. A character can see who else is
  around, what model they're on and the *name* of the project they have open —
  and nothing more: the message carries no path and no permission, so the one
  who takes it works under her own approvals or refuses.
- **Take one order for everybody.** A Spotlight-style command window sends a
  single instruction to every character you tick, collects their answers in a
  results strip you can copy or save, and raises any approval card they hit
  where you are actually looking.
- **Keep watch and keep going.** `/loop` reports back every N minutes;
  `/watch` follows a folder or a file and acts on what lands there; `/run`
  walks an instruction file one confirmed step at a time, scanning it for
  prompt injection first.
- **Remember what it learns.** With your approval it writes notes into the
  project's own Claude Code memory — the same place your terminal reads.
- **Tell you when it's done.** A macOS notification per finished turn, carrying
  the character's portrait, that opens her chat when clicked — and stays quiet
  when her chat is already on screen.

Sprints 1–23 of the charter have shipped. Sprint 24 (Codex) is next; Gemini CLI,
Discord-style notifications and voice come after it.

**[`docs/FEATURES.md`](docs/FEATURES.md) is the full inventory** — every feature
and the scenarios they add up to, with the version each landed at, plus what is
deliberately not there yet.

## Getting started

**Before you start** you need macOS 26 or later, the Xcode 26 command line
tools (Swift 6.3), and [Claude Code](https://claude.com/claude-code) installed
and signed in with `/login` — or OpenCode on the machine, if you would rather
run that. There is no API key to set up and nothing to configure: the app
drives a binary on your own machine under your own account. It looks on launch,
asks the tool whether you are really signed in rather than assuming a binary it
found will answer, and says so in the chat if it can't find one — no CLI, no
reply.

```bash
git clone https://github.com/olarn/AI-Secretary.git
cd AI-Secretary/code
swift build            # or: swift test
./scripts/package-app.sh
open AISecretary.app
```

That builds the bundle and opens it. A character appears near the bottom-right
of your screen and a ✨ item appears in the menu bar; click the character to
open the chat, and quit from the ✨ menu. Nothing else is registered — no Dock
icon, no login item.

While you are changing code, `swift run AISecretaryApp` runs the checkout
directly and skips the packaging step. It holds a Terminal window open, and
four things only exist in a real bundle — the About window's build stamp, the
icon, the version in `Info.plist`, and reopening by double-click — so check
those against a packaged build rather than a `swift run`.

[`docs/FEATURES.md`](docs/FEATURES.md) is what the app does, feature by feature
and scenario by scenario. [`code/README.md`](code/README.md) is the developer's
guide: every module, how it is layered, how it is tested and driven, and where
it keeps things on disk.

**One `.app`, always.** The packaging script deletes every other
`AISecretary.app` in the repository and stamps the bundle with the commit and
branch it was built from — shown in About. Several bundles carrying the same
version and different code inside is how a fixed feature comes to look broken
again.

**Copying it to another Mac.** The bundle is ad-hoc signed and not notarized —
`spctl` rejects it and `codesign` reports `TeamIdentifier=not set`. That is
invisible on the machine it was built on, because a locally built app is never
quarantined. Move it to another Mac by AirDrop, zip or download and macOS
attaches `com.apple.quarantine`, then refuses with *"can't be opened because
Apple cannot check it for malicious software. This software needs to be
updated."* Nothing is wrong with the build; Gatekeeper simply has no developer
identity to check. On your own second machine, either right-click → **Open** (or
System Settings → Privacy & Security → **Open Anyway**), or:

```bash
xattr -dr com.apple.quarantine /Applications/AISecretary.app
```

Handing it to anyone else needs a Developer ID certificate, notarization and a
stapled ticket — a paid Apple Developer account, so it is the owner's call, not
something the packaging script can do on its own.

## The repository

| Path | What's there |
| --- | --- |
| [`CLAUDE.md`](CLAUDE.md) | The charter: product vision, permission model, sprint-by-sprint scope, and the engineering rules this code is held to. **Read this first.** |
| [`docs/FEATURES.md`](docs/FEATURES.md) | What the app does today, as one document: features, scenarios, and what isn't there. |
| [`PRODUCT_BACKLOG.md`](PRODUCT_BACKLOG.md) | What shipped, round by round, with the reasoning and the measurements behind each decision. |
| [`code/`](code/) | The Swift package. Its [README](code/README.md) is the detailed guide — architecture, every module, how to run things. |
| `code/Sources/` | Domain modules (`AssistantState`, `ProjectRegistry`, `Permissions`, `ToolAdapters`, `LLMProvider`, `SecretaryCore`) and the SwiftUI app. |
| `code/Tests/` | One suite per domain module (`FunctionalCore` is re-exports and the app target is exercised by driving the app, not the test bundle). |
| `docs/design-notes/` | One file per source target. The code carries no comments, so this is where the residue lives: platform behaviour that was tried and failed, couplings to build scripts, and measured numbers whose measurement is the justification. |
| `docs/diagrams/` | Excalidraw: what happens at app start, and one reply followed end to end. |
| `initial-implementation-prompt.md` | The original brief, kept for provenance. |

Domain logic is written in a typed functional style on
[Bow](https://github.com/bow-swift/bow): failures are the left of an `Either`
rather than thrown, and absence is `Option` rather than `?`. SwiftUI views stay
ordinary SwiftUI and cross that boundary through a bridge file — Bow exports its
own `State`, which would otherwise shadow `@State`. The rules are in the
`swift-functional-programming` skill.

**No `.swift` file in this repository carries a comment.** What the code does is
said by its names, why a thing broke is said by the name of the test that
reproduces it, and anything neither can hold goes to `docs/design-notes/`. The
one exception is `// swift-tools-version: 5.9`, which SwiftPM parses.

## Security posture

- Least privilege by default. Read-only and acting are separate classes, and
  approval is asked at the point of impact with a description of what will
  actually happen rather than the name of the rule being granted.
- Reading and writing **inside a folder you registered** can be remembered:
  the card offers Once, Always and Deny, and only Always is written to disk —
  the app's own file, one per character, that nothing else reads. Always is
  offered only when what gets stored would describe the whole of what you
  agreed to.
- Everything else asks every time however you answer it, and nothing about it
  is ever written down: sending a file to the model, acting in your browser,
  deleting or overwriting data, changing Git history, installing software,
  opening another folder to the assistant, and keeping a note in your Claude
  Code memory — that one lands outside every folder you registered, where your
  own terminal reads it. A path dragged in from outside your projects is asked
  about every time too.
- The app holds no credentials of its own — it drives the CLI you installed, and
  `ANTHROPIC_API_KEY` is stripped from the child process environment, so a stray
  export can't quietly bill your API credit for work you asked to run on your
  subscription. When it checks whether you are signed in it reads only whether
  you are and which plan you have, never the email or organisation in the same
  reply.
- The app acts only on markers it defined — ` ```choices `, ` ```to `,
  ` ```watch `, ` ```remember ` and the rest — and never on what a sentence
  appears to mean. A model saying "I'll keep an eye on that" must not become a
  background job.
- Model output, web pages, tool results, MCP responses and messages from other
  characters are all treated as untrusted input. Links are limited to `http`,
  `https` and `mailto`.
- Filesystem access is scoped to folders you registered. An instruction file is
  scanned for prompt injection before it is run, deterministically rather than
  by asking the model that is being deceived.
- **OpenCode is the exception to all of this** and says so on its own row: it
  writes inside the project folder without a card.

## A note on the character art

A character's picture is a **development placeholder and is not committed** —
each profile's image lives in your own Application Support folder and is
uploaded through the Profile panel. The app icon is committed, at
`docs/Noti-Icon.png`, and is also what a newly created character wears until
you give her a picture of her own. Replace both with art you hold the rights to
before distributing anything.

## Testing culture

A UI feature is not done until it has been driven in the running app. Unit
tests over the numbers behind a view are not evidence the view works: the
message box once shipped with eight passing tests about its height while the
box itself never grew past one line, because the measurement feeding those
tests was always zero. Open the app, do the thing a user would do, and look at
it.

The app target is deliberately thin for the same reason: it is never linked into
the test bundle, so any rule the app has to *decide* lives as a pure function in
a library target, and the view only applies the answer.
