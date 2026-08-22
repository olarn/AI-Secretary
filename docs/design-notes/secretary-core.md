# SecretaryCore

Everything below was written next to the code it describes, back when the code
carried comments. It is kept because most of it is not recoverable from any
name: refuted approaches with the inputs that refuted them, measurements against
specific Claude Code builds, product decisions the owner made and the driving
session that found each bug.

The reasons that *were* recoverable are gone from here and live in the code as
names — `noGrantMaySkipThis`, `resolveOffTheMainThread`,
`aVisiblePickerWithNothingTypedOwnsThemAsEscapeDoes` and the rest. What remains
is the residue: read a section here when you are about to change the thing it
names, and especially before you "simplify" something back to the shape a
paragraph here says was already tried.

Sections are in file order. A heading with nothing under it means that file's
comments were all restatement and were simply deleted.

## ActivityLine.swift

One line of the "what I'm doing" box, marked by whose work it is.

A sub-agent's steps are indented under her own and carry a hollow marker:
the same kind of event, one level in, and not her doing. Until the stream was
read for `parent_tool_use_id` they were drawn identically to hers — so the
box said she had run a `Bash` command she had never run, and there was
nothing on screen that could have told anyone otherwise.

The marker is chosen here, in a library target, rather than inline where the
box is built: `AISecretaryApp` is invisible to coverage, and this is a rule
with four answers.


## ActivityPreference.swift

Remembers whether the user wants to see what the assistant is doing.

Separated so it can be swapped in tests, and because the default matters:
a first run is quiet, and the setting only exists once someone has chosen.
Backed by user defaults, so the choice survives quitting the app.
Hidden until asked for: the default experience is a companion that
answers, not a progress log. `object(forKey:)` rather than `bool` so an
unset value is false by intent rather than by accident.
For tests.


## AppearanceKey.swift

Where one character's look is kept in `UserDefaults`.

A free function rather than string building inside the store, because the
two things that must not drift are on either side of a launch: what `save`
writes and what `load` reads, including the app-wide name a character falls
back to before she has been changed. Getting them out of step is silent —
the settings simply stop being remembered.


## AppearanceSettings.swift

How big the floating character is on the desktop: three fixed steps, both
measured from the current size so they can't compound.
`medium` is what the app has always shipped as, so it's 1.0 and the
other two are ±30% of it.
Text size, chat-window height, and character size.

A value type with the limits built in, rather than two numbers nudged around
inside a view, because the edges are the interesting part: the buttons have
to stop at the ends rather than appear broken, and a height stored by an
older build — or on a bigger display — must not leave the window taller than
the screen it's now on.
The cap is a product decision: past 32pt the bubble shows so little at
once that every reply needs scrolling.
The default height is also the floor — shrinking below it leaves too
little of the conversation visible to be useful.
The width the bubble has always shipped as, and its floor: the tail is
drawn against the width, and much narrower than this the wrapped text
stops being readable.
The widths the widen/restore buttons step through, as multiples of the
default. One press is one step, so the jump to three times the width is
something the user arrives at rather than lands on by surprise.
Which colours the windows are painted with. Not clamped to anything —
unlike the sizes, every value is as valid as every other.
Which face the conversation is set in. Unclamped for the same reason as
the theme: there is no such thing as a value out of range.
Whether the chrome — the bubble itself and the footer buttons — is drawn
as Liquid Glass instead of the palette's solid ground. A surface over
both palettes rather than a third palette: every colour still comes from
`theme`, so the contrast rules `ThemeTests` enforces keep holding for
everything drawn *on* a surface. Off by default — the solid look is the
one that never depends on the wallpaper.
The most the bubble may become: the usable area of the screen it's on.
Deliberately not persisted — the display can change between launches, so
these are supplied each time rather than remembered.
Called when the screen is known or changes. Re-clamps the current height,
so moving to a smaller display pulls an over-tall window back in.
MARK: - Free resizing

A drag on the bubble's grip. Both axes at once, because a corner grip
moves both, and clamped rather than refused so the drag simply stops at
the limit instead of jumping.
MARK: - Stepping the width

The stops the two buttons move between, narrowest first. Each is capped
to the screen, and a stop that the screen has squeezed into another one
isn't a separate stop — otherwise a press would appear to do nothing.
The next stop wider than the bubble is now. A hand-dragged width sits
between stops, and stepping from there goes to the next one up rather
than snapping backwards.
Restoring is one press back to the default, not a step, so it's offered
from any width above the default — including one dragged by hand.
Straight back to the default width in one press. Widening is a stepped
climb because each step is a size worth stopping at; coming back is not —
what's wanted there is the bubble out of the way, now.
MARK: - Stepping

Used to dim a button that can't do anything, so pressing nothing looks
intentional rather than broken.
MARK: - Derived sizes

Every size that follows from the body size, in one value.

Split out of this struct so a window whose text size is *not* the chat's
can still scale as one piece. The command window is the one that made it
necessary: it carries its own ⌘+/⌘− size, and read its captions, hints
and rhythm off the chat's settings instead — so growing the box grew the
text being typed and nothing else on the slab (the owner's report,
Sprint 21.2).
The sizes that follow from one body text size.

A function of `fontSize` and nothing else, so the same number always yields
the same panel — and so any window can ask for the set, whichever size it
happens to be scaling from.
Secondary text tracks the body size so the panel scales as one piece
instead of leaving captions tiny beside 32pt text.
A step below secondary — the Token Usage window's table numbers and
axis labels. Was `max(9, secondaryFontSize - 2)` written out at six
call sites, which is six chances to update five of them.
The explanatory line under a control — "Blank means professional",
"Free text — who she is". Smaller than the row it explains, and
scaled like everything else: these were pinned at 9pt, so the Settings
and Profile panels stayed the same size whatever the text size said.
Gap between rows inside a panel, and the panel's own inset.

Scaled for the same reason the text is, and learned the same way: type
that grew while the spacing stayed at 6 and 10 points made the Settings
panel read as a wall — "พอขยาย font แล้ว เนื้อหามันแน่น". Rhythm is part
of the size, not a constant the size happens to sit inside.
The values worth remembering across launches. The screen limits aren't
among them: the display can change between runs, so they're supplied fresh.
Remembers the choice across launches.
The names on disk, unchanged. `appScale` reads oddly now that the type is
`CharacterScale`, and renaming it would quietly discard the S/M/L choice
of everyone who had made one — a key is a promise to whatever wrote it.
- Parameter character: whose look this is. `nil` means the app-wide keys
  written before each character had her own, which every character still
  reads as her starting point — see `load`.
Her own value, or the shared one, or the default.

The middle step is what keeps the app looking the way it did: nothing is
renamed or moved when characters get their own settings, so on the first
launch after this every character reads the one look that was there and
they all match. She stops reading it the moment she is changed, because
from then on she has a value of her own.
`object(forKey:)` rather than `double(forKey:)` so an unset key falls
back to the default instead of to zero — which matters for width, added
after the other two, and so absent for anyone upgrading. An unrecognised
scale — written by a build with different steps — also falls back rather
than throwing.
Writes only under this character's keys. The shared ones are left where
they are: they are what a character who has never been changed is still
reading, and overwriting them with one character's choice would move
everybody who hasn't chosen yet.


## ApprovalAsked.swift

A permission card, as somebody outside the character's own chat sees it.

The command window is why this exists. Claude Code has no mid-turn
approval, so the only honest loop is try-refused-ask-retry (see
`offerToWiden`) — and the asking happened in the character's chat panel and
nowhere else. Commanded from the command window, every character that
wanted to write a file said it had no permission and then waited on a card
the person was never shown: either they happened to open her chat and
answer, or the work sat there for ever. That is the owner's report opening
Sprint 21.2, both halves of it, and it is one bug.

Carries the words rather than the `ApprovalRequest`: what the person has to
weigh is what will happen, and the sentence she just said is already written
for a human. The answers come from `offeredApprovalAnswers`, so the buttons
outside the chat and the buttons inside it can never differ.
What she said when she put the card up, verbatim.


## ArrowKeyOwner.swift

Who the Up and Down keys belong to at this moment in the chat panel.

Three features want the same two keys: walking a question's options,
recalling what you sent earlier, and moving the caret inside a multi-line
draft. Leaving that to whichever handler runs first is how the arrows came
to feel broken — so ownership is decided here, as one total function over
the state, rather than by the order of `if`s inside an event monitor.

The deciding question is whether the message box is empty. An empty box
means you are answering the question that is on screen; the moment you type
something you are writing your own reply instead, and the picker steps
aside. That is the same rule Return already followed, now stated once for
both keys.
Move the highlight through the options; Return takes the highlighted one.
Step back and forth through messages already sent, as a terminal does.
Leave the key alone so the text field moves the caret with it.
A question on screen with nothing typed: the arrows are the picker's,
whether or not the caret happens to be in the box — the same reach as
Escape, because a picker you can see should answer to the keys you
press at it.

In a draft that has more than one line the arrows are how you get
between them, so recall must not take them.


## AssistantChoiceStore.swift

Which model and effort a character answers with, when she has been told.

`.none()` on either half means "whatever Claude Code is configured to use" —
an absence, not a value, which is why both are `Option` rather than a
sentinel model called "default".
Where a character's model and effort survive between launches.

They did not, until now. `selectModel` set a property and said a line, and
nothing wrote it anywhere — so every character came back on "Default" every
morning, and the only way to notice was to read the badge. Sprint 12 recorded
the omission deliberately ("Model กับ Effort … ไม่ใช่ field ของ profile ที่เก็บลงดิสก์")
because those rows apply immediately rather than waiting for Save; remembering
them does not require giving that up, which is why this is its own store and
not a pair of profile fields.
The default, and it deliberately reaches nowhere — the same rule the grant
store follows. A suite that forgot to override it would otherwise write into
the person's own preferences.
Per character, written the moment the choice is made.

Its own key namespace rather than the appearance one: Sprint 12 sorted these
rows by what they are about, and "who is answering" is not "how the app
looks". Sharing a namespace would only be convenient.
**An unrecognised value reads as "inherit", never as a crash and never as
a guess.** Model ids come and go between Claude Code releases, so a
character configured for a model that no longer exists has to fall back to
whatever the CLI is set to rather than insisting on a name nothing will
answer to.
Going back to "Default" is a choice too, so it is written as the absence
of a key rather than left alone — otherwise clearing it would come back
the next morning.


## Attachment.swift

A file the person has handed over for this message.

The point of it is data entry: "here is the list, put it into that web app".
Typing a table into a chat box is the part nobody wants to do, so the file
itself comes across — dragged onto the input, or picked from the panel the
assistant can ask for.

Deliberately *staged*, not linked. The file is copied into the app's own
folder and the model is pointed at the copy. Pointing it at the original
would mean opening the folder the file came from — drop something off the
Desktop and the whole Desktop becomes readable for the session, which is a
far wider thing than the person did. The copy is also a snapshot: the answer
describes the file that was handed over, not whatever it became halfway
through the turn.
What it is called, as the person knows it.
Where the copy lives. Inside the app's own folder, always.
What kind of thing the file is, as far as it matters here: enough to tell
the model what it is being handed, and to refuse what it can't use.

No parsers. The model reads the file with its own tools — a CSV parser, a
key-value parser and a "sort of JSON" parser written here would be three
things to maintain that are each worse than what already reads them, and the
fourth format would still arrive.
`key: value` lines, .env-shaped notes, plain text — and anything else
whose bytes turn out to be text.
A file of code. Its own kind rather than plain text because saying
"Swift" in the chip and in the note is the difference between "here is
a file" and "here is the thing you asked to look at".
Read by the model, not by us: a PDF is a container, and the words in it
are the point.
A picture with words in it — a screenshot of a form, a photo of a
receipt. The model reads it; nothing here tries to.
Extensions that say "this is code", so the chip and the note can say so
too.

A list, and it will always be missing someone's language — which is exactly
why nothing depends on it being complete. A file whose extension isn't here
still gets in as text if its bytes are text; all this list changes is what
the person and the model are told it is.
Extensions that are worth naming as text even before the bytes are looked
at — configuration and prose formats a person hands over constantly.
The kind a file's name implies, or nothing when the name doesn't say.

By extension, not by sniffing — for the kinds that change how the file is
*described*. A person choosing a file knows what they chose, and guessing
past the name would mean treating a `.txt` as a CSV because it had commas in
it. When the name says nothing at all, the bytes get a turn: see
`textIfReadable`.
`.env`, `.gitignore`, `Makefile`: no extension, and `pathExtension` says
so, which had them refused as an unknown format. A name with nothing
after a dot is a text file by convention on this platform, and reading
one as text is the mildest thing that could be wrong.
Whether a file the name couldn't place is text after all.

The alternative was a list of extensions that grows every time someone
hands over a format nobody thought of — and the list is never the point,
because what the model needs is only whether it can read the thing. So the
name decides the *description*, and for anything left over the bytes decide
admission: valid UTF-8 with no NUL in the first stretch is text.

A prefix rather than the whole file, because a 4MB log has to be answered
as fast as a 4KB note, and a file that is text for its first few thousand
bytes and binary after that is not a case worth being slow for.
How much of an unnamed file is looked at before deciding it is text.
How many files may ride along on one message.

Five, because each one is read in full on the turn it arrives and the
person can still see all five at once above the input. A cap that can be
exceeded quietly isn't one.
Largest file that may be handed over, in bytes. The same order as the file
understanding cap and for the same reason: bytes on screen are free, bytes
on the wire are not.
Said to the person, in the chat, in their terms.
Whether one more file may join the list, given what it is and how big it is.

Pure, and separate from the copying, so the rules can be read and tested
without a filesystem. Size arrives as a number for the same reason.
The name first, the bytes second. A `.swift` file is source whatever its
first four kilobytes look like; a `.bak` is whatever it turns out to be.
What the drop area says while a file is being dragged over the window.

It has to be able to say no. The window accepts a drop anywhere, so the
person can be holding a sixth file over a list that is already full — and an
area still reading "drop files here" would invite exactly the drop that
`admitting` then refuses, with the refusal arriving after they let go.
Saying it before the drop is the only place it helps.
What the model is told about the files riding along with this message.

Paths, not contents. The assistant has file tools and the staged copies sit
in a folder it has been given, so it opens them itself — the same rule the
rest of the app follows, and the only one that works for a picture.
How an attachment reads in the transcript, under the message it came with.
MARK: - Staging

The folder the copies live in, when there is one. Handed to the backend
so it can open what was staged — and nothing else.
Copies a chosen file into the app's own folder and describes the copy.
Throws away every staged copy. Called when a conversation ends — the
files were handed over for a conversation, and keeping them past it
would leave someone's spreadsheet in Application Support forever.
Only when the name didn't say. Opening every file to look at it would
make an ordinary `.csv` wait on a read it doesn't need.

The copy keeps the person's own filename, prefixed so two files
called `data.csv` from different folders don't overwrite each
other — the model is told the plain name either way.

The first few kilobytes, or nothing if the file can't be opened. Read
through a handle rather than `Data(contentsOf:)` so a large file doesn't
come into memory to answer a question about its first page.
Stands in for the disk. Keeps the same rules — the refusals are what most
tests are about — but stages nowhere.
Sizes to report for named files, so a test can hand over a large one.
MARK: - The assistant asking for a file

The assistant asking the app to put an open-file button in front of the
person.

```attach
the spreadsheet with the rows to enter
```

Marked rather than inferred, like every other block: a reply that merely
mentions a file must not open a file dialog. What it buys is that the
person never has to know where the file is in a path — they press a button
and choose it, which is also the only way this would work sandboxed.
What the assistant says it is asking for, shown on the button's line.


## AuditLog.swift

One recorded step in a task's life, correlated by `taskID`.
Keeps the trail in memory and mirrors it to the unified log. Command text
and paths are logged; message content beyond the classified intent is not.


## BlockedBlock.swift

A request the assistant could not finish, and what it was missing.

Held by the app rather than left to the model to remember. Telling the model
"a message that supplies the missing piece belongs to the earlier request"
was not enough on its own: asked for a ratebook and told where to look, it
treated the second message as a fresh instruction, confirmed the tool worked,
and searched for something else. With the request written down, the app can
put it back in front of the model on the next turn instead of hoping.
The user's words, verbatim.
What the assistant said it lacked, in its own words.
The line handed to the backend on the next turn. Written as an
instruction about *this* conversation rather than a general rule,
because a general rule is what already failed.
Reading a ` ```blocked ` marker out of a reply.

Same bargain as the other markers: the app never infers this. "I couldn't
find that" appears in ordinary answers constantly, and treating every such
sentence as an unfinished request would put a stale reminder in front of the
model for the rest of the conversation.
The message with the marker taken out.
What the assistant said it was missing, if it declared anything.
MARK: - The one kind of missing nobody can hand over

Whether what the assistant marked as missing is a *permission*.

This is not prose-reading of the kind the charter forbids: the text comes
out of a ` ```blocked ` block, a field we defined and asked for, and the
question asked of it is only "is this the sort of missing that waiting
cannot fix". Nothing is acted on from an unmarked sentence.

Why it needs answering at all — the deadlock the owner hit on 2026-08-20,
commanding four characters into a shared folder whose `CLAUDE.md` opens
with *"เมื่อพร้อม ทุกคน จะขอ write permission file และ folder ของ project"*
("when ready, everyone will ask for write permission"). อาเนีย did exactly
that: she asked, in words — *"หนูขอสิทธิ์เขียนไฟล์ 2.actions/task.md"* — and
then waited. **There is nobody to ask.** Claude Code has no mid-turn
approval; in this app the only way to raise the question is to make the
call and be refused, and a request that is never made is never refused, so
no card is ever drawn and the turn ends with her waiting for ever. The
other three attempted, were refused for real, and were widened.

Both languages, because the character answers in the person's, and the
blocked line is written in whatever she was speaking.
What the app says to the assistant to break that deadlock.

It grants nothing and it cannot: it only tells her that the waiting she has
settled into has no end, and that attempting is how the person gets asked.
The refusal that follows is real, and *that* is what draws the card.

Addressed to the project instruction by name, because that is what she is
obeying and she is right to obey it — the app has to say how this project
asks, not tell her to ignore what she was told.


## BrowserPreference.swift

Remembers whether the user has connected the assistant to their browser.

Its own store rather than a field on the profile or the appearance settings:
this is a permission, and permissions that reach the user's signed-in
sessions shouldn't ride along with a profile picture or a font size, where
switching profiles could quietly turn one on.
Backed by user defaults, so the choice survives quitting the app.
Off until asked for. Least privilege, and the honest default: connecting
gives the assistant reach into every site the person is signed into, so
it should be a thing they did, not a thing they inherited.
For tests.


## BubblePlacement.swift

Where the speech bubble goes, given where the character is standing.

Lifted out of `AppDelegate` so it can be checked without a screen. The rule
it encodes is not obvious and got this wrong twice: the bubble may flip to
the other side of the character to stay on screen, but a flip is only worth
making when the other side is actually roomier. Flipping into a *smaller*
space just moves the problem — the panel gets clamped back into the screen
and lands on top of the character, which is the one thing the bubble must
never do, since the character is how the user reaches it.

Coordinates are AppKit's: y grows upward, origins are bottom-left.
Tail on the right rather than the left.
Bubble below the character, tail pointing up.
The gap `placeBubble` keeps between the bubble and each screen edge.

