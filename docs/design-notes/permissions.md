# Permissions

## The rule behind `mayBeRemembered`

A grant is `(project, tool, class)` and nothing else. **A class may be
remembered exactly when that key describes the whole of what was agreed to.**
Danger is not the criterion — expressiveness of the key is.

`.readOnly` qualifies: "Claude Code may read and work in this project" is the
whole of what `startAgent` asks, and re-asking on every new session in a project
the person already chose is friction with nothing behind it.

`.localWrite` qualifies too, **but only since `.projectMemoryWrite` was split
out of it.** This is the reversal of a narrowing made in Sprint 15, and what
made it safe to reverse was the split, not a change of mind about the danger.
While two operations shared `.localWrite`, the key did not describe them:
`rememberNote` is scoped by the sentence it writes and writes outside every
registered project, so one Always on a file edit would have covered every later
note as well. Driven and found wanting on 2026-08-17 — writing in a registered
vault asked again for every new shell command (`mkdir`, then `mv`, then …),
because the only thing holding a widened permission was a per-rule set that dies
with the conversation.

The rest are excluded, each for its own reason:

- `.destructive`, `.gitHistoryChanging`, `.dependencyInstalling` are on the
  charter's approval list because they are hard or impossible to undo. None
  becomes routine by being agreed to once.
- `.externalNetwork` and `.browserAction` leave this Mac, or act as the person
  somewhere else. That is a different promise from "stop asking about my own
  project".
- `.projectMemoryWrite` writes where the person's own terminal `claude` reads
  back, outside every folder a grant is keyed to. "Yes" here is a different
  promise from "yes, work in my project".
- `.directoryAccess` is a grant about a *place*, and the key cannot name a
  folder — so a remembered yes would silently cover the next folder too.

## Why `.browserAction` and `.directoryAccess` are their own classes

The card is where someone decides, so the class has to read correctly there.
Called `localWrite`, a browser action reads "Writes files in the project", which
a click on a web page is not; called `externalNetwork` it reads as sending data
out, which it also is not. What matters is whose session it acts in — theirs.
`.directoryAccess` exists because no other class says *where*.

## `noteToolOutsideAllowlist` marks rather than refuses

It used to refuse, on the reasoning that an allowlist miss is answered by
editing the allowlist rather than by asking a human to wave it through. In the
app that came out as a red "denied by policy" with no way forward from the chat
— the person could not even say yes to something they wanted. The scratch
project made it worse: it allows only the agent, so with no project registered,
`/watch` and `/run` were refused outright rather than asked.

The miss does not vanish. `noGrantMaySkipThis` turns it into a question no grant
can answer for, and the card says which list is being stepped past.

## The order inside `requireApproval` is load-bearing

`noGrantMaySkipThis` is consulted **before** the grants, never after. A grant is
remembered per project and tool, so checking grants first would let a tool the
allowlist never covered run unattended on the strength of one earlier yes —
which is the hole the rail exists to close.

## `PermissionError` has a case no rail produces

`toolNotAllowlisted` is unused since the allowlist started asking. The rail is
kept rather than removed: a policy that can only ever say yes-or-ask has nowhere
to put a rule that genuinely must not be waved through, and adding the left rail
back later is a worse change than leaving room for it.

## Two grant sets, and only one reaches disk

`session` dies with the conversation; `standing` is written and read back next
launch. A lookup asks both, because from the caller's side "have they agreed to
this" has one answer. `remembered` exposes only the standing half — a session
grant reaching disk is the bug the split exists to make impossible.

`adopting` replaces the standing half rather than merging: the file is the
record of what is remembered, so a pair deleted from it is a pair the person
took back. `forgetting` takes both halves, because a project registered again
later with a *reused* id would otherwise inherit grants nobody can see to
revoke.
