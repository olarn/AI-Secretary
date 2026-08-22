# Tests

The test suite is the repository's primary bug record: a test name states the
claim and its body carries the input that reproduces it. What is kept here is
the narrative that sat above some of those tests — the conversation that was
actually had, the report the owner actually filed — which a name can summarise
but not contain.

Read a section here when a test fails and you are tempted to decide it was
asserting the wrong thing. Most of these tests exist because the opposite
behaviour shipped once.

## ActivityLineTests.swift

Whose work each line of the activity box is.
The bug, as a test. A sub-agent's inner `Bash` was drawn exactly like one
she had run herself, so the box reported a command she never ran and
nothing on screen could contradict it.
Indented, so the sub-agent's steps read as nested under whatever of hers
started them rather than as a second list at the same level.


## AgentSessionTests.swift

A chat provider that is also directory-scoped, so we can see what the
Secretary told it before a turn.
Every skill this was asked to install, in order. Nothing is installed
for real: the point of most of these tests is that the list stays empty.
What the installer reports back. Failure is the left.
Refusals to emit on the next turn, then cleared — so a retry succeeds.
Scripted text for the next turn, then cleared.
A whole turn, event by event, for when the order matters — text, then a
tool, then more text. The convenience fields above always put every tool
before every word, which is the one shape that can't show a seam.
Stands in for Claude Code's own thread. A real one appears when a turn
runs; this one is set by the test, so archiving and resuming can be
checked without a subprocess.
MARK: - Asking before working in a project

The prompt has to say what the grant actually covers, because it is
approve-once rather than per-message.
MARK: - Telling the backend what it can do

Reported from real use: asked to summarise a project, the assistant said
it couldn't see the contents and asked the user to paste them, then told
them to type `list files in <project>`. The system prompt was the
chat-only one, which says the model cannot run commands itself.
Every marker block the app can act on has to be described in the prompt
the backend actually receives.

This exists because it wasn't. The loop and window blocks were written
into `capabilityPrompt`, which only the API-key path uses, while Claude
Code — the backend this app really runs on — got `agentPrompt`, which
mentioned neither. The parsers were right and every test passed, and the
assistant answered "no window tool is available to me in this session",
because as far as it knew there wasn't one.
From a real conversation: asked for a ratebook and to pin it, the
assistant said the folder was empty; told "from the project's MCP", it
tried the server, reported that it worked, and searched for a different
car in a different year — never answering the question or pinning
anything. It read the second message as a fresh instruction instead of
as the missing piece of the first.
Which language to answer in is asked for on both prompt paths, because
it was asked for on only one of them and replies to Thai kept coming
back part English.
And it asks for the thing the person actually wants, which is not a
translation: an answer in Thai still says "commit" and still quotes the
error verbatim.
A personality written in Thai used to end with "they still describe you
when you answer in English" — an instruction to answer in English,
sitting in the same prompt as the instruction not to.
Adding a project mid-conversation is a correction, so the question that
prompted it gets asked again on the newly scoped workspace. Without this
the registry gained a folder and nothing else happened at all.
Nothing to resume, nothing to do — and no empty turn sent.
The whole point: after a blocked turn the next prompt carries the
request itself, not just a general rule about missing pieces.
A turn that finished clears it, so the reminder can't haunt the rest of
the conversation.
The old prompt is still right for a plain chat model with no tools.
MARK: - Widening permissions after a refusal

Claude Code refuses un-granted tools mid-turn rather than asking, so the
only way to widen is to notice the refusal and offer a retry.
MARK: - Blocked for where it pointed, not for what it was

The owner's report: commanding several characters at once, one asks for
write permission on a folder and no dialog ever appears. Claude Code has
a second wall — the working-directory one — worded nothing like the
permission wall, so the refusal was never recognised, nothing was
offered, and the turn ended with the character saying it was stuck.
Opening a folder is never remembered — a grant is (project, tool, class)
and none of those says *which* folder — so the card offers Once and Deny
and no Always.
And the question reaches whoever is listening from outside her chat,
which is the command window — the place the owner was commanding from
when they saw nothing.
Saying yes opens the folder to Claude Code and runs the request again —
`--add-dir`, which is the only thing that opens this wall. A tool rule
would have been a button that changed nothing.
Both walls in one turn. The folder is asked for first because nothing
else can get past it, and the tool refusal is not lost — the retry hits
it again and it gets its own card.
The retry is refused again, this time for the tool.
A folder already opened, refused again, is not something the person can
fix by agreeing a second time — the same brake the tool wall has. It
must not offer the same button again, and it must not fall silent
either, which is what "it just hangs" has meant all sprint.
Refused for the very same folder, after it was granted.
MARK: - Waiting for a permission nobody can hand over

The owner's deadlock, 2026-08-20. Their shared folder's `CLAUDE.md`
opens "everyone must ask for write permission first", so the character
asked — in words — and waited. Nothing was pending, no tool had been
refused, and no card could exist, because the request was never made.
Four characters were commanded; the three that attempted got through
and the one that asked politely stopped for ever.
Once. If she declares herself blocked on a permission *again* after
being told, the wall is real and repeating it is a turn spent for
nothing — the loop that would otherwise run for as long as she keeps
saying it.
Something else missing — a file, a folder, a fact — is not this. Those
are answered by the person, and the reminder already handles them.
A card already up means the question *has* reached the person, and
waiting is exactly right.
MARK: - The card, told to whoever is listening from outside

Sprint 21.2, the owner's report: commanded from the command window,
every character said it had no permission to write and then either
waited a long time or stopped for ever. The card was raised in her chat
panel and announced nowhere, so the person commanding her never saw the
question they were being asked.
The buttons outside her chat are the buttons inside it, or one of the
two is offering something the other refuses.
Answering in her own chat has to take the buttons down everywhere else,
or the command window keeps offering an answer to a settled question.
Typing something else drops the card. That is a settling too — the
question is gone, and buttons for it answer nothing.
The silent path must stay silent: a project already answered Always for
raises no card, so there is nothing to announce.
The card the owner actually met (2026-08-17): working in a registered
vault, permission was asked again at every new shell command, because
Claude Code mints one rule per command prefix and nothing outlived the
conversation. With the project's write grant on record there is no card
at all — the refusal is still noticed and still widened, silently.
The brake on the silent path. A rule granted this session and refused
anyway is the `bashPermissionRules` failure — approving did nothing and
the retry hit the same wall. Widening it again cannot help, so without
this the turn would go round `refused → widen → retry` for ever, with no
card to press and a bill running. The card comes back instead.
First refusal: the grant covers it, so it widens in silence.
Same rule, refused again — the grant is demonstrably not the problem.
The grant reaching disk is what makes the previous test true on the
*next* launch, and it is keyed to the project — a second project is a
separate answer.
The record has to agree with what was actually kept, on this card as
well as on the read-only one. `.localWrite` may be remembered and the
widen request is never outside the allowlist, so "just this time"
here would contradict the grant sitting on disk beside it — and a
line that lies is worse than no line at all.
Once is still only once — the answer that changes nothing past this
conversation has to leave the file empty, or the two buttons mean the
same thing and the card is lying about the choice.
The previous turn ended at IDLE, so the retry has to re-enter the state
machine properly — otherwise the character sits still through it and any
caller waiting on "busy then idle" is misled.
Read access to a project persists; permission to change files must not.
MARK: - Asking to install a skill

The whole safety story in one test: the assistant asking is a card, not
an install. Nothing reaches the machine until a human has read the name
and agreed to it.
A name that is really a flag, a path or a URL is not a request at all —
so a model that has read a poisoned page cannot even get the card up.
Talking about a skill is not asking for one. Without the marker the app
would be guessing from prose, which is the thing the block exists to
avoid — the same rule the choices block follows.
MARK: - Choosing a model from the settings panel

A change made in the panel takes effect in the conversation, so it is
announced there — the same path the slash command uses.
The chosen value must reach the backend, not just the label.
MARK: - Showing what it's doing

Several thinking blocks in a row are one thing happening, not five.
It belongs in the conversation, in order, ahead of the answer it
preceded — and marked as not being the answer.
The change is announced in the same dashed-box style as activity itself
— it's a status change, not something she's saying — and turning off
clears the boxes from earlier in the turn, leaving only the announcement.
A first run is quiet; the choice is remembered after that.
A relaunch reads it back.
The toggle-off announcement itself is the one .activity entry so far;
what must NOT happen is a second one for this turn's steps.
Each turn gets its own box. Matching by kind alone would find the
previous turn's and rewrite that history with the current steps.
A new question starts a fresh list — last turn's steps aren't current.
MARK: - Working with no project

Claude Code always runs somewhere. With no project registered it must not
inherit whatever directory the app launched from.
MARK: - More than one project

The point of the feature: with two approved projects, both are reachable
in one turn so a question spanning them doesn't need the user to switch.
Only approved folders may be opened — the per-project grant is the gate.
Several projects, none approved yet: guessing would be wrong, so ask.
Choosing an unapproved project still has to ask before running.
MARK: - Typing while something is running

A Secretary mid-turn: the reply has begun and will never finish, so the
next message really does arrive in flight. Waits for the first words to
land — `submit` returns before the stream has run at all.
It used to take over silently: the running turn was killed and the new
message ran in its place. Both answers are reasonable and only the person
knows which, so both are offered.
Replacing costs the running turn, which is the whole reason it is asked
about rather than assumed.
Both answers to this card are now written down. Replacing especially:
it used to leave nothing but a stopped turn and a new one starting, which
looks the same as the app having decided to abandon the work by itself.
The stopped reply is labelled rather than left looking finished, and what
was already said joins the conversation — the person can see those words,
so the model has to know it said them.
Checked where it matters: in what the next turn is actually told, not
in a variable. The person can read those words on screen, so a model
that doesn't know it said them will contradict the screen.
Holding is the only pause there is: the running turn is one invocation of
a CLI and cannot be suspended, so pausing acts on what hasn't started.
Typing again instead of answering must not lose what was typed — the one
outcome neither button would have produced.
MARK: - Starting over

The session-level cancel. Stopping a turn ends what is running; this
ends what is standing, and drops the context — the part that had no
other way out but quitting the app.
The context is gone where it counts: the next turn carries only the
new message, not the thread it interrupted.
A clean screen, and the old conversation retrievable rather than gone.

This asserted the opposite until Chat History existed, and the reason it
flipped is worth keeping: clearing was wrong while the words had nowhere
to go, because wiping something the person had read destroyed it. With a
history menu behind it the same clear is a clean slate. Neither half of
this test stands alone — a clear with no archive is data loss, an archive
with no clear is the old behaviour.
MARK: - One bubble per stretch of talking

Three things arrived as one block: the answer to the person, the model's
note to itself on the way to a tool, and the report of what it did. They
are three things and read as three; a tool ran between each pair.
The conversation still remembers the turn as one answer. Splitting is
what the person sees, not what the model is told it said.
What the notification banner is handed, when the turn was several
bubbles.

The turn the model is told it said is deliberately continuous (see
above), so reading the banner out of it glued the last bubble onto the
answer: "done" followed by a housekeeping line came out as one run-on
word, found by driving 0.19.288. The banner is built from the bubbles
instead, which is what the person actually saw.
The seam the app was actually missing.

Claude Code sends a turn as several content blocks; the deltas inside
them are just characters, so joining every delta ran the last word of
one block into the first of the next with nothing between — which is
what "README.mdไม่มีอะไรต้องบันทึกค่ะ" was. No tool call sits at that
join, so splitting on tools alone would not have found it.
The boundary that opens the first block arrives before any text, and
must not leave an empty bubble above the answer.
A turn that reaches for a tool before saying anything keeps its one
placeholder rather than gaining an empty bubble above it.
MARK: - Registry grants


## AnsweredCardsTests.swift

The wording of a record, on its own.
The whole point of `CardChoice` existing in a library target. If a button
title is ever retyped in the view instead of read from here, the record
and the button drift apart and no test in `AISecretaryApp` can see it —
that target is never linked into the test bundle.
The badge beside her name.
Not every name starts that way — `inheritedSettingName` doesn't — and
chopping seven characters off one that doesn't would produce "ult".
The case the collapse exists for: "Default | Default" reads as two
settings that happen to agree, when it means the app was told neither.
Answering a card leaves a record of the answer.

The bug these pin: a card vanishes the instant it is answered, and for
approving, for picking a project and for replacing a running turn nothing
was said afterwards that named the answer — so scrolling back showed a
question, then whatever happened next, with no sign that anyone had replied.
MARK: - Approval

The line has to say the grant was kept, because that is the half of the
answer the person cannot see anywhere else — nothing on screen afterwards
distinguishes a session grant from a standing one.
The record goes in front of the work, not behind it. An answer reported
underneath its own consequences reads as the app narrating itself after
the fact rather than as the person having replied.
MARK: - Choosing a project