The one owner of this number. It used to live twice in the app layer — once
as the clamp margin handed to `placeBubble` and once, pre-doubled, inside
the max-width rule — and nothing said the second was derived from the first.
The widest the bubble can be without `placeBubble` clamping it: the screen
minus the margin kept at each side.
Clamps into a range, tolerating an inverted one: a bubble taller than the
screen has no valid origin, and the top edge is the less bad end to lose.
Places the bubble beside and above the character, flipping only when that
buys room.

- Parameters:
  - character: the character window's frame.
  - bubble: the size the chat panel currently wants to be.
  - visibleFrame: the screen area excluding the menu bar and Dock.
  - tailTipOffset: distance from the bubble's leading edge to the tail tip.
  - clearance: how far the bubble is pushed sideways off the character.
  - gap: vertical gap between character and bubble; negative on purpose, so
    the tail visually touches the avatar inside its padded window.
  - margin: gap kept from the screen edge.
Measured from the tip inwards, so only one edge is pinned to the
character and the other is free: widening the bubble grows it away from
the character instead of sliding the tip off it.
Room each side would give a bubble of any height. Compared rather than
just testing "does it fit above", because when it fits neither side the
answer is still the roomier one, not always down.


## CardChoice.swift

The words on the buttons of every card that waits for an answer.

Here rather than in the view because the transcript now repeats them back:
a record that reads "You chose “Go ahead”" while the button said "Yes" is
worse than no record, and `AISecretaryApp` is never linked into the test
bundle, so a literal typed twice there is a drift no test could see.

`PermissionAnswer.title` is the fourth member of this set and stays where it
is — it is owned by the type whose cases the buttons are.
The control that opens the list of everyone free.

One control rather than one button per character. Buttons were the first
shape and they do not survive a roster: four characters already filled
three rows under the other two answers, and the card grows a row per
character with nothing to stop it — the same unbounded growth the charter
forbids in the settings panels. A menu is the same height whether two
characters are free or twenty, and the list inside it is AppKit's problem
rather than ours.
How the choice is named once it has been made — the menu's words and the
item's words together, which is what the person actually read.
How an answered card is written into the conversation.

The card itself disappears the moment it is answered, so without this the
only trace of a decision is whatever happened next — and for approving, for
picking a project, and for replacing a running turn, nothing happened that
said so. The person is left reading a conversation in which they apparently
never answered anything.

Deliberately just the opening clause: each caller adds what followed from
the answer, so there is one rule for how a choice is named and no table of
near-identical sentences to keep in step.


## CharacterDirectory.swift

One character as her neighbours are allowed to see her.

The type is the permission boundary, which is why it is worth having at all
rather than passing `SecretaryProfile` around. Sprint 14.2 asks that a
character know *which project* another has open and still have no access to
it — so this card carries the project's **name** and no path, no grant, no
tool id and no session id. A value cannot leak what it does not hold, and a
later field added here has to be argued for against that sentence.
As the app words it elsewhere — "Opus 5", "Default" — not a model id.
The name of the project she has open, if any. Never its location.
Whether she was mid-turn when this snapshot was taken.

True only *as of that moment*. It is rendered into a prompt that a model
may still be reading a minute later, so `directoryPrompt` says when it
was true rather than stating it as a standing fact — a model told she is
free, acting on it after she has started something, is a wrong-answer
generator.
Everyone except the character being prompted, in a stable order.

Sorted by name rather than left in roster order so the prompt text for an
unchanged desktop is byte-identical from turn to turn: a system prompt that
reshuffles itself is a prompt cache that never hits, and a test that has to
sort before comparing.
How the roster is put to the model, or nothing when she is alone.

`.none()` rather than an empty string: a character by herself should have no
paragraph about her colleagues at all, and "there is nobody else" is a
sentence that invites the model to bring the subject up.

This paragraph alone answers Sprint 14.1's first item — knowing the others
exist and which model each is running needs no message sent and no round
trip, because the answer is already in front of her.
The standing rules about the others: that they exist, what may be seen of
them, and how to send one of them something.

**Nothing here may change between turns, and nothing about what a character
is doing may be added to it.**

This text goes into `--append-system-prompt`, which is a *launch* flag: it
is fixed when the `claude` process starts, so it is part of
`WarmProcessKey`, and a process whose key no longer matches is terminated
and started again. A value that moves therefore costs a whole cold start —
the repo's own measurement, 5.47s to first text against 1.15s warm, plus the
transcript read back with a cold prompt cache.

It used to carry a row per character with their model, effort, project and
whether they were busy. With one character on the desktop this block is
absent entirely and nothing was ever noticed; with four it moved constantly
— first the busy flag, then, once that was removed, the project name, as
each character opened the shared folder in turn. Measured on 2026-08-20
while four answered one broadcast: three of the four warm processes were
killed and respawned between two consecutive turns, and the diagnostic named
the difference as `- Ditto — Default, effort medium, no project open` giving
way to `working in “ai-team-work”`. That is the whole of "four characters
answer much slower than one".

Who they are and what they are doing is not lost — it moved to
`directoryStatus`, which rides on the turn itself, where it costs nothing
and is fresher than it ever was here.
Who the interruption card may offer the work to: everyone who is free.

An empty result *is* the requirement "nobody free, no delegate choice" — the
card draws one button per candidate, so an empty list means no buttons, and
there is no second branch that could disagree with this one.

The directory it reads is a snapshot taken as the card is drawn, so it can be
seconds stale by the time a button is pressed. That is exactly why pressing
one re-checks against live state (`delegationDeliverable`) instead of
trusting what the card was drawn from.
Who the others are and what each is doing, right now.

The half of the neighbours block that moves. It rides on the turn — the
message, not the launch flag — which is why it may be as fresh as it likes:
see `directoryPrompt` for what carrying it in the system prompt cost, which
was a whole `claude` restart for every character every time any of them
opened a project or started working.

Being on the turn also makes it *more* accurate than it was. The busy flag
is back, and it no longer needs the old apology about having been true when
the process started: this is read at the moment the turn begins.


## CharacterLaunchOrigin.swift

Where the character stands the first time it appears.

A rule the app has to decide, so it lives here rather than in the delegate:
`AISecretaryApp` is never linked into the test bundle, and a launch position
can only be checked by launching.
Distance in from the right edge of the usable area.
How high the character used to stand above the bottom of the usable area.
Taken off that, as a fraction of the usable height — the character was
asked to stand lower. Expressed against the screen rather than as a fixed
number of points because "how high up the screen it looks" is what
changes with the display, and a constant that reads right on one screen
reads wrong on the next.
- Parameters:
  - characterSize: the panel's size, so the clamp keeps all of it visible.
  - visibleFrame: the area left over by the Dock and the menu bar, which
    is what the resting position is measured from.
  - screenFrame: the whole display. The clamp uses this, not the visible
    frame, so that launch agrees with `keepCharacterOnScreen`: standing
    on the Dock is a normal place for a desktop character, and the only
    rule is that it must not end up off the screen.
How far left each further character stands from the one before, as a
fraction of its own width. A share rather than a fixed gap, for the same
reason `lowering` is: the character is drawn at three sizes, and a
spacing that looks right at S has them overlapping at L.
Where character number `existing.count + 1` stands.

The resting spot is taken, so she stands to the left of whoever is
already there — landing a new character exactly on top of an existing one
looks like nothing happened, which is the worst possible answer to
"New Character…".

Measured from the resting position rather than from the leftmost
character on screen: characters are draggable, so following them would
mean a new one appearing wherever the last one was dropped, including
off in a corner. Counting instead keeps the row predictable, and once it
would run off the left edge the clamp stacks them at the edge rather
than putting one where it cannot be clicked.
Low wins if the two cross — a character taller than the screen is pinned
to the bottom rather than to a negative height above it.


## CharacterMessage.swift

A message travelling from one character on this desktop to another.

**The envelope is data, never a capability.** There is no path on it, no
grant, no tool id, no working directory and no Claude Code session id — so
the recipient works in her own project registry, under her own approvals, in
her own session, and an errand that reaches outside what she already has is
refused rather than quietly widened. `CharacterMessageTests` asserts the
absence, so adding a field here fails the suite rather than leaking.

It is not `Codable` and is never written to disk. Everything runs in one
process on one actor; a shared file with a lock around it is Sprint 14.3's
problem and buying it now would pay for every hazard that sprint lists while
delivery is still a function call.
An errand expects an answer; a report is that answer. A question is just
an errand whose answer happens to be words, so it needs no case of its
own.

`accepted` is the third because silence and a queue look identical from
the other end. A character who is mid-conversation takes the errand and
works through it when she gets there — correct, and indistinguishable
from being ignored unless she says so. It closes nothing: the errand is
still outstanding and the answer still has to come.
Carried so a transcript line can name the sender without looking her up
in a roster that may have changed. A name is not a capability.
The errand this belongs to. A report carries the id of the errand it
answers, which is what lets an answer arriving minutes later be shown
against the thing it answers instead of as a message out of nowhere.
How many characters this has already been through. Bounded, so
Miku → Anya → Miku → … cannot run away.
An errand sent and not yet answered.
One errand at a time between the same two characters, in the same
direction. Without this a person repeating themselves — or a model
reading its own forwarded words — starts a second copy of work already
under way, which is the "ทำซ้ำกัน" hazard.
A report for an errand nobody is waiting on: already answered, timed
out, or invented.
Only reachable from the interruption card's third button, where the
whole promise is "she is free". Between the card being drawn and the
button being pressed she may have started something, and handing it over
anyway would break the one thing that button says.

Deliberately *not* used by the prose hand-off: Sprint 14 decided a busy
recipient takes the errand and queues it, and this must not quietly
reverse that. See `delegationDeliverable`.
Two hops is Miku → Anya → Miku, which is the whole of the scenario in
the backlog. A third would mean Anya handing it on again, and there is
no request for that — so the ceiling is set at what is asked for rather
than at a number that merely feels safe.
After this an errand is treated as abandoned, so the pair is not blocked
for the rest of the session by a turn that died.
The errands still worth waiting for.

`now` is the last parameter and defaulted, so tests pass a fixed date and
production never types one — the repo's idiom for keeping a time-dependent
decision deterministic.
MARK: - The rails

An errand may not overtake one already in flight to the same character.

A report is waved through here: whether it is expected is a question about
the *recipient's* outstanding list, and the sender does not have that. It is
asked on arrival instead, by `relayAcceptableReport`.
Whether this message may be handed over, asked by the character sending it.

Every reason to refuse is a value the caller can put on screen, which is the
point: a message that silently does not arrive is indistinguishable from a
character ignoring you.
Whether an answer belongs to something this character is still waiting on,
asked by the character receiving it.

An answer to an errand that has already been reported, or that timed out, is
dropped rather than read out: it would arrive in the conversation attached to
nothing, which is worse than silence.
MARK: - What each conversation says

In the sender's own chat, when her errand has gone.
In the recipient's chat, when an errand arrives. The person watching her
should be able to see where the work came from before it starts.
In the recipient's chat, when she is mid-something and the errand has to
wait its turn.
In the sender's chat, when the other end has taken it but not started.

Without this the sender says "passed it on" and then nothing happens for as
long as the other character is busy — which reads exactly like being
ignored, and is the one thing a hand-off must never look like.
In the sender's chat, when the answer comes back.
In her own chat, when a sub-agent she started finishes.

Deliberately shaped like `relayReportLine`: an answer that came from
somewhere other than her own turn reads the same whether the somewhere was a
colleague or a sub-agent, and the arrow is what says "this is not me
talking". Said without being asked, which is the whole point — the old
behaviour was silence until the person asked again.

A sub-agent that ends with nothing to say still gets a line. "It finished
and said nothing" is information; a character that stays quiet is
indistinguishable from one whose session died.
In her own chat, the moment one starts, so the wait has a reason attached to
it rather than being unexplained silence.
Whether this may be handed to a character the person picked *because she was
free*, asked at the moment the button is pressed.

The freeness rail sits in front of the ordinary ones rather than replacing
them: everything that refuses a prose hand-off still refuses this. What it
adds is the promise the button made, checked against live state instead of
against the snapshot the card was drawn from — the card can be seconds stale,
the check never is, because every character shares one actor in one process.

`relayDeliverable` is untouched on purpose. The prose path must keep Sprint
14's behaviour, where a busy recipient takes the errand and queues it.
How a relayed errand is put to the character who has to act on it.

The words came out of another model, and they are about to drive an agent
with file tools. The charter's rule that all external content is untrusted
applies here with force, so the request is framed as something to weigh
rather than as an instruction from the app or from the person — and it is
told plainly that the message cannot change what it is allowed to do.


## CharacterWindowMemory.swift

Where each character was left, remembered across launches (20.1).

The command window already remembers itself; this is the characters' half.
Plain Swift for the same reason as `CommandWindow.swift`: it crosses into
the app target.

One key per character, built in one place so save and load can't drift —
the same rule as `appearanceKey`.
The remembered origin, if it is still worth using.

`nil` — meaning "use the default launch position" — when nothing was saved,
the save doesn't parse, or the character would come back somewhere she
cannot be clicked. The owner's rule is explicit about that last case: a
position saved on a screen that is gone (a shared or external display) is
*not* clamped back to the nearest edge the way the command window's is —
she returns to her default spot, because an edge-clamped character reads as
"she moved by herself" while the default reads as a fresh start.

"On screen" is at least `minimumVisible` of her in both axes inside the
whole screen frame, not the visible frame — standing on the Dock is a
normal place for a desktop character (the same reasoning as
`keepCharacterOnScreen`).
The saved origin, in the only form `UserDefaults` round-trips exactly —
the command window's encoding, shared on purpose.


## CommandWindow.swift

The command window's decisions: who a broadcast goes to, what each recipient
is told, how dropped instruction files merge, and where the window sits.

Plain Swift where it crosses into the app target (the same rule as
`StatusMenu`), pure everywhere: same text and same roster in, same answer
out. The window itself only applies these answers.

MARK: - Who receives a command

What pressing send in the command window should do.
Nobody is ticked. The red line under the box; nothing is sent.
The message names only characters that are not ticked. Sending it to
the ticked ones instead would be work handed to someone who was never
asked — the same wrong-recipient hazard `DelegationIntent` records — so
it is refused with the names, and the person ticks them or rephrases.
Send it to these, each with her own copy.
Reads the person's command against the ticked characters.

The rule has one narrowing step: a command that names ticked characters goes
only to the named ones ("Miku pin คำตอบล่าสุดไว้" with three ticked runs Miku
alone), and a command that names nobody goes to everyone ticked. Matching
reuses `namesFor` — the same full-name-or-first-word reading the hand-off
path trusts — rather than growing a second, slightly different notion of
what counts as naming somebody.

`roster` is everyone on the desktop, ticked or not: a name that matches the
roster but not the selection is how `namedNotSelected` is told apart from
prose that names nobody.
The red line under the box when nobody is ticked. In the product's own
words — the backlog states this string, not just that one exists.
The red line when the command names only characters that are not ticked.
MARK: - What each recipient is told

One recipient's copy of a broadcast.

Sent to one character, the instructions go as typed — it is the same act as
typing in her own chat, and a preamble would be noise. Sent to several, each
copy opens by saying who else received it and how shared work is divided:
by name or role when the instructions assign it, among themselves when they
don't. The characters already reach each other through their own hand-off
blocks, so "divide it yourselves" is something they can actually do.
MARK: - Instruction files

Dropped instruction files and the typed text, merged into one instruction.

In drop order — the backlog's rule is that steps in the first file run
before steps in the next — with the typed text last, since it is written
with the files already on the window and reads as a note about them.
MARK: - Where the window sits

The one place the defaults key is written, so save and load can't drift.
The saved origin, in the only form `UserDefaults` round-trips exactly.
Where the window opens: the remembered spot, or the middle of the screen.

Clamped to the visible frame either way — a position saved on a display
that is no longer attached would otherwise open the window somewhere no
click can reach.
MARK: - How wide it is

The one place these defaults keys are written, same rule as the origin's.
Height granted beyond the minimum, all of it the message box's — the
window's own height is never stored, because the minimum moves with the
content and a stored total would reopen with yesterday's error line's
worth of dead space.
Asked for by the owner (2026-08-19): the window resizes. Width only — the
height always follows the content, so a free height would either clip the
box or leave dead slab under it.
Narrow enough to park beside other work, never so narrow the chips wrap
into a column; wide enough for a long instruction, never wider than the
smallest screen this app targets.
MARK: - What a dropped file becomes

What one file dragged onto the command window turns into.
Read as text and merged into the instructions.
Handed to each recipient as a real attachment, the way the chat's own
drop does — an image read as UTF-8 was an error message before this.
Notes are instructions; everything else rides along as a file. Extension
rather than content sniffing, because "a markdown file of tasks" versus "a
CSV the tasks are about" is a distinction of kind, not of bytes.
MARK: - The box's own text size

The one place this defaults key is written, same rule as the origin's.
The chat boxes' default, which is where this box's look came from.
⌘+ / ⌘− while the command box holds the caret size *this box*, not the
focused character's chat — the window is the app's, and growing one
character's bubbles because the pointer happened to be here would be the
same borrowed-look bug Token Usage exists to avoid. Clamped to the range
the chat's own sizes span.
MARK: - The menu row

One row for both directions, worded from what is on screen right now —
the same rule as `allCharactersTitle`, for the same reason.
MARK: - Saving what came back

One answer, as the saved document holds it.

A value of its own rather than the strip's own row type: `CommandResult`
lives in `AISecretaryApp`, which is never linked into the test bundle, and
laying out a document is a decision — so it is written and tested here, and
the strip only hands over what it is showing.
What Save writes: the strip as Markdown, in the order it is on screen.

Screen order, newest first, deliberately — the file is a copy of what the
person is looking at, and re-sorting it into "the order it happened" would
hand them a document they cannot line up against the window it came from.

A character who could not finish is marked, because "she answered" and "she
failed" read identically once the coloured dot is gone.
The name the save panel opens with. Markdown, because the answers are
Markdown — the owner named the default.


## CompletionNotice.swift

A turn that has just come to rest, as the notifier sees it.

