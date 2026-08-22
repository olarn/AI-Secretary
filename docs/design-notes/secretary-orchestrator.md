# Secretary (the orchestrator)

The orchestrator — the one impure object in the domain, and the file that held a
third of the repository's comments. Everything below was written beside the code
it explains, and is kept verbatim rather than summarised.

Read the section for a method before you change it. Much of what follows is a
record of something already tried that did not work, with the input that showed
it: a `Secretary` method that looks needlessly roundabout is usually one whose
direct version is described here as a bug.

Conditions a comment used to name now read as names in the code —
`checkingNowWouldTalkOverAReplyOrOverItself`,
`neitherWallHasAnythingLeftToOpen`,
`aDraggedInFileIsACompleteRequestOnItsOwn` — so what remains here is only what a
name could not hold.

The text runs in file order, so a paragraph's neighbours are the paragraphs that
were next to it in the source.

## Secretary.swift

`text` is a `var` so a streamed reply can grow token-by-token in the same
entry rather than appending one per token.
What this entry is. Activity sits in the conversation in order, so you
can see what happened before an answer, but it is not an answer and the
UI renders it differently. A failure is not an answer either — it is the
app reporting that it couldn't get one — and looking like one is how
"Can't reach Claude Code" gets read as something the Secretary said.
`divider` marks where one conversation ended and the next began. It is
not a message — nobody said it — and it is the only kind that exists to
be a line rather than words.
Set at the end of a turn that failed, so it is a `var`: the entry exists
from the first streamed token, long before anyone knows how it ends.
Who said it, named at the time — not looked up later.

The transcript used to render every reply under the *current* profile's
name, so switching from Ditto to อาเนีย rewrote the whole conversation:
answers Ditto had given were suddenly signed อาเนีย, which reads as the
app having forgotten who it was. A name is a fact about the moment the
line was written, so it is stored with the line.

Empty for the user's own turns, which render as "Me" and have no profile
behind them.
A tool operation the Secretary can run through the approval pipeline: either
a read-only Git command or a read-only file access. Both are `.readOnly`, so
they share the same approval and audit path.
Read a file and send it to the model. `.externalNetwork`, so unlike the
other two this always stops for approval.
Read a file and work out the steps it asks for. `.externalNetwork` like
`understand`, and asked every time for the same reason — plus the plan
it produces is shown before any of it runs.
Watch a path and say when it changes. `.readOnly` — repeated local
reading, nothing written and nothing sent.
Let Claude Code work inside a project, then answer this prompt. Approved
once per project — asking before every message would make the assistant
unusable, so the prompt has to be explicit about what the grant covers.
Re-run a turn with extra tools after Claude Code was refused them.
`.localWrite` — the door to changing the user's files, so it is asked,
but the answer may be kept for the project: see `mayBeRemembered`.
Re-run a turn with another folder open to Claude Code, after it refused
a call for pointing outside the session's working directories.

Not the same as widening tools, and no tool rule substitutes for it:
what was missing is `--add-dir`. See `isDirectoryRefusal`.
Install a skill the assistant says it needs, then ask again.
`.dependencyInstalling`, so it is asked every time: this puts software
on the person's machine.
Keep something about this project in its Claude Code memory.
`.projectMemoryWrite` — its own class precisely because it writes
*outside* every registered project, into the directory the person's own
terminal sessions read back, and so may never be remembered.
Approve-once: the grant is per project, and the prompt says so.
Something typed while a turn was running, kept whole until its turn comes.

The files travel with the words because they were handed over together. A
queue of strings dropped them: the attachment was taken off the list when
the person pressed Return, and the message that finally ran mentioned a
spreadsheet nobody had sent.
The errand this message is answering, when it arrived from another
character rather than from the person.

It rides in the queue for the same reason the attachments do: by the
time the message runs, whatever was known when it was accepted is gone,
and an answer with no errand behind it has nowhere to go back to.
Whether the app queued this itself — a watch follow-up, or the nudge
that breaks a permission deadlock.

Only the announcement depends on it: "Now, the one that was waiting:"
credits the person with typing something, and they typed none of these.
Errands sent together, and what to do when their answers are in.

Held by the character who sent them. The follow-up is the person's own step
2, kept here rather than forwarded: the characters answering step 1 were
never asked to do it, and half of them could not if they tried.
Who is still to answer, by correlation id and name.
Sent to, then never answered — or never reachable at all.
A hand-off that needs the person to say who it is for.

The words are kept whole so that answering the question runs the request
that prompted it, rather than the single name that was picked.
The person's later steps, if they numbered them. Kept across the
question so that answering "Pikachu" still leaves step 2 to be done.
The state of one streaming reply, threaded through the handlers as a value.

It was five locals captured by a 160-line closure, which is why every arm of
that switch had to be read together to know what any one of them did. As a
value it is the accumulator of a fold: each handler takes the current run
and returns the next one, and only the stream loop holds it in a variable.

`reply` is the whole turn — what the conversation remembers and what the
fenced blocks are read out of — while `segmentText` is only what belongs in
the bubble being written now: a reply is one bubble per stretch of talking,
split wherever a tool ran.
The profile that was active when the reply started.
The bubbles of this turn that are already finished, in order.

Not derivable from `reply`, which is deliberately one continuous answer
— the conversation has to remember the turn as one thing said, and a
test pins that. The seam only exists on screen, so anything that wants
the turn *as the person saw it* — the notification banner, so far — has
to be told where the bubbles were. Without it a turn that answered
"done" and then added a line came out of `reply` as one run-on word
(driven at 0.19.288).
Every bubble of this turn, the one being written included.
The bubble being written is finished; the next words open a new one.
The next words go into this (freshly appended) transcript entry.
Collected rather than acted on immediately: the turn keeps going and
may be refused several things, and one prompt listing all of them beats
a stream of them.
A request waiting on the user: either confirm an action, or pick a project.
The steps read out of an instruction file, waiting to be confirmed.
Nothing from the file has been acted on at this point — the plan is
shown in full, with anything the scan flagged, and the run starts only
if the person says so.
Something was typed while a request was still in flight.

It used to just take over: the running turn was killed and the new
message ran in its place, with no warning and nothing said about the
work thrown away. Both answers are reasonable — wait your turn, or drop
that and do this — and which one is right depends on what the person
meant, which only they know.
`candidates` are the characters who were free when the card was drawn —
one button each. Carried on the decision rather than fetched by the view
at draw time, so the card cannot redraw itself into a different set of
buttons while somebody is deciding which one to press.
A link arrived in chat and the assistant is being asked whether to go
and work in that site as the person. Nothing has been opened yet.
The three answers to "I'm still on the last one".

A type rather than a `Bool` plus an optional second argument: the third
answer carries *who*, and a boolean cannot say that without a companion
parameter which is meaningless whenever the boolean is true.
Orchestration layer. Interprets a message, resolves context, applies policy,
and invokes a tool — or, for conversational messages, streams a reply from
the Claude API. Drives the shared `AssistantState` machine so the character
UI reflects real work.

`@MainActor` because every mutation here feeds an `@Observable` SwiftUI view;
the chat provider does its network work off the main actor and this type
consumes the stream back on the main actor.
Conversations that have been put away, newest first.

Survives quitting, unlike the live transcript: the point of a history is
that it outlasts the session, and one that emptied itself on relaunch
would be a list of things you could already scroll to.
The sub-agent running right now, if one is.

Observed by the header so the wait has something attached to it. One at a
time, not a list: Claude Code runs the `Agent` tool to completion before
the turn goes on, so a second starting means the first has ended — and a
list nobody can empty is how a stale badge outlives the work it describes.
What the assistant is doing this turn, newest last. Collected whether or
not it is being shown, so switching it on mid-turn isn't blank.
Whether activity is woven into the conversation. Hidden on a first run
and remembered after that, so the choice survives quitting.
Whether the assistant is connected to the user's Chrome.
Files handed over for the next message, waiting above the input.

Observed because they are on screen with an × each: something the person
attached and can't see attached is something they will attach twice.
What the assistant has asked for a file for, when it has. Shows the
open-file button; cleared as soon as one is chosen or the person moves
on, so a button offering to pick "the spreadsheet" never outlives the
question that wanted it.
Files she has just made and is offering to hand over. The mirror of
`fileRequest`, and cleared at the same moments and for the same reason:
an offer belongs to the turn that made it, and a Save button left over
from three answers ago points at a file the conversation has moved past.