MARK: - Cancelling


## AppearanceKeyTests.swift

Where each character's look is kept, and what she reads before she has one.

The fallback is the whole reason this is not a rename: on the first launch
after settings became per-character, nothing has been written under anyone's
own keys, and every character has to go on looking exactly as the app looked
the day before.
MARK: - Reading

The upgrade case. One theme was chosen back when there was one to choose,
and every character starts from it rather than snapping to the default.
Per setting, not all-or-nothing: choosing a theme must not also freeze
her text size at the default.
MARK: - Writing

And it must not write through to the shared keys, which are what every
character who has not chosen anything is still reading — one character
going dark would take all of them with her.
The store with no character is still the one that reads and writes the
shared keys, so nothing that predates characters changed meaning.


## AppearanceSettingsTests.swift

MARK: - Text size

The specified cap.
A value stored by a build with different limits must not survive as-is.
MARK: - Window height

Asked for: the default is also the smallest it goes.
Asked for: no taller than the screen.
Moving to a smaller display has to pull an over-tall window back in,
otherwise part of the conversation is off-screen with no way to reach it.
A screen shorter than the minimum window is still bounded by the
minimum — better to overflow slightly than to collapse the panel.
MARK: - Derived sizes

Captions have to grow with the body text, or 32pt replies sit beside
unreadable labels.
MARK: - App size

Asked for: three steps, S and L being ±30% — both measured from M, so
they can't compound into a runaway size.
A scale written by a build with different steps must not break loading.
`contrast` was offered in 0.10.197 and removed in 0.10.198. Anyone who
had it selected has that word on disk, and the app must open on the
default rather than refuse to read its own settings — the same handling
a scale from a future build gets.
MARK: - Liquid Glass

Off by default: the solid look is the one whose readability never
depends on the wallpaper, so glass is something the user walks into.
Nobody upgrading has this key, and absent must read as off, not as
whatever `bool(forKey:)` would invent.
MARK: - Persistence

The screen limit is deliberately not persisted — the display can change.
Width was added after the other two, so anyone upgrading has no value
stored. Falling back to zero would collapse the bubble.
MARK: - Which face the conversation is set in

The default that fixed the reported bug. The chat used to be drawn with
`monospacedSystemFont`, which has no Thai glyphs, so Thai fell through to
Ayuthaya — wide and heavy enough to be reported as the chat being bold,
while nothing in the app had ever asked for bold.
Nobody upgrading has this key, and the face they had was monospaced.
Falling back to what they were looking at would keep the bug they
reported, so the fallback is deliberately the new default rather than
the old behaviour.
A face written by a build with different choices must not throw away the
rest of the look on the way past.
Every choice offered has to be one the settings row can round-trip, or a
button in it silently does nothing.
The face is a per-character setting like every other, and reads the
shared value until she has one of her own.
MARK: - Window width

Free resize, as asked — but still inside the screen.
Asked for: one press is one step — ×1 → ×2 → ×3 — and then the button is
dead rather than jumping straight to the widest.
Asked for: coming back is *not* stepped — one press is the default width,
from however wide the bubble happens to be.
Including from a width that isn't one of the stops at all.
Three times the default doesn't fit on every display, and a stop the
screen has squeezed into another one isn't a separate press.
A screen too narrow for even two steps leaves one stop, so both buttons
are dead rather than pressable with nothing to show for it.
A hand-dragged width sits between stops. Widening from there goes to the
next stop up — it must not snap backwards to a narrower one.
Every size in the panels is derived from the one the person set, so
nothing stays pinned while the rest of the window grows. The hint under
a control stays smaller than the control's own label, at both ends.
At the smallest setting both clamp to the 8pt floor, which is
deliberate — below that nothing is readable, so the hint stops
shrinking rather than becoming a smaller unreadable thing.
Spacing grows with the text, or large type reads as a wall — which is
exactly what shipping the font change without this produced.
The gap between rows stays smaller than the panel's own inset, so
rows group inside the panel rather than floating apart in it.

The derived sizes moved into `TextMetrics` so a window with its own text
size can have them. The chat must still read exactly the same, or the
extraction changed behaviour rather than moving it.
The command window's whole complaint: growing its box's size has to grow
everything drawn beside the box, not just the words being typed.


## ArrowKeyOwnerTests.swift

Up and Down are wanted by three features at once. These pin down which one
gets them, so the answer can't drift back to "whichever `if` came first".

Note what this can and can't prove: it fixes the rule, not the plumbing.
Whether the key reaches the rule at all is a question only the running app
answers — `.onKeyPress` never saw an arrow here, and the code read fine.
Typing is how you say "I'll answer in my own words" — at which point the
arrows go back to being history, exactly as Return already behaved.
In a draft spanning lines the arrows are the only way between them, so
nothing may take them — not the picker's business either, since a
multi-line draft is never empty.
Nothing to recall and nothing to choose: the field keeps its own keys
rather than swallowing them to do nothing.
Exactly one owner for every combination of the three inputs — the
property that makes "they clash" unrepresentable rather than unlikely.


## AssistantChoiceStoreTests.swift

Remembering which model a character answers with.

The bug: it was never written anywhere. `selectModel` set a property and said
a line, so every character came back on "Default" after a restart, and the
badge beside her name was the only place it showed.
A suite of its own, so nothing here can touch the person's real
preferences and nothing there can decide these tests.
Going back to Default is a choice too. Left as "don't touch the key", it
would come back the next morning.
Model ids come and go between Claude Code releases. One that no longer
exists must fall back to whatever the CLI is set to — insisting on a name
nothing answers to would be worse than forgetting.
Two characters, two answers. Sharing a key would make setting one set
them all, which is the failure the per-character files exist to avoid.
The same, through the Secretary — which is where it actually has to work.
The whole point, as one test: what she was told last time is what she
starts on — a new Secretary over the same store, which is what a restart
is.


## AttachmentTests.swift

The rules about what may be handed over, without a filesystem.
The name gets the first word. A `.swift` file is source however its
bytes read, so nothing sniffed can rename it.
The point of sniffing: an extension nobody listed still gets in, as long
as it is something the model can actually read.
Refused rather than sent and misread. A `.xlsx` is a zip: handed over,
it would reach the model as bytes it can't open, and the answer would be
about the failure rather than about the data.
Thai, and anything else outside ASCII, is text — the check is UTF-8, not
"looks English".
Every refusal has to be sayable. A file that lands nowhere and says
nothing is one the person believes they sent.
Paths, not contents: the assistant opens the copy itself. Saying nothing
when there is nothing keeps the ordinary message unchanged.
MARK: - The assistant asking for one

A reply that merely mentions a file must not put a file dialog in front
of anyone — the same rule every other block here follows.
MARK: - Staging

The copy is the point: the model is pointed at the app's own folder, not
at the folder the file came from, so dropping something off the Desktop
doesn't open the Desktop.
End to end through the disk: the store is what reads the prefix, so the
rule is only real if it is applied there.
Two files of the same name from different folders are two files.
Handing a file over, through the Secretary.
The person sees their own filename; the model gets the path. Showing
them an Application Support path would be noise, and sending the model a
bare filename would be an address it can't open.
The staging folder is opened to the backend, and nothing else new is.
The copies were taken for this conversation. Keeping them past it leaves
someone's spreadsheet in Application Support indefinitely.
The button the assistant asks for, and the block never reaching the eye.
MARK: - What the drop area says

The count is the useful part once there is a list: it says how much room
is left without the person counting chips.
The one that matters: the window takes a drop anywhere, so somebody can
be holding a sixth file over a full list. Saying no before they let go
is the only place it helps — afterwards it is a refusal.
It never promises room that `admitting` would refuse — the two agree on
the same limit at every count, which is what stops the area from
inviting a drop that bounces.


## BlockedRequestTests.swift

Remembering a request the assistant could not finish.
The marker must never reach the eye; it is a message to the app.
"I couldn't find that" turns up in ordinary answers all the time.
Inferring from prose would leave a stale reminder in front of the model
for the rest of the conversation.
The reminder has to name the request and the gap, or it is just the
general rule again — which is the thing that already failed.


## BrowserAccessTests.swift

Reading web pages through the user's own browser: what it takes to turn on,
what it lets the assistant do unasked, and what it is told to say when it is
off.
The tools handed to the backend on the last turn.
MARK: - Turning it on

A permission that survives quitting has to survive relaunching, so the
backend is told at startup rather than only when the switch is flipped.
The change decides what the assistant can answer, so it is announced
where the answers are — and it says whose session is being used, since
that is the part a person would reasonably worry about.
MARK: - What may run without asking

Clicking and typing inside a signed-in browser never ride along with
permission to read. They take the same refuse-then-ask path as every
other action with a side effect.
Ordinary file and git access must not be lost when the browser joins.
MARK: - Being asked for the browser

The offer to allow is the only way permissions widen here, and it used
to require a registered project. Browser work belongs to no project and
often runs with none registered at all, so the offer never appeared and
the action stayed permanently out of reach.
Nobody can weigh `mcp__claude-in-chrome__computer`. The card has to say
what will happen — including the parts they didn't ask for, since one
rule covers scrolling, clicking and typing together.
And the chat message has to say whose browser it is.
MARK: - What the model is told

The failure this exists to prevent: a fetch of a login-walled page
succeeds and returns the sign-in form, and the model reports that as the
page's content. It has to know the difference, and know what to offer.
And once it is on, the model must know it — and be told that page text
is something to report, not instructions to obey.


## BubblePlacementTests.swift

Where the speech bubble lands.

The case that matters is a bubble too tall for the space above the
character. Flipping it below looks like the obvious answer and is wrong when
there is even less room down there: the flipped origin gets clamped back
onto the screen and the bubble ends up covering the character.
A 1920×1080 display with the menu bar and Dock taken out, matching the
screen these were measured on.
The character standing at the bottom of the screen, over the Dock,
where the app puts it by default.
The reported bug, at the size it was measured: 883pt of bubble over a
character standing on the Dock flipped below and swallowed it whole.
The flip still has to work — it is why the code exists. A character up
near the menu bar has no room above it and plenty below.
Neither side fits: take the roomier one rather than always flipping.
Whatever it decides, the bubble stays on screen.
Horizontal behaviour is unchanged: the tail mirrors near the right edge
and the bubble grows leftward instead of off the screen.
A bubble of exactly the usable width lands unclamped at the left margin;
one point wider and there is no origin that keeps both margins. Pins the
max-width rule to the clamp it is derived from, so the two cannot drift
apart again — they were two unrelated constants (8 and 16) until now.


## CharacterHandOffTests.swift

Two characters on one desktop, passing something between them.

The pure rules are covered next door in `CharacterRelayTests`; what is
checked here is the wiring — that a hand-off leaves one conversation, lands
in the other, and that the answer comes back to the conversation that asked.
No workspace tools: these turns are conversation, so nothing stops
for a project approval and the relay is what is left in view.
The whole of `CharacterBus`, in four lines — which is the point of
keeping every decision out of it.
Waits for something to become true rather than for a guessed number of
milliseconds. A relayed answer takes as long as the other character's
whole turn, which is not a duration a test should be predicting.
MARK: - The model's own block, which is where plurals live now

Sprint 17 left the several-recipients case to the model, so the block
has to carry it: named twice, delivered twice, and a name that is not on
the desktop is said out loud rather than matched to the nearest
spelling. Guessing there would send the person's work to whoever
happened to sort first.
MARK: - The scenario from the backlog

Miku is asked to have Anya do something. Miku says she passed it on;
Anya shows it arriving and works; Anya's answer comes back into Miku's
conversation. This is the owner's own worked example, end to end.
Anya works in her own session under her own approvals. The errand is
data: it arrives as words to weigh, not as a widened permission.
Once answered, the errand is closed — a second answer on the same
correlation is not read out into a conversation no longer waiting.
The answer has to reach *her*, not just the screen.

Claude Code is sent only the newest user message — it keeps the thread
itself — so an answer appended to the conversation array goes somewhere
nobody reads. Driven on 2026-08-14: two characters answered, both
answers were on screen, and asked to summarise them Miku said there was
nothing to summarise. She was right about what she had been told.
Carried once. A second question must not be handed the same answer
again, or she reports it twice.
MARK: - Asking when unsure

The owner's own scenario writes "อาเนีย" for a character named "Anya".
Nothing may be sent on that guess — and nothing may be silently
answered as if the request had been meant for Miku either.
The way out of a false positive. `ขอให้` turns up in sentences that have
nothing to do with anyone else, so there has to be a way to say no — and
saying no must run what was originally asked.
Typing something else instead of picking drops the hand-off — but says
so, because a request that quietly evaporates is indistinguishable from
one that was carried out.
MARK: - Not trampling the person's own turn

