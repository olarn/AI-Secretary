# AI Secretary

A macOS desktop companion: a floating animated character that lives on your
desktop, talks to you in chat, and gets work done through the Claude Code you
already have installed.

Version 0.9.153. macOS 14+. Not shipped — this is a working repository.

## What it actually is

The character is the face. Behind it sits an orchestration layer that reads
your intent, resolves context, asks permission at the point of impact, and then
picks a tool. **Claude Code is one of those tools, not the assistant itself.**

That distinction is the whole design. The app drives the `claude` binary on
your own machine, under your own account and subscription — so there is no API
key to manage at all, and the assistant inherits everything your Claude Code
can already do: reading files, searching, running approved commands, your MCP
servers, and your browser. There is no second path: no Claude Code, no reply,
and it says so.

## What it can do today

- **Live on the desktop.** Transparent always-on-top character window, three
  sizes, draggable, click to open a speech-bubble chat that you can resize by
  dragging or in steps.
- **Hold a conversation.** Streaming replies with continuous context, markdown
  tables, clickable links, and an optional running commentary of which tool it
  reached for.
- **Work in your projects.** Explicitly registered folders only — a path is
  never guessed from a name. Read-only by default; anything that writes stops
  and asks, and the grant lasts the session, not forever.
- **Read your browser.** Optional, off by default. With the
  [Claude in Chrome](https://claude.com/claude-for-chrome) extension it reads
  pages in your own Chrome — including sites you're signed into, because it
  borrows the session that is already open rather than fetching the page
  anonymously. Reading is pre-approved; scrolling, clicking and typing ask
  first, and the card says plainly that one grant covers all three.
- **Be several people.** Profiles with their own name, picture and manner.

Phases 1–6 of the charter are done. Voice, and companions talking to each
other, are not started.

## Getting started

```bash
cd code
swift build            # or: swift test   (401 tests)
./scripts/package-app.sh
open AISecretary.app
```

You need Claude Code installed and signed in via `/login`. The app looks for it
on launch and says so in the chat if it can't find it.

**One `.app`, always.** The packaging script deletes every other
`AISecretary.app` in the repository and stamps the bundle with the commit and
branch it was built from — shown in About and in the status-bar menu. Several
bundles carrying the same version and different code inside is how a fixed
feature comes to look broken again.

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
| [`CLAUDE.md`](CLAUDE.md) | The charter: product vision, permission model, phase-by-phase scope, and the engineering rules this code is held to. **Read this first.** |
| [`code/`](code/) | The Swift package. Its [README](code/README.md) is the detailed guide — architecture, every module, how to run things. |
| `code/Sources/` | Domain modules (`AssistantState`, `ProjectRegistry`, `Permissions`, `ToolAdapters`, `LLMProvider`, `SecretaryCore`) and the SwiftUI app. |
| `code/Tests/` | One suite per module. |
| `initial-implementation-prompt.md` | The original brief, kept for provenance. |

Domain logic is written in a typed functional style on
[Bow](https://github.com/bow-swift/bow): failures are the left of an `Either`
rather than thrown, and absence is `Option` rather than `?`. SwiftUI views stay
ordinary SwiftUI and cross that boundary through a bridge file — Bow exports its
own `State`, which would otherwise shadow `@State`. The rules are in the
`swift-functional-programming` skill.

## Security posture

- Least privilege by default. Read-only and acting are separate classes, and
  approval is asked at the point of impact with a description of what will
  actually happen rather than the name of the rule being granted.
- Write and browser grants last one session and are never written to disk.
- Secrets live in the Keychain. `ANTHROPIC_API_KEY` is stripped from the child
  process environment, so a stray export can't quietly bill your API credit for
  work you asked to run on your subscription.
- Model output, web pages, tool results and MCP responses are all treated as
  untrusted input. Links are limited to `http`, `https` and `mailto`.
- Filesystem access is scoped to folders you registered.

## A note on the character art

The character image is a **development placeholder and is not committed**. The
app icon and the on-screen character are generated at package time from an
image in your own Application Support folder. Replace it with art you hold the
rights to before distributing anything.

## Testing culture

A UI feature is not done until it has been driven in the running app. Unit
tests over the numbers behind a view are not evidence the view works: the
message box once shipped with eight passing tests about its height while the
box itself never grew past one line, because the measurement feeding those
tests was always zero. Open the app, do the thing a user would do, and look at
it.
