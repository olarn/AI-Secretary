# LLMProvider

## The mask model

The app never authenticates to Anthropic itself. It launches the `claude`
binary the person already installed and signed in to, so the work runs on their
account and their subscription — and the app inherits Claude Code's real
capabilities (file editing, shell, web search, sub-agents, skills, MCP) instead
of the small tool set we could implement ourselves.

There is no second path. The app used to fall back to a Claude API key in the
Keychain, which meant a turn could quietly run on API billing instead of the
subscription, and meant two answers to "where did this reply come from". Now:
Claude Code, or an honest refusal.

- `ANTHROPIC_API_KEY` is stripped from the child environment for the same
  reason, even if the person happens to export one.
- **`--bare` must never be added as an optimisation.** It is the documented
  recommendation for scripted calls, and it skips the OAuth and keychain reads
  that are exactly the authentication this whole approach depends on.
- Conversation history lives in Claude Code's own session, resumed by id. Only
  the newest user turn is sent; re-sending our transcript would duplicate what
  the session already holds.

## Measurements that decide designs

### The warm process (2026-08-13, CLI 2.1.229)

Every turn used to be its own `claude -p --resume <id>` process: boot, config,
and the whole transcript read back with a cold prompt cache. Feeding one
long-lived process instead — `--input-format stream-json`, one user message per
line — took first text from **5.47s to 1.15s** at the real system prompt size.
The app itself was never the slow part; it spawns the CLI 0.04s after Return.

None of the launch flags can be changed on a running process, so a turn may
reuse the process it finds only if every one of them still matches.
`WarmProcessKey.canBeServed(by:)` **is** the invalidation mechanism — there is
no separate stale flag that could be forgotten at a call site.

Feeding the message down stdin as JSON also retired an old hazard: as a
command-line argument, a message beginning with a dash was read as a flag
(`unknown option '- A…'`), which is why it had to go last behind `--`. A JSON
string on stdin cannot be mistaken for a flag.

### OpenCode warm-up (2026-08-21, opencode 1.18.15 + a local 27B)

| | |
|---|---|
| opencode binary startup | 0.3s |
| loading the model (26.9 GB) | ~27s |
| prefilling opencode's 13,127-token prompt, cold | ~116s (~126 tok/s) |
| the same prefill once the cache holds it | 0.3s |

So keeping a *process* warm — the obvious idea — buys 0.3 seconds of a
two-minute wait and is not worth building. What costs the time is the model
re-reading the same 13k-token system prompt, and that is cached.
`WarmUpTarget`'s three fields are exactly what changes the cached prefix; the
directory is among them because opencode reads the project's own rules files
into the prompt.

**The warm-up flags have to match a real turn or it warms the wrong thing.** A
warm-up that leaves out `--dir` prefills a prompt no later turn will ever send,
and the person still waits the full two minutes. It deliberately omits
`--session` so a throwaway "hi" never appears in the conversation.

### Sessions survive a directory change (2026-08-06, CLI 2.1.220)

Changing the working directory used to drop the session, on the belief that
Claude Code scoped session lookup to the directory. Measured: a session created
in one directory resumes from another and still remembers.

The pre-emptive reset had to go because it silently beat Chat History.
Reopening a conversation adopts its session; resolving the project on the first
turn then moved the directory and threw the session away before it was ever
used — so the thread came back on screen with none of it behind the answers,
and nothing said so, because no resume was even attempted. Trying and failing is
strictly better: a session that really has gone comes back as `.staleSession`,
which starts a fresh one *and* says so.

The same measurement applies to `--chrome`: a session started without it and
resumed *with* it reports `claude-in-chrome` connected and runs its tools.
Dropping the session on a browser toggle cost everything said before it, and the
browser's tab group — which the extension binds to the Claude Code session, so a
new session is a new group in a new window. That was "it opens a new tab group
every time".

## Two different walls, and only one was ever noticed

The familiar one is the **permission** wall — "requested permissions", "requires
approval" — which a tool rule opens. The other is the **working-directory**
wall, worded nothing like it:

```
ls in '/Users/Olarn/Temp/ai-probe-watch' was blocked. For security, Claude
Code may only list files in the allowed working directories for this
session: '/Users/Olarn/Temp/ai-team-work'.
```

Captured verbatim on 2026-08-20. It matched none of the permission phrases, so
no `toolDenied` event was emitted, nothing was offered to widen, and **no card
was ever put in front of anybody** — the character said it had no permission and
the work stopped. It bites hardest with several characters, because a character
with no project open stands in the scratch directory, so *every* path into a
shared folder is outside her session. A tool rule cannot open this wall; what is
missing is the folder, `--add-dir`.

`firstQuotedAbsolutePath` takes the **first** quoted path because the sentence
names what was wanted first and what is permitted afterwards.

## Refusal phrases

`"require approval"` is in the list separately from `"requires approval"`, and
that plural was a bug all of its own: a command with more than one operation is
refused with *"The following parts require approval: …"*, which is not a
substring of the singular. Without it the refusal read as an ordinary failure,
so nothing was offered and the wall had no door — every `cd … && python3 …` the
owner tried landed there. Verified against Claude Code 2.1.229.

`"requires permission"` is admitted **only** for browser tools. The browser
tools word their refusal that way and matched none of the others, so a blocked
scroll or click was never recognised as blocked. The phrase is too broad to
admit generally: an unrelated tool failing for its own reasons would read as a
refusal and the person would be offered a grant for something that was never in
the way.

## One refused `Bash` call needs several rules

Claude Code splits a command on its shell operators and requires **every part**
to be permitted. One rule built from the head of the whole command authorises,
at best, the first operation, and the retry is refused exactly as before — the
person is asked, says yes, and watches the same wall.

The second half of the same bug was the head itself: it was the first two
space-separated tokens, so a quoted path with a space in it was cut in the
middle — `cd "/Users/…/TISCO - AI Sharing"` became `Bash(cd "/Users/…/TISCO *)`,
with the quote left open, matching nothing.

A lone `&` is not a separator worth splitting on: in `2>&1` it is part of a
redirect, and splitting there invented a rule for a sub-command called `1`.

## Why the tools she may never have are denied rather than left off

`--allowedTools` is an *auto-approve* list, so everything left off it still
exists and merely asks. `SendMessage` and `ListAgents` have to be denied
outright.

Driven on 2026-08-14: asked to get something from Pikachu, Ditto called
`ListAgents`, went looking with `ToolSearch`, called `SendMessage`, and told the
person **"ส่งสำเร็จแล้วครับ! ข้อความไปถึง Pikachu (session my-mcp-server-80)"** — a
confident report of something that never happened, addressed to a Claude Code
session with nothing to do with the character of that name. Pikachu, of course,
said nothing. No wording in a prompt makes a tool that is right there stop
looking like the answer. The relay between characters is the app's job, and this
is what keeps it the app's job.

## Why the browser connection exists, and why read and act are split

`WebFetch` retrieves a URL from this app's own process, with no cookies and no
session, so a page behind a login answers it with the sign-in page — the
assistant reads something real and reports something wrong. The Claude in Chrome
extension reads the rendered tab in the browser the person is already signed
into; the password never comes near us, an open session is borrowed.

That is also why the split matters. The same connection that reads an
authenticated page can type into it, and the page text feeding the model is
untrusted input that may carry instructions of its own. Reading is cheap and
reversible; acting is neither.

`tabs_context_mcp` is on the read-only list for a practical reason: without it
the model cannot find the tab the person is looking at. Its `createIfEmpty` flag
can open a blank tab — the one state change that list admits.

`mcp__claude-in-chrome__computer` is described as "scroll, click and type"
rather than as whichever of those was asked for: one tool covers all three and
`--allowedTools` cannot express argument-level rules, so labelling narrowly
while granting broadly would be a lie.

## OpenCode is not gated by the approval cards

Measured 2026-08-21 against 1.18.15: `run` created a file with no permission
prompt and no refusal event, so there is nothing for the app to turn into a
card. The containment is the working directory passed as `--dir` and nothing
else. The owner decided to ship it on those terms with the Profile panel saying
so plainly — do not quietly present it as equivalent to the Claude path.