Assembled by `Secretary` at the moment the state machine settles, so it
carries what only she knows — who she is, what she ended up saying, and
whether anybody actually asked her. What she cannot know is whether the
person is looking at it; that arrives separately, from the windows.
The reply as it appears in the bubble — already stripped of the marker
blocks, so a banner never shows a ```choices fence.
Whether this turn was another character's errand rather than the
person's request.
What the reply offered to pick, parsed from the raw bubble before the
fence was stripped — `text` deliberately no longer carries it, so a
listener that wants the question's options has to be handed them.
What a banner says.
Whether a finished turn is worth a notification, and what it should say.

Returns Swift's `Optional` rather than `Option` for the same reason
`dismissDecision` does: its only caller is `AppDelegate`, and importing
`FunctionalCore` there to fold one value would drag Bow's `State` into a
file that sits next to SwiftUI.

Three refusals, each for a different reason:

- **An errand.** One request from the person can finish twice — the
  character she handed it to answers, then reports back, and the character
  who asked finishes again. Notifying on both means two banners for one
  piece of work, the first from somebody the person never spoke to.
- **Her chat is on screen.** The reply lands in a window the person can
  already see, so a banner would be a second copy of it. Being frontmost is
  deliberately not part of this: the owner's rule is the window, not the
  focus (asked for on 2026-08-18, while driving 0.19.288). A bubble left
  open on a second display, or behind the editor, still counts as shown.
- **Nothing to say.** A turn that ends with an empty bubble has no body, and
  a banner with a title and no text reads as a bug.

A loop check passes all three on purpose. Something that reports every ten
minutes while nobody is watching is exactly what a notification is for.
The reply, flattened into something a banner can hold.

Newlines are collapsed because macOS renders a banner as at most a few lines
and folds them itself; a reply that opens with a heading and a blank line
would otherwise spend the whole banner on the heading.

- Parameter limit: how much survives. 180 is well past what a banner shows —
  the cap is there so a thousand-word answer isn't handed to the system in
  full, not to match a pixel width.


## ConversationArchive.swift

A conversation that has been put away, so starting a new one doesn't destroy
the last one.

Two different things have to come back when this is reopened, and confusing
them is the whole risk of the feature: `entries` is what was *said* — the
words the person already read — and `sessionID` is what the model
*remembers*. Restoring the first without the second gives you a transcript
full of context the model has no knowledge of, which reads as the app having
quietly lost its mind mid-sentence. Whenever the second can't be restored,
that has to be said out loud rather than papered over.
What the menu calls it. Derived once, when the conversation is put away,
and stored — a title that recomputed itself would change under the
person as the derivation improved.
Claude Code's own session for this thread. Absent when the conversation
never reached the model — the person typed, the turn failed, and there
is nothing on the other side to resume.
The project this ran in, held by id and never by path.

`ProjectStore` keeps paths out of chat history on purpose, and this file
is chat history. The path is looked up through the registry at the
moment of resuming, so a project that has since been removed resolves to
nothing rather than to a stale directory we'd then hand to a tool.
How many conversations the menu keeps.

A menu is a list you read at a glance; past a screenful it stops being one.
Whether the person said this to the assistant, or to the app.

A slash command is an instruction to the program — `/new`, `/history 2`,
`/model sonnet`. It appears in the transcript because seeing what you typed
is how you know it registered, but it isn't part of a conversation, and
treating it as one produced a history row literally titled "/history 1":
reopening a conversation archived the command used to reopen it.
Whether this conversation is worth keeping at all.

The rule is that somebody said something. Opening the app, watching the
greeting arrive and pressing New Conversation must not leave a row behind —
the history would fill with threads nobody had, and the ten real ones would
fall off the end to make room for them.

`relayed` is the second way for something to have happened, and it exists
because of what "somebody" quietly meant: a `.user` turn. A character who
spent her whole conversation doing another character's errand never has one
— every line in her transcript is hers — so the entire exchange was dropped
on the floor. Measured on 2026-08-14: Pikachu and Ditto both answered a
relayed request, both showed it on screen, and neither conversation file was
touched, while the character who *sent* it filed hers normally.
The conversation as it should be filed.

Commands stay where they fall — `/model sonnet` halfway down explains why
the answers change tone after it, and removing it would leave a conversation
that doesn't account for itself. The exception is the last line, which is
the command that closed the conversation and belongs to what happens next
rather than to what was said.
What to call a conversation in the menu.

The first thing the person asked for, shortened. Deliberately derived rather
than generated: asking the model for a title costs a turn, can fail, and can
be slow at exactly the moment the person is trying to start something else —
three failure modes for a menu label. The opening question is also what
people actually search their own memory by.
Cut on a word boundary when there is one near the end, so a title doesn't
break in the middle of a word — but never search so far back that a long
first word leaves a stub.
Puts a conversation at the front of the list and drops whatever no longer
fits.

Newest first, because that is the order they are looked for in, and it means
the cap always trims the end. Re-archiving a conversation already in the
list replaces it in place rather than appearing twice: resuming and putting
away again is one thread continuing, not two.
What one row in the history menu reads as.

The title alone isn't enough to tell two of them apart — people ask the same
thing on different days — so the age rides along. Coarse on purpose: the
question a menu answers is "which one was that", not "at what minute", and a
clock time would have to be read and converted before it meant anything.
One row of the history menu, already decided.

Plain Swift on purpose: this crosses into `AISecretaryApp`, which cannot
import `FunctionalCore` without Bow's `State` shadowing SwiftUI's. The menu
receives answers, not domain values to interrogate.
The conversation currently on screen, when it came from this list.
MARK: - Persistence

The transfer shape. `TranscriptEntry.id` is a `let` with an inline default
and `Option` has no `Codable`, so neither type can be encoded directly.
An unreadable kind becomes a plain message rather than being dropped: a
file written by a newer build should cost the person a differently-styled
line, not a hole in a conversation they read.
Keeps the history as JSON under Application Support, beside the registry.

Failures come back as values for the same reason `FileProjectStore`'s do:
this is read at launch, and an unreadable history file must cost the person
their old conversations, not their app.
Where history lived while there was one character. Still read once, to
be adopted — see `conversationFileMigration`.
One file per character. A character's conversations are hers, and a
single file holding everybody's would have to carry an owner on every
row and be rewritten by whichever character saved last.
Hands the pre-Sprint-13 history file to a character, once.

The decision is `conversationFileMigration`; this reads the two `exists`
answers off the disk and applies what it says. Returns what it decided
so a caller can see whether anything moved.


## ConversationFileMigration.swift

What to do with the history file written before characters had their own.

This was the first per-character migration and the shape it found is now
shared with the project registry, which needed the same decision word for
word. The name stays because the history file's callers read better with
it, and because it is the name its tests know.
- Parameters:
  - legacyExists: whether `conversations.json` is on disk.
  - perCharacterExists: whether this character's own file already is. If it
    is, she has been through this once and the old file is somebody else's
    problem — never overwrite what she has now with what everyone shared
    then.


## DelegationIntent.swift

What the person's message looks like it wants doing about another character.

Three answers rather than two, and the middle one is the point. The charter
forbids guessing an action out of prose — the ```choices block exists
because a model writes lists constantly and picking them up built pickers
over things that were never questions. The rule that survives is not "never
read prose", it is **never act silently on a guess**: an unsure reading here
becomes a question the person answers, so nothing is done on a maybe.
Nothing about anyone else. An ordinary turn.
Someone is meant to be asked and it isn't clear who.
Send it — to one character, or to several at once.

Plural since 0.14.236, and still plural, but **prose no longer produces
a plural**: from Sprint 17 the several-recipients case comes from the
model's own ```to block, which names them a line at a time and is read
rather than scanned. Reading "จาก Pikachu และ Ditto" as two recipients
meant asking `contains("และ")` whether a conjunction joined the *names*,
which it cannot know — and the price of being wrong is the person's work
sent to somebody who was never asked.
Phrases that name a third party by their shape alone — the person is asking
for something to be passed on, not asking you.

These stand on their own: `ขอให้` with nobody named still means somebody
else is meant to do it, and that is the case this list exists for.

**Frozen. Do not add to this list.** It grew twice in one day (2026-08-14)
chasing sentences that had slipped through, and the second note recorded
that the slipped case reached the model and *did the right thing through the
block*. That is the answer: a phrasing this list misses is the model's to
read, not a signal to type another keyword. Substring matching on a language
written without spaces cannot be made good by lengthening it, and every
word added widened what it caught in ordinary sentences too.
A name short enough to appear inside ordinary words is not looked for.

Thai runs without spaces, so matching has to be by substring, and a
one-character name would match nearly every sentence. Two is the shortest
that is worth trusting; a character called "A" simply cannot be addressed by
name, which is a better failure than every message being read as an errand.
A *first word* has to clear a higher bar than a whole name, because it is a
guess about what somebody is called rather than what they are called.
Three was not enough: "The Assistant" offered "the", which appears in most
English sentences ever typed. "Miku" is four.
The ways a character can be named in a sentence.

Her whole profile name, and — when it is several words — the first of them.
Profiles carry what they are for as well as who they are: the one on this
machine is called **Miku (Second Brain)**, and nobody types that. Without the
first word she could not be addressed at all, which would have shipped as
"it works for one of my characters and not the other".

Only the first word, and only when it is long enough to be worth trusting:
"The" and "Dr" would match half of everything.
Reads the person's own words against the roster.

Deterministic: no clock, no ids minted, same text and same roster in, same
answer out. The errand it hands on is **the whole message, uncut**. Trying
to excise "ช่วยขอให้อาเนีย" and forward only the remainder is exactly the kind
of surgery that goes wrong on a language without spaces, and the recipient
reads the request better with the sentence intact than with a stump of it.
One unambiguous hand-off phrase, one name on it. The only reading this
function still makes on its own.
Several names is always a question now. It used to send to all of them
when a conjunction appeared somewhere in the sentence, which was a guess:
`contains("กับ")` cannot tell "Anya กับ Ditto" from "Anya กับผม", and a
wrong recipient is work sent to someone who was never asked, with no
undo. A person who means both is one tap away through the question, and
the model — which reads the sentence rather than scanning it — names both
in its own block when it is sure.
The case this whole enum exists for. The owner's own scenario writes
"อาเนีย" for a character whose profile name is "Anya", so a roster-name
match finds nothing and the message would otherwise be answered as if it
had been meant for the character it was typed at — which reads, correctly,
as the feature not working. A phrase that means "somebody else" with
nobody matched asks who.
Offered alongside the names, because the reading may simply be wrong.

Without a way out, a false positive on `ขอให้` — which appears in ordinary
sentences that have nothing to do with anyone else — would leave the person
with no option but to send work somewhere they never meant to.
Offered whenever more than one name was found, so that "both of them" is a
tap rather than a rephrase.

Sprint 17 stopped prose from producing several recipients on its own, since
deciding it meant asking `contains("และ")` whether a conjunction joined the
*names*. Asking instead is right; asking a question whose only answers are
"Anya" and "Ditto" when the person plainly wrote both is not — that is the
app making them choose one, which is the same wrong guess with an extra
step. So the question carries the answer they meant.


## DelimitedTable.swift

Pasted rows — CSV or tab-separated — recognised as a table.

The reason this exists: handing over data is the point of Sprint 11, and the
two ways a person has it to hand are a file and their clipboard. A pasted
CSV rendered as prose is a wall of commas the person cannot check, and the
whole risk of data entry is entering the wrong thing — so it goes on screen
as a grid, in the same view a markdown table already uses, and they can see
their own columns before anything is typed into anyone's web app.

Recognition, not parsing of a format. Everything below is about *whether*
this run of lines is a table; the fields are split simply and quoted commas
are respected because a name like "Smith, J." is the ordinary case, not an
edge one.
The delimiters worth guessing between. Semicolons are what a European
spreadsheet exports; tabs are what a copied selection carries.
Fewest lines that can be a table: a header and one row. One line of
commas is a sentence.
Splits a message into prose and every table in it — pipe tables first,
then pasted rows inside what is left.

Order matters: a markdown table's separator row (`---|---`) is itself
consistent enough to look delimited, so the pipe parser gets first look.
The longest run of lines from `start` that all split the same way.

"The same way" is the whole test, and it is deliberately strict: every
line in the run has to yield the same number of fields, and there has to
be more than one field. Two consecutive prose lines almost never carry
an identical number of commas, and the cost of being wrong is a
paragraph drawn as a grid — so being wrong is made hard rather than
impossible.
A run where nothing is filled in — ",,," repeated — is punctuation
that happens to line up, not data.

Whether this comma is the one inside "1,250" rather than a separator.

Found by driving it: a reply reading "total 1,250 THB" over two lines
split into a two-column grid with the thousands cut off in the first
column. A comma between two digits is part of a number in every locale
that writes numbers that way, and a CSV that means a comma there quotes
the field — so this loses nothing and stops the most common false table
there is, money.
Whether a line's fields read as data rather than as a sentence that
happens to contain commas.

Matching field counts alone was not enough, and the case that broke it
is ordinary writing: "I went to the shop, and then home." over "It was
raining, so I hurried." is two lines of two fields each, and it was
drawn as a two-column grid. Two signals separate them — a sentence ends
in a full stop, and a cell is short. Both are about the *last* field or
the length, neither about the content, so nothing here has to know what
the data is about.

The cost, stated plainly: a column of long notes that end in full stops
stays prose. That is the safe way round — an unstyled CSV is still
readable, a paragraph in a grid is not.
One line's fields. Quotes are honoured because a value with a comma in
it — an address, a name written surname-first — is what quoting is for,
and splitting through it would silently shift every later column.
A doubled quote inside a quoted field is one quote.


## DismissTarget.swift

One character, as far as Esc is concerned.
Whether one of her windows currently holds the keyboard.
Whether she has anything Esc would put away — a chat bubble up, or a
pinned pane.
Whether she is on the desktop at all. The last rung of the ladder: with
nothing left to put away, Esc puts *her* away.
Whether Esc has anything to put away for one character.

**Counts panes that are on screen, never panes that merely exist.** The set
behind a character's pinned panes deliberately keeps every pane that was ever
pinned — the status-bar menu is built from it, and a pane that Esc put away
has to stay listed so one click brings it back. Asking that set whether it is
*empty* therefore answers a different question from the one Esc asks, and it
answers `true` for the rest of the session after the very first pin.

What that cost, driven on 2026-08-17 at v0.17.278: pin one box, press Esc to
put the pane away, press Esc again to close the chat — and the third press,
the one that should hide the character, did nothing, then or ever again in
that session. `dismissDecision` was right to refuse; it was being told
something was still on screen. The same wrong answer keeps the system-wide
Esc claim registered with nothing of ours visible, so the key is taken from
every other app and spent on doing nothing.
Where an Esc press came from.

The two paths are not interchangeable and the difference is the whole reason
this is a parameter rather than an assumption:

- `.hotKey` is the system-wide claim. It arrives from anywhere, including
  while the person is typing in another app, so it may only put windows
  away — never hide a character somebody isn't looking at.
- `.ownWindow` is the local monitor, which by construction only sees the key
  when one of this app's windows holds the keyboard.
What Esc does, and to whom.
Put away the frontmost thing she has — a pinned pane, else the chat.
Take her off the desktop.
What Esc means right now.

Esc is claimed from the whole system, once, because that is all the system
grants — so with several characters on the desktop something has to decide
whose window it means. It went to `characters.first` for a while, which is
how Esc stopped working: type in the third character's bubble, press Esc,
and the first character's chat is asked to close, which it usually is not
even showing. The key that had always put the chat away appeared to do
nothing.

The keyboard is the answer when there is one — you are typing in her, so she
is the one you mean. Failing that, anybody with something to put away, in
roster order, so Esc still works when the pointer never entered a bubble.

**Two Esc handlers exist, and this function is what keeps them from both
firing.** The hot key is registered only while something is dismissable
(`claimedShortcuts`), and while registered it consumes the keystroke before
any local monitor sees it. Rather than trust that ordering, the rule is
written down: a local press with anything dismissable on screen belongs to
the hot key and this returns `nil`, so the local monitor lets the event
through instead of acting on it. Exactly one of the two paths ever answers.

Hiding a character is deliberately unreachable from `.hotKey`. Esc is the
busiest key on the keyboard, and a companion that vanished because somebody
dismissed a dialog in Photoshop would be a bug, not a feature.


## EmptyTranscriptHint.swift

Where the search for the person's own coding tool has got to.

Three states rather than two flags, because the middle one is the whole
point: not finding it *yet* is not the same as not having it, and a panel
that treats "still looking" as "not installed" tells everyone who launches
the app to go and install what they already have.
What stands in for the conversation before there is one.

A pure function in a library target rather than a string in the view,
because `AISecretaryApp` is never linked into the test bundle — and this is
what that costs when it isn't: the ready line shipped with thirteen literal
spaces in the middle of it, left behind when a line break was collapsed into
the sentence, and nothing could see it but a person looking at the window
(reported 2026-08-17). The tests below assert the whole string, which is the
only kind of assertion that catches whitespace.

`makers` are the tools the app can run a turn through, and they arrive as an
argument rather than being named here: this line greeted every character
with "your own Claude Code", including the ones set to OpenCode, which is
the same defect the Model and Effort menus had before they learned to say
"the tool's own default" (owner, 2026-08-21). The greeting no longer names a
maker at all — which one was found is already in the brackets after it.
One break, not a blank line. Two beats — what I am, then what to do —
so they do not belong on one line, but a paragraph between two short
sentences read as a gap rather than as structure (owner, 2026-08-17).
The makers written out for a sentence. An empty list still has to read as
English, because "Install  and sign in" is how a missing argument would show
up on screen — and the reason this file is a tested function at all is that
nothing else in the app can see a broken string.


## ErrandPlan.swift

One character's answer to an errand.
A numbered request split into the part to send now and the part to do once
the answers are back.

The person writes what they want as a list, and the list is the plan:

    1. ขอข้อมูล … จาก Pikachu และ Ditto
    2. เมื่อได้ข้อมูลทั้ง 2 ชุด ให้รวมข้อมูล แล้วบันทึกลง file ใน project

Before this, the whole thing was forwarded verbatim and step 2 went with it
— so the character who was meant to *do* step 2 never saw it, and the
characters who were only meant to answer step 1 were handed an instruction
to write files in a project they cannot reach.
What to send now.
What the sender does once the answers are in.
A line that opens a numbered step: `1.`, `2)`, `ข้อ 3`.
A bare "2015 Civic" is a year, not a step. The punctuation is what makes
it a list item.
Splits a numbered request, or `nil` when it is just a message.

Two steps at minimum, and they have to be numbered — inferring a plan from
prose would turn "I want two things: a and b" into a hand-off with a
follow-up nobody asked for.
The first has to be step 1 and there has to be a second one, or this is
an ordinary message that happens to contain a numeral.
What the sender is asked once the answers are in.

The answers are quoted rather than summarised, and whoever did not answer is
named. A follow-up that silently works from one reply when two were asked
for produces a comparison of one thing, presented as a comparison of two.

In the sender's chat, when one errand went to several people.
Said when somebody could not be sent to at all, so the person knows the
plan shrank before it started rather than wondering later.


## FencedBlock.swift