Session-only and never written to disk, like the loop and the grants:
the scratch folder is cleared out from under it by anything, and an
offer that survived a relaunch would be a button for a file that is no
longer there.
The standing check-back, when one is running: every so often the
Secretary asks itself the question the user left standing, and answers
into the conversation. Observed so the panel can show that it is on and
offer one click to stop it — a timer that talks must be visible.
Tokens and cost so far. Observed, so the usage window can be left open
and follow along instead of showing a figure from whenever it was opened.

Per session, not per lifetime: the number people want is "how much of the
context have I filled in this conversation", and a running total that
survived restarts would answer a question nobody asked.
Called when a reply asked for a pane to be pinned. Set by the app layer,
which owns the windows; the Secretary only recognises the request.
The last request the assistant said it could not finish. Put back in
front of the model on the next turn, then cleared once a turn completes
without declaring itself blocked.
Absent means "whatever the backend is already set up to use" — for
Claude Code that's the model and effort from the user's own settings.
Skills found under `~/.claude/skills` and each registered project's
`.claude/skills`. Refreshed on demand rather than watched, since a
skill installed mid-session is the rare case, not the one to optimise.
Which of `availableSkills` this session is restricted to. Empty means
no restriction — the ordinary, unconstrained case. Session-only, like
`activeLoop`: a restriction that outlived the session that asked for
it would apply itself to a conversation nobody chose it for.
The instruction file being carried out, when one is. Observed so the
panel can show which step it is on and offer one click to stop — a run
that keeps sending turns on its own has to be visible while it does.
What each instruction file said the last time it was run this session,
so a second run can point out that the steps have changed. Session-only,
like the run itself.
Where the running plan's file lives. Kept beside the run rather than
inside it: the run is a value, and a `Project` is context.
Set while the turn that reads an instruction file is in flight, so its
reply is treated as a plan to confirm rather than as an answer.
The folders and files being watched. Observed for the same reason as
`activeLoop`: something that speaks without being spoken to has to be
visible while it's armed, with one click to stop it.

A list, because the two useful cases run together — a folder for files
appearing, a document for edits — and making them exclusive meant
starting the second silently replaced the first.
Who the assistant is. The user can switch profiles while a conversation
is open, so this changes at runtime — see `apply(profile:)`.
Which project/tool pairs the user has approved this session.

A value inside the store rather than a policy object holding its own
mutable set: there is exactly one copy, it lives beside everything else
the UI renders, and the decision itself is a pure function of it.
How a message becomes an intent. A function, not a protocol: there is
one thing to do here, and a test hands in a closure instead of building
a fake.
How installed skills are found. A parameter rather than a hardcoded
call to `SkillDiscovery.discover`, so a test can supply a fixed list
instead of whatever happens to be installed on the machine running it.
Where the grants that outlive this conversation are kept. Read once at
startup and written the moment one is added, so the file is the record
rather than a copy that has to be flushed.
How a note reaches the project's memory directory. A closure for the
same reason as `discoverSkills`: the real one writes into the person's
own `~/.claude`, which is not somewhere a test may go.
The user's own words for the request in flight, so a completed tool run
can be written into the conversation as a real exchange.
Last project actually worked in, so follow-up commands don't need
"in <project>" repeated on every line.
The name of the project she has open, for the roster the other
characters see. The name and nothing else — `CharacterCard` carries no
path on purpose, so knowing where someone is working never becomes
access to it.
Where a turn would run if one started now — the open project, or the
scratch directory when none is open.

The same expression `prepareWorkspace` uses, exposed because a maker
whose prompt is built from the project's own files has to be warmed in
the directory the next turn will actually use; warming elsewhere prefills
a prompt nothing will send.
Sites the person has agreed the assistant may work in, this session.
Whether anything has been staged, so the backend is only pointed at the
staging folder once there is something in it — `--add-dir` on a folder
that doesn't exist is an argument the CLI has to reject.
This turn's activity entry. Without it, a later turn would find the
previous turn's box by kind and overwrite that history instead of
starting its own.
Which row in the history menu the conversation on screen *is*.

Set when a conversation is reopened from history, and minted on the
first turn worth filing otherwise — because a conversation is now filed
as it goes rather than only on the way out. Either way it is what makes
the next turn update that row instead of adding a second one, and what
ticks the row you are already in.
The transcript entry the current reply is being written into.
Wakes up to see whether a loop check is due. Lives here rather than in
the view so a loop keeps running with the chat window closed — the
person who asked for it is looking at a room, not at the screen.
How often the timer looks at the clock. Far shorter than any allowed
interval, so a check lands within seconds of when it was due, and cheap
because looking is a comparison.
Looks at the watched path. Its own timer rather than the loop's: the two
are unrelated, and one running must not depend on the other.
Largest file, in bytes, that may be sent to the model in one turn. Well
under the adapter's local read cap: bytes shown on screen are free, bytes
on the wire are not.
How much of a tool's output is carried into the conversation so later
questions can refer back to it. A directory listing or `git log` is
unbounded; a chat turn is not.
How much of a file read with `read <path>` is carried into the
conversation. Larger than a listing because a file is the point of the
question, but still bounded: whatever lands here is re-sent on every
later turn of the session.
Ceiling on the whole remembered conversation. Oldest turns fall off first.
In memory unless told otherwise, and the app says otherwise.

The default used to be the real file, and the first run of the suite
wrote nine test conversations into the owner's own history. A default
that reaches the user's data is a default that a test has to remember
to override, and the ones that forgot were the ones that had nothing
to do with history.
Nowhere by default, for the same reason as the history store: the
real one copies the person's files onto disk, which no test should
have to remember to opt out of.
The real one writes into `~/.claude/projects/<slug>/memory/`, which is
the person's own Claude Code memory and not a directory a test may
touch. Unlike the history and attachment stores there is no in-memory
twin to default to, because there is nothing to read back — so the
default is the real one and every test passes its own temporary home.
Nowhere by default, like the history and attachment stores: a default
that reaches the person's own remembered permissions is one a test
has to remember to override, and permissions are the last thing that
should be granted by a suite that forgot.
Nowhere by default, for the same reason as the grant store above.
Whichever model she was told to use, put back before the first turn
can be sent — a character who came back on "Default" every morning is
the bug this fixes, and the badge is the only place it showed.
What was remembered on an earlier run, put back before anything can
ask. A file that won't load reads as nothing remembered: the cost is
one card the person has already answered, and the alternative is
starting up believing in permissions nobody can see.
A history that failed to load reads as an empty one. The alternative
is refusing to start over a file of old chat, which trades the whole
app for the part of it that remembers.
The provider is told at startup, not only when the switch is flipped:
a preference that survives quitting has to survive relaunching too.
MARK: - Skills

Re-scans for installed skills, and drops any selection that no longer
names a real one — a skill can be removed on disk while its session is
still open.
MARK: - Entry point

Dragging a file in and pressing Return is a complete request — the
file is the message. Requiring words as well would leave the person
typing "here" to send what they had already handed over.

Typing instead of answering drops whatever was waiting — but not
silently. It used to vanish, and the next reply then claimed the
thing had been set up: the assistant had asked for a watch, the card
was dropped by this very message, and it answered "เฝ้าอยู่เหมือนเดิมค่ะ"
with nothing watching. The note goes into the conversation as well as
the transcript, because the model's belief is the half that produced
the false claim.
The files ride with this message and this message only. Taken off the
list here, before anything can fail, so a refused or queued turn
never leaves them attached to the *next* thing typed.
The previous answer's offer goes with the previous answer.
Local commands first: never hit the network or the state machine.

Before the busy check, deliberately: passing something to another
character is not work for this one, so there is nothing to wait for.

Runs a message now, or asks whether it should wait.

Slash commands are handled above this on purpose: `/watch stop` and
`/run stop` are how you call something off, and they have to work while
that something is running.
The message as the model receives it: what was typed, plus where the
staged copies of any attached files are.

The paths go to the model and not to the screen. On screen the person
sees the names of their own files, which is what they handed over; a
line of Application Support path is noise to them and the address the
assistant needs.
Everything `submit` does once it is settled that this message runs now.
A link is a request to go somewhere, and where it goes is someone
else's site holding the person's signed-in session. Asked here rather
than in `submit` so the question is put whichever way the message
arrived — typed, queued behind a running turn, or picked from a list
of choices.