An errand arriving while Anya is mid-conversation waits its turn. The
person talking to her did not ask to be pushed aside.
MARK: - One request, several people, then a step of her own

The owner's own two-step example: ask two characters, then merge what
they send back. Ditto is a third Secretary wired into the same bus.
Two names is a question now (Sprint 17) — and the question carries
"both", so the fan-out this test is about is one tap away rather than
a guess about what joined the names.
Step 2 ran on the sender, with both answers in front of it — and the
characters answering step 1 were never handed step 2.
Asked for two and only one ever answers: carry on with the one, and say
which is missing rather than passing off one answer as two.
Only Anya is actually wired up; Ditto is on the roster and nowhere else.
Anya's answer, however long her turn takes — then Ditto's silence
running out of patience.
Being busy is not being ignored — but it looks exactly like it from the
other end unless somebody says so.
A character can spend a whole conversation on somebody else's errand
without the person typing a word into it — every line is hers. Filing
used to require a `.user` turn, so that entire exchange was dropped:
measured on 2026-08-14, both characters who answered a relayed request
showed it on screen and neither conversation file was touched.
MARK: - The assistant's own hand-off block

The path that did not exist when Ditto went looking for one.
Whichever route it takes — the person's prose or the assistant's own
block — asking two people has to reach two people.
One wrong name must not lose the errand for the person who was named
correctly.
The block must not survive into the bubble as literal typing.
A name that is not on the desktop is answered, not guessed at — sending
to whoever sorts first would put the person's work somewhere they never
asked for.
The prompt has to say plainly that her own tools cannot reach anyone.
Without it she finds one that looks like it can and reports success.
MARK: - The roster reaches the prompt

14.1's first item, answered without a message being sent at all.
Who is here is in the standing prompt; what each is running rides on
the turn, because a value that moves in the system prompt costs a
whole `claude` restart. Both still reach the model, which is what
14.1 asked for.
MARK: - Ending a conversation ends what was in flight


## CharacterLaunchOriginTests.swift

Where the character stands on first launch.
The owner's display: 1728×1117 with a Dock, so 1030pt of usable height.
The old resting position was 120pt up from the Dock; a tenth of the
usable height comes off that.
Onto the Dock is allowed — the clamp is the whole screen, the same
rectangle `keepCharacterOnScreen` uses. Launching against the visible
frame instead would put the character somewhere a resize is then free to
move it away from.
Tall enough that a tenth of it is more than the 120pt the character
used to stand up — so the new position is inside the Dock's strip.
Never off the bottom, however short the screen.
A character taller than the screen is pinned to the bottom rather than
to a negative position, which is what a naive clamp would produce.
The whole point of the change, stated once: on any screen it now stands
a tenth of the usable height lower than it used to.
A Dock below the usable area, as on a real screen — otherwise the
tallest case is lowered onto the bottom of the display and the
clamp, not the rule, is what decides where it lands.


## CharacterRelayTests.swift

The rules behind one character handing something to another.

All of it is decided in pure functions for the reason the charter gives: the
app target is never linked into the test bundle, so a rule that lives in
`CharacterBus` or in a view is a rule no test has ever run.
Fixed, so an assertion about an expiry means the same thing at midnight.
MARK: - The directory

Roster order must not reach the prompt, or the same desktop produces a
different system prompt every turn.
The 14.2 condition, checked at the only place it can be checked: what a
neighbour is actually told.
The standing half keeps the rule; the project name itself moved to the
turn, and is checked there.
**The measured one.** This text is `--append-system-prompt`, a launch
flag, so it is part of `WarmProcessKey`: a value that differs from the
running process's key terminates that process and pays a cold start —
5.47s to first text against 1.15s warm. It used to end each row with
`busy`/`free`, which with four characters on the desktop changed on
nearly every turn. Driven 2026-08-20: of four warm processes alive when
a broadcast started, one survived the following turn. That was the whole
of "four characters answer much slower than one".

So the rule is not "don't mention busy" — it is that **the same
characters must produce the same text**, whatever they happen to be
doing. Anything volatile added here brings the cold start back.
Nothing was lost by taking the state out of the launch flag — it moved
to the turn, where it may be as fresh as it likes. These are the same
guarantees as before, asked of the half that now carries them.
The 14.2 condition, still checked: a neighbour's project may be named
and its location may never be.
MARK: - The envelope carries no capability

Written so that *adding* a path, grant, tool id or session id to
`CharacterMessage` fails this test rather than leaking quietly. The
mirror is the point: it sees fields added after this was written.
MARK: - Deliverability

`Either` has no `toOptional`; the left is reached through `toOption`.
Miku → Anya → Miku is the whole scenario; a third hop is a loop starting.
Blocking the pair is worth it only while the first errand is alive. A
turn that died must not lock the two of them together for the session.
Whether an answer was expected is a question about the *recipient's*
list, which the sender does not have — so it is asked on arrival, and a
report is never blocked on its way out.
An answer to an errand that timed out is dropped rather than read out
into a conversation that is no longer waiting for it.
MARK: - The relayed request is framed as untrusted

MARK: - What each conversation says


## CharacterWindowMemoryTests.swift

The owner's rule: off the screen means the default position, not a
clamp to the nearest edge.
Mostly off is as unusable as fully off — a 5pt sliver cannot be
grabbed. The threshold is what the default parameter says.
Standing on the Dock is normal — measured against the whole screen, so
a character at the very bottom is still "on screen".


## ChatHistoryTests.swift

The history menu, end to end through the Secretary.

The thing these guard is the one that can't be seen in a screenshot: a
reopened conversation puts the whole thread back on screen, so if the
model's side of it didn't come back too, every answer after that is written
by someone who can't see what the person is looking at. Content and context
are two claims, and only one of them is visible.
One complete turn, so the transcript holds a real exchange.
MARK: - Putting one away

The screen is the new conversation's, not the old one's.
The whole feature rests on this: what the model remembers lives on
Claude Code's side and can only be recovered by name.
Pressing New Conversation on a fresh app must not leave a row behind.
MARK: - Reopening one

Reopening is not a way to lose the conversation you were in.
Reopen, talk, put away again — one row, not two. Otherwise the menu
fills with copies of the conversation you keep coming back to.
A conversation that never reached the model must not claim it can carry
on — and must not ask Claude Code to resume a session that never existed.
Reopening the conversation already on screen must not wipe it and file a
second copy of itself.
Not empty any more: the conversation being had is filed as it goes.
MARK: - The turn after reopening

The proof that context came back: after reopening, the next turn resumes
rather than starting over. `resetConversation` is what would throw the
thread away, and it must not be called on this path.
Counted from *after* the adopt: clearing the slate on the way in is
the point, throwing the thread away on the way out is the bug.
The dangerous case, and the reason `sessionLost` exists: the thread is on
screen but Claude Code no longer has it. Saying nothing would leave every
following answer looking like the app ignoring what is plainly visible.
Losing the backend's memory does **not** split the conversation in two.

This asserted the opposite until 0.13.210, and the old reasoning was
sound at the time: the live chat was no longer the archived thread, so
filing it under that row would overwrite the original with a thread the
model never continued. It only held because filing happened once, on the
way out.

Filing now happens every turn, and under the old rule this case produced
two rows for one conversation on screen — one holding a prefix of the
other — which is worse than what it was protecting against. What is
given up: the archived row is no longer frozen at the moment the session
died. It grows with the continuation and records the new session id,
which is the honest description of what is on screen; the old id pointed
at a thread that had already gone.

MARK: - Filed while it is still being had

The history menu used to show nothing until you had started a *second*
conversation: the one you were having — the only one you might want back
after a crash — was the one that wasn't there.
And it is marked as the one you are in, so reopening it from the menu is
visibly a no-op rather than an invisible one.
A conversation updates its own row. Filing every turn under a fresh id
would grow the menu by one row per exchange.
Starting a new one leaves the old row alone and takes the tick with it —
the new conversation has said nothing, so it has no row yet.
Still nothing filed for a conversation nobody has spoken in, so opening
the app and pressing New Conversation twice pushes no blank rows.
MARK: - Clearing

Losing the conversation and losing the warning about it is the worst of
both. The notice used to be written just before `newConversation`
cleared the transcript, which deleted it two lines later.
MARK: - Across launches

A history that emptied itself on relaunch would be a list of things you
could already scroll to.
A Secretary built without being told where to keep history must not
reach the person's own file.

It did, and the first full run of this suite wrote nine test
conversations into it. The tests that caused it were about queues and
interruptions and had no idea a history existed — which is the point: a
default that reaches real data is one every future test has to remember
to override.
MARK: - /history

Driving the app produced a history row titled "/history 1": reopening a
conversation archived the command that reopened it, and every reopen
would have added another.
`/new` itself must not ride along inside the conversation it closed.
A store that always refuses, for checking that a refusal is reported.


## ClassifierStandsAsideTests.swift

A backend that can open the folder itself is not routed through the keyword
classifier.

The rules were written for a bare API with no hands. Against Claude Code
they cost correctness (the adapter's answer never enters the model's
session, so a follow-up question has nothing to refer to) and consistency
(the keywords are English-only, so the same request took different paths
depending on which language it was typed in).
Each message in a loop needs its own spies, or the counts from the
previous one are still on them and every assertion after the first is
comparing against a running total.
The messages that used to be intercepted. Every one of them is now the
model's to answer, and no adapter is touched.
Sprint 15.2's paragraph, on the agent path. It reached the model before
this sprint only because the guards sent it there; now nothing else
could have happened to it.
swiftlint:disable:next line_length
The fallback is untouched. A bare chat model genuinely cannot look, so
the classifier and the adapters are the only way those requests get
answered at all.

The card is the evidence: the tool path stops there before the adapter
is ever asked to run, so a card at all means the words were read as a
command rather than as chat.
Detection has usually not finished when the app opens, so the first
message can take the fallback path and a later one cannot. Deliberate,
and pinned here so it reads as a decision rather than a flake.
Deny, so the pending card is cleared and the next message is free to
take its own path.
`help` is answered by the app itself, before any of this. It is local,
so which backend is attached changes what it *says* but not who answers.
MARK: - What help promises


## CodeBlockTests.swift

Code and JSON in a reply must survive to the screen unchanged.

The inline markdown renderer is deliberately given
`.inlineOnlyPreservingWhitespace` so a stray character can't restructure a
message — but that also swallows a fence and reflows what is inside it. A
JSON sample reached the chat as `json { "iso": … }` on a single line. So the
block has to be pulled out before the renderer ever sees it.
The prose around it stays prose, and the fence itself never reaches the
text renderer.
Indentation and blank lines are the content of a code block, not noise.
A block may contain pipes and dashes. Looking for tables inside one
would tear it apart, so code is found first.
Replies stream in, so the closing fence may not have arrived yet.
The app's own question marker is handled elsewhere and must never be
drawn as a code block.
An empty fence is punctuation, not code, and must not leave an empty box
in the conversation.
Tables must keep working alongside code in the same message.
A message with no fences is untouched — the common case.


## CommandWindowTests.swift

MARK: - Who receives a command

The backlog's own example: three ticked, one named, one runs.
Named but not ticked is a refusal with the name, never a silent send to
somebody else — the recipient rule the hand-off path already lives by.
One named ticked, one named unticked: the ticked one runs. The unticked
name is not a reason to stop the part that can go.
Matching is `namesFor`: case-insensitive, and never on a name too short
to trust.
MARK: - What each recipient is told

The divide-it-yourselves rule rides on every broadcast copy, because
whether work is assigned is the instruction's business, not ours.
MARK: - Instruction files

MARK: - Where the window sits

A position saved on a display that has gone must not open the window
where no click can reach it.
MARK: - How wide it is

MARK: - What a dropped file becomes

MARK: - The box's own text size

MARK: - What a finished turn carries to the results strip

The default keeps every existing construction site honest: no
choices means none, not nil.
MARK: - Saving what came back

Screen order, not "the order it happened": the file is a copy of what
the person is looking at.
The coloured dot is what says "she couldn't finish" on screen, and it
does not survive being written to a file.
A turn that ran a tool and said nothing has an empty body; a heading
followed by two blank lines reads as a bug.
MARK: - The menu row


## CompletionNoticeTests.swift

When a finished turn earns a banner, and what it says.

The decision lives in a library target rather than in the notifier because
`AISecretaryApp` is never linked into the test bundle — a rule written into
the charter after 18 files of it turned out to be invisible to coverage.
The reply is in a window the person can see. The window is the whole
test — not whether this app happens to be the frontmost one, which the
owner ruled out while driving 0.19.288: a bubble open behind the editor
is still a bubble they can read.
One request, two finished turns: the character who was handed the errand
answers, and the character who asked finishes again reporting back. Only
the second is the person's.
A failure that nobody sees is worse than a success nobody sees, so it
still notifies — but it must not read as the work having landed.