Splitting a ```something block off the end of a reply.

The shape is the app's one way of letting the assistant ask for an action:
marked, or it didn't ask. Guessing from prose would turn every sentence
containing "I'll keep an eye on that" into a running background job — and
the model writes sentences like that constantly.

`LoopBlock` and `InfoWindowBlock` predate this and each carry their own copy
of the walk; they are left alone rather than churned, but nothing new should
add a fourth.
The message with the block removed, plus the non-empty lines that were
inside it. `nil` when there is no block, which is nearly every message.
An empty block asks for nothing. Hand back the original rather than
showing a reply with a hole where the marker was.


## FileUnderstanding.swift

Reading a file *and asking the model about it*.

This is deliberately a separate concept from `FileOperation.readFile`, which
only shows you the bytes locally. Understanding a file sends its contents to
the Anthropic API, so it is classed `.externalNetwork`, not `.readOnly` — it
can never run unattended, and the user is asked every single time, with the
destination named in the prompt. Approving "read files in this project" must
not silently become permission to upload them.
What to ask about the file. A closed set, like every other operation the
Secretary can plan — the user's words never become a free-form command.
The instruction appended after the file contents.
Never `.readOnly`: the file leaves the machine.


## FolderWatch.swift

A project that exists only to name one folder somebody approved watching.

Never registered and never saved. It is the smallest thing that carries
"this folder, read-only, right now" through code that expects a project —
and rooting it *at* that folder is what keeps the adapter's escape check
working every tick, now around the boundary that was just agreed to.

A new identity each time it is called, deliberately: a grant recorded
against it can never be matched again, so the same folder is asked about
afresh rather than quietly inheriting yesterday's yes.
A path the person asked to be told about.

`.readOnly`: nothing is written and nothing leaves the machine — it is
repeated reading of files in a project they already approved. That is a
weaker grant than `InstructionRequest`, deliberately, and the difference is
exactly whether the bytes go anywhere.
`.` is the natural way to say "this project", and reads badly
everywhere else, so it is normalised once here.
Where this points when it names somewhere outright rather than somewhere
inside a project — an absolute path, or one starting at the home folder.

Answered here, without a project, because it decides which way the
request is routed *before* a project has been resolved: a full path is
not a thing to look for inside a project and then refuse, it is a place
the person named and can be asked about.

Symlinks and `..` are resolved, so what the card shows is where the
reading will actually happen. That is the whole point of showing it.
What changed under a watched path between two looks.
The most that can be watched at once.

Each one costs a walk of up to `WatchLimits.maxEntries` every few seconds,
so this is the same argument as those caps, one level up: several watches
are genuinely useful — a folder for new files and a document for edits —
but an unbounded list is an unbounded amount of work on a timer. Hitting it
refuses the new one and leaves everything already running alone.
How much of a folder is worth looking at.

The caps are not tuning knobs, they are the feature working at all: a
registered project is often a whole repository, and `.build` alone can hold
tens of thousands of files. Re-stamping those every few seconds would be a
background process quietly eating the user's Mac, which is the opposite of
what a desktop companion is allowed to be.
Directories never descended into: build output and dependency trees
change constantly and mean nothing to the person watching.
One look at a path: every entry that was there, and a stamp saying what it
was like.

The stamp is size-and-modification-time for entries under a folder, and the
content digest for a single watched file. That split is the two backlog
bullets: a folder is being watched for *what appeared, vanished or moved*,
where cheap identity is enough and hashing every file would be absurd; a
single file is being watched for *whether its contents changed*, which is
the only question a stamp can't answer honestly — saving a file unchanged
moves its mtime.
True when the walk hit `maxEntries` and stopped. Surfaced to the user,
never swallowed: "watching this folder" and "watching the first 500
files of this folder" are different promises.
Sorted so the same change set always reads the same way, and so a test
doesn't depend on dictionary order.
Two questions, each answered over one collection: what is in the new
snapshot that is new or different, and what was in the old one and
isn't there now. The accumulator this replaced could be read three
ways depending on where you entered the loop.
How a set of changes is announced.

Capped, because a `git checkout` under a watched folder produces hundreds of
changes at once and a message listing them all is a message nobody reads —
but the count is always exact, so the summary never understates what
happened.
"3 changes" / "1 change" — the headline, always the true total.
Takes a look at a path on disk.

Lives here rather than in an adapter because what it produces is a value the
rest of the app compares and renders; the only thing it borrows from
Foundation is the directory listing. The caller has already resolved the URL
through the project's own rules — nothing here joins a path from user text.
The most a single file's contents are read before falling back to its
size and date. A watched log can grow without bound and must not be
pulled into memory every few seconds.
Resolved once, up front, and used for both the walk and the relative
paths. `contentsOfDirectory` hands back real paths, so on a Mac where
the folder is under /var the listing comes out as /private/var and
stripping the unresolved root leaves mangled names like
"/privatesrc.swift" — every entry then reads as added-and-removed on
the next look.

Contents, so that saving a file without changing it isn't reported as a
change — the whole point of watching one file rather than its folder.
Size and modification date. Cheap enough to do to hundreds of entries on
a timer, which contents are not.
A path being watched, and what it looked like last time.

Carries its own project rather than borrowing one from beside it: several
of these run at once and they need not be in the same project, so a single
"the project being watched" would be a value that is right for one of them
and wrong for the rest.
Relative to the project. Empty means the project folder itself.
The folder this actually landed on, symlinks resolved.

Identity, and only identity. The loop deliberately re-resolves through
the adapter on every tick instead of reusing this, so the escape check
keeps running rather than being answered once at the start.
How many times something has been reported. Shown when it stops, so the
person can tell "nothing happened" from "I wasn't looking".
What the person asked for when this watch started, verbatim.

Held because the model is not: a change report was said into the
transcript and never into the conversation, so the assistant never saw
it happen and could not act on the standing instruction it had been
given. Told "watch this folder and follow the instructions in whatever
lands there", it reported the new file and did nothing with it — the
owner's Sprint 21.2 report, and it reads as forgetting when it is really
never having been told.

Empty means nobody is asked to do anything: the watch reports, as it
always did.
The folder itself, which is what "already watching that" is really
asking about.

It used to be the project's id plus the relative path. That answered the
question only while every watch came through a registered project: a
folder named outright is carried by a throwaway project made on the spot,
so a second `/watch` of the same folder arrived with a different id and
would have started a second watch reporting everything twice. The folder
on disk can't drift like that.
The name to use in a message. The project's own folder has no relative
path, and "watching “”" reads as a bug.
Whether the person meant this one when they typed a path. They type
what they see in the messages, so both spellings have to answer.
What the assistant is told when something changes under a watch it was asked
to act on.

The change goes to the *model*, not only into the transcript. `say` writes a
bubble and nothing else, so before this the assistant learned nothing at all
from a watch: the person saw "👁 1 change", the model saw nothing, and the
standing instruction — "when a file lands here, do what it says" — was never
reached. It looked like forgetting.

The instruction is quoted back rather than trusted to memory for the same
reason `OutstandingRequest.reminder` quotes the request back: it is several
turns old by now, and the app has it written down.

Returns nothing when nobody asked for anything to happen — a bare `/watch`
is a request to be told, and told is what `say` already did.
A typed slash command says only "watch this", so there is nothing to
carry out and no turn worth spending on it.


## FontChoice.swift

Which face the conversation is set in.

Four system designs rather than a list of installed families, and the reason
is the one that made this setting necessary in the first place. The chat was
drawn with `monospacedSystemFont`, which has no Thai glyphs at all, so every
Thai word fell out of it into whatever the system reached for next — measured
on 2026-08-14, that is Ayuthaya, a wide display face that reads as bold
beside the Latin around it. Nothing in the app had ever asked for bold.

A system design cannot repeat that. Each is a request the font machinery
resolves per script, so Thai lands on the Thai face of that design instead of
on whatever happens to be installed. A named family can't promise it: half of
what `availableFontFamilies` returns has no Thai at all, and offering a
picker whose entries turn the owner's own messages into empty boxes would be
a worse bug than the one being fixed.

Code is not affected by any of this. A fenced block stays monospaced whatever
is chosen here — alignment is the whole point of it, and this setting is
about prose.
The face the rest of macOS is set in.
The same proportions with the corners taken off. Softer, and noticeably
friendlier at the sizes a companion window is read at.
With serifs, for reading long answers rather than scanning short ones.
Fixed width everywhere, which is what the chat used to be for everyone.
Kept as a choice, not as the default: it is the right face for output
and the wrong one for a conversation.
What the row in Settings says under the name.


## FooterOrder.swift

The panel buttons along the bottom of the chat.
One position in the footer row — a button, or the gap that pushes the rest
of the row to the far edge.

The gap is part of the sequence rather than something the view adds, because
it is what makes the row two groups instead of one, and mirroring has to move
it along with everything else.
Left to right. The same row wherever the bubble is.

The row is not one cluster: Projects sits alone against the left edge, and
Profile, Skills and Settings sit together against the right, with the
window's width between them.

```text
| [Projects]                [Profile] [Skills] [Settings] |
```

This used to reverse — gap included — when the bubble mirrored, on the
reasoning that each button then kept its distance from the outer edge it had
been against. That reasoning was about the box; the person is aiming at
Settings, and Settings moving to the far end because the character wandered
too near the right of the screen costs a hunt every time. A row that reads
the same in both placements is worth more than one that mirrors tidily, so
the placement is no longer an input here at all.


## GlobalShortcut.swift

A key combination the app claims from the whole system, not just from its
own windows.

These are not ordinary shortcuts. A system-wide hot key *consumes* the
keystroke, so while one is claimed that combination stops meaning what it
used to mean in every other app. Which ones are claimed, and when, is
therefore a decision worth stating in one place and testing, rather than a
pair of register calls buried in window code.
⌘H is deliberately **not** here. It was, briefly, and taking it broke Hide in
every other app on the machine — which is the whole hazard this type exists to
make visible. ⌘H stays an ordinary per-app shortcut, served by the menu item,
and works when this app is frontmost like everyone else's.
Esc — put the chat away, from anywhere.
Key code and modifier mask, in the form Carbon wants.
Which shortcuts should be claimed right now.

`closeChat` is claimed only while there is something on screen for it to put
away — the chat bubble, or a pinned pane. Esc is the busiest
key on the keyboard — it cancels dialogs, leaves full screen, ends a Keynote
slideshow — and claiming it permanently would break all of that for the sake
of a window that isn't even showing. With the chat closed the shortcut has
nothing to do anyway, so releasing it costs nothing and hands Esc back to
whatever app the user is actually in.

Nothing at all is claimed when there is nothing to dismiss. A desktop
companion that is only sitting there has no business holding a key hostage.


## GripCorner.swift

Which corner of the chat bubble the resize grip sits in.

Pulled out of the view so the rule can be pinned down by tests: the grip has
to be in the corner the bubble grows out of, and that corner moves as the
bubble mirrors and flips. Get it wrong and the gesture argues with itself —
you drag away from the empty space you are trying to fill.
Bottom edge rather than top.
Leading edge rather than trailing.
The grip goes opposite the tail horizontally and on whichever horizontal
edge is free to move vertically. Both are the edges the bubble grows into,
which is what makes "drag it the way you want the box to extend" and the
usual corner-handle reading of "drag away from the box" the same gesture.
The SF Symbol whose arrows already lie along this corner's own diagonal,
pointing out of it. Named rather than produced by rotating one glyph: a
rotated symbol is a symbol drawn at an angle it was not hinted for, and
"which way does this arrow point" is exactly the thing the grip has to say
without ambiguity. Two corners share each diagonal — a double-headed arrow
reads the same from both ends.

Each diagonal has an inward twin whose name is the same two words in the
other order: `arrow.up.right.and.arrow.down.left` draws the arrows meeting
in the middle, which reads as "collapse". The name lists the directions the
heads point, so the outward one names the corner's own two directions.


## HandOffBlock.swift

The assistant asking the app to pass something to another character.

```to
Pikachu
หาราคา civic 2015 เทียบกับ vios 2015 ให้หน่อย
```

**This exists because the alternative was a lie.** The app reads the
person's own words for a hand-off, and that catches the plain cases — but
when it misses, the turn goes to the model, and a model that has just been
told other characters exist will try to reach them. Driven on 2026-08-14:
Ditto found Claude Code's own `SendMessage`, aimed it at a Claude Code
session, and reported success to the person. Nothing had been sent.

Denying that tool stops the false claim; it does not give her a way to do
the thing she was asked to do. This is that way, and it is the same shape as
every other request the assistant can make of the app — marked, never
inferred, so a reply that merely *mentions* asking Pikachu stays a sentence.

First line is who, the rest is what. The name is matched against the roster
by the caller, which knows who is on the desktop; an unknown name is
answered rather than guessed at.
Everyone named on the first line.

Plural since 0.14.242. It took one name, so a character asked for
something from two people could only ever reach one — and said so,
out loud, to the person who had asked for both: *"ขอถามทีละคนก่อนค่ะ"*.
She was describing the limit of the block she had been given.
The message with the block taken out, ready to render.
Several names on one line, however they were separated.

A model writes a list the way a person would — commas, `และ`, `and` —
so all of them are accepted rather than one being mandated and the rest
silently swallowed as part of a name.
`to: Pikachu` reads better in a prompt than a bare name, so the label
is accepted and dropped — the same courtesy `WatchBlock` extends to
`path:`.

A name with nothing to say is not a request. Sending an empty errand
would put "← Ditto passed this on from you" in someone's chat above
no question at all.


## HoverClaim.swift

Which box in the transcript shows its pin and copy buttons, after one
pointer event.

One value for the whole thread rather than a flag per box: the pointer is
only ever in one place, and a flag each is a set of them that can all be
true at once after a fast drag.

The clause that earns this a function of its own is the second one. A box
being left may **not** clear the claim unless it still holds it: moving from
one box to the next delivers the new box's enter before the old box's leave,
so a leave that cleared unconditionally would wipe a claim that has already
moved on.

**Only the box reports.** The buttons hang off its corner, but they sit in
the box's overlay, and a view's hover region includes its overlay — measured
in the running app: gliding from the middle of a box onto its copy button
produces enters and no leave. The buttons used to report as well, on the
theory that reaching them meant leaving the box, and that extra reporting is
what broke them: moving from copy to pin fired copy's *leave*, which
released the claim and unmounted both buttons out from under the pointer.
The pin button was unclickable. Nothing but the box may report, or that
comes back.


## InfoWindowBlock.swift

A pane of content the assistant was asked to put somewhere it will stay.
Markdown, rendered with the same parser the chat uses, so a table asked
for in the chat looks the same once it is pulled out of it.
Reading a ` ```window ` block out of a reply.

Marker-based for the same reason as ` ```choices ` and ` ```loop `: the model
produces tables and lists constantly, and guessing which of them the user
wanted kept would open windows nobody asked for. Only an explicit block
counts, and the block never survives into what is shown — otherwise the
content appears twice, once in the chat and once in the window.
The message with every block taken out.
What to open, in the order the blocks appeared. Several are allowed:
"pin these two side by side" is one request, and merging them into a
single pane — which an earlier version did silently — answers a question
nobody asked.
The first `title:` line names the window; everything after it
is content, including any later line that happens to start
with "title:".
An unterminated block still counts; the stream ended, not the intent.

Nothing usable: leave the message whole rather than half-swallowed.
The set of panes currently kept open, oldest first.

A value rather than a mutable list so the menu, the windows and the tests all
read the same thing, and so "remove one" and "clear all" are single
expressions instead of index arithmetic.
Enough to be useful, few enough that a runaway loop of window blocks
cannot bury the screen. The oldest goes when the limit is reached.
A pane already showing exactly this, if there is one.

Pinning the same box twice should hand back the window you already have,
not a second copy of it. That is what a reader means by "pin this", and
it also absorbs a duplicated click: a non-activating panel can deliver
the press that activates the app *and* the press itself, which turned one
press of the pin button into two identical panes cascaded across the
screen. Matching on what the pane holds rather than on timing means the
answer doesn't depend on how fast the second one arrived.


## InstructionFile.swift

Reading a file *and doing what it says*.

Kept apart from `FileUnderstanding` for the same reason that one is kept
apart from `FileOperation.readFile`: each is a wider grant than the last.
Reading shows you bytes; understanding sends them to the model; following
turns them into work. So this is `.externalNetwork` too — the contents leave
the machine before anything is planned — and the user is asked every time,
with the file named.

The user picks the file. Nothing here searches for one, and no filename is
ever inferred from a request: "run my deploy steps" resolves to a path the
person typed, or it doesn't resolve at all.
Never `.readOnly`. Approving "read files in this project" must not
become permission to upload one, and it must certainly not become
permission to act on what it says.
What a file said, small enough to keep and compare.

Two questions need this and they are the same question at two scopes: has
the file changed *while a run is going* (stop, don't quietly switch to new
instructions mid-flight), and has it changed *since the last run this
session* (say so before starting again). Content, not modification date —
touching a file, or saving it unchanged, is not a change to what it asks
for.
A short SHA-256 hex digest. Short because it is shown to nobody and
compared against itself; 16 hex characters is 64 bits, which no accident
will collide on.
Which instruction files have already been run, and what they said at the
time.

Session-scoped and never written to disk, like `selectedSkills` and
`activeLoop`: "have the steps changed since last time?" is a question about
this sitting, and a stale answer from last week would either nag about a
change the person already approved or stay silent about one they didn't.
False for a file never run here — a first run has nothing to have
changed from, and saying "the steps changed" would be a lie.


## InstructionPlan.swift

The steps a file asks for, as the model read them back.

There is deliberately no parser here for the file's own format. The charter
asks this to work with prose, numbered steps, a diagram, or a LangGraph
graph — four parsers, none of which would ever cover the fifth thing
somebody writes. The model reads the document and answers in one shape;
this is that shape, and it is the only thing the rest of the app sees.