What the model is answering, which is the typed words plus where the
staged files are. Classification below sees only what was typed: the
note is a list of paths, and one read as a command turned "read this"
into a request to open a project called "what they asked:".
A backend that can open the folder itself does not need the
classifier, and is actively harmed by it.

The rules were written when the backend was a bare API with no hands
(`Intent.swift` still says "for this sprint"). Against Claude Code
they cause three things. The local adapter's answer never enters the
model's session — only the latest user message is sent, then
`--resume` — so "diff in X" followed by "explain that" leaves the
model with no idea which diff, the same class of bug as answering
"there's nothing to summarise yet" with the answer on screen. The
keywords are English-only, so "อ่าน README.md" got the capable path
and "read README.md" got the limited one — behaviour split by which
language you typed. And the adapter is simply worse at the job the
agent is already instructed to do for itself.

Asked of the same value `systemPrompt` uses to choose `agentPrompt`.
They must not diverge: a prompt telling the model it has hands, on a
turn the adapter intercepted, is a promise the app then breaks.

**There is a window where this is false and the classifier still
runs**, and it is deliberate. Detection has usually not finished when
the app opens, so the first message or two after launch take the
fallback path. That is the correct behaviour for a moment when
nobody yet knows whether Claude Code is there — not a bug, and not
something to hold the turn waiting for.
MARK: - Decisions

Messages typed while something was running, waiting their turn.

Session-only, like the grants and the watches: a queue that survived a
relaunch would fire work nobody was there to see asked for.
MARK: - The other characters on the desktop

Who else is here, asked afresh at the start of every turn.

A closure rather than a stored array so it cannot go stale: a character
added, renamed, or moved to another model between two turns is in the
next prompt without anyone having to remember to push it across.
Hands a message to whoever does the delivering — `CharacterBus` in the
app, a closure in tests. Unset means she is the only one here.
Told each time a turn comes to rest, so the app can put a banner up for
work that finished while nobody was looking. Whether it deserves one is
`completionNotice`, not this — she reports, the app decides, because
only the app knows whether her chat is on screen.
Told each time a permission card goes up, so somewhere other than her
chat panel can put the question in front of the person. See
`ApprovalAsked` for why: commanded from the command window, she would
otherwise wait on a card nobody was ever shown.
Told when that card is gone, however it went — answered here, answered
in her chat, or dropped because the person typed something else. A
listener drawing buttons for it has to take them away, or it offers an
answer to a question that is already settled.
Errands sent and not yet answered. Session-only, like the grants and the
queue: one that outlived a relaunch would have nobody left to answer it.
The errand this turn is answering, when it came from another character
rather than from the person.
A hand-off waiting on the person to say who it is for.
Answers that have reached the screen but not yet the character.

`ClaudeCodeProvider` sends **only the newest user message** — Claude Code
holds the thread itself and is rejoined with `--resume` — so appending an
arriving answer to `conversation` puts it somewhere nobody reads. Driven
on 2026-08-14: two characters answered, both answers were on screen, and
asked to summarise them Miku said *"ยังไม่มีอะไรให้สรุปเลยค่ะ — เรายังไม่ได้คุย
หรือทำงานอะไรกันในเซสชันนี้เลย"*. She was right about what she had been told.

They ride along with whatever is said next instead, which costs no extra
turn and reaches her at the moment she needs them. Answers belonging to a
plan are not held here — the follow-up prompt quotes those itself.
Whether anything passed between characters in this conversation.

The other reason a conversation is worth filing. Hers may contain no
`.user` turn at all — a whole exchange can be somebody else's errand,
arriving, being worked and being answered, with the person who owns the
desktop never typing a word into it.
Errands sent together, with the person's own next step waiting on them.
Gives up on whoever has not answered, so one silent character cannot
hold the person's step 2 for the rest of the session.
How long to wait for an answer before carrying on without it.

Injectable for the same reason a clock is: the behaviour worth testing
is what happens when somebody never replies, and a test that has to wait
fifteen real minutes to see it is a test nobody runs.
What is waiting, in words. The files waiting with them are the queue's
business, not the panel's — it counts them and shows what was typed.
Whether the queue is held. The running turn can't be paused — it is one
invocation of a CLI and there is nothing to pause — so this is the only
pause there is: nothing new starts until it is let go.
Ends this conversation and starts a fresh one.

The session-level cancel. Stopping a turn only ends what is running;
this ends everything that is standing — the queue, the loop, the run,
the watches — and drops the context the model has been answering from,
which is the part that has no other way out. Without it, a conversation
that had gone wrong could only be escaped by quitting the app.

The screen is cleared, and what was on it goes into the history menu
first. Until there was a history this cleared nothing — wiping words the
person had read, with no way back to them, is destroying their work to
tidy up. Now there is a way back, so the clean slate is a clean slate
rather than a loss.
Put the old one away before anything is cleared — including after
`stopCurrentTurn`, so the archived copy carries the "(stopped
part-way)" mark the person last saw rather than a reply that looks
like it finished.
Sites go with the tools that reach them. A conversation about one web
app is over; the next one starts by asking again, which is the whole
point of the grant being session-shaped.
The copies were taken for this conversation. Keeping them would leave
someone's spreadsheet in Application Support for as long as the app
is installed, for a conversation that is over.
Session-only, like the grants above. An errand outstanding across a
new conversation would report an answer into a transcript that no
longer holds the question, and a hand-off waiting on a name would be
answered by the first thing typed in the fresh one.
The backend keeps its own thread; ours going quiet is not enough.
The conversation that was on screen has been filed; what comes next
is a different one and mints its own id on its first real turn.
After the clear, so it survives it. The person has just lost the
conversation from the screen; being told it also didn't reach the
history is the whole point of saying it.
MARK: - Chat history

Files the conversation on screen under the history menu, and keeps it
filed as it grows.

Called at the end of every turn as well as when a conversation is put
away. It used to run only on the way out, which meant the history menu
showed nothing until you had started a *second* conversation — the one
you were having, the only one you might want to reopen after a crash,
was the one that wasn't there. Archiving keeps the same id, so a
conversation updates its own row rather than growing a new one per turn.

Does nothing when nobody said anything, so opening the app and pressing
New Conversation twice doesn't push two blank rows in front of ten real
ones.
Held from here on, so the next turn updates this row. Also what makes
the menu tick the conversation you are actually in.
Keep the title a reopened conversation already had. It was derived
from its opening message, which hasn't changed, and re-deriving it
would let a menu row rename itself for no reason the person can see.
Reopens a conversation: its words back on screen, and Claude Code's own
thread picked up where it was left.

The two can come apart. The words are ours and always return; the memory
is Claude Code's and may have been cleaned up since. That is not
knowable from here — it only shows up when the next turn tries to resume
— so this promises the transcript and nothing more, and the turn itself
says if the memory turned out to be gone.
`newConversation` filed whatever was on screen and left its own note;
this conversation replaces that note rather than following it.
The thread ran somewhere else. Its memory is of that project's files,
while any tool now would run in the current one — worth saying before
an answer confidently describes the wrong directory.
The chat-side way in, for the same reason `/new` exists alongside the
menu item: the keyboard shouldn't have to reach for the menu bar.

Numbered rather than named — titles are the user's own sentences, and
matching a typed fragment against them would reopen the wrong
conversation often enough to be worse than useless.
The history menu's rows, decided here so the menu only draws them.
Empties the history menu. The conversation on screen is not one of them
and is left alone.
Writes the history out, and hands back what to tell the person if it
didn't work rather than saying it here.

Returned instead of appended because of where this is called from:
`newConversation` archives and then clears the transcript, so a warning
written at this point is deleted two lines later — the person would lose
the conversation *and* the notice that it hadn't been saved. The caller
knows when the screen has settled.
Answers the card that appears when something is typed mid-flight.

An enum rather than the `Bool` this used to take. The moment a two-way
answer grew a third, a boolean could only have carried it as a second
parameter that is meaningless unless the first is false — which is the
same trap the charter records for the arrow keys: one key, one owner, one
type that can say all of what it means.
The queue is normally pumped when a turn ends. If this turn ended
while the card was still on screen — which is ordinary, the card
waits as long as the person does — that moment has already gone,
and nothing else would ever start what was just queued. Found by
driving it (0.18.282): the badge sat at 1 for ever, after she had
said out loud that she would come to it.

