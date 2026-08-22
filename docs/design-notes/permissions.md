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

## The two rescue paths, and why exactly one may run per turn

A refusal can reach the app twice over: the CLI refuses a tool and
`ClaudeCodeProvider` parses it into a `DeniedTool`, *and* the model says in words
that it is blocked, which `BlockedBlock` turns into a nudge. Both are rescues for
the same wall, and until 0.23.365 both could fire for one turn.

They collided in the worst possible order. `finishChat` queued the nudge and then
drained the queue on its way out (`defer`), so a new turn was already `thinking`
when `complete` called `offerToWiden`; the retry's state transitions were refused,
`streamReply` ran anyway, appended its empty placeholder and cancelled the turn
the nudge had just started. What the person saw was two empty bubbles, a
character insisting it was waiting for approval, and no card — the app waiting
for her while she waited for the app, which is the shape `9fa4824` was written to
break and this reproduced by a different route.

So the refusal path owns the turn whenever it parsed anything: `finishChat` takes
the denials, computes the recovery before the queue drains, and the nudge fires
only when nothing was refused — the case it was written for, where she asks in
prose without ever calling a tool.

## A retry is held, never fired from inside the turn it is retrying

`complete` runs inside the stream loop, so `streamingTask` is still set when the
recovery is decided. Calling `streamReply` there cancels the very task it is
running in. `widenAndRetry` therefore parks the operation in `pendingRetry` — one
slot, not a queue, because there is only ever one conversation to resume — and it
is drained after the loop ends. It is deliberately not the message `queue`, which
`dispatchNextQueued` feeds to `beginTurn`: that is the user-message path, and a
retry is not a new request.

## The brake is scoped to the retry chain, not the conversation

`6cb1ab5` added a brake so `refused -> widen -> retry -> refused` could not spin,
and keyed it on `sessionAgentTools`, which accumulates for the whole
conversation. Claude Code's rule for a file write is the bare tool name, so the
first write of a conversation put `Write` in that set and **every later write
skipped the standing-grant lookup and raised the card again** — with a matching
Always in hand. Measured in the owner's own archive on 2026-08-22: Always granted
at 16:43:32, the same file asked again at 16:43:51.

`widenedThisChain` holds only the rules widened for the attempt being retried and
is cleared as soon as a turn completes without being refused on them. A rule
refused again inside one chain is a real deadlock and stops with a sentence
saying so; a rule granted earlier and needed again is just work.

## A folder inside the project is not another place

`offerToOpen` asks about a *place*, and `.directoryAccess` is not rememberable, so
that card returns every session. Applied to a sub-folder of the project the
person already approved, it turned one Always into a per-folder grant: writing to
`Second-Brain/11-Experiments` asked to "work in that folder" although the folder
is inside `Second-Brain`. Refused folders that lie inside the resolved project are
dropped before the folder card is considered — one Always covers the project and
every folder under it. A folder genuinely outside it still asks, every time.

## What the project grant does not cover

A refused shell rule used to arrive as `.localWrite` whatever it was, so under a
project grant a refused `rm` would have been widened silently. `classOf` reads
the rule's command head instead: `rm`/`shred`/`dd`/`sudo` and friends are
`.destructive`, package managers are `.dependencyInstalling`, and
`git rebase`/`reset`/`push` are `.gitHistoryChanging` — three classes
`mayBeRemembered` refuses, so they are asked about every time even in a project
answered Always for. `mkdir` and `mv` stay `.localWrite`: renaming and creating
folders is the ordinary work of a vault, and making them ask was the friction
this whole area exists to remove.

## The scratch project's id is fixed, and is not a grant key

`scratchProject` was a computed `static var` whose `Project.init` defaulted
`id: UUID()`, so it minted a new identity on every read. Anything keyed to it
could never be found again. It now carries a constant id, and — more to the point
— `GrantSubject` makes "no project open" a case of its own, so no grant is looked
up against it and Always is not offered. The card says so rather than naming a
project called "no project".

## One key per project, and the key is the folder

A grant used to be `(projectID, toolID, actionClass)`, and `project.id` is a UUID
minted fresh by `Project.init` each time a folder is added. Remove a folder and add
it back and every Always given for it was orphaned silently. The owner's file held
**six** rows on 2026-08-22 of which **one** named a project that still existed;
another character's project list was empty while two grants sat beside it. That is
not an edge case — his Second-Brain Always was granted on 2026-08-20, lost when the
registry was rewritten on 08-21, and granted again on 08-22.

So a remembered grant is now one row, `StandingGrant(projectPath:)`, and the key is
the folder. `CanonicalPath` is the single place a path becomes a key —
`standardizedFileURL`, no trailing slash — so two spellings of one folder cannot
become two grants. The owner chose this shape explicitly (2026-08-22) over keeping
the id and merely cleaning up orphans.

**One yes covers the project, not a folder inside it.** Asked directly which he
wanted, the answer was: writing to the vault root or any sub-folder must never ask
again. So the standing half carries no tool and no class — it means "approved to
work in this project" — and the folder card is skipped for anything under it.

**What it still does not cover** is unchanged, and is the other half of the same
answer: reading and writing only. `noGrantMaySkipThis` is still consulted *before*
the grants, so `.destructive`, `.gitHistoryChanging`, `.dependencyInstalling`,
`.projectMemoryWrite`, `.externalNetwork`, `.browserAction` and `.directoryAccess`
can never be answered by the key, and a tool outside the project's own
`allowedTools` still asks. `permissionScopeSentence` had to change with it — it
promised "you won't be asked for this project again", which under this shape is
exactly the kind of overpromise `requestAgentAccess` was criticised for.

**The session half keeps its tool and its class.** "Once" must still mean only what
was asked, so `SessionGrant` stays `(path, toolID, actionClass)`. That asymmetry is
deliberate: only the remembered half is one-per-project.

### The migration reads the project list, and prunes only here

`FileStandingGrantStore.load` tries the new shape, and on failure decodes the old
one and maps each `projectID` through that character's `projects-<id>.json` to a
path. A row whose project no longer exists is **dropped** — its path is unknowable,
and inventing one would grant a folder nobody named. The result is written back
once, so this is a migration rather than something redone on every launch.

Pruning happens **only** during this migration, never on an ordinary load: an
external drive that is not mounted must not silently revoke anything.

Driven on the owner's own files, 2026-08-22: six rows became one for
`/Users/Olarn/AllWorks/Second-Brain`, and the four dead ids are gone. Two other
characters kept nothing, correctly — one had an empty project list, the other's
grant named an id its registry no longer had.