`prepare` accepts `additionalDirectories` and `allowedTools` and does nothing
with them because opencode has no `--add-dir` and no allowlist flag.

opencode has no `--append-system-prompt`. Its equivalent is `--agent`, which
means a file the user has to write and keep in step with a profile they edit in
this app — two places for one personality. Prepending the system text to the
message is the honest alternative and it is not free: the model sees the
instructions as something the user said, which is weaker than a real system
prompt. Without it the persona never arrived at all (2026-08-21).

## `PATH` is not usable from a bundled app

An app launched from Finder inherits launchd's environment, where `PATH` is
unset — the process gets `/usr/bin:/bin:/usr/sbin:/sbin`. The standard Claude
Code install lives in `~/.local/bin`, which is not on that list. Worse, the
things Claude Code then launches — an MCP server started with `node` or `uvx`, a
Bash command calling a Homebrew, nvm, mise or pyenv tool — all need the user's
real `PATH`. Observed failure this fixes: a stdio MCP server configured as
`node …/build/index.js` reported `status: "failed"` from the packaged app while
working fine from a terminal.

A **login** shell is required to read it: a non-interactive one skips the profile
that sets up version managers.

## The four things a process that outlives a turn has to get right

1. Its output is one stream, read in turn-sized pieces. The iterator is held on
   the process, not made per turn, or the second turn would start reading a new
   stream from a process that only ever had one.
2. Its stderr is drained continuously. A pipe nobody reads fills up, and a child
   blocked writing to a full pipe hangs forever. Over a one-turn process that
   never happened; over one that lives all afternoon it would.
3. Death is noticed on the way in. Writing to a dead process's stdin raises
   rather than hanging, which is what lets the caller retry once.
4. Ending it is explicit, so a stopped turn, a changed workspace and a
   torn-down character all end a session through one method.

## Two blocks of text with nothing between them

A turn is not one piece of writing: the model says something, reaches for a
tool, says something else, and each is its own content block. The deltas carry
no hint of where one ends, so joining them gave
`…/grill-with-docs เองได้เลยนะNo existing note on this.` — two thoughts with not
even a space between them, because there was never a character there to begin
with. `.textBlockBegan` is that missing character, and both readers emit it.

## Session loss is announced, never swallowed

Reopening a conversation from history puts the whole thread back on screen, so
if the model's memory of it has expired, every following answer is written by
someone who cannot see what is plainly visible to the person reading. Silently
starting over is the one outcome indistinguishable from the app having broken.

## What a `ChatBackend` must not inherit by default

`currentSessionID` and `adoptSession` had default implementations on
`WorkspaceScopedProvider` for a while, and `ChatBackend` — the only conformer
the app actually runs — silently inherited them. Every conversation was archived
with no session, so reopening one restored the words and nothing else, while the
tests passed because the test double implemented them properly. `installSkill`
was the same shape: `ClaudeCodeProvider` always conformed to `SkillInstalling`,
but the object the orchestrator holds is the wrapper, which did not, so the
`as? SkillInstalling` test failed every time and the character answered "I can't
install skills without Claude Code" with Claude Code sitting right there.
Nothing surfaced it, because the refusal is a plausible sentence.

`ChatBackend.adopt` guards on the Claude runtime because what arrives there is
where *Claude Code* was found, while the factory is whichever maker the
character is set to — without the guard, a character switched to OpenCode would
be handed an OpenCodeProvider pointed at the `claude` binary.

## `claude auth status` carries more than the tier

The reply includes the user's email, organisation id and organisation name. Only
`loggedIn` and `subscriptionType` are ever read out of it, and nothing may log
or return the rest. Widening what is read is how a support paste ends up
carrying somebody's address.

An unreadable reply is refused as *unreadable*, never as signed out: telling
someone to sign in when they already are sends them somewhere that cannot fix
it.

## Cache token counts are not a rounding error

`ChatUsage` keeps cache writes and reads as separate fields because they are
priced differently and because leaving them out made the reported figure useless
on any real turn: a turn reported as 2 in / 5 out really moved 11,768 cache
writes and 24,436 cache reads.