Safe to call unconditionally: `dispatchNextQueued` refuses while
busy, paused, or with a card still open, so this is only ever the
already-finished case.
Before the stop, deliberately. `stopCurrentTurn` writes its own
line about the work being thrown away, and that line only makes
sense underneath the answer that ordered it.
The third answer: give it to a character who was free.

Freeness is re-read here rather than taken from the card. The card is a
snapshot from when it was drawn and the person may have sat with it for a
minute; every character lives on this actor in this process, so asking
again costs nothing and is exact. Handing work to somebody who has since
started something would break the only promise the button makes.

On refusal the card comes back with the *same* candidate list minus
nobody — `delegationCandidates` re-filters it, so if she was the last one
free the card returns with two buttons and the person is not offered the
same dead end twice.
Asked again rather than dropped: the message is still
unanswered, and silently keeping it would leave the person
believing it had gone somewhere.
Drops everything waiting. Said out loud, because a queue disappearing
quietly is indistinguishable from a queue that ran.
Stops whatever is in flight.

The half-written bubble is closed off here rather than left looking like
a finished answer, and what was said before the stop joins the
conversation: the person can see those words, so the model has to know
it said them or the next turn will contradict the screen.
Starts the next waiting message, if this is a moment to start one.
Set before the turn starts, so that when it ends the answer knows
which errand it belongs to.
MARK: - Passing work to another character

Whether this message was about somebody else, and has been dealt with.

This is the one place prose is read for an action, and it is allowed to
be because of what it does when it is unsure: it asks. The charter's
rule is not "never read prose", it is never *act* on a guess.
A numbered request is a plan: step 1 goes out, the rest waits here
for the answers. Forwarding the whole thing sent step 2 to the people
who were only ever asked step 1.
Asks in the conversation, using the same marked block the assistant uses
for its own questions — so the picker, the arrow keys and the "send the
option's own words" rule all work already, with no new UI.
Typing something else instead of picking drops the hand-off —
said out loud, for the same reason dropping a pending decision is:
a request that quietly evaporates is indistinguishable from one
that was carried out.
Her own ```to block: a name she typed, matched against who is here.

An unrecognised name is said out loud rather than guessed at. She has
the roster in front of her, so getting it wrong means she meant somebody
who is not here — and picking the nearest spelling would send the
person's work to whoever happened to sort first.
Whoever was named and is here still gets it. Refusing the lot because
one name was wrong would lose the part that was right.

Sends one errand to one or several characters, and remembers the
person's next step if there is one.

Whoever cannot be reached is dropped from the plan *here*, before any
waiting starts, and said out loud — the person asked two people and is
owed the news that it became one, at the moment it became one rather
than fifteen minutes later.
Nobody took step 1, so there is nothing for step 2 to work
from. Better said now than attempted on no data.
Files an answer against the plan waiting on it, and runs the person's
next step once nobody is left to hear from.
Gives up on whoever has not answered by the deadline and carries on with
what did arrive.

The person's instruction was to go on once the answers were in; one
character that never replies must not turn that into never.
Runs the person's later steps, once the answers are in or time is up.
Something another character on this desktop has sent her.

An errand joins the ordinary queue rather than interrupting: the person
talking to her now did not ask for their turn to be pushed aside, and
the queue already knows how to hold something whole until its turn.
Whatever else happens, something passed between characters here — so
this conversation is worth keeping even if the person never types
into it.
Taken, not refused. She is mid-something for the person in
front of her, and pushing that aside for another character's
errand is not hers to decide.
Told back, because a queue and being ignored look identical
from the other end.
Only news, never an answer: the errand stays outstanding and the
plan keeps waiting. The clock restarts, though — somebody has it,
and timing out work that is genuinely queued would be wrong.

Whether this belongs to a plan has to be asked before
`collect` takes it: the follow-up quotes those answers
itself, and holding them here as well would say
everything twice.
Held for the next thing said to her, not appended to
`conversation`: the person can see the answer, so she has
to know it arrived or her next turn will contradict what
is on screen.

Writes the conversation out now, without a turn having ended.

Everything else that reaches the transcript arrives during a turn, and
`finishChat` files the conversation on its way out. The relay lines do
not: forwarding an errand deliberately costs the sender no turn, and an
answer arrives while she is idle. Left alone they lived in memory only —
found on 2026-08-14 by grepping the saved conversations, where every
character who *received* an errand had the line (a turn ran right after)
and no character who *sent* one did. The hand-off being in writing on
both sides is the whole promise; in writing until quit is not it.
Sends this turn's answer back, when the turn was somebody else's errand.

Called for every ending, including a failed one: a character left
waiting on an answer that is never coming is worse than being told it
went wrong.
Which buttons the card in front of the person should carry.

Asked of the Secretary rather than worked out in the view, because the
answer needs the registry — Always is only on offer for a project that
was actually registered — and `AISecretaryApp` is never linked into the
test bundle. Empty when nothing is waiting.
The two-answer door, kept for the callers that only ever meant yes or
no. Yes is `.once` — the answer that changes nothing beyond this
conversation.
Said before the work starts, not after: the answer is the last thing
the person did, and a record of it arriving underneath the result
reads as something the app decided once the work was already done.

Whether Always actually kept anything is checked rather than assumed.
The card only offers it when it can be kept, but `remember` refuses a
tool outside the project's allowlist as well, and a line claiming a
grant that policy will ignore is the worst of the three outcomes.
Writes down what the answer said to keep, and nothing more.

Never for a tool outside the project's allowlist, even a read-only one.
`requireApproval` re-asks for those before it ever looks at the grants,
so a recorded one would leave the session holding a permission that
policy ignores — the kind of state that reads as "already agreed" to
whoever looks next.

The class decides whether anything may be kept at all
(`PermissionAnswer.duration(for:)`), which is what stops Always from
reaching the charter's approval list. Only the standing half is written
out; a session grant that reached disk would be the bug the two sets
exist to make impossible.
MARK: - Files handed over

Takes a file the person dropped on the input or chose from the panel.

Refusals are said in the chat rather than swallowed: a file that lands
nowhere and says nothing is one the person believes they sent.
The button was asking for exactly this; leaving it up would
invite a second copy of the same file.
Puts the open-file button away without choosing anything.
Takes the names out of a ```save-file block and turns the ones that
survive `offeredFile` into the card.

**Only when the turn ran without a project.** A file written into a
project the person registered is already where they asked for it, and
offering to save it somewhere else would be a button for work that is
finished — it would also fire on ordinary code edits. The scratch folder
is the case the feature exists for: under Application Support, where the
result is otherwise stranded.
Puts the save card away. The files stay where they are — this dismisses
an offer, it does not throw anything out, and asking her again brings
back a fresh one.
MARK: - Working in a web app

Raises the card when a message carries a link to a site that hasn't been
agreed to yet. Returns whether the turn should stop and wait.

A site already granted this session goes straight through: the person
answered that question, and asking it again per page would turn the card
into something to dismiss rather than read.
Answers the site card. Approving grants the host for this session and,
when it was off, connects the browser — then runs the message that
raised the question, so nothing has to be typed twice.
Opening the page is the first thing this approval is for, so the tool
that does it is granted here. Without this the person would answer
this card and then immediately meet the refuse-then-widen card for
`navigate`, which asks the same question in worse words.
Puts a permission card up: says it where she is, and tells whoever is
listening from outside her chat.

The words are passed in rather than built here because each caller says
it differently — a browser action, a folder outside every project, a
skill to install — and the person outside the chat has to read the same
sentence the person inside it does, not a summary of it.

Order matters: `offeredApprovalAnswers` reads the decision that was just
set, so the card has to be standing before the answers are asked for.
Takes the waiting card down, and says so if it was one somebody outside
was shown.

Every clear goes through here rather than assigning `.none()` in place:
a row of Once/Always/Deny buttons in the command window outlives the
question otherwise, and pressing one then answers nothing.
Clears a waiting card and records that it never happened.
Typing again while being asked "wait or replace?" answers nothing, so
the message that raised the question is put in the queue rather than
dropped. Losing what someone typed is the one outcome neither answer
would have produced.
A plan turned down has no tool in flight to fail — the turn that
produced it already finished — so it says so and leaves the state
machine where it is.
MARK: - Slash commands