It is a plan, not a permission. Every step still runs through the ordinary
approval path when it acts, and the whole plan is shown before any of it
starts.
What the file said when the plan was made. The run is pinned to this.
A message with a ```plan block in it, split apart.

Same shape as `LoopBlock` and `MessageChoices`, and for the same reason:
steps guessed out of prose would turn every list the model writes into a
plan waiting to be run. Marked or not a plan at all.

```plan
Pull the latest changes
Run the test suite
```
The message with the block taken out, ready to render.
An empty block asks for nothing. Hand the message back whole
rather than showing a reply with a hole in it.
"1. Pull" and "- Pull" and "Pull" are the same step. The model is asked
for bare lines and mostly obliges, but a numbered list is the natural
way to write steps and shouldn't produce steps that begin with a digit.


## InstructionRisk.swift

Something in an instruction file worth reading twice before starting.

Why this exists at all, given that the model already reads the file: the
file is untrusted input, and a file that tells the model "this is safe, say
nothing about it" is exactly the input a model-side judgement fails on. A
judgement the document can argue with isn't a check. So the scan is ours,
deterministic, and runs over both the document and the steps that came back
from it — if a step appeared that the document didn't ask for, it is caught
on the same pass.

It escalates, it never refuses. A blocklist over free Thai and English
would miss the real cases and reject innocent ones — the same argument the
personality prohibition settles the same way — so a flag adds a warning and
an extra confirmation to a card the user was going to see anyway. The real
defences are elsewhere and unchanged: every step is shown verbatim before
anything runs, and every action a step takes still meets the ordinary
permission card.
What to warn about, in the user's terms.
The words that triggered it, so the warning can be checked rather than
believed. A warning nobody can verify gets clicked through.
The patterns worth stopping on, and what to say about each.

Grouped by consequence rather than by tool: the person deciding cares that
something might be deleted, not that the word was `rm` or `trash`.
Bare "email" rather than only "send an email": the natural way to
write the step is "email the report to…", and a warning that only
fires on one phrasing is a warning that misses the real file.
Scans a document and the steps read out of it.

One entry per reason, however many phrases matched: five spellings of
"delete" is still one thing to weigh, and a list of twenty warnings is a
list nobody reads.


## InstructionRun.swift

A plan being carried out, one step at a time.

A value, not a mutable controller: where the run has got to is something the
view renders and a test can construct, and a second copy of that number
living in a class is the copy that drifts.

The run is pinned to the fingerprint the plan was made from. If the file
changes while it is going, the run halts and says so — it does not pick up
the new steps, and it does not silently finish the old ones. Somebody
editing the file mid-run has changed their mind; carrying on with either
version without asking would be the app deciding which.
Stopped before the end: the user cancelled, or the file changed.
Which step comes next; equal to `plan.steps.count` when they're all done.
The step about to run, if there is one and the run is still going.
One-based, for people. `stepIndex` is zero-based, for arrays.
Moves on. A run that has just used its last step is finished, so the
caller never has to compare the index against the count itself.
"Step 2 of 5 of deploy.md" — used in the announcement before each step
and in `/run` status, so both say it the same way.


## Intent.swift

What the Secretary understood from a user message. Deliberately a small
closed set for this sprint — no free-form command construction.
Run a known read-only code operation, optionally against a named project.
Read a directory listing or a text file inside a named project.
Read a file *and send it to the model* to summarise, explain, analyse,
review or describe. Separate from `fileTool` because it leaves the machine.
Understood, but nothing to execute.
Not understood; the Secretary will say so rather than guess.
Rule-based classifier: keyword matching only, no model call. Anything that
doesn't clearly match a known operation returns `.unknown`, so the assistant
never invents an action from ambiguous text.

A class because it holds the rule tables, but it is not a seam: what the
Secretary takes is the function `classify`, not a protocol. There was a
one-method `IntentClassifying` here purely so a test could substitute it,
which is a closure wearing a protocol's clothes.
Ordered: more specific phrasings are checked before broader ones.
"Strong" prefixes name a file operation unambiguously ("show file …"), so
they classify as a file op regardless of what follows. "Weak" prefixes are
also common chat openers ("read me a poem"), so they only count as a file
op when the message is project-scoped or the argument looks path-like —
otherwise the message falls through to normal conversation.
Verbs that mean "tell me about this file". Every one of them is a common
conversational opener too ("explain how actors work", "review my plan"),
so unlike the read/list verbs these *always* require a path-like argument
— a project scope alone is not enough to make them a file operation.
File operations are checked before Git rules so "read the log file"
isn't captured by the "log" keyword. Both answers stay inside
`Option` until the last line, where the fallback is chat.

Whether `keyword` appears in `text` as a whole word or phrase, rather
than buried inside a longer one.

A plain `contains` matched "log" inside "login", so asking whether a web
page was logged in ran `git log` instead — and then failed, because the
tool path needs a registered project while ordinary chat does not. Any
keyword short enough to be useful is short enough to hide inside another
word: "diff" in "different", "status" in "statuses", "ls" in almost
anything.

Only ASCII letters and digits continue a word, because every keyword is
ASCII. Thai is written without spaces, so an English term inside a Thai
sentence usually has none around it — "ขอดูlogหน่อย" is the word `log`
with Thai on either side, and treating any letter as continuing the word
would miss it.
The first Git rule whose keywords appear in the text, as an `Option` so
`classify` can chain it rather than unwrap it. `first(where:)` says what
the `for … where … { return }` it replaced was doing: first match wins.
The armour `fileIntent` has had all along, finally on this side too.
A git keyword only means a command when the message is shaped like
one; in prose it is just a word. See `isSingleSentence`.
Parses "read <path> in <project>", "list [<path>] in <project>", etc.
Returns nil if the text isn't a file command, so it falls through to Git
or chat. A path is never turned into an absolute path here — it stays a
project-relative string for the adapter to resolve and bound-check.
Understand: checked first so "summarize README.md" doesn't fall into
the read path and merely dump the file.
Read: explicit phrasing always counts; weak verbs need a scope or a
path-like argument so they don't capture ordinary chat.
List: a bare "list"/"ls"/"dir" is an unambiguous command. Everything
else follows the same weak-verb guard as read.
Parses "summarize <path>", "explain <path>", "what does <path> do".
Returns nil unless the argument actually looks like a path, so ordinary
requests ("explain how actors work") stay conversation.
"what does <path> do?" — the one non-prefix phrasing worth supporting.
Trailing punctuation comes off first so the "… do?" suffix matches.
"summarize the file src/Main.swift" — drop a leading article so the
path heuristic sees the path itself.
Heuristic for "this argument is a filesystem path, not prose": it contains
a slash, ends in a short extension, or is a leading-dot dotfile.
Splits a "… in/for/on <project>" suffix off the command, preserving the
original case of both halves. Returns (command, projectQuery?).
Note: no "." here — dotfiles like ".env" must keep their leading dot.
Extracts a project name following "in"/"for"/"on", e.g.
"git status in AI-Secretary". Returns nil when no such phrase appears.
MARK: - Prose is not a command

Whether this could be the name of a registered project.

Guards the `" in "` / `" for "` / `" on "` split, which used to hand back
everything after the marker whatever it was. A 300-character English
paragraph about debt management (2026-08-17) contained "legal **status**"
and "specializing **in** non-performing…", so it was read as `git status`
in a project named by the remaining ~50 words, resolved to nothing, and the
turn ended with *"No registered project matches …"* — **the model was never
called at all**, which reads to the person as the app going quiet.

The three conditions are what separates a name from a sentence:

- **60 characters.** Long enough for the longest folder name anyone has
  registered here (`AI-Secretary`, `Second-Brain`, `TISCO - AI Sharing`)
  with room to spare; far shorter than the ~300-character paragraph that
  caused this.
- **5 words.** A folder name is a name. The paragraph's tail ran to about
  fifty, and even a generous multi-word name stops well before five.
- **No `, . ( ) ; :`.** Sentence punctuation. A path may carry a dot, but
  this is not a path — the file rules have `looksLikePath` for that, and a
  trailing `.` or `?` is already trimmed before this is asked.

Both numbers are ceilings on a *name*, not tuned thresholds: the failing
input was an order of magnitude past either, so neither is close to the line.
Whether the text is one sentence, with no boundary inside it.

The second guard, and the one that catches prose the first cannot: a short
single sentence with "legal status" and " in " in it still classifies wrong,
and a paragraph with a plausible short tail after its last marker still
reaches the git rules. A boundary is `.`, `?` or `!` followed by whitespace
and then more text — `README.md` and a trailing `?` are both untouched by
that, and a real command is one sentence by construction.

**Structural on purpose, and it must stay that way.** A word count would be
a number, and the Settings-panel lesson is that a number can always be
exceeded; "one sentence" has no dial to turn. There is deliberately no
"unless it says `git`" shortcut either — that reopens the same hole for any
paragraph mentioning git, and this case never needed it.
Splits "<command> in/for/on <project>" at the **last** marker whose tail
could be a name.

Last, not first: a project name sits at the end of the request, while an
English sentence can contain "in" anywhere. The previous version looped over
the markers in the order `[" in ", " for ", " on "]` and returned the first
marker that appeared *at all*, which is not even the earliest one in the
text — "specializing in …" won over every later, better candidate.

Shared by the file rules and the git rules. It was two near-identical
copies, and guarding one of them would have left the other still able to
hand a whole paragraph to the file adapter as a path.

Searches `text` itself, case-insensitively. Searching a lowercased copy and
then slicing the original is undefined — a `String.Index` belongs to the
string it came from. It happened to work for ASCII and crashed on the first
Thai message that contained " On ": "Range requires lowerBound <= upperBound".
Every occurrence of every marker, in the order they appear in the text.
Resumes one character past the *start* of the hit, not past its end, so
overlapping markers in " on in " are both seen.


## LocalShortcut.swift

Whether ⌘H belongs to this app right now.

The chat bubble is a non-activating panel: it takes the keyboard without
making the app frontmost, so the menu bar still belongs to whatever the user
was in before. A menu key equivalent is searched in the *active* app's main
menu, which is why typing in the bubble and pressing ⌘H hid Safari, or the
terminal, or whatever happened to be behind — the keystroke was never ours
to begin with.

So it is claimed here instead, from the app's own event stream, and only
while one of this app's windows holds the keyboard. That keeps the promise
the owner set when a system-wide claim broke Hide everywhere: ⌘H stays an
ordinary per-app shortcut. The difference is that "this app" now means "the
window you are typing in" rather than "the app macOS thinks is in front",
which for a panel like this one are not the same thing.

**Matched on the key's position, never on the character it produces.** This
took `key: String` and compared it to `"h"`, which is only the letter H on a
Latin layout. The owner types Thai: with Kedmanee active the same key reports
`charactersIgnoringModifiers` as `้` (U+0E49), the comparison failed, the
monitor handed the event on, and the stale `Hide Character` item in the main
menu answered it instead — so ⌘H hid one character rather than the whole app,
exactly the behaviour Sprint 13-2 replaced. It looked like the feature had
been reverted; nothing had changed but the input source.

Measured on 2026-08-17 by logging the event: `code=4`,
`chars=Optional("\u{0E49}")`, `flags=1048576`, `keyWindow=true`. The control
in the same log is ⌘V, which kept working — main-menu key equivalents are
matched layout-independently by AppKit, and only this hand-rolled comparison
was not.

The test that should have caught it was called
`testCapitalsAndLayoutsAreTheSameKey` and checked `"h"` against `"H"`, which
is a *capital*, not another layout. Anything comparing a typed character to a
Latin letter has this bug; `keyCode` is the same number on every layout.

- Parameters:
  - isOurWindowKey: whether the keyboard currently belongs to one of this
    app's windows. False means the user is typing somewhere else and their
    ⌘H is none of our business.
  - keyCode: the hardware key, which does not move when the layout changes.
  - hasOnlyCommand: Command held, and nothing else. ⌘⇧H is Hide Others and
    ⌥⌘H is a different thing again; neither is ours to take.


## LoopBlock.swift

A loop the assistant asked to start, or stop, on its own.

The point of the feature is that nobody has to type: someone running a
workshop asks "keep track of where we are" once, with both hands otherwise
busy. So the assistant needs a way to set the timer itself — but a timer
that starts because a sentence *sounded* like a request would be exactly the
hidden autonomy this app is built to avoid. Hence a marker, the same shape
as `MessageChoices`: the request is unmistakable, and everything unmarked
stays prose.

```loop
every: 10m
บอกว่าตอนนี้ถึงหัวข้อไหน และถัดไปคืออะไร
```

Starting one is announced in the conversation with how to stop it, and the
limits in `LoopSchedule` apply whoever asked — so the worst case is a
visible, bounded, one-click-reversible timer rather than an app that quietly
talks to itself.
The message with the block taken out, ready to render.
What the assistant asked for, if it asked.
Splits a message. Anything without a block comes back untouched, which
is nearly every message.
An empty block asks for nothing. Hand back the original rather
than quietly dropping part of the message.
`every: 10m` reads better in a prompt than a bare `10m`, so the label
is accepted and dropped.

An unreadable or out-of-bounds interval leaves the message
whole and starts nothing: better a reply that mentions a
timer than a timer nobody asked for at a rate nobody chose.


## LoopSchedule.swift

Why a `/loop` request was refused.
The interval wasn't a duration anyone wrote on purpose.
Faster than this and a check would arrive before the previous answer
finished — and it would spend the user's Claude subscription doing it.
A standing instruction to check back in every so often.

The Secretary can already answer "where are we in the agenda?" when asked.
What it could not do is ask itself, which is the whole of what a person
running a workshop wants: they are in front of a room and cannot type. This
is that timer, kept as a value so the arithmetic of *when* is testable
without waiting for real minutes to pass.

Deliberately session-only. A loop is tied to something happening right now,
and one that survived a restart would wake up hours later asking about an
agenda that finished — the same reason write and browser grants are never
persisted.
How long between checks.
What to report each time, in the user's own words.
When the next check is due. Moved forward on each fire rather than
derived from `startedAt`, so a check that had to be skipped doesn't
leave the loop trying to catch up on missed ones.
A minute is the floor: a reply takes tens of seconds, and anything
tighter would have checks queuing behind each other.
Past a couple of hours this is a reminder, not a loop, and the user is
better served by asking when they want to know.
A working day. A loop nobody stopped must not still be running
tomorrow morning, quietly spending tokens.
What to report when the user didn't say. Phrased as an agenda check
because that is what asked for the feature, but it reads sensibly for
anything being watched.
A fresh loop's first check is one interval away, not immediate: the user
has just been talking to the Secretary, so it already knows where things
stand.
The loop after a check has gone out. The next one is measured from now,
so a check delayed by a reply still leaves a full interval of quiet.
A check delayed because the Secretary was mid-reply. The due time moves
on so the loop doesn't spin, and nothing is counted as delivered.
"every 10 minutes" in the shortest form that still reads.
The prompt a check sends. Says the time in words, because the model has
no clock of its own and this is a question about now.
Reading the argument of `/loop`.

Kept apart from the schedule itself so the parsing has no clock in it: the
command says *how often*, and only the Secretary knows *when* it was said.
What the user asked `/loop` to do.
Report the loop's state, or how to start one.
Parses everything after `/loop`.

Forgiving about how the duration is written — `10m`, `10`, `10 min`,
`10 นาที`, `1h`, `90s` all work — because this gets typed one-handed
while something else is going on.
The duration is the first word; whatever follows is what to report.
"10 นาที ..." and "10 min ..." put the unit in its own word, so it has
to be taken off the note rather than read as part of the report.
A duration on its own, checked against the limits. Shared with the
model-facing block so a loop the assistant starts can't be faster or
longer-lived than one the user could have typed.
A bare number is minutes: "/loop 10" means ten minutes, not ten
seconds, and certainly not ten hours.

The *longest* matching suffix wins, not the first one listed. Order
alone got this wrong: `10minutes` ends in `s`, so a first-match search
read it as ten seconds and then choked on the leftover `10minute`.
A unit written as its own word, as in "10 นาที" or "10 m".


## MarkdownTable.swift

A pipe table found in a reply.
A fenced block of code, or something the model handed over verbatim.
What the fence was labelled with — `swift`, `json`, and so on. Absent
when the fence carried no label.
One run of a message: prose, a table to lay out, or code to show verbatim.
Splits a reply into prose and tables.

SwiftUI's `Text` understands inline markdown but not tables, so a table
arrives as a wall of pipes and dashes. Pulling them out here lets the view
lay each one out properly — and, because a table is often wider than the
chat bubble, scroll it sideways on its own without the whole conversation
scrolling with it.

Deliberately forgiving: anything that isn't clearly a table stays prose. A
message is a model's output, not a document we control, and mangling normal
text that happens to contain a pipe would be worse than not styling a table.
Trailing blank lines around a table are separators, not content.
Code first. A fenced block can contain pipes, dashes, anything —
it is verbatim by definition — so looking for tables inside one
would tear it apart.
A blank line straight after a table is spacing, not prose.
A table is a row of cells followed by a dashes-and-colons row with the
same number of cells. Requiring both is what keeps ordinary prose
containing a `|` from being swallowed.
`---`, `:---`, `---:`, `:---:` — one per column.
Splits on pipes, ignoring the optional outer ones. Escaped pipes inside a
cell (`\|`) are honoured so a cell can contain one.
A fenced block starting at `index`, if there is one.

Fences have to be pulled out before anything else touches the message.
The inline markdown renderer is given `.inlineOnlyPreservingWhitespace`
so a stray character can't restructure a reply — but that also means it
swallows the fence and reflows the contents, which is how a JSON sample
arrived in the chat as `json { "iso": ... }` on one line.

An unclosed fence still yields its block: replies stream in, and the
closing line may not have arrived yet.
```choices is the app's own marker for a question, handled elsewhere
and already removed before rendering. Never draw it as code.

A fence with nothing in it is punctuation, not code.

Ragged rows are common in generated markdown; pad or trim so the grid
stays rectangular rather than dropping cells on the floor.


## MessageBubbleStyle.swift

How one transcript entry is laid out in the thread.

The conversation reads like a chat app: what you said is tucked against one
edge, what the Secretary said against the other, and neither runs the full
width. Which side an entry takes and how much room it may have are decisions,
so they live here rather than in the view — `AISecretaryApp` is never linked
into the test bundle.
Which edge the bubble sits against.
The user's own messages, which get the tinted fill.
Whether the entry is drawn as a bubble at all. Activity is a report of
what happened rather than something anyone said, so it is drawn as bare
dimmed text instead — no box — starting in the same column as the
Secretary's words.
Every message is named — "Me" for yours, the persona's name for the
Secretary's — with the time beside it, on a line above the boxes rather
than inside one: a turn split into three boxes has one speaker, and a
name inside the first box reads as a caption on that box alone. The side
already says who spoke, but a thread kept across launches needs to say
*when*, and a name to hang the time on costs nothing.
A turn that ended in an error rather than an answer. Drawn on the
Secretary's side, because that is where an answer would have been, but
in a warning colour and headed as a failure — the app reporting that it
couldn't get an answer, not the persona saying something.
Only the Secretary's answers can be copied. Yours you already have, and
a copy button on every line you typed is clutter on the side of the
thread that never needs it.
The "Working" heading over a line of running commentary.

Only activity earns it. A divider shares activity's plain unattributed
look but is not work in progress, and the heading is a claim about the
app's state, not a style: "Working / New conversation." says something
is running when the whole point of the line is that nothing is.
A divider is drawn like the running commentary — plain, unattributed, no
bubble — because it is the same sort of thing: the app saying where it
is, not the persona saying anything.
Copyable like an answer: the text of a failure is the thing most
worth pasting somewhere — a terminal, a bug report — of anything in
the thread.
The empty lane left on the far side of a bubble, so a message is visibly
tucked against its own edge instead of spanning the panel.

A share of the panel's width, not a constant: the chat is resizable in both
axes, and a fixed gutter is either invisible when the panel is wide or eats
the message when it is narrow. Floored so a very narrow panel still shows
the offset, and capped so a very wide one doesn't squeeze a table into a
column.


## MessageChoices.swift

A question the assistant asked, split into what it said and what you can
pick.

The options are found by an agreed marker rather than by reading the prose,
and that is the whole point. Assistants write lists constantly — three
candidate stacks, three steps they are about to take, three reasons
something failed — and a picker rendered over the wrong one is worse than
no picker at all. Two messages in a single afternoon of testing would have
been misread that way. So the model is asked to mark a real question, and
anything unmarked stays prose.

The marker is a fenced block, which is already invisible to nothing: it has
to be removed before rendering or it shows up as literal text under the
picker.

```choices
Stateless stub — the same fixture every time
Stateful — a POST has to be visible to the next GET
```
The message with the block taken out, ready to render.
What the person can pick, in the order given. Empty when the message
asked nothing.
More than this and a keyboard list stops being quicker than typing.
Extra options are dropped rather than the block rejected, so a
long-winded question still offers its first few.
Splits a message. A message with no block comes back unchanged and with
no options, which is the overwhelmingly common case.
Any closing fence ends it. An unclosed block runs to the end
of the message rather than swallowing the rest as prose —
a reply cut off mid-stream still offers what arrived.

A block with nothing in it isn't a question. Give back the
original so nothing is silently lost from the message.
Options are written as a plain line, but models reach for list markers
out of habit; a leading bullet or number would otherwise be sent back as
part of the answer.
"1. ", "2) " and so on.

The blank lines that surrounded the block are separators, not content.


## MessageMarkdown.swift

Turns a reply into displayable rich text: inline markdown, plus bare URLs
made clickable.