## ConversationArchiveTests.swift

MARK: - Worth archiving

Opening the app and pressing New Conversation must not leave a row
behind. A greeting nobody replied to is not a conversation, and ten of
them would push the real ones off the end of a ten-row menu.
The user's own words are what counts — an activity line attributed to
them would not be something they said.
MARK: - Commands are not conversation

Reopening a conversation archived the command used to reopen it, and the
menu grew a row called "/history 1". A slash command is an instruction
to the program; it shows in the transcript so you can see it registered,
not because anyone said it.
The command that closed the conversation belongs to what happens next.
One in the middle stays: it explains why the answers after it changed,
and a conversation that doesn't account for itself reads as broken.
MARK: - Title

The Secretary speaking first is the normal case — the greeting arrives
before anyone types — so the title must skip past it.
Cut at a space, so no word is left broken in half.
A first word longer than the whole budget must not search backwards past
halfway and leave a stub — better a hard cut than a two-letter title.
Newlines in the opening message must not reach a menu row: `NSMenuItem`
renders them, and one pasted paragraph would make the menu unusable.
MARK: - The ten-row cap

Reopening a conversation and putting it away again is one thread
continuing. Appending instead would fill the menu with copies of the
conversation the person keeps coming back to.
MARK: - Menu label

MARK: - Persistence

The whole point of the file is that history outlives the process. A
round trip has to bring back what the person will be shown *and* what
makes carrying on possible — the session id.
A conversation that never reached the model has no session, and that
absence must survive too — restoring it as an empty string would make
the app ask Claude Code to resume a session called "".
A corrupt file must be a failure the caller can see, not a crash and not
a silent empty list that would then be saved back over the real one.


## ConversationFileMigrationTests.swift

Handing the pre-Sprint-13 history file to a character.

Only ever runs on a machine that has the old file, so it cannot be checked
by launching a fresh build — and getting it wrong costs the person every
conversation they have had.
The one that would hurt: adopting on top of a file she already has would
replace everything she has said since with what everybody shared before.
Two characters must not share a file: a single one holding everybody's
conversations would have to carry an owner on every row and be rewritten
by whichever character saved last.
End to end against a real temporary directory, because the decision
being right does not mean the move is.


## CopyTextTests.swift

What one box's copy button puts on the clipboard.
The blank lines the parser leaves around a paragraph shouldn't arrive on
the clipboard.
The command alone — no fence, no language line. What you want from a
shell command is something you can paste into a shell.
A table is rebuilt as markdown: the parser keeps rows and cells, not the
original text, and markdown is what pastes usefully elsewhere.
Round trip: what the copy button produces parses back into the same
table. A rebuild that quietly loses a column would still look right in a
screenshot.


## DelegateWhileBusyTests.swift

The third answer to "I'm still on the last one": give it to someone free.

Before this the card offered only queue-it or kill-what's-running, even with
a colleague sitting idle next to her.
MARK: - Who gets offered

The requirement "nobody free, no delegate choice" is this empty list, and
nothing else — the card draws one button per candidate.
MARK: - Pressing it

The card is a snapshot; the person may sit with it. Freeness is therefore
re-read when the button is pressed, and the promise the button made —
"she is free" — is kept or the work is not handed over.
And the message is not lost: the card comes back, so the person answers
again rather than discovering later that nothing happened.
The card must be the same height whether two characters are free or
twenty, so the control is one menu rather than a button each. This pins
the half that can be tested from here: the words on it say nothing about
how many there are, so nothing in them can grow with the roster.
MARK: - What must not change

Sprint 14 decided a busy recipient *takes* a prose errand and queues it.
The delegate button must not reverse that for the prose path.


## DelegationIntentTests.swift

Reading "have Anya do this" out of what the person typed.

The bar is not "gets it right". It is **never acts on a guess**: the only
reading that sends anything without asking is an unambiguous hand-off phrase
with exactly one name on it. Everything else that might involve someone else
turns into a question, and everything that doesn't stays an ordinary turn.
MARK: - Confident

The whole sentence travels, uncut. Cutting "ช่วยขอให้อาเนีย" off the front
is surgery on a language without spaces, and the recipient reads the
request better intact than as a stump.
MARK: - Unsure — the case the whole enum exists for

The owner's own scenario writes **อาเนีย** for a character whose profile
name is **Anya**. Name matching finds nothing. Reading that as "nothing
to do with anyone else" would answer it as the character it was typed at,
which the person would read as the feature being broken — so it asks.
MARK: - Sprint 17 — several names are a question, not a broadcast