Folds one turn's usage into the session total.
MARK: - Watching a folder or a file

`/watch <path>` — say when something under a path changes.
`/watch stop [path]` — stop one, or all of them.

Only when asked. Watching is a standing instruction that produces
messages nobody typed for, so like the loop each one is announced when
it starts, visible while it runs, and stoppable in one click.
`stop`, or `stop docs` for one of several.
What is being watched, or how to start.
Shared by the typed `/watch` and by the assistant's own ```watch block.

Through the ordinary project resolution and approval, and classed
`.readOnly`: nothing is sent anywhere and nothing is written, but it is
still repeated reading of the person's files and belongs to a project
they approved.
Taken before the line below overwrites it, which is the whole reason
this is a field and not read at `startWatch`: by then the request
text says "/watch <path>" — this function put it there — and the
person's own standing instruction, the thing the watch exists to
carry out, is gone. Found by driving it (Sprint 21.2): the watch
remembered "/watch /Users/…/inbox" and so had nothing to act on.

Only when the assistant raised it. A typed `/watch` *is* the whole
request: it asks to be told, and told is all it gets.
A full path names a place rather than something to look for inside a
project, so it is asked about directly. Sending it through project
resolution first would ask "may I watch /Users/…/aaa in Second-Brain?"
— a question about the wrong folder — and only then discover it was
somewhere else entirely.
Asks about a folder that no registered project contains.

It used to be refused: "it isn't inside <project>", and that was the end
of it. Watching is reading, so it does need a yes — but a yes was never
possible to give, which left the person with a rule instead of a choice.

The yes is carried by a project made here and never registered. That is
what makes the rest of the machinery work unchanged, and it keeps the one
property that matters: the watch loop re-resolves through the adapter
every tick, so the escape check still runs — around this folder now,
which is exactly the boundary that was just agreed to. A symlink inside
it still cannot lead anywhere else.

Nothing is written to the registry, and the throwaway project is a new
identity each time, so a grant recorded on the way through can never be
matched again. Watching the same folder tomorrow asks again.
The resolved path, spelled out. "May I watch aaa?" is not a question
anyone can answer — `..` and symlinks are precisely where the folder
you typed and the folder you get come apart.

Acts on a ```watch block, once the reply that carried it is whole.
Takes the first look and starts the timer.
Climbed out of the project with `..`, or followed a link that led
outside it. Where it landed is a real folder the person can be
asked about, so it is — the same question a full path gets, since
it is the same situation arrived at by a different spelling.
The half of `beginWatching` that runs once the path resolved inside the
project: refuse duplicates and the cap, then take the first look.
What the person actually asked for, so a change can be acted on
rather than only announced. See `watchFollowUpPrompt`.
Asking twice for the same thing is a no-op, not a second watch that
reports everything in duplicate.
Refuses the new one and leaves the running ones alone: dropping one
of them to make room would stop something nobody asked to stop.

The cap is stated when it bites. "Watching this folder" and "watching
the first 500 files of it" are different promises, and the person has
to know which one they got.
Stops one watch, or all of them when `path` is empty. Safe when nothing
is running, so a button can call it.
The request a watch is being started for, held between `beginWatch` and
`startWatch` — the two are separated by a path resolution and often by a
permission card, so it cannot simply be a parameter.
Whether the nudge that breaks a permission deadlock has already been
spent on this dead end.

Once, never twice: if she marks herself blocked on a permission *again*
after being told that attempting is how one asks, the wall is real and
saying the same thing a second time is a turn spent to no purpose. It is
released by any turn that finishes without declaring itself blocked.
Whether a watch has already handed the model something to act on that
has not come back yet.

The brake on the obvious hazard: the assistant acting on a change may
write inside the folder it is watching, and that is another change. One
in flight at a time means a busy folder cannot turn into a queue of
turns the person never asked for. Released when any turn finishes,
beside the queue it is pumped with.
One look at every watch. Separate from the timer so a test can drive it
directly instead of waiting for real seconds.

Each is reported in its own message rather than merged: they are
different questions the person asked at different times, and "3 changes"
spanning two unrelated folders would answer neither.
Resolving is a *decision* — it re-checks that the path still lies
inside what was approved — so it stays here, on the actor that owns
the watches. Only the walk goes elsewhere.
Back on the actor, and nothing is assumed to be where it was: a watch
can be stopped, or the list re-ordered, while the disk was being read.
Found by index it would report against the wrong folder; found by id
it simply isn't there any more.
Still advanced, so a change that comes and goes between looks
isn't reported twice.
The person is told by the app, always — this line does not depend
on a model turn succeeding, or on there being one at all.
The looking, off the main actor.

`WatchScan.snapshot` walks up to `WatchLimits.maxEntries` files and asks
each for its size and date — and for a single watched file, reads and
digests up to a megabyte of it. That ran on the main actor every four
seconds, per watch, up to five watches per character, on a desktop that
may have four characters watching folders at once. Nothing about it needs
the actor: it takes a URL and hands back a value.

Concurrently, one child task per watch, because they are separate folders
and the slow one should not decide when the others are read.
Answers a reply that has settled into waiting for a permission.

The dead end is real and it is silent: the turn ends, the state machine
goes idle, nothing is pending, and she is waiting for a grant that no
message can carry. Nothing here grants anything — it tells her that
attempting is how the question reaches the person, and the refusal that
follows is what draws the card. See `isWaitingForPermission`.

Not when a card is already up: then the question *has* reached the
person and she is waiting for exactly the right thing.
Hands a change to the model, when the watch was started by somebody
asking for something to happen.

Queued rather than run on the spot: she may be mid-turn, and the queue
is the app's existing answer to "this arrived while she was busy" —
`dispatchNextQueued` starts it the moment she is free.
MARK: - Following a file's instructions

Acts on a ```run block. Gets as far as the confirmation card and no
further, exactly like the typed command.
Whether a run is standing *and* still going — the question all three
callers were asking through their own unwraps.
MARK: - Following a file's instructions

`/run <file>` — read a file and do what it says.

The file is named by the person, always. There is no search for "the
instructions", and no filename is guessed from a request: the charter's
rule against inferring a path from a name applies just as much to a file
that is about to become work.
Starts the read-and-plan turn. Shared by the typed `/run` and by the
assistant's own ```run block — one path in, so a request raised by the
model meets exactly the same approval, the same plan card and the same
refusals as one the person typed.
MARK: - Looping back

Starts, or replaces, the standing check-back.

Announced in the conversation every time, with how to stop it. A timer
that speaks on its own must never be something the user has to deduce
from a message arriving out of nowhere — and that holds whether they
typed `/loop` or the assistant set it up from what they asked for.
Stops the loop. Safe to call when nothing is running, so the view can
wire a button to it without asking first.
One look at the clock. Separate from the timer so a test can drive it
with any date it likes instead of waiting for real minutes.
Never talk over the Secretary, or itself. A check that arrives while a
reply is streaming would interleave two answers in one transcript and
cancel the first — `streamingTask` is single-flight. It waits for the
next look instead, and the delay costs one poll, not one interval.

Shown whether or not activity is switched on: this is not a step in
work the user asked for, it is the reason a message they didn't ask
for is about to appear.
The same two events a typed message sends: `.beginExecuting` is not a
legal move out of `.idle`, so a timer cannot shortcut into working.
Straight to the agent, never the intent classifier: a check is our
own words, and routing them as a command could run a tool nobody
asked for.
Acts on a loop the assistant asked for in its reply.
MARK: - Chat

Tool identifier for "may Claude Code work in this project".
Neutral directory used when no project is in play. Claude Code always
runs *somewhere*; without this it would inherit whatever directory the
app happened to launch from, which could be the user's home.
Stands in for a project when none is registered. Chat and browser work
both run in the scratch folder in that case, so there is a real
workspace to name — it just isn't one the person chose.
A directory-scoped backend needs to be told where to run before the
turn starts. Working in a registered project is a real capability
grant, so the first time in each project we ask.
Prefer where we were last, then anything already approved. A
single unapproved project is worth asking about; with several,
guessing which one the user meant would be wrong.
Answers that arrived while she was idle ride along with whatever is
said next. See `unseenReports` for why they cannot simply be appended
to `conversation`.
After a turn in which Claude Code was refused a tool, offers to allow it
and run the same request again.