Links arrive from the model, from pages it fetched, and from tool output —
all untrusted. So the link attribute is only ever attached to schemes that
are safe to hand to the browser; anything else is left as plain text the
person can read but not click by accident.
Schemes a link may use. Deliberately short: `file:` would open local
content, and custom schemes can drive other apps, neither of which
should be one click away from a sentence the model wrote.
Inline markdown only — `**bold**`, `` `code` ``, `[label](url)` — so a
stray character can't restructure the message, and newlines survive.
`[click me](file:///etc/passwd)` renders as text, not as a link.
Most replies contain plain `https://…` rather than markdown links, and
the markdown parser leaves those as text.
An existing link wins: a markdown label shouldn't be re-pointed at
whatever the detector reads out of its own text.


## MessageParts.swift

One thing the thread shows for a reply.

A reply that contains a table or a fenced block is not one message any more:
the block leaves the bubble and arrives as its own message underneath, the
way a chat app sends an attachment separately. Boxes were being drawn inside
boxes, and a table already has a border, a background and its own sideways
scroll — a bubble around that is a second frame saying nothing.
Prose, which goes in a bubble. Never empty.
A table or a fenced block, drawn on its own with no bubble around it.
What the copy button on one box puts on the clipboard.

Each box copies itself, so what comes back is what that box shows — not the
whole answer. A table comes back as markdown, which is how it arrived and
what pastes usefully anywhere else; a fenced block comes back as the code
alone, without the fence or the language, because what you want from a shell
command is the command.
A parsed table, written back out as markdown.

The original text isn't kept — the parser hands back rows and cells — so it
is rebuilt rather than remembered. Cells go back verbatim, whatever inline
markdown they carried.
Groups a reply's segments into the messages the thread will show.

Consecutive prose stays together — a paragraph split by nothing shouldn't
arrive as two bubbles — and every table and fenced block becomes its own
message. Prose that is only whitespace is dropped rather than shown as an
empty bubble, which is what a reply that opens with a table would otherwise
produce.


## MessagePartsCache.swift

Remembers how each message was broken into boxes, so a reply arriving token
by token doesn't re-parse the whole conversation on every token.

Why it earns its keep: the transcript is one list, and a token landing in
the last message rebuilds all of it. Splitting one long message into prose,
tables and fenced blocks measured at about 2ms, so a conversation with ten
long messages in it was paying twenty for every token of the eleventh —
which is what the scrolling stutter was made of. Only the message currently
growing actually needs parsing; the ones above it are finished and cannot
have changed.

Keyed by message, and holding the exact text it parsed. Same text, same
answer — `parts(id:text:)` is a memo of a deterministic function, not a
second source of truth, so a stale entry is impossible rather than merely
unlikely: if the text differs by one character it is parsed again.
How many parses were avoided and how many were done. For tests — the
point of this type is a count, and a count is the only way to assert it.
The boxes for one message: markers stripped, pasted rows recognised as
tables, prose grouped.
Drops everything not in the conversation any more — starting a new
conversation, or loading an old one, replaces the lot.
A message with the markers meant for the app rather than the reader taken
out.

The Secretary already strips a loop block from a finished reply, but not
from a failed one, and a reply still streaming has yet to be stripped at all
— neither should put a fenced block on screen.


## MessageTime.swift

The time shown beside a message's name.

A conversation that ran over an afternoon and a conversation that ran over a
week look identical without one, and the thread is kept across launches.
Time alone for anything sent today, date and time otherwise.

A date on every line of a conversation you are having right now is noise;
a bare time on a message from Tuesday is a lie by omission. Which of the
two applies is decided against `now`, passed in rather than read from the
clock so it can be checked.


## ModelBadge.swift

One spelling for "the app was not told, so whatever Claude Code picks will
run". Said in the settings panel, in the chat header, and to the other
characters in `directoryPrompt`; three spellings would read as three
different situations.
The model's name with the maker's dropped — "Claude Opus 5" → "Opus 5".

Every model this app can reach is a Claude, so the word carries no
information and costs six characters in a header row that already holds a
name, a state tag and up to five badges. `CharacterCard.model` has always
documented itself as holding this shorter form; until now the app handed it
a raw model id instead.
What the character is running, for the header beside her name.

Both halves collapse to one word when neither is known, because
"Default | Default" says the same thing twice and reads as two settings
that happen to match rather than as one absence. The separator is the pipe
the owner asked for.


## NewCharacter.swift

What `New Character…` produces.

Two decisions, and both are the kind the charter says must not live in the
view layer: what a new character inherits, and what she is called. A name
picked in the app target is a name no test has ever seen.

A new character cloned from an existing one, named so she is not confusable
with anybody already on the desktop.

The backlog asks for "configuration from the existing Profile", so
everything about who she is comes across — age, gender, personality — and
only the identity is new. Her picture does not: artwork is stored per
profile id and copying the file would leave two characters that are
indistinguishable on screen, which defeats the point of having two.
What a fresh character is called before anyone renames her. The stem the
numbering counts from — "Secretary", "Secretary 2", … — chosen over cloning
the focused character's name now that New Character starts from the default
profile rather than a copy (owner, 2026-08-19).
"Miku" → "Miku 2" → "Miku 3", skipping any number already taken.

Names are how the person tells characters apart in the menu and in the
transcript, so two called the same thing is not a cosmetic problem: the menu
would show two identical rows and neither would say which is which.

The suffix is stripped before counting, so cloning "Miku 2" gives "Miku 3"
rather than "Miku 2 2".
Bounded by the number of names in play plus one, so there is always an
unused candidate in range and the search cannot fail to terminate.
The name without a trailing copy number.


## PlanUsage.swift

How much of the subscription's allowance is gone.

Separate from `SessionUsage`, which counts tokens this conversation moved.
This is the thing that actually stops work: a rate limit on the plan, shared
across every machine and every Claude Code session, not just this app's.

Shaped after the Usage panel in the Claude app, because that is the layout
the user already reads. Two of its sections cannot be filled from here: the
plan's name and the usage-credit figures are not in anything the CLI prints.
Which window a limit belongs to, so the view can group them the way the
Claude app does instead of listing three unrelated bars.
What to call it in the list: "Current session", "All models", "Fable".
0…1.
When the window rolls over, exactly as Claude Code phrased it. Kept
verbatim as the fallback, because it already carries the user's
timezone and re-deriving it risks showing the wrong time.
The same instant, when it could be read. Absent is normal, not a
failure — the weekly per-model line carries no reset at all.
"Resets in 27 min" close up, the CLI's own words otherwise. Relative
only within a day: past that, "in 6 days" is less useful than the
date the CLI already spelled out with a timezone on it.
A recent stretch of work, as Claude Code counts it locally.
"Last 24h", "Last 7d" — the CLI's own wording.
The behaviour lines under it, e.g. "84% of your usage was at >150k
context". Kept verbatim: they explain *why* the bars are where they
are, which is the only reason this section is worth the space.
"Max", "Pro" — the subscription tier, title-cased from what
`claude auth status` reports. Absent if it could not be read.
The CLI's own disclaimer, shown with the counts because it changes what
they mean: they are this machine's sessions, not the account's.
Reads the plan limits out of what `claude -p -- /usage` prints.

Text, not JSON — the CLI has no machine-readable form of this — so the parser
is deliberately forgiving and, more importantly, **silent when it doesn't
recognise something**. A wrong percentage is worse than no percentage: this
number is the one people use to decide whether to keep working, and the
format belongs to another program that can change it in any release.
Matches lines like
`Current session: 25% used · resets Jul 31 at 1:59pm (Asia/Bangkok)`
and `Current week (all models): 3% used · resets Aug 7 at 8:59am (…)`.
Clamped: a plan that has gone over its allowance reports
more than 100, and a bar past its end reads as a bug.
Matches `Last 24h · 532 requests · 11 sessions`.
The "what's contributing" block: how much work went through this machine
recently, and what shape it had.

The notes are the indented lines under each period. `Top skills` and
`Top plugins` are deliberately dropped — they name what the user has been
working on, which is more than a usage gauge needs to put on screen.
Indented, so it belongs to the period above it.
The CLI says "Current week (all models)"; under a "Weekly limits" heading
that reads as a stutter. These names match the Claude app's.
Turns `Jul 31 at 2pm (Asia/Bangkok)` into an instant.

The year is missing from the CLI's wording, so it is taken as the one
that puts the date ahead of now — without that, every reset in January
would read as eleven months past. Both `2pm` and `1:59pm` occur.
Returns nil rather than guessing if anything fails to parse; the caller
falls back to showing the CLI's own words.
A reset slightly in the past is normal — the reading is a
couple of minutes old. Months back means the year was wrong.
Reads the subscription tier out of `claude auth status`, which answers JSON.

Only the tier is taken. That command also reports the account's email and
organisation id, and this app has no reason to hold either.


## ProfileArtwork.swift

Where a profile's picture lives.

One picture per profile. Uploading a separate picture per state was more
work than it was worth — the state already reads from the halo colour, the
badge, and the label under the character — so there is a single slot.

Kept to `URL`s and the filesystem — no `NSImage` — so the resolution rules
are testable without a display, and so the app layer stays the only place
that decodes an image.

Pictures are stored outside the repository, under Application Support, for
the same reason the existing placeholder is: art the user supplies must never
end up committed or distributed with the project.
One directory per profile, keyed by id, so deleting a profile is a single
directory removal and two profiles can't collide on a file name.
The picture to show, absent if there isn't one and the caller should
fall back to the built-in avatar. A profile with no picture is normal, so
this is an ordinary outcome rather than an error.
Stores an uploaded picture. Copied rather than referenced because the user
will eventually move or rename the original, and the character would
silently go blank.

The caller passes PNG bytes: the app layer decodes whatever the user
chose (JPEG, HEIC…) and re-encodes, so the file on disk always matches
its name.
Called when a profile is deleted, so its picture doesn't outlive it.
Nothing there is success: the postcondition the caller wanted already
holds, so it is not a failure to report.
MARK: - Migration

File names written back when pictures were per-state, in the order they
should be preferred. Someone who uploaded only a `thinking` picture and
no default would otherwise open the app to a blank character.
Promotes the first picture from the old per-state layout into the single
picture slot. Copies rather than moves, and leaves the other old files
alone: they're a few KB of dead weight in Application Support, which is a
better trade than deleting something the user uploaded.

Does nothing once a picture exists, so it's safe to call on every launch.
Why a picture could not be written or deleted. Reading is not here: a
missing picture is an `Option`, not an error.


## ProfileLibrary.swift

The profiles the user has, and which one the app is wearing right now.

Holds the list, persists every change, and reports the active profile so the
character art, the chat header, and the system prompt all follow one source.
The callbacks are callbacks rather than observation because a change has
imperative consequences — the Secretary's prompt changes and the character
window has to reload its picture — that must happen once per change, not
during a view update.
Bumped whenever the picture on disk changes. The character's image is
looked up from the filesystem, which SwiftUI can't observe, so this is
what tells the view its picture is stale.
Fired when a profile is added or removed — which, since every profile is
a character on the desktop, means a character arriving or leaving.
Fired when a profile's details change, so her prompt can follow her name
and manner rather than only her label doing so. Carries which one, since
several are live at once.
A profile file that cannot be read starts empty rather than blocking
launch; the seeding below then gives the app someone to be.
First launch, or a file that somehow lost its contents: the built-in
character is seeded so the app always has someone to be.

A saved id that no longer names a profile is treated as unset.
Written out immediately rather than on the first edit, so a fresh
install has a real default profile on disk — Miku, active — instead of
one that only exists in memory until something changes.
Pictures used to have a slot per state. Carry whichever one the user
had over to the single slot, so nobody loses their character.
Deleting the last profile is not offered: the app has to be someone.
MARK: - Changes

Which profile a newly created character is cloned from, and which one
the app falls back to. It stopped meaning "the one you can see" when
every profile became a character on the desktop.
Adds and switches to it, because creating a profile you then have to go
and select is a step nobody wants.
Edits in place. Renaming the active profile is a live change too — the
name in the transcript and the prompt both follow it.
Removes the profile and its picture. Refuses the last one.
MARK: - Picture

Copies a chosen image in and reports the change, so the character reloads
without waiting for the next state transition.
No callback: the character view reads `artworkRevision`, so
bumping it is what redraws her.
The active profile's picture, absent when the built-in avatar should be
used instead.
One particular character's picture. Every character on the desktop draws
her own, so the active one is no longer the only one that has to be
findable.
The profile with this id, falling back to the active one so a character
whose profile was deleted out from under her still has somebody to be
until her window is taken down.
A failed write is deliberately not surfaced: profiles are cosmetic, every
caller is a UI action already committed in memory, and there is nothing
useful to say mid-gesture. Discarded explicitly so it reads as a decision
rather than an oversight — unlike the project registry, where a failed
write must not be silent and `add`/`grant` return their outcome.


## ProfileStore.swift

The saved profile list plus which one is active.

Not `Codable` — `Option` cannot be. `ProfileSelectionDTO` is the on-disk
shape and keeps the same JSON keys, so existing `profiles.json` files load
unchanged.
MARK: - Persistence edge

Why the profile list could not be read or written.
Persistence boundary, so tests never touch the user's real Application
Support directory.
Stores profiles as JSON beside the project registry. Pictures are not in
here — they live as files under `ProfileArtwork`, keyed by profile id.


## ProjectMemory.swift

What a character remembers about a project, and where it is kept.

**The store already exists and is already being read.** Verified against
Claude Code 2.1.220 on 2026-08-14: a `claude -p` started with this app's
exact flag set, with the working directory set to a registered project,
loads that project's `CLAUDE.md` *and*
`~/.claude/projects/<slug>/memory/MEMORY.md` into its context without being
asked. So the reading half of "give the app access to the project's memory"
was true the moment Sprint 5 pointed the backend at a project folder — what
was missing is the other half: nothing the character learned ever got
written back.

That is why this writes into the Claude Code memory directory rather than
into Application Support beside the conversations. A second store would have
to be hand-injected into `--append-system-prompt` while the character went
on reading a *different* memory from the same conceptual place, and the
person's own terminal `claude` would see one and not the other. One store,
read by both.

The consequence is stated rather than hidden: what a character remembers
here is also what the person's terminal sessions in that project will read.
That is the feature — and it is why writing asks first.

MARK: - Where Claude Code keeps a project's memory

The directory name Claude Code derives from a working directory.

**Measured, not guessed.** Every character outside `[A-Za-z0-9-]` becomes a
dash, one dash per UTF-16 code unit, and case is kept. Two observations pin
the parts that no reading of the shape would give you:

- `/Users/Olarn/…/A_b.c d,e-ก่ะZ9` → `…-A-b-c-d-e----Z9`. The three Thai
  scalars produce three dashes, so it is not per grapheme cluster — `ก่` is
  one grapheme and would have produced one.
- `/Users/Olarn/…/em🎨x` → `…-em--x`. One emoji produces *two* dashes, so it
  is not per Unicode scalar either. UTF-16 code units is the only unit that
  gives both answers, which is what a JavaScript `String.replace` over a
  non-`u` regex does.

Getting this wrong is silent: memory would be written to a directory that
nothing ever reads.

Symlinks resolved the way the shell resolves them: `/tmp` is `-private-tmp`
on disk.

`realpath(3)` and not Foundation. Both `standardizedFileURL` and
`resolvingSymlinksInPath` hand back `/tmp` — the second resolves the link
and then strips the leading `/private` again for tidiness, which is exactly
the component the directory name is built from. `Project.normalize` is not
reused for the same reason and one more: it answers "are these the same
project", a laxer question than "which directory did Claude Code name".

A path that does not exist cannot be resolved, so it is used as given —
standardised, which is all that can honestly be done with it. Every real
project is a directory that exists.
- Parameter home: the user's home directory, passed in rather than read, so
  the function is the same function on every machine and in every test.
MARK: - One thing remembered

A single fact about a project, as it will be filed.

One file per fact rather than one long note, because that is the shape the
recall mechanism was built for: only `MEMORY.md` is loaded into context
automatically, and it is the one-line pointers in it that decide which files
get opened. A single growing file would arrive as one pointer that is either
always relevant or never.
One line, and the thing the index is scanned for.
The fact itself. May be empty, in which case the title *is* the fact.
The file this note is written to, derived from the title so a fact
recorded twice overwrites rather than accumulating near-duplicates.
Frontmatter plus the fact, in the format the memory directory already
holds — `type: project`, because that is what every one of these is.
The pointer in `MEMORY.md`. This line is the whole reachability of the
note: a file with no line here is a file nothing will ever look at.
The first sentence of the fact, short enough to sit on one line of an
index that is read in full every session.
A kebab-case name for a title, in the ASCII range the existing files use.

Non-ASCII is dropped rather than transliterated, so a title with no ASCII in
it has no stem to make a name from. **The fallback is a fingerprint of the
title, not a fixed word.** A fixed word was what shipped first, and driving
it found the hole: the owner writes in Thai, so every all-Thai fact would
have been filed as `project-note.md` and each one would have silently
replaced the last — with the index line replaced alongside it, so nothing
would even look broken. The fingerprint keeps re-recording the *same* title
idempotent, which is the property the index depends on, while two different
titles stay two different files.

The title itself still carries the meaning: it is in the frontmatter, in the
index line, and on screen. Only the file name is ASCII.

MARK: - The index

`MEMORY.md` with this note's pointer in it, replacing any line that already
points at the same file.

Replacing rather than appending is what makes recording the same fact twice
idempotent — the note file is overwritten by name, and without this the
index would grow a second line pointing at the same overwritten file.
MARK: - The block

The assistant asking for something to be kept.

```remember
The build script must run from code/, not the repo root
package-app.sh deletes every other AISecretary.app in the repo,
so running it from a worktree leaves code/ with no build at all.
```

Marked, never inferred, for the reason every block here is marked: a model
writes "I'll remember that" constantly, and a reply that merely says so must
not write a file into the person's Claude Code memory — where their own
terminal sessions will read it back for months.

First line is the title, the rest is the fact. `FencedBlock.split` already
drops blank lines and trims each one, so a blank separator cannot be relied
on and is not asked for.
MARK: - What is said about it

The card's one-line summary of what will be written where.

**No project name in it.** The sentence it lands in already ends with "in
\(project)", and the first drive of this produced "…for my-mcp-server, in
your Claude Code memory in my-mcp-server?" — the name twice in one question.

It does say *outside the project folder*. That began as a correction to the
card's subtitle, which read "Writes files in the project" back when this
shared `.localWrite` with every other write; the class was split and
`.projectMemoryWrite` now says it too. Kept because the sentence is what the
person reads first, and saying where a write lands twice is cheap next to
their believing it lands in the project.
One decision is pending at a time, and something else got there first.

Said rather than swallowed, like every other refusal here. Dropping it in
silence would leave her believing it was kept — the same failure the write
error is announced for, and rare enough that nobody would ever find it by
using the app.
Refused before it is written, when the fact itself reads as an instruction.

This is the one thing memory adds that no other block does: text written by
a model is re-read as context on every later turn, by this app *and* by the
person's own terminal. A line that says "ignore previous instructions" is
therefore not a note, it is a standing order, and `instructionRisks` already
knows the shapes.
Told to the character only while a project is open, because with none open
there is no project for a fact to be about — the scratch folder is where she
stands when the person chose nothing, and memory accumulating under it would
be memory filed against a project nobody picked.


## ProjectMemoryStore.swift

Writing a note into the Claude Code memory directory for a project.