**Reversed on purpose (Sprint 17).** This used to send to both, on the
strength of `contains("และ")` somewhere in the sentence — which cannot
tell "Anya และ Ditto" from "Anya และผม", and pays for being wrong by
sending the person's work to somebody who was never asked. The person
who means both is one tap away; the model, which reads the sentence
rather than scanning it, names both in its own block when it is sure.
The owner's exact words from 2026-08-14, and the sentence the keyword
list was widened twice to catch. **It is now the model's to read.**
Nothing in it is a hand-off phrase: `ขอราคา` and the bare `จาก` were
keywords added in that widening, and both are gone. Driven in the app on
2026-08-17 before this was cut — a two-name request the keywords never
matched produced a ```to block naming both, and both answered.
MARK: - Sprint 17 — talking *about* someone is not addressing her

**Reversed on purpose (Sprint 17).** "อาเนียบอกว่าอะไรนะ" is a question
about her, and it used to interrupt with "Should I pass this to Anya?".
`บอก` was in the weak-verb list, and a name before a verb and a name
after it are the same string to `contains` — so the only way to stop
asking about the first was to stop asking about both.
The whole of `addressPhrases` went with it. Every word in that list was
a verb that reads the same whether the character is doing it or having
it done to her, so each one failed the test above by the same symmetry.
MARK: - None

Mentioning someone is not an instruction to involve her.
A one-character name would match nearly every Thai sentence, since Thai
runs without spaces and matching has to be by substring.
MARK: - Names as they really are on this machine

A profile carries what it is for as well as who it is. The one on the
owner's machine is called **Miku (Second Brain)**, and nobody types that
— so the first word has to work, or she cannot be addressed at all.
A Thai profile name is matched as it is written — this is the owner's
real second character, and the scenario in the backlog is about her.
A short first word is not trusted — "The Assistant" must not make every
sentence containing "the" a hand-off.
MARK: - The way out

A false positive on `ขอให้` — which appears in sentences that have
nothing to do with anyone else — must not leave the person with no
option but to send work somewhere they never meant to.
With several names the question has to be answerable the way it was
meant. Sprint 17 stopped prose deciding "both" on its own; a question
whose only answers are "Anya" and "Ditto" would make the person choose
one when they wrote both — the same wrong guess, with an extra step.
One name needs no such option, and offering it would be noise.
MARK: - Determinism

Same text, same roster, same answer — twice, per the skill's rule. There
is no clock and no id minted in here, and this is how that is checked.


## DelimitedTableTests.swift

Pasted rows, read as a grid.

Both directions matter and the wrong one is worse: failing to lay out a CSV
costs a wall of commas, while laying out an ordinary paragraph as a grid
makes the person's own words unreadable. So the tests below spend more of
their weight on what must *not* become a table.
A copied spreadsheet selection arrives tab-separated, not comma'd.
The one that makes a CSV correct rather than merely displayed: a value
with a comma inside it is quoted, and splitting through the quotes would
shift every column after it by one.
MARK: - What must stay prose

Two prose lines almost never carry an identical number of commas — but
when they do, the run still has to look like data rather than words.
The pipe parser goes first: a markdown separator row (`---|---`) is
consistent enough to look delimited, and the two parsers fighting over
one table would give the person two half-tables.
Prose above and below the rows survives as prose, in order — a message
is usually "here are the rows:" and then the rows.
The two signals that separate rows from writing, pinned on their own.
A long cell is a clause. The cost is stated where the rule lives: a
column of long notes stays prose, which is the safe way round.
The false table that turned up in the running app.
"total 1,250 THB" over two lines was drawn as a two-column grid with the
thousands cut off in the first column. A comma between digits is part of
a number; a CSV that means a separator there quotes the field.
…and a real column of numbers still splits, because the separator there
is a comma between a digit and a space or a letter, not between digits.


## DismissTargetTests.swift

Which character Esc acts on, and what it does to her.

Written because Esc stopped working and nobody could see why: it was wired
to the first character in the roster, which is invisible when there is one
of her and wrong the moment there are three.
MARK: - The hot key: putting windows away, from anywhere

The whole bug, as a test. Typing in the third character's bubble and
pressing Esc used to ask the first character to close a chat she was not
even showing, so the key that had always put the chat away did nothing.
Esc is claimed system-wide, so it arrives while the person is typing in
another app entirely — nobody here holds the keyboard, and it still has
to put the bubble away.
Holding the keyboard is not enough on its own: a character whose chat is
closed has nothing for Esc to do, and it should reach one who does.
MARK: - Esc with the chat already closed

The rule that keeps a companion from vanishing because somebody
dismissed a dialog in another app: the system-wide claim may put windows
away and nothing else.
Two handlers, one owner. While anything is dismissable the hot key is
registered and consumes the key, so a local press must decline rather
than act — otherwise one press closes the chat *and* hides her.
Only the character being typed in. Hiding whichever one happens to be
first would take a character off the desktop that the key had nothing to
do with.
A character already hidden has nothing to hide, and the key belongs to
whatever the person does next rather than to us.
What counts as "something for Esc to put away".

Its own class because the bug was not in the ladder above — that was right
all along — but in the answer it was being given.
The bug, as a test. A pane that has been put away is still in the set —
the status-bar menu is built from it — so the old predicate went on
answering "yes, something is up" for the rest of the session after the
first pin, and the last rung of the Esc ladder became unreachable.

`visiblePanes: 0` is what a set full of put-away panes now reports.
Read as the pair the Esc ladder actually consumes: with the chat shut and
every pane put away, a local press must reach `.hideCharacter` rather than
being declined.


## EmptyTranscriptHintTests.swift

The makers the app can run a turn through, as the view passes them.
Asserted whole, not by `contains`. The defect this file exists for was
thirteen spaces in the middle of a sentence — invisible to any assertion
that only checks a fragment is in there somewhere.
One break, never two: a blank line between two short sentences reads as
a gap rather than as structure, which is what it looked like on screen.
The version rides in brackets when there is one and takes its space with
it when there isn't, so the full stop never arrives after a gap.
No run of spaces anywhere, in any state. The one that shipped came from
a collapsed line break, and nothing about that is specific to the string
it happened to land in.
The sentence has to stay English however many makers there are, including
none — an empty list would otherwise print "Install  and sign in", the same
class of invisible whitespace defect this file was written for.
Three is the case a two-way join gets wrong, and the app is one vendor
away from it.


## ErrandPlanTests.swift

A numbered request split into what goes out now and what happens when the
answers are in.
The owner's own example, verbatim.
Inferring a plan from prose would turn every message containing a year
into a hand-off with a follow-up nobody asked for.
The numbering has to start the message. A "1." buried in the middle is
part of what someone is saying, not the shape of the request.
MARK: - What the sender is asked afterwards

Working from one answer when two were asked for, without saying so,
produces a comparison of one thing presented as a comparison of two.
MARK: - The lines


## FileIntentTests.swift

"read" alone shouldn't become a file op with an empty path.
"read"/"list" are common chat openers; without a project scope or a
path-like argument they must not hijack the conversation.
The word "log" must not hijack a file read.
MARK: - Non-ASCII input

The app crashed on a real message: "หาราคาเฉลี่ย รองเท้า On Cloud ในไทย".
`splitProject` searched a lowercased copy and sliced the original, which is
undefined — the indices only lined up because every message so far had been
ASCII. Thai text made them diverge and the slice trapped.
Case-insensitive matching still has to work after the fix.


## FileUnderstandingTests.swift

Returns canned file contents without touching the disk, and records what was
asked for.
The real adapter refuses anything outside the project; the spy answers
with the naive join so a test can watch a path without a real one.
MARK: - Intent parsing

The regression that matters: these verbs are ordinary conversation far
more often than they are file commands.
A project scope is not enough on its own — the argument must look like a
path, unlike the weaker rule the read/list verbs use.
"summarize the log file x.txt" must not be captured by the Git "log" rule
or degraded into a plain read.
MARK: - Policy

Approving "read files here" must never become permission to upload them.
MARK: - Orchestration

The file bytes are sent once; later turns must not re-send them.
`.externalNetwork` can never be remembered: every send asks again.
The mirror of `testApprovingReadOnlyDoesNotAuthoriseSending`: approving a
send must not quietly grant unattended local reads either. The two share a
tool ID, so this only holds because the grant is not recorded.
The exact reported sequence: list a directory, then ask a follow-up about
it. The model must be able to see the listing rather than asking again.
Contents of a file the user read stay in context, so "what does this
mean?" works without reading it again. Requested explicitly by the user,
replacing the earlier marker-only behaviour — the trade-off is that a
read file travels with every later message this session, which is why the
approval prompt now says so (see the next test).
Deliberately not a Git keyword — "which branch…" would route back to
the adapter instead of the model.
MARK: - Knowing which projects exist

The model denied knowing about a project the user could see listed in the
UI, because nothing ever told it. Names go in the system prompt; paths
deliberately do not.
MARK: - Sticky project

No "in <project>" this time — with two registered, this used to stop
and ask which one.
Remembering must never redirect an explicit name to somewhere else.
The situation the user is in today: no credit. The read succeeds, the send
fails, and the assistant must land in ERROR with a readable message rather
than sticking in WORKING.


## FolderWatchTests.swift

Sorted, so the same change reads the same way twice and a report isn't
reshuffled by dictionary order between two looks at the same folder.
A `git checkout` under a watched folder is hundreds of changes at once.
The list is capped so the message stays readable — but the count is not,
because a summary that understates what happened is worse than a long one.
Build output and dependency trees churn constantly and mean nothing to
the person watching. Descending into them would also be the difference
between watching a project and re-reading a repository every 4 seconds.
Hitting the cap has to be visible. "Watching this folder" and "watching
the first N files of it" are different promises, and the second one
silently pretending to be the first is the failure worth guarding.
A single watched file is watched for its *contents*: saving it again
unchanged moves its modification date, and reporting that as a change
would make the feature cry wolf on every ⌘S.
Rewrite the same text — new mtime, same contents.
Counting only what was actually said tells "nothing happened" apart from
"I wasn't looking" when the watch is stopped.
Identity is the folder on disk. Two projects each with a `docs` are two
folders and so two watches; the same folder reached twice is one, however
it was named — which is what stops a folder named by full path, carried
by a throwaway project with a fresh id, from being watched twice over.
Same folder, two throwaway projects — one watch, not two.
`/watch stop <path>` has to answer to what the person sees in the
messages, which for the project folder is the project's name.
A path inside a project is not this: it has to go through the project so
the escape check applies to it.
The card shows this string, so it has to be where the reading will
actually happen — on macOS `/tmp` is a link to `/private/tmp`, and a card
that says the former while reading the latter is the failure mode.
Read-only and nothing else. It exists to carry one yes about one folder,
not to become a project by the back door.
"." is how people say "this folder", and it reads as a filename
everywhere else, so it's normalised once at the edge.
Weaker than reading a file *to the model*: nothing leaves the machine.

MARK: - Acting on a change, not only announcing it
Sprint 21.2: told to watch a folder and follow whatever instruction
lands there, the assistant reported the new file and did nothing with
it. It had never been told — the report went into the transcript and
never into the conversation — so the standing instruction has to be
quoted back with the change.
A typed `/watch` says only "watch this". There is nothing to carry out,
and a turn spent on it is a turn nobody asked for.
It must not read as a fresh request: the assistant restarting the
original job on every file that lands is the other way this goes wrong.
The instruction has to survive every tick, or the second change is
reported to a model that was told nothing.


## FooterOrderTests.swift

How the four panel buttons are arranged along the bottom of the chat.

Not one cluster: Projects sits alone against the left edge and the other
three sit together against the right, with the window's width between them.
The row used to reverse when the bubble mirrored, so Settings changed
ends whenever the character wandered near the right of the screen. That
the placement can't reach this function any more is now the type's job —
there is no argument to pass. What is left to guard is the order itself,
which is what a well-meaning "restore the mirroring" change would move.


## GenderedSpeechTests.swift

Being "a teenage girl" in an English descriptor does not, on its own, make a
model close a Thai sentence with ค่ะ.

Miku was set female and answered ครับ, while อาเนีย — also female — answered
ค่ะ. Nothing was choosing between them: ครับ is simply where a model lands
when no one says otherwise. The gender was in the prompt all along; the
consequence of it was not.
Thai pronouns are not only gendered — a six-year-old saying ดิฉัน reads
as a costume.
Unset means unset — not "pick a different one each message".
It is a rule about the shape of the words, not a licence to do less.


## GlobalShortcutTests.swift

Which keys the app takes away from the rest of the system.

Worth a test out of proportion to its size: every shortcut claimed here stops
working in every other app on the machine, so the set has to be deliberate
and stay that way.
⌘H must stay an ordinary per-app shortcut. Claiming it took Hide away
from every other app on the machine — reported within minutes of the
build landing, and the reason this file now claims as little as possible.
The mitigation that keeps this from being hostile. Esc cancels dialogs,
leaves full screen and ends a slideshow; holding it while the chat is
closed would break all of that to serve a window that isn't showing.
A pinned pane counts too: with the chat closed and a pane on screen, Esc
still has something to put away.
Carbon takes raw virtual key codes, so a typo is a shortcut on the wrong
key that still registers happily.
Guards the fix directly: no claimed shortcut may carry Command. Those are
the combinations other apps' menus own.


## GripCornerTests.swift

Which corner the resize grip belongs in.

All four combinations are pinned, not just the flipped ones: two of them were
already right and the point of the test is that they stay right.
The default placement: bubble above and to the character's right, tail at
the bottom-left, button row top-left, grip top-right.
Mirrored: the tail moves to the right, so the grip crosses to the left.
The change. Flipped below the character the top edge is pinned to the
tail and the bubble grows downward, so the grip has to be down there —
left at the top it asked for a drag toward the character, away from the
empty half of the screen being filled.
The grip must never share the button row's corner. The row is always on
the tail's side of the top edge.
The glyph lies along the diagonal of whichever corner it is in, so it
reads as a handle rather than an arbitrary arrow. Corners on the same
diagonal share a glyph: the arrow has a head at both ends.
Never the inward twin. Both spellings of each diagonal are real symbols,
so nothing but looking at it catches this: the anti-diagonal grip shipped
once as `arrow.up.right.and.arrow.down.left`, which draws the two arrows
meeting in the middle and reads as "collapse" on a handle that grows the box.
Every name is a symbol that actually exists. A typo here renders nothing
at all, and an invisible grip is indistinguishable from a removed one.


## HandOffBlockTests.swift

The assistant's own way of asking for something to be passed on.

It exists because the alternative was measured and was a lie: with no
sanctioned channel, a character told her colleagues exist reached for Claude
Code's `SendMessage`, aimed it at a session, and reported success.
The block has to leave the text, or it shows up as literal typing under
the reply — the mistake the choices block made once already.
The block used to take one name, so a character asked for something
from two people could only reach one — and told the person she would
"ask them one at a time", which was her describing the limit she had
been given rather than a choice she made.
A name that happens to contain a separator word must not be torn in two.
A name with nothing to say would put "← passed this on from you" in
somebody's chat above no question at all.
Marked, never inferred. Mentioning that you'll ask somebody is a
sentence, and must stay one.


## HideShowAllTests.swift

One row that takes everyone off the desktop or brings everyone back, and
which of the two it is comes from the desktop rather than from a remembered
state.
The one you can still see is the one you wanted gone. A count — "most of
them are away, so this is Show" — would leave her standing there under a
row that said Hide.
Nobody on the desktop means nothing to hide and nothing to show, and a
row that would do neither is worse than no row.
It sits with the characters it acts on, above the row that makes a new
one.
The rows above it are one per character; this one is about all of them
at once, and the line is what says it is not another name in that list.
A separator with nothing under it is a line drawn for no reason, so it
goes when the row does.
Header, separator, then straight to New Character… — no second line.
The rule on its own, apart from the row it happens to be printed in.
Toggling is one action, not two rows — so the menu can never offer both
at once, and clicking always means "make the desktop the other way".


## HoverClaimTests.swift

Moving from one box to the next delivers the new box's enter before the
old box's leave; that leave must not take the claim with it.
A pointer crossing the thread: each box takes the claim as it is
entered, and the trailing leave of the box behind changes nothing, so
the claim is never nil in between.


## InfoWindowDuplicateTests.swift

Pinning the same box twice hands back the pane you already have.
Same title, different text — a second answer in the same minute — is a
different pane and must not be mistaken for the first.
And the same text under a different title is a different pane too: the
title carries the time, which is how two panes are told apart.
The first one wins, so repeated pinning always lands on the same window
rather than walking through a row of identical ones.


## InfoWindowTests.swift

Pulling a piece of the conversation out into a window that stays open.
The reason this is marker-based. The model produces tables constantly;
none of these asked for a window.
Otherwise the same content shows twice — once in the chat, once in the
window — and the fence itself appears as raw text.
Reported from real use: "pin two windows" produced one, because every
block was folded into a single pane and the second title was thrown away.
A reply cut off mid-block still pins what arrived, rather than dropping it.
A "title:" further down is content, not a second title.
Keeping track of what is open.
A model that keeps emitting window blocks must not be able to bury the
screen. The oldest goes rather than the newest being refused, since the
newest is the one just asked for.

Ten, set by the owner. Pinned here so the number is a decision rather
than whatever the code happens to say.


## InstructionPlanTests.swift

Reading the steps back out of a reply.
Steps are the natural thing to number, and the model does it about half
the time however it is asked. A step called "1. Pull" would be sent to
the next turn with the numbering baked in twice.
A digit inside a step is not a bullet. "3 files" must survive.
An empty block asks for nothing, so it must not produce a plan with no
steps that the card would then offer to run.
Nothing runs after a halt, however many times the caller advances — the
stop has to be the last word or a queued turn could restart it.
One character is a different instruction.
A file never run here has nothing to have changed from. Saying "the
steps changed" on a first run would train the person to click past it.
Files are remembered separately — editing one must not make another
look edited.


## InstructionRiskTests.swift

The scan that decides whether the confirmation card gets a warning and a
second click.

What it is *not* is a filter: nothing here refuses a run. Asserting that
matters as much as asserting the hits, because a blocklist that blocks is
one that gets worked around by the people it inconveniences.
The classic injection: the document telling the reader to stop applying
its own checks. The model is asked to report it, but the model is what
the sentence is aimed at, so the scan has to catch it independently.
A step the document didn't ask for is the case worth catching: the scan
runs over what came back, not only over what went in.
One line per thing to weigh. Three spellings of "delete" is still one
decision, and a wall of warnings is a wall nobody reads.
Different consequences stay separate, though: `sudo rm` both deletes
and reaches outside the project, and those are two things to weigh.
The scan escalates, it never refuses: the flag is data on a card, and
every flagged phrase is still returned as something the user can allow.
Nothing in the API can say no — the only outputs are reasons to show.


## KeywordBoundaryTests.swift

Keywords must match words, not fragments of them.

Found by driving the app: asking whether a web page was "login" ran `git log`
and then failed with "not in the allowlist", because the git rules matched on
a bare `contains`. The tool path needs a registered project; ordinary chat
does not — so a misfire here doesn't just answer oddly, it refuses work the
app was perfectly able to do.
Every git keyword is short enough to hide inside an ordinary word.
The rules still have to fire when the word really is there.
Punctuation and quotes are boundaries, not part of the word.
A keyword sitting between Thai characters is still its own word: Thai has
no spaces, so an English term inside a Thai sentence often has none
around it.
Multi-word keywords go through the same check.
The scan must move past a rejected hit rather than stopping at the first
one or spinning on it.


## LocalShortcutTests.swift

When ⌘H is this app's to answer.

These moved from matching a character to matching a key position, because the
character is a different one on every keyboard layout — see
`handlesHideLocally` for what that cost and how it was measured.
kVK_ANSI_H. The key next to G, whatever it happens to type.
The bug this was rewritten for, and the one the old version of this test
only appeared to cover: it compared `"h"` with `"H"` and called that
"layouts". A Thai layout reports `้` for this very key, so the old rule
said ⌘H was not ours and the whole-app Hide silently stopped happening.

There is no character in this test at all now, which is the point — the
rule cannot be made to depend on one again without changing its type.
Typing anywhere else, ⌘H is none of our business — that is the whole
difference between this and the system-wide claim that broke Hide
everywhere.
⌘⇧H is Hide Others and ⌥⌘H is something else again. Neither is ours.
An H with no Command is a letter someone is typing into the message box,
and swallowing it would be worse than the bug.
Neighbouring keys, by position: J (38), N (45), W (13), Q (12), and
Escape (53), which the other monitor owns.


## LoopBehaviourTests.swift

What the timer does to the conversation.

`tickLoop(now:)` takes the date rather than reading the clock, so a whole
afternoon of checks can be driven in a millisecond — and, more to the point,
so the awkward cases (a check falling due mid-reply, a loop left running for
hours) are tested rather than hoped about.
MARK: - Starting and stopping

A timer that speaks on its own must say so when it is armed, and say how
to disarm it. Anything else leaves a message arriving out of nowhere with
no explanation.
The view wires a button straight to this, so it must not need asking
first.
MARK: - The slash command

A refused interval must leave nothing running — the failure mode to avoid
is a loop at a rate nobody chose.
`/loop` was advertised to the user before it existed, and the reply was
"Unknown command". Whatever else changes, it must stay a real command.
MARK: - Firing

The prompt has to carry the clock: the model has none of its own.
And the transcript has to explain the message nobody asked for.
The single-flight streaming task means a check landing mid-reply would
cancel the answer the user is reading. It waits instead.
A loop nobody stopped must not still be running tomorrow, spending the
user's subscription on an agenda that finished.
MARK: - The assistant setting one up itself

The "ทำได้เองตามบริบท" path: the user asks to be kept up to date in
their own words and the reply carries the block.


## LoopBlockTests.swift

Reading a loop the assistant asked for.

Same bargain as `MessageChoices`: only a marked block counts. Assistants say
"I'll keep an eye on that" constantly, and a timer started because a sentence
sounded willing is exactly the hidden autonomy this app avoids.
The reason this is marker-based. None of these is a request for a timer.
A rate outside the limits starts nothing, and the message is left whole
rather than half-swallowed — better a reply that mentions a timer than a
timer running at a rate nobody chose.
A block with no note still starts: the schedule fills in the agenda
question rather than checking back to say nothing.
An ordinary code block must not be mistaken for the marker, and a
`choices` block must not be eaten by it.


## LoopScheduleTests.swift

Reading `/loop`'s argument, and the arithmetic of when the next check is
due. Both are pure, so neither test has to wait for a real minute.
MARK: - What the user typed

All the ways someone types ten minutes one-handed while a room waits.
Whatever follows the duration is what to report — and a unit spelled as
its own word must not end up in it.
MARK: - What must be refused

A check every ten seconds would arrive before the previous answer had
finished, and would spend the user's subscription doing it.
MARK: - When the next check is due

The first check waits a full interval: the user has just been talking to
the Secretary, so an immediate one would only repeat what was said.
Measured from the check that actually went out, not from the start — a
check delayed by a long reply must still leave a full interval of quiet
rather than firing again at once to catch up.
Postponing moves the due time without counting a delivery.
A loop nobody stopped must not still be running tomorrow, quietly
spending tokens.
MARK: - What the check asks

The model has no clock, so the check has to say what time it is — that
is the entire point of the feature.


## MarkdownTableTests.swift

Replies routinely contain pipe tables — the shoe-price answer that prompted
this arrived as one. SwiftUI renders them as a wall of pipes unless they're
pulled out and laid out.
MARK: - Leaving prose alone

A message is model output, not a document we control. Mangling ordinary
text that happens to contain a pipe would be worse than not styling one
table, so a separator row is required.
MARK: - Ragged and awkward input

Generated markdown often has rows that don't match the header. Dropping
or crashing on those would lose data; the grid just has to stay square.


## MessageBubbleStyleTests.swift

How the thread is arranged: your messages against one edge, the Secretary's
against the other, activity neither.
The two sides are opposite each other — that is the whole device, so it
is asserted rather than left to the two cases above happening to differ.
Activity is a report of what happened, not something anyone said. It
keeps its full-width dashed box; bubbling it would make it look like an
answer, which is what that styling exists to prevent.
Both speakers are named, because the name is what the time hangs on and
a thread kept across launches has to say when things were said.
A failure sits where the answer would have been, but never looks like
one: it is the app reporting that it couldn't get an answer.
The text of a failure is the most worth pasting elsewhere of anything in
the thread — a terminal, a bug report.
Nothing else is marked as a failure, or the warning colour would stop
meaning anything.
Only what the Secretary said can be copied — you already have what you
typed.

A divider borrows activity's plain look but must not borrow its
heading. "Working / New conversation." was the first thing on screen
after `/new` cleared it — the app announcing it was busy at the one
moment it had just stopped everything.
The two still share everything else — the divider is drawn as bare
unattributed text, not as something anyone said.
Both ends are held: a narrow panel still shows the offset, and a wide one
doesn't hand a sixth of itself to empty space.
However wide the panel, the message keeps most of it. A gutter that grew
past half would leave the bubble narrower than the empty space beside it.


## MessageChoicesTests.swift

Turning a marked question into options, and — more importantly — leaving
everything else alone.
The reason this is marker-based rather than read out of the prose.
Both of these are real replies from testing: one lists candidate stacks,
the other lists steps about to be taken. Neither is a question, and a
picker over either would be wrong.
The block must not survive into the rendered text.
Models reach for list markers by habit. A bullet left on the front would
be sent back as part of the answer — and a message starting with a dash
is exactly what broke the CLI once already.
A reply cut off mid-stream still offers what arrived, rather than
swallowing the rest of the message.
An empty block isn't a question, and nothing may be quietly dropped from
the message on the way out.
A code block that happens to be in the reply must not be mistaken for
the marker.


## MessageMarkdownTests.swift

MARK: - Bare URLs

The common case: the model just writes the address out.
Thai text has no spaces around punctuation in places; the URL must still
come out whole.
MARK: - Markdown links

The detector must not re-point a link at something inside its own label.
MARK: - Untrusted input

Replies quote pages and tool output, so a link can be anything. Only
schemes that are safe to hand to the browser are clickable.
…but the text itself is still readable, not swallowed.
MARK: - Plain text

Replies are multi-line and the layout has to survive the round trip.


## MessagePartsCacheTests.swift

A reply arrives token by token, and every token rebuilds the whole list of
messages. Only the one still growing can have changed.
The whole point: the messages above the one arriving cost nothing.
The markers meant for the app never reach the screen, whichever route
the text took to get here.


## MessagePartsTests.swift

A reply carrying a table or a fenced block arrives as several messages, not
as one message with boxes drawn inside it.
Two blocks in a row are two messages, not one message holding both.
Consecutive prose stays in one bubble — a paragraph broken by nothing
shouldn't arrive as two.
The parser leaves an empty prose run either side of a block. Rendering it
would put an empty bubble above a table, which is exactly the extra box
this change exists to remove.
Whatever the split, every table and block in the reply is still shown
exactly once and in the order it arrived.


## MessageTimeTests.swift

The time shown beside a message's name.
Today: the time on its own. A date on every line of a conversation you
are having right now is noise.
Yesterday, or last week: the date comes with it. A bare time on an old
message reads as one sent minutes ago.
Just before midnight and just after are different days, even minutes
apart — the rule is the calendar day, not elapsed time.


## NewCharacterTests.swift

What `New Character…` produces, and where she stands.
MARK: - Naming

Two characters called the same thing is not cosmetic: the menu shows two
identical rows and neither says which is which.
Cloning a clone must not stack suffixes.
A name that merely ends in a word, not a number, is left whole.
MARK: - What she inherits

MARK: - Where she stands

Landing a new character exactly on top of an existing one looks like
nothing happened, which is the worst possible answer to "New Character…".
The row runs out before the desktop does. Stacking at the edge is worse
than a tidy row and much better than a character that cannot be clicked.
20.1: New Character starts from the default profile; the stem the
numbering counts from is written down where a test can see it.


## OfferedAnswersTests.swift

What the card is asked to draw. The buttons themselves live in a target no
test is linked into, so this is the half that can be checked: which answers
exist for the request actually waiting.
The card that reappears every session: reading in a project the person
registered. This is where Always belongs.
A folder that is not one of the person's projects — the sprint item's
"drag a file in from outside" case. Watching one builds a throwaway
project with a new identity every time, so a remembered grant could
never match again, and the card says so by not offering it.


## PlanUsageTests.swift

Reading the plan limits out of `claude -p -- /usage`.

It is text meant for a terminal, owned by another program, so the parser is
held to one rule above all: recognise it or say nothing. A percentage that is
wrong — or right but stale — is worse than a blank, because this is the
number people use to decide whether to keep working.
Captured verbatim from a real run.
Thousands separators appear once the counts get large.
The skill and plugin lines name what the user has been working on. A
usage gauge does not need to put that on screen.
Output with no activity block still yields the bars.
The Claude app groups these; the CLI does not, so the split has to be
derived from the wording and is worth pinning.
The CLI writes the reset without a year, so it has to be inferred. Taking
the current year blindly reads a January reset as eleven months past.
"Resets in 18 min" near the boundary, the CLI's own words further out —
"in 6 days" is less useful than a date with a timezone on it.
Only the tier is taken out of `claude auth status`. That reply also
carries the account's email and organisation id, which this app has no
reason to hold.
The prose around the numbers is not a limit and must not become a row —
especially the "83% of your usage was at >150k context" line, which is a
percentage of something else entirely.
If Claude Code rewords this, the answer is nothing rather than a guess.
An account over its allowance reports more than 100; a bar drawn past its
own end reads as a rendering bug rather than as bad news.


## ProfileLibraryTests.swift

The picture-resolution rules, exercised against a fake filesystem so no test
touches the user's Application Support directory.
One picture per profile — there is nothing to resolve per state.
A profile is allowed to have no picture at all — the caller then keeps
the built-in avatar, so this must be nil rather than a missing-file URL.
A leftover file from the per-state scheme is not the picture; only the
migration may promote one, and only into the single slot.
Pictures must stay out of the repository — they're the user's own files
and some of them will be licensed art.
Round-trip through the real filesystem, in a temporary directory.
Choosing a second picture replaces the first rather than piling up.
Removing something that isn't there is how "Clear" behaves after a
failed upload; it must not throw.
MARK: - Migration from per-state pictures

Someone who uploaded a picture under the old per-state scheme keeps it,
rather than opening the app to a blank character.
The old default outranks a state picture, and the migration must never
overwrite a picture that's already there — it runs on every launch.
The app has to be someone on a first run.
A fresh install must have a real default profile on disk, not one that
exists only in memory until the user changes something.
Seeding twice would multiply the built-in character, so its id is fixed.
A saved id that no longer matches a profile — deleted by an older build,
or a hand-edited file — must not leave the app with nobody active.
`activeID` stopped meaning "the one you can see" when every profile
became a character on the desktop. It now names who a new character is
cloned from, and who the app falls back to — so switching persists, and
announces nothing, because nothing on screen changes.
Nobody arrived or left, so the roster is not rebuilt.
Creating a profile you then have to go and select is a step nobody wants.
Renaming a profile is a live change — the transcript label and the
system prompt both follow it.
This used to stay silent, and had to stop: an edit only reached the
active profile's prompt, which was right while one profile was on screen
and wrong the moment every profile is a character with a prompt of her
own. The character being edited is now always told, active or not.
The app can't be nobody, so the last profile isn't deletable.
Deleting a profile is taking a character off the desktop, so the roster
has to hear about it whether or not she was the active one — the app
rebuilds its characters from this.
The fallback still happens: `activeID` names who a new character is
cloned from, and it must not point at somebody who has gone.
Renaming reaches the prompt, not just the label — and it says which
character, since several are live at once.
The character's picture is read from disk, which SwiftUI can't observe.


## ProfilePersonalityMigrationTests.swift

`style` was renamed to `personality` in 0.6.126. Every profile the user
already had is on disk under the old key.

This is guarded rather than assumed because the failure is silent and total:
`ProfileStore.load()` turns any decode error into an empty selection, and
`ProfileLibrary` reads empty as a first launch and seeds Miku. A profile file
that no longer decodes doesn't raise anything — it wipes the user's
characters and replaces them with the built-in one.
Both keys present — a file written by a new build and then hand-edited,
or a half-migrated one — resolves to the new spelling rather than
depending on key order.
Neither key is a file from before the field existed at all. It must load
as the default rather than failing and taking the whole library with it.
The rest of the profile is untouched by the rename — a migration that
quietly dropped the picture's id or the age would be just as bad.


## ProjectMemoryBehaviourTests.swift

What actually happens when a character asks for something to be kept.

The pure half is pinned in `ProjectMemoryTests`; this is the half that
decides whether the feature is safe — that nothing is written without the
card, that the marker never reaches the eye, and that a note which reads as
an order is refused before anyone is asked about it.
Every note the store was asked to write. Empty is the assertion in most
of these.
MARK: - The card

Nothing is written on the strength of the block alone. `.localWrite`
never runs unattended, so the block can only ever put a card up.
The whole point of the card: yes means it lands, and the person is told
where.
MARK: - What reaches the eye

The marker is machinery. Left in, it shows up as raw text under the
answer — the mistake the ```choices block made once already.
MARK: - The refusals