This is how permissions widen at all. Claude Code has no mid-turn
approval — an un-granted tool is simply refused — so the only honest loop
is: try, get refused, ask the human, retry with more.

The refusal is per rule, and Claude Code mints one rule per shell
command prefix, so a session of ordinary work asks again at `mkdir`,
again at `mv`, again at whatever comes next. That is the friction the
standing `.localWrite` grant removes: answered Always once, the same
loop still runs — try, refused, widen, retry — but silently, and the
person is not shown a card they have already answered for this project.
A browser action belongs to no project — it happens in Chrome — and
the person may have registered none at all. Requiring one here meant
the offer was silently skipped and the action stayed unreachable, the
same way it did on the chat path. The grant is per-session, not
per-project, so the project is only what the card names.
A folder first, because no tool rule opens that wall and a card
offering one would be a button that changes nothing. A call refused
for pointing outside the session carries the folder that would let it
through; see `isDirectoryRefusal` for how the two walls are told
apart, and what it cost to conflate them.

Only folders that are not already open, and that is the same brake
the tool wall has in `isNew` below: a folder this session has already
been granted, refused again, is not a folder the person can fix by
agreeing to it a second time. Offering it again would be a card whose
button does nothing, pressed forever.

Falling *through* rather than returning when they are all already
open is the point of the rewrite: a turn can hit both walls at once,
and stopping here would swallow the tool refusal in silence — which
is the exact shape of the bug this whole run has been chasing.

Nothing either wall can open. It reaches here when a folder was
granted and the call was refused again anyway, and saying so is the
honest end: the person has agreed to everything there is to agree to,
and a silent stop would read as the app losing the request — which is
what "it just hangs" has meant every time in this sprint.

A project the person has already answered Always for is not asked
again. The check has to be made *here*: `proceed` intercepts
`widenAgentTools` before the rail that consults the grants, so this
is the only place on the path that ever reads them. Without it the
Always button records a grant nothing looks at, and the card comes
back on the next command prefix exactly as before.

Browser actions are excluded, by class and by this condition both:
acting inside a session the person is signed into is not something a
grant scoped to a project folder can speak for.

`isNew` is the brake. Silent widening replaces a card the person had
to press, and a card is what used to stop `refused → widen → retry →
refused` from going round for ever. Claude Code refusing a rule this
session has *already* been granted is precisely the failure
`bashPermissionRules` was written for — approving did nothing, and
the retry hit the same wall. Granting it a second time cannot help,
so the loop stops and the person sees the card, which is the honest
report that the grant is not the thing standing in the way.
What it will do, not the rule that permits it: nobody can weigh
`mcp__claude-in-chrome__navigate`.
Browser actions happen inside a browser the person is signed into, so
the card has to say that rather than leave them to infer it from a
tool name. The wider-than-asked-for scope is stated too: they are
agreeing to more than the one action that triggered this.
Asks to open a folder Claude Code was refused for being outside the
session's working directories.

A separate card from the tool one, and worded as a place rather than as
a permission, because that is what is being agreed to: the assistant
gets to read and write in another folder for the rest of this
conversation. The charter puts accessing a new directory on the list of
things a human has to approve, and this is where that happens.

Never remembered — `.directoryAccess` refuses it in `mayBeRemembered`,
since a grant keyed by `(project, tool, class)` cannot say *which*
folder and would quietly cover the next one too.
The assistant says it needs a skill it hasn't got, and asks to install it.

The same try-refuse-ask-retry shape as widening tools, and asked for the
same reason: nothing about "what this assistant can do" changes without
somebody being shown the change and agreeing to it. Installing software
is on the charter's approval list, so this is `.dependencyInstalling` and
is never remembered — a skill installed once stays installed, but the
permission to install does not carry to the next one.

Where it comes from is not negotiable: `claude plugin install` resolves a
bare name against the marketplaces the person has already added, so this
can reach nothing they have not already chosen to trust (owner's
decision, 2026-08-13). It is also why an "MS Office" skill cannot arrive
this way — there is no such plugin in the official marketplace.
Puts a card up for something the assistant asked to keep.

Three things have to be true before the card appears, and each is a
refusal rather than a silent drop:

- **A project is open.** With none, the working directory is the scratch
  folder and there is no project for a fact to be about. Memory filed
  there would be filed against a project the person never chose.
- **The note does not read as an instruction.** This is the one thing
  memory adds that no other block does: it is model-written text that
  will be re-read as context on every later turn — by this app, and by
  the person's own terminal in that project. `instructionRisks` already
  knows the shapes, and the refusal is said out loud rather than logged.
- **The person says yes.** `.localWrite`, so the card comes every time.
  Approve-once was the alternative and was rejected: the grant would be
  to write into `~/.claude`, which is not the project the person
  approved, and each note is a different sentence to weigh.
Writes it, and says what landed where.

Announced on both outcomes. A note the person approved and that then
failed to write is the case where silence is worst: they would go on
believing it was remembered, and only find out weeks later when nothing
recalled it.
Installs, says how it went, and asks the question again.

The rescan is the point: a skill Claude Code has just installed is not in
`availableSkills` until something looks, and the retry would run without
the very thing that was installed for it.
The turn that asked for this has already finished, so the machine is
back at IDLE and `.beginExecuting` from there is an invalid
transition — the same trap `widenAndRetry` documents. Re-enter through
the front door so the character is visibly busy while the installer
runs, which can take a while.
The point of the rescan: Claude Code has the skill now,
but `availableSkills` was read before it existed, and the
retry would run without the very thing installed for it.
The request itself is already the last user turn.
The set of projects changed while a conversation was going.

Adding a project is nearly always a correction: the person asked for
something, the assistant couldn't reach the folder — or the MCP servers
that folder configures — and they went and added it. Until now nothing
told this object at all, so the workspace kept its old scope and the
question that prompted the change sat there answered wrongly.

Re-preparing matters as much as re-asking. Claude Code loads a project's
MCP servers when a session starts, so a server added mid-conversation is
invisible until the session is replaced — which moving the working
directory already does. The app's own `conversation` carries the context
across that, so nothing is lost by starting a new one.
A project brings its own `.claude/skills` with it, so the list of
skills follows the list of projects — and it does so whether or not
there is a workspace here to re-scope, which is why this is above the
guard. It was below nothing at all: the list was scanned at launch
and never again, so a skill that arrived with a project stayed
invisible until somebody found the refresh button.
Runs the last thing the user asked, again, on the freshly scoped
workspace.

Announced in an activity box rather than done silently: an answer nobody
just asked for has to carry the reason it appeared, the same rule the
loop follows. Skipped while the assistant is busy — cancelling a reply
the user is reading to re-ask an older question is worse than waiting.
One line of it, so the box names the question without reprinting it.
The words themselves live in `SecretaryPrompts.swift`; these two are
still reachable through `Secretary` because tests pin the prompt by
asserting these exact texts appear in what was sent.
Adds the rules for this session and retries the request that was blocked.
The folder the person just agreed to is opened to Claude Code, and the
request runs again.

Session-only and never written down: `mayBeRemembered` refuses
`.directoryAccess` because a grant cannot name a folder, so the next
folder is asked about afresh rather than inheriting this yes.

The backend restarts here, and that is correct rather than a cost to
avoid: `--add-dir` is a launch flag, so it is part of `WarmProcessKey`,
and a process already running cannot be told about a new folder.
Same re-entry as `widenAndRetry`: the previous turn finished, so the
machine is at IDLE and `.beginExecuting` from there is invalid.
The previous turn already finished, so the machine is back at IDLE.
Re-enter through the normal path — sending `.beginExecuting` straight
from IDLE is an invalid transition, and the character would sit still
through the whole retry.
The request itself is already the last user turn in `conversation`.
Extra tool rules granted for this run only. Deliberately not persisted —
a project keeps its read access across launches, but permission to write
starts closed every time.
Every project the user has approved for Claude Code.
Points the backend at one project and opens the other approved ones
alongside it, so a question spanning projects can be answered without
making the user switch. Only approved folders are ever passed — the
per-project grant is what widens this set.
Folders the person opened to Claude Code this session, on top of the
projects — see `openDirectoriesAndRetry`. Session-only, like
`sessionAgentTools`, and for the same reason.
Remembered before streaming so the system prompt can name the folder
the backend is actually standing in.
The staging folder, once there is something in it. This is the whole
reason attachments are copied rather than linked: the backend is
opened onto one folder that holds only what was handed over, instead
of onto whichever folder the person happened to drag from.