Everything that decides anything is in `ProjectMemory.swift`; this only
touches the disk. It is a value with a `home` rather than a reader of
`FileManager.default.homeDirectory`, so a test writes into a temporary
directory and asserts the bytes, and so the pure half never learns where
home is.

**The app writes, not the model.** That is what keeps this from widening any
tool grant: the memory directory is outside every registered project and is
never passed to `--add-dir`, so nothing the backend can reach has changed.
The character asks with a ```remember block; the app is what puts bytes on
disk, after the person has said yes.
The note file and the index line, both, or a reason.

Both or neither is not achievable without a transaction the filesystem
does not offer, so the order is chosen instead: the note file first, the
index second. A note with no index line is invisible and harmless; an
index line pointing at a file that was never written is a dangling
pointer in the one document that is read every session.


## RunningSubagent.swift

A sub-agent that is running now, and when it last said anything.

The pair exists because neither half answers the question on its own: the
task says *what* is happening, the timestamp says whether it is still
happening at all. Keeping them together means the header cannot show a live
description beside a stale liveness, which is the failure this replaces —
working and dead looked identical.
Stamped from the last event that mentioned this task, not from when it
started: the whole point is elapsed silence.
A new reading of the same sub-agent. `-ing` and returning a value rather
than mutating, per the domain rules.
How it looks from outside right now. `now` last and defaulted, so tests
pin it and production never types one.
What the header says about it. In here rather than in the view, because
it is a decision and `AISecretaryApp` is invisible to coverage.
One line for the header: what it is doing, and whether it is still answering.

**Never says it failed.** Nothing on this side can know that — a sub-agent
running one slow tool call looks exactly like one whose process died, and the
only honest thing to report is how long it has been since it last said
anything. Wording that guessed would be wrong about half the time and would
be believed every time.

The tool name is worth carrying: "quiet" next to `Bash` reads as a long
command, which is the common case and stops the silence looking like a fault.


## SaveFileBlock.swift

A file the assistant made and is offering to hand over.

Work done without a project open happens in the scratch folder, which lives
under Application Support — a path nobody browses to. Before this the
spreadsheet she had just built was, from the person's side, nowhere: the
answer said "I've made the file" and there was no way to get it.

Same shape as `LoopBlock`, `SkillInstallBlock` and `MessageChoices`, for the
same reason: "I've written that up for you" is a sentence the model produces
constantly, and a Save button that appeared whenever it did would be a
button for a file that often doesn't exist. The offer is a marker or it is
prose.

```save-file
report.xlsx
```
The message with the block taken out, ready to render.
The names it offered, in the order written, already capped.
How many files one block may offer.

Not a technical limit — each file gets its own row and its own save
panel, so nothing breaks at fifty. It is there because the card is a
thing the person reads, and a turn that offers fifty files has gone
wrong in a way that a scrolling card would hide rather than show.
Splits a message. Anything without a block comes back untouched, which
is nearly every message.
One file on the card: what it is called, where it really is, and how big.
The resolved location is the identity — two rows for one file would be
two buttons that do the same thing.
What the card calls it, and what the save panel is pre-filled with.
Why a name in the block is not something to offer.
Turns one name from the block into a file that may be offered — or refuses.

**This is the security half of the feature, and the reason it is a function
with tests rather than a few lines in the view.** The name is written by the
model, and the button it produces copies a file wherever the person points
it. `../../.ssh/id_rsa`, or a plain `/etc/passwd`, must not become a
friendly Save button — so the name is resolved against the scratch folder
and has to land inside it.

Symlinks are resolved on both sides before the comparison, for two separate
reasons: a link written *into* the scratch folder would otherwise be a legal
path to anywhere, and the scratch folder's own path can contain a link that
makes a perfectly contained file look foreign (`/var` is a link to
`/private/var` on every Mac).

- Parameters:
  - resolveSymlinks: injected so the containment rule can be tested without
    making real links on disk; production passes the Foundation one.
  - size: the file's length, absent when there is no file. Existence and
    size are one question here — a card that offers something already gone
    is a button that fails when pressed.
Refused here rather than left to the containment check below, which would
accept it for the wrong reason: `appendingPathComponent("/etc/passwd")`
quietly produces `…/scratch/etc/passwd`, so an absolute name comes back as
"no such file" — safe, but it reads as though the path was searched, and
the next person to touch this would have no idea the rule was accidental.
The trailing separator matters: without it "/scratchings/x" reads as
being inside "/scratch".
Every offer in one block that survives the rules above.

The refusals are dropped rather than reported: the person did not write the
block and can do nothing about a bad name in it, so the only useful outcome
is the files that are really there. A block where nothing survives leaves no
card at all.
`fold`, because Bow's `Either` has no `toOptional` — only `Option` does.


## SecretaryProfile.swift

Who the assistant is: the name shown in the conversation, and the character
the model is asked to write as.

The user can have several of these and switch between them, so it carries an
`id` and is `Codable` — the pictures live on disk beside it, keyed by the
same id (see `ProfileStore`).
Male and female are offered as buttons because they're the common case;
anything else is free text rather than a short list nobody fits.
What the user sees in the picker.
Either a life stage or an exact age — the charter allows both, and an
exact age still implies a stage, so one derives from the other.
Used when the gender doesn't supply a noun of its own.
An exact age is bucketed rather than described on its own, so the
prompt reads the same whichever way it was entered.
Only present when the user gave a number; the prompt mentions it then.
What an unset or unusable personality falls back to, as specified.
Free text — "professional", "ขี้เล่น ร่าเริง", anything. Blank means the
default; it is never interpreted here, only passed to the model as the
character to write as, which the prompt then bounds.

Called `style` until 0.6.126, when it was widened from a register hint to
an actual character and the name stopped matching the job. Old profile
files still say `style`; see `init(from:)`.
MARK: - Codable

What the field was called on disk before the rename.
Reads either spelling, so renaming the property does not throw away every
profile the user has.

This matters more than it looks: `ProfileStore.load()` returns an empty
selection on any decode failure, and `ProfileLibrary` treats empty as a
first launch and seeds Miku. A missing key would therefore not surface as
an error — it would silently replace the user's profiles with the
built-in one. New files are written with `personality`; old ones keep
working until they are next saved.
The character shipped with the app, matching the placeholder artwork.
A fixed id so the built-in profile stays the same object across launches
rather than multiplying every time the app starts.
The personality actually used: whitespace-only text is treated as unset.
Name with the blank case handled, so an empty field never renders an
anonymous speaker label in the transcript.
"a teenage girl", "a man", "a teenager, nonbinary" — the phrase that
follows the name in the prompt.
How who she is has to show up in languages that inflect for it.

The descriptor above says "a teenage girl" — in English, where nothing
downstream of that changes. Thai marks the speaker's gender in every
polite sentence, and the model was left to infer the connection: Miku,
set female, closed her replies with **ครับ** for weeks while อาเนีย, also
female, said **ค่ะ**. Nothing was choosing; ครับ is simply where a model
lands when no one says otherwise.

So the consequence is spelled out rather than implied. Age is in here
too, because Thai first-person pronouns are not only gendered — a small
child says หนู, and a six-year-old saying ดิฉัน reads as a costume.
Character notes for the system prompt.

The personality is the user's own words and is granted as *character*,
not as a register dial. It used to be clamped — "take that as register
only — how formal or casual to sound", followed by "keep all of this in
the tone, not in extra words" — and the result was that every profile
sounded identical: "ขี้เล่น ร่าเริง ซึนเดเระ" and "professional" both
produced the same flat two-line answer, which is what the owner
reported. A description nobody can hear is the same as no description,
so the grant is now wide enough to be audible in a one-sentence reply.

Two things still bound it, and both are fixed text that outranks
whatever the user typed:

- Usefulness. Character changes *how* something is said, never whether
  it is true or how much work gets done. Lead with the answer stays.
- The romantic/sexual prohibition. It lives here rather than in a filter
  over the text box because a keyword blocklist over free Thai and
  English would both miss the real cases and reject innocent ones,
  whereas the prompt is where the personality takes effect at all.


## SecretaryPrompts.swift

The words the assistant is given, out of `Secretary` and into functions of
their inputs.

`Secretary` remains the one place that knows *which* state feeds each
prompt — its computed properties gather the state and call these. What
moved here is everything below that line: the text itself, and the rules
for assembling it, which take plain values and can be checked without
constructing a `Secretary` at all.
What language to answer in.

It was one clause in the middle of a paragraph, on one of the two prompt
paths, and replies to Thai kept coming back part English. Three things
were wrong and all three are addressed here: the rule was missing
entirely from the chat-only prompt; the profile said a personality
written in another language "still describes you when you answer in
English", which is an instruction to answer in English; and the rule
never said what it wanted, so "answer in Thai" read as "translate
everything", which nobody wants for `git rebase` or a stack trace.

Short lines are called out because that is where it actually slips — the
answer comes back in Thai and the "Done —" in front of it doesn't.
What to do when the person supplies the thing that was missing.

From a real conversation: asked for a ratebook and to pin it, the
assistant said the folder was empty; told "from the project's MCP", it
tried the server, found it worked, and reported a search for a different
car in a different year — never answering the question or pinning
anything. It had read the second message as a fresh instruction rather
than as the missing piece of the first.
How the assistant is asked to pull something out of the chat. A marker
again, and for the same reason: replies are full of tables and lists, and
guessing which of them to pin would open windows nobody asked for.
How the assistant asks for the timer. Written as a block rather than
left to inference, because "keep an eye on this" in the middle of a
conversation must not be able to start something that talks on its own.
Watching is the app's job, but noticing that they asked for it is the
assistant's. It used to only be able to point at the command: asked to
keep an eye on a folder it replied "พิมพ์คำสั่งนี้เองนะคะ: /watch ." —
having understood the request completely. Telling someone to type what
you already understood is the opposite of a secretary.
Same reasoning as `watch`, and safe for the same reason the typed
command is: this only reaches the confirmation card, where the person
reads every step before anything runs.
How the assistant asks for a file instead of asking the person to type
out what's in it.

The button matters more than it looks. The alternative is "paste the
rows here", which is the work the person came to hand over, and "give me
the path", which nobody knows off the top of their head and which a
sandboxed build could not open anyway.
Only in the agent prompt: without Claude Code there is nothing to install
into, and nothing that would use the skill afterwards.
How the assistant hands over a file she has just made.

Only in the agent prompt: chat on its own cannot write a file, so
offering one there could only ever be an offer of something that isn't
there. (The charter records the opposite mistake — a block described in
one prompt while the backend in use read the other, so the feature was
silently missing the whole time. This one is genuinely agent-only.)
The half that is true whichever backend answered — every slash command
is handled here in the app, before anything is sent anywhere.
The typed commands, which exist only on the fallback path.

A bare chat model cannot open a folder, so there it really does matter
that the person knows to type "list files in …". Shown nowhere else —
see `helpText(workspaceTools:)`.
What the assistant tells you it can do — which now depends on which
backend answered.

Two texts because there are two behaviours. Sprint 16 sends every
message straight to the agent when the backend has its own tools, so on
that path "type status in AI-Secretary" describes a keyword rule that no
longer runs: the words go to the model, which looks for itself. Help
that teaches a command whose behaviour does not match the teaching is
worse than no help, because the person believes the phrasing matters and
blames themselves when it doesn't.
What the assistant can and can't see of the web, and — when it can't —
the thing to offer instead.

The off case is the point. `WebFetch` succeeds on a login-walled page
and returns the sign-in form, so without being told, the model reads
that and reports it as the content. It has to know the difference
between "I couldn't load this" and "I loaded the wrong thing", and that
there is a way out the user can switch on.
Kept in step with the allowlist actually passed to the backend. Telling
the model it is read-only after the user widened permissions would stop
it retrying the very thing they just approved.

**It must never tell the model to give up instead of trying.** This note
used to end "writing or running commands will be refused", and the model did
the obedient thing: it stopped before the tool call and answered "I don't
have write permission". No tool call means no refusal, no refusal means
`offerToWiden` has nothing to offer, and no card is ever put in front of
anybody — so the work simply stopped, for ever, with a polite sentence.
That is the owner's Sprint 21.2 report, driven and reproduced on 2026-08-20:
commanded to write a file, every character said it had no permission, and
the ones that eventually succeeded were the ones standing in a project with
a write grant already on record, where the refusal happens for real and is
widened silently.

The refusal *is* the mechanism. Claude Code has no mid-turn approval, so the
only way the person is ever asked is: attempt, be refused, show the card,
retry. A note that stops the attempt removes the only step that can start it.
For a backend that has its own file tools and is already running inside
the project directory.

The chat-only prompt below must never be used here. It tells the model it
"cannot run commands yourself" and should tell the user what to type —
true of a bare API call, catastrophic for an agent holding Read and Grep.
It produced exactly that: asked to summarise a project, the assistant
asked the user to paste the contents and to type `list files in <name>`.

The static instructions plus whatever the user has actually registered.
Without the project list the model denies knowing about a project the
user can plainly see in the UI. Names only — paths, tool allowlists and
approval state stay out of chat history.


## SessionUsage.swift

What one turn cost, and what the session has cost so far.

The four token counts are kept apart rather than summed into one number,
because they are priced differently and behave differently: a cache read is
most of the traffic on a long conversation and a fraction of the price, while
a cache write is the expensive one. Reporting only `input + output` — which
is what this app did until now — understates a real turn by orders of
magnitude: measured at 2 in / 5 out against 11,768 written and 24,436 read.
Tokens written into the prompt cache. Charged at a premium.
Tokens served from the prompt cache. Charged at a discount.
What the same traffic would cost on the API. Not money charged to a
subscription — see `costNote`.
The model's context window, when the backend reported one.
Tokens the *last* turn put into the context window, which is what decides
how much room is left — unlike the totals, this one does not accumulate.
Everything that crossed the wire, in both directions.
How full the model's context window was on the last turn, 0…1.

Everything the model had to read counts — fresh input plus whatever came
from the cache — since the cache is a billing arrangement, not a smaller
prompt.
A new total including this turn. The window is carried forward from
whichever turn last reported one, so a turn that omits it doesn't erase it.
Formatting, kept next to the numbers so the chat command and the panel can
never disagree about what a figure means.
Thousands separators, because six-digit token counts are unreadable
without them.
The line that must always accompany a dollar figure here. Claude Code
reports `total_cost_usd` whether or not anyone is paying per token, so on
a subscription the number is a comparison, not a charge — and a bare
dollar amount in a chat window reads as a bill.
"18 min", "3 hr", "2 days" — the gap to a reset, in one unit. Rounded up,
so a window with 30 seconds left says "1 min" rather than "0 min".
"just now", "3 min ago" — how old a reading is, for the line under it.
The whole summary, as shown by `/usage`.
Everybody's usage added up, for the one Token Usage window the app has.

The window is at the root of the menu because the figures are the machine's
bill, not one character's — but each character keeps her own session, so the
total has to be made rather than read.

Two fields deliberately do not sum:

- **`contextWindow`** is a property of the model, not a quantity. Adding two
  200k windows to get 400k would say the context is twice as big as any
  character actually has. The largest reported one is kept, so "how full is
  the context" is still answered against a real window.
- **`lastTurnContextTokens`** is how full one session's context is right
  now, and the fullest is the one worth knowing about — summing would report
  a session nobody is in.


## SkillDiscovery.swift

Where a skill was found. Shown next to the name so two skills with the
same folder name in different scopes aren't mistaken for one.
A standalone folder under `~/.claude/skills`.
A standalone folder under a registered project's `.claude/skills`.
Provided by an installed, enabled plugin — `id` is the plugin's own
identifier, `plugin@marketplace`, exactly as it appears as a key in
`~/.claude/settings.json`'s `enabledPlugins`.
One installed Claude Code skill, as read from its `SKILL.md` frontmatter.

`id` is stable and unique within a scope — the folder name for a
standalone skill, or `plugin@marketplace:folder name` for a plugin one,
since two enabled plugins could otherwise both contribute a folder called
the same thing — while `name`/`summary` are what a person reads, falling
back to the folder name when frontmatter is missing or unparsable, since a
skill with a broken header should still show up rather than vanish.
What to tell the model about the skills someone checked in the Skills panel.

Two things this had wrong, and both came out as "I checked it and it never
gets used".

**It only ever subtracted.** The note used to say "only use these; don't
invoke any other" — which turns other skills off and does nothing at all to
turn the checked ones on. Whether a skill loads is decided inside Claude
Code by matching the request against the skill's own description, and
checking a box does not change that description. So the box could lose you
skills and never gain you one. It now asks for them to be preferred, which
is what checking something is understood to mean.

**It sent names only.** The panel shows each description; the prompt didn't
pass it on, leaving the model a bare `superpowers:brainstorming` with no way
to tell whether it fitted. The descriptions are the part it can actually
match against, so they go too.

What this still can't do is force a load — that happens in the child
process, out of reach. This makes the match likelier; naming a skill in the
message is still the only certainty.

Long enough to tell skills apart, short enough that checking twenty of them
doesn't quietly become the largest thing in the request.
Finds installed skills by reading directories directly, the same way
Claude Code itself resolves them — there is no `claude` subcommand that
lists skills (only `claude plugin list`, which only shows plugins
installed through the marketplace, not the skill folders sitting directly
under `~/.claude/skills`, and says nothing about the skills inside a
plugin either).
`~/.claude/skills`, `.claude/skills` under each given project path,
and the skills bundled inside every plugin `~/.claude/settings.json`
currently has enabled. A directory that doesn't exist yields no
entries rather than an error — most projects simply have none.
Plugins are read from `enabledPlugins` in `settings.json` — a disabled
or never-installed plugin's cached files can still sit on disk, and
only the enabled ones are actually available in a session.

A plugin's skills can live in more than one layout depending on how it
was installed (`plugins/cache/<marketplace>/<plugin>/<version>/skills`
for one installed through the marketplace registry, or directly under
`plugins/marketplaces/<marketplace>/skills` for a single-plugin
marketplace cloned straight from its repo) — so each candidate root is
tried in turn and the first one that actually has skills wins, rather
than merging all of them, which would also pull in every *other*
plugin a shared marketplace happens to host.
Points at the marketplace's own `skills/` folder directly,
not the marketplace root — a single-plugin marketplace
keeps its skills there, but the root also holds a
`plugins/` folder for any *other* plugins that marketplace
hosts, which must stay out of reach here.
Depth-bounded rather than a plain recursive walk, so a plugin whose
skills sit several directories deep (`<plugin>/<version>/skills/<name>`)
is still found, without the search wandering off into unrelated
content a real plugin checkout also carries (assets, evals, docs).
Just enough YAML to read `name:`/`description:` out of a `---` header —
SKILL.md frontmatter is never more than flat string keys, so a real
parser would be answering a question nobody's asking.


## SkillInstallBlock.swift

A plugin the assistant says it needs and is asking to install.

Same shape as `LoopBlock` and `MessageChoices`, for the same reason: a
sentence that *sounds* like "I could do this if I had the pptx skill" must
not put an install button on screen. The request is a marker or it is prose.

```install-skill
canva
```

Only the name goes in the block. Where it comes from is not the assistant's
to choose — see `validSkillPluginName` — and what it costs is on the card.
The message with the block taken out, ready to render.
The plugin it asked for, if it asked for one it is allowed to name.
Splits a message. Anything without a block comes back untouched, which
is nearly every message.

One plugin per turn on purpose: the card names what is about to be
installed, and a list makes "yes" mean more than the person read.


## SpeakerLabel.swift

The name above a message in the transcript.

Two rules, and both of them are the kind that quietly rot if they live in a
view: the user is always "Me" whatever profile is active, and the assistant
is whoever it was *when the line was written* — see `TranscriptEntry
.speakerName` for why that is stored rather than looked up.

- Parameters:
  - isMine: whether this is the user's own turn.
  - speakerName: the name recorded on the entry. Blank for entries written
    before names were recorded, and for anything that somehow reaches here
    without one; those fall back rather than rendering an anonymous line.


## StandingGrantStore.swift

Where the grants that outlive a conversation are kept.

Failures come back as values rather than thrown errors, for the same reason
the project registry's do: loading happens in an initialiser, and an
initialiser is no place to unwind from.
The app's own file, under Application Support, one per character.

**Deliberately not the project's Claude Code memory** (owner's decision,
2026-08-17), which the backlog item could have been read as asking for.
That directory is loaded into the model's context on every turn and is read
by the person's own terminal `claude` — so a grant written there would be
instruction-shaped text the model can see, and a permission this app gave
itself would silently apply outside this app. Here it is the app's own
record: invisible to the model, and deletable by deleting the file.

Per character for the same reason the project registry is: a grant is one
character's answer about one of her projects, and sharing the file would
mean approving something for Miku approves it for everyone.
Nowhere, for tests and for a character whose store hasn't been built yet.
MARK: - Persistence edge


## StatusMenu.swift

The status bar menu, as a value.

`AISecretaryApp` is never linked into the test bundle, so a menu built by
hand out of `NSMenuItem`s is a hundred-odd lines that no test has ever
executed — and Sprint 13 turns those hundred lines into a tree three levels
deep with a branch per character. The rule the charter draws for exactly
this case is that the app applies answers rather than computing them, so
the shape lives here, where it can be asserted row by row, and
`StatusBarController` becomes a renderer.

Plain Swift, no Bow: this crosses into the app target, which cannot import
`FunctionalCore` without Bow's `State` shadowing SwiftUI's — the same reason
`ConversationMenuRow` next door is plain.

MARK: - What the menu is built from

One pinned pane, reduced to what a menu row needs. `InfoWindowSpec` carries
its body and timestamp too, and a menu that receives those invites itself to
start deciding things about them.
Everything the menu needs to know about one character.
MARK: - What the menu is

What a row does when it is clicked. A closed set, so the renderer cannot
invent an action and the tests can name every one that exists.
Everyone off the desktop, or everyone back on.
The command window on or off screen — hidden, not torn down, so the
sessions it started keep running.
A keystroke the row advertises. Command-only, because every shortcut this
menu has ever carried is.
Absent for a label or a submenu parent — rows that are not clicked.
Drawn with a tick. Marks the conversation you are already in; without it
reopening it is an invisible no-op that reads as the menu being broken.
MARK: - The menu

The whole tree, from `menu.pdf`.

```text
AI Secretary 0.13.x
├ Miku ▸ ──────── Show/Hide Character
├ Anya ▸          New chat
├ New Character…  Chat History ▸
├ Token Usage     ─────────
├ About           Pinned Messages ▸
└ Quit
```

Everything about a conversation hangs off the character it belongs to; only
the three rows that are about the app stay at the root.

The characters used to sit one level further in, under a "Characters" row.
That row held nothing of its own — it existed to be hovered past — so the
owner asked for it gone and the characters moved up into its place.
A label, not a row to click: it answers "which version am I running"
without opening anything.
Asked for between New Character and Token Usage, with a line on each
side: commanding everyone at once is neither one character's business
nor the app's bookkeeping, so it stands alone.
Clicking her name shows or hides her, which is the thing anyone
wants from a character row often enough to be worth a click
rather than a hover and a second click. Her submenu is still
there for everything else.
The rule above it is "one row per character"; this one is about all
of them at once, so it is not another name in that list and the line
says so. It goes inside the same condition, because a separator with
nothing under it is a line drawn for no reason.
⌘H is advertised here because this is what it does: the whole desktop,
since Sprint 13-2. It used to be advertised on each character's own
row, which was true before that and quietly false after — and stayed
false long enough that ⌘H really did hide one character again, for a
different reason (see `handlesHideLocally`).
Always after them, so its position doesn't move as characters come
and go.
One row for both directions, and which one it is comes from the desktop
rather than from a remembered state.

**Anyone still on screen means the row hides.** A count — "most of them are
away, so this is Show" — would leave a visible character behind on a row
that said Hide, and the one you can see is the one you wanted gone. Only
when there is nobody left does it turn around and offer to bring them back.
No shortcut on this row: ⌘H takes the whole desktop, and it is
advertised on the row that does that. Hiding one character is a click,
here or on her name.
Everything above is the conversation; below is what was pulled out
of one. The line is where that changes.
Clicking a pane brings it forward. Deleting one lives on its own close
button and on Clear All: a row whose whole job is "show me this" should not
need a submenu in front of it, and a Delete one pixel from Show is a
mis-click waiting to throw away the thing you meant to look at.
Always last, in this order, so their positions don't move as panes
come and go.


## Theme.swift

Which set of colours the windows are painted with.

Three, not a full theme engine: the charter asks for a small MVP, and the
problem being solved is one specific failure — a bright desktop showing
through the panel — not "I want to pick colours".

The three are the two palettes plus "follow the system", which is the whole
choice there is to make once the surfaces are opaque. A fourth, `contrast`
— dark with a heavier border — shipped in 0.10.197 and was taken out in
0.10.198 at the owner's request. A stored `"contrast"` no longer decodes and
falls back to `system`, which is the same handling an unknown value gets.
Follow the system's light/dark setting.
Light whatever the system says.
Dark whatever the system says. For a light desktop the user doesn't
want to change.
What the row in Settings says under the name.
A colour as three components, not a `SwiftUI.Color`.

Components rather than a platform type for one reason: a test has to be able
to do arithmetic on it. `Color` can be compared but not measured, and the
thing worth checking about a palette is whether the text stands off its
background by enough — which is a number, computed from the components.
WCAG relative luminance, on the sRGB components as stored.
How far apart two colours are, 1 (identical) to 21 (black on white).

The usual floor for body text is 4.5. `Palette.contrastFloor` is what this
app holds itself to, and `ThemeTests` checks every pair against it.
Every colour the windows use, named by the job it does rather than by what
it looks like.

**Opaque grounds, deliberately.** The panel used to be `.regularMaterial`,
which samples the desktop behind it: on a bright wallpaper the surface
lightened, and since every bubble was a low-opacity tint *over that surface*
the whole low-contrast layer — muted text, the bubble's edge, the small
chips — went with it. Whether the app was readable depended on the user's
wallpaper, which the app does not control. Grounds here are solid, so it
no longer does.

**Roles, not literals.** These live in `SecretaryCore` rather than in the
views for the reason `MessageBubbleStyle` does: `AISecretaryApp` is never
linked into the test bundle, so a colour decided there cannot be checked.
The view applies a role; it does not choose a value.
The contrast every text colour must reach against every ground it can
be drawn on. WCAG AA for body text.
Grounds — surfaces something is drawn on top of.

The window itself.
Small raised surfaces: the message box, chips, inline code.
The user's own messages.
The Secretary's messages.
A tinted card or pill that means "this is the active/primary thing".
A tinted card or pill that means "careful". Also the failure bubble:
a turn that ended in an error is the same claim in bubble form, and
giving it a fourth near-identical orange would be a distinction the eye
can't make.
"This leaves the machine" — the strongest of the three.
A neutral informational card.
A surface *inside* a bubble — a code block, a table.

It cannot be told apart from its parent by fill alone: `bubbleMine` is a
blue tint, `bubbleTheirs` a grey one, and one neutral cannot stand off
both while staying a quiet surface. So the rule is that a nested surface
is told apart by its **edge**: it always carries the hairline.

Four sites, and every one of them must keep its stroke —
`ChatPanelView.codeBlockView` / `.tableView` and
`MarkdownBodyView`'s two. Two of them shipped without one for an hour;
`nestedFill` against `bubbleMine` is 1.05 in `light` — no boundary at
all without the stroke. `testEveryEdgeIsVisibleAgainstEveryGround` checks
the hairline's *colour* would be visible — it cannot see whether the
stroke is drawn, so that part is on the reader.
Marks — text, icons, and strokes drawn on those grounds.

Timestamps, the running commentary, hints. This is the role the old
translucent background actually broke.
Text and glyphs drawn *on* `accent` used as a solid fill — the selected
footer button. The only role whose job is defined by another role, so
the pair is checked together rather than against the grounds.
Separators and the outline of small controls.
The outline of the speech bubble itself.
Whether the window should ask AppKit for the dark control appearance,
so scrollers, the caret and the text-selection tint match the palette
instead of the system setting.
The grounds, paired with the name a failing test should print.

A list rather than a `switch`: adding a ground is adding an element, and
the contrast test then covers it without being edited.
The marks that carry words. `hairline` and `panelBorder` are not here:
they are edges, and an edge is allowed to be quieter than text.
Used when the system is in light mode and the user hasn't overridden it.
Still opaque — a light window that stays the same white over any
wallpaper is the point, not the absence of light mode.
Every palette that can end up on screen, so a check written once covers
all of them — including any added later.
Which palette to paint with.

Takes the system's setting as an argument rather than reading it, so it is
the same function in a test as in the app.


## TranscriptScrollPin.swift

Whether the transcript should follow new output.

Reading back through a conversation while the assistant is still typing is
a normal thing to do, and being yanked to the bottom mid-sentence makes it
impossible. So the view follows new output only while the reader is already
at the bottom, and starts following again the moment they scroll back down.

The subtlety is that a scrolling view can't tell who moved it, and the two
things that move it look identical from a position alone: the reader
scrolling up, and the content growing under a reader who hasn't moved. Both
push the end of the transcript out of sight.

The first attempt told them apart by time — ignore measurements for a moment
after we scroll ourselves — and that is what the bug turned out to be. A
streamed reply scrolls on every token, each scroll pushed the window out by
another 0.3s, and tokens arrive faster than that, so for the whole length of
a reply no measurement was ever read and following could not be switched
off. Exactly the case the mechanism existed for.

So the two are told apart by *source* instead of by timing, which no rate of
tokens can defeat:

- only a scroll the reader performs can stop it following (`readerScrolledUp`),
- a measured position can only ever start it again (`update`).

Growth therefore cannot unlatch following by construction rather than by
arithmetic, and there is no clock in here at all — every function below
returns the same answer for the same arguments.
Follows by default — a fresh conversation is at the bottom already.
Call for a scroll the reader performed themselves, back towards earlier
messages. They are reading; nothing arriving should move the view.
Call whenever the end of the transcript is measured against the bottom
edge of the view: positive means it sits below the fold.

Re-arms only within `settled` of the fold — the same threshold
`isBehind` uses to call the reader already there, not a wider one of
its own. A wider one used to live here, on the theory that "still
basically at the bottom" ought to be more forgiving than "already
exactly at the bottom". It wasn't a free choice: `readerScrolledUp` is
never allowed to consume the scroll event that reported it (see
`startWatchingScroll`), so the reader's own short scroll up still moves
the content, and the very next call here measures that scroll's own
resulting position — not a later, separate trip back down. A short flick
lands well within any generous slack, so a wide threshold undid it on
the spot, which is why scrolling up sometimes took two or three tries
before it held. A reader who genuinely scrolls back down always
converges on the same near-zero rest position `isBehind` already
trusts — the scroll view has nowhere further to give past its own
bottom — so nothing legitimate is lost by asking for that here too.
The reader did something that means they want to be at the bottom —
sending a message, for instance, which overrides wherever they happened
to be scrolled.
Closer than this to the bottom edge and the end is already where
following would put it, so scrolling again would move nothing — and, by
the same measure, close enough to count as *at* the bottom in the first
place. One number answers both questions now. Two used to: this one,
strict, for "stop nudging it, it's there"; a much wider one for "still
counts as there" when deciding whether to resume following after a
scroll. The wider one existed to forgive a token landing a layout pass
before the scroll that follows it — but `update` only reads that
forgiveness when following is already on, where it changes nothing, and
it was reached on the one path where it did change something: the
reader's own short scroll up, whose resulting position it forgave right
back into following. See `update` for the rest of that story.
Whether the end of the transcript has been pushed below the bottom edge
while we are supposed to be following it — the whole condition for
scrolling back to the end, decided from the measurement itself.

This is what replaced watching the transcript for changes. A change
signature has to be able to name every cause of movement in advance, and
the one that shipped could not: it was the number of messages and the
length of the last one, while the running commentary grows *in place*,
in an entry inserted *above* the reply being written. Neither number
moved, so nothing scrolled, and every step of a tool run pushed the
newest text a line further out of sight.

A position cannot miss a cause. The commentary growing, a viewport that
shrank because an approval card appeared, a font size change, a window
resize — all of them move the end of the content, and this sees them
without knowing which one happened.
Whether a scroll wheel/trackpad event is the reader moving back through the
conversation.

Only upwards counts. Scrolling *down* is either asking for more of what is
arriving or on the way back to the bottom, and neither is a reason to stop
following — while stopping on it would need a second event to undo, at the
moment the reader least expects the view to be stuck.

A free function rather than a method: it is a rule about an event, decided
once, in a target the tests can see. The view only applies the answer.


## VendorChoiceStore.swift

Which maker a character works through, and where its tool is.

Per character rather than per app, like her model and her effort: the panel
that chooses it is her Profile, and two characters on the same desktop may
reasonably run through different makers — one on the user's Claude Code
subscription, one on a local model that costs nothing.
Only meaningful for a maker whose executable the user supplies. Absent
means "look in the usual places", which is what the field being empty
means on screen.
What a character runs through until somebody chooses otherwise.
The default, which deliberately reaches nowhere — a suite that forgot to
override it must not write into the person's own preferences.
Hers, keyed by profile, like the model and effort beside it.
A stored id this build has never heard of reads as the default rather
than as a failure — a settings file written by a later build must not
leave a character unable to work.
Clearing the path removes the key rather than storing an empty string:
"look in the usual places" is a choice, and an empty string would later
read as a path that happens to be blank.


## WatchBlock.swift

The assistant asking the app to watch a path, or to stop watching.

Without this the feature only half worked. Asked to "คอย monitor folder aaa
แล้วบอกชื่อไฟล์ที่เพิ่มมา" the assistant understood the request perfectly
and then told the person to type `/watch .` themselves — the one thing a
secretary shouldn't do with an instruction it already understood.

```watch
aaa
```

Marked rather than inferred, for the reason every other block here is: a
reply that merely mentions keeping an eye on something must not start a
background job. What the marker buys is that the request is unmistakable;
what keeps it safe is unchanged — the path is resolved inside an approved
project, the first watch in a project still meets the permission card, the
start is announced, and the badge stops it in one click.
A bare `stop` stops all of them; naming a path stops that one, now
that several can run together.
The message with the block taken out, ready to render.
`path: docs` reads better in a prompt than a bare `docs`, so the
label is accepted and dropped.

The assistant asking the app to follow a file's instructions.

Safe to let the assistant raise because raising it isn't doing it: this only
gets as far as reading the file and putting the steps on the confirmation
card, which is the same gate a typed `/run` reaches. Nothing runs until the
person reads the steps and presses Start.

```run
deploy.md
```


## WebTask.swift

Working *in* a web app on the person's behalf, rather than reading one.

The difference is the whole reason this file exists. Reading a page is one
question with one answer; working in a web app is a session — the assistant
opens the site, works out what it is, and then may type into it as the
person, inside the browser they are signed into. That is not something to
stumble into because a URL happened to appear in a sentence, so a link
arriving in chat raises a card first and nothing is opened until it is
answered.

Scoped by host, not by URL. Nobody decides one path at a time — approving
a link to a board and then being asked again for the next page of the same
board would train the person to click through the card without reading it,
which is worse than not asking.
The address that was recognised, as typed.
The site the grant covers, lowercased and without `www.`.
The message that carried the link, held so it can run once the card is
answered rather than making the person type it again.
Whether saying yes also connects the browser. Approving one card that
does two things is only acceptable because the second is what makes the
first mean anything — without Chrome the assistant is fetching the page
anonymously, which is a different, weaker thing than the card offers.
What the card says it is about to do.
The site of a URL, as a grant is scoped.

`www.` is dropped because it is not a different site to anyone reading the
card, and lowercased because hosts are case-insensitive while `Set<String>`
is not — a grant for `Example.com` that didn't cover `example.com` would ask
twice for one site.
The first web address in a message, if there is one.

Only `http` and `https`, the same limit link rendering uses: `file:` would
reach the person's disk and a custom scheme hands the click to whatever app
claims it. A bare `www.` prefix counts, because that is how people write
addresses; a bare `example.com` deliberately does not — "check config.json"
and "it's about node.js" would both become sites to ask about.
First match wins, which `orElse` says on its own: once something is
there, later tokens can't replace it. The loop this replaced said the
same thing with a `continue` and a `return` you had to pair up by eye.
One word, if it is an address.
Trailing punctuation belongs to the sentence, not the address.
The sites the person has agreed the assistant may work in, this session.

Session-only, like every other grant that can act rather than read: a list
of sites the app would silently walk back into on the next launch is a
standing permission nobody re-read. Kept as a value so the decision is
something a test can hold and compare.
Named, in the order they will be read in.
What the model is told once a site has been approved.

Three rules, and each one is here because the alternative is a specific
failure. Look before acting, because "what is this app" is the question the
person is really asking and answering it wrong wastes a form submission.
Confirm anything ambiguous, because a guess typed into someone's real
account is not a draft. And treat the page as untrusted, because a web app
the assistant is filling in is exactly where injected text would sit.


## WindowGeometry.swift

Sizing and placement rules that used to live inline in `AISecretaryApp` —
the target the test bundle never links, where a rule can regress without a
single test noticing. Each is a pure function; the view or delegate only
applies the answer. Same reasoning as `placeBubble` and `GripCorner`.

Sized to the content, within reason: a two-row table should not open a
window the height of the screen, and a long one should not try to. The
32pt is breathing room around the hosting view's fitting size.
Cascade, so a second window doesn't land exactly on the first — and the
ninth starts over at the top rather than marching off the screen.
The message box grows with the draft, between one line and the line limit.
One free-resize drag of the chat bubble, measured from where it started.

The edges on the tail's side stay pinned to the character — the tail must
not slide off it just because the window got bigger — so the bubble only
ever grows into the two opposite edges, and the drag follows those: right
and up in the usual position, left when mirrored, down when flipped below
the character.

Everything is captured once, at the start of the drag. Read the layout
fresh on every event instead and a layout that flips mid-drag inverts the
gesture: keep dragging the same way and the box shrinks, which un-flips
it, which grows it again. Measured at the top of the screen, the height
oscillated 909 → 801 → 933 → 777 in four events, the swing widening each
time. Same reason each step is measured from the one fixed starting point
rather than accumulated.
Which way the bubble grows, fixed for the whole drag.
Screen coordinates point up, so this is already "up is taller"
unless the bubble sits below the character and grows downward.
The size the bubble should be with the pointer here.