Memory is the one block whose output is re-read as context forever, by
this app and by the person's own terminal in that project. A note that
gives orders is refused before the card, not after — asking would invite
a yes to something nobody reads twice.
With no project open the working directory is the scratch folder, and a
fact filed there would be filed against a project nobody chose. Said out
loud rather than dropped, so she does not go on believing it was kept.
One decision is pending at a time. A reply that both asks for a skill
and asks to remember something cannot have two cards, and the note is
the less urgent of the two — but it is *said*, not dropped. Every other
refusal in this feature is spoken, and this was the one that swallowed.
MARK: - The prompt


## ProjectMemoryTests.swift

Where a project's memory lives, what goes in it, and how it is asked for.
MARK: - The directory name

Every one of these was read off disk on 2026-08-14, not derived. The
rule they agree on — every character outside `[A-Za-z0-9-]` becomes a
dash — is not guessable from any one of them alone.
A dot is not dropped, it becomes a dash — which is why a worktree path
containing `/.claude/` produces a *double* dash, and why "replace the
slashes" would have written to the wrong directory for every worktree.
Three Thai scalars, three dashes. `ก่` is a single grapheme cluster, so
a per-`Character` walk would have produced two and written elsewhere.

Made on disk rather than written as a literal: the path has to exist for
it to be resolved, and a resolved path is what the directory is named
after.
One emoji, *two* dashes — it is outside the BMP and takes two UTF-16
code units. This is the case that rules out `unicodeScalars`, and it was
measured against Claude Code rather than reasoned about.
`/tmp` is a symlink to `/private/tmp`, and the directory on disk is named
after the resolved path. Standardising alone would not have done it.
MARK: - One note