Folders agreed to mid-session. Appended here rather than at the one
call site that grants them, so every later `prepare` keeps them —
dropping them on the next turn would ask the same question again.
What the backend may use without asking. The browser's reading tools
join it only while the connection is on: pre-approving a tool the
session doesn't have would be noise, and leaving them out while it is on
would put a permission card in front of every "what does this page say?".

Everything else the browser offers — navigating, typing, clicking,
uploading, running JavaScript — is deliberately absent, so it takes the
refuse-then-ask path the rest of the app already uses.
Persists the grant, points the backend at the project, and runs the turn
the user was trying to send when we interrupted them.
Streams a reply for `messages` into a new transcript entry.

`messages` is what gets sent; `conversation` is what gets remembered. They
are the same for ordinary chat, but deliberately differ for file
understanding, where the file bytes are sent once and only a short marker
is retained — otherwise every later turn would re-send (and re-bill) the
whole file.
Named now, when the reply starts, so a profile switch part-way through
a conversation doesn't re-sign the answers already on screen.
Remembered so that stopping a run mid-reply can close off the entry
it interrupted. A cancelled stream never reaches `.completed`, so
without this the half-written bubble just sits there, indistinguishable
from a reply still arriving.
Explicitly main-actor: every step below touches @MainActor state
(transcript, state machine, audit). The stream itself does its network
work off-actor and we consume it back here on the main actor.
The one variable: the fold's accumulator, threaded through
handlers that each return the next run.
One event from the stream. Returns whether the turn is over — the error
rail ends it, everything else is something to render.
The model started saying a new thing. Whatever it was saying
before is finished — left joined, an answer to the person ran
into its note to itself and then into the report of what it did,
three things in one block with not even a space between them.
A tool between two things said ends the first of them too. In
practice a block boundary follows anyway, but not every backend
sends one and the seam belongs wherever the turn actually turns.
Kept even when the user has the panel closed: turning it on
mid-turn should show what already happened.
Said in the conversation, not only in the activity box: that box
is off by default, and a person who has never turned it on is
exactly the one who cannot tell working from dead.
No line of its own — the CLI sends one of these per step, and a
conversation that grows a paragraph per step buries the answer.
It moves the header instead, and re-stamps the clock the liveness
rule reads.
Read before clearing: the kind is only known from the sub-agent
that is ending, and the finish line does not repeat it.
Finishes the bubble being written, if anything was written in it.

The empty case matters: a turn that reaches for a tool before saying
anything keeps its placeholder instead of gaining a blank bubble, and
the block boundary that opens the very first block arrives before any
text at all.
The first token is what turns THINKING into WORKING — not the request,
which may still be waiting on a tool.
The file-understanding path is already WORKING from the read;
re-sending the event there would be an invalid transition.

Speaking again after a tool: a new bubble, named with the profile
this reply started under, so a profile switch mid-turn can't
re-sign it.
Said in the transcript, not just logged. The whole conversation is
sitting above this line, so an answer written without it would look like
the app ignoring what is right there on screen.
The id deliberately stays. It used to be dropped here, which was
harmless while archiving happened once on the way out; now that a
conversation is filed as it goes, dropping it would split what is
plainly one conversation on screen into two rows in the menu.
Ends the turn: reads the fenced blocks out of the reply, and writes what
is left into the bubble that was being written.

Two texts, because a reply can be several bubbles now. The blocks are
read from `fullText` — the whole turn, however many tools split it —
since a `watch` or `loop` block asked for before a tool call still has
to be acted on. Only `displayText` is written, because the earlier
bubbles are already on screen and finished; writing the whole reply here
is what used to glue three separate things back into one.

`entryID` is absent when the turn ended on a tool rather than a word.
There is then nothing left to say and no bubble to say it in.

- Parameter bubbles: the same turn a third way — one entry per bubble
  the person saw. Only the notification banner wants it; see `spoken`.