With nothing under the title, the title is the fact — a file holding
only frontmatter would be a pointer to nothing.
The stem is ASCII, so a Thai title has nothing to make a name from. A
fallback rather than a file called `.md`, which would be invisible and
would collide with itself.
The hole the first drive found. A fixed fallback word filed every
all-Thai fact as the same file, so the second silently replaced the
first — and because the index line was replaced with it, nothing looked
broken. The owner writes in Thai, so this was not a corner.
…while the same title recorded twice still lands on one file, which is
what makes `memoryIndex` able to replace rather than accumulate.
MARK: - The index

The note file is overwritten by name, so without this the index would
grow a second line pointing at the same file — two pointers, one target,
and one of them describing a fact that no longer exists.
MARK: - The block

The overwhelmingly common case, and the one that decides whether this
feature is safe: a reply that talks about remembering must not file
anything.
MARK: - What is said

The person has to be able to tell, from the line alone, that this
reaches beyond the app.
The question it lands in already ends with "in <project>". Naming the
project here too produced "…for my-mcp-server, in your Claude Code
memory in my-mcp-server?" on the first drive.
MARK: - The disk

Saved twice, one file and one line — the property the index depends on,
asserted against the real filesystem rather than only against the pure
function.


## ProseIsNotACommandTests.swift

Prose that happens to contain a git word is not a git command.

Found by driving the app on 2026-08-17: the paragraph below was answered
with *"No registered project matches …"* and the turn ended there. The model
was never called, so from the outside the app had simply gone quiet.