A loop the assistant asked for is acted on once, here, when the reply
is whole — not while it streams, where a half-written block would read
as a different interval every few characters.
A pane the assistant was asked to pin, read once the reply is whole for
the same reason as the loop block.
Whether the assistant declared itself stuck, and on what. Recorded
before the transcript is updated so the marker never reaches the eye.
Only when a plan was asked for. Parsing every reply would let an
ordinary answer that happens to fence a ```plan block put a run on
the table, which is the guessing this feature is built to avoid.
A watch or a run the assistant asked to start itself. Read once the
reply is whole, like the loop: a half-written block would name a
different path every few characters.
The assistant asking for a file to be handed over. Read once the
reply is whole, like the rest: a half-written block would put a
button up asking for half a sentence.
A skill the assistant says it needs. Read once the reply is whole,
like the rest — and only from a marker, so "you'd need the pptx
skill for that" stays a sentence rather than becoming a button.
The assistant asking to pass something to another character. Read
once the reply is whole, like the rest — a half-written block would
name half a character and send half a sentence.
Something she wants kept about this project. Read once the reply is
whole, like the rest — half a block would file half a fact, and this
is the one block whose output the person's own terminal reads back.
Files she made and is offering to hand over. Read once the reply is
whole, like the rest — a half-written block would name half a file.
She got somewhere this turn, so the next dead end is a new one
and deserves its own nudge.
The blocks came out of the whole turn above; what goes on screen is
this bubble's share of it, stripped the same way.
Before `reportBackIfAnswering`, which clears `answering` — after it,
an errand would look like the person's own request and every hand-off
would put a banner up from a character nobody spoke to.
Every bubble, not just `displayText`, which is the last one only: a
turn that answered "done" and then added a housekeeping line put the
housekeeping in the banner and left the answer off it (driven at
0.19.288). Joined with a blank line rather than taken from `reply`,
which glues the bubbles character to character on purpose.
From the raw last bubble, where the fence still is — the spoken
text above has already had it stripped.
If this turn was another character's errand, the answer goes back
now — after the state machine has settled, so what is sent is a
finished answer rather than one still closing.
Her own request to pass something on. After the report above, so a
character answering an errand can hand a piece of it to a third
without the two crossing.
After the state machine is back to idle, so the announcement lands in
a settled conversation and a loop asked for mid-reply can't fire into
the reply that asked for it.
Last of all: whatever was typed while this was running goes now, with
the finished turn behind it in the conversation — which is what makes
"wait its turn" different from "ask me again later".
A finished turn releases the watch brake. Beside the pump because it
is the same moment: whatever was waiting may go now.
After the state machine has settled, for the same reason as the loop:
the card and the next step both belong to a finished turn, not to the
one still closing.
Last, so that a step of a run can't start a watch that then reports
into the turn that asked for it.
Only a button, and only until the next thing is typed. Asking is not
reading: nothing opens a panel, and nothing is read, until the person
presses it and chooses the file themselves.
Last of all, because it puts a card up and the card is about the turn
that just ended. Only ever a card: nothing is installed until someone
reads what it names and says yes.
After it, and only if it didn't already claim the card: one decision
is pending at a time, and a note is the less urgent of the two — the
skill install is blocking the answer, the note is about keeping
something once the answer is given.
File it now, not when it is put away. Every ending goes through here
— answered, refused, failed — so the conversation you are having is
in the history menu from its first turn, and survives the app dying
mid-thought. A failed write is deliberately not announced: the
conversation is still on screen, unlike the `newConversation` case
where losing it silently is the whole risk.
Appends a step, collapsing an immediate repeat — several thinking blocks
in a row are one "thinking", not five identical lines.
A bubble's text with every fenced block taken out of it.

Display only — nothing here acts on what it finds. The requests are read
once, from the whole turn, in `finishChat`; this exists so a block that
happened to be written before a tool call doesn't sit on screen as raw
text in the bubble that was closed off around it.
- Parameter replyID: the bubble being written, when there is one. With
  none — a tool ran straight after a finished bubble — the commentary
  goes at the end, which is where it happened.
Ahead of the bubble being written, when one is: the work
happened before that answer and should read in that order.
With no bubble open, the last one is already finished and
this goes after it.
Flips the running commentary on or off and says so, because the change
happens in the conversation and should be visible there.
Announced in the same dashed-box style as activity itself, not as a
spoken reply — this is a status change, not something she's saying.
Nothing to back-fill mid-turn: the entry appears on the next step.
Connects or disconnects the user's browser, and says so in the chat —
the same rule as every other setting: a change the assistant's answers
depend on is announced where the answers are.
MARK: - Git pipeline

**A misreading must fall through to chat, never end the turn** — and
today it can still do the latter, on purpose. Written down so the next
person knows it was weighed rather than missed.

The `.notFound` arm below finishes the turn with a refusal. When the
classifier could hand this a whole paragraph as a project name, that
refusal was the app going silent on an ordinary question (2026-08-17).
With `looksLikeProjectName` and `isSingleSentence` in front of it, a
query only reaches here if it is short, unpunctuated and shaped like a
name — in which case "no registered project matches" is the *correct*
answer and turning it into a chat turn would hide a real mistake.

So the fix belongs at the guards, and it is there. If a misclassification
ever reaches this line again, widen the guards; do not make the refusal
quieter.
No project named, but we were working in one a moment ago — keep
working there instead of asking again every single message. Only when
the user said nothing: an explicit name that doesn't match is still a
"not found", never silently redirected somewhere else.
Starting the agent in a project is what *creates* the grant, so it
can't be gated on the project already holding it.
A read is local, but its contents then join this conversation and
travel with the next chat message. Say that at the point of asking
rather than letting the user discover it later.
Stepping past the project's own allowlist is a different kind of yes
from the ordinary one, so it is said rather than left to be inferred
from the tool name. It is also asked every time: this grant is never
remembered, and never written back to the project on disk.
Reached through the card the first time. Since Sprint 15 a
`.localWrite` that was answered Once or Always can come straight
here on a later turn — the note itself is still built from a reply
that was scanned, and the grant is per project and per class.
MARK: - Conversation memory

Writes a finished tool run into the conversation so follow-up questions
("how many .md files?") land on a model that can actually see the answer.
Without this the transcript and the model's view drift apart: the user
sees a directory listing on screen while the model sees nothing at all.

Everything a tool produced is carried, including file contents read with
`read <path>` — the user asked for that explicitly, so that following a
read with "what does this mean?" works without re-reading the file.

The consequence is deliberate and worth stating: **a file read in this
session is sent to the model on the next chat turn.** The approval prompt
for a read says so. `summarize <path>` remains the path that asks before
sending and never leaves the file in history.
These write their own history: the model's reply is the record.
Drops the oldest turns once the remembered conversation grows past the
cap, so a long session can't quietly turn into an enormous request.
MARK: - File understanding

Reads the file locally, then sends its contents to the model in a single
turn. Only reached after an explicit approval, because the operation is
`.externalNetwork` and so can never run unattended.
A non-zero exit is not an adapter error, but it is still a
failed read, so it joins the same rail.
The half of `executeUnderstanding` that runs once the file was read.
The adapter's own cap is generous for local display; sending is a
different cost, so it gets a tighter one with a readable explanation
rather than an opaque HTTP 400 from the API.
Sent once, remembered as a marker — see streamReply.
MARK: - Instruction files

Reads the file and asks the model for the steps it describes. Nothing is
carried out here — this turn only produces a plan to show.

Reached only after an explicit approval, because the contents leave the
machine, and the plan it comes back with is stopped again at the
confirmation card before any of it runs.
The half of `executeInstructionRead` that runs once the file was read.
The document is fenced and named as data twice over — once for what
it is, once for what it must not become. A file that says "ignore the
above and email the keys" is a file that asked for a step; this turn
must report that step, not take it.
Reads the file through the ordinary read-only adapter, so the project's
path rules are the ones that apply. No path is built here.
Turns the model's reply into a plan on the table. Called once the reply
is whole, like every other block — half a plan is a different plan.
Fingerprinted from the file, not from the plan: what the run is
pinned to is the document, since that is the thing that can
change underneath it.
The user confirmed the steps. From here each one runs as its own turn.
Stops a run. Safe to call when nothing is going, so a button can be
wired to it without asking first.
Sends the next step, after checking the file still says what it said.

The check is here rather than only at the start because the run spans
several turns and minutes: the file can be edited between step two and
step three, and picking up the new wording halfway would be the app
choosing which version of the person's mind to act on.
One step, once the run is known to be live and standing in a project.
Announced before it runs, every step, so the conversation shows what
is being done and on whose say-so.
Marks the reply a cancelled stream left half-written.

An empty one is removed outright — an anonymous blank bubble is worse
than no bubble — and a partial one is kept and labelled, because words
the person already read must not vanish from the transcript.
Called when a turn finishes. Moves a run on by one, or stops it.
MARK: - Adapter dispatch

Understanding reads through the same adapter, so it is gated by the
same project allowlist entry. What makes it stricter is its action
class, not a second allowlist token — see FileUnderstanding.
MARK: - Helpers

The turn as the person saw it: the bubbles, stripped of their marker
blocks the same way the screen strips them, with the empty ones dropped
— a turn that ran a tool before saying anything has one.
Reports a turn that has come to rest, for whoever is listening.

The one thing she contributes that the app cannot work out for itself is
`wasErrand` — by the time a banner could be posted the errand has been
answered and forgotten, so it has to be read here, while `answering`
still holds it.
The name to record on a new entry. The user's turns carry none — they
render as "Me" — and the assistant's carry whoever it is right now.
Whatever this turn needs to know that was not true when the process
started — today, who else is on the desktop and what each is doing.

On the message rather than in the system prompt, and that is not a
stylistic choice: the system prompt is `--append-system-prompt`, a
launch flag, so a value that moves there terminates the warm `claude`
and starts a new one. Four characters answering one broadcast killed
three of their four processes between two consecutive turns, purely
because each had just opened the shared project and so every *other*
character's prompt had changed. See `directoryPrompt`.

Only the last user message is sent — the provider reads that and Claude
Code keeps the thread — so this attaches there, and `conversation` keeps
holding what was actually said.
The static instructions plus whatever the user has actually registered.
Without the project list the model denies knowing about a project the
user can plainly see in the UI. Names only — paths, tool allowlists and
approval state stay out of chat history.
Named, verbatim, for this one turn. A standing rule about "messages
that supply the missing piece" was already in the prompt and was not
enough; the request itself has to be in front of the model.
Who else is on the desktop, read fresh for this turn. Absent when she
is the only one here, which is the overwhelmingly common case and
should cost the prompt nothing.
Only with a project open — see `offerToRemember`, which refuses for
the same reason. Telling her about a memory she cannot file anything
into would be an invitation to try.
Gathers the state `agentSystemPrompt` needs; the words and their
assembly live in `SecretaryPrompts.swift`, as functions of these values.
MARK: - Model and effort

The model that will actually be used, named. Falls back to what the
backend is configured with so the settings panel can show a real name
rather than "your default".
"Default" rather than "Unknown" when there is no name to show.

Nothing is broken in that case: the app hasn't been told a model, and
hasn't been able to read which one the user's own Claude Code will pick,
so whatever Claude Code defaults to is what will run. "Unknown" said
that as a fault — it reads as *something is wrong with your settings* —
and it sat directly above a menu item already spelling out the true
answer, "The tool's own default".
What is actually running, short enough for the header beside her name.

Built from the *effective* pair, not from `modelDescription`, which says
"the tool's own default" — a phrase that is right in a sentence and
absurd in a badge.
One spelling for both rows. They sit one above the other in the same
panel and mean the same thing, so two spellings would read as two
different situations.
True when the value comes from the user's own Claude Code rather than a
choice made in this app — worth showing, because it explains why it can
change out from under the app.
Picks a model, or absent to go back to inheriting. Announced in the
transcript so a change made in the settings panel is visible in the
conversation it affects.
Both halves together, because they live in one value and writing one
without the other would drop whichever was not being changed.
What to show the user for a setting they may never have touched.
Switches who the assistant is, mid-conversation if need be.

The change is immediate everywhere it can be: the UI observes `profile`,
and the system prompt is rebuilt from it and sent with every turn — even a
resumed one — so the next reply is already the new character. The
conversation itself is deliberately *not* reset: losing the context to
change a name would be a worse trade than one turn of overlap. Announced
in the transcript for the same reason a model change is: the conversation
is where it takes effect.
Drops duplicates while keeping the order the user will read them in.