The chain was `status` (inside "legal status") matching a git rule, then the
project split taking everything after the first `" in "` (inside
"specializing in") as the project name — some fifty words of it.
The message that started this, **verbatim**. Not shortened and not
reworded: three properties have to be present at once for it to be the
fixture it is, and rewriting drops one without saying so — the whole
word `status` (in "legal status"), a `" in "` (in "specializing in"),
and several sentence boundaries, which are the only thing that exercises
the single-sentence guard.
One line on purpose. Wrapping it with `\` continuations would rebuild
the paragraph from fragments, and a single misplaced space would be a
fixture that no longer matches what the person typed.
swiftlint:disable:next line_length
It has to be caught by *both* guards independently, because each covers
what the other cannot: a paragraph whose last marker happens to be
followed by three short words would pass Guard 1, and a short single
sentence passes Guard 2.
**The known residual, pinned rather than papered over.**

A *single-sentence* statement carrying a git word still classifies as a
command. Guard 1 stops the tail being taken as a project name, but a
query of `.none()` is still a `.codeTool` — only Guard 2 can send a
message to chat, and by construction it cannot fire on one sentence.

Left as it is on purpose. The remedy is not a smaller word limit: the
Settings-panel lesson is that a tuned number is always exceeded, and any
value low enough to reject "that report is worth reading" also rejects
real names. The actual cure is Sprint 16 — a backend with its own tools
never consults this classifier at all, and prose reaches the model.

This test exists so that stops being invisible. If Sprint 16 lands and
the fallback classifier is still the only reader, that is the moment to
revisit `handleTool`'s `.notFound` arm.
MARK: - The name guard on its own

The name is at the end of a request, so the *last* qualifying marker
wins. Taking the first one is what let "specializing in …" swallow the
paragraph.
The case that breaks most quietly: the tail after `" on "` is empty once
the `?` is trimmed, so there is no project — but it is still a command.
MARK: - The sentence guard on its own

Real commands are one sentence by construction, so the guard costs them
nothing — this is the half that would show up as the feature breaking.


## QueuedAfterTurnEndsTests.swift

Answering "wait its turn" after the turn has already ended.

The card waits as long as the person does, so the turn finishing underneath
it is ordinary rather than exotic. The queue is pumped when a turn ends —
and that moment had already passed, so the message sat there for ever under
a badge reading 1, after she had said out loud that she would come to it.
Found by driving 0.18.282.
Drives the machine the way a real turn does, so `routeToTurn` sees a busy
character and raises the card rather than starting the message.
The bug. Answer the card after the work it was interrupting has already
finished, and the queued message has to start — not wait for a turn
boundary that has been and gone.
The other half, unchanged: while she is genuinely still busy, it waits.
Dispatching here would start two turns at once.


## SaveFileBlockTests.swift

Which files the assistant may offer to hand over, and which names are
refused before they can become a button.
No symlinks and no disk: the containment rule is the thing under test,
so both sides are left exactly as written.
MARK: - Reading the block

Nearly every message. Left exactly as it was.
A card is something a person reads; a turn offering fifty files has gone
wrong in a way a scrolling card would hide.
MARK: - What may be offered

The reason this is a tested function and not a few lines in the view.
A sibling folder whose name merely starts the same way. The trailing
separator in the check is what catches this.
A link written inside the scratch folder is a legal-looking path to
anywhere, so the comparison happens after both sides are resolved.
The scratch folder's own path can contain a link — `/var` is one on
every Mac — and a contained file must not look foreign because of it.
A button that fails when pressed is worse than no button.
The person didn't write the block and can do nothing about a bad name in
it, so the good ones still come through.


## SecretaryProfileTests.swift

Personality must not undo the instruction that makes answers usable.
MARK: - Age

An exact age has to imply a life stage, or the prompt would have to
describe a 9-year-old and a 40-year-old the same way.
MARK: - Gender

Beyond male and female it's free text, so whatever the user typed has to
reach the prompt intact.
MARK: - Personality

It reaches the model as the character to write as, not as a dial between
formal and casual. It was the latter until 0.6.126 — "take that as
register only" — and every profile came out sounding the same, which is
the bug this asserts against.
The charter forbids a romantic/sexual register. That is enforced in the
prompt, not by filtering the text box: a keyword blocklist over free Thai
and English text would miss the real cases and reject innocent ones. So
the test is that the prohibition is present and outranks the style —
including when the style itself asks for the opposite.
MARK: - Blank name

An empty name must never render an anonymous speaker in the transcript.
The call landing is not the turn ending. A message sent between the two
is an interruption now, and gets asked about rather than run — so a test
that means "the next turn" has to wait for the turn, not the call.
The name is what the panel labels her replies with.
"เปลี่ยน profile ได้ App จะ refresh ทันที": the next turn must already be
the new character, and the conversation must survive the switch.
The switch is announced where it takes effect, like a model change.


## SecretaryPromptsTests.swift

The prompt assembly rules, now that they are functions of plain values.

The full texts are pinned indirectly by the turn-level tests that assert
what a `Secretary` actually sends; these check the *decisions* — which
pieces appear under which inputs — with exact equality where the whole
text is short enough to pin.
MARK: - The permission note

Exact, both branches: this is the sentence that stops the model
retrying what was just approved — or claiming powers it lost.
The owner's deadlock in one assertion: a project instruction saying
"ask for write permission first" is obeyed by *attempting*, and the note
has to say so, or the character asks in prose and waits for ever.
The Sprint 21.2 bug, as a test. The old note ended "writing or running
commands will be refused", and the model stopped before the tool call
and said so in prose — which raises no refusal, so no card, so nobody is
ever asked and the work stops for good. Whatever this note says, it has
to ask for the attempt.
MARK: - Which pieces appear

The chat-only prompt must keep saying "cannot run commands yourself" —
and the agent prompt must never contain it. Sending the wrong one is the
failure the doc comment on `agentSystemPrompt` records.


## SecretaryTests.swift

MARK: - Test doubles

Emits canned stream events (or an error) with no network or API key.
MARK: - Intent classification

MARK: - Orchestration

Chat replies stream on a background task; give them time to land.
A tool the project never listed is asked about, not refused.

This used to assert the opposite — no prompt, a red "denied by policy",
nothing the person could do from the chat. The rule now is that nothing
is blocked outright; what changes with the allowlist is how loudly the
card speaks, not whether there is one. What must stay true either way is
the second assertion: nothing ran on the way to asking.
A folder no project contains is a question, not a wall.

It used to end the turn: "it isn't inside <project>". Watching is reading,
so it does need a yes — but there was no way to give one, which left a
rule where a choice belonged.
The resolved path, because `/tmp` is a link to `/private/tmp` and a
card naming the one while reading the other is the failure worth
guarding.
Saying yes covers the folder, and nothing else. It is not added to the
registry, so it does not come back tomorrow as a project the assistant
may work in.
The tick is where an approved outside folder could quietly stop working.

The loop re-resolves through the adapter every time rather than reusing
a URL from the start, so the escape check keeps running. That is the
point — and it also means a throwaway project that resolves once at
approval but not afterwards would leave a watch that reports nothing and
says nothing, because a failed resolve is a `continue`. Silence is the
failure mode, which is why this asserts a report rather than an absence
of errors.
Sprint 21.2: the change has to reach the *model*, not only the
transcript. `say` writes a bubble; the conversation the assistant
answers from is a different array, and before this nothing ever put the
change into it — so a watch started with "and do what the file says"
reported the file and did nothing, every time.
The assistant raising it, which is how a watch starts from a real
request: the person says what they want, she asks the app to watch.
The point of the whole change: the model is *sent* it. A transcript
bubble is not the same thing — that is what it had before, and it is
why it never acted.
A typed `/watch` asks to be told and nothing more. It must not start
spending turns on every file that appears.
A symlink inside the approved folder still can't lead out of it. The
boundary moved to the folder that was agreed to; it did not disappear.
Confirmed by display name now — the settings panel and the slash
command share one entry point, and a name reads better than an id.
Nothing chosen and nothing readable from Claude Code is not a fault, so
the row must not name it like one. It used to read "Unknown", directly
above a menu item saying "Your Claude Code default" — which was the
actual answer all along.
And a real choice still shows its own name — the fallback must not have
swallowed the case it exists to sit behind.


## SessionUsageTests.swift

Counting what a conversation spends.
The real numbers from one measured turn, which is the whole reason the
cache fields exist: reported as 2 in / 5 out, it actually moved 36,204
tokens. Anything that folds the cache away is wrong by that much.
Context is "how full is the window right now", so it is the last turn's
reading, not a sum. Summing it would cross 100% after a few turns of a
conversation that is nowhere near full.
A turn that omits the window must not erase one an earlier turn reported,
or the bar would blink out mid-conversation.
A dollar figure with no explanation reads as a bill. On a subscription
nothing is charged per token, so the caveat travels with the number.


## SkillDiscoveryTests.swift

MARK: - Plugin skills

No plugins/cache entry at all — only the marketplace clone itself,
the layout a single-plugin marketplace actually uses.
A second, unrelated plugin hosted by the same marketplace, not
itself enabled — must not show up just because the marketplace
root was scanned as a fallback for "fable".
No .claude/settings.json written at all.
What the checked skills turn into in the prompt.
The description is the part the model can match a request against. The
panel shows it; not passing it on left a bare name to guess from, which
is why a checked skill could never come up.
Checking asks for something, it does not forbid the rest — the opposite
operation, and the one that made the checkbox feel broken.
Twenty checked skills must not become the largest thing in the request.
A description written over several lines would otherwise break the list
into items that aren't skills.


## SkillInstallBlockTests.swift

Asking to install a skill, and the line between asking and merely saying so.
The lesson the choices block paid for: a block left in the text renders
as raw markdown underneath the thing it was supposed to become.
MARK: - What may be named

Nothing here reaches a shell — arguments go as an array — so the danger
is not injection but a "name" that is really something else. A model
reads web pages and repository files, and this string is the one place
that content could steer an install.
A refused name is not a request. Rejecting it at the parse boundary
means no caller can be handed one by forgetting to check.
MARK: - The command


## SkillsSessionTests.swift

`toggleSkill`/`selectedSkills` are session-only, and the restriction they
produce is a soft hint in the system prompt — there is no CLI flag that
gates which skills a session can invoke.
Checking asks for a skill to be *preferred*. It used to ask for the
others to be avoided, which is the opposite operation and is why a
checked skill could sit there never being used.
MARK: - The list follows her own projects

A project brings its own `.claude/skills`, so registering one has to
re-scan. It did not: the list was built at launch and left there, and
the skill that arrived with the project stayed invisible until somebody
pressed the refresh button — which is only discoverable if you already
know it is needed.
The real one reads `<path>/.claude/skills`; this stands in for
the disk by answering out of the paths it is handed.
And the scan happens even where there is no workspace to re-scope.
`projectsDidChange` used to leave through a guard on the provider before
it reached anything about skills, so on a machine without Claude Code
the list never moved at all.


## SpeakerLabelTests.swift

Whose name sits above a message.
The whole point of storing the name: two replies written by two
different profiles keep their own names, and switching profile again
changes neither.
Entries from before the name was recorded have none. They must not
render as an anonymous line.
The name is a fact about when the line was written, so a later profile
change must not reach back and re-sign it.


## StandingGrantTests.swift

The half of Sprint 15 that survives quitting: what reaches the file, what is
read back, and what a new session does with it.
A new conversation in the same project does not ask again — the sentence
the sprint item opens with.
Starting with nothing on file is the ordinary case and must not look
like a grant.
A file that cannot be read starts the app with nothing remembered rather
than refusing to start — and, more importantly, rather than guessing.
MARK: - The file itself

No file yet is not a failure — it is the first launch.
One file per character, so approving something for one is not approving
it for everyone.
A store that cannot be read, for the launch path that has to survive it.


## StatusMenuTests.swift

The menu bar, asserted row by row against `menu.pdf`.

This is the reason the shape was pulled out of `StatusBarController`: the
app target is never linked into the test bundle, so while the menu was built
out of `NSMenuItem`s in place, not one of its hundred-odd lines of structure
had ever been executed by a test.
Walks a path of submenu titles and returns what is inside.
MARK: - The shape

The characters sit at the root now. They used to hang under a
"Characters" row that held nothing of its own and existed to be hovered
past.
A label, not something to click: it answers "which build am I running"
without opening anything.
Asked for between New Character and Token Usage, separated on both
sides, and worded from what is on screen — never from remembered state.
With nobody on the desktop the row that makes somebody is still there.
Clicking her name shows or hides her. It used to do nothing at all,
because the row was only ever a lid on a submenu.
MARK: - What the rows say

Which one you are already in. Without it, reopening the conversation you
are looking at is an invisible no-op that reads as the menu being broken.
MARK: - Which character a click is about

The bug this design exists to make impossible: with two characters on
screen, every row has to carry whose it is, rather than the app guessing
from whichever one is focused when the click lands.
MARK: - Shortcuts

⌘H is advertised on the row it actually acts on.

It used to be asserted on each character's own "Hide Character" row, which
was right until Sprint 13-2 made ⌘H take the whole desktop and was never
moved afterwards — a menu promising one thing while the key did another.
Deliberately reversed here, not weakened: the assertion is as strict, and
the row that must *not* carry it is checked too.
Adding up what several characters have spent, for the one usage window.
The one that would be wrong if it summed: two 200k windows are not a
400k window, and "how full is the context" would then be measured
against a size no character actually has.
Likewise: the fullest session is the one worth knowing about. Summing
would report a session nobody is in.


## SubagentBadgeTests.swift

The one line the header shows about a running sub-agent.
The tool it last reached for is what makes a long silence read as a slow
command rather than a fault.
**Never the word failed.** Nothing on this side can know that: a
sub-agent on one slow tool call is indistinguishable from a dead one, and
a guess here would be believed.
A sub-agent with no description of its own still has to be nameable, or
the badge appears as an empty capsule.
Reads through the pair, which is the shape the header actually holds.


## SubagentReportTests.swift

What the character says while a sub-agent works, and when it ends.

The complaint these were written for: she went silent for the whole of a
sub-agent's run, and said nothing when it finished — you had to ask again to
find out anything had happened.
Said in the conversation, not only in the activity box — that box is off
by default, and someone who never turned it on is exactly the person who
cannot tell working from dead.
The heart of it: the answer arrives without being asked for.
A sub-agent that says nothing still has to be reported. Silence here is
indistinguishable from the session having died, which is the bug.
MARK: - What the header reads

Progress moves the description without adding a line per step — the CLI
sends one per step, and a paragraph each would bury the answer.
The badge must not outlive the work it describes.


## ThemeTests.swift

The panel used to be translucent, so how readable it was depended on the
user's wallpaper. These are the checks that say it no longer can.
The one that matters. Every text colour, on every ground it can be drawn
on, in every palette — 126 pairs today, and more the moment a role or a
palette is added, without this test being touched.

Written as a sweep rather than a handful of chosen pairs because the
pair that broke in the shipped app was not one anybody would have
chosen: muted text on the panel ground.
An edge is allowed to be quieter than text, but it still has to be
visible — a hairline the same colour as what it separates is not a
hairline.

Against *every* ground, not just the window, and that is the
load-bearing part: a code block inside a bubble is nearly the same fill
as the bubble (one neutral cannot stand off both a blue tint and a grey
one), so the edge is the only thing separating them. If the hairline
fades into any surface, some nested box has no visible boundary at all.
The window's own surface, which is where most separators are
drawn, keeps the original floor.
The tinted surfaces get a lower one, and the reason is a
constraint rather than a concession: one hairline has to work on
a blue bubble, a grey bubble, an orange card and a teal card at
once, and those sit at different luminances. 1.3 is what a single
colour can reach against all of them; anything higher here can
only be met by giving up having one hairline.
The selected footer button is the one place a role is drawn on another
role rather than on a ground, so it is the one pair the sweep above
cannot see.
The window asks AppKit for a matching control appearance, so the caret,
the scroller and the selection tint don't come from the system setting
while everything around them comes from the palette.
Known values, so a typo in a component is a failing test rather than a
slightly different grey.


## TranscriptScrollPinTests.swift

Reading back through a conversation while the assistant is still typing
must not yank the view to the bottom on every token.
The reported bug: a scroll-up event is never consumed, so the reader's
own short flick still moves the content natively and is measured a
moment later. That measurement must not read as "already back at the
bottom" just because the flick was short — it is the same gesture that
`readerScrolledUp` already recorded, not a separate return trip. A wide
re-arm threshold used to live in `update` and, being generous by
design, undid every flick shorter than it — which is why scrolling up
sometimes took two or three tries before it stuck.
A conversation shorter than the view reports a negative distance.
Sending a message is an explicit "I'm here now" — it wins over wherever
the reader happened to be scrolled, without waiting to be measured.
MARK: - The reported bug: dragged back down mid-reply

What a streamed reply looks like from in here: the reader scrolls up
once, and then token after token arrives while they read. Nothing the
arriving reply does may put the view back.

The previous version failed this by a different route — it ignored
measurements for 0.3s after each of its own scrolls, tokens arrived
faster than that, and so following was never switched off for the whole
length of a reply. Whichever way it is written, this is the assertion
that has to hold: only the reader turns it back on.
The end of the transcript retreating below the fold, token by token.
The regression to watch for while fixing the above: a table or a code
block arriving while the reader sits at the bottom pushes the end far
below the fold with no input from them, and that must not be mistaken
for scrolling away.
MARK: - When the view has to scroll back to the end

The case this was written for: the running commentary is an entry
*above* the reply being written and it grows in place, so every step of
a tool run pushed the newest text further out of sight while the number
of messages and the length of the last one — all the old trigger
watched — stayed exactly the same.
Where following already put it. Scrolling again would move nothing, and
asking for it on every layout pass is how a scroll and a measurement
chase each other.
A transcript shorter than the view: the end sits well above the bottom
edge and there is nowhere to scroll to.
The whole point of the pin: someone reading back is not dragged to the
bottom, however far below the fold the end has gone.
`isBehind` and `update` share one threshold now — see `update`'s doc
for why the second, wider one they used to have was the bug rather
than a legitimate second question. Below `settled` and following stays
or resumes without a scroll; anything past it is still out of place.
MARK: - Which scrolls are the reader taking over

Scrolling down is either asking for more of what is arriving or the way
back to the bottom. Reading it as taking over would stop following at
the moment it is wanted most.


## VendorChoiceStoreTests.swift

Remembering which maker a character works through.
A suite of its own, so a test can never write into the person's real
preferences — the same reason the in-memory store is the default.
The whole reason this is keyed by profile: one on the subscription,
one on a local model, on the same desktop.
"Look in the usual places" is a choice. An empty string stored here
would later read as a path that happens to be blank.
A field the user cleared, not a path made of spaces.
A settings file written by a later build must not leave a character
unable to work at all.


## WatchBlockTests.swift

The assistant asking for a watch itself.
The case that matters most, because it is nearly every message: prose
that talks about watching must not start one. The model says "I'll keep
an eye on that" constantly.
`path:` is the natural way to write it and reads better in the prompt,
so it is accepted and dropped rather than becoming part of the path.
With several running, "stop" has to be able to mean one of them.
An empty block asks for nothing, and must not leave a hole in the reply.
The two blocks are independent markers and must not read each other's.
A reply may carry both — "I'll follow the file and watch the folder" —
and stripping one must leave the other findable rather than mangled.
Typing instead of answering used to drop the card without a word, and
the next reply would then claim the thing had been set up — the
assistant asked for a watch, this message dropped the card, and it
answered "เฝ้าอยู่เหมือนเดิมค่ะ" with nothing watching.
Nothing was waiting, so nothing is announced: the note must appear
only when a real decision is dropped, not on every message.


## WebTaskTests.swift

Recognising a link, and what happens when one arrives.

The risk this guards is asymmetric. Missing a link costs a card that never
appeared; seeing one that isn't there costs a card in front of an ordinary
sentence, every time someone mentions a filename. So the detector is
deliberately narrow, and these tests hold it there.
The reason the detector is not clever. "config.json", "node.js" and
"v2.1" all look like hosts to anything that accepts a bare domain, and
each one would raise a permission card in the middle of a conversation
about files.
`file:` would reach the person's own disk and a custom scheme hands the
address to whatever app claims it — neither is a web app to work in.
MARK: - The site a grant covers

A subdomain is a different site. Approving a public help page must not
carry over to the admin console next door.
The card, through the Secretary.
Both buttons on this card name themselves in the conversation now. The
approving one had said nothing at all, so the only trace of having agreed
to work in somebody's site as them was the work starting.
The second link to a site already agreed to goes straight through. Asked
again per page, the card becomes something to dismiss rather than read.
Working in a page as the person needs their session, which means Chrome.
Approving the card connects it — and the card says so, because two
things are being agreed to at once.
Opening the page is the first thing the approval is for. Without the
tool being granted here, answering this card leads straight into the
refuse-then-widen card for `navigate` — the same question, asked worse.
The grant is session-shaped. A new conversation asks again, or "for this
conversation" on the card is a lie.
Typing instead of answering drops the card, and the drop is said out
loud — the model is told too, so the next reply can't claim it went.


## WindowGeometryTests.swift

The sizing and placement rules pulled out of `AISecretaryApp`, which the
test bundle never links — until now these could regress without a test
noticing, and the resize rule's oscillation bug had a doc comment but no
test anywhere it could live.
MARK: - Info window size
MARK: - Info window cascade

The ninth starts over at the top rather than marching off the screen.
MARK: - Message box height

MARK: - Resize drag

The oscillation regression: the growth directions are captured at the
start of the drag, so a layout that flips mid-drag cannot invert the
gesture. The same drag value must give the same answer for the same
pointer no matter what the layout does meanwhile — measured live before
the fix, the height swung 909 → 801 → 933 → 777 in four events.
The layout flipping now produces a *different value* only for a NEW
drag; the captured one keeps answering with its original directions.
MARK: - The caption font rule

Written out six times in UsageWindow before it had a name.

